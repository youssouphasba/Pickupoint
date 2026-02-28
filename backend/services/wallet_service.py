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
    Distribue les revenus entre driver, relais origine, relais destination et plateforme.
    Les taux sont configurables via system_configs (défauts hardcodés ici).
    """
    price = parcel.get("paid_price") or parcel.get("quoted_price", 0)
    if price <= 0:
        return

    # Lire les taux depuis system_configs (ou valeurs par défaut)
    config = await db.system_configs.find_one({"key": "revenue_split"}, {"_id": 0}) or {}
    driver_rate       = config.get("driver_rate", 0.20)
    origin_rate       = config.get("origin_rate", 0.10)
    destination_rate  = config.get("destination_rate", 0.15)

    parcel_id = parcel.get("parcel_id")

    # Driver
    if parcel.get("assigned_driver_id"):
        driver_amount = round(price * driver_rate)
        await credit_wallet(
            owner_id=parcel["assigned_driver_id"],
            owner_type="driver",
            amount=driver_amount,
            description=f"Commission livraison {parcel_id}",
            parcel_id=parcel_id,
        )

    # Relais origine
    if parcel.get("origin_relay_id"):
        origin_relay = await db.relay_points.find_one(
            {"relay_id": parcel["origin_relay_id"]}, {"_id": 0}
        )
        if origin_relay:
            await credit_wallet(
                owner_id=origin_relay["owner_user_id"],
                owner_type="relay",
                amount=round(price * origin_rate),
                description=f"Commission relais origine {parcel_id}",
                parcel_id=parcel_id,
            )

    # Relais destination
    dest_relay_id = parcel.get("redirect_relay_id") or parcel.get("destination_relay_id")
    if dest_relay_id:
        dest_relay = await db.relay_points.find_one(
            {"relay_id": dest_relay_id}, {"_id": 0}
        )
        if dest_relay:
            await credit_wallet(
                owner_id=dest_relay["owner_user_id"],
                owner_type="relay",
                amount=round(price * destination_rate),
                description=f"Commission relais destination {parcel_id}",
                parcel_id=parcel_id,
            )
