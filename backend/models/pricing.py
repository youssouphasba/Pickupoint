from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator

from models.common import DeliveryMode, clean_optional_text


class PricingZone(BaseModel):
    zone_id: str
    name: str
    relay_ids: List[str] = Field(default_factory=list)
    districts: List[str] = Field(default_factory=list)
    is_active: bool = True
    created_at: datetime


class PricingZoneCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=120)
    relay_ids: List[str] = Field(default_factory=list, max_length=500)
    districts: List[str] = Field(default_factory=list, max_length=500)

    @field_validator("name")
    @classmethod
    def normalize_name(cls, value: str) -> str:
        cleaned = clean_optional_text(value)
        if not cleaned:
            raise ValueError("Champ requis")
        return cleaned


class PricingRule(BaseModel):
    rule_id: str
    name: str
    delivery_mode: DeliveryMode
    origin_zone_id: Optional[str] = None
    destination_zone_id: Optional[str] = None
    base_price: float
    price_per_kg: float = 0.0
    price_per_km: float = 0.0
    min_price: float
    max_price: Optional[float] = None
    is_active: bool = True
    created_at: datetime


class PricingRuleCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=120)
    delivery_mode: DeliveryMode
    origin_zone_id: Optional[str] = Field(default=None, max_length=80)
    destination_zone_id: Optional[str] = Field(default=None, max_length=80)
    base_price: float = Field(..., ge=0, le=10_000_000)
    price_per_kg: float = Field(default=0.0, ge=0, le=10_000_000)
    price_per_km: float = Field(default=0.0, ge=0, le=10_000_000)
    min_price: float = Field(..., ge=0, le=10_000_000)
    max_price: Optional[float] = Field(default=None, ge=0, le=10_000_000)

    @field_validator("name", "origin_zone_id", "destination_zone_id")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class PricingRuleUpdate(BaseModel):
    name: Optional[str] = Field(default=None, max_length=120)
    base_price: Optional[float] = Field(default=None, ge=0, le=10_000_000)
    price_per_kg: Optional[float] = Field(default=None, ge=0, le=10_000_000)
    price_per_km: Optional[float] = Field(default=None, ge=0, le=10_000_000)
    min_price: Optional[float] = Field(default=None, ge=0, le=10_000_000)
    max_price: Optional[float] = Field(default=None, ge=0, le=10_000_000)
    is_active: Optional[bool] = None

    @field_validator("name")
    @classmethod
    def normalize_name(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)
