from datetime import datetime, timezone
from enum import Enum
from typing import List, Optional
from uuid import uuid4

from pydantic import BaseModel, Field, field_validator

from models.common import clean_optional_text


class PromoType(str, Enum):
    PERCENTAGE = "percentage"
    FIXED_AMOUNT = "fixed_amount"
    FREE_DELIVERY = "free_delivery"
    EXPRESS_UPGRADE = "express_upgrade"


class PromoTarget(str, Enum):
    ALL = "all"
    FIRST_DELIVERY = "first_delivery"
    TIER_SILVER = "tier_silver"
    TIER_GOLD = "tier_gold"
    DELIVERY_MODE = "delivery_mode"


class PromotionCreate(BaseModel):
    title: str = Field(..., min_length=2, max_length=120)
    description: str = Field(default="", max_length=1000)
    promo_type: PromoType
    value: float = Field(default=0.0, ge=0, le=1_000_000)
    target: PromoTarget = PromoTarget.ALL
    delivery_mode: Optional[str] = Field(default=None, max_length=80)
    target_user_ids: Optional[List[str]] = Field(default=None, max_length=1000)
    min_amount: Optional[float] = Field(default=None, ge=0)
    max_uses_total: Optional[int] = Field(default=None, ge=1)
    max_uses_per_user: int = Field(default=1, ge=1, le=100000)
    promo_code: Optional[str] = Field(default=None, max_length=40)
    start_date: datetime
    end_date: datetime
    is_active: bool = True

    @field_validator("title", "description", "delivery_mode", "promo_code")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class Promotion(PromotionCreate):
    promo_id: str = Field(default_factory=lambda: f"promo_{uuid4().hex[:12]}")
    uses_count: int = 0
    created_by: str = ""
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class PromoUse(BaseModel):
    use_id: str
    promo_id: str
    user_id: str
    parcel_id: str
    created_at: datetime
