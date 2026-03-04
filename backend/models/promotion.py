from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field
from uuid import uuid4


class PromoType(str, Enum):
    PERCENTAGE      = "percentage"       # ex: -20%
    FIXED_AMOUNT    = "fixed_amount"     # ex: -500 XOF
    FREE_DELIVERY   = "free_delivery"    # 0 XOF
    EXPRESS_UPGRADE = "express_upgrade"  # express offert (pas de ×1.40)


class PromoTarget(str, Enum):
    ALL            = "all"              # tous les clients
    FIRST_DELIVERY = "first_delivery"   # 1ère livraison seulement
    TIER_SILVER    = "tier_silver"      # clients Argent+
    TIER_GOLD      = "tier_gold"        # clients Or seulement
    DELIVERY_MODE  = "delivery_mode"    # mode spécifique (ex: relay_to_relay)


class PromotionCreate(BaseModel):
    title:              str
    description:        str = ""
    promo_type:         PromoType
    value:              float = 0.0        # % (20.0 pour -20%) ou XOF (500)
    target:             PromoTarget = PromoTarget.ALL
    delivery_mode:      Optional[str] = None  # si target=DELIVERY_MODE
    min_amount:         Optional[float] = None
    max_uses_total:     Optional[int]   = None  # None = illimité
    max_uses_per_user:  int = 1
    promo_code:         Optional[str]   = None  # None = automatique
    start_date:         datetime
    end_date:           datetime
    is_active:          bool = True


class Promotion(PromotionCreate):
    promo_id:    str = Field(default_factory=lambda: f"promo_{uuid4().hex[:12]}")
    uses_count:  int = 0
    created_by:  str = ""
    created_at:  datetime = Field(default_factory=lambda: datetime.now(__import__('datetime').timezone.utc))


class PromoUse(BaseModel):
    use_id:     str
    promo_id:   str
    user_id:    str
    parcel_id:  str
    created_at: datetime
