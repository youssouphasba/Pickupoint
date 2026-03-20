"""
Router admin : tableau de bord, gestion globale colis/relais/drivers/wallets.
"""
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from core.dependencies import require_role
from core.exceptions import not_found_exception, bad_request_exception
from core.limiter import limiter
from database import db
from models.common import UserRole, ParcelStatus
from models.wallet import TransactionType
from services.parcel_service import _record_event, sync_active_mission_with_parcel
from services.notification_service import notify_payout_result
from services.user_service import (
    build_referral_url,
    build_referral_share_message,
    describe_referral_apply_rule,
    describe_referral_reward_rule,
    get_effective_referral_share_base_url,
    get_referral_allowed_roles,
    get_referral_apply_max_count,
    get_referral_apply_metric,
    get_referral_metric_options,
    get_referral_referred_allowed_roles,
    get_referral_referred_bonus_xof,
    get_referral_share_base_url,
    get_referral_sponsor_allowed_roles,
    get_referral_sponsor_bonus_xof,
    get_referral_reward_count,
    get_referral_reward_metric,
    is_referral_role_allowed,
    is_referral_referred_role_allowed,
    is_referral_referred_enabled_for_user,
    is_referral_enabled_for_user,
    is_referral_sponsor_enabled_for_user,
    is_referral_sponsor_role_allowed,
    is_referral_globally_enabled,
)
from services.wallet_service import record_wallet_transaction

router = APIRouter()

require_admin_dep = require_role(UserRole.ADMIN, UserRole.SUPERADMIN)


class PaymentOverrideRequest(BaseModel):
    reason: str = Field(..., min_length=3, max_length=300)


class AdminDecisionRequest(BaseModel):
    reason: str = Field(..., min_length=3, max_length=300)


class MissionReassignRequest(BaseModel):
    new_driver_id: str = Field(..., min_length=3, max_length=64)
    reason: str = Field("Reassignation admin", min_length=3, max_length=300)


class ReferralSettingsRequest(BaseModel):
    enabled: bool
    bonus_xof: Optional[int] = Field(default=None, ge=0, le=1000000)
    sponsor_bonus_xof: Optional[int] = Field(default=None, ge=0, le=1000000)
    referred_bonus_xof: Optional[int] = Field(default=None, ge=0, le=1000000)
    share_base_url: Optional[str] = Field(default=None, max_length=500)
    allowed_roles: list[str] = Field(default_factory=list)
    sponsor_allowed_roles: list[str] = Field(default_factory=list)
    referred_allowed_roles: list[str] = Field(default_factory=list)
    apply_metric: str = Field("sent_parcels", min_length=3, max_length=64)
    apply_max_count: int = Field(0, ge=0, le=100000)
    reward_metric: str = Field("delivered_sender_parcels", min_length=3, max_length=64)
    reward_count: int = Field(1, ge=1, le=100000)


class UserReferralAccessRequest(BaseModel):
    enabled_override: Optional[bool] = None


def _pick_snapshot(doc: dict | None, fields: list[str]) -> dict:
    if not doc:
        return {}
    return {field: doc.get(field) for field in fields}


def _user_identity_snapshot(user: dict | None) -> dict | None:
    if not user:
        return None
    return {
        "user_id": user.get("user_id"),
        "name": user.get("name"),
        "phone": user.get("phone"),
        "email": user.get("email"),
        "role": user.get("role"),
        "profile_picture_url": user.get("profile_picture_url"),
        "is_active": user.get("is_active", True),
        "is_banned": user.get("is_banned", False),
        "is_available": user.get("is_available", False),
        "kyc_status": user.get("kyc_status", "none"),
        "relay_point_id": user.get("relay_point_id"),
        "deliveries_completed": user.get("deliveries_completed", 0),
        "average_rating": user.get("average_rating", 0.0),
        "total_earned": user.get("total_earned", 0.0),
        "created_at": user.get("created_at"),
        "updated_at": user.get("updated_at"),
        "last_driver_location": user.get("last_driver_location"),
        "last_driver_location_at": user.get("last_driver_location_at"),
    }


def _relay_identity_snapshot(relay: dict | None) -> dict | None:
    if not relay:
        return None
    return {
        "relay_id": relay.get("relay_id"),
        "name": relay.get("name"),
        "phone": relay.get("phone"),
        "description": relay.get("description"),
        "relay_type": relay.get("relay_type"),
        "address": relay.get("address"),
        "opening_hours": relay.get("opening_hours"),
        "owner_user_id": relay.get("owner_user_id"),
        "agent_user_ids": relay.get("agent_user_ids") or [],
        "max_capacity": relay.get("max_capacity", 0),
        "current_load": relay.get("current_load", 0),
        "coverage_radius_km": relay.get("coverage_radius_km"),
        "score": relay.get("score"),
        "is_active": relay.get("is_active", True),
        "is_verified": relay.get("is_verified", False),
        "store_id": relay.get("store_id"),
        "external_ref": relay.get("external_ref"),
        "created_at": relay.get("created_at"),
        "updated_at": relay.get("updated_at"),
    }


@router.get("/dashboard", summary="KPIs temps réel")
async def dashboard(_admin=Depends(require_admin_dep)):
    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    fleet_cutoff = now - timedelta(hours=1)
    signal_lost_cutoff = now - timedelta(minutes=20)
    long_mission_cutoff = now - timedelta(hours=3)
    stale_cutoff = now - timedelta(days=7)
    active_statuses = [
        ParcelStatus.CREATED.value,
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value,
        ParcelStatus.IN_TRANSIT.value,
        ParcelStatus.AT_DESTINATION_RELAY.value,
        ParcelStatus.AVAILABLE_AT_RELAY.value,
        ParcelStatus.OUT_FOR_DELIVERY.value,
        ParcelStatus.REDIRECTED_TO_RELAY.value,
        ParcelStatus.INCIDENT_REPORTED.value,
    ]
    stale_statuses = [
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value,
        ParcelStatus.AT_DESTINATION_RELAY.value,
        ParcelStatus.AVAILABLE_AT_RELAY.value,
    ]
    payment_blocked_statuses = [
        ParcelStatus.AT_DESTINATION_RELAY.value,
        ParcelStatus.AVAILABLE_AT_RELAY.value,
        ParcelStatus.OUT_FOR_DELIVERY.value,
        ParcelStatus.REDIRECTED_TO_RELAY.value,
    ]

    total_parcels = await db.parcels.count_documents({})
    parcels_today = await db.parcels.count_documents({"created_at": {"$gte": today_start}})
    delivered     = await db.parcels.count_documents({"status": ParcelStatus.DELIVERED.value})
    failed        = await db.parcels.count_documents({"status": ParcelStatus.DELIVERY_FAILED.value})
    active_parcels = await db.parcels.count_documents({"status": {"$in": active_statuses}})
    pending_payouts = await db.payout_requests.count_documents({"status": "pending"})
    active_relays = await db.relay_points.count_documents({"is_active": True})
    active_drivers = await db.users.count_documents({"role": UserRole.DRIVER.value, "is_active": True})
    live_fleet = await db.delivery_missions.count_documents({"location_updated_at": {"$gte": fleet_cutoff}})
    signal_lost = await db.delivery_missions.count_documents({
        "status": {"$in": ["assigned", "in_progress"]},
        "location_updated_at": {"$lt": signal_lost_cutoff},
    })
    critical_delay = await db.delivery_missions.count_documents({
        "status": {"$in": ["assigned", "in_progress"]},
        "assigned_at": {"$lt": long_mission_cutoff},
    })
    stale_parcels = await db.parcels.count_documents({
        "status": {"$in": stale_statuses},
        "updated_at": {"$lt": stale_cutoff},
    })
    payment_blocked_parcels = await db.parcels.count_documents({
        "status": {"$in": payment_blocked_statuses},
        "payment_status": {"$ne": "paid"},
        "payment_override": {"$ne": True},
    })

    success_rate = round(delivered / total_parcels * 100, 1) if total_parcels else 0.0

    # Chiffre d'affaires : somme des paid_price des colis livrés
    pipeline = [
        {"$match": {"status": ParcelStatus.DELIVERED.value, "paid_price": {"$ne": None}}},
        {"$group": {"_id": None, "total": {"$sum": "$paid_price"}}},
    ]
    ca_result = await db.parcels.aggregate(pipeline).to_list(length=1)
    ca = ca_result[0]["total"] if ca_result else 0.0

    return {
        "total_parcels":  total_parcels,
        "parcels_today":  parcels_today,
        "delivered":      delivered,
        "failed":         failed,
        "active_parcels": active_parcels,
        "pending_payouts": pending_payouts,
        "success_rate":   success_rate,
        "active_relays":  active_relays,
        "active_drivers": active_drivers,
        "live_fleet":     live_fleet,
        "signal_lost":    signal_lost,
        "critical_delay": critical_delay,
        "stale_parcels":  stale_parcels,
        "payment_blocked_parcels": payment_blocked_parcels,
        "revenue_xof":    ca,
    }


