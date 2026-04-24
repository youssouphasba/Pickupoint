"""
Router deliveries : missions de livraison pour les drivers.
"""
import math
import random
import re
import uuid
from datetime import datetime, timezone, timedelta

from typing import Optional
from fastapi import APIRouter, Depends, Query, Request
from pymongo import ReturnDocument

from config import settings
from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, bad_request_exception, forbidden_exception
from database import db
from models.common import UserRole, ParcelStatus
from models.delivery import MissionStatus, LocationUpdate
from pydantic import BaseModel, Field
from services.parcel_service import transition_status, _record_event
from services.admin_events_service import AdminEventType, record_admin_event
from services.google_maps_service import get_directions_eta
from services.notification_service import (
    notify_approaching_driver,
    notify_sender_driver_assigned,
    notify_sender_parcel_collected,
)
from services.whatsapp_call_service import (
    connect_driver_whatsapp_call,
    ensure_driver_call_permission_request,
    get_driver_call_permission,
)
from core.limiter import limiter
from core.utils import check_code_lockout, record_failed_attempt, clear_code_attempts, mask_phone, phone_suffix

router = APIRouter()


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


def _driver_has_profile_photo(current_user: dict) -> bool:
    return bool((current_user.get("profile_picture_url") or "").strip()) and (
        current_user.get("profile_picture_status") == "approved"
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


async def advance_pending_delivery_dispatch() -> int:
    """
    Fait progresser le dispatch en cascade hors du flux HTTP.
    Retourne le nombre de missions mises à jour.
    """
    now = datetime.now(timezone.utc)
    cursor = db.delivery_missions.find({"status": MissionStatus.PENDING.value}, {"_id": 0})
    raw_missions = await cursor.to_list(length=200)
    updated_count = 0

    for mission in raw_missions:
        if mission.get("is_broadcast") or not mission.get("ping_expires_at"):
            continue

        expires_at = mission["ping_expires_at"].replace(tzinfo=timezone.utc)
        if now <= expires_at:
            continue

        candidates = mission.get("candidate_drivers") or []
        next_idx = mission.get("ping_index", 0) + 1
        updates: dict[str, object] = {"updated_at": now}

        if next_idx < len(candidates):
            updates["ping_index"] = next_idx
            updates["ping_expires_at"] = now + timedelta(seconds=30)
        else:
            updates["is_broadcast"] = True
            updates["ping_expires_at"] = None

        await db.delivery_missions.update_one({"mission_id": mission["mission_id"]}, {"$set": updates})
        updated_count += 1

        if next_idx < len(candidates):
            from services.notification_service import notify_new_mission_ping

            updated_mission = {**mission, **updates}
            await notify_new_mission_ping(candidates[next_idx], updated_mission)

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

    if lat is not None and lng is not None:
        result = []
        for m in missions:
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
    
    # Masquage numéro destinataire — révélé seulement si :
    #   - livraison à domicile (*_to_home) ET driver est à proximité (approaching_notified)
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin:
        for m in missions:
            if m.get("recipient_phone"):
                m["recipient_phone"] = mask_phone(m["recipient_phone"])
                
    return {"missions": missions}

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
        },
    )
    if parcel:
        mission["parcel_status"] = parcel.get("status")
        mission["payment_status"] = parcel.get("payment_status", "pending")
        mission["payment_method"] = mission.get("payment_method") or parcel.get("payment_method")
        mission["who_pays"] = mission.get("who_pays") or parcel.get("who_pays")
        mission["payment_override"] = bool(parcel.get("payment_override"))
        mission["pickup_voice_note"] = mission.get("pickup_voice_note") or parcel.get("pickup_voice_note")
        mission["delivery_voice_note"] = mission.get("delivery_voice_note") or parcel.get("delivery_voice_note")
        mission["driver_bonus_xof"] = float(parcel.get("driver_bonus_xof", 0.0))
        mission["delivery_blocked_by_payment"] = False

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

    parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"_id": 0})
    if parcel and parcel.get("status") == ParcelStatus.SUSPENDED.value:
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
    updated_mission = await db.delivery_missions.find_one_and_update(
        {
            "mission_id": mission_id,
            "status": MissionStatus.PENDING.value,
            "$or": [{"driver_id": None}, {"driver_id": {"$exists": False}}],
        },
        {"$set": {
            "driver_id": current_user["user_id"],
            "status": MissionStatus.ASSIGNED.value,
            "assigned_at": now,
            "updated_at": now,
        }},
        return_document=ReturnDocument.AFTER,
        projection={"_id": 0},
    )
    if not updated_mission:
        raise bad_request_exception("Mission déjà prise en charge")

    # Mettre à jour le colis avec le livreur assigné
    await db.parcels.update_one(
        {"parcel_id": mission["parcel_id"]},
        {"$set": {
            "assigned_driver_id": current_user["user_id"],
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
        {"$set": {
            "status":      MissionStatus.PENDING.value,
            "driver_id":   None,
            "assigned_at": None,
            "updated_at":  now,
        }},
    )
    await db.parcels.update_one(
        {"parcel_id": mission["parcel_id"]},
        {"$set": {"assigned_driver_id": None, "updated_at": now}},
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


# ── Classements (Phase 8) ───────────────────────────────────────────────────

@router.get("/rankings", summary="Classement mensuel des livreurs")
async def get_rankings(
    period: str = Query(default="", description="Format YYYY-MM. Vide = mois en cours"),
    current_user: dict = Depends(get_current_user),
):
    """
    Retourne le top des livreurs pour une période donnée.
    Admin : voit tout.
    Driver : voit les noms masqués sauf le sien.
    """
    from datetime import datetime, timezone
    if not period:
        now = datetime.now(timezone.utc)
        period = f"{now.year}-{now.month:02d}"

    is_admin = current_user.get("role") in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    is_driver = current_user.get("role") == UserRole.DRIVER.value

    if not (is_admin or is_driver):
        raise forbidden_exception("Accès réservé aux livreurs et administrateurs")

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
            bonus        = s.get("bonus_paid_xof", 0)
        else:
            display_name = f"Livreur #{s['rank']}"
            total_earned = None
            bonus        = None

        result.append({
            "rank":              s["rank"],
            "display_name":      display_name,
            "badge":             s["badge"],
            "deliveries_total":  s["deliveries_total"],
            "deliveries_success":s["deliveries_success"],
            "success_rate":      s["success_rate"],
            "avg_rating":        s["avg_rating"],
            "total_earned_xof":  total_earned,
            "bonus_paid_xof":    bonus,
            "is_me":             is_me,
        })

    return {"period": period, "rankings": result}


@router.get("/rankings/me", summary="Ma position au classement")
async def get_my_ranking(
    period: str = Query(default=""),
    current_user: dict = Depends(require_role(UserRole.DRIVER)),
):
    from datetime import datetime, timezone
    if not period:
        now = datetime.now(timezone.utc)
        period = f"{now.year}-{now.month:02d}"

    stat = await db.driver_stats.find_one({
        "driver_id": current_user["user_id"],
        "period": period,
    }, {"_id": 0})
    
    if not stat:
        return {"period": period, "rank": None, "message": "Aucune donnée pour cette période"}

    return stat
