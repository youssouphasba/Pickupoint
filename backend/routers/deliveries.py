"""
Router deliveries : missions de livraison pour les drivers.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, bad_request_exception
from database import db
from models.common import UserRole, ParcelStatus
from models.delivery import MissionStatus, LocationUpdate
from services.parcel_service import transition_status

router = APIRouter()


def _mission_id() -> str:
    return f"msn_{uuid.uuid4().hex[:12]}"


@router.get("/available", summary="Missions disponibles (drivers)")
async def available_missions(
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    cursor = db.delivery_missions.find(
        {"status": MissionStatus.PENDING.value},
        {"_id": 0},
    ).limit(50)
    return {"missions": await cursor.to_list(length=50)}


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
    await db.delivery_missions.update_one(
        {"mission_id": mission_id},
        {"$set": {
            "driver_id":   current_user["user_id"],
            "status":      MissionStatus.ASSIGNED.value,
            "assigned_at": now,
            "updated_at":  now,
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
    await db.delivery_missions.update_one(
        {"mission_id": mission_id, "driver_id": current_user["user_id"]},
        {"$set": {
            "driver_location": {"lat": body.lat, "lng": body.lng, "accuracy": body.accuracy},
            "location_updated_at": now,
            "updated_at": now,
        }},
    )
    return {"message": "Position mise à jour"}
