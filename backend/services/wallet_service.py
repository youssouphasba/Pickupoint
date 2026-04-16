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
) -> dict:
    wallet = await get_or_create_wallet(owner_id, owner_type)

    async def _op(session):
        now = datetime.now(timezone.utc)
        await db.wallets.update_one(
            {"owner_id": owner_id},
            {"$inc": {"balance": amount}, "$set": {"updated_at": now}},
            session=session,
        )
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
            session=session,
        )

    tx = await _run_in_transaction(_op)
    logger.info(f"Wallet crédité : owner={owner_id} montant={amount} XOF")
    return tx


async def debit_wallet(
    owner_id: str,
    amount: float,
    description: str,
    parcel_id: Optional[str] = None,
) -> dict:
    async def _op(session):
        wallet = await db.wallets.find_one(
            {"owner_id": owner_id}, {"_id": 0}, session=session
        )
        if not wallet or wallet["balance"] < amount:
            raise ValueError("Solde insuffisant")

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
            session=session,
        )

    return await _run_in_transaction(_op)


async def distribute_delivery_revenue(parcel: dict):
    """
    Distribue les revenus à chaque livraison réussie.

    Taux validés (config.py) : plateforme 15 %, relais 15 %, livreur 70 %.
    Répartition par mode de livraison :
      RELAY_TO_RELAY : 15% plateforme + 7.5% relais origine + 7.5% relais dest + 70% driver
      RELAY_TO_HOME  : 15% plateforme + 15% relais origine + 70% driver
      HOME_TO_RELAY  : 15% plateforme + 15% relais destination + 70% driver
      HOME_TO_HOME   : 15% plateforme + 85% driver (pas de relais)
    """
    from config import settings

    driver_bonus = float(parcel.get("driver_bonus_xof", 0.0) or 0.0)

    # COD : paiement à la livraison — le client paye en cash au livreur
    # Le livreur reverse la plateforme et les relais via son wallet (Phase 2)
    # Phase 1 : log seulement, on ne crédite pas le wallet automatiquement
    if parcel.get("who_pays") == "recipient":
        price = parcel.get("paid_price") or parcel.get("quoted_price", 0)
        driver_id = parcel.get("assigned_driver_id")
        collected_total = float(price) + driver_bonus
        if driver_id and collected_total > 0:
            await db.users.update_one(
                {"user_id": driver_id},
                {"$inc": {"cod_balance": collected_total}, "$set": {"updated_at": datetime.now(timezone.utc)}}
            )
            logger.info(
                "COD livraison %s — montant collecte %s XOF — crédité au cod_balance du livreur %s",
                parcel.get("parcel_id"), collected_total, driver_id
            )
        return

    price = parcel.get("paid_price") or parcel.get("quoted_price", 0)
    if price <= 0:
        return

    mode      = parcel.get("delivery_mode", "")
    parcel_id = parcel.get("parcel_id")

    platform_rate = settings.PLATFORM_RATE   # 0.15
    relay_rate    = settings.RELAY_RATE       # 0.15
    driver_rate   = settings.DRIVER_RATE      # 0.70

    # ── Calcul des parts par mode ─────────────────────────────────────────────
    if mode == "relay_to_relay":
        relay_each    = relay_rate / 2          # 7.5 % chaque relais
        driver_share  = driver_rate             # 70 %
        origin_share  = relay_each
        dest_share    = relay_each
    elif mode == "relay_to_home":
        driver_share  = driver_rate             # 70 %
        origin_share  = relay_rate              # 15 % relais origine
        dest_share    = 0.0
    elif mode == "home_to_relay":
        driver_share  = driver_rate             # 70 %
        origin_share  = 0.0
        dest_share    = relay_rate              # 15 % relais destination
    else:  # home_to_home ou inconnu
        driver_share  = driver_rate + relay_rate  # 85 % (pas de relais)
        origin_share  = 0.0
        dest_share    = 0.0

    # ── Créditer le driver ────────────────────────────────────────────────────
    if parcel.get("assigned_driver_id") and driver_share > 0:
        await credit_wallet(
            owner_id=parcel["assigned_driver_id"],
            owner_type="driver",
            amount=round(price * driver_share),
            description=f"Commission livraison {parcel_id}",
            parcel_id=parcel_id,
        )
        if driver_bonus > 0:
            await credit_wallet(
                owner_id=parcel["assigned_driver_id"],
                owner_type="driver",
                amount=round(driver_bonus),
                description=f"Bonus changement d'adresse {parcel_id}",
                parcel_id=parcel_id,
            )

    # ── Créditer le relais origine ────────────────────────────────────────────
    if parcel.get("origin_relay_id") and origin_share > 0:
        relay = await db.relay_points.find_one(
            {"relay_id": parcel["origin_relay_id"]}, {"_id": 0}
        )
        if relay:
            await credit_wallet(
                owner_id=relay["owner_user_id"],
                owner_type="relay",
                amount=round(price * origin_share),
                description=f"Commission relais origine {parcel_id}",
                parcel_id=parcel_id,
            )

    # ── Créditer le relais destination (ou relais de repli) ───────────────────
    dest_relay_id = parcel.get("redirect_relay_id") or parcel.get("destination_relay_id")
    if dest_relay_id and dest_share > 0:
        relay = await db.relay_points.find_one(
            {"relay_id": dest_relay_id}, {"_id": 0}
        )
        if relay:
            await credit_wallet(
                owner_id=relay["owner_user_id"],
                owner_type="relay",
                amount=round(price * dest_share),
                description=f"Commission relais destination {parcel_id}",
                parcel_id=parcel_id,
            )

    logger.info(
        "Revenus distribués — colis=%s mode=%s prix=%s XOF",
        parcel_id, mode, price,
    )
