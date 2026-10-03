"""
Service wallet : crédit/débit, distribution des revenus à chaque livraison réussie.
"""
import logging
import hashlib
import math
from contextvars import ContextVar
import uuid
from datetime import datetime, timezone
from typing import Optional

from pymongo.errors import DuplicateKeyError, OperationFailure

from core.exceptions import DeliveryCommissionDataError
from database import db, get_client
from models.wallet import TransactionType

logger = logging.getLogger(__name__)
_transaction_session = ContextVar("wallet_transaction_session", default=None)

async def _run_in_transaction(op):
    active_session = _transaction_session.get()
    if active_session is not None:
        return await op(active_session)
    client = get_client()
    if client is None:
        return await op(None)
    try:
        async with await client.start_session() as session:
            async def execute(transaction_session):
                token = _transaction_session.set(transaction_session)
                try:
                    return await op(transaction_session)
                finally:
                    _transaction_session.reset(token)
            return await session.with_transaction(execute)
    except OperationFailure as exc:
        if "Transaction numbers are only allowed" in str(exc) or "replica set" in str(exc).lower():
            raise RuntimeError("Les opérations financières nécessitent un replica set MongoDB") from exc
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
        try:
            values = {key: float(source.get(key, fallback)) for key, fallback in defaults[mode].items()}
        except (TypeError, ValueError) as exc:
            raise DeliveryCommissionDataError() from exc
        if any(not math.isfinite(value) or value < 0 for value in values.values()):
            raise DeliveryCommissionDataError()
        total = sum(values.values())
        if total <= 0:
            values = defaults[mode].copy()
        else:
            values = {key: round(value / total, 8) for key, value in values.items()}
            values["driver_rate"] = round(1 - sum(value for key, value in values.items() if key != "driver_rate"), 8)
        normalized[mode] = values
    return normalized


def resolve_delivery_commission_mode(parcel: dict | None, mission: dict | None = None) -> str:
    for source in (parcel, mission):
        contract = (source or {}).get("financial_contract") or {}
        if contract.get("delivery_mode") in COMMISSION_MODES:
            return contract["delivery_mode"]
    for source in (mission, parcel):
        if not isinstance(source, dict):
            continue
        for key in ("delivery_mode", "mode"):
            raw = source.get(key)
            mode = str(getattr(raw, "value", raw) or "").strip()
            if not mode:
                continue
            if mode not in COMMISSION_MODES:
                raise DeliveryCommissionDataError()
            return mode
    raise DeliveryCommissionDataError()


