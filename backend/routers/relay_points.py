"""
Router relay_points : gestion des points relais.
"""
import uuid
import re
import math
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query, Request

from core.dependencies import get_current_user, get_current_user_optional, require_role
from core.exceptions import not_found_exception, forbidden_exception, bad_request_exception, conflict_exception, DeliveryCommissionDataError
from database import db
from models.common import UserRole
from models.relay_point import RelayPoint, RelayPointCreate, RelayPointUpdate, RelayLocationReview
from models.common import Address
from services.admin_events_service import AdminEventType, record_admin_event
from services.relay_geocoding_service import geocode_relay_address
from services.performance_rewards_service import get_performance_rewards_settings
from services.relay_hours import has_enabled_opening_day, normalize_opening_hours, relay_open_status
from services.wallet_service import build_relay_financial_summary
from services.relay_settlement_service import RELAY_FINANCIAL_STATUSES
from core.parcel_privacy import serialize_parcel

router = APIRouter()
logger = logging.getLogger(__name__)

from core.limiter import limiter


def _relay_id() -> str:
    return f"rly_{uuid.uuid4().hex[:12]}"


async def _get_relay_or_404(relay_id: str) -> dict:
    relay = await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0})
    if not relay:
        raise not_found_exception("Point relais")
    return relay


def _relay_address(relay: dict) -> dict:
    raw = relay.get("address")
    address = dict(raw) if isinstance(raw, dict) else {"label": raw} if isinstance(raw, str) else {}
    pin = address.get("geopin") or {}
    lat = pin.get("lat", address.get("latitude", relay.get("latitude", relay.get("lat"))))
    lng = pin.get("lng", address.get("longitude", relay.get("longitude", relay.get("lng"))))
    try:
        lat, lng = float(lat), float(lng)
        if math.isfinite(lat) and math.isfinite(lng) and -90 <= lat <= 90 and -180 <= lng <= 180:
            address["geopin"] = {**pin, "lat": lat, "lng": lng}
    except (TypeError, ValueError):
        pass
    if not address.get("city") and relay.get("city"):
        address["city"] = relay["city"]
    return address


def _with_opening_status(relay: dict, *, management: bool = False) -> dict:
    result = dict(relay)
    result["address"] = _relay_address(relay)
    if not management:
        result.pop("location_change_request", None)
    result["opening_status"] = relay_open_status(relay)
    result["is_open"] = result["opening_status"]["is_open"]
    return result


def _can_manage_relay(relay: dict, current_user: dict) -> bool:
    role = current_user.get("role")
    if role in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]:
        return True
    user_id = current_user.get("user_id")
    return (
        relay.get("owner_user_id") == user_id
        or user_id in (relay.get("agent_user_ids") or [])
        or current_user.get("relay_point_id") == relay.get("relay_id")
    )


def _period_bounds(period: Optional[str] = None) -> tuple[str, datetime, datetime]:
    now = datetime.now(timezone.utc)
    if period:
        year, month = map(int, period.split("-"))
    else:
        year, month = now.year, now.month
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    end = (
        datetime(year + 1, 1, 1, tzinfo=timezone.utc)
        if month == 12
        else datetime(year, month + 1, 1, tzinfo=timezone.utc)
    ) - timedelta(microseconds=1)
    return f"{year}-{month:02d}", start, end


@router.get("", summary="Liste des relais (public)")
@limiter.limit("10/minute")
async def list_relay_points(
    request: Request,
    city: Optional[str] = None,
    search: Optional[str] = None,
    is_active: bool = True,
    skip: int = 0,
    limit: int = 50,
):
    query = {"is_active": is_active, "is_verified": True}
    if city:
        query["address.city"] = city
    if search and search.strip():
        tokens = [token for token in re.split(r"[\s,_-]+", search.strip()) if token]
        pattern = ".*" + ".*".join(re.escape(token) for token in tokens) + ".*"
        query["$or"] = [
            {"name": {"$regex": pattern, "$options": "i"}},
            {"address.city": {"$regex": pattern, "$options": "i"}},
            {"address.district": {"$regex": pattern, "$options": "i"}},
            {"address.label": {"$regex": pattern, "$options": "i"}},
        ]
        
    cursor = db.relay_points.find(query, {"_id": 0}).skip(skip).limit(limit)
    relays = await cursor.to_list(length=limit)
    return {
        "relay_points": [_with_opening_status(relay) for relay in relays],
        "total": await db.relay_points.count_documents(query),
    }


