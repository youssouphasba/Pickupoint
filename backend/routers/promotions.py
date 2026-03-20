from fastapi import APIRouter, Depends, HTTPException, Query
from datetime import datetime, timezone
from typing import List

from core.dependencies import require_role
from database import db
from models.common import UserRole
from models.promotion import Promotion, PromotionCreate

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
    # Only allow updating some fields
    allowed_fields = {
        "title", "description", "is_active", "end_date",
        "max_uses_total", "max_uses_per_user", "value", "min_amount",
        "target_user_ids",
    }
    updates = {k: v for k, v in body.items() if k in allowed_fields}
    if not updates:
        raise HTTPException(status_code=400, detail="Aucun champ valide à mettre à jour")
    
    result = await db.promotions.update_one({"promo_id": promo_id}, {"$set": updates})
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Promotion non trouvée")
    
    return {"message": "Promotion mise à jour"}


@router.delete("/{promo_id}", summary="Supprimer une promotion (Admin)")
async def delete_promotion(
    promo_id: str,
    current_user: dict = Depends(require_admin),
):
    result = await db.promotions.delete_one({"promo_id": promo_id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Promotion non trouvée")
    return {"message": "Promotion supprimée"}
