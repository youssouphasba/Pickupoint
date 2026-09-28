"""
Service wallet : crédit/débit, distribution des revenus à chaque livraison réussie.
"""
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from pymongo.errors import OperationFailure

from database import db, get_client
from models.wallet import TransactionType

logger = logging.getLogger(__name__)


async def _run_in_transaction(op):
    """Execute op(session) dans une transaction Mongo si disponible (replica set),
    sinon execute sans session (meilleur effort). op est une coroutine acceptant
    une session (ou None) et retournant le resultat final."""
    client = get_client()
    if client is None:
        return await op(None)
    try:
        async with await client.start_session() as session:
            async with session.start_transaction():
                return await op(session)
    except OperationFailure as exc:
        # MongoDB standalone (pas de replica set) — fallback non atomique.
        if "Transaction numbers are only allowed" in str(exc) or "replica set" in str(exc).lower():
            logger.warning("MongoDB non replica-set, wallet en mode non atomique")
            return await op(None)
        raise


def _wallet_id() -> str:
    return f"wlt_{uuid.uuid4().hex[:12]}"


def _tx_id() -> str:
    return f"wtx_{uuid.uuid4().hex[:12]}"


def delivery_commissions_enabled(parcel: dict | None = None, mission: dict | None = None) -> bool:
    merged: dict = {}
    if isinstance(parcel, dict):
        merged.update(parcel)
    if isinstance(mission, dict):
        merged.update(mission)
    raw = merged.get("delivery_commissions_enabled")
    if raw is None:
        return True
    return bool(raw)


COMMISSION_MODES = (
    "home_to_home",
    "home_to_relay",
    "relay_to_home",
    "relay_to_relay",
)


def default_commission_rules() -> dict:
    """Taux par mode. Les valeurs sont des parts du prix total, jamais des montants."""
    return {
        "home_to_home": {"platform_rate": 0.15, "origin_relay_rate": 0.0, "destination_relay_rate": 0.0, "driver_rate": 0.85},
        "home_to_relay": {"platform_rate": 0.15, "origin_relay_rate": 0.0, "destination_relay_rate": 0.15, "driver_rate": 0.70},
        "relay_to_home": {"platform_rate": 0.15, "origin_relay_rate": 0.15, "destination_relay_rate": 0.0, "driver_rate": 0.70},
        "relay_to_relay": {"platform_rate": 0.15, "origin_relay_rate": 0.075, "destination_relay_rate": 0.075, "driver_rate": 0.70},
    }


def normalize_commission_rules(raw: dict | None) -> dict:
    defaults = default_commission_rules()
    if not isinstance(raw, dict):
        return defaults
    normalized = {}
    for mode in COMMISSION_MODES:
        source = raw.get(mode) if isinstance(raw.get(mode), dict) else {}
        values = {
            key: max(float(source.get(key, fallback)), 0.0)
            for key, fallback in defaults[mode].items()
        }
        total = sum(values.values())
        if total <= 0:
            values = defaults[mode].copy()
        else:
            values = {key: round(value / total, 8) for key, value in values.items()}
            values["driver_rate"] = round(1 - sum(value for key, value in values.items() if key != "driver_rate"), 8)
        normalized[mode] = values
    return normalized


def commission_rules_for(source: dict, mode: str) -> dict:
    rules = source.get("commission_rules_snapshot") or source.get("commission_rules")
    if isinstance(rules, dict):
        return normalize_commission_rules(rules).get(mode, default_commission_rules()[mode])
    from config import settings
    legacy = {
        "platform_rate": float(settings.PLATFORM_RATE or 0),
        "origin_relay_rate": 0.0,
        "destination_relay_rate": 0.0,
        "driver_rate": float(settings.DRIVER_RATE or 0),
    }
    if mode == "home_to_home":
        legacy["driver_rate"] += float(settings.RELAY_RATE or 0)
    elif mode == "home_to_relay":
        legacy["destination_relay_rate"] = float(settings.RELAY_RATE or 0)
    elif mode == "relay_to_home":
        legacy["origin_relay_rate"] = float(settings.RELAY_RATE or 0)
    else:
        legacy["origin_relay_rate"] = float(settings.RELAY_RATE or 0) / 2
        legacy["destination_relay_rate"] = float(settings.RELAY_RATE or 0) / 2
    return legacy


