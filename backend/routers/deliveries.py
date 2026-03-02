"""
Router deliveries : missions de livraison pour les drivers.
"""
import math
import uuid
from datetime import datetime, timezone, timedelta

from typing import Optional
from fastapi import APIRouter, Depends, Query

from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, bad_request_exception, forbidden_exception
from database import db
from models.common import UserRole, ParcelStatus
from models.delivery import MissionStatus, LocationUpdate
from pydantic import BaseModel
from services.parcel_service import transition_status
from services.google_maps_service import get_directions_eta
from services.notification_service import notify_approaching_driver

router = APIRouter()


def _mission_id() -> str:
    return f"msn_{uuid.uuid4().hex[:12]}"


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng / 2) ** 2
    return R * 2 * math.asin(math.sqrt(a))


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
    now = datetime.now(timezone.utc)
    user_id = current_user["user_id"]
    
    # On récupère toutes les missions PENDING
    cursor = db.delivery_missions.find({"status": MissionStatus.PENDING.value}, {"_id": 0})
    raw_missions = await cursor.to_list(length=200)

    filtered_missions = []
    
    for m in raw_missions:
        needs_update = False
        # Si mission avec cascade et temps expiré
        if not m.get("is_broadcast") and m.get("ping_expires_at"):
            if now > m["ping_expires_at"].replace(tzinfo=timezone.utc):
                # On passe au suivant
                candidates = m.get("candidate_drivers") or []
                next_idx = m.get("ping_index", 0) + 1
                
                if next_idx < len(candidates):
                    m["ping_index"] = next_idx
                    m["ping_expires_at"] = now + timedelta(seconds=30)
                    needs_update = True
                    # Notifier le suivant
                    from services.notification_service import notify_new_mission_ping
                    await notify_new_mission_ping(candidates[next_idx], m)
                else:
                    m["is_broadcast"] = True
                    needs_update = True
                    
        if needs_update:
            await db.delivery_missions.update_one(
                {"mission_id": m["mission_id"]},
                {"$set": {
                    "ping_index": m.get("ping_index"),
                    "ping_expires_at": m.get("ping_expires_at"),
                    "is_broadcast": m.get("is_broadcast")
                }}
            )

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
        return {"missions": result, "driver_lat": lat, "driver_lng": lng, "radius_km": radius_km}

    # Fallback : pas de GPS (permission refusée) → toutes les missions
    missions.sort(key=lambda m: m["created_at"])
    
    # Masquage anti-bypass
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin:
        from core.utils import mask_phone
        for m in missions:
            if "recipient_phone" in m:
                m["recipient_phone"] = mask_phone(m["recipient_phone"])
                
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
    
    # Masquage anti-bypass
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin:
        from core.utils import mask_phone
        for m in missions:
            if "recipient_phone" in m:
                m["recipient_phone"] = mask_phone(m["recipient_phone"])
                
    return {"missions": missions}

class ConfirmPickupRequest(BaseModel):
    code: str

@router.post("/{mission_id}/confirm-pickup", summary="Confirmer collecte avec code")
async def confirm_pickup(
    mission_id: str,
    body: ConfirmPickupRequest,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    
    parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    # Si expéditeur/relais a renseigné un code, vérifier :
    if parcel.get("pickup_code", "") != body.code.strip():
        raise bad_request_exception("Code de collecte invalide")

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
    # 2. Transition colis IN_TRANSIT (ou "pickup depuis expéditeur" selon le contexte)
    # (La machine d'états permet OUT_FOR_DELIVERY -> IN_TRANSIT pour les pick-ups ?)
    # En réalité, on passe souvent OUT_FOR_DELIVERY => DELIVERED, ou AT_DESTINATION_RELAY => OUT_FOR_DELIVERY
    # L'important est que la collecte est validée.
    return {"message": "Collecte confirmée", "mission_id": mission_id}


from core.utils import mask_phone

@router.get("/{mission_id}", summary="Détail mission")
async def get_mission(
    mission_id: str,
    current_user: dict = Depends(get_current_user),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    
    parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"payment_status": 1})
    if parcel:
        mission["payment_status"] = parcel.get("payment_status", "pending")

    # Masquage anti-bypass
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin:
        # Masquer les infos de l'expéditeur/destinataire si présentes dans la mission
        if "sender_phone" in mission:
            mission["sender_phone"] = mask_phone(mission["sender_phone"])
        if "recipient_phone" in mission:
            mission["recipient_phone"] = mask_phone(mission["recipient_phone"])
            
    return mission