@router.get("/nearby", summary="Relais proches d'un geopin")
@limiter.limit("10/minute")
async def nearby_relay_points(
    request: Request,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(5.0, gt=0, le=100),
):
    delta = radius_km / 111.0  # ~1 degré = 111 km
    longitude_delta = min(180, delta / max(abs(math.cos(math.radians(lat))), 0.001))
    query = {
        "is_active": True,
        "is_verified": True,
        "address.geopin.lat": {"$gte": lat - delta, "$lte": lat + delta},
        "address.geopin.lng": {"$gte": lng - longitude_delta, "$lte": lng + longitude_delta},
    }
    cursor = db.relay_points.find(query, {"_id": 0})
    relay_list = await cursor.to_list(length=None)

    from services.pricing_service import _haversine_km
    relay_list = [relay for relay in relay_list if _haversine_km(
        lat, lng, relay["address"]["geopin"]["lat"], relay["address"]["geopin"]["lng"]
    ) <= radius_km]
    relay_list.sort(
        key=lambda r: _haversine_km(lat, lng, r["address"]["geopin"]["lat"], r["address"]["geopin"]["lng"])
    )
    return {"relay_points": [_with_opening_status(relay) for relay in relay_list[:20]]}


@router.get("/{relay_id}", summary="Détail d'un relais")
async def get_relay_point(relay_id: str, current_user: Optional[dict] = Depends(get_current_user_optional)):
    relay = await _get_relay_or_404(relay_id)
    return _with_opening_status(relay, management=bool(current_user and _can_manage_relay(relay, current_user)))


@router.get("/{relay_id}/stock", summary="Colis en stock dans ce relais")
async def relay_stock(relay_id: str, current_user: dict = Depends(get_current_user)):
    relay = await _get_relay_or_404(relay_id)
    if not _can_manage_relay(relay, current_user):
        raise forbidden_exception("Acces refuse a ce stock relais")

    cursor = db.parcels.find(
        {
            "$or": [
                # Relais ORIGINE : colis déposé ici, en attente du livreur
                {
                    "origin_relay_id": relay_id,
                    "status": "dropped_at_origin_relay",
                },
                # Relais DESTINATION : colis en route vers ce relais
                {
                    "destination_relay_id": relay_id,
                    "status": "in_transit",
                },
                # Relais DESTINATION : colis arrivé ou disponible ici
                {
                    "destination_relay_id": relay_id,
                    "status": {"$in": ["at_destination_relay", "available_at_relay"]},
                },
                # Relais DE REPLI : colis redirigé après échec de livraison
                {
                    "redirect_relay_id": relay_id,
                    "status": {"$in": ["redirected_to_relay", "at_destination_relay", "available_at_relay"]},
                },
            ]
        },
        {"_id": 0},
    )
    parcels = await cursor.to_list(length=200)
    # Masquer les codes des colis pas encore physiquement au relais
    for p in parcels:
        p["relay_financial"] = build_relay_financial_summary(p, relay_id)
        if p.get("status") == "in_transit":
            p.pop("pickup_code", None)
            p.pop("relay_pin", None)
            p.pop("delivery_code", None)
    return {"parcels": [serialize_parcel(p, {**current_user, "relay_point_id": relay_id}) for p in parcels]}