def compute_delivery_commission_breakdown(parcel: dict | None, mission: dict | None = None) -> dict:
    source: dict = {}
    if isinstance(parcel, dict):
        source.update(parcel)
    if isinstance(mission, dict):
        source.update(mission)
    price = (
        source.get("paid_price")
        or source.get("quoted_price")
        or (mission or {}).get("quoted_price")
        or 0
    )
    safe_price = max(float(price or 0), 0.0)
    mode = str(source.get("delivery_mode") or source.get("mode") or "").strip()

    commissions_are_enabled = delivery_commissions_enabled(parcel, mission)
    rules = commission_rules_for(source, mode)
    if not commissions_are_enabled:
        rules = {"platform_rate": 0.0, "origin_relay_rate": 0.0, "destination_relay_rate": 0.0, "driver_rate": 1.0}

    platform_rate = rules["platform_rate"]
    origin_share_rate = rules["origin_relay_rate"]
    destination_share_rate = rules["destination_relay_rate"]
    driver_share_rate = rules["driver_rate"]

    platform_commission_xof = round(safe_price * platform_rate, 2)
    origin_relay_commission_xof = round(safe_price * origin_share_rate, 2)
    destination_relay_commission_xof = round(safe_price * destination_share_rate, 2)
    relay_commission_xof = round(
        origin_relay_commission_xof + destination_relay_commission_xof,
        2,
    )
    total_commission_xof = round(
        platform_commission_xof + relay_commission_xof,
        2,
    )
    driver_revenue_xof = round(safe_price * driver_share_rate, 2)

    return {
        "price_xof": round(safe_price, 2),
        "platform_commission_xof": platform_commission_xof,
        "origin_relay_commission_xof": origin_relay_commission_xof,
        "destination_relay_commission_xof": destination_relay_commission_xof,
        "relay_commission_xof": relay_commission_xof,
        "total_commission_xof": total_commission_xof,
        "wallet_balance_required_xof": total_commission_xof,
        "driver_revenue_xof": driver_revenue_xof,
        "driver_revenue_rate": driver_share_rate,
        "platform_rate": platform_rate,
        "origin_relay_rate": origin_share_rate,
        "destination_relay_rate": destination_share_rate,
        "settlement_model": "origin_relay_collects" if mode == "relay_to_relay" else "driver_collects",
    }


def build_relay_financial_summary(parcel: dict, relay_id: str) -> dict:
    """Résumé opérationnel lisible par le relais pour un colis donné."""
    breakdown = compute_delivery_commission_breakdown(parcel)
    mode = str(parcel.get("delivery_mode") or "")
    is_origin = parcel.get("origin_relay_id") == relay_id
    is_destination = parcel.get("destination_relay_id") == relay_id or parcel.get("redirect_relay_id") == relay_id
    roles = [role for role, enabled in (("origin", is_origin), ("destination", is_destination)) if enabled]
    settlement = parcel.get("relay_settlement") or {}
    actions = []
    if mode == "relay_to_relay" and is_origin:
        actions.extend([
            {"key": "driver_payment", "label": "Remettre la part du livreur", "amount_xof": breakdown["driver_revenue_xof"], "status": settlement.get("driver_payment_status", "pending")},
            {"key": "denkma_payment", "label": "Déclarer la part à régler à Denkma", "amount_xof": breakdown["platform_commission_xof"] + breakdown["destination_relay_commission_xof"], "status": settlement.get("denkma_payment_status", "pending")},
        ])
    if is_origin and mode == "relay_to_home":
        actions.append({"key": "driver_payment", "label": "Remettre la part du livreur", "amount_xof": breakdown["driver_revenue_xof"], "status": settlement.get("driver_payment_status", "pending")})
        actions.append({"key": "relay_commission", "label": "Suivre la commission à recevoir de Denkma", "amount_xof": breakdown["origin_relay_commission_xof"], "status": settlement.get("origin_relay_payment_status", "pending")})
    if is_destination and mode == "home_to_relay":
        actions.append({"key": "relay_commission", "label": "Suivre la commission à recevoir", "amount_xof": breakdown["destination_relay_commission_xof"], "status": settlement.get("destination_relay_payment_status", "pending")})
    if is_destination and mode == "relay_to_relay":
        actions.append({"key": "relay_commission", "label": "Suivre la commission à recevoir", "amount_xof": breakdown["destination_relay_commission_xof"], "status": settlement.get("destination_relay_payment_status", "pending")})
    return {
        "mode": mode,
        "roles": roles,
        "own_commission_xof": round(sum(
            breakdown[key] for key in ("origin_relay_commission_xof",) if is_origin
        ) + sum(
            breakdown[key] for key in ("destination_relay_commission_xof",) if is_destination
        ), 2),
        "platform_commission_xof": breakdown["platform_commission_xof"],
        "origin_relay_commission_xof": breakdown["origin_relay_commission_xof"],
        "destination_relay_commission_xof": breakdown["destination_relay_commission_xof"],
        "driver_revenue_xof": breakdown["driver_revenue_xof"],
        "customer_payment_collector": "origin_relay" if mode == "relay_to_relay" else "driver",
        "settlement_model": breakdown["settlement_model"],
        "actions": actions,
    }