@router.get("/parcels", summary="Tous les colis avec filtres")
async def admin_list_parcels(
    status: str = None,
    skip: int = 0,
    limit: int = 100,
    _admin=Depends(require_admin_dep),
):
    query = {}
    if status:
        query["status"] = status
    cursor = db.parcels.find(query, {"_id": 0}).skip(skip).limit(limit)
    total = await db.parcels.count_documents(query)
    return {"parcels": await cursor.to_list(length=limit), "total": total}


@router.post("/parcels/{parcel_id}/confirm-payment", summary="Valider manuellement le paiement (Admin)")
async def admin_confirm_payment(
    parcel_id: str,
    _admin=Depends(require_admin_dep),
):
    """
    Force le statut de paiement à 'paid'. Utile pour les paiements hors-ligne
    ou pour débloquer un flux si le webhook de paiement a échoué.
    """
    now = datetime.now(timezone.utc)
    result = await db.parcels.update_one(
        {"parcel_id": parcel_id},
        {"$set": {"payment_status": "paid", "payment_method": "admin_manual", "updated_at": now}},
    )
    if result.matched_count == 0:
        raise not_found_exception("Colis")
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    await sync_active_mission_with_parcel(parcel)
    await _record_event(
        parcel_id=parcel_id,
        event_type="ADMIN_PAYMENT_CONFIRMED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes="Paiement validé manuellement par l'admin",
    )
    return {"message": "Paiement validé avec succès"}


@router.post("/parcels/{parcel_id}/payment-override", summary="Lever le blocage paiement d'un colis")
@limiter.limit("10/minute")
async def admin_payment_override(
    parcel_id: str,
    body: PaymentOverrideRequest,
    request: Request,
    _admin=Depends(require_admin_dep),
):
    reason = body.reason.strip()
    if not reason:
        raise bad_request_exception("Le motif d'override paiement est obligatoire")
    before = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not before:
        raise not_found_exception("Colis")

    now = datetime.now(timezone.utc)
    result = await db.parcels.update_one(
        {"parcel_id": parcel_id},
        {"$set": {
            "payment_override": True,
            "payment_override_reason": reason,
            "payment_override_by": _admin.get("user_id") if isinstance(_admin, dict) else "admin",
            "payment_override_at": now,
            "updated_at": now,
        }},
    )
    if result.matched_count == 0:
        raise not_found_exception("Colis")

    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    await sync_active_mission_with_parcel(parcel)
    await _record_event(
        parcel_id=parcel_id,
        event_type="ADMIN_PAYMENT_OVERRIDE",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=reason,
        metadata={
            "before": _pick_snapshot(before, [
                "payment_status",
                "payment_override",
                "payment_override_reason",
                "payment_override_by",
                "payment_override_at",
            ]),
            "after": _pick_snapshot(parcel, [
                "payment_status",
                "payment_override",
                "payment_override_reason",
                "payment_override_by",
                "payment_override_at",
            ]),
        },
    )
    return {"message": "Blocage paiement levé", "parcel_id": parcel_id}


@router.post("/parcels/{parcel_id}/suspend", summary="Suspendre un colis (Admin)")
async def admin_suspend_parcel(
    parcel_id: str,
    _admin=Depends(require_admin_dep),
):
    """
    Bloque temporairement toutes les actions sur le colis (collecte, livraison).
    """
    from services.parcel_service import transition_status
    actor = {"actor_id": _admin["user_id"] if isinstance(_admin, dict) else "admin_system", "actor_role": "admin"}
    
    await transition_status(
        parcel_id, ParcelStatus.SUSPENDED,
        notes="Colis suspendu par l'administration",
        **actor
    )
    return {"message": "Colis suspendu"}


@router.post("/parcels/{parcel_id}/unsuspend", summary="Lever la suspension (Admin)")
async def admin_unsuspend_parcel(
    parcel_id: str,
    to_status: ParcelStatus,
    _admin=Depends(require_admin_dep),
):
    """
    Relance le colis vers un statut actif (ex: CREATED, OUT_FOR_DELIVERY).
    """
    from services.parcel_service import transition_status
    actor = {"actor_id": _admin["user_id"] if isinstance(_admin, dict) else "admin_system", "actor_role": "admin"}
    
    await transition_status(
        parcel_id, to_status,
        notes=f"Suspension levée vers {to_status.value}",
        **actor
    )
    return {"message": f"Suspension levée vers {to_status.value}"}


@router.get("/relay-points", summary="Réseau relais complet")
async def admin_relay_points(
    skip: int = 0, limit: int = 100,
    _admin=Depends(require_admin_dep),
):
    cursor = db.relay_points.find({}, {"_id": 0}).skip(skip).limit(limit)
    total = await db.relay_points.count_documents({})
    return {"relay_points": await cursor.to_list(length=limit), "total": total}


@router.put("/relay-points/{relay_id}/verify", summary="Valider un relais")
async def verify_relay(relay_id: str, _admin=Depends(require_admin_dep)):
    result = await db.relay_points.update_one(
        {"relay_id": relay_id},
        {"$set": {"is_verified": True, "updated_at": datetime.now(timezone.utc)}},
    )
    if result.matched_count == 0:
        raise not_found_exception("Point relais")
    return {"message": "Relais vérifié"}


@router.get("/drivers", summary="Liste livreurs + stats")
async def admin_drivers(_admin=Depends(require_admin_dep)):
    cursor = db.users.find({"role": UserRole.DRIVER.value}, {"_id": 0})
    drivers = await cursor.to_list(length=200)
    # Enrichir avec nb de missions
    for d in drivers:
        d["missions_count"] = await db.delivery_missions.count_documents(
            {"driver_id": d["user_id"]}
        )
    return {"drivers": drivers}


@router.get("/wallets/payouts", summary="Demandes de retrait en attente")
async def admin_pending_payouts(_admin=Depends(require_admin_dep)):
    cursor = db.payout_requests.find({"status": "pending"}, {"_id": 0}).sort("created_at", 1)
    return {"payouts": await cursor.to_list(length=200)}


@router.put("/wallets/payouts/{payout_id}/approve", summary="Valider retrait")
@limiter.limit("10/minute")
async def approve_payout(
    payout_id: str,
    request: Request,
    _admin=Depends(require_admin_dep),
):
    payout = await db.payout_requests.find_one({"payout_id": payout_id}, {"_id": 0})
    if not payout:
        raise not_found_exception("Demande de retrait")
    wallet_before = await db.wallets.find_one({"wallet_id": payout["wallet_id"]}, {"_id": 0})

    now = datetime.now(timezone.utc)
    payout_result = await db.payout_requests.update_one(
        {"payout_id": payout_id, "status": "pending"},
        {"$set": {
            "status": "approved",
            "approved_by": _admin.get("user_id") if isinstance(_admin, dict) else "admin",
            "approved_at": now,
            "updated_at": now,
        }},
    )
    if payout_result.matched_count == 0:
        raise bad_request_exception("Ce retrait n'est plus en attente")

    wallet_result = await db.wallets.update_one(
        {"wallet_id": payout["wallet_id"], "pending": {"$gte": payout["amount"]}},
        {"$inc": {"pending": -payout["amount"]}, "$set": {"updated_at": now}},
    )
    if wallet_result.modified_count == 0:
        await db.payout_requests.update_one(
            {"payout_id": payout_id, "status": "approved"},
            {"$set": {"status": "pending", "updated_at": datetime.now(timezone.utc)}},
        )
        raise bad_request_exception("Solde bloque incoherent pour cette demande")

    wallet_after = await db.wallets.find_one({"wallet_id": payout["wallet_id"]}, {"_id": 0})
    await record_wallet_transaction(
        wallet_id=payout["wallet_id"],
        amount=payout["amount"],
        tx_type=TransactionType.DEBIT.value,
        description="Retrait approuve et verse",
        reference=payout_id,
        ensure_unique=True,
    )

    await _record_event(
        event_type="PAYOUT_APPROVED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Retrait approuve pour le montant {payout['amount']} XOF",
        metadata={
            "payout_id": payout_id,
            "amount": payout["amount"],
            "before": {
                "payout": _pick_snapshot(payout, [
                    "status",
                    "amount",
                    "method",
                    "phone",
                    "created_at",
                ]),
                "wallet": _pick_snapshot(wallet_before, [
                    "balance",
                    "pending",
                    "updated_at",
                ]),
            },
            "after": {
                "payout": {
                    "status": "approved",
                    "approved_by": _admin.get("user_id") if isinstance(_admin, dict) else "admin",
                    "approved_at": now,
                },
                "wallet": _pick_snapshot(wallet_after, [
                    "balance",
                    "pending",
                    "updated_at",
                ]),
            },
        },
    )

    owner_id = payout.get("user_id") or payout.get("owner_id")
    if owner_id:
        await notify_payout_result(owner_id, payout["amount"], approved=True)

    return {"message": "Retrait approuve", "payout_id": payout_id}



# ── Gestion des Utilisateurs & Bannissement ───────────────────────────────────

