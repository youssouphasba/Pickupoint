"""
Router deliveries : missions de livraison pour les drivers.
"""
import math
import random
import re
import uuid
from calendar import monthrange
from datetime import datetime, timezone, timedelta

from typing import Optional
from fastapi import APIRouter, Body, Depends, Query, Request
from pymongo import ReturnDocument

from config import settings
from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, bad_request_exception, forbidden_exception
from database import db
from models.common import UserRole, ParcelStatus
from models.delivery import MissionStatus, LocationUpdate
from pydantic import BaseModel, Field
from services.parcel_service import (
    _record_event,
    _find_candidate_drivers_within_radius,
    get_assigned_mission_auto_release_minutes,
    get_delivery_dispatch_settings,
    resolve_delivery_dispatch_state,
    transition_status,
)
from services.admin_events_service import AdminEventType, record_admin_event
from services.google_maps_service import get_directions_eta
from services.performance_rewards_service import get_performance_rewards_settings
from services.ranking_service import refresh_driver_stats_for_period
from services.notification_service import (
    notify_approaching_driver,
    notify_new_mission_dispatch_wave,
    notify_pending_mission_dispatch_reminder,
    notify_sender_driver_assigned,
    notify_sender_parcel_collected,
)
from services.wallet_service import (
    compute_delivery_commission_breakdown,
    credit_wallet,
    debit_wallet,
)
from services.whatsapp_call_service import (
    connect_driver_whatsapp_call,
    ensure_driver_call_permission_request,
    get_driver_call_permission,
    terminate_driver_whatsapp_call,
)
from core.limiter import limiter
from core.utils import check_code_lockout, record_failed_attempt, clear_code_attempts, mask_phone, phone_suffix

router = APIRouter()

_DISPATCH_HIDDEN_PARCEL_STATUSES = {
    ParcelStatus.CANCELLED.value,
    ParcelStatus.RETURNED.value,
    ParcelStatus.DELIVERED.value,
    ParcelStatus.EXPIRED.value,
    ParcelStatus.DISPUTED.value,
    ParcelStatus.SUSPENDED.value,
}


def _as_aware_utc(value: Optional[datetime]) -> Optional[datetime]:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _mission_id() -> str:
    return f"msn_{uuid.uuid4().hex[:12]}"


def _return_code() -> str:
    return f"{random.randint(100000, 999999)}"


def _period_or_current(period: str = "") -> str:
    if period:
        return period
    now = datetime.now(timezone.utc)
    return f"{now.year}-{now.month:02d}"


def _period_bounds(period: str) -> tuple[datetime, datetime]:
    year, month = map(int, period.split("-"))
    _, last_day = monthrange(year, month)
    return (
        datetime(year, month, 1, tzinfo=timezone.utc),
        datetime(year, month, last_day, 23, 59, 59, 999000, tzinfo=timezone.utc),
    )


def _driver_has_profile_photo(current_user: dict) -> bool:
    return bool((current_user.get("profile_picture_url") or "").strip()) and (
        current_user.get("profile_picture_status") == "approved"
    )


def _mission_commission_xof(parcel: Optional[dict], mission: Optional[dict] = None) -> float:
    breakdown = compute_delivery_commission_breakdown(parcel, mission)
    return float(breakdown["total_commission_xof"])


async def _attach_commission_requirements(missions: list[dict]) -> None:
    parcel_ids = [m.get("parcel_id") for m in missions if m.get("parcel_id")]
    parcel_lookup: dict[str, dict] = {}
    if parcel_ids:
        cursor = db.parcels.find(
            {"parcel_id": {"$in": list(set(parcel_ids))}},
            {"_id": 0, "parcel_id": 1, "paid_price": 1, "quoted_price": 1},
        )
        parcels = await cursor.to_list(length=len(set(parcel_ids)))
        parcel_lookup = {p["parcel_id"]: p for p in parcels}

    for mission in missions:
        breakdown = compute_delivery_commission_breakdown(
            parcel_lookup.get(mission.get("parcel_id")),
            mission,
        )
        mission["platform_commission_xof"] = mission.get(
            "platform_commission_xof",
            breakdown["platform_commission_xof"],
        )
        mission["relay_commission_xof"] = mission.get(
            "relay_commission_xof",
            breakdown["relay_commission_xof"],
        )
        mission["origin_relay_commission_xof"] = mission.get(
            "origin_relay_commission_xof",
            breakdown["origin_relay_commission_xof"],
        )
        mission["destination_relay_commission_xof"] = mission.get(
            "destination_relay_commission_xof",
            breakdown["destination_relay_commission_xof"],
        )
        mission["total_commission_xof"] = mission.get(
            "total_commission_xof",
            breakdown["total_commission_xof"],
        )
        mission["wallet_balance_required_xof"] = mission.get(
            "wallet_balance_required_xof",
            breakdown["wallet_balance_required_xof"],
        )


def _mask_recipient_phone_for_driver(missions: list[dict], current_user: dict) -> None:
    if current_user.get("role") != UserRole.DRIVER.value:
        return
    for mission in missions:
        if mission.get("recipient_phone"):
            mission["recipient_phone"] = mask_phone(mission["recipient_phone"])


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng / 2) ** 2
    return R * 2 * math.asin(math.sqrt(a))


def _normalize_geopin(source: Optional[dict]) -> Optional[dict]:
    if not source:
        return None
    geopin = source.get("geopin") or source
    lat = geopin.get("lat")
    lng = geopin.get("lng")
    if lat is None or lng is None:
        return None
    return {
        "lat": float(lat),
        "lng": float(lng),
        "accuracy": geopin.get("accuracy"),
    }


def _format_distance_text(distance_meters: Optional[float]) -> Optional[str]:
    if distance_meters is None:
        return None
    if distance_meters < 1000:
        return f"{round(distance_meters)} m"
    return f"{distance_meters / 1000:.1f} km"


def _format_duration_text(duration_seconds: Optional[int]) -> Optional[str]:
    if duration_seconds is None:
        return None
    if duration_seconds < 3600:
        minutes = max(1, math.ceil(duration_seconds / 60))
        return f"{minutes} min"
    hours = duration_seconds // 3600
    minutes = math.ceil((duration_seconds % 3600) / 60)
    if minutes == 60:
        hours += 1
        minutes = 0
    if minutes == 0:
        return f"{hours} h"
    return f"{hours} h {minutes:02d}"


def _attach_pickup_confirmation_window(
    mission: dict,
    *,
    auto_release_minutes: int,
    now: Optional[datetime] = None,
) -> None:
    mission["pickup_confirmation_timeout_minutes"] = int(auto_release_minutes)
    assigned_at = _as_aware_utc(mission.get("assigned_at"))
    if assigned_at is None:
        mission["pickup_confirmation_deadline_at"] = None
        mission["pickup_confirmation_remaining_seconds"] = None
        return

    deadline_at = assigned_at + timedelta(minutes=auto_release_minutes)
    mission["pickup_confirmation_deadline_at"] = deadline_at.isoformat()

    if (
        mission.get("status") != MissionStatus.ASSIGNED.value
        or mission.get("started_at") is not None
    ):
        mission["pickup_confirmation_remaining_seconds"] = None
        return

    reference_now = _as_aware_utc(now) or datetime.now(timezone.utc)
    remaining_seconds = max(
        0,
        int((deadline_at - reference_now).total_seconds()),
    )
    mission["pickup_confirmation_remaining_seconds"] = remaining_seconds


def _can_driver_preview_pending_mission(
    mission: dict,
    driver_user_id: str,
    lat: Optional[float],
    lng: Optional[float],
) -> bool:
    if mission.get("status") != MissionStatus.PENDING.value:
        return False

    if mission.get("is_broadcast"):
        return True

    candidates = mission.get("candidate_drivers") or []
    notified_driver_ids = mission.get("dispatch_notified_driver_ids") or []
    if driver_user_id not in candidates and driver_user_id not in notified_driver_ids:
        return False

    pickup_geopin = _normalize_geopin(mission.get("pickup_geopin"))
    if pickup_geopin is None or lat is None or lng is None:
        return True

    dispatch_radius_km = mission.get("dispatch_radius_km")
    if dispatch_radius_km is None:
        dispatch_radius_km = 10.0 if mission.get("is_broadcast") else 5.0

    distance_km = _haversine_km(
        lat,
        lng,
        pickup_geopin["lat"],
        pickup_geopin["lng"],
    )
    return distance_km <= float(dispatch_radius_km)


def _merge_driver_ids(existing: list[str], incoming: list[str]) -> list[str]:
    merged: list[str] = []
    seen: set[str] = set()
    for driver_id in [*(existing or []), *(incoming or [])]:
        if not driver_id or driver_id in seen:
            continue
        seen.add(driver_id)
        merged.append(driver_id)
    return merged


async def _filter_dispatchable_pending_missions(
    missions: list[dict],
    *,
    cleanup_stale: bool = False,
) -> list[dict]:
    parcel_ids = list({mission.get("parcel_id") for mission in missions if mission.get("parcel_id")})
    if not parcel_ids:
        return missions

    parcels_cursor = db.parcels.find(
        {"parcel_id": {"$in": parcel_ids}},
        {"_id": 0, "parcel_id": 1, "status": 1},
    )
    parcel_rows = await parcels_cursor.to_list(length=len(parcel_ids))
    parcel_statuses = {
        row["parcel_id"]: row.get("status")
        for row in parcel_rows
        if row.get("parcel_id")
    }

    stale_mission_ids = [
        mission["mission_id"]
        for mission in missions
        if parcel_statuses.get(mission.get("parcel_id")) in _DISPATCH_HIDDEN_PARCEL_STATUSES
        and mission.get("mission_id")
    ]
    if cleanup_stale and stale_mission_ids:
        now = datetime.now(timezone.utc)
        await db.delivery_missions.update_many(
            {
                "mission_id": {"$in": stale_mission_ids},
                "status": MissionStatus.PENDING.value,
            },
            {
                "$set": {
                    "status": MissionStatus.CANCELLED.value,
                    "failure_reason": "parcel_not_dispatchable",
                    "completed_at": now,
                    "updated_at": now,
                    "is_broadcast": False,
                }
            },
        )

    return [
        mission
        for mission in missions
        if parcel_statuses.get(mission.get("parcel_id")) not in _DISPATCH_HIDDEN_PARCEL_STATUSES
    ]


