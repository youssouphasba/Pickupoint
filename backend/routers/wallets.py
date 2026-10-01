"""
Router wallets : wallet personnel, transactions, demandes de retrait.
"""
import uuid
import hashlib
import logging
from calendar import monthrange
from datetime import datetime, timedelta, timezone
import re
from typing import Optional

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field

from core.dependencies import get_current_user
from core.exceptions import bad_request_exception, not_found_exception
from core.limiter import limiter
from core.utils import normalize_phone
from database import db
from models.wallet import PayoutRequest, TransactionType
from services.wallet_service import get_or_create_wallet, record_wallet_transaction
from services.wallet_service import _run_in_transaction
from services.wallet_activity_service import wallet_activity
from services.admin_events_service import AdminEventType, record_admin_event
from services.stripe_service import (
    create_wallet_topup_checkout, get_wallet_topup, get_wallet_topups,
    reconcile_wallet_topups, wallet_topup_options,
)

router = APIRouter()
logger = logging.getLogger(__name__)

ALLOWED_PAYOUT_METHODS = {"wave", "orange_money", "free_money"}


def _payout_id() -> str:
    return f"pay_{uuid.uuid4().hex[:12]}"


class StripeTopupRequest(BaseModel):
    amount: float = Field(..., gt=0, allow_inf_nan=False)


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
        if not 1 <= month <= 12 or not 1 <= year <= 9999:
            raise bad_request_exception("Période invalide")
        start = datetime(year, month, 1, tzinfo=timezone.utc)
        end = datetime(year, month, monthrange(year, month)[1], 23, 59, 59, 999000, tzinfo=timezone.utc)
        return {"created_at": {"$gte": start, "$lte": end}}

    raise bad_request_exception("Période invalide")


@router.get("/me", summary="Mon wallet")
async def get_my_wallet(current_user: dict = Depends(get_current_user)):
    owner_type = current_user.get("role", "client")
    if owner_type == "driver":
        await reconcile_wallet_topups(current_user["user_id"])
    wallet = await get_or_create_wallet(current_user["user_id"], owner_type)
    wallet.pop("stripe_credited_topups", None)
    if owner_type == "driver":
        wallet["topup_options"] = wallet_topup_options()
        wallet["topups"] = await get_wallet_topups(current_user["user_id"])
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
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
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


@router.get("/me/activity", summary="Solde et revenus : historique regroupé et résumé de période")
async def get_my_activity(
    skip: int = Query(0, ge=0), limit: int = Query(20, ge=1, le=100),
    period: Optional[str] = Query(None), category: str = Query("balance", pattern="^(balance|revenues)$"),
    current_user: dict = Depends(get_current_user),
):
    return await wallet_activity(db, current_user, _transaction_period_filter(period), category=category, skip=skip, limit=limit)


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
    payout_id = ("pay_" + hashlib.sha256(f"{current_user['user_id']}:{body.request_key}".encode()).hexdigest()
                 if body.request_key else _payout_id())
    async def reserve(session):
        existing = await db.payout_requests.find_one({"payout_id": payout_id}, {"_id": 0}, session=session)
        if existing:
            if existing["amount"] != body.amount or existing["method"] != method or existing["phone"] != payout_phone:
                raise bad_request_exception("Cette demande de retrait a déjà été utilisée avec d'autres informations")
            return existing
        if current_user.get("role") == "driver":
            await db.users.update_one({"user_id": current_user["user_id"]}, {"$inc": {"mission_assignment_revision": 1}}, session=session)
            if await db.delivery_missions.find_one(
                {"driver_id": current_user["user_id"], "status": {"$in": ["assigned", "in_progress", "incident_reported"]}}, session=session,
            ):
                raise bad_request_exception("Décaissement indisponible tant qu'une course est active")
        wallet_update = await db.wallets.update_one(
        {"owner_id": current_user["user_id"], "balance": {"$gte": body.amount},
         "payout_blocked": {"$ne": True}, "is_active": {"$ne": False}},
        {
            "$inc": {"balance": -body.amount, "pending": body.amount},
            "$set": {"updated_at": now},
        },
        session=session,
        )
        if wallet_update.modified_count == 0:
            raise bad_request_exception("Solde insuffisant")
        payout = {
        "_id": payout_id,
        "payout_id": payout_id,
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
        await db.payout_requests.insert_one(payout, session=session)
        await record_wallet_transaction(
            wallet_id=wallet["wallet_id"],
            amount=body.amount,
            tx_type=TransactionType.PENDING.value,
            description="Demande de décaissement du solde en attente",
            reference=payout["payout_id"],
            ensure_unique=True,
            session=session,
        )
        return payout
    payout = await _run_in_transaction(reserve)
    try:
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
    except Exception:
        logger.exception("Notification admin du retrait %s à reprendre", payout_id)

    return {k: v for k, v in payout.items() if k != "_id"}


@router.post("/me/topups/stripe", summary="Créer une recharge wallet Stripe")
async def create_stripe_wallet_topup(
    body: StripeTopupRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user.get("role") != "driver":
        raise bad_request_exception("La recharge Stripe est réservée aux livreurs")
    return await create_wallet_topup_checkout(user=current_user, amount=body.amount)


@router.get("/me/topups/stripe/{topup_id}", summary="Vérifier ma recharge Stripe")
async def verify_my_stripe_wallet_topup(
    topup_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user.get("role") != "driver":
        raise bad_request_exception("La recharge Stripe est réservée aux livreurs")
    return await get_wallet_topup(current_user["user_id"], topup_id)


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