@router.get("/users", summary="Liste tous les utilisateurs (Admin)")
async def admin_list_users(
    skip: int = 0,
    limit: int = 100,
    role: str = None,
    _admin=Depends(require_admin_dep),
):
    query = {}
    if role:
        query["role"] = role
    
    cursor = db.users.find(query, {"_id": 0}).skip(skip).limit(limit).sort("created_at", -1)
    users = await cursor.to_list(length=limit)
    total = await db.users.count_documents(query)
    
    return {"users": users, "total": total}


@router.get("/users/{user_id}/detail", summary="Fiche detaillee d'un utilisateur")
async def admin_user_detail(
    user_id: str,
    _admin=Depends(require_admin_dep),
):
    user = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not user:
        raise not_found_exception("Utilisateur")

    phone_candidates = [candidate for candidate in {user.get("phone")} if candidate]
    received_query = {"recipient_user_id": user_id}
    if phone_candidates:
        received_query = {
            "$or": [
                {"recipient_user_id": user_id},
                {"recipient_phone": {"$in": phone_candidates}},
            ]
        }

    linked_relay = None
    relay_id = user.get("relay_point_id")
    if relay_id:
        relay_doc = await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0})
        linked_relay = _relay_identity_snapshot(relay_doc)

    wallet = await db.wallets.find_one({"owner_id": user_id}, {"_id": 0})
    active_mission = await db.delivery_missions.find_one(
        {"driver_id": user_id, "status": {"$in": ["assigned", "in_progress"]}},
        {"_id": 0},
        sort=[("updated_at", -1)],
    )
    last_mission = await db.delivery_missions.find_one(
        {"driver_id": user_id},
        {"_id": 0},
        sort=[("updated_at", -1)],
    )
    recent_events = await db.parcel_events.find(
        {"actor_id": user_id},
        {"_id": 0},
    ).sort("created_at", -1).limit(10).to_list(length=10)
    last_session = await db.user_sessions.find_one(
        {"user_id": user_id},
        {"_id": 0, "refresh_token": 0},
        sort=[("created_at", -1)],
    )
    active_sessions = await db.user_sessions.count_documents(
        {"user_id": user_id, "expires_at": {"$gte": datetime.now(timezone.utc)}}
    )
    app_settings = await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}
    referred_by_user = None
    if user.get("referred_by"):
        referred_by_user = await db.users.find_one(
            {"user_id": user["referred_by"]},
            {"_id": 0, "user_id": 1, "name": 1, "phone": 1, "email": 1},
        )

    return {
        "user": user,
        "summary": {
            "parcels_sent": await db.parcels.count_documents({"sender_user_id": user_id}),
            "parcels_received": await db.parcels.count_documents(received_query),
            "missions_count": await db.delivery_missions.count_documents({"driver_id": user_id}),
            "active_sessions": active_sessions,
        },
        "linked_relay": linked_relay,
        "wallet": _pick_snapshot(
            wallet,
            [
                "wallet_id",
                "owner_type",
                "balance",
                "pending",
                "currency",
                "updated_at",
            ],
        ),
        "active_mission": _pick_snapshot(
            active_mission,
            [
                "mission_id",
                "parcel_id",
                "status",
                "pickup_label",
                "delivery_label",
                "assigned_at",
                "updated_at",
                "location_updated_at",
                "driver_location",
            ],
        ),
        "last_mission": _pick_snapshot(
            last_mission,
            [
                "mission_id",
                "parcel_id",
                "status",
                "pickup_label",
                "delivery_label",
                "assigned_at",
                "completed_at",
                "updated_at",
            ],
        ),
        "last_session": last_session,
        "recent_events": recent_events,
        "referral": {
            "code": user.get("referral_code"),
            "referred_by": user.get("referred_by"),
            "referred_by_user": referred_by_user,
            "referral_credited": user.get("referral_credited", False),
            "enabled_override": user.get("referral_enabled_override"),
            "allowed_roles": get_referral_allowed_roles(app_settings),
            "sponsor_allowed_roles": get_referral_sponsor_allowed_roles(app_settings),
            "referred_allowed_roles": get_referral_referred_allowed_roles(app_settings),
            "role_allowed": is_referral_role_allowed(user.get("role"), app_settings),
            "sponsor_role_allowed": is_referral_sponsor_role_allowed(user.get("role"), app_settings),
            "referred_role_allowed": is_referral_referred_role_allowed(user.get("role"), app_settings),
            "effective_enabled": is_referral_enabled_for_user(user, app_settings),
            "can_sponsor": is_referral_sponsor_enabled_for_user(user, app_settings),
            "can_be_referred": is_referral_referred_enabled_for_user(user, app_settings),
            "share_base_url": get_referral_share_base_url(app_settings),
            "effective_share_base_url": get_effective_referral_share_base_url(app_settings),
            "referral_url": build_referral_url(
                user.get("referral_code", ""),
                get_effective_referral_share_base_url(app_settings),
            ),
            "bonus_xof": get_referral_referred_bonus_xof(app_settings),
            "sponsor_bonus_xof": get_referral_sponsor_bonus_xof(app_settings),
            "referred_bonus_xof": get_referral_referred_bonus_xof(app_settings),
            "apply_metric": get_referral_apply_metric(app_settings),
            "apply_max_count": get_referral_apply_max_count(app_settings),
            "apply_rule": describe_referral_apply_rule(app_settings),
            "reward_metric": get_referral_reward_metric(app_settings),
            "reward_count": get_referral_reward_count(app_settings),
            "reward_rule": describe_referral_reward_rule(app_settings),
            "referrals_count": await db.users.count_documents({"referred_by": user_id}),
        },
    }


@router.post("/users/{user_id}/ban", summary="Bannir un utilisateur")
@limiter.limit("10/minute")
async def admin_ban_user(
    user_id: str,
    body: AdminDecisionRequest,
    request: Request,
    _admin=Depends(require_admin_dep),
):
    """Marque un utilisateur comme banni et trace le motif."""
    reason = body.reason.strip()
    if not reason:
        raise bad_request_exception("Le motif du bannissement est obligatoire")

    admin_user_id = _admin.get("user_id") if isinstance(_admin, dict) else None
    if admin_user_id and admin_user_id == user_id:
        raise bad_request_exception("Vous ne pouvez pas vous bannir vous-meme")

    before = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not before:
        raise not_found_exception("Utilisateur")

    now = datetime.now(timezone.utc)
    result = await db.users.update_one(
        {"user_id": user_id},
        {"$set": {
            "is_banned": True,
            "ban_reason": reason,
            "banned_by": admin_user_id or "admin",
            "banned_at": now,
            "updated_at": now,
        }}
    )
    if result.matched_count == 0:
        raise not_found_exception("Utilisateur")

    await db.user_sessions.delete_many({"user_id": user_id})
    after = await db.users.find_one({"user_id": user_id}, {"_id": 0})

    await _record_event(
        event_type="USER_BANNED",
        actor_id=admin_user_id or "admin",
        actor_role="admin",
        notes=reason,
        metadata={
            "target_user_id": user_id,
            "before": _pick_snapshot(before, [
                "role",
                "is_active",
                "is_banned",
                "ban_reason",
                "banned_by",
                "banned_at",
                "updated_at",
            ]),
            "after": _pick_snapshot(after, [
                "role",
                "is_active",
                "is_banned",
                "ban_reason",
                "banned_by",
                "banned_at",
                "updated_at",
            ]),
        }
    )

    return {"message": "Utilisateur banni et sessions revoquees"}


@router.post("/users/{user_id}/unban", summary="Lever le bannissement")
async def admin_unban_user(
    user_id: str,
    body: AdminDecisionRequest,
    _admin=Depends(require_admin_dep),
):
    reason = body.reason.strip()
    if not reason:
        raise bad_request_exception("Le motif du debannissement est obligatoire")

    before = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not before:
        raise not_found_exception("Utilisateur")

    now = datetime.now(timezone.utc)
    result = await db.users.update_one(
        {"user_id": user_id},
        {"$set": {
            "is_banned": False,
            "unban_reason": reason,
            "unbanned_by": _admin.get("user_id") if isinstance(_admin, dict) else "admin",
            "unbanned_at": now,
            "updated_at": now,
        }}
    )
    if result.matched_count == 0:
        raise not_found_exception("Utilisateur")

    after = await db.users.find_one({"user_id": user_id}, {"_id": 0})

    await _record_event(
        event_type="USER_UNBANNED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=reason,
        metadata={
            "target_user_id": user_id,
            "before": _pick_snapshot(before, [
                "role",
                "is_active",
                "is_banned",
                "ban_reason",
                "banned_by",
                "banned_at",
                "updated_at",
            ]),
            "after": _pick_snapshot(after, [
                "role",
                "is_active",
                "is_banned",
                "unban_reason",
                "unbanned_by",
                "unbanned_at",
                "updated_at",
            ]),
        }
    )

    return {"message": "Bannissement leve"}