async def _eligible_driver_ids_for_dispatch_stage(
    mission: dict,
    dispatch_state: dict,
    pickup_geopin: Optional[dict],
) -> list[str]:
    requested_driver_id = mission.get("admin_requested_driver_id")
    if requested_driver_id:
        return [requested_driver_id]
    if not pickup_geopin:
        return []
    return await _find_candidate_drivers_within_radius(
        pickup_geopin["lat"],
        pickup_geopin["lng"],
        dispatch_state["radius_km"],
    )


async def _notify_driver_when_entering_dispatch_radius(
    *,
    driver_user_id: str,
    lat: float,
    lng: float,
    now: datetime,
) -> int:
    cursor = db.delivery_missions.find(
        {"status": MissionStatus.PENDING.value},
        {"_id": 0},
    )
    pending_missions = await cursor.to_list(length=200)
    pending_missions = await _filter_dispatchable_pending_missions(
        pending_missions,
        cleanup_stale=True,
    )
    notified_count = 0

    for mission in pending_missions:
        requested_driver_id = mission.get("admin_requested_driver_id")
        if requested_driver_id and requested_driver_id != driver_user_id:
            continue

        pickup_geopin = _normalize_geopin(mission.get("pickup_geopin"))
        if pickup_geopin is None:
            continue

        dispatch_settings = mission.get("delivery_dispatch")
        if not dispatch_settings:
            dispatch_settings = await get_delivery_dispatch_settings()

        dispatch_started_at = _as_aware_utc(mission.get("dispatch_started_at")) or _as_aware_utc(
            mission.get("created_at")
        ) or now
        dispatch_state = resolve_delivery_dispatch_state(
            dispatch_settings,
            dispatch_started_at,
            now=now,
        )

        distance_km = _haversine_km(
            lat,
            lng,
            pickup_geopin["lat"],
            pickup_geopin["lng"],
        )
        if distance_km > float(dispatch_state["radius_km"]):
            continue

        notified_driver_ids = list(mission.get("dispatch_notified_driver_ids") or [])
        candidate_drivers = list(mission.get("candidate_drivers") or [])
        if driver_user_id in notified_driver_ids or driver_user_id in candidate_drivers:
            continue

        notified_driver_ids = _merge_driver_ids(notified_driver_ids, [driver_user_id])
        candidate_drivers = _merge_driver_ids(candidate_drivers, [driver_user_id])
        updates = {
            "updated_at": now,
            "delivery_dispatch": dispatch_settings,
            "dispatch_stage_index": dispatch_state["stage_index"],
            "dispatch_radius_km": dispatch_state["radius_km"],
            "dispatch_next_escalation_at": dispatch_state["next_escalation_at"],
            "dispatch_notified_driver_ids": notified_driver_ids,
            "candidate_drivers": candidate_drivers,
            "is_broadcast": dispatch_state["is_final_stage"],
            "ping_expires_at": dispatch_state["next_escalation_at"],
            "ping_index": 0,
        }
        await db.delivery_missions.update_one(
            {"mission_id": mission["mission_id"], "status": MissionStatus.PENDING.value},
            {"$set": updates},
        )
        updated_mission = {**mission, **updates}
        await notify_new_mission_dispatch_wave(
            user_ids=[driver_user_id],
            mission=updated_mission,
            radius_km=dispatch_state["radius_km"],
        )
        notified_count += 1

    return notified_count


async def advance_pending_delivery_dispatch() -> int:
    """
    Fait progresser le dispatch en cascade hors du flux HTTP.
    Retourne le nombre de missions mises à jour.
    """
    now = datetime.now(timezone.utc)
    cursor = db.delivery_missions.find({"status": MissionStatus.PENDING.value}, {"_id": 0})
    raw_missions = await cursor.to_list(length=200)
    raw_missions = await _filter_dispatchable_pending_missions(
        raw_missions,
        cleanup_stale=True,
    )
    updated_count = 0
    reminder_interval = timedelta(minutes=5)

    for mission in raw_missions:
        pickup_geopin = _normalize_geopin(mission.get("pickup_geopin"))
        dispatch_settings = mission.get("delivery_dispatch")
        if not dispatch_settings:
            dispatch_settings = await get_delivery_dispatch_settings()

        dispatch_started_at = _as_aware_utc(mission.get("dispatch_started_at")) or _as_aware_utc(
            mission.get("created_at")
        ) or now
        dispatch_state = resolve_delivery_dispatch_state(
            dispatch_settings,
            dispatch_started_at,
            now=now,
        )

        notified_driver_ids = list(mission.get("dispatch_notified_driver_ids") or [])
        candidate_drivers = list(mission.get("candidate_drivers") or [])
        new_driver_ids: list[str] = []
        updates: dict[str, object] = {}

        ping_expires_at = _as_aware_utc(mission.get("ping_expires_at"))
        dispatch_next_escalation_at = _as_aware_utc(mission.get("dispatch_next_escalation_at"))
        next_escalation_at = dispatch_next_escalation_at or ping_expires_at
        should_escalate = next_escalation_at is not None and now > next_escalation_at

        if should_escalate:
            eligible_driver_ids = await _eligible_driver_ids_for_dispatch_stage(
                mission,
                dispatch_state,
                pickup_geopin,
            )
            new_driver_ids = [
                driver_id for driver_id in eligible_driver_ids if driver_id not in notified_driver_ids
            ]
            notified_driver_ids = _merge_driver_ids(notified_driver_ids, new_driver_ids)
            candidate_drivers = _merge_driver_ids(candidate_drivers, eligible_driver_ids)
            updates.update({
                "updated_at": now,
                "delivery_dispatch": dispatch_settings,
                "dispatch_stage_index": dispatch_state["stage_index"],
                "dispatch_radius_km": dispatch_state["radius_km"],
                "dispatch_next_escalation_at": dispatch_state["next_escalation_at"],
                "dispatch_notified_driver_ids": notified_driver_ids,
                "candidate_drivers": candidate_drivers,
                "is_broadcast": dispatch_state["is_final_stage"],
                "ping_expires_at": dispatch_state["next_escalation_at"],
                "ping_index": 0,
            })

        last_reminder_at = _as_aware_utc(mission.get("dispatch_last_reminder_at"))
        should_send_reminder = (
            last_reminder_at is None or now - last_reminder_at >= reminder_interval
        )
        reminder_driver_ids: list[str] = []
        if should_send_reminder:
            reminder_driver_ids = await _eligible_driver_ids_for_dispatch_stage(
                {**mission, **updates},
                dispatch_state,
                pickup_geopin,
            )
            if reminder_driver_ids:
                notified_driver_ids = _merge_driver_ids(notified_driver_ids, reminder_driver_ids)
                candidate_drivers = _merge_driver_ids(candidate_drivers, reminder_driver_ids)
                updates.update({
                    "updated_at": now,
                    "delivery_dispatch": dispatch_settings,
                    "dispatch_stage_index": dispatch_state["stage_index"],
                    "dispatch_radius_km": dispatch_state["radius_km"],
                    "dispatch_next_escalation_at": dispatch_state["next_escalation_at"],
                    "dispatch_notified_driver_ids": notified_driver_ids,
                    "candidate_drivers": candidate_drivers,
                    "is_broadcast": dispatch_state["is_final_stage"],
                    "ping_expires_at": dispatch_state["next_escalation_at"],
                    "ping_index": 0,
                    "dispatch_last_reminder_at": now,
                })

        if updates:
            await db.delivery_missions.update_one(
                {"mission_id": mission["mission_id"]},
                {"$set": updates},
            )
            updated_count += 1

        updated_mission = {**mission, **updates}
        if new_driver_ids:
            await notify_new_mission_dispatch_wave(
                user_ids=new_driver_ids,
                mission=updated_mission,
                radius_km=dispatch_state["radius_km"],
            )
        if reminder_driver_ids:
            reminder_targets = [
                driver_id for driver_id in reminder_driver_ids if driver_id not in new_driver_ids
            ]
            if reminder_targets:
                await notify_pending_mission_dispatch_reminder(
                    user_ids=reminder_targets,
                    mission=updated_mission,
                    radius_km=dispatch_state["radius_km"],
                )

    return updated_count


