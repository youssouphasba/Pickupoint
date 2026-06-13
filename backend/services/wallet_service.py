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


def compute_delivery_commission_breakdown(parcel: dict | None, mission: dict | None = None) -> dict:
    from config import settings

    source = parcel or mission or {}
    price = (
        source.get("paid_price")
        or source.get("quoted_price")
        or (mission or {}).get("quoted_price")
        or 0
    )
    safe_price = max(float(price or 0), 0.0)
    mode = str(source.get("delivery_mode") or source.get("mode") or "").strip()

    platform_rate = float(settings.PLATFORM_RATE or 0)
    relay_rate = float(settings.RELAY_RATE or 0)
    driver_rate = float(settings.DRIVER_RATE or 0)

    if mode == "relay_to_relay":
        origin_share_rate = relay_rate / 2
        destination_share_rate = relay_rate / 2
        driver_share_rate = driver_rate
    elif mode == "relay_to_home":
        origin_share_rate = relay_rate
        destination_share_rate = 0.0
        driver_share_rate = driver_rate
    elif mode == "home_to_relay":
        origin_share_rate = 0.0
        destination_share_rate = relay_rate
        driver_share_rate = driver_rate
    else:
        origin_share_rate = 0.0
        destination_share_rate = 0.0
        driver_share_rate = driver_rate + relay_rate

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

    if parcel.get("origin_relay_id") and breakdown["origin_relay_commission_xof"] > 0:
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