async def record_wallet_transaction(
    wallet_id: str,
    amount: float,
    tx_type: str,
    description: str,
    *,
    parcel_id: Optional[str] = None,
    reference: Optional[str] = None,
    ensure_unique: bool = False,
    session=None,
) -> dict:
    if ensure_unique and reference:
        existing = await db.wallet_transactions.find_one(
            {"wallet_id": wallet_id, "reference": reference, "tx_type": tx_type},
            {"_id": 0},
            session=session,
        )
        if existing:
            return existing

    tx = {
        "tx_id": _tx_id(),
        "wallet_id": wallet_id,
        "parcel_id": parcel_id,
        "amount": amount,
        "tx_type": tx_type,
        "description": description,
        "reference": reference,
        "created_at": datetime.now(timezone.utc),
    }
    await db.wallet_transactions.insert_one(tx, session=session)
    return {k: v for k, v in tx.items() if k != "_id"}


async def get_or_create_wallet(owner_id: str, owner_type: str) -> dict:
    """Retourne le wallet existant ou en crée un nouveau."""
    wallet = await db.wallets.find_one({"owner_id": owner_id}, {"_id": 0})
    if wallet:
        return wallet

    now = datetime.now(timezone.utc)
    wallet = {
        "wallet_id":  _wallet_id(),
        "owner_id":   owner_id,
        "owner_type": owner_type,
        "balance":    0.0,
        "pending":    0.0,
        "currency":   "XOF",
        "is_active":  True,
        "created_at": now,
        "updated_at": now,
    }
    await db.wallets.insert_one(wallet)
    return {k: v for k, v in wallet.items() if k != "_id"}


async def credit_wallet(
    owner_id: str,
    owner_type: str,
    amount: float,
    description: str,
    parcel_id: Optional[str] = None,
    reference: Optional[str] = None,
    count_as_earned: bool = True,
    ensure_unique: bool = False,
) -> dict:
    wallet = await get_or_create_wallet(owner_id, owner_type)

    async def _op(session):
        now = datetime.now(timezone.utc)
        await db.wallets.update_one(
            {"owner_id": owner_id},
            {"$inc": {"balance": amount}, "$set": {"updated_at": now}},
            session=session,
        )
        if count_as_earned:
            await db.users.update_one(
                {"user_id": owner_id},
                {"$inc": {"total_earned": amount}},
                session=session,
            )
        return await record_wallet_transaction(
            wallet_id=wallet["wallet_id"],
            amount=amount,
            tx_type=TransactionType.CREDIT.value,
            description=description,
            parcel_id=parcel_id,
            reference=reference,
            ensure_unique=ensure_unique,
            session=session,
        )

    tx = await _run_in_transaction(_op)
    logger.info(f"Wallet crédité : owner={owner_id} montant={amount} XOF")
    return tx


async def record_driver_revenue(
    driver_id: str,
    amount: float,
    description: str,
    parcel_id: Optional[str] = None,
    reference: Optional[str] = None,
    ensure_unique: bool = False,
) -> dict:
    wallet = await get_or_create_wallet(driver_id, "driver")

    async def _op(session):
        await db.users.update_one(
            {"user_id": driver_id},
            {"$inc": {"total_earned": amount}, "$set": {"updated_at": datetime.now(timezone.utc)}},
            session=session,
        )
        return await record_wallet_transaction(
            wallet_id=wallet["wallet_id"],
            amount=amount,
            tx_type=TransactionType.REVENUE.value,
            description=description,
            parcel_id=parcel_id,
            reference=reference,
            ensure_unique=ensure_unique,
            session=session,
        )

    tx = await _run_in_transaction(_op)
    logger.info(
        "Revenu livreur enregistré hors solde : owner=%s montant=%s XOF",
        driver_id,
        amount,
    )
    return tx


async def debit_wallet(
    owner_id: str,
    amount: float,
    description: str,
    parcel_id: Optional[str] = None,
    reference: Optional[str] = None,
    ensure_unique: bool = False,
) -> dict:
    async def _op(session):
        wallet = await db.wallets.find_one(
            {"owner_id": owner_id}, {"_id": 0}, session=session
        )
        if not wallet or wallet["balance"] < amount:
            raise ValueError("Solde insuffisant")

        if ensure_unique and reference:
            existing = await db.wallet_transactions.find_one(
                {
                    "wallet_id": wallet["wallet_id"],
                    "reference": reference,
                    "tx_type": TransactionType.DEBIT.value,
                },
                {"_id": 0},
                session=session,
            )
            if existing:
                return existing

        now = datetime.now(timezone.utc)
        # Filtre sur balance >= amount pour éviter un débit si concurrent a vidé entretemps
        result = await db.wallets.update_one(
            {"owner_id": owner_id, "balance": {"$gte": amount}},
            {"$inc": {"balance": -amount}, "$set": {"updated_at": now}},
            session=session,
        )
        if result.modified_count == 0:
            raise ValueError("Solde insuffisant")

        return await record_wallet_transaction(
            wallet_id=wallet["wallet_id"],
            amount=amount,
            tx_type=TransactionType.DEBIT.value,
            description=description,
            parcel_id=parcel_id,
            reference=reference,
            ensure_unique=ensure_unique,
            session=session,
        )

    return await _run_in_transaction(_op)


