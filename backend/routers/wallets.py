"""
Router wallets : wallet personnel, transactions, demandes de retrait.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query, Request

from core.dependencies import get_current_user
from core.exceptions import bad_request_exception, not_found_exception
from core.limiter import limiter
from core.utils import normalize_phone
from database import db
from models.wallet import PayoutRequest, TransactionType
from services.wallet_service import get_or_create_wallet, record_wallet_transaction

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
    period: Optional[str] = Query(None, description="Filtre: 'week' ou 'month'"),
    current_user: dict = Depends(get_current_user),
):
    wallet = await db.wallets.find_one({"owner_id": current_user["user_id"]}, {"_id": 0})
    if not wallet:
        return {"transactions": [], "total": 0}

    query: dict = {"wallet_id": wallet["wallet_id"]}
    if period:
        from datetime import datetime, timedelta, timezone

        now = datetime.now(timezone.utc)
        if period == "week":
            query["created_at"] = {"$gte": now - timedelta(days=7)}
        elif period == "month":
            query["created_at"] = {"$gte": now - timedelta(days=30)}

    cursor = (
        db.wallet_transactions.find(query, {"_id": 0})
        .sort("created_at", -1)
        .skip(skip)
        .limit(limit)
    )

    txs = await cursor.to_list(length=limit)
    total = await db.wallet_transactions.count_documents(query)
    return {"transactions": txs, "total": total}


@router.post("/me/payout", summary="Demander un retrait")
@limiter.limit("5/minute")
async def request_payout(
    body: PayoutRequest,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    if body.amount <= 0:
        raise bad_request_exception("Montant invalide")

    payout_phone = normalize_phone(body.phone)
    if not payout_phone:
        raise bad_request_exception("Numero de retrait invalide")

    wallet = await db.wallets.find_one({"owner_id": current_user["user_id"]}, {"_id": 0})
    if not wallet:
        raise not_found_exception("Wallet")

    now = datetime.now(timezone.utc)
    wallet_update = await db.wallets.update_one(
        {"owner_id": current_user["user_id"], "balance": {"$gte": body.amount}},
        {
            "$inc": {"balance": -body.amount, "pending": body.amount},
            "$set": {"updated_at": now},
        },
    )
    if wallet_update.modified_count == 0:
        raise bad_request_exception("Solde insuffisant")

    payout = {
        "payout_id": _payout_id(),
        "wallet_id": wallet["wallet_id"],
        "owner_id": current_user["user_id"],
        "amount": body.amount,
        "method": body.method,
        "phone": payout_phone,
        "status": "pending",
        "created_at": now,
        "updated_at": now,
    }
    try:
        await db.payout_requests.insert_one(payout)
        await record_wallet_transaction(
            wallet_id=wallet["wallet_id"],
            amount=body.amount,
            tx_type=TransactionType.PENDING.value,
            description="Demande de retrait en attente",
            reference=payout["payout_id"],
            ensure_unique=True,
        )
    except Exception:
        await db.wallets.update_one(
            {"wallet_id": wallet["wallet_id"]},
            {
                "$inc": {"balance": body.amount, "pending": -body.amount},
                "$set": {"updated_at": datetime.now(timezone.utc)},
            },
        )
        await db.payout_requests.delete_one({"payout_id": payout["payout_id"]})
        raise

    return {k: v for k, v in payout.items() if k != "_id"}


@router.get("/me/payouts", summary="Historique des retraits")
async def get_my_payouts(
    skip: int = 0,
    limit: int = 20,
    current_user: dict = Depends(get_current_user),
):
    cursor = (
        db.payout_requests.find({"owner_id": current_user["user_id"]}, {"_id": 0})
        .sort("created_at", -1)
        .skip(skip)
        .limit(limit)
    )
    return {"payouts": await cursor.to_list(length=limit)}
