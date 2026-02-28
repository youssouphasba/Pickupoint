"""
Router relay_points : gestion des points relais.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query

from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, forbidden_exception
from database import db
from models.common import UserRole
from models.relay_point import RelayPoint, RelayPointCreate, RelayPointUpdate

router = APIRouter()


def _relay_id() -> str:
    return f"rly_{uuid.uuid4().hex[:12]}"


@router.get("", summary="Liste des relais (public)")
async def list_relay_points(
    city: str = "Dakar",
    is_active: bool = True,
    skip: int = 0,
    limit: int = 50,
):
    query = {"is_active": is_active, "address.city": city}
    cursor = db.relay_points.find(query, {"_id": 0}).skip(skip).limit(limit)
    relays = await cursor.to_list(length=limit)
    return {"relay_points": relays, "total": await db.relay_points.count_documents(query)}


@router.get("/nearby", summary="Relais proches d'un geopin")
async def nearby_relay_points(
    lat: float = Query(...),
    lng: float = Query(...),
    radius_km: float = Query(5.0),
):
    """
    Recherche approximative par bounding box (Phase 1).
    Phase 2 : utiliser un index géospatial MongoDB 2dsphere.
    """
    delta = radius_km / 111.0  # ~1 degré = 111 km
    query = {
        "is_active": True,
        "address.geopin.lat": {"$gte": lat - delta, "$lte": lat + delta},
        "address.geopin.lng": {"$gte": lng - delta, "$lte": lng + delta},
    }
    cursor = db.relay_points.find(query, {"_id": 0}).limit(20)
    return {"relay_points": await cursor.to_list(length=20)}


@router.get("/{relay_id}", summary="Détail d'un relais")
async def get_relay_point(relay_id: str):
    relay = await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0})
    if not relay:
        raise not_found_exception("Point relais")
    return relay


@router.get("/{relay_id}/stock", summary="Colis en stock dans ce relais")
async def relay_stock(relay_id: str, current_user: dict = Depends(get_current_user)):
    cursor = db.parcels.find(
        {
            "$or": [{"origin_relay_id": relay_id}, {"destination_relay_id": relay_id}],
            "status": {"$in": [
                "dropped_at_origin_relay", "at_destination_relay", "available_at_relay"
            ]},
        },
        {"_id": 0},
    )
    return {"parcels": await cursor.to_list(length=100)}


@router.post("", response_model=RelayPoint, summary="Créer un relais (admin)")
async def create_relay_point(
    body: RelayPointCreate,
    current_user: dict = Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    now = datetime.now(timezone.utc)
    relay_doc = {
        "relay_id":          _relay_id(),
        "owner_user_id":     current_user["user_id"],
        "agent_user_ids":    [],
        "name":              body.name,
        "address":           body.address.model_dump(),
        "phone":             body.phone,
        "max_capacity":      body.max_capacity,
        "current_load":      0,
        "opening_hours":     body.opening_hours,
        "zone_ids":          [],
        "coverage_radius_km": 5.0,
        "is_active":         True,
        "is_verified":       False,
        "score":             5.0,
        "store_id":          body.store_id,
        "external_ref":      None,
        "created_at":        now,
        "updated_at":        now,
    }
    await db.relay_points.insert_one(relay_doc)
    return RelayPoint(**{k: v for k, v in relay_doc.items() if k != "_id"})


@router.put("/{relay_id}", summary="Modifier un relais (admin ou owner)")
async def update_relay_point(
    relay_id: str,
    body: RelayPointUpdate,
    current_user: dict = Depends(get_current_user),
):
    relay = await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0})
    if not relay:
        raise not_found_exception("Point relais")

    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    is_owner = relay["owner_user_id"] == current_user["user_id"]
    if not is_admin and not is_owner:
        raise forbidden_exception()

    updates = body.model_dump(exclude_none=True)
    if "address" in updates:
        updates["address"] = body.address.model_dump()
    if updates:
        updates["updated_at"] = datetime.now(timezone.utc)
        await db.relay_points.update_one({"relay_id": relay_id}, {"$set": updates})

    updated = await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0})
    return updated
