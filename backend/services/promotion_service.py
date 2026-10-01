"""
Service promotions : recherche de la meilleure promo applicable + enregistrement.
"""
from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4
from core.exceptions import bad_request_exception
from services.wallet_service import _run_in_transaction


def apply_promotion(promo: dict, price: float, express_surcharge: float = 0.0) -> dict:
    kind = promo.get("promo_type")
    if kind == "express_upgrade":
        discount = express_surcharge
    elif kind == "free_delivery":
        discount = price
    elif kind == "percentage":
        discount = round(price * float(promo.get("value") or 0) / 100)
    elif kind == "fixed_amount":
        discount = float(promo.get("value") or 0)
    else:
        discount = 0.0
    discount = min(max(discount, 0.0), price)
    return {"promo": promo, "discount_xof": discount,
            "final_price": max(price - discount, 0.0), "express_free": kind == "express_upgrade"}


async def find_best_promo(
    db,
    delivery_mode:     str,
    original_price:    float,
    user_id:           str,
    user_tier:         str,
    is_first_delivery: bool,
    promo_code:        Optional[str] = None,
    *, express_surcharge: float = 0.0, express_enabled: bool = True,
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
        # Ciblage par utilisateurs spécifiques
        target_user_ids = p.get("target_user_ids")
        if target_user_ids and user_id not in target_user_ids:
            continue

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

        if p.get("promo_type") == "express_upgrade" and not express_enabled:
            continue
        disc = apply_promotion(p, original_price, express_surcharge)["discount_xof"]

        if disc > best_disc or (best is None and p.get("promo_type") == "express_upgrade"):
            best_disc = disc
            best = p

    if best is None:
        return None

    final = max(0.0, original_price - best_disc)
    return {
        "promo":        best,
        "discount_xof": best_disc,
        "final_price":  final,
        "express_free": best.get("promo_type") == "express_upgrade",
    }


async def record_promo_use(db, promo_id: str, user_id: str, parcel_id: str):
    now = datetime.now(timezone.utc)
    async def reserve(session):
        existing = await db.promo_uses.find_one({"promo_id": promo_id, "parcel_id": parcel_id}, session=session)
        if existing:
            if existing.get("user_id") != user_id:
                raise bad_request_exception("Utilisation promotionnelle incohérente")
            return existing
        promo = await db.promotions.find_one({"promo_id": promo_id}, session=session)
        if not promo:
            raise bad_request_exception("La promotion n'est plus disponible")
        query = {"promo_id": promo_id, "is_active": True, "start_date": {"$lte": now}, "end_date": {"$gte": now}}
        if promo.get("max_uses_total"):
            query["$or"] = [{"uses_count": {"$lt": promo["max_uses_total"]}}, {"uses_count": None}]
        result = await db.promotions.update_one(query, {"$inc": {"uses_count": 1}}, session=session)
        if result.modified_count != 1:
            raise bad_request_exception("Le quota de cette promotion est atteint ou l'offre a expiré. Demandez un nouveau devis.")
        uses = await db.promo_uses.count_documents({"promo_id": promo_id, "user_id": user_id}, session=session)
        if uses >= int(promo.get("max_uses_per_user", 1)):
            raise bad_request_exception("Vous avez déjà utilisé cette promotion le nombre de fois autorisé")
        receipt = {"_id": f"promo_use:{promo_id}:{parcel_id}", "use_id": f"puse_{uuid4().hex[:12]}",
                   "promo_id": promo_id, "user_id": user_id, "parcel_id": parcel_id, "created_at": now}
        await db.promo_uses.insert_one(receipt, session=session)
        return receipt
    return await _run_in_transaction(reserve)
