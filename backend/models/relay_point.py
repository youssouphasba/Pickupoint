from datetime import datetime
from typing import Dict, List, Optional

from pydantic import BaseModel, Field, field_validator

from models.common import Address, RelayType, clean_optional_text


class RelayPoint(BaseModel):
    relay_id: str
    owner_user_id: str
    agent_user_ids: List[str] = Field(default_factory=list)
    name: str
    address: Address
    relay_type: RelayType = RelayType.STANDARD
    phone: str
    description: Optional[str] = None
    max_capacity: int = 20
    current_load: int = 0
    opening_hours: Optional[Dict[str, str]] = None
    zone_ids: List[str] = Field(default_factory=list)
    coverage_radius_km: float = 5.0
    is_active: bool = True
    is_verified: bool = False
    score: float = 5.0
    store_id: Optional[str] = None
    external_ref: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class RelayPointCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=120)
    address: Address
    relay_type: RelayType = RelayType.STANDARD
    phone: str = Field(..., min_length=8, max_length=32)
    description: Optional[str] = Field(default=None, max_length=1000)
    max_capacity: int = Field(default=20, ge=1, le=10000)
    opening_hours: Optional[Dict[str, str]] = None
    store_id: Optional[str] = Field(default=None, max_length=120)

    @field_validator("name", "phone", "description", "store_id")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class RelayPointUpdate(BaseModel):
    name: Optional[str] = Field(default=None, max_length=120)
    address: Optional[Address] = None
    phone: Optional[str] = Field(default=None, max_length=32)
    description: Optional[str] = Field(default=None, max_length=1000)
    max_capacity: Optional[int] = Field(default=None, ge=1, le=10000)
    opening_hours: Optional[Dict[str, str]] = None
    relay_type: Optional[RelayType] = None
    is_active: Optional[bool] = None

    @field_validator("name", "phone", "description")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)