@router.put("/users/{user_id}/referral-access", summary="Configurer l'acces parrainage d'un utilisateur")
async def admin_set_user_referral_access(
    user_id: str,
    body: UserReferralAccessRequest,
    _admin=Depends(require_admin_dep),
):
    before = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not before:
        raise not_found_exception("Utilisateur")

    now = datetime.now(timezone.utc)
    await db.users.update_one(
        {"user_id": user_id},
        {"$set": {
            "referral_enabled_override": body.enabled_override,
            "updated_at": now,
        }},
    )
    after = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    settings_doc = await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}
    await _record_event(
        event_type="USER_REFERRAL_ACCESS_UPDATED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes="Acces parrainage utilisateur mis a jour",
        metadata={
            "target_user_id": user_id,
            "before": {
                "referral_enabled_override": before.get("referral_enabled_override"),
                "effective_enabled": is_referral_enabled_for_user(before, settings_doc),
            },
            "after": {
                "referral_enabled_override": after.get("referral_enabled_override"),
                "effective_enabled": is_referral_enabled_for_user(after, settings_doc),
            },
        },
    )
    return {
        "user_id": user_id,
        "enabled_override": after.get("referral_enabled_override"),
        "effective_enabled": is_referral_enabled_for_user(after, settings_doc),
    }


@router.get("/fleet/live", summary="Position GPS temps réel de la flotte")
async def get_live_fleet(_admin=Depends(require_admin_dep)):
    """
    Retourne la position GPS de tous les livreurs connectés 
    ayant mis à jour leur position récemment.
    """
    # On cherche les livreurs actifs (mis à jour depuis < 1h)
    from datetime import timedelta
    cutoff = datetime.now(timezone.utc) - timedelta(hours=1)
    
    cursor = db.delivery_missions.find(
        {"location_updated_at": {"$gte": cutoff}},
        {"_id": 0, "mission_id": 1, "parcel_id": 1, "driver_id": 1, "driver_location": 1, "status": 1, "location_updated_at": 1}
    )
    fleet = await cursor.to_list(length=500)
    
    # On enrichit avec le nom du livreur
    for m in fleet:
        driver = await db.users.find_one({"user_id": m["driver_id"]}, {"_id": 0, "name": 1})
        if driver:
            m["driver_name"] = driver["name"]
            
    return {"fleet": fleet}


@router.get("/analytics/stale-parcels", summary="Colis stagnant en relais (> 7j)")
async def get_stale_parcels(_admin=Depends(require_admin_dep)):
    """
    Liste les colis qui sont en relais
    depuis plus de 7 jours sans mouvement.
    """
    from datetime import timedelta
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    
    query = {
        "status": {
            "$in": [
                ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value,
                ParcelStatus.AT_DESTINATION_RELAY.value,
                ParcelStatus.AVAILABLE_AT_RELAY.value,
            ]
        },
        "updated_at": {"$lt": cutoff}
    }
    
    cursor = db.parcels.find(query, {"_id": 0})
    stale = await cursor.to_list(length=200)
    
    return {"stale_parcels": stale, "total": len(stale)}


@router.get("/analytics/anomaly-alerts", summary="Détection d'anomalies (Immobilité/Retard)")
async def get_anomaly_alerts(_admin=Depends(require_admin_dep)):
    """
    Identifie les anomalies opérationnelles :
    - Signal perdu : Pas de mise à jour GPS depuis > 20 min sur une mission active.
    - Retard critique : Mission active depuis > 3 heures.
    """
    from datetime import timedelta
    now = datetime.now(timezone.utc)
    signal_lost_cutoff = now - timedelta(minutes=20)
    long_mission_cutoff = now - timedelta(hours=3)
    
    anomalies = []
    
    # 1. Signal Perdu
    lost_cursor = db.delivery_missions.find({
        "status": {"$in": ["assigned", "in_progress"]},
        "location_updated_at": {"$lt": signal_lost_cutoff}
    }, {"_id": 0})
    
    async for m in lost_cursor:
        anomalies.append({
            "type": "signal_lost",
            "severity": "high",
            "mission_id": m["mission_id"],
            "parcel_id": m.get("parcel_id"),
            "driver_id": m["driver_id"],
            "mission_status": m.get("status"),
            "can_reassign": m.get("status") in {"pending", "assigned", "incident_reported"},
            "last_seen": m.get("location_updated_at"),
            "description": "Aucun signal GPS depuis plus de 20 minutes."
        })
        
    # 2. Mission Trop Longue
    long_cursor = db.delivery_missions.find({
        "status": {"$in": ["assigned", "in_progress"]},
        "assigned_at": {"$lt": long_mission_cutoff}
    }, {"_id": 0})
    
    async for m in long_cursor:
        # Éviter les doublons si déjà en signal_lost
        if any(a["mission_id"] == m["mission_id"] for a in anomalies):
            continue
            
        anomalies.append({
            "type": "critical_delay",
            "severity": "medium",
            "mission_id": m["mission_id"],
            "parcel_id": m.get("parcel_id"),
            "driver_id": m["driver_id"],
            "mission_status": m.get("status"),
            "can_reassign": m.get("status") in {"pending", "assigned", "incident_reported"},
            "assigned_at": m.get("assigned_at"),
            "description": "Mission active depuis plus de 3 heures."
        })

    # Enrichir avec les noms des drivers
    for a in anomalies:
        driver = await db.users.find_one({"user_id": a["driver_id"]}, {"_id": 0, "name": 1})
        if driver:
            a["driver_name"] = driver["name"]
            
    return {"anomalies": anomalies, "total": len(anomalies)}


@router.get("/analytics/heatmap", summary="Données pour la heatmap des demandes")
async def get_heatmap_data(_admin=Depends(require_admin_dep)):
    """
    Retourne les coordonnées GPS de tous les points de collecte et livraison
    pour visualiser la densité de la demande sur les 30 derniers jours.
    """
    from datetime import timedelta
    cutoff = datetime.now(timezone.utc) - timedelta(days=30)
    
    pipeline = [
        {"$match": {"created_at": {"$gte": cutoff}}},
        {"$project": {
            "_id": 0,
            "origin_lat": "$origin_location.geopin.lat",
            "origin_lng": "$origin_location.geopin.lng",
            "dest_lat": "$delivery_address.geopin.lat",
            "dest_lng": "$delivery_address.geopin.lng"
        }}
    ]
    
    cursor = db.parcels.aggregate(pipeline)
    parcels = await cursor.to_list(length=2000)
    
    points = []
    for p in parcels:
        if p.get("origin_lat") and p.get("origin_lng"):
            points.append({"lat": p["origin_lat"], "lng": p["origin_lng"]})
        if p.get("dest_lat") and p.get("dest_lng"):
            points.append({"lat": p["dest_lat"], "lng": p["dest_lng"]})
            
    return {"points": points}


@router.get("/parcels/{parcel_id}/audit", summary="Audit Trail complet du colis")
async def get_parcel_audit(parcel_id: str, _admin=Depends(require_admin_dep)):
    """
    Retourne l'historique complet des événements avec métadonnées techniques 
    (Scans, traces GPS, etc.) et noms des intervenants.
    """
    from services.parcel_service import get_parcel_timeline
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
        
    # Enrichir les infos de base du colis
    if parcel.get("sender_user_id") and not parcel.get("sender_name"):
        sender = await db.users.find_one({"user_id": parcel["sender_user_id"]}, {"_id": 0, "name": 1})
        if sender:
            parcel["sender_name"] = sender["name"]

    if parcel.get("origin_relay_id"):
        relay = await db.relay_points.find_one({"relay_id": parcel["origin_relay_id"]}, {"_id": 0, "name": 1})
        if relay:
            parcel["origin_relay_name"] = relay["name"]

    if parcel.get("destination_relay_id"):
        relay = await db.relay_points.find_one({"relay_id": parcel["destination_relay_id"]}, {"_id": 0, "name": 1})
        if relay:
            parcel["destination_relay_name"] = relay["name"]

    timeline = await get_parcel_timeline(parcel_id)
    # Enrichir la timeline avec les noms des acteurs si possible
    for event in timeline:
        event["timestamp"] = event.get("created_at")
        if event.get("actor_id"):
            actor = await db.users.find_one({"user_id": event["actor_id"]}, {"_id": 0, "name": 1})
            if actor:
                event["actor_name"] = actor["name"]

    # On cherche aussi les traces GPS associées aux missions de ce colis
    missions_cursor = db.delivery_missions.find({"parcel_id": parcel_id}, {"_id": 0})
    missions = await missions_cursor.to_list(length=10)
    
    # Enrichir les missions avec le nom du livreur
    for m in missions:
        if m.get("driver_id"):
            driver = await db.users.find_one({"user_id": m["driver_id"]}, {"_id": 0, "name": 1})
            if driver:
                m["driver_name"] = driver["name"]
    
    return {
        "parcel": parcel,
        "financial_summary": {
            "who_pays":       parcel.get("who_pays"),
            "payment_status": parcel.get("payment_status"),
            "payment_method": parcel.get("payment_method"),
            "payment_override": parcel.get("payment_override"),
            "payment_override_reason": parcel.get("payment_override_reason"),
            "quoted_price":   parcel.get("quoted_price"),
            "payment_url":    parcel.get("payment_url"),
            "address_change_surcharge_xof": parcel.get("address_change_surcharge_xof", 0.0),
            "driver_bonus_xof": parcel.get("driver_bonus_xof", 0.0),
        },
        "timeline": timeline,
        "missions": missions
    }


