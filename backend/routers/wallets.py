"""
Router wallets : wallet personnel, transactions, demandes de retrait.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from core.dependencies import get_current_user
from core.exceptions import not_found_exception, bad_request_exception
from database import db
from models.wallet import PayoutRequest
from services.wallet_service import get_or_create_wallet

router = APIRouter()


def _payout_id() -> str:
    return f"pay_{uuid.uuid4().hex[:12]}"


@router.get("/me", summary="Mon wallet")
async def get_my_wallet(current_user: dict = Depends(get_current_user)):
    owner_type = current_user.get("role", "client")
    wallet = await get_or_create_wallet(current_user["user_id"], owner_type)
    return wallet


@router.get("/me/transactions", summary="Historique des transactions")
async def get_my_transactions(
    skip: int = 0,
    limit: int = 50,
    current_user: dict = Depends(get_current_user),
):
    wallet = await db.wallets.find_one({"owner_id": current_user["user_id"]}, {"_id": 0})
    if not wallet:
        return {"transactions": [], "total": 0}

    cursor = db.wallet_transactions.find(
        {"wallet_id": wallet["wallet_id"]},
        {"_id": 0},
    ).sort("created_at", -1).skip(skip).limit(limit)

    txs = await cursor.to_list(length=limit)
    total = await db.wallet_transactions.count_documents({"wallet_id": wallet["wallet_id"]})
    return {"transactions": txs, "total": total}


@router.post("/me/payout", summary="Demander un retrait")
async def request_payout(
    body: PayoutRequest,
    current_user: dict = Depends(get_current_user),
):
    wallet = await db.wallets.find_one({"owner_id": current_user["user_id"]}, {"_id": 0})
    if not wallet:
        raise not_found_exception("Wallet")
    if wallet["balance"] < body.amount:
        raise bad_request_exception("Solde insuffisant")
    if body.amount <= 0:
        raise bad_request_exception("Montant invalide")

    now = datetime.now(timezone.utc)
    payout = {
        "payout_id":  _payout_id(),
        "wallet_id":  wallet["wallet_id"],
        "owner_id":   current_user["user_id"],
        "amount":     body.amount,
        "method":     body.method,
        "phone":      body.phone,
        "status":     "pending",
        "created_at": now,
        "updated_at": now,
    }
    await db.payout_requests.insert_one(payout)

    # Bloquer le montant (pending)
    await db.wallets.update_one(
        {"owner_id": current_user["user_id"]},
        {"$inc": {"balance": -body.amount, "pending": body.amount}, "$set": {"updated_at": now}},
    )

    return {k: v for k, v in payout.items() if k != "_id"}


@router.get("/me/payouts", summary="Historique des retraits")
async def get_my_payouts(
    skip: int = 0,
    limit: int = 20,
    current_user: dict = Depends(get_current_user),
):
    cursor = db.payout_requests.find(
        {"owner_id": current_user["user_id"]},
        {"_id": 0},
    ).sort("created_at", -1).skip(skip).limit(limit)
    return {"payouts": await cursor.to_list(length=limit)}