@router.post("/{relay_id}/parcels/{parcel_id}/financial-action", summary="Déclarer une action financière relais")
async def relay_financial_action(
    relay_id: str,
    parcel_id: str,
    body: dict,
    current_user: dict = Depends(get_current_user),
):
    relay = await _get_relay_or_404(relay_id)
    if not _can_manage_relay(relay, current_user):
        raise forbidden_exception("Accès refusé")
    action = str(body.get("action") or "").strip()
    if action not in {"driver_payment", "denkma_payment"}:
        raise forbidden_exception("Action financière non autorisée")
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    if parcel.get("status") not in RELAY_FINANCIAL_STATUSES:
        raise bad_request_exception("Les actions de paiement sont disponibles après la collecte du colis.")
    summary = build_relay_financial_summary(parcel, relay_id)
    allowed = {item["key"] for item in summary["actions"]}
    if action not in allowed:
        raise forbidden_exception("Cette action ne concerne pas ce relais")
    now = datetime.now(timezone.utc)
    field = "driver_payment_status" if action == "driver_payment" else "denkma_payment_status"
    current_status = (parcel.get("relay_settlement") or {}).get(field, "pending")
    if current_status in {"validated", "declared"}:
        return {"ok": True, "relay_financial": summary}
    if current_status not in {"pending", "rejected"}:
        raise forbidden_exception("Ce règlement ne peut pas être déclaré dans son état actuel")
    update = {
        f"relay_settlement.{field}": "declared",
        f"relay_settlement.{field}_declared_at": now,
        f"relay_settlement.{field}_declared_by": current_user.get("user_id"),
        "updated_at": now,
    }
    await db.parcels.update_one(
        {"parcel_id": parcel_id, f"relay_settlement.{field}": {"$in": [None, "pending", "rejected"]}},
        {"$set": update},
    )
    updated = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    return {"ok": True, "relay_financial": build_relay_financial_summary(updated, relay_id)}




@router.get("/{relay_id}/financial-actions", summary="Actions de paiement du relais, y compris après remise des colis")
async def relay_financial_actions(
    relay_id: str, skip: int = Query(0, ge=0), limit: int = Query(20, ge=1, le=100),
    pending_only: bool = True, current_user: dict = Depends(get_current_user),
):
    relay = await _get_relay_or_404(relay_id)
    if not _can_manage_relay(relay, current_user):
        raise forbidden_exception("Accès refusé aux règlements de ce relais")
    query = {"status": {"$in": sorted(RELAY_FINANCIAL_STATUSES)}, "$or": [
        {"origin_relay_id": relay_id}, {"destination_relay_id": relay_id}, {"redirect_relay_id": relay_id},
    ]}
    cursor = db.parcels.find(query, {"_id": 0}).sort([("updated_at", -1), ("parcel_id", 1)])
    items, total, pending_count, unavailable = [], 0, 0, 0
    async for parcel in cursor:
        try:
            summary = build_relay_financial_summary(parcel, relay_id)
        except DeliveryCommissionDataError:
            unavailable += 1
            logger.warning("Invalid financial data for parcel %s", parcel.get("parcel_id"))
            continue
        for action in summary["actions"]:
            if float(action.get("amount_xof") or 0) <= 0:
                continue
            actionable = action["key"] in {"driver_payment", "denkma_payment"} and action["status"] in {"pending", "rejected"}
            pending_count += int(actionable)
            if pending_only and not actionable:
                continue
            if skip <= total < skip + limit:
                items.append({
                    **action, "actionable": actionable, "parcel_id": parcel["parcel_id"],
                    "tracking_code": parcel.get("tracking_code") or parcel["parcel_id"],
                    "updated_at": parcel.get("updated_at"), "delivery_mode": summary["mode"],
                    "driver_id": parcel.get("assigned_driver_id") if action["key"] == "driver_payment" else None,
                })
            total += 1
    driver_ids = list({item["driver_id"] for item in items if item.get("driver_id")})
    drivers = await db.users.find({"user_id": {"$in": driver_ids}}, {"_id": 0, "user_id": 1, "name": 1, "phone": 1}).to_list(length=len(driver_ids)) if driver_ids else []
    lookup = {driver["user_id"]: driver for driver in drivers}
    for item in items:
        driver = lookup.get(item.get("driver_id")) or {}
        item["beneficiary_name"] = (
            driver.get("name") or "Livreur du colis" if item["key"] == "driver_payment"
            else "Denkma" if item["key"] == "denkma_payment" else relay.get("name") or "Votre relais"
        )
        item["beneficiary_phone"] = driver.get("phone")
    return {"actions": items, "total": total, "pending_count": pending_count, "unavailable_count": unavailable,
            "has_more": skip + len(items) < total}