@router.get("/available", summary="Missions disponibles (drivers)")
async def available_missions(
    lat:       Optional[float] = Query(None, description="Latitude du livreur"),
    lng:       Optional[float] = Query(None, description="Longitude du livreur"),
    radius_km: float           = Query(5.0,  description="Rayon de recherche en km"),
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    """
    Retourne les missions en attente, triées par distance au pickup.
    Gère le Dispatch en Cascade (Phase 7).
    """
    user_id = current_user["user_id"]
    if current_user["role"] == UserRole.DRIVER.value and not _driver_has_profile_photo(current_user):
        return {
            "missions": [],
            "driver_lat": lat,
            "driver_lng": lng,
            "radius_km": radius_km,
            "profile_photo_required": True,
        }
    
    # On récupère toutes les missions PENDING
    cursor = db.delivery_missions.find({"status": MissionStatus.PENDING.value}, {"_id": 0})
    raw_missions = await cursor.to_list(length=200)
    if raw_missions:
        parcel_ids = list({mission.get("parcel_id") for mission in raw_missions if mission.get("parcel_id")})
        if parcel_ids:
            parcels_cursor = db.parcels.find(
                {"parcel_id": {"$in": parcel_ids}},
                {"_id": 0, "parcel_id": 1, "status": 1},
            )
            parcel_rows = await parcels_cursor.to_list(length=len(parcel_ids))
            parcel_statuses = {row["parcel_id"]: row.get("status") for row in parcel_rows if row.get("parcel_id")}
            hidden_statuses = {
                ParcelStatus.CANCELLED.value,
                ParcelStatus.RETURNED.value,
                ParcelStatus.DELIVERED.value,
                ParcelStatus.EXPIRED.value,
                ParcelStatus.DISPUTED.value,
                ParcelStatus.SUSPENDED.value,
            }
            raw_missions = [
                mission
                for mission in raw_missions
                if parcel_statuses.get(mission.get("parcel_id")) not in hidden_statuses
            ]

    filtered_missions = []
    
    for m in raw_missions:
        # Filtrage pour le livreur actuel
        if m.get("is_broadcast"):
            filtered_missions.append(m)
        else:
            candidates = m.get("candidate_drivers") or []
            ping_idx = m.get("ping_index", 0)
            if ping_idx < len(candidates) and candidates[ping_idx] == user_id:
                filtered_missions.append(m)
            elif not candidates: # Sécurité : si pas de candidats calculés mais pas is_broadcast
                filtered_missions.append(m)

    missions = filtered_missions

    if current_user["role"] != UserRole.DRIVER.value:
        missions = raw_missions
    elif lat is None or lng is None:
        missions = [
            mission
            for mission in raw_missions
            if mission.get("is_broadcast")
            or user_id in (mission.get("dispatch_notified_driver_ids") or [])
            or user_id in (mission.get("candidate_drivers") or [])
        ]
    else:
        visible_missions = []
        for mission in raw_missions:
            if current_user["role"] == UserRole.DRIVER.value and not mission.get("is_broadcast"):
                candidates = mission.get("candidate_drivers") or []
                ping_idx = mission.get("ping_index", 0)
                requested_driver_id = mission.get("admin_requested_driver_id")
                is_targeted_driver = requested_driver_id == user_id
                is_current_candidate = ping_idx < len(candidates) and candidates[ping_idx] == user_id
                if not is_targeted_driver and not is_current_candidate:
                    continue
            pickup_geopin = _normalize_geopin(mission.get("pickup_geopin"))
            dispatch_radius_km = mission.get("dispatch_radius_km")
            if dispatch_radius_km is None:
                dispatch_radius_km = 10.0 if mission.get("is_broadcast") else radius_km

            if pickup_geopin:
                distance_km = _haversine_km(
                    lat,
                    lng,
                    pickup_geopin["lat"],
                    pickup_geopin["lng"],
                )
                if distance_km <= float(dispatch_radius_km):
                    mission["distance_km"] = round(distance_km, 2)
                    visible_missions.append(mission)
            else:
                mission["distance_km"] = None
                visible_missions.append(mission)
        missions = visible_missions

    if lat is not None and lng is not None:
        result = []
        for m in missions:
            if current_user["role"] == UserRole.DRIVER.value and "distance_km" in m:
                result.append(m)
                continue
            geopin = m.get("pickup_geopin") or {}
            plat   = geopin.get("lat")
            plng   = geopin.get("lng")
            if plat is not None and plng is not None:
                dist = _haversine_km(lat, lng, plat, plng)
                if dist <= radius_km:
                    m["distance_km"] = round(dist, 2)
                    result.append(m)
            else:
                # Pickup sans coordonnées (relay sans geopin) → inclus sans filtre
                m["distance_km"] = None
                result.append(m)
        # Trier : missions avec distance connue en premier (croissant), puis sans coordonnées
        result.sort(key=lambda m: m.get("distance_km") if m.get("distance_km") is not None else 9999)
        await _attach_commission_requirements(result)
        _mask_recipient_phone_for_driver(result, current_user)
        return {"missions": result, "driver_lat": lat, "driver_lng": lng, "radius_km": radius_km}

    if current_user["role"] == UserRole.DRIVER.value:
        return {
            "missions": [],
            "driver_lat": None,
            "driver_lng": None,
            "radius_km": None,
            "gps_required": True,
        }

    _mask_recipient_phone_for_driver(missions, current_user)
    missions.sort(key=lambda m: m["created_at"])
    await _attach_commission_requirements(missions)
    return {"missions": missions, "driver_lat": None, "driver_lng": None, "radius_km": None}


@router.get("/my", summary="Mes missions (driver)")
async def my_missions(
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    cursor = db.delivery_missions.find(
        {"driver_id": current_user["user_id"]},
        {"_id": 0},
    ).sort("created_at", -1).limit(50)
    missions = await cursor.to_list(length=50)
    auto_release_minutes = await get_assigned_mission_auto_release_minutes()
    for mission in missions:
        _attach_pickup_confirmation_window(
            mission,
            auto_release_minutes=auto_release_minutes,
        )
    await _attach_commission_requirements(missions)
    
    # Masquage numéro destinataire — révélé seulement si :
    #   - livraison à domicile (*_to_home) ET driver est à proximité (approaching_notified)
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin:
        for m in missions:
            if m.get("recipient_phone"):
                m["recipient_phone"] = mask_phone(m["recipient_phone"])
                
    return {"missions": missions}


@router.get("/{mission_id}/preview", summary="Aperçu d'une mission disponible")
async def mission_preview(
    mission_id: str,
    lat: Optional[float] = Query(None, description="Latitude courante du livreur"),
    lng: Optional[float] = Query(None, description="Longitude courante du livreur"),
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")

    if current_user["role"] == UserRole.DRIVER.value:
        if not _driver_has_profile_photo(current_user):
            raise bad_request_exception(
                "Votre photo de profil doit être ajoutée puis approuvée avant de recevoir des missions."
            )
        if not _can_driver_preview_pending_mission(
            mission,
            current_user["user_id"],
            lat,
            lng,
        ):
            raise forbidden_exception("Cette course n'est plus disponible pour vous.")

    await _attach_commission_requirements([mission])
    _mask_recipient_phone_for_driver([mission], current_user)

    pickup_geopin = _normalize_geopin(mission.get("pickup_geopin"))
    delivery_geopin = _normalize_geopin(mission.get("delivery_geopin"))

    pickup_distance_km: Optional[float] = None
    pickup_distance_text: Optional[str] = None
    pickup_eta_seconds: Optional[int] = None
    pickup_eta_text: Optional[str] = None

    if lat is not None and lng is not None and pickup_geopin is not None:
        pickup_distance_km = round(
            _haversine_km(lat, lng, pickup_geopin["lat"], pickup_geopin["lng"]),
            2,
        )
        pickup_distance_text = f"{pickup_distance_km:.1f} km"
        pickup_route = await get_directions_eta(
            lat,
            lng,
            pickup_geopin["lat"],
            pickup_geopin["lng"],
        )
        if pickup_route:
            pickup_distance_text = pickup_route.get("distance_text") or pickup_distance_text
            pickup_eta_seconds = pickup_route.get("duration_seconds")
            pickup_eta_text = pickup_route.get("duration_text")

    delivery_distance_km: Optional[float] = None
    delivery_distance_text: Optional[str] = None
    delivery_eta_seconds: Optional[int] = None
    delivery_eta_text: Optional[str] = None

    if pickup_geopin is not None and delivery_geopin is not None:
        delivery_distance_km = round(
            _haversine_km(
                pickup_geopin["lat"],
                pickup_geopin["lng"],
                delivery_geopin["lat"],
                delivery_geopin["lng"],
            ),
            2,
        )
        delivery_distance_text = f"{delivery_distance_km:.1f} km"
        delivery_route = await get_directions_eta(
            pickup_geopin["lat"],
            pickup_geopin["lng"],
            delivery_geopin["lat"],
            delivery_geopin["lng"],
        )
        if delivery_route:
            delivery_distance_text = delivery_route.get("distance_text") or delivery_distance_text
            delivery_eta_seconds = delivery_route.get("duration_seconds")
            delivery_eta_text = delivery_route.get("duration_text")

    total_distance_km: Optional[float] = None
    total_eta_seconds: Optional[int] = None
    if pickup_distance_km is not None or delivery_distance_km is not None:
        total_distance_km = round((pickup_distance_km or 0.0) + (delivery_distance_km or 0.0), 2)
    if pickup_eta_seconds is not None or delivery_eta_seconds is not None:
        total_eta_seconds = (pickup_eta_seconds or 0) + (delivery_eta_seconds or 0)

    pickup_distance_meters = pickup_distance_km * 1000 if pickup_distance_km is not None else None
    delivery_distance_meters = delivery_distance_km * 1000 if delivery_distance_km is not None else None
    total_distance_meters = total_distance_km * 1000 if total_distance_km is not None else None

    if pickup_distance_text is None:
        pickup_distance_text = _format_distance_text(pickup_distance_meters)
    if delivery_distance_text is None:
        delivery_distance_text = _format_distance_text(delivery_distance_meters)

    return {
        "mission": mission,
        "preview": {
            "pickup_distance_km": pickup_distance_km,
            "pickup_distance_text": pickup_distance_text,
            "pickup_eta_seconds": pickup_eta_seconds,
            "pickup_eta_text": pickup_eta_text,
            "delivery_distance_km": delivery_distance_km,
            "delivery_distance_text": delivery_distance_text,
            "delivery_eta_seconds": delivery_eta_seconds,
            "delivery_eta_text": delivery_eta_text,
            "total_distance_km": total_distance_km,
            "total_distance_text": _format_distance_text(total_distance_meters),
            "total_eta_seconds": total_eta_seconds,
            "total_eta_text": _format_duration_text(total_eta_seconds),
        },
    }

class ConfirmPickupRequest(BaseModel):
    code: str
    lat: Optional[float] = Field(None, ge=-90, le=90)
    lng: Optional[float] = Field(None, ge=-180, le=180)


class WhatsAppCallConnectRequest(BaseModel):
    sdp_offer: str = Field(..., min_length=20, description="Offre SDP WebRTC générée par l'app livreur")

@router.post("/{mission_id}/confirm-pickup", summary="Confirmer collecte avec code")
@limiter.limit("10/minute")
async def confirm_pickup(
    mission_id: str,
    body: ConfirmPickupRequest,
    request: Request,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    if mission["status"] != MissionStatus.ASSIGNED.value:
        raise bad_request_exception("La mission doit être assignée avant confirmation de collecte")
    if current_user["role"] not in {UserRole.ADMIN.value, UserRole.SUPERADMIN.value} and mission.get("driver_id") != current_user["user_id"]:
        raise forbidden_exception("Seul le livreur assigné peut confirmer la collecte")
    
    parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    # Si expéditeur/relais a renseigné un code, vérifier :
    if parcel.get("status") == ParcelStatus.SUSPENDED.value:
        raise forbidden_exception("Ce colis est suspendu par l'administration. Collecte impossible.")

    await check_code_lockout(db, parcel["parcel_id"], "pickup_code")
    if parcel.get("pickup_code", "") != body.code.strip():
        await record_failed_attempt(db, parcel["parcel_id"], "pickup_code")
        raise bad_request_exception("Code de collecte invalide")
    await clear_code_attempts(db, parcel["parcel_id"], "pickup_code")

    # Vérification proximité : driver doit être proche du point de collecte (< 500m)
    if body.lat is not None and body.lng is not None and not (parcel.get("is_simulation") and settings.DEBUG):
        from services.pricing_service import _haversine_km
        pickup_geopin = None
        mode = parcel.get("delivery_mode", "")
        if mode.startswith("home_to"):
            # Collecte chez l'expéditeur
            pickup_geopin = (parcel.get("pickup_address") or {}).get("geopin")
        else:
            # Collecte au relais d'origine
            origin_relay_id = parcel.get("origin_relay_id")
            if origin_relay_id:
                relay = await db.relay_points.find_one({"relay_id": origin_relay_id}, {"location": 1})
                if relay and relay.get("location"):
                    pickup_geopin = relay["location"]
        if pickup_geopin and pickup_geopin.get("lat") and pickup_geopin.get("lng"):
            dist_m = _haversine_km(body.lat, body.lng, pickup_geopin["lat"], pickup_geopin["lng"]) * 1000
            if dist_m > 500:
                raise bad_request_exception(
                    f"Vous êtes à {int(dist_m)}m du point de collecte. Rapprochez-vous à moins de 500m."
                )

    now = datetime.now(timezone.utc)
    # 1. Mettre à jour la mission "in_progress"
    await db.delivery_missions.update_one(
        {"mission_id": mission_id},
        {"$set": {
            "status": MissionStatus.IN_PROGRESS.value,
            "started_at": now,
            "updated_at":  now,
        }},
    )
    # 2. Transition colis IN_TRANSIT ou OUT_FOR_DELIVERY
    actor = {"actor_id": current_user["user_id"], "actor_role": current_user["role"]}
    p_status = parcel["status"]
    
    if p_status == ParcelStatus.CREATED.value:
        delivery_mode = (parcel.get("delivery_mode") or "").strip()
        if delivery_mode.endswith("_to_home"):
            await transition_status(
                parcel["parcel_id"],
                ParcelStatus.OUT_FOR_DELIVERY,
                notes="Pick-up expéditeur (vers domicile)",
                **actor,
            )
        else:
            await transition_status(
                parcel["parcel_id"],
                ParcelStatus.IN_TRANSIT,
                notes="Pick-up expéditeur (en transit)",
                **actor,
            )
    elif p_status in [ParcelStatus.AT_DESTINATION_RELAY.value, ParcelStatus.AVAILABLE_AT_RELAY.value]:
        await transition_status(parcel["parcel_id"], ParcelStatus.OUT_FOR_DELIVERY, notes="Pick-up depuis relais destination", **actor)
    elif p_status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value:
        # R2H et R2R : driver quitte le relais origine → IN_TRANSIT
        await transition_status(parcel["parcel_id"], ParcelStatus.IN_TRANSIT, notes="Pick-up au relais origine", **actor)

    await notify_sender_parcel_collected(parcel)

    return {"message": "Collecte confirmée", "mission_id": mission_id}


@router.get("/{mission_id}", summary="Détail mission")
async def get_mission(
    mission_id: str,
    current_user: dict = Depends(get_current_user),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin and mission.get("driver_id") != current_user["user_id"]:
        raise forbidden_exception("Accès refusé à cette mission")
    
    parcel = await db.parcels.find_one(
        {"parcel_id": mission["parcel_id"]},
        {
            "_id": 0,
            "status": 1,
            "payment_status": 1,
            "payment_method": 1,
            "who_pays": 1,
            "payment_override": 1,
            "pickup_voice_note": 1,
            "delivery_voice_note": 1,
            "driver_bonus_xof": 1,
            "paid_price": 1,
            "quoted_price": 1,
        },
    )
    if parcel:
        breakdown = compute_delivery_commission_breakdown(parcel, mission)
        mission["platform_commission_xof"] = mission.get(
            "platform_commission_xof",
            breakdown["platform_commission_xof"],
        )
        mission["relay_commission_xof"] = mission.get(
            "relay_commission_xof",
            breakdown["relay_commission_xof"],
        )
        mission["origin_relay_commission_xof"] = mission.get(
            "origin_relay_commission_xof",
            breakdown["origin_relay_commission_xof"],
        )
        mission["destination_relay_commission_xof"] = mission.get(
            "destination_relay_commission_xof",
            breakdown["destination_relay_commission_xof"],
        )
        mission["total_commission_xof"] = mission.get(
            "total_commission_xof",
            breakdown["total_commission_xof"],
        )
        mission["wallet_balance_required_xof"] = mission.get(
            "wallet_balance_required_xof",
            breakdown["wallet_balance_required_xof"],
        )
        mission["parcel_status"] = parcel.get("status")
        mission["payment_status"] = parcel.get("payment_status", "pending")
        mission["payment_method"] = mission.get("payment_method") or parcel.get("payment_method")
        mission["who_pays"] = mission.get("who_pays") or parcel.get("who_pays")
        mission["payment_override"] = bool(parcel.get("payment_override"))
        mission["pickup_voice_note"] = mission.get("pickup_voice_note") or parcel.get("pickup_voice_note")
        mission["delivery_voice_note"] = mission.get("delivery_voice_note") or parcel.get("delivery_voice_note")
        mission["driver_bonus_xof"] = float(parcel.get("driver_bonus_xof", 0.0))
        mission["delivery_blocked_by_payment"] = False

    _attach_pickup_confirmation_window(
        mission,
        auto_release_minutes=await get_assigned_mission_auto_release_minutes(),
    )

    # Enrichissement Photos
    # Driver
    if mission.get("driver_id"):
        driver = await db.users.find_one(
            {"user_id": mission["driver_id"]},
            {"name": 1, "phone": 1, "profile_picture_url": 1},
        )
        if driver:
            mission["driver_name"] = driver.get("name")
            mission["driver_phone"] = driver.get("phone")
            mission["driver_photo_url"] = driver.get("profile_picture_url")
    
    # Sender
    sender = await db.users.find_one(
        {"user_id": mission.get("sender_user_id")},
        {"name": 1, "profile_picture_url": 1},
    )
    if sender:
        mission["sender_name"] = sender.get("name")
        mission["sender_photo_url"] = sender.get("profile_picture_url")
    
    # Recipient
    recipient_uid = mission.get("recipient_user_id")
    if not recipient_uid and mission.get("recipient_phone"):
        phone = mission["recipient_phone"]
        suffix = phone_suffix(phone)
        phone_query = {"phone": phone}
        if suffix:
            phone_query = {
                "$or": [
                    {"phone": phone},
                    {"phone": {"$regex": f"{re.escape(suffix)}$"}},
                ]
            }
        recipient_user = await db.users.find_one(phone_query, {"profile_picture_url": 1})
        if recipient_user:
            mission["recipient_photo_url"] = recipient_user.get("profile_picture_url")
    elif recipient_uid:
        recipient_user = await db.users.find_one({"user_id": recipient_uid}, {"profile_picture_url": 1})
        if recipient_user:
            mission["recipient_photo_url"] = recipient_user.get("profile_picture_url")

    # Masquage numéro destinataire — révélé si livraison domicile + driver à proximité
    if (
        current_user["role"] == UserRole.DRIVER.value
        and mission.get("recipient_phone")
    ):
        mission["recipient_phone"] = mask_phone(mission["recipient_phone"])

    return mission


@router.post("/{mission_id}/accept", summary="Accepter une mission")
async def accept_mission(
    mission_id: str,
    body: Optional[LocationUpdate] = Body(None),
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    if current_user["role"] != UserRole.DRIVER.value:
        raise forbidden_exception("Seuls les livreurs peuvent accepter une mission")
    if not _driver_has_profile_photo(current_user):
        raise bad_request_exception("Votre photo de profil doit être ajoutée puis approuvée avant d'accepter une mission.")

    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    if mission["status"] != MissionStatus.PENDING.value:
        raise bad_request_exception("Mission déjà prise en charge")
    requested_driver_id = mission.get("admin_requested_driver_id")
    if requested_driver_id and requested_driver_id != current_user["user_id"]:
        raise forbidden_exception("Cette mission est réservée à un autre livreur")

    parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    if parcel.get("status") == ParcelStatus.SUSPENDED.value:
        raise forbidden_exception("Ce colis est suspendu par l'administration. Mission indisponible.")

    # ── Rigueur Opérationnelle : un seul colis à la fois ──
    # Un livreur ne peut pas accepter une mission s'il en a déjà une en cours (ASSIGNED, PICKED_UP, IN_PROGRESS)
    active_mission = await db.delivery_missions.find_one({
        "driver_id": current_user["user_id"],
        "status": {"$in": [
            MissionStatus.ASSIGNED.value,
            MissionStatus.IN_PROGRESS.value
        ]}
    })
    if active_mission:
        raise forbidden_exception("Vous avez déjà une mission en cours. Terminez-la avant d'en accepter une autre.")

    now = datetime.now(timezone.utc)
    breakdown = compute_delivery_commission_breakdown(parcel, mission)
    commission_xof = float(breakdown["total_commission_xof"])
    if commission_xof <= 0:
        raise bad_request_exception(
            "Commission mission indisponible. Impossible d'accepter cette course pour le moment."
        )
    if commission_xof > 0:
        wallet = await db.wallets.find_one(
            {"owner_id": current_user["user_id"]},
            {"_id": 0, "balance": 1},
        )
        if not wallet or float(wallet.get("balance") or 0) < commission_xof:
            raise bad_request_exception(
                f"Solde insuffisant. Cette mission demande {commission_xof:.0f} XOF de commission requise disponible."
            )

    mission_set = {
        "driver_id": current_user["user_id"],
        "status": MissionStatus.ASSIGNED.value,
        "assigned_at": now,
        "updated_at": now,
        "pickup_reminder_10_sent_at": None,
        "pickup_reminder_5_sent_at": None,
        "admin_assignment_status": "accepted" if requested_driver_id else mission.get("admin_assignment_status"),
        "platform_commission_xof": breakdown["platform_commission_xof"],
        "relay_commission_xof": breakdown["relay_commission_xof"],
        "origin_relay_commission_xof": breakdown["origin_relay_commission_xof"],
        "destination_relay_commission_xof": breakdown["destination_relay_commission_xof"],
        "total_commission_xof": breakdown["total_commission_xof"],
        "wallet_balance_required_xof": breakdown["wallet_balance_required_xof"],
        "commission_charge_mode": "wallet_hold",
        "platform_commission_wallet_reference": f"commission:{mission_id}",
    }
    mission_push = None
    if body is not None:
        driver_location = {"lat": body.lat, "lng": body.lng, "accuracy": body.accuracy}
        trail_point = {**driver_location, "ts": now}
        mission_set["driver_location"] = driver_location
        mission_set["location_updated_at"] = now
        mission_push = {"gps_trail": {"$each": [trail_point], "$slice": -300}}

    mission_update = {"$set": mission_set}
    if mission_push:
        mission_update["$push"] = mission_push

    updated_mission = await db.delivery_missions.find_one_and_update(
        {
            "mission_id": mission_id,
            "status": MissionStatus.PENDING.value,
            "$or": [{"driver_id": None}, {"driver_id": {"$exists": False}}],
        },
        mission_update,
        return_document=ReturnDocument.AFTER,
        projection={"_id": 0},
    )
    if not updated_mission:
        raise bad_request_exception("Mission déjà prise en charge")

    # Mettre à jour le colis avec le livreur assigné
    if commission_xof > 0:
        try:
            await debit_wallet(
                current_user["user_id"],
                commission_xof,
                f"Commission requise mission {mission_id}",
                parcel_id=mission["parcel_id"],
                reference=f"commission:{mission_id}",
                ensure_unique=True,
            )
        except ValueError:
            await db.delivery_missions.update_one(
                {"mission_id": mission_id},
                {
                    "$set": {
                        "driver_id": None,
                        "status": MissionStatus.PENDING.value,
                        "assigned_at": None,
                        "updated_at": datetime.now(timezone.utc),
                    },
                    "$unset": {
                        "driver_location": "",
                        "location_updated_at": "",
                        "gps_trail": "",
                        "platform_commission_xof": "",
                        "relay_commission_xof": "",
                        "origin_relay_commission_xof": "",
                        "destination_relay_commission_xof": "",
                        "total_commission_xof": "",
                        "wallet_balance_required_xof": "",
                        "platform_commission_wallet_reference": "",
                    },
                },
            )
            raise bad_request_exception(
                "Solde insuffisant. Rechargez votre wallet avant d'accepter cette mission."
            )

    await db.parcels.update_one(
        {"parcel_id": mission["parcel_id"]},
        {"$set": {
            "assigned_driver_id": current_user["user_id"],
            "updated_at": now,
        }},
    )
    if body is not None:
        await db.users.update_one(
            {"user_id": current_user["user_id"]},
            {"$set": {
                "last_driver_location": {"lat": body.lat, "lng": body.lng},
                "last_driver_location_at": now,
                "updated_at": now,
            }},
        )
    if parcel:
        await notify_sender_driver_assigned(parcel, current_user)
        await _record_event(
            parcel_id=mission["parcel_id"],
            event_type="MISSION_ACCEPTED",
            actor_id=current_user["user_id"],
            actor_role=current_user["role"],
            notes=(
                f"Livreur assigné : {current_user.get('name') or 'Livreur'}. "
                "L'expéditeur a été notifié pour préparer la remise du colis."
            ),
            metadata={
                "mission_id": mission_id,
                "driver_id": current_user["user_id"],
                "driver_name": current_user.get("name"),
                "assigned_at": now.isoformat(),
                "notified_sender": True,
            },
        )
    return {"message": "Mission acceptée", "mission_id": mission_id}


@router.post("/{mission_id}/decline", summary="Refuser une mission proposée")
async def decline_mission(
    mission_id: str,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    if mission["status"] != MissionStatus.PENDING.value:
        raise bad_request_exception("Impossible de refuser une mission déjà prise en charge")

    user_id = current_user["user_id"]
    candidate_drivers = [driver_id for driver_id in (mission.get("candidate_drivers") or []) if driver_id != user_id]
    notified_driver_ids = [
        driver_id for driver_id in (mission.get("dispatch_notified_driver_ids") or []) if driver_id != user_id
    ]
    requested_driver_id = mission.get("admin_requested_driver_id")
    if user_id not in (mission.get("candidate_drivers") or []) and user_id not in (mission.get("dispatch_notified_driver_ids") or []):
        raise forbidden_exception("Cette mission ne vous est pas proposée")

    now = datetime.now(timezone.utc)
    update_doc = {
        "candidate_drivers": candidate_drivers,
        "dispatch_notified_driver_ids": notified_driver_ids,
        "updated_at": now,
    }
    if requested_driver_id == user_id:
        update_doc["admin_assignment_status"] = "declined"

    await db.delivery_missions.update_one(
        {"mission_id": mission_id},
        {"$set": update_doc},
    )
    await _record_event(
        parcel_id=mission["parcel_id"],
        event_type="MISSION_DECLINED",
        actor_id=user_id,
        actor_role=current_user["role"],
        notes="Mission refusée par le livreur",
        metadata={"mission_id": mission_id},
    )
    return {"message": "Mission refusée"}


async def _update_driver_presence_location(
    *,
    body: LocationUpdate,
    current_user: dict,
) -> dict:
    if current_user["role"] != UserRole.DRIVER.value:
        raise forbidden_exception("Seuls les livreurs peuvent mettre a jour cette position")

    now = datetime.now(timezone.utc)
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {
            "$set": {
                "last_driver_location": {"lat": body.lat, "lng": body.lng},
                "last_driver_location_at": now,
                "updated_at": now,
            }
        },
    )
    if (
        current_user.get("is_available", False)
        and _driver_has_profile_photo(current_user)
    ):
        await _notify_driver_when_entering_dispatch_radius(
            driver_user_id=current_user["user_id"],
            lat=body.lat,
            lng=body.lng,
            now=now,
        )
    return {"message": "Position livreur mise a jour"}


@router.put("/me/location", summary="Mettre a jour la position du livreur connecte")
async def update_my_driver_location_legacy(
    body: LocationUpdate,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    return await _update_driver_presence_location(
        body=body,
        current_user=current_user,
    )


@router.put("/{mission_id}/location", summary="Mettre à jour position GPS")
async def update_location(
    mission_id: str,
    body: LocationUpdate,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    now = datetime.now(timezone.utc)
    driver_loc = {"lat": body.lat, "lng": body.lng, "accuracy": body.accuracy, "ts": now}
    
    # ── Récupérer la mission pour voir si on doit refresh l'ETA ──
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin and mission.get("driver_id") != current_user["user_id"]:
        raise forbidden_exception("Seul le livreur assigné peut mettre à jour la position")

    update_query = {
        "$set": {
            "driver_location": {"lat": body.lat, "lng": body.lng, "accuracy": body.accuracy},
            "location_updated_at": now,
            "updated_at": now,
        },
        "$push": {
            "gps_trail": {
                "$each": [driver_loc],
                "$slice": -300
            }
        }
    }

    # ── Calculer l'ETA si nécessaire (max 1 fois toutes les 5 minutes pour budget API) ──
    last_eta_update = _as_aware_utc(mission.get("eta_updated_at"))
    should_update_eta = (
        mission["status"] == MissionStatus.IN_PROGRESS.value
        and (last_eta_update is None or (now - last_eta_update).total_seconds() > 300)
    )
    
    delivery_geopin = _normalize_geopin(mission.get("delivery_geopin"))
    if should_update_eta:
        dest_lat = delivery_geopin.get("lat") if delivery_geopin else None
        dest_lng = delivery_geopin.get("lng") if delivery_geopin else None
        if dest_lat and dest_lng:
            eta_data = await get_directions_eta(body.lat, body.lng, dest_lat, dest_lng)
            if eta_data:
                update_query["$set"].update({
                    "eta_seconds":    eta_data["duration_seconds"],
                    "eta_text":       eta_data["duration_text"],
                    "distance_text":  eta_data["distance_text"],
                    "eta_updated_at": now,
                })
                if eta_data.get("encoded_polyline"):
                    update_query["$set"]["encoded_polyline"] = eta_data["encoded_polyline"]

    # ── Géofence : Notification "Votre livreur approche" (< 500m) ──
    if (mission["status"] == MissionStatus.IN_PROGRESS.value and 
        not mission.get("approaching_notified")):
        
        dest_lat = delivery_geopin.get("lat") if delivery_geopin else None
        dest_lng = delivery_geopin.get("lng") if delivery_geopin else None
        if dest_lat and dest_lng:
            dist_m = _haversine_km(body.lat, body.lng, dest_lat, dest_lng) * 1000
            if dist_m < 500:
                # Récupérer le colis pour avoir le tracking_code
                parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]})
                if parcel:
                    await notify_approaching_driver(parcel)
                    update_query["$set"]["approaching_notified"] = True

    mission_query = {"mission_id": mission_id}
    if not is_admin:
        mission_query["driver_id"] = current_user["user_id"]
    await db.delivery_missions.update_one(mission_query, update_query)
    
    # ── Mettre à jour la position globale du livreur (pour le dispatch/heatmap) ──
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {
            "last_driver_location": {"lat": body.lat, "lng": body.lng},
            "last_driver_location_at": now,
            "updated_at": now
        }}
    )

    return {"message": "Position mise à jour"}


@router.put("/driver-presence/location", summary="Mettre a jour la position de presence du livreur connecte")
async def update_my_driver_location(
    body: LocationUpdate,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    return await _update_driver_presence_location(
        body=body,
        current_user=current_user,
    )


@router.post("/{mission_id}/contact-recipient", summary="Contacter le destinataire via Denkma")
@limiter.limit("6/minute")
async def contact_recipient_via_denkma(
    mission_id: str,
    request: Request,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    """Demande un contact WhatsApp sans exposer le numéro au livreur."""
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")

    is_admin = current_user["role"] in {UserRole.ADMIN.value, UserRole.SUPERADMIN.value}
    if not is_admin and mission.get("driver_id") != current_user["user_id"]:
        raise forbidden_exception("Seul le livreur assigné peut contacter le destinataire")

    if mission.get("status") not in {MissionStatus.ASSIGNED.value, MissionStatus.IN_PROGRESS.value}:
        raise bad_request_exception("Le contact est possible seulement pendant une mission active")

    parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    if parcel.get("status") == ParcelStatus.SUSPENDED.value:
        raise forbidden_exception("Ce colis est suspendu par l'administration")

    recipient_phone = mission.get("recipient_phone") or parcel.get("recipient_phone")
    if not recipient_phone:
        raise bad_request_exception("Aucun numéro destinataire n'est disponible pour ce colis")

    permission = await get_driver_call_permission(recipient_phone)
    now = datetime.now(timezone.utc)
    if not permission.get("approved"):
        recent_cutoff = now - timedelta(minutes=2)
        recent_count = await db.driver_contact_requests.count_documents({
            "mission_id": mission_id,
            "driver_id": current_user["user_id"],
            "sent": True,
            "created_at": {"$gte": recent_cutoff},
        })
        if recent_count >= 2:
            raise bad_request_exception("Attendez quelques instants avant de relancer le destinataire")

    result = await ensure_driver_call_permission_request(
        recipient_phone=recipient_phone,
        parcel=parcel,
        mission=mission,
        driver=current_user,
    )

    request_doc = {
        "request_id": f"wac_{uuid.uuid4().hex[:16]}",
        "mission_id": mission_id,
        "parcel_id": mission["parcel_id"],
        "driver_id": current_user["user_id"],
        "driver_name": current_user.get("name"),
        "channel": "whatsapp",
        "recipient_phone_masked": mask_phone(recipient_phone),
        "tracking_code": parcel.get("tracking_code") or mission.get("tracking_code"),
        "sent": bool(result.get("sent")),
        "approved": bool(result.get("approved")),
        "whatsapp_message_id": result.get("message_id"),
        "whatsapp_template": result.get("template"),
        "action": result.get("action"),
        "whatsapp_template": result.get("template"),
        "status_code": result.get("status_code"),
        "permission_status_code": result.get("permission_status_code"),
        "permission_error": result.get("permission_error"),
        "reason": result.get("reason"),
        "meta_error": result.get("meta_error"),
        "created_at": now,
    }
    await db.driver_contact_requests.insert_one(request_doc)

    await _record_event(
        parcel_id=mission["parcel_id"],
        event_type="DRIVER_CONTACT_RECIPIENT_REQUESTED",
        actor_id=current_user.get("user_id"),
        actor_role=current_user.get("role"),
        notes=(
            "Demande de contact WhatsApp envoyée au destinataire"
            if result.get("sent")
            else "Demande de contact WhatsApp non envoyée"
        ),
        metadata={
            "mission_id": mission_id,
            "channel": "whatsapp",
            "sent": bool(result.get("sent")),
            "approved": bool(result.get("approved")),
            "whatsapp_message_id": result.get("message_id"),
            "whatsapp_template": result.get("template"),
            "action": result.get("action"),
            "whatsapp_template": result.get("template"),
            "reason": result.get("reason"),
            "status_code": result.get("status_code"),
            "permission_status_code": result.get("permission_status_code"),
        },
    )

    return {
        "message": result.get("message"),
        "sent": bool(result.get("sent")),
        "approved": bool(result.get("approved")),
        "channel": "whatsapp",
        "request_id": request_doc["request_id"],
        "reason": result.get("reason"),
        "permission_status_code": result.get("permission_status_code"),
    }


@router.post("/{mission_id}/call-recipient", summary="Appeler le destinataire via l'API WhatsApp")
@limiter.limit("4/minute")
async def call_recipient_via_whatsapp_api(
    mission_id: str,
    body: WhatsAppCallConnectRequest,
    request: Request,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    """Lance un vrai appel WhatsApp Cloud API sans exposer le numéro au livreur."""
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")

    is_admin = current_user["role"] in {UserRole.ADMIN.value, UserRole.SUPERADMIN.value}
    if not is_admin and mission.get("driver_id") != current_user["user_id"]:
        raise forbidden_exception("Seul le livreur assigné peut appeler le destinataire")

    if mission.get("status") not in {MissionStatus.ASSIGNED.value, MissionStatus.IN_PROGRESS.value}:
        raise bad_request_exception("L'appel est possible seulement pendant une mission active")

    parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    if parcel.get("status") == ParcelStatus.SUSPENDED.value:
        raise forbidden_exception("Ce colis est suspendu par l'administration")

    recipient_phone = mission.get("recipient_phone") or parcel.get("recipient_phone")
    if not recipient_phone:
        raise bad_request_exception("Aucun numéro destinataire n'est disponible pour ce colis")

    now = datetime.now(timezone.utc)
    recent_cutoff = now - timedelta(minutes=2)
    recent_count = await db.driver_call_requests.count_documents({
        "mission_id": mission_id,
        "driver_id": current_user["user_id"],
        "created_at": {"$gte": recent_cutoff},
    })
    if recent_count >= 2:
        raise bad_request_exception("Attendez quelques instants avant de relancer un appel")

    result = await connect_driver_whatsapp_call(
        recipient_phone=recipient_phone,
        parcel=parcel,
        mission=mission,
        driver=current_user,
        sdp_offer=body.sdp_offer,
    )

    request_doc = {
        "request_id": f"wacall_{uuid.uuid4().hex[:16]}",
        "mission_id": mission_id,
        "parcel_id": mission["parcel_id"],
        "driver_id": current_user["user_id"],
        "driver_name": current_user.get("name"),
        "channel": "whatsapp_call",
        "recipient_phone_masked": mask_phone(recipient_phone),
        "tracking_code": parcel.get("tracking_code") or mission.get("tracking_code"),
        "connected": bool(result.get("connected")),
        "whatsapp_call_id": result.get("call_id"),
        "action": result.get("action"),
        "status_code": result.get("status_code"),
        "permission_request_sent": result.get("permission_request_sent"),
        "permission_status_code": result.get("permission_status_code"),
        "permission_error": result.get("permission_error"),
        "request_status_code": result.get("request_status_code"),
        "request_error": result.get("request_error"),
        "reason": result.get("reason"),
        "meta_error": result.get("meta_error"),
        "created_at": now,
    }
    await db.driver_call_requests.insert_one(request_doc)

    await _record_event(
        parcel_id=mission["parcel_id"],
        event_type="DRIVER_WHATSAPP_CALL_REQUESTED",
        actor_id=current_user.get("user_id"),
        actor_role=current_user.get("role"),
        notes=(
            "Appel WhatsApp lancé via Denkma"
            if result.get("connected")
            else "Appel WhatsApp non lancé"
        ),
        metadata={
            "mission_id": mission_id,
            "channel": "whatsapp_call",
            "connected": bool(result.get("connected")),
            "whatsapp_call_id": result.get("call_id"),
            "action": result.get("action"),
            "reason": result.get("reason"),
            "status_code": result.get("status_code"),
            "permission_request_sent": result.get("permission_request_sent"),
            "permission_status_code": result.get("permission_status_code"),
        },
    )

    return {
        "message": result.get("message"),
        "connected": bool(result.get("connected")),
        "channel": "whatsapp_call",
        "call_id": result.get("call_id"),
        "request_id": request_doc["request_id"],
        "reason": result.get("reason"),
        "permission_request_sent": bool(result.get("permission_request_sent")),
        "whatsapp_template": result.get("template"),
    }


@router.get("/{mission_id}/calls/{call_id}", summary="Statut d'un appel WhatsApp")
async def get_driver_whatsapp_call_status(
    mission_id: str,
    call_id: str,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    request_doc = await db.driver_call_requests.find_one(
        {"mission_id": mission_id, "whatsapp_call_id": call_id},
        {"_id": 0},
    )
    if not request_doc:
        raise not_found_exception("Appel WhatsApp")

    is_admin = current_user["role"] in {UserRole.ADMIN.value, UserRole.SUPERADMIN.value}
    if not is_admin and request_doc.get("driver_id") != current_user["user_id"]:
        raise forbidden_exception("Accès refusé à cet appel")

    events = await db.whatsapp_call_events.find(
        {"call_event_id": call_id},
        {"_id": 0},
    ).sort("created_at", -1).limit(10).to_list(length=10)
    latest = events[0] if events else None
    return {
        "call_id": call_id,
        "mission_id": mission_id,
        "connected": request_doc.get("connected"),
        "latest_event": latest,
        "events": events,
    }


@router.post("/{mission_id}/calls/{call_id}/terminate", summary="Terminer un appel WhatsApp en cours")
@limiter.limit("10/minute")
async def terminate_whatsapp_call(
    mission_id: str,
    call_id: str,
    request: Request,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    """Termine côté Meta un appel WhatsApp précédemment lancé par le livreur."""
    request_doc = await db.driver_call_requests.find_one(
        {"mission_id": mission_id, "whatsapp_call_id": call_id},
        {"_id": 0},
    )
    if not request_doc:
        raise not_found_exception("Appel WhatsApp")

    is_admin = current_user["role"] in {UserRole.ADMIN.value, UserRole.SUPERADMIN.value}
    if not is_admin and request_doc.get("driver_id") != current_user["user_id"]:
        raise forbidden_exception("Accès refusé à cet appel")

    result = await terminate_driver_whatsapp_call(call_id)
    await _record_event(
        parcel_id=request_doc.get("parcel_id"),
        event_type="DRIVER_WHATSAPP_CALL_TERMINATED",
        actor_id=current_user.get("user_id"),
        actor_role=current_user.get("role"),
        notes="Appel WhatsApp terminé par le livreur" if result.get("terminated") else "Échec terminaison appel WhatsApp",
        metadata={
            "mission_id": mission_id,
            "whatsapp_call_id": call_id,
            "terminated": bool(result.get("terminated")),
            "reason": result.get("reason"),
            "status_code": result.get("status_code"),
        },
    )
    return result


@router.post("/{mission_id}/release", summary="Libérer une mission (driver)")
async def release_mission(
    mission_id: str,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    """
    Le livreur libère une mission qu'il a acceptée mais ne peut pas honorer.
    La mission repasse en PENDING, disponible pour d'autres livreurs.
    Impossible si la collecte est déjà confirmée (statut IN_PROGRESS).
    """
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    if mission["status"] != MissionStatus.ASSIGNED.value:
        raise bad_request_exception("Impossible de libérer : collecte déjà confirmée ou mission terminée")
    if mission.get("driver_id") != current_user["user_id"]:
        raise forbidden_exception()

    now = datetime.now(timezone.utc)
    await db.delivery_missions.update_one(
        {"mission_id": mission_id},
        {
            "$set": {
                "status": MissionStatus.PENDING.value,
                "driver_id": None,
                "assigned_at": None,
                "updated_at": now,
            },
            "$unset": {
                "pickup_reminder_10_sent_at": "",
                "pickup_reminder_5_sent_at": "",
            },
        },
    )
    await db.parcels.update_one(
        {"parcel_id": mission["parcel_id"]},
        {"$set": {"assigned_driver_id": None, "updated_at": now}},
    )
    commission_xof = float(
        mission.get("total_commission_xof")
        or mission.get("wallet_balance_required_xof")
        or mission.get("relay_commission_xof")
        or mission.get("platform_commission_xof")
        or _mission_commission_xof(None, mission)
        or 0
    )
    charge_mode = mission.get("commission_charge_mode") or "wallet_hold"
    if commission_xof > 0 and charge_mode in {"wallet_hold", "driver_debt"}:
        await credit_wallet(
            owner_id=current_user["user_id"],
            owner_type="driver",
            amount=commission_xof,
            description=f"Remboursement commission requise mission {mission_id}",
            parcel_id=mission["parcel_id"],
            reference=f"commission_refund:{mission_id}",
            count_as_earned=False,
            ensure_unique=True,
        )

    parcel = await db.parcels.find_one(
        {"parcel_id": mission["parcel_id"]},
        {"_id": 0, "tracking_code": 1},
    )
    tracking = (parcel or {}).get("tracking_code") or mission["parcel_id"]
    await record_admin_event(
        AdminEventType.MISSION_RELEASED,
        title=f"Mission relâchée — colis {tracking}",
        message=f"{current_user.get('name') or 'Livreur'} a libéré la mission, à réassigner.",
        href=f"/dashboard/parcels/{mission['parcel_id']}",
        metadata={
            "mission_id": mission_id,
            "parcel_id": mission["parcel_id"],
            "tracking_code": tracking,
            "driver_id": current_user["user_id"],
        },
    )
    return {"message": "Mission libérée, disponible pour d'autres livreurs"}


class IncidentReportRequest(BaseModel):
    reason: str
    notes: Optional[str] = None


class ConfirmReturnRequest(BaseModel):
    code: str = Field(..., min_length=6, max_length=6)
    notes: Optional[str] = None

@router.post("/{mission_id}/report-incident", summary="Signaler un incident (driver)")
async def report_incident(
    mission_id: str,
    body: IncidentReportRequest,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    """
    Le livreur signale un incident (panne, accident, etc.) sur sa mission.
    Le colis passe en INCIDENT_REPORTED et l'admin est notifié.
    """
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    
    if mission.get("driver_id") != current_user["user_id"]:
        raise forbidden_exception()

    parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    if (
        mission.get("status") == MissionStatus.INCIDENT_REPORTED.value
        and parcel.get("status") == ParcelStatus.INCIDENT_REPORTED.value
    ):
        return {
            "message": "Retour déjà demandé. Rapportez le colis à l'expéditeur puis saisissez le code de retour."
        }
    if mission.get("status") != MissionStatus.IN_PROGRESS.value:
        raise bad_request_exception("Le retour à l'expéditeur n'est possible qu'après la collecte du colis")

    now = datetime.now(timezone.utc)
    return_code = parcel.get("return_code") or _return_code()
    # 1. Marquer la mission en incident
    await db.delivery_missions.update_one(
        {"mission_id": mission_id},
        {"$set": {
            "status": MissionStatus.INCIDENT_REPORTED.value,
            "failure_reason": body.reason,
            "updated_at": now
        }}
    )

    await db.parcels.update_one(
        {"parcel_id": mission["parcel_id"]},
        {"$set": {"return_code": return_code, "updated_at": now}},
    )

    # 2. Transition colis
    actor = {"actor_id": current_user["user_id"], "actor_role": current_user["role"]}
    await transition_status(
        mission["parcel_id"],
        ParcelStatus.INCIDENT_REPORTED,
        notes=f"Retour à l'expéditeur demandé : {body.reason}. {body.notes or ''}",
        **actor
    )

    await record_admin_event(
        AdminEventType.INCIDENT_REPORTED,
        title=f"Incident sur colis {parcel.get('tracking_code') if parcel else mission['parcel_id']}",
        message=f"{body.reason}{' · ' + body.notes if body.notes else ''}",
        href=f"/dashboard/parcels/{mission['parcel_id']}",
        metadata={
            "parcel_id": mission["parcel_id"],
            "mission_id": mission_id,
            "driver_id": current_user["user_id"],
            "reason": body.reason,
        },
    )

    await _record_event(
        parcel_id=mission["parcel_id"],
        event_type="RETURN_TO_SENDER_REQUESTED",
        actor_id=current_user["user_id"],
        actor_role=current_user["role"],
        notes="Le livreur doit rapporter le colis à l'expéditeur et saisir le code de retour.",
        metadata={
            "mission_id": mission_id,
            "return_code_generated": True,
        },
    )

    return {
        "message": "Retour demandé. L'expéditeur doit donner le code de retour au livreur après réception du colis."
    }


@router.post("/{mission_id}/confirm-return", summary="Confirmer le retour chez l'expéditeur")
@limiter.limit("10/minute")
async def confirm_return_to_sender(
    mission_id: str,
    body: ConfirmReturnRequest,
    request: Request,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")

    is_admin = current_user["role"] in {UserRole.ADMIN.value, UserRole.SUPERADMIN.value}
    if not is_admin and mission.get("driver_id") != current_user["user_id"]:
        raise forbidden_exception("Seul le livreur assigné peut confirmer ce retour")
    if mission.get("status") != MissionStatus.INCIDENT_REPORTED.value:
        raise bad_request_exception("Le retour doit d'abord être demandé depuis la mission")

    parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    if parcel.get("status") != ParcelStatus.INCIDENT_REPORTED.value:
        raise bad_request_exception("Le colis n'est pas en attente de retour expéditeur")

    await check_code_lockout(db, parcel["parcel_id"], "return_code")
    if (parcel.get("return_code") or "") != body.code.strip():
        await record_failed_attempt(db, parcel["parcel_id"], "return_code")
        raise bad_request_exception("Code de retour invalide")
    await clear_code_attempts(db, parcel["parcel_id"], "return_code")

    now = datetime.now(timezone.utc)
    await db.delivery_missions.update_one(
        {"mission_id": mission_id},
        {"$set": {
            "status": MissionStatus.FAILED.value,
            "failure_reason": "retour_expediteur_confirme",
            "completed_at": now,
            "updated_at": now,
        }},
    )

    actor = {"actor_id": current_user["user_id"], "actor_role": current_user["role"]}
    updated = await transition_status(
        parcel["parcel_id"],
        ParcelStatus.RETURNED,
        notes=body.notes or "Retour confirmé par code expéditeur",
        metadata={"mission_id": mission_id, "return_code_used": True},
        **actor,
    )

    await _record_event(
        parcel_id=parcel["parcel_id"],
        event_type="RETURN_TO_SENDER_CONFIRMED",
        actor_id=current_user["user_id"],
        actor_role=current_user["role"],
        notes="Le colis a été remis à l'expéditeur avec le code de retour.",
        metadata={"mission_id": mission_id},
    )

    return {"message": "Retour confirmé chez l'expéditeur", "parcel": updated}


@router.get("/{mission_id}/trail", summary="Trail GPS complet (admin)")
async def get_gps_trail(
    mission_id: str,
    current_user: dict = Depends(require_role(
        UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0, "gps_trail": 1})
    if not mission:
        raise not_found_exception("Mission")
    trail = mission.get("gps_trail", [])
    return {"trail": trail, "count": len(trail)}


@router.get("/rankings", summary="Classement mensuel des livreurs")
async def get_rankings(
    period: str = Query(default="", description="Format YYYY-MM. Vide = mois en cours"),
    current_user: dict = Depends(get_current_user),
):
    period = _period_or_current(period)
    all_stats = await refresh_driver_stats_for_period(period)

    is_admin = current_user.get("role") in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    is_driver = current_user.get("role") == UserRole.DRIVER.value

    if not (is_admin or is_driver):
        raise forbidden_exception("Acces reserve aux livreurs et administrateurs")

    stats = await db.driver_stats.find(
        {"period": period},
        sort=[("rank", 1)],
        limit=50,
    ).to_list(length=50)

    result = []
    for s in stats:
        is_me = s["driver_id"] == current_user["user_id"]

        if is_admin or is_me:
            driver = await db.users.find_one({"user_id": s["driver_id"]})
            display_name = driver.get("name", "Livreur") if driver else "Livreur"
            total_earned = s.get("total_earned_xof", 0)
            bonus = s.get("bonus_paid_xof", 0)
        else:
            display_name = f"Livreur #{s['rank']}"
            total_earned = None
            bonus = None

        result.append({
            "rank": s["rank"],
            "display_name": display_name,
            "badge": s["badge"],
            "deliveries_total": s["deliveries_total"],
            "deliveries_success": s["deliveries_success"],
            "success_rate": s["success_rate"],
            "avg_rating": s["avg_rating"],
            "total_earned_xof": total_earned,
            "bonus_paid_xof": bonus,
            "is_me": is_me,
        })

    return {
        "period": period,
        "total_ranked_drivers": len(all_stats),
        "rankings": result,
    }


async def _driver_month_activity(driver_id: str, period: str) -> dict:
    start, end = _period_bounds(period)
    missions = await db.delivery_missions.find(
        {
            "driver_id": driver_id,
            "completed_at": {"$gte": start, "$lte": end},
        },
        {"_id": 0, "status": 1, "completed_at": 1},
    ).to_list(None)

    active_dates = set()
    last_completed_at = None
    for mission in missions:
        if mission.get("status") != MissionStatus.COMPLETED.value:
            continue
        completed_at = _as_aware_utc(mission.get("completed_at"))
        if completed_at is None:
            continue
        active_dates.add(completed_at.date())
        if last_completed_at is None or completed_at > last_completed_at:
            last_completed_at = completed_at

    today = datetime.now(timezone.utc).date()
    streak = 0
    cursor = today if today in active_dates else max(active_dates, default=today)
    while cursor in active_dates:
        streak += 1
        cursor = cursor - timedelta(days=1)

    return {
        "active_days": len(active_dates),
        "streak_days": streak,
        "last_completed_at": last_completed_at,
    }


def _badge_items(stat: dict, activity: dict) -> list[dict]:
    total = int(stat.get("deliveries_total") or 0)
    success = int(stat.get("deliveries_success") or 0)
    rank = int(stat.get("rank") or 0)
    rate = float(stat.get("success_rate") or 0)
    items = []
    if success >= 1:
        items.append({"code": "starter", "label": "Lance", "icon": "rocket"})
    if total >= 5:
        items.append({"code": "sprinter", "label": "Sprinter", "icon": "speed"})
    if rate >= 95 and total >= 5:
        items.append({"code": "reliable", "label": "Fiable", "icon": "verified"})
    if rank and rank <= 10:
        items.append({"code": "top_10", "label": "Top 10", "icon": "trophy"})
    if total == success and success > 0:
        items.append({"code": "clean_run", "label": "Sans incident", "icon": "shield"})
    if int(activity.get("streak_days") or 0) >= 3:
        items.append({"code": "regular", "label": "Regulier", "icon": "calendar"})
    return items


def _achievement_items(stat: dict, activity: dict) -> list[dict]:
    success = int(stat.get("deliveries_success") or 0)
    earned = float(stat.get("total_earned_xof") or 0)
    rank = int(stat.get("rank") or 0)
    items = []
    if success > 0:
        items.append({"label": f"{success} course(s) livree(s) ce mois-ci"})
    if earned > 0:
        items.append({"label": f"{round(earned)} FCFA generes ce mois-ci"})
    if rank > 0:
        items.append({"label": f"Position #{rank} au classement mensuel"})
    if activity.get("last_completed_at"):
        items.append({"label": "Derniere livraison comptabilisee"})
    return items


async def _driver_general_position(driver_id: str) -> dict:
    drivers = await db.users.find(
        {"role": UserRole.DRIVER.value},
        {"_id": 0, "user_id": 1},
    ).to_list(None)
    driver_ids = [item.get("user_id") for item in drivers if item.get("user_id")]

    pipeline = [
        {
            "$match": {
                "driver_id": {"$in": driver_ids},
                "status": MissionStatus.COMPLETED.value,
            }
        },
        {
            "$group": {
                "_id": "$driver_id",
                "deliveries_success": {"$sum": 1},
                "total_earned_xof": {"$sum": {"$ifNull": ["$earn_amount", 0]}},
            }
        },
    ]
    rows = await db.delivery_missions.aggregate(pipeline).to_list(None)
    by_driver = {row["_id"]: row for row in rows if row.get("_id")}

    ranking = []
    for item in driver_ids:
        row = by_driver.get(item, {})
        ranking.append({
            "driver_id": item,
            "deliveries_success": int(row.get("deliveries_success") or 0),
            "total_earned_xof": float(row.get("total_earned_xof") or 0),
        })
    ranking.sort(
        key=lambda item: (
            -item["deliveries_success"],
            -item["total_earned_xof"],
            item["driver_id"],
        )
    )

    for index, item in enumerate(ranking, start=1):
        if item["driver_id"] == driver_id:
            return {
                "rank": index,
                "total_drivers": len(ranking),
                "deliveries_success": item["deliveries_success"],
                "total_earned_xof": item["total_earned_xof"],
            }

    return {
        "rank": 0,
        "total_drivers": len(ranking),
        "deliveries_success": 0,
        "total_earned_xof": 0,
    }


async def _driver_month_history(driver_id: str, current_period: str, months: int = 6) -> list[dict]:
    year, month = map(int, current_period.split("-"))
    periods = []
    for offset in range(months):
        cursor_month = month - offset
        cursor_year = year
        while cursor_month <= 0:
            cursor_month += 12
            cursor_year -= 1
        periods.append(f"{cursor_year}-{cursor_month:02d}")

    history = []
    for period in periods:
        stats = await refresh_driver_stats_for_period(period)
        stat = next((item for item in stats if item.get("driver_id") == driver_id), None)
        if not stat:
            stat = {
                "rank": 0,
                "deliveries_success": 0,
                "success_rate": 0,
                "total_earned_xof": 0,
            }
        history.append({
            "period": period,
            "rank": int(stat.get("rank") or 0),
            "total_drivers": len(stats),
            "deliveries_success": int(stat.get("deliveries_success") or 0),
            "success_rate": float(stat.get("success_rate") or 0),
            "total_earned_xof": float(stat.get("total_earned_xof") or 0),
        })
    return history


def _driver_motivation_message(stat: dict, missing_top3: int, monthly_goal: int) -> str:
    success = int(stat.get("deliveries_success") or 0)
    rank = int(stat.get("rank") or 0)
    remaining = max(monthly_goal - success, 0)
    if success == 0:
        return "Votre première course du mois lancera le classement."
    if rank and rank <= 3:
        return "Vous êtes sur le podium du mois. Gardez le rythme."
    if missing_top3 > 0:
        return f"Encore {missing_top3} course(s) pour viser le podium."
    if remaining > 0:
        return f"Encore {remaining} course(s) pour atteindre l'objectif mensuel."
    return "Objectif mensuel atteint. Chaque course renforce votre classement."


async def _format_driver_ranking(stat: dict, current_user: dict, podium_stats: list[dict]) -> dict:
    rewards = await get_performance_rewards_settings()
    monthly_goal = rewards["driver"]["monthly_goal_deliveries"]
    activity = await _driver_month_activity(current_user["user_id"], stat["period"])
    general = await _driver_general_position(current_user["user_id"])
    history = await _driver_month_history(current_user["user_id"], stat["period"])
    success = int(stat.get("deliveries_success") or 0)
    rank = int(stat.get("rank") or 0)
    top3_success = [
        int(item.get("deliveries_success") or 0)
        for item in podium_stats[:3]
        if item.get("driver_id") != current_user["user_id"]
    ]
    podium_threshold = min(top3_success) if len(podium_stats) >= 3 and top3_success else 0
    missing_top3 = max(podium_threshold - success + 1, 0) if rank > 3 else 0

    podium = []
    for item in podium_stats[:3]:
        is_me = item.get("driver_id") == current_user["user_id"]
        driver = None
        if is_me:
            driver = await db.users.find_one({"user_id": item.get("driver_id")}, {"_id": 0, "name": 1})
        podium.append({
            "rank": item.get("rank", 0),
            "display_name": driver.get("name", "Moi") if driver else f"Livreur #{item.get('rank', 0)}",
            "deliveries_success": item.get("deliveries_success", 0),
            "badge": item.get("badge", "none"),
            "is_me": is_me,
        })

    goal_progress = round(min(success / max(monthly_goal, 1), 1), 3)
    return {
        **stat,
        "display_name": current_user.get("name", "Moi"),
        "is_me": True,
        "monthly_goal": {
            "target": monthly_goal,
            "current": success,
            "remaining": max(monthly_goal - success, 0),
            "progress": goal_progress,
        },
        "streak_days": activity["streak_days"],
        "active_days": activity["active_days"],
        "podium": podium,
        "badges_earned": _badge_items(stat, activity),
        "achievements": _achievement_items(stat, activity),
        "missing_deliveries_to_top3": missing_top3,
        "total_ranked_drivers": len(podium_stats),
        "general_ranking": general,
        "monthly_history": history,
        "message": _driver_motivation_message(stat, missing_top3, monthly_goal),
        "last_updated_at": datetime.now(timezone.utc),
    }


@router.get("/rankings/me", summary="Ma position au classement")
async def get_my_ranking(
    period: str = Query(default=""),
    current_user: dict = Depends(require_role(UserRole.DRIVER)),
):
    period = _period_or_current(period)
    stats = await refresh_driver_stats_for_period(period)
    stat = next((item for item in stats if item.get("driver_id") == current_user["user_id"]), None)

    if not stat:
        stat = {
            "period": period,
            "driver_id": current_user["user_id"],
            "rank": 0,
            "badge": "none",
            "deliveries_total": 0,
            "deliveries_success": 0,
            "success_rate": 0,
            "avg_rating": 0,
            "total_earned_xof": 0,
            "bonus_paid_xof": 0,
        }

    return await _format_driver_ranking(stat, current_user, stats)