@router.get("/users/{user_id}/history", summary="Historique complet d'un utilisateur")
async def get_user_history(user_id: str, _admin=Depends(require_admin_dep)):
    """
    Retourne la liste des activités liées à cet utilisateur :
    - Colis envoyés
    - Colis dont il est destinataire
    - Missions de livraison (si livreur)
    - Événements d'audit liés
    """
    user = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not user:
        raise not_found_exception("Utilisateur")

    # 1. Colis envoyés
    parcels_sent = await db.parcels.find({"sender_user_id": user_id}, {"_id": 0}).to_list(length=100)
    
    # 2. Colis reçus (basé sur le numéro de téléphone ou user_id si lié)
    parcels_received = await db.parcels.find({
        "$or": [
            {"recipient_phone": user["phone"]},
            {"recipient_user_id": user_id}
        ]
    }, {"_id": 0}).to_list(length=100)

    # 3. Missions (si livreur)
    missions = []
    if user.get("role") == UserRole.DRIVER.value:
        missions = await db.delivery_missions.find({"driver_id": user_id}, {"_id": 0}).to_list(length=100)

    # 4. Événements récents où il est l'acteur
    events = await db.parcel_events.find({"actor_id": user_id}, {"_id": 0}).sort("created_at", -1).to_list(length=50)

    return {
        "user": user,
        "parcels_sent": parcels_sent,
        "parcels_received": parcels_received,
        "missions": missions,
        "events": events
    }


@router.get("/relay-points/{relay_id}/detail", summary="Fiche detaillee d'un point relais")
async def admin_relay_point_detail(
    relay_id: str,
    _admin=Depends(require_admin_dep),
):
    relay = await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0})
    if not relay:
        raise not_found_exception("Point relais")

    owner = await db.users.find_one({"user_id": relay.get("owner_user_id")}, {"_id": 0})
    agent_ids = set(relay.get("agent_user_ids") or [])
    agent_filter = []
    if agent_ids:
        agent_filter.append({"user_id": {"$in": list(agent_ids)}})
    agent_filter.append({"relay_point_id": relay_id})
    agents = await db.users.find(
        {"$or": agent_filter},
        {"_id": 0},
    ).to_list(length=20)

    stock_summary = {
        "pending_origin": await db.parcels.count_documents({
            "origin_relay_id": relay_id,
            "status": "dropped_at_origin_relay",
        }),
        "incoming": await db.parcels.count_documents({
            "destination_relay_id": relay_id,
            "status": "in_transit",
        }),
        "available": await db.parcels.count_documents({
            "$or": [
                {
                    "destination_relay_id": relay_id,
                    "status": {"$in": ["at_destination_relay", "available_at_relay"]},
                },
                {
                    "redirect_relay_id": relay_id,
                    "status": {"$in": ["redirected_to_relay", "at_destination_relay", "available_at_relay"]},
                },
            ]
        }),
        "delivered_total": await db.parcels.count_documents({
            "status": "delivered",
            "$or": [
                {"destination_relay_id": relay_id},
                {"redirect_relay_id": relay_id},
            ],
        }),
    }

    recent_parcels = await db.parcels.find(
        {
            "$or": [
                {"origin_relay_id": relay_id},
                {"destination_relay_id": relay_id},
                {"redirect_relay_id": relay_id},
            ]
        },
        {"_id": 0},
    ).sort("updated_at", -1).limit(8).to_list(length=8)

    relay_wallet = await db.wallets.find_one(
        {"owner_id": relay.get("owner_user_id"), "owner_type": "relay"},
        {"_id": 0},
    )

    return {
        "relay_point": relay,
        "owner": _user_identity_snapshot(owner),
        "agents": [_user_identity_snapshot(agent) for agent in agents],
        "stock_summary": stock_summary,
        "wallet": _pick_snapshot(
            relay_wallet,
            [
                "wallet_id",
                "owner_type",
                "balance",
                "pending",
                "currency",
                "updated_at",
            ],
        ),
        "recent_parcels": recent_parcels,
    }


@router.get("/finance/cod-monitoring", summary="Suivi du cash autorisé")
async def get_cod_monitoring(_admin=Depends(require_admin_dep)):
    """
    Retourne le montant de cash théoriquement détenu par chaque livreur/relais
    pour les transactions autorisées hors-app (point 2).
    """
    # Ici on simule une agrégation sur les missions ou wallets
    # Selon le schéma, on peut chercher les "cash_collected" dans les événements
    pipeline = [
        {"$match": {"role": UserRole.DRIVER.value}},
        {"$project": {"_id": 0, "user_id": 1, "name": 1, "cod_balance": {"$ifNull": ["$cod_balance", 0]}}}
    ]
    drivers_cash = await db.users.aggregate(pipeline).to_list(length=100)
    return {"entities": drivers_cash}


@router.get("/finance/reconciliation", summary="Rapport de reconciliation finance et operations")
async def get_finance_reconciliation(_admin=Depends(require_admin_dep)):
    wallets = await db.wallets.find(
        {},
        {
            "_id": 0,
            "wallet_id": 1,
            "owner_id": 1,
            "owner_type": 1,
            "balance": 1,
            "pending": 1,
            "currency": 1,
            "updated_at": 1,
        },
    ).to_list(length=2000)
    payouts = await db.payout_requests.find(
        {},
        {
            "_id": 0,
            "payout_id": 1,
            "wallet_id": 1,
            "owner_id": 1,
            "amount": 1,
            "method": 1,
            "phone": 1,
            "status": 1,
            "created_at": 1,
            "updated_at": 1,
        },
    ).to_list(length=5000)
    txs = await db.wallet_transactions.find(
        {"reference": {"$ne": None}},
        {
            "_id": 0,
            "wallet_id": 1,
            "reference": 1,
            "tx_type": 1,
            "amount": 1,
            "created_at": 1,
        },
    ).to_list(length=10000)

    tx_index = {
        (tx.get("wallet_id"), tx.get("reference"), tx.get("tx_type")): tx
        for tx in txs
        if tx.get("reference")
    }

    pending_by_wallet: dict[str, float] = {}
    for payout in payouts:
        if payout.get("status") == "pending":
            wallet_id = payout.get("wallet_id")
            pending_by_wallet[wallet_id] = pending_by_wallet.get(wallet_id, 0.0) + float(payout.get("amount", 0.0) or 0.0)

    wallet_pending_mismatches = []
    negative_wallets = []
    for wallet in wallets:
        wallet_id = wallet["wallet_id"]
        expected_pending = round(pending_by_wallet.get(wallet_id, 0.0), 2)
        actual_pending = round(float(wallet.get("pending", 0.0) or 0.0), 2)
        if abs(actual_pending - expected_pending) > 0.01:
            wallet_pending_mismatches.append({
                "wallet_id": wallet_id,
                "owner_id": wallet.get("owner_id"),
                "owner_type": wallet.get("owner_type"),
                "wallet_pending": actual_pending,
                "expected_pending": expected_pending,
                "updated_at": wallet.get("updated_at"),
            })
        if float(wallet.get("balance", 0.0) or 0.0) < 0 or actual_pending < 0:
            negative_wallets.append({
                "wallet_id": wallet_id,
                "owner_id": wallet.get("owner_id"),
                "owner_type": wallet.get("owner_type"),
                "balance": float(wallet.get("balance", 0.0) or 0.0),
                "pending": actual_pending,
                "updated_at": wallet.get("updated_at"),
            })

    payout_ledger_gaps = []
    expected_tx_types = {
        "pending": TransactionType.PENDING.value,
        "approved": TransactionType.DEBIT.value,
        "rejected": TransactionType.CREDIT.value,
    }
    for payout in payouts:
        expected_type = expected_tx_types.get(payout.get("status"))
        if not expected_type:
            continue
        key = (payout.get("wallet_id"), payout.get("payout_id"), expected_type)
        if key not in tx_index:
            payout_ledger_gaps.append({
                "payout_id": payout.get("payout_id"),
                "wallet_id": payout.get("wallet_id"),
                "owner_id": payout.get("owner_id"),
                "status": payout.get("status"),
                "expected_tx_type": expected_type,
                "amount": float(payout.get("amount", 0.0) or 0.0),
                "updated_at": payout.get("updated_at"),
            })

    active_missions = await db.delivery_missions.find(
        {"status": {"$in": ["pending", "assigned", "in_progress"]}},
        {"_id": 0, "mission_id": 1, "parcel_id": 1, "status": 1, "driver_id": 1, "updated_at": 1},
    ).to_list(length=1000)
    active_parcel_statuses = {
        ParcelStatus.CREATED.value,
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value,
        ParcelStatus.IN_TRANSIT.value,
        ParcelStatus.AT_DESTINATION_RELAY.value,
        ParcelStatus.AVAILABLE_AT_RELAY.value,
        ParcelStatus.OUT_FOR_DELIVERY.value,
        ParcelStatus.REDIRECTED_TO_RELAY.value,
        ParcelStatus.INCIDENT_REPORTED.value,
        ParcelStatus.SUSPENDED.value,
    }
    mission_parcel_mismatches = []
    if active_missions:
        parcel_ids = [mission["parcel_id"] for mission in active_missions if mission.get("parcel_id")]
        parcels = await db.parcels.find(
            {"parcel_id": {"$in": parcel_ids}},
            {"_id": 0, "parcel_id": 1, "status": 1, "payment_status": 1, "payment_override": 1, "updated_at": 1},
        ).to_list(length=len(parcel_ids))
        parcel_map = {parcel["parcel_id"]: parcel for parcel in parcels}
        for mission in active_missions:
            parcel = parcel_map.get(mission.get("parcel_id"))
            if not parcel or parcel.get("status") not in active_parcel_statuses:
                mission_parcel_mismatches.append({
                    "mission_id": mission.get("mission_id"),
                    "parcel_id": mission.get("parcel_id"),
                    "mission_status": mission.get("status"),
                    "parcel_status": parcel.get("status") if parcel else None,
                    "driver_id": mission.get("driver_id"),
                    "updated_at": mission.get("updated_at"),
                })

    delivered_unpaid = await db.parcels.find(
        {
            "status": ParcelStatus.DELIVERED.value,
            "payment_status": {"$ne": "paid"},
            "payment_override": {"$ne": True},
            "who_pays": {"$ne": "recipient"},
        },
        {
            "_id": 0,
            "parcel_id": 1,
            "tracking_code": 1,
            "payment_status": 1,
            "who_pays": 1,
            "updated_at": 1,
        },
    ).to_list(length=100)

    return {
        "summary": {
            "wallets_checked": len(wallets),
            "payouts_checked": len(payouts),
            "wallet_pending_mismatches": len(wallet_pending_mismatches),
            "negative_wallets": len(negative_wallets),
            "payout_ledger_gaps": len(payout_ledger_gaps),
            "mission_parcel_mismatches": len(mission_parcel_mismatches),
            "delivered_unpaid": len(delivered_unpaid),
            "issues_total": (
                len(wallet_pending_mismatches)
                + len(negative_wallets)
                + len(payout_ledger_gaps)
                + len(mission_parcel_mismatches)
                + len(delivered_unpaid)
            ),
        },
        "wallet_pending_mismatches": wallet_pending_mismatches[:20],
        "negative_wallets": negative_wallets[:20],
        "payout_ledger_gaps": payout_ledger_gaps[:20],
        "mission_parcel_mismatches": mission_parcel_mismatches[:20],
        "delivered_unpaid": delivered_unpaid[:20],
    }


