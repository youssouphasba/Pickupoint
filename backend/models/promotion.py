from datetime import datetime, timezone
from typing import Optional
from pydantic import BaseModel, Field
from uuid import uuid4


class PromotionCreate(BaseModel):
    title:             str
    description:       str = ""
    promo_type:        str                     # "percentage" | "fixed_amount" | "free_delivery" | "express_upgrade"
    value:             float = 0.0            # % ou XOF selon promo_type
    target:            str   = "all"          # "all" | "first_delivery" | "tier_silver" | "tier_gold" | "delivery_mode"
    delivery_mode:     Optional[str] = None   # si target="delivery_mode"
    min_amount:        Optional[float] = None
    max_uses_total:    Optional[int]   = None # None = illimité
    max_uses_per_user: int = 1
    promo_code:        Optional[str]   = None # None = automatique (sans code)
    start_date:        datetime
    end_date:          datetime
    is_active:         bool = True


class Promotion(PromotionCreate):
    promo_id:   str      = Field(default_factory=lambda: f"promo_{uuid4().hex[:12]}")
    uses_count: int      = 0
    created_by: str      = ""
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