async def debit_wallet_allow_negative(
    owner_id: str,
    owner_type: str,
    amount: float,
    description: str,
    parcel_id: Optional[str] = None,
    reference: Optional[str] = None,
    ensure_unique: bool = False,
) -> dict:
    wallet = await get_or_create_wallet(owner_id, owner_type)

    async def _op(session):
        if ensure_unique and reference:
            existing = await db.wallet_transactions.find_one(
                {
                    "wallet_id": wallet["wallet_id"],
                    "reference": reference,
                    "tx_type": TransactionType.DEBIT.value,
                },
                {"_id": 0},
                session=session,
            )
            if existing:
                return existing

        now = datetime.now(timezone.utc)
        await db.wallets.update_one(
            {"owner_id": owner_id},
            {"$inc": {"balance": -amount}, "$set": {"updated_at": now}},
            session=session,
        )
        return await record_wallet_transaction(
            wallet_id=wallet["wallet_id"],
            amount=amount,
            tx_type=TransactionType.DEBIT.value,
            description=description,
            parcel_id=parcel_id,
            reference=reference,
            ensure_unique=ensure_unique,
            session=session,
        )

    tx = await _run_in_transaction(_op)
    logger.info(f"Wallet débité avec découvert : owner={owner_id} montant={amount} XOF")
    return tx


async def distribute_delivery_revenue(parcel: dict):
    """
    Distribue les revenus à chaque livraison réussie.

    Le livreur conserve son revenu hors plateforme.
    Denkma verse les relais et conserve sa propre commission via la couverture
    prélevée sur le wallet du livreur au moment de l'acceptation.
    """
    driver_bonus = float(parcel.get("driver_bonus_xof", 0.0) or 0.0)
    breakdown = compute_delivery_commission_breakdown(parcel)
    price = breakdown["price_xof"]
    if price <= 0:
        return

    mode = parcel.get("delivery_mode", "")
    parcel_id = parcel.get("parcel_id")

    if parcel.get("assigned_driver_id") and breakdown["driver_revenue_xof"] > 0:
        await record_driver_revenue(
            driver_id=parcel["assigned_driver_id"],
            amount=breakdown["driver_revenue_xof"],
            description=f"Revenu livraison {parcel_id}",
            parcel_id=parcel_id,
            reference=f"driver_revenue:{parcel_id}",
            ensure_unique=True,
        )
        if driver_bonus > 0:
            await record_driver_revenue(
                driver_id=parcel["assigned_driver_id"],
                amount=round(driver_bonus),
                description=f"Revenu bonus changement d'adresse {parcel_id}",
                parcel_id=parcel_id,
                reference=f"driver_bonus_revenue:{parcel_id}",
                ensure_unique=True,
            )

    # En relais -> relais, le relais de départ conserve directement sa part
    # sur le montant encaissé ; Denkma ne la lui reverse donc pas une seconde fois.
    if parcel.get("origin_relay_id") and mode != "relay_to_relay" and breakdown["origin_relay_commission_xof"] > 0:
        relay = await db.relay_points.find_one(
            {"relay_id": parcel["origin_relay_id"]}, {"_id": 0}
        )
        if relay:
            await credit_wallet(
                owner_id=relay["owner_user_id"],
                owner_type="relay",
                amount=breakdown["origin_relay_commission_xof"],
                description=f"Commission relais origine {parcel_id}",
                parcel_id=parcel_id,
                reference=f"relay_origin_commission:{parcel_id}",
                ensure_unique=True,
            )

    dest_relay_id = parcel.get("redirect_relay_id") or parcel.get("destination_relay_id")
    if dest_relay_id and breakdown["destination_relay_commission_xof"] > 0:
        relay = await db.relay_points.find_one(
            {"relay_id": dest_relay_id}, {"_id": 0}
        )
        if relay:
            await credit_wallet(
                owner_id=relay["owner_user_id"],
                owner_type="relay",
                amount=breakdown["destination_relay_commission_xof"],
                description=f"Commission relais destination {parcel_id}",
                parcel_id=parcel_id,
                reference=f"relay_destination_commission:{parcel_id}",
                ensure_unique=True,
            )

    logger.info(
        "Revenus distribués : colis=%s mode=%s prix=%s XOF commission_totale=%s XOF",
        parcel_id,
        mode,
        price,
        breakdown["total_commission_xof"],
    )
