from fastapi import APIRouter, Depends, HTTPException, Query
from datetime import datetime, timezone
from typing import List

from core.dependencies import require_role
from database import db
from models.common import UserRole
from models.promotion import Promotion, PromotionCreate, PromotionUpdate
from services.admin_events_service import AdminEventType, record_admin_event

router = APIRouter(prefix="/promotions", tags=["Promotions"])

# Dependency shorthand
require_admin = require_role(UserRole.ADMIN, UserRole.SUPERADMIN)

@router.post("", response_model=dict, summary="Créer une offre promotionnelle (Admin)")
async def create_promotion(
    body: PromotionCreate,
    current_user: dict = Depends(require_admin),
):
    """
    Crée une nouvelle promotion. 
    Si promo_code est None, elle s'applique automatiquement si les conditions sont remplies.
    """
    promo = Promotion(**body.model_dump(), created_by=current_user["user_id"])
    await db.promotions.insert_one(promo.model_dump())
    await record_admin_event(
        AdminEventType.PROMOTION_CREATED,
        title=f"Promotion créée : {promo.title}",
        message=f"Promotion {promo.promo_id}",
        href="/dashboard/promotions",
        metadata={"promo_id": promo.promo_id, "promo_code": promo.promo_code},
    )
    return {"promo_id": promo.promo_id, "message": "Promotion créée avec succès"}


@router.get("", response_model=dict, summary="Lister toutes les promotions (Admin)")
async def list_promotions(
    active_only: bool = Query(False),
    current_user: dict = Depends(require_admin),
):
    query = {}
    if active_only:
        now = datetime.now(timezone.utc)
        query = {
            "is_active": True,
            "start_date": {"$lte": now},
            "end_date": {"$gte": now}
        }
    
    promos = await db.promotions.find(query).sort("created_at", -1).to_list(100)
    # Ensure datetime objects are converted to ISO strings for JSON if needed (FastAPI handles it)
    return {"promotions": promos}


@router.put("/{promo_id}", summary="Modifier une promotion (Admin)")
async def update_promotion(
    promo_id: str,
    body: dict,
    current_user: dict = Depends(require_admin),
):
    updates = body.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=400, detail="Aucun champ valide à mettre à jour")
    promo = await db.promotions.find_one({"promo_id": promo_id}, {"_id": 0})
    if not promo:
        raise HTTPException(status_code=404, detail="Promotion non trouvée")
    if "end_date" in updates and updates["end_date"] <= promo.get("start_date"):
        raise HTTPException(status_code=400, detail="La date de fin doit être postérieure au début")
    if promo.get("promo_type") == "percentage" and "value" in updates and updates["value"] > 100:
        raise HTTPException(status_code=400, detail="Une remise en pourcentage ne peut pas dépasser 100 %")
    result = await db.promotions.update_one({"promo_id": promo_id}, {"$set": updates})
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Promotion non trouvée")
    
    await record_admin_event(
        AdminEventType.PROMOTION_UPDATED,
        title=f"Promotion modifiée : {promo.get('title') or promo_id}",
        message=f"Promotion {promo_id}",
        href="/dashboard/promotions",
        metadata={"promo_id": promo_id, "updates": updates},
    )
    return {"message": "Promotion mise à jour"}


@router.delete("/{promo_id}", summary="Supprimer une promotion (Admin)")
async def delete_promotion(
    promo_id: str,
    current_user: dict = Depends(require_admin),
):
    promo = await db.promotions.find_one({"promo_id": promo_id}, {"_id": 0})
    if not promo:
        raise HTTPException(status_code=404, detail="Promotion non trouvée")
    uses_count = await db.promo_uses.count_documents({"promo_id": promo_id})
    if uses_count:
        await db.promotions.update_one({"promo_id": promo_id}, {"$set": {"is_active": False}})
        await record_admin_event(
            AdminEventType.PROMOTION_DISABLED,
            title=f"Promotion désactivée : {promo.get('title') or promo_id}",
            message=f"Promotion {promo_id}",
            href="/dashboard/promotions",
            metadata={"promo_id": promo_id, "uses_count": uses_count},
        )
        return {"message": "Promotion désactivée pour conserver son historique", "deactivated": True}
    await db.promotions.delete_one({"promo_id": promo_id})
    return {"message": "Promotion supprimée", "deactivated": False}


@router.get("/{promo_id}/stats", response_model=dict, summary="Statistiques et historique d'une promotion")
async def promotion_stats(
    promo_id: str,
    from_date: datetime | None = Query(None),
    to_date: datetime | None = Query(None),
    current_user: dict = Depends(require_admin),
):
    promo = await db.promotions.find_one({"promo_id": promo_id}, {"_id": 0})
    if not promo:
        raise HTTPException(status_code=404, detail="Promotion non trouvée")
    query: dict = {"promo_id": promo_id}
    if from_date or to_date:
        query["created_at"] = {key: value for key, value in (("$gte", from_date), ("$lte", to_date)) if value is not None}
    uses = await db.promo_uses.find(query, {"_id": 0}).sort("created_at", -1).to_list(length=500)
    parcel_ids = [use.get("parcel_id") for use in uses if use.get("parcel_id")]
    parcels = await db.parcels.find(
        {"parcel_id": {"$in": parcel_ids or ["__none__"]}},
        {"_id": 0, "parcel_id": 1, "tracking_code": 1, "sender_user_id": 1, "discount_xof": 1, "original_price": 1, "paid_price": 1, "created_at": 1},
    ).to_list(length=len(parcel_ids) or 1)
    parcel_by_id = {parcel.get("parcel_id"): parcel for parcel in parcels}
    items = []
    discount_total = 0.0
    revenue_total = 0.0
    users = set()
    for use in uses:
        parcel = parcel_by_id.get(use.get("parcel_id"), {})
        discount = float(parcel.get("discount_xof") or 0.0)
        revenue = float(parcel.get("paid_price") or parcel.get("original_price") or 0.0)
        discount_total += discount
        revenue_total += revenue
        if use.get("user_id"):
            users.add(use["user_id"])
        items.append({"use_id": use.get("use_id"), "user_id": use.get("user_id"), "parcel_id": use.get("parcel_id"), "tracking_code": parcel.get("tracking_code"), "discount_xof": round(discount, 2), "revenue_xof": round(revenue, 2), "created_at": use.get("created_at")})
    return {"promo_id": promo_id, "uses": len(uses), "unique_users": len(users), "discount_total_xof": round(discount_total, 2), "revenue_total_xof": round(revenue_total, 2), "history": items}