def commission_rules_for(source: dict, mode: str) -> dict:
    if mode not in COMMISSION_MODES:
        raise DeliveryCommissionDataError()
    rules = source.get("commission_rules_snapshot") or source.get("commission_rules")
    if isinstance(rules, dict):
        return normalize_commission_rules(rules)[mode]
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
    for item in (parcel, mission):
        contract = (item or {}).get("financial_contract") or {}
        if contract.get("breakdown"):
            return dict(contract["breakdown"])
    source: dict = {}
    if isinstance(parcel, dict):
        source.update(parcel)
    if isinstance(mission, dict):
        source.update(mission)
    if isinstance(parcel, dict) and isinstance(mission, dict):
        for key in ("commission_rules_snapshot", "commission_rules"):
            if not mission.get(key) and parcel.get(key):
                source[key] = parcel[key]
        if mission.get("delivery_commissions_enabled") is None:
            source["delivery_commissions_enabled"] = parcel.get("delivery_commissions_enabled")
    price = (
        source.get("paid_price")
        or source.get("quoted_price")
        or (mission or {}).get("quoted_price")
        or 0
    )
    try:
        safe_price = float(price or 0)
    except (TypeError, ValueError) as exc:
        raise DeliveryCommissionDataError() from exc
    if not math.isfinite(safe_price) or safe_price < 0:
        raise DeliveryCommissionDataError()
    mode = resolve_delivery_commission_mode(parcel, mission)

    commissions_are_enabled = delivery_commissions_enabled(source)
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
    mode = resolve_delivery_commission_mode(parcel)
    is_origin = parcel.get("origin_relay_id") == relay_id
    is_destination = (parcel.get("redirect_relay_id") or parcel.get("destination_relay_id")) == relay_id
    roles = [role for role, enabled in (("origin", is_origin), ("destination", is_destination)) if enabled]
    settlement = parcel.get("relay_settlement") or {}
    if parcel.get("redirect_relay_commission_xof") and is_destination:
        breakdown["destination_relay_commission_xof"] = float(parcel.get("redirect_relay_commission_xof") or breakdown["destination_relay_commission_xof"])
    actions = []
    if mode == "relay_to_relay" and is_origin:
        actions.extend([
            {"key": "driver_payment", "label": "Remettre la part du livreur", "amount_xof": breakdown["driver_revenue_xof"], "status": settlement.get("driver_payment_status", "pending")},
            {"key": "denkma_payment", "label": "Déclarer la part à régler à Denkma", "amount_xof": breakdown["platform_commission_xof"] + breakdown["destination_relay_commission_xof"], "status": settlement.get("denkma_payment_status", "pending")},
        ])
    if is_origin and mode == "relay_to_home":
        actions.append({"key": "driver_payment", "label": "Remettre la part du livreur", "amount_xof": breakdown["driver_revenue_xof"], "status": settlement.get("driver_payment_status", "pending")})
        actions.append({"key": "relay_commission", "settlement_action": "origin_relay_payment", "label": "Suivre la commission à recevoir de Denkma", "amount_xof": breakdown["origin_relay_commission_xof"], "status": settlement.get("origin_relay_payment_status", "pending")})
    if is_destination and (mode == "home_to_relay" or parcel.get("redirect_relay_id") or parcel.get("redirect_relay_commission_xof")):
        actions.append({"key": "relay_commission", "settlement_action": "destination_relay_payment", "label": "Suivre la commission à recevoir", "amount_xof": breakdown["destination_relay_commission_xof"], "status": settlement.get("destination_relay_payment_status", "pending")})
    if is_destination and mode == "relay_to_relay" and not parcel.get("redirect_relay_id") and not parcel.get("redirect_relay_commission_xof"):
        actions.append({"key": "relay_commission", "settlement_action": "destination_relay_payment", "label": "Suivre la commission à recevoir", "amount_xof": breakdown["destination_relay_commission_xof"], "status": settlement.get("destination_relay_payment_status", "pending")})
    plan = parcel.get("recipient_collection_plan") or {}
    if plan:
        actions = [item for item in actions if item["key"] not in {"driver_payment", "denkma_payment"} or item["status"] in {"declared", "validated"}]
        collected = round(sum(float(receipt["amount_xof"]) for receipt in plan.get("receipts", []) if receipt.get("collector") == "relay" and receipt.get("collector_id") == relay_id), 2)
        remittance = (parcel.get("recipient_collection_remittances") or {}).get(relay_id) or {}
        transferred = float(remittance.get("amount_validated_xof") or 0)
        outstanding = round(max(0, collected - transferred), 2)
        if collected > 0:
            actions.append({"key": "recipient_collection_payment", "label": "Reverser l'encaissement destinataire à Denkma",
                            "amount_xof": outstanding or transferred, "status": "validated" if outstanding == 0 else remittance.get("status", "pending"),
                            "settlement_field": f"recipient_collection_remittances.{relay_id}.status",
                            "validated_amount_xof": transferred, "received_amount_xof": collected})
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
        "customer_payment_collector": plan.get("collector") if plan else "origin_relay" if mode == "relay_to_relay" else "driver",
        "settlement_model": breakdown["settlement_model"],
        "actions": actions,
        "redirect_funding_review_required": bool(parcel.get("redirect_relay_commission_xof") and settlement.get("destination_relay_payment_status") != "validated"),
        "recipient_collection_plan": parcel.get("recipient_collection_plan"),
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
        "tx_id": (
            "wtx_" + hashlib.sha256(f"{wallet_id}:{tx_type}:{reference}".encode()).hexdigest()
            if ensure_unique and reference else _tx_id()
        ),
        "wallet_id": wallet_id,
        "parcel_id": parcel_id,
        "amount": amount,
        "tx_type": tx_type,
        "description": description,
        "reference": reference,
        "created_at": datetime.now(timezone.utc),
    }
    tx["_id"] = tx["tx_id"]
    await db.wallet_transactions.insert_one(tx, session=session)
    return {k: v for k, v in tx.items() if k != "_id"}


async def get_or_create_wallet(owner_id: str, owner_type: str) -> dict:
    """Retourne le wallet existant ou en crée un nouveau."""
    kwargs = {"session": _transaction_session.get()} if _transaction_session.get() is not None else {}
    wallet = await db.wallets.find_one({"owner_id": owner_id}, {"_id": 0}, **kwargs)
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
    try:
        await db.wallets.insert_one(wallet, **kwargs)
    except DuplicateKeyError:
        if _transaction_session.get() is not None:
            raise
        return await db.wallets.find_one({"owner_id": owner_id}, {"_id": 0}, **kwargs)
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
        existing = await _existing_operation(wallet["wallet_id"], TransactionType.CREDIT.value, reference, ensure_unique, amount, session)
        if existing:
            return existing
        tx = await record_wallet_transaction(
            wallet["wallet_id"], amount, TransactionType.CREDIT.value, description,
            parcel_id=parcel_id, reference=reference, ensure_unique=ensure_unique, session=session,
        )
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
        return tx

    tx = await _run_wallet_operation(_op)
    logger.info(f"Wallet crédité : owner={owner_id} montant={amount} XOF")
    return tx


