"""
Service wallet : crédit/débit, distribution des revenus à chaque livraison réussie.
"""
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from database import db
from models.wallet import TransactionType

logger = logging.getLogger(__name__)


def _wallet_id() -> str:
    return f"wlt_{uuid.uuid4().hex[:12]}"


def _tx_id() -> str:
    return f"wtx_{uuid.uuid4().hex[:12]}"


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
    now = datetime.now(timezone.utc)

    await db.wallets.update_one(
        {"owner_id": owner_id},
        {"$inc": {"balance": amount}, "$set": {"updated_at": now}},
    )

    tx = {
        "tx_id":       _tx_id(),
        "wallet_id":   wallet["wallet_id"],
        "parcel_id":   parcel_id,
        "amount":      amount,
        "tx_type":     TransactionType.CREDIT.value,
        "description": description,
        "reference":   reference,
        "created_at":  now,
    }
    await db.wallet_transactions.insert_one(tx)
    logger.info(f"Wallet crédité : owner={owner_id} montant={amount} XOF")
    return {k: v for k, v in tx.items() if k != "_id"}


async def debit_wallet(
    owner_id: str,
    amount: float,
    description: str,
    parcel_id: Optional[str] = None,
) -> dict:
    wallet = await db.wallets.find_one({"owner_id": owner_id}, {"_id": 0})
    if not wallet or wallet["balance"] < amount:
        raise ValueError("Solde insuffisant")

    now = datetime.now(timezone.utc)
    await db.wallets.update_one(
        {"owner_id": owner_id},
        {"$inc": {"balance": -amount}, "$set": {"updated_at": now}},
    )

    tx = {
        "tx_id":       _tx_id(),
        "wallet_id":   wallet["wallet_id"],
        "parcel_id":   parcel_id,
        "amount":      amount,
        "tx_type":     TransactionType.DEBIT.value,
        "description": description,
        "reference":   None,
        "created_at":  now,
    }
    await db.wallet_transactions.insert_one(tx)
    return {k: v for k, v in tx.items() if k != "_id"}


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