@router.get("/{relay_id}/history", summary="Historique des colis remis par ce relais")
async def relay_history(relay_id: str, current_user: dict = Depends(get_current_user)):
    relay = await _get_relay_or_404(relay_id)
    if not _can_manage_relay(relay, current_user):
        raise forbidden_exception("Acces refuse a cet historique relais")

    cursor = db.parcels.find(
        {
            "status": "delivered",
            "$or": [
                {"destination_relay_id": relay_id},
                {"redirect_relay_id": relay_id},
            ],
        },
        {"_id": 0},
    ).sort("updated_at", -1).limit(50)
    parcels = await cursor.to_list(length=50)
    return {"parcels": [serialize_parcel(p, current_user) for p in parcels], "total": len(parcels)}


@router.get("/{relay_id}/performance", summary="Performance mensuelle du relais")
async def relay_performance(
    relay_id: str,
    period: Optional[str] = Query(None),
    current_user: dict = Depends(get_current_user),
):
    relay = await _get_relay_or_404(relay_id)
    if not _can_manage_relay(relay, current_user):
        raise forbidden_exception("Acces refuse a cette performance relais")

    normalized_period, start, end = _period_bounds(period)
    rewards = await get_performance_rewards_settings()
    rules = rewards["relay"]["volume_bonuses"]
    processed = await db.parcels.count_documents({
        "$or": [
            {"origin_relay_id": relay_id},
            {"destination_relay_id": relay_id},
            {"redirect_relay_id": relay_id},
            {"transit_relay_id": relay_id},
        ],
        "updated_at": {"$gte": start, "$lte": end},
    })
    delivered = await db.parcels.count_documents({
        "status": "delivered",
        "$or": [
            {"destination_relay_id": relay_id},
            {"redirect_relay_id": relay_id},
        ],
        "updated_at": {"$gte": start, "$lte": end},
    })
    stock = await db.parcels.count_documents({
        "$or": [
            {"origin_relay_id": relay_id, "status": "dropped_at_origin_relay"},
            {"destination_relay_id": relay_id, "status": {"$in": ["at_destination_relay", "available_at_relay"]}},
            {"redirect_relay_id": relay_id, "status": {"$in": ["redirected_to_relay", "at_destination_relay", "available_at_relay"]}},
        ],
    })
    projected_bonus = 0
    next_threshold = None
    for rule in sorted(rules, key=lambda item: item["min_parcels"]):
        if processed >= rule["min_parcels"]:
            projected_bonus = max(projected_bonus, rule["amount_xof"])
        elif next_threshold is None:
            next_threshold = rule["min_parcels"]

    return {
        "period": normalized_period,
        "relay_id": relay_id,
        "parcels_processed": processed,
        "parcels_delivered": delivered,
        "stock_count": stock,
        "projected_bonus_xof": projected_bonus,
        "next_bonus_threshold": next_threshold,
        "is_active": relay.get("is_active", False),
        "is_verified": relay.get("is_verified", False),
    }