async def _existing_operation(wallet_id, tx_type, reference, ensure_unique, amount, session):
    if not math.isfinite(amount) or amount < 0:
        raise ValueError("Montant invalide")
    if not ensure_unique or not reference:
        return None
    existing = await db.wallet_transactions.find_one(
        {"wallet_id": wallet_id, "reference": reference, "tx_type": tx_type},
        {"_id": 0}, session=session,
    )
    if existing and float(existing["amount"]) != float(amount):
        raise ValueError("Cette opération a déjà été enregistrée avec un autre montant")
    return existing


async def _run_wallet_operation(op):
    if _transaction_session.get() is not None:
        return await op(_transaction_session.get())
    try:
        return await _run_in_transaction(op)
    except DuplicateKeyError:
        return await _run_in_transaction(op)


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
        existing = await _existing_operation(wallet["wallet_id"], TransactionType.REVENUE.value, reference, ensure_unique, amount, session)
        if existing:
            return existing
        tx = await record_wallet_transaction(
            wallet["wallet_id"], amount, TransactionType.REVENUE.value, description,
            parcel_id=parcel_id, reference=reference, ensure_unique=ensure_unique, session=session,
        )
        await db.users.update_one(
            {"user_id": driver_id},
            {"$inc": {"total_earned": amount}, "$set": {"updated_at": datetime.now(timezone.utc)}},
            session=session,
        )
        return tx

    tx = await _run_wallet_operation(_op)
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
        if not wallet:
            raise ValueError("Solde insuffisant")
        existing = await _existing_operation(wallet["wallet_id"], TransactionType.DEBIT.value, reference, ensure_unique, amount, session)
        if existing:
            return existing
        if wallet["balance"] < amount:
            raise ValueError("Solde insuffisant")
        tx = await record_wallet_transaction(
            wallet["wallet_id"], amount, TransactionType.DEBIT.value, description,
            parcel_id=parcel_id, reference=reference, ensure_unique=ensure_unique, session=session,
        )

        now = datetime.now(timezone.utc)
        # Filtre sur balance >= amount pour éviter un débit si concurrent a vidé entretemps
        result = await db.wallets.update_one(
            {"owner_id": owner_id, "balance": {"$gte": amount}},
            {"$inc": {"balance": -amount}, "$set": {"updated_at": now}},
            session=session,
        )
        if result.modified_count == 0:
            raise ValueError("Solde insuffisant")

        return tx

    return await _run_wallet_operation(_op)


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
        existing = await _existing_operation(wallet["wallet_id"], TransactionType.DEBIT.value, reference, ensure_unique, amount, session)
        if existing:
            return existing
        tx = await record_wallet_transaction(
            wallet["wallet_id"], amount, TransactionType.DEBIT.value, description,
            parcel_id=parcel_id, reference=reference, ensure_unique=ensure_unique, session=session,
        )

        now = datetime.now(timezone.utc)
        await db.wallets.update_one(
            {"owner_id": owner_id},
            {"$inc": {"balance": -amount}, "$set": {"updated_at": now}},
            session=session,
        )
        return tx

    tx = await _run_wallet_operation(_op)
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

    mode = resolve_delivery_commission_mode(parcel)
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


async def refund_mission_commission(mission: dict, *, session=None) -> dict | None:
    driver_id = mission.get("driver_id")
    reference = mission_charge_reference(mission)
    wallet = await db.wallets.find_one({"owner_id": driver_id}, {"_id": 0}, session=session)
    if not wallet:
        return None
    charge = await db.wallet_transactions.find_one(
        {"wallet_id": wallet["wallet_id"], "reference": reference, "tx_type": "debit"},
        {"_id": 0}, session=session,
    )
    if not charge:
        return None
    refund_reference = commission_refund_reference(reference)
    return await credit_wallet(
        driver_id, "driver", float(charge["amount"]),
        f"Remboursement commission mission {mission['mission_id']}",
        parcel_id=mission.get("parcel_id"), reference=refund_reference,
        count_as_earned=False, ensure_unique=True,
    )


def commission_refund_reference(reference: str) -> str:
    prefix, _, suffix = reference.partition(":")
    if prefix in {"commission", "commission_debt"}:
        return f"commission_refund:{suffix}"
    return f"commission_refund:{reference}"


def mission_charge_reference(mission: dict) -> str:
    prefix = "commission_debt" if mission.get("commission_charge_mode") == "driver_debt" else "commission"
    return mission.get("platform_commission_wallet_reference") or f"{prefix}:{mission['mission_id']}"


def mission_commission_refunded(mission: dict, references: set[str]) -> bool:
    if commission_refund_reference(mission_charge_reference(mission)) in references:
        return True
    return not mission.get("platform_commission_wallet_reference") and any(
        ref.startswith(f"commission_reversal:{mission['mission_id']}:") for ref in references
    )
