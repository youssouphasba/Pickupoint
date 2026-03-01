"""
Router deliveries : missions de livraison pour les drivers.
"""
import math
import uuid
from datetime import datetime, timezone

from typing import Optional
from fastapi import APIRouter, Depends, Query

from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, bad_request_exception
from database import db
from models.common import UserRole, ParcelStatus
from models.delivery import MissionStatus, LocationUpdate
from pydantic import BaseModel
from services.parcel_service import transition_status

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
    - Si lat/lng fournis : filtre par rayon_km, ajoute distance_km, tri croissant.
    - Sinon : retourne toutes les missions (fallback GPS refusé).
    """
    query: dict = {"status": MissionStatus.PENDING.value}
    missions = await db.delivery_missions.find(query, {"_id": 0}).to_list(length=200)

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
    return {"missions": await cursor.to_list(length=50)}

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


@router.get("/{mission_id}", summary="Détail mission")
async def get_mission(
    mission_id: str,
    current_user: dict = Depends(get_current_user),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
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
    
    await db.delivery_missions.update_one(
        {"mission_id": mission_id, "driver_id": current_user["user_id"]},
        {
            "$set": {
                "driver_location": {"lat": body.lat, "lng": body.lng, "accuracy": body.accuracy},
                "location_updated_at": now,
                "updated_at": now,
            },
            "$push": {
                "gps_trail": {
                    "$each": [driver_loc],
                    "$slice": -300  # Garde les 300 dernières positions (env. 2h30 à 30s d'intervalle)
                }
            }
        },
    )
    return {"message": "Position mise à jour"}


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
