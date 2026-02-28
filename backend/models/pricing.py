from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel
from models.common import DeliveryMode


class PricingZone(BaseModel):
    zone_id:    str
    name:       str      # "Dakar Centre", "Banlieue", "Hors Dakar"
    relay_ids:  List[str] = []
    districts:  List[str] = []
    is_active:  bool = True
    created_at: datetime


class PricingZoneCreate(BaseModel):
    name:      str
    relay_ids: List[str] = []
    districts: List[str] = []


class PricingRule(BaseModel):
    rule_id:              str
    name:                 str
    delivery_mode:        DeliveryMode
    origin_zone_id:       Optional[str] = None
    destination_zone_id:  Optional[str] = None
    base_price:           float         # XOF
    price_per_kg:         float = 0.0
    price_per_km:         float = 0.0
    min_price:            float
    max_price:            Optional[float] = None
    # Surcharges
    insurance_rate:       float = 0.02  # 2% de la valeur déclarée
    is_active:            bool  = True
    created_at:           datetime


class PricingRuleCreate(BaseModel):
    name:                 str
    delivery_mode:        DeliveryMode
    origin_zone_id:       Optional[str] = None
    destination_zone_id:  Optional[str] = None
    base_price:           float
    price_per_kg:         float = 0.0
    price_per_km:         float = 0.0
    min_price:            float
    max_price:            Optional[float] = None
    insurance_rate:       float = 0.02


class PricingRuleUpdate(BaseModel):
    name:                 Optional[str]   = None
    base_price:           Optional[float] = None
    price_per_kg:         Optional[float] = None
    price_per_km:         Optional[float] = None
    min_price:            Optional[float] = None
    max_price:            Optional[float] = None
    insurance_rate:       Optional[float] = None
    is_active:            Optional[bool]  = None
