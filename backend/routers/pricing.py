"""
Router pricing : zones tarifaires et règles de prix.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from core.dependencies import require_role
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
async def get_quote(body: ParcelQuote):
    return await calculate_price(body)


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
        "insurance_rate":       body.insurance_rate,
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
