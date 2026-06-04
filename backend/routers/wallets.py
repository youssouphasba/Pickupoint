"""
Router wallets : wallet personnel, transactions, demandes de retrait.
"""
import uuid
from calendar import monthrange
from datetime import datetime, timedelta, timezone
import re
from typing import Optional

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel

from core.dependencies import get_current_user
from core.exceptions import bad_request_exception, not_found_exception
from core.limiter import limiter
from core.utils import normalize_phone
from database import db
from models.wallet import PayoutRequest, TransactionType
from services.wallet_service import get_or_create_wallet, record_wallet_transaction
from services.admin_events_service import AdminEventType, record_admin_event
from services.stripe_service import create_wallet_topup_checkout

router = APIRouter()

ALLOWED_PAYOUT_METHODS = {"wave", "orange_money", "free_money"}


def _payout_id() -> str:
    return f"pay_{uuid.uuid4().hex[:12]}"


class StripeTopupRequest(BaseModel):
    amount: float


async def _has_active_driver_mission(user_id: str) -> bool:
    mission = await db.delivery_missions.find_one(
        {
            "driver_id": user_id,
            "status": {"$in": ["assigned", "in_progress", "incident_reported"]},
        },
        {"_id": 0, "mission_id": 1},
    )
    return mission is not None


async def _recent_failed_driver_mission(user_id: str) -> Optional[dict]:
    cutoff = datetime.now(timezone.utc) - timedelta(hours=48)
    return await db.delivery_missions.find_one(
        {
            "driver_id": user_id,
            "status": "failed",
            "$or": [
                {"completed_at": {"$gte": cutoff}},
                {"updated_at": {"$gte": cutoff}},
            ],
        },
        {"_id": 0, "mission_id": 1, "completed_at": 1, "updated_at": 1},
    )


def _payout_block_message(wallet: dict, failed_mission: Optional[dict]) -> Optional[str]:
    if wallet.get("payout_blocked"):
        reason = (wallet.get("payout_block_reason") or "").strip()
        return reason or "Décaissement bloqué manuellement par l'administration"
    if failed_mission:
        return "Décaissement bloqué pendant 48h après une mission échouée"
    return None


def _transaction_period_filter(period: Optional[str]) -> dict:
    if not period:
        return {}

    now = datetime.now(timezone.utc)
    if period == "week":
        return {"created_at": {"$gte": now - timedelta(days=7)}}
    if period == "month":
        return {"created_at": {"$gte": now - timedelta(days=30)}}

    if re.fullmatch(r"\d{4}-\d{2}", period):
        year, month = map(int, period.split("-"))
        if not 1 <= month <= 12:
            raise bad_request_exception("Période invalide")
        start = datetime(year, month, 1, tzinfo=timezone.utc)
        end = datetime(year, month, monthrange(year, month)[1], 23, 59, 59, 999000, tzinfo=timezone.utc)
        return {"created_at": {"$gte": start, "$lte": end}}

    raise bad_request_exception("Période invalide")


@router.get("/me", summary="Mon wallet")
async def get_my_wallet(current_user: dict = Depends(get_current_user)):
    owner_type = current_user.get("role", "client")
    wallet = await get_or_create_wallet(current_user["user_id"], owner_type)
    if owner_type == "driver":
        failed_mission = await _recent_failed_driver_mission(current_user["user_id"])
        has_active_mission = await _has_active_driver_mission(current_user["user_id"])
        blocked_reason = _payout_block_message(wallet, failed_mission)
        if not blocked_reason and has_active_mission:
            blocked_reason = "Décaissement indisponible tant qu'une course est active"
        wallet["payout_available"] = not blocked_reason
        wallet["payout_block_reason"] = blocked_reason
    return wallet


@router.get("/me/transactions", summary="Historique des transactions")
async def get_my_transactions(
    skip: int = 0,
    limit: int = 50,
    period: Optional[str] = Query(None, description="Filtre: 'week', 'month' ou 'YYYY-MM'"),
    current_user: dict = Depends(get_current_user),
):
    wallet = await db.wallets.find_one({"owner_id": current_user["user_id"]}, {"_id": 0})
    if not wallet:
        return {"transactions": [], "total": 0}

    query: dict = {"wallet_id": wallet["wallet_id"]}
    query.update(_transaction_period_filter(period))

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
    if current_user.get("role") == "driver" and await _has_active_driver_mission(current_user["user_id"]):
        raise bad_request_exception("Décaissement indisponible tant qu'une course est active")
    if body.amount <= 0:
        raise bad_request_exception("Montant invalide")

    payout_phone = normalize_phone(body.phone)
    if not payout_phone:
        raise bad_request_exception("Numero de retrait invalide")
    method = body.method.strip().lower()
    if method not in ALLOWED_PAYOUT_METHODS:
        raise bad_request_exception("Methode de retrait invalide")

    wallet = await db.wallets.find_one({"owner_id": current_user["user_id"]}, {"_id": 0})
    if not wallet:
        raise not_found_exception("Wallet")
    if current_user.get("role") == "driver":
        failed_mission = await _recent_failed_driver_mission(current_user["user_id"])
        blocked_reason = _payout_block_message(wallet, failed_mission)
        if blocked_reason:
            raise bad_request_exception(blocked_reason)

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
        "user_id": current_user["user_id"],
        "amount": body.amount,
        "method": method,
        "phone": payout_phone,
        "destination": payout_phone,
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
            description="Demande de décaissement du solde en attente",
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

    await record_admin_event(
        AdminEventType.PAYOUT_REQUESTED,
        title=f"Demande de décaissement : {body.amount:,} XOF".replace(",", " "),
        message=f"{current_user.get('name') or current_user['phone']} · {method}",
        href="/dashboard/payouts",
        metadata={
            "payout_id": payout["payout_id"],
            "owner_id": current_user["user_id"],
            "amount": body.amount,
            "method": method,
        },
    )

    return {k: v for k, v in payout.items() if k != "_id"}


@router.post("/me/topups/stripe", summary="Créer une recharge wallet Stripe")
async def create_stripe_wallet_topup(
    body: StripeTopupRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user.get("role") != "driver":
        raise bad_request_exception("La recharge Stripe est réservée aux livreurs")
    return await create_wallet_topup_checkout(user=current_user, amount=body.amount)


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
