"""
Service promotions : recherche de la meilleure promo applicable + enregistrement.
"""
from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4


async def find_best_promo(
    db,
    delivery_mode:     str,
    original_price:    float,
    user_id:           str,
    user_tier:         str,
    is_first_delivery: bool,
    promo_code:        Optional[str] = None,
) -> Optional[dict]:
    """
    Cherche la meilleure promo applicable pour ce devis.
    - promo_code fourni → cherche ce code précis
    - promo_code absent → cherche promos automatiques (sans code requis)
    Retourne {promo, discount_xof, final_price, express_free} ou None.
    """
    now = datetime.now(timezone.utc)

    if promo_code:
        query = {
            "promo_code": promo_code.upper().strip(),
            "is_active":  True,
            "start_date": {"$lte": now},
            "end_date":   {"$gte": now},
        }
    else:
        # Promos automatiques (sans code)
        query = {
            "promo_code": None,
            "is_active":  True,
            "start_date": {"$lte": now},
            "end_date":   {"$gte": now},
        }

    promos = await db.promotions.find(query).to_list(50)

    best      = None
    best_disc = 0.0

    for p in promos:
        target = p.get("target", "all")

        # Vérifier la cible
        if target == "first_delivery"  and not is_first_delivery:                      continue
        if target == "tier_silver"     and user_tier not in ("silver", "gold"):         continue
        if target == "tier_gold"       and user_tier != "gold":                         continue
        if target == "delivery_mode"   and p.get("delivery_mode") != delivery_mode:    continue

        # Montant minimum
        min_amt = p.get("min_amount")
        if min_amt and original_price < min_amt:
            continue

        # Quota total
        max_total = p.get("max_uses_total")
        if max_total and p.get("uses_count", 0) >= max_total:
            continue

        # Quota par utilisateur
        max_per = p.get("max_uses_per_user", 1)
        user_uses = await db.promo_uses.count_documents({
            "promo_id": p["promo_id"],
            "user_id":  user_id,
        })
        if user_uses >= max_per:
            continue

        # Cas spécial express_upgrade : pas de réduction XOF directe
        if p.get("promo_type") == "express_upgrade":
            return {
                "promo":        p,
                "discount_xof": 0.0,
                "final_price":  original_price,
                "express_free": True,
            }

        # Calcul réduction
        promo_type = p.get("promo_type")
        if promo_type == "free_delivery":
            disc = original_price
        elif promo_type == "percentage":
            disc = round(original_price * p.get("value", 0) / 100)
        elif promo_type == "fixed_amount":
            disc = min(p.get("value", 0), original_price)
        else:
            disc = 0.0

        if disc > best_disc:
            best_disc = disc
            best = p

    if best is None:
        return None

    final = max(0.0, original_price - best_disc)
    return {
        "promo":        best,
        "discount_xof": best_disc,
        "final_price":  final,
        "express_free": False,
    }


async def record_promo_use(db, promo_id: str, user_id: str, parcel_id: str):
    """Enregistre l'utilisation et incrémente le compteur."""
    now = datetime.now(timezone.utc)
    await db.promo_uses.insert_one({
        "use_id":     f"puse_{uuid4().hex[:12]}",
        "promo_id":   promo_id,
        "user_id":    user_id,
        "parcel_id":  parcel_id,
        "created_at": now,
    })
    await db.promotions.update_one(
        {"promo_id": promo_id},
        {"$inc": {"uses_count": 1}},
    )