@router.post("", response_model=RelayPoint, summary="Créer un relais (admin)")
async def create_relay_point(
    body: RelayPointCreate,
    current_user: dict = Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    opening_hours = normalize_opening_hours(body.opening_hours)
    if not has_enabled_opening_day(opening_hours):
        raise bad_request_exception("Sélectionnez au moins un jour et définissez ses horaires d’ouverture.")
    now = datetime.now(timezone.utc)
    address = await geocode_relay_address(body.address)
    relay_doc = {
        "relay_id":          _relay_id(),
        "owner_user_id":     current_user["user_id"],
        "agent_user_ids":    [],
        "name":              body.name,
        "address":           address.model_dump(),
        "relay_type":        body.relay_type,
        "phone":             body.phone,
        "max_capacity":      body.max_capacity,
        "current_load":      0,
        "opening_hours":     opening_hours,
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
    return _with_opening_status(RelayPoint(**{k: v for k, v in relay_doc.items() if k != "_id"}).model_dump())


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
    is_owner = relay.get("owner_user_id") == current_user.get("user_id")
    is_agent = (
        current_user.get("user_id") in (relay.get("agent_user_ids") or [])
        or current_user.get("relay_point_id") == relay.get("relay_id")
    )
    if not is_admin and not is_owner and not is_agent:
        raise forbidden_exception()

    updates = body.model_dump(exclude_none=True)
    if "description" in body.model_fields_set:
        updates["description"] = body.description
    if "opening_hours" in updates:
        updates["opening_hours"] = normalize_opening_hours(updates["opening_hours"])
        if not has_enabled_opening_day(updates["opening_hours"]):
            raise bad_request_exception("Sélectionnez au moins un jour et définissez ses horaires d’ouverture.")
    if "address" in updates:
        updates["address"] = (await geocode_relay_address(body.address)).model_dump()
        if not is_admin:
            if not updates["address"].get("geopin"):
                raise bad_request_exception("Choisissez la position précise proposée sur la carte.")
            current_address = Address.model_validate(_relay_address(relay)).model_dump()
            proposed = updates.pop("address")
            if proposed != current_address:
                pending = relay.get("location_change_request") or {}
                if pending.get("status") != "pending" or pending.get("address") != proposed:
                    updates["location_change_request"] = {
                        "request_id": f"rlc_{uuid.uuid4().hex[:16]}",
                        "status": "pending", "address": proposed,
                        "requested_by": current_user["user_id"],
                        "requested_at": datetime.now(timezone.utc),
                    }
        else:
            # Keep legacy readers on the same approved coordinates.
            pin = updates["address"].get("geopin") or {}
            updates["latitude"], updates["longitude"] = pin.get("lat"), pin.get("lng")
            if (relay.get("location_change_request") or {}).get("status") == "pending":
                raise conflict_exception("Traitez d’abord la demande de changement d’emplacement du relais.")
    if updates:
        updates["updated_at"] = datetime.now(timezone.utc)
        await db.relay_points.update_one({"relay_id": relay_id}, {"$set": updates})

    updated = await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0})
    if "location_change_request" in updates:
        await record_admin_event(
            AdminEventType.RELAY_LOCATION_REQUESTED,
            title="Changement d’emplacement à valider",
            message=f"{relay.get('name') or relay_id} propose une nouvelle adresse. La position actuelle reste publique.",
            href=f"/dashboard/relays/{relay_id}",
            metadata={"relay_id": relay_id, "request_id": updates["location_change_request"]["request_id"]},
        )
    return _with_opening_status(updated, management=True)


@router.post("/{relay_id}/location-review", summary="Valider ou refuser un changement d’emplacement (admin)")
async def review_relay_location(
    relay_id: str, body: RelayLocationReview,
    current_user: dict = Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    relay = await _get_relay_or_404(relay_id)
    proposal = relay.get("location_change_request") or {}
    if proposal.get("request_id") != body.request_id or proposal.get("status") != "pending":
        raise conflict_exception("Cette demande a déjà été traitée ou remplacée. Actualisez la fiche.")
    reason = (body.reason or "").strip()
    if body.decision == "rejected" and not reason:
        raise bad_request_exception("Indiquez au relais pourquoi cette position est refusée.")
    now = datetime.now(timezone.utc)
    updates = {"location_change_request": {
        **proposal, "status": body.decision, "reason": reason or None,
        "reviewed_by": current_user["user_id"], "reviewed_at": now,
        "previous_address": _relay_address(relay),
    }, "updated_at": now}
    if body.decision == "approved":
        address = Address.model_validate(proposal["address"])
        if address.geopin is None:
            raise bad_request_exception("La demande ne contient pas de position précise.")
        updates.update(address=address.model_dump(), latitude=address.geopin.lat, longitude=address.geopin.lng)
    result = await db.relay_points.update_one({
        "relay_id": relay_id, "location_change_request.request_id": body.request_id,
        "location_change_request.status": "pending",
    }, {"$set": updates})
    if result.matched_count == 0:
        raise conflict_exception("La demande a changé. Actualisez la fiche avant de décider.")
    await record_admin_event(
        AdminEventType.RELAY_LOCATION_REVIEWED,
        title="Emplacement relais validé" if body.decision == "approved" else "Emplacement relais refusé",
        message=f"{relay.get('name') or relay_id} · {reason}", href=f"/dashboard/relays/{relay_id}",
        metadata={"relay_id": relay_id, "request_id": body.request_id, "decision": body.decision, "admin_id": current_user["user_id"]},
    )
    return _with_opening_status(await _get_relay_or_404(relay_id), management=True)