@router.post("/missions/{mission_id}/reassign", summary="Reassigner une mission a un autre livreur")
async def admin_reassign_mission(
    mission_id: str,
    body: MissionReassignRequest,
    _admin=Depends(require_admin_dep),
):
    from models.delivery import MissionStatus

    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")

    if mission.get("status") not in {
        MissionStatus.PENDING.value,
        MissionStatus.ASSIGNED.value,
        MissionStatus.INCIDENT_REPORTED.value,
    }:
        raise bad_request_exception(
            "La reassignation directe n'est autorisee qu'avant la collecte ou apres un incident."
        )

    driver = await db.users.find_one(
        {
            "user_id": body.new_driver_id,
            "role": UserRole.DRIVER.value,
            "is_active": True,
        },
        {"_id": 0, "name": 1, "is_available": 1},
    )
    if not driver:
        raise bad_request_exception("Livreur cible introuvable ou inactif")
    if driver.get("is_available") is False:
        raise bad_request_exception("Le livreur cible est actuellement indisponible")

    active_mission = await db.delivery_missions.find_one(
        {
            "mission_id": {"$ne": mission_id},
            "driver_id": body.new_driver_id,
            "status": {"$in": [MissionStatus.ASSIGNED.value, MissionStatus.IN_PROGRESS.value]},
        },
        {"_id": 0, "mission_id": 1},
    )
    if active_mission:
        raise bad_request_exception("Le livreur cible a deja une mission en cours")

    now = datetime.now(timezone.utc)
    current_candidates = list(mission.get("candidate_drivers") or [])
    candidate_drivers = [body.new_driver_id] + [
        driver_id for driver_id in current_candidates if driver_id != body.new_driver_id
    ]

    await db.delivery_missions.update_one(
        {"mission_id": mission_id},
        {"$set": {
            "driver_id": body.new_driver_id,
            "status": MissionStatus.ASSIGNED.value,
            "assigned_at": now,
            "updated_at": now,
            "is_broadcast": False,
            "ping_index": 0,
            "ping_expires_at": None,
            "candidate_drivers": candidate_drivers,
        }},
    )
    updated_mission = await db.delivery_missions.find_one(
        {"mission_id": mission_id},
        {"_id": 0},
    )
    await db.parcels.update_one(
        {"parcel_id": mission["parcel_id"]},
        {"$set": {
            "assigned_driver_id": body.new_driver_id,
            "updated_at": now,
        }},
    )

    await _record_event(
        event_type="MISSION_REASSIGNED",
        parcel_id=mission.get("parcel_id"),
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=body.reason,
        metadata={
            "mission_id": mission_id,
            "previous_driver_id": mission.get("driver_id"),
            "new_driver_id": body.new_driver_id,
        },
    )
    if updated_mission:
        from services.notification_service import notify_new_mission_ping

        await notify_new_mission_ping(body.new_driver_id, updated_mission)

    return {
        "message": "Mission reassignée avec succes",
        "mission_id": mission_id,
        "parcel_id": mission.get("parcel_id"),
        "driver_id": body.new_driver_id,
        "driver_name": driver.get("name"),
    }


class IncidentResolutionRequest(BaseModel):
    action: str  # "reassign", "return", "cancel"
    notes: Optional[str] = None

@router.post("/incidents/{parcel_id}/resolve", summary="Résoudre un incident (Admin)")
async def admin_resolve_incident(
    parcel_id: str,
    body: IncidentResolutionRequest,
    _admin=Depends(require_admin_dep),
):
    """
    Prend une décision suite à un incident signalé par un livreur.
    """
    parcel = await db.parcels.find_one({"parcel_id": parcel_id})
    if not parcel:
        raise not_found_exception("Colis")

    now = datetime.now(timezone.utc)
    from services.parcel_service import transition_status, _create_delivery_mission, _record_event
    from models.delivery import MissionStatus

    # 1. Clôturer l'ancienne mission si elle est encore active
    await db.delivery_missions.update_one(
        {"parcel_id": parcel_id, "status": {"$in": ["assigned", "in_progress", "incident_reported"]}},
        {"$set": {"status": MissionStatus.FAILED.value, "completed_at": now, "updated_at": now}}
    )

    actor = {"actor_id": _admin["user_id"] if isinstance(_admin, dict) else "admin_system", "actor_role": "admin"}

    if body.action == "reassign":
        # Repasser en OUT_FOR_DELIVERY (ou CREATED/IN_TRANSIT selon l'endroit)
        # Pour simplifier, on force OUT_FOR_DELIVERY pour qu'une nouvelle mission soit créée
        await db.parcels.update_one(
            {"parcel_id": parcel_id},
            {"$set": {"assigned_driver_id": None, "updated_at": now}}
        )
        # On recrée une mission
        await _create_delivery_mission(parcel, ParcelStatus(parcel["status"]))
        notes = f"Incident résolu par réassignation. {body.notes or ''}"
    
    elif body.action == "return":
        await transition_status(parcel_id, ParcelStatus.RETURNED, notes=f"Incident résolu par retour à l'envoyeur. {body.notes or ''}", **actor)
        return {"message": "Incident résolu : Colis en cours de retour"}

    elif body.action == "cancel":
        await transition_status(parcel_id, ParcelStatus.CANCELLED, notes=f"Incident résolu par annulation. {body.notes or ''}", **actor)
        return {"message": "Incident résolu : Colis annulé"}

    else:
        raise bad_request_exception("Action de résolution invalide")

    await _record_event(
        parcel_id=parcel_id,
        event_type="INCIDENT_RESOLVED",
        actor_role="admin",
        notes=notes,
        metadata={"action": body.action}
    )
    
    return {"message": "Incident résolu avec succès"}


@router.post("/finance/settle", summary="Confirmer l'encaissement du cash (COD)")
async def admin_settle_cod(
    driver_id: str,
    amount: float = None,
    _admin=Depends(require_admin_dep),
):
    """
    Solde tout ou partie du cash on delivery collecté par un livreur.
    """
    from services.admin_service import settle_driver_cod
    res = await settle_driver_cod(driver_id, amount)
    
    await _record_event(
        event_type="COD_SETTLED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Encaissement COD validé pour le livreur {driver_id}: {res['amount_settled']} XOF",
        metadata={"driver_id": driver_id, "amount_settled": res["amount_settled"]}
    )
    
    return res