@router.post("/{mission_id}/accept", summary="Accepter une mission")
async def accept_mission(
    mission_id: str,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    if mission["status"] != MissionStatus.PENDING.value:
        raise bad_request_exception("Mission déjà prise en charge")

    # ── Rigueur Opérationnelle : un seul colis à la fois ──
    # Un livreur ne peut pas accepter une mission s'il en a déjà une en cours (ASSIGNED, PICKED_UP, IN_PROGRESS)
    active_mission = await db.delivery_missions.find_one({
        "driver_id": current_user["user_id"],
        "status": {"$in": [
            MissionStatus.ASSIGNED.value,
            MissionStatus.PICKED_UP.value,
            MissionStatus.IN_PROGRESS.value
        ]}
    })
    if active_mission:
        raise forbidden_exception("Vous avez déjà une mission en cours. Terminez-la avant d'en accepter une autre.")

    now = datetime.now(timezone.utc)
    # Marquer la mission comme assignée
    await db.delivery_missions.update_one(
        {"mission_id": mission_id},
        {"$set": {
            "driver_id":   current_user["user_id"],
            "status":      MissionStatus.ASSIGNED.value,
            "assigned_at": now,
            "updated_at":  now,
        }},
    )
    # Mettre à jour le colis avec le livreur assigné
    await db.parcels.update_one(
        {"parcel_id": mission["parcel_id"]},
        {"$set": {
            "assigned_driver_id": current_user["user_id"],
            "updated_at": now,
        }},
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
    mission = await db.delivery_missions.find_one({"mission_id": mission_id})
    if not mission:
        raise not_found_exception("Mission")

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
    last_eta_update = mission.get("eta_updated_at")
    should_update_eta = (
        mission["status"] == MissionStatus.IN_PROGRESS.value
        and (last_eta_update is None or (now - last_eta_update).total_seconds() > 300)
    )
    
    if should_update_eta:
        dest_lat = mission.get("delivery_lat")
        dest_lng = mission.get("delivery_lng")
        if dest_lat and dest_lng:
            eta_data = await get_directions_eta(body.lat, body.lng, dest_lat, dest_lng)
            if eta_data:
                update_query["$set"].update({
                    "eta_seconds":  eta_data["duration_seconds"],
                    "eta_text":     eta_data["duration_text"],
                    "distance_text": eta_data["distance_text"],
                    "eta_updated_at": now
                })

    # ── Géofence : Notification "Votre livreur approche" (< 500m) ──
    if (mission["status"] == MissionStatus.IN_PROGRESS.value and 
        not mission.get("approaching_notified")):
        
        dest_lat = mission.get("delivery_lat")
        dest_lng = mission.get("delivery_lng")
        if dest_lat and dest_lng:
            dist_m = _haversine_km(body.lat, body.lng, dest_lat, dest_lng) * 1000
            if dist_m < 500:
                # Récupérer le colis pour avoir le tracking_code
                parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]})
                if parcel:
                    await notify_approaching_driver(parcel)
                    update_query["$set"]["approaching_notified"] = True

    await db.delivery_missions.update_one(
        {"mission_id": mission_id, "driver_id": current_user["user_id"]},
        update_query
    )
    
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
    return {"message": "Mission libérée, disponible pour d'autres livreurs"}


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
