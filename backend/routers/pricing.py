"""
Router pricing : zones tarifaires et règles de prix.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query, Request
from typing import Optional

from core.dependencies import require_role, get_current_user_optional
from core.exceptions import not_found_exception
from database import db
from models.common import UserRole
from models.pricing import (
    PricingZone, PricingZoneCreate,
    PricingRule, PricingRuleCreate, PricingRuleUpdate,
)
from models.parcel import ParcelQuote, QuoteResponse
from services.pricing_service import calculate_price

router = APIRouter()

from core.limiter import limiter


def _zone_id() -> str:
    return f"zon_{uuid.uuid4().hex[:12]}"


def _rule_id() -> str:
    return f"prl_{uuid.uuid4().hex[:12]}"


# ── Public ────────────────────────────────────────────────────────────────────
@router.get("/zones", summary="Liste des zones tarifaires (public)")
async def list_zones():
    cursor = db.pricing_zones.find({"is_active": True}, {"_id": 0})
    return {"zones": await cursor.to_list(length=100)}


@router.post("/quote", response_model=QuoteResponse, summary="Calculer un devis (public)")
@limiter.limit("15/minute")
async def get_quote(
    body: ParcelQuote, 
    request: Request,
    current_user: Optional[dict] = Depends(get_current_user_optional)
):
    sender_tier = "bronze"
    is_frequent = False
    
    is_first = False
    
    if current_user:
        user_id = current_user["user_id"]
        user = await db.users.find_one({"user_id": user_id})
        if user:
            sender_tier = user.get("loyalty_tier", "bronze")
            
            # Check for frequent sender (>= 10 delivered in last 30 days)
            from datetime import datetime, timezone, timedelta
            month_ago = datetime.now(timezone.utc) - timedelta(days=30)
            delivered_count = await db.parcels.count_documents({
                "sender_user_id": user_id,
                "status": "delivered",
                "created_at": {"$gte": month_ago}
            })
            is_frequent = delivered_count >= 10

            # Check for first delivery
            total_delivered = await db.parcels.count_documents({
                "sender_user_id": user_id,
                "status": "delivered"
            })
            is_first = (total_delivered == 0)

    return await calculate_price(
        body, 
        sender_tier=sender_tier, 
        is_frequent=is_frequent,
        user_id=current_user["user_id"] if current_user else None,
        is_first_delivery=is_first
    )


# ── Admin ─────────────────────────────────────────────────────────────────────
@router.get("/rules", summary="Liste des règles (admin)")
async def list_rules(
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    cursor = db.pricing_rules.find({}, {"_id": 0})
    return {"rules": await cursor.to_list(length=200)}


@router.post("/zones", response_model=PricingZone, summary="Créer une zone (admin)")
async def create_zone(
    body: PricingZoneCreate,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    now = datetime.now(timezone.utc)
    zone_doc = {
        "zone_id":    _zone_id(),
        "name":       body.name,
        "relay_ids":  body.relay_ids,
        "districts":  body.districts,
        "is_active":  True,
        "created_at": now,
    }
    await db.pricing_zones.insert_one(zone_doc)
    return PricingZone(**{k: v for k, v in zone_doc.items() if k != "_id"})


@router.post("/rules", response_model=PricingRule, summary="Créer une règle (admin)")
async def create_rule(
    body: PricingRuleCreate,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    now = datetime.now(timezone.utc)
    rule_doc = {
        "rule_id":              _rule_id(),
        "name":                 body.name,
        "delivery_mode":        body.delivery_mode.value,
        "origin_zone_id":       body.origin_zone_id,
        "destination_zone_id":  body.destination_zone_id,
        "base_price":           body.base_price,
        "price_per_kg":         body.price_per_kg,
        "price_per_km":         body.price_per_km,
        "min_price":            body.min_price,
        "max_price":            body.max_price,
        "is_active":            True,
        "created_at":           now,
    }
    await db.pricing_rules.insert_one(rule_doc)
    return PricingRule(**{k: v for k, v in rule_doc.items() if k != "_id"})


@router.put("/rules/{rule_id}", summary="Modifier une règle (admin)")
async def update_rule(
    rule_id: str,
    body: PricingRuleUpdate,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    updates = body.model_dump(exclude_none=True)
    if not updates:
        raise not_found_exception("Aucun champ à mettre à jour")
    await db.pricing_rules.update_one({"rule_id": rule_id}, {"$set": updates})
    updated = await db.pricing_rules.find_one({"rule_id": rule_id}, {"_id": 0})
    if not updated:
        raise not_found_exception("Règle de prix")
    return updated