@router.post("/parcels/{parcel_id}/override", summary="Forcer un changement de statut (SuperAdmin)")
async def admin_override_status(
    parcel_id: str,
    new_status: ParcelStatus,
    notes: str,
    _admin=Depends(require_admin_dep),
):
    """
    Intervention manuelle sur le cycle de vie d'un colis.
    """
    from services.admin_service import override_parcel_status
    return await override_parcel_status(parcel_id, new_status, notes)


# ── Fidélité & Récompenses (Phase 8) ─────────────────────────────────────────

@router.post("/recompenses/trigger-monthly", summary="Lancer manuellement le calcul mensuel (Admin)")
async def admin_trigger_monthly(
    period: str, # YYYY-MM
    _admin=Depends(require_admin_dep),
):
    """
    Déclenche le calcul des stats et le versement des bonus pour une période donnée.
    """
    from services.ranking_service import (
        compute_driver_stats_for_period, 
        pay_monthly_driver_bonuses,
        compute_relay_stats_and_pay_bonuses
    )
    
    # 1. Stats Drivers
    stats = await compute_driver_stats_for_period(period)
    for stat in stats:
        await db.driver_stats.update_one(
            {"driver_id": stat["driver_id"], "period": period},
            {"$set": stat},
            upsert=True,
        )
    
    # 2. Bonus Drivers
    await pay_monthly_driver_bonuses(period)
    
    # 3. Bonus Relais
    await compute_relay_stats_and_pay_bonuses(period)
    
    return {"message": f"Calculs terminés pour la période {period}"}


@router.get("/recompenses/driver-stats", summary="Voir les stats de performance drivers")
async def admin_get_driver_stats(
    period: str,
    _admin=Depends(require_admin_dep),
):
    stats = await db.driver_stats.find({"period": period}).sort("rank", 1).to_list(length=200)
    return {"period": period, "stats": stats}


@router.get("/audit-log", summary="Journal d'audit global")
async def admin_get_audit_log(
    limit: int = 100,
    offset: int = 0,
    _admin=Depends(require_admin_dep),
):
    """
    Récupère les derniers événements système pour une traçabilité complète.
    """
    cursor = db.parcel_events.find({}, {"_id": 0}).sort("created_at", -1).skip(offset).limit(limit)
    events = await cursor.to_list(length=limit)
    
    # Enrichissement avec les noms des acteurs et codes de colis
    for ev in events:
        if ev.get("actor_id"):
            actor = await db.users.find_one({"user_id": ev["actor_id"]}, {"_id": 0, "name": 1})
            if actor:
                ev["actor_name"] = actor["name"]
        
        if ev.get("parcel_id"):
            parcel = await db.parcels.find_one({"parcel_id": ev["parcel_id"]}, {"_id": 0, "tracking_code": 1})
            if parcel:
                ev["tracking_code"] = parcel["tracking_code"]
                
    return {"events": events}


@router.put("/wallets/payouts/{payout_id}/reject", summary="Rejeter retrait")
@limiter.limit("10/minute")
async def reject_payout(
    payout_id: str,
    body: AdminDecisionRequest,
    request: Request,
    _admin=Depends(require_admin_dep),
):
    reason = body.reason.strip()
    if not reason:
        raise bad_request_exception("Le motif du rejet est obligatoire")

    payout = await db.payout_requests.find_one({"payout_id": payout_id}, {"_id": 0})
    if not payout:
        raise not_found_exception("Demande de retrait")
    if payout["status"] != "pending":
        raise bad_request_exception("Ce retrait n'est plus en attente")
    wallet_before = await db.wallets.find_one({"wallet_id": payout["wallet_id"]}, {"_id": 0})

    now = datetime.now(timezone.utc)
    payout_result = await db.payout_requests.update_one(
        {"payout_id": payout_id, "status": "pending"},
        {"$set": {
            "status": "rejected",
            "rejected_by": _admin.get("user_id") if isinstance(_admin, dict) else "admin",
            "rejected_at": now,
            "rejection_reason": reason,
            "updated_at": now,
        }},
    )
    if payout_result.matched_count == 0:
        raise bad_request_exception("Ce retrait n'est plus en attente")

    wallet_result = await db.wallets.update_one(
        {"wallet_id": payout["wallet_id"], "pending": {"$gte": payout["amount"]}},
        {
            "$inc": {"pending": -payout["amount"], "balance": payout["amount"]},
            "$set": {"updated_at": now},
        },
    )
    if wallet_result.modified_count == 0:
        await db.payout_requests.update_one(
            {"payout_id": payout_id, "status": "rejected"},
            {"$set": {"status": "pending", "updated_at": datetime.now(timezone.utc)}},
        )
        raise bad_request_exception("Solde bloque incoherent pour cette demande")

    wallet_after = await db.wallets.find_one({"wallet_id": payout["wallet_id"]}, {"_id": 0})
    await record_wallet_transaction(
        wallet_id=payout["wallet_id"],
        amount=payout["amount"],
        tx_type=TransactionType.CREDIT.value,
        description="Retrait rejete et montant restitue",
        reference=payout_id,
        ensure_unique=True,
    )

    await _record_event(
        event_type="PAYOUT_REJECTED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=reason,
        metadata={
            "payout_id": payout_id,
            "amount": payout["amount"],
            "reason": reason,
            "before": {
                "payout": _pick_snapshot(payout, [
                    "status",
                    "amount",
                    "method",
                    "phone",
                    "created_at",
                ]),
                "wallet": _pick_snapshot(wallet_before, [
                    "balance",
                    "pending",
                    "updated_at",
                ]),
            },
            "after": {
                "payout": {
                    "status": "rejected",
                    "rejected_by": _admin.get("user_id") if isinstance(_admin, dict) else "admin",
                    "rejected_at": now,
                    "rejection_reason": reason,
                },
                "wallet": _pick_snapshot(wallet_after, [
                    "balance",
                    "pending",
                    "updated_at",
                ]),
            },
        },
    )
    owner_id = payout.get("user_id") or payout.get("owner_id")
    if owner_id:
        await notify_payout_result(owner_id, payout["amount"], approved=False)

    return {"message": "Retrait rejete", "payout_id": payout_id}



# ── App Settings (Express, etc.) ─────────────────────────────────────────────

@router.get("/settings", summary="Lire les paramètres globaux de l'app")
async def get_app_settings(_admin=Depends(require_admin_dep)):
    settings_doc = await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}
    return {
        "express_enabled": settings_doc.get("express_enabled", False),
        "referral_enabled": is_referral_globally_enabled(settings_doc),
        "referral_bonus_xof": get_referral_referred_bonus_xof(settings_doc),
        "referral_sponsor_bonus_xof": get_referral_sponsor_bonus_xof(settings_doc),
        "referral_referred_bonus_xof": get_referral_referred_bonus_xof(settings_doc),
        "referral_share_base_url": get_referral_share_base_url(settings_doc),
        "effective_referral_share_base_url": get_effective_referral_share_base_url(settings_doc),
        "referral_allowed_roles": get_referral_allowed_roles(settings_doc),
        "referral_sponsor_allowed_roles": get_referral_sponsor_allowed_roles(settings_doc),
        "referral_referred_allowed_roles": get_referral_referred_allowed_roles(settings_doc),
        "referral_apply_metric": get_referral_apply_metric(settings_doc),
        "referral_apply_max_count": get_referral_apply_max_count(settings_doc),
        "referral_apply_rule": describe_referral_apply_rule(settings_doc),
        "referral_reward_metric": get_referral_reward_metric(settings_doc),
        "referral_reward_count": get_referral_reward_count(settings_doc),
        "referral_reward_rule": describe_referral_reward_rule(settings_doc),
        "referral_metric_options": get_referral_metric_options(),
    }


@router.get("/settings/referral/stats", summary="Statistiques du programme de parrainage")
async def get_referral_settings_stats(_admin=Depends(require_admin_dep)):
    settings_doc = await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}
    share_base_url = get_referral_share_base_url(settings_doc)
    effective_share_base_url = get_effective_referral_share_base_url(settings_doc)
    sponsor_allowed_roles = get_referral_sponsor_allowed_roles(settings_doc)
    referred_allowed_roles = get_referral_referred_allowed_roles(settings_doc)
    users = await db.users.find(
        {},
        {
            "_id": 0,
            "user_id": 1,
            "role": 1,
            "referral_code": 1,
            "referral_enabled_override": 1,
            "referred_by": 1,
            "referral_credited": 1,
        },
    ).to_list(length=10000)

    stats_by_role: dict[str, dict] = {}
    total_with_code = 0
    total_effective_enabled = 0
    total_referred_users = 0
    total_rewarded_users = 0
    total_pending_rewards = 0
    total_override_enabled = 0
    total_override_disabled = 0

    for user in users:
        role = str(user.get("role") or "client")
        role_stats = stats_by_role.setdefault(
            role,
            {
                "total_users": 0,
                "with_code": 0,
                "effective_enabled": 0,
                "forced_enabled": 0,
                "forced_disabled": 0,
                "referred_users": 0,
                "rewarded_users": 0,
            },
        )
        role_stats["total_users"] += 1

        if user.get("referral_code"):
            total_with_code += 1
            role_stats["with_code"] += 1

        if is_referral_enabled_for_user(user, settings_doc):
            total_effective_enabled += 1
            role_stats["effective_enabled"] += 1

        if user.get("referral_enabled_override") is True:
            total_override_enabled += 1
            role_stats["forced_enabled"] += 1
        elif user.get("referral_enabled_override") is False:
            total_override_disabled += 1
            role_stats["forced_disabled"] += 1

        if user.get("referred_by"):
            total_referred_users += 1
            role_stats["referred_users"] += 1
            if user.get("referral_credited"):
                total_rewarded_users += 1
                role_stats["rewarded_users"] += 1
            else:
                total_pending_rewards += 1

    sponsor_bonus_xof = get_referral_sponsor_bonus_xof(settings_doc)
    referred_bonus_xof = get_referral_referred_bonus_xof(settings_doc)
    return {
        "referral_enabled": is_referral_globally_enabled(settings_doc),
        "referral_bonus_xof": referred_bonus_xof,
        "referral_sponsor_bonus_xof": sponsor_bonus_xof,
        "referral_referred_bonus_xof": referred_bonus_xof,
        "referral_share_base_url": share_base_url,
        "effective_referral_share_base_url": effective_share_base_url,
        "referral_allowed_roles": sponsor_allowed_roles,
        "referral_sponsor_allowed_roles": sponsor_allowed_roles,
        "referral_referred_allowed_roles": referred_allowed_roles,
        "referral_apply_metric": get_referral_apply_metric(settings_doc),
        "referral_apply_max_count": get_referral_apply_max_count(settings_doc),
        "referral_apply_rule": describe_referral_apply_rule(settings_doc),
        "referral_reward_metric": get_referral_reward_metric(settings_doc),
        "referral_reward_count": get_referral_reward_count(settings_doc),
        "referral_reward_rule": describe_referral_reward_rule(settings_doc),
        "referral_metric_options": get_referral_metric_options(),
        "sample_referral_url": build_referral_url("DENKMA-DEMO", effective_share_base_url),
        "sample_share_message": build_referral_share_message(
            code="DENKMA-DEMO",
            referral_url=build_referral_url("DENKMA-DEMO", effective_share_base_url),
            referred_bonus_xof=referred_bonus_xof,
            reward_rule=describe_referral_reward_rule(settings_doc),
        ),
        "total_users": len(users),
        "users_with_code": total_with_code,
        "effective_enabled_users": total_effective_enabled,
        "override_enabled_users": total_override_enabled,
        "override_disabled_users": total_override_disabled,
        "referred_users": total_referred_users,
        "rewarded_users": total_rewarded_users,
        "pending_reward_users": total_pending_rewards,
        "stats_by_role": stats_by_role,
    }


@router.put("/settings/express", summary="Activer/désactiver la livraison Express")
async def toggle_express(body: dict, _admin=Depends(require_admin_dep)):
    enabled = bool(body.get("enabled", False))
    await db.app_settings.update_one(
        {"key": "global"},
        {"$set": {"express_enabled": enabled, "updated_at": datetime.now(timezone.utc)}},
        upsert=True,
    )
    status = "activée" if enabled else "désactivée"
    return {"express_enabled": enabled, "message": f"Livraison Express {status}"}


@router.put("/settings/referral", summary="Configurer le parrainage")
async def update_referral_settings(
    body: ReferralSettingsRequest,
    _admin=Depends(require_admin_dep),
):
    share_base_url = (body.share_base_url or "").strip() or None
    sponsor_allowed_roles = []
    referred_allowed_roles = []
    raw_sponsor_roles = body.sponsor_allowed_roles or body.allowed_roles
    raw_referred_roles = body.referred_allowed_roles or body.allowed_roles
    for role in raw_sponsor_roles:
        normalized_role = str(role or "").strip()
        if normalized_role and normalized_role not in sponsor_allowed_roles:
            sponsor_allowed_roles.append(normalized_role)
    for role in raw_referred_roles:
        normalized_role = str(role or "").strip()
        if normalized_role and normalized_role not in referred_allowed_roles:
            referred_allowed_roles.append(normalized_role)
    if not sponsor_allowed_roles:
        raise bad_request_exception("Au moins un role parrain doit etre autorise")
    if not referred_allowed_roles:
        raise bad_request_exception("Au moins un role filleul doit etre autorise")

    sponsor_bonus_xof = (
        body.sponsor_bonus_xof
        if body.sponsor_bonus_xof is not None
        else (body.bonus_xof if body.bonus_xof is not None else 500)
    )
    referred_bonus_xof = (
        body.referred_bonus_xof
        if body.referred_bonus_xof is not None
        else (body.bonus_xof if body.bonus_xof is not None else 500)
    )
    now = datetime.now(timezone.utc)
    before = await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}
    await db.app_settings.update_one(
        {"key": "global"},
        {"$set": {
            "referral_enabled": body.enabled,
            "referral_bonus_xof": referred_bonus_xof,
            "referral_sponsor_bonus_xof": sponsor_bonus_xof,
            "referral_referred_bonus_xof": referred_bonus_xof,
            "referral_share_base_url": share_base_url,
            "referral_allowed_roles": sponsor_allowed_roles,
            "referral_sponsor_allowed_roles": sponsor_allowed_roles,
            "referral_referred_allowed_roles": referred_allowed_roles,
            "referral_apply_metric": body.apply_metric,
            "referral_apply_max_count": body.apply_max_count,
            "referral_reward_metric": body.reward_metric,
            "referral_reward_count": body.reward_count,
            "updated_at": now,
        }},
        upsert=True,
    )
    after = await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}
    await _record_event(
        event_type="ADMIN_REFERRAL_SETTINGS_UPDATED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes="Configuration du parrainage mise a jour",
        metadata={
            "before": {
                "referral_enabled": before.get("referral_enabled", True),
                "referral_bonus_xof": get_referral_referred_bonus_xof(before),
                "referral_sponsor_bonus_xof": get_referral_sponsor_bonus_xof(before),
                "referral_referred_bonus_xof": get_referral_referred_bonus_xof(before),
                "referral_share_base_url": before.get("referral_share_base_url"),
                "referral_allowed_roles": get_referral_allowed_roles(before),
                "referral_sponsor_allowed_roles": get_referral_sponsor_allowed_roles(before),
                "referral_referred_allowed_roles": get_referral_referred_allowed_roles(before),
                "referral_apply_metric": get_referral_apply_metric(before),
                "referral_apply_max_count": get_referral_apply_max_count(before),
                "referral_reward_metric": get_referral_reward_metric(before),
                "referral_reward_count": get_referral_reward_count(before),
            },
            "after": {
                "referral_enabled": after.get("referral_enabled", True),
                "referral_bonus_xof": get_referral_referred_bonus_xof(after),
                "referral_sponsor_bonus_xof": get_referral_sponsor_bonus_xof(after),
                "referral_referred_bonus_xof": get_referral_referred_bonus_xof(after),
                "referral_share_base_url": after.get("referral_share_base_url"),
                "referral_allowed_roles": get_referral_allowed_roles(after),
                "referral_sponsor_allowed_roles": get_referral_sponsor_allowed_roles(after),
                "referral_referred_allowed_roles": get_referral_referred_allowed_roles(after),
                "referral_apply_metric": get_referral_apply_metric(after),
                "referral_apply_max_count": get_referral_apply_max_count(after),
                "referral_reward_metric": get_referral_reward_metric(after),
                "referral_reward_count": get_referral_reward_count(after),
            },
        },
    )
    return {
        "referral_enabled": is_referral_globally_enabled(after),
        "referral_bonus_xof": get_referral_referred_bonus_xof(after),
        "referral_sponsor_bonus_xof": get_referral_sponsor_bonus_xof(after),
        "referral_referred_bonus_xof": get_referral_referred_bonus_xof(after),
        "referral_share_base_url": get_referral_share_base_url(after),
        "effective_referral_share_base_url": get_effective_referral_share_base_url(after),
        "referral_allowed_roles": get_referral_allowed_roles(after),
        "referral_sponsor_allowed_roles": get_referral_sponsor_allowed_roles(after),
        "referral_referred_allowed_roles": get_referral_referred_allowed_roles(after),
        "referral_apply_metric": get_referral_apply_metric(after),
        "referral_apply_max_count": get_referral_apply_max_count(after),
        "referral_apply_rule": describe_referral_apply_rule(after),
        "referral_reward_metric": get_referral_reward_metric(after),
        "referral_reward_count": get_referral_reward_count(after),
        "referral_reward_rule": describe_referral_reward_rule(after),
        "referral_metric_options": get_referral_metric_options(),
        "message": "Configuration du parrainage mise a jour",
    }
