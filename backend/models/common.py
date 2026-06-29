from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, field_validator


class DeliveryMode(str, Enum):
    RELAY_TO_RELAY = "relay_to_relay"
    RELAY_TO_HOME = "relay_to_home"
    HOME_TO_RELAY = "home_to_relay"
    HOME_TO_HOME = "home_to_home"


class RelayType(str, Enum):
    STANDARD = "standard"
    MOBILE = "mobile"
    STATION = "station"


class ParcelStatus(str, Enum):
    CREATED = "created"
    DROPPED_AT_ORIGIN_RELAY = "dropped_at_origin_relay"
    IN_TRANSIT = "in_transit"
    AT_DESTINATION_RELAY = "at_destination_relay"
    AVAILABLE_AT_RELAY = "available_at_relay"
    OUT_FOR_DELIVERY = "out_for_delivery"
    DELIVERED = "delivered"
    DELIVERY_FAILED = "delivery_failed"
    REDIRECTED_TO_RELAY = "redirected_to_relay"
    CANCELLED = "cancelled"
    SUSPENDED = "suspended"
    EXPIRED = "expired"
    DISPUTED = "disputed"
    INCIDENT_REPORTED = "incident_reported"
    RETURNED = "returned"


class UserRole(str, Enum):
    CLIENT = "client"
    RELAY_AGENT = "relay_agent"
    DRIVER = "driver"
    ADMIN = "admin"
    SUPERADMIN = "superadmin"


def clean_optional_text(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    cleaned = " ".join(str(value).split())
    return cleaned or None


class GeoPin(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    accuracy: Optional[float] = Field(None, ge=0, le=10000)


class Address(BaseModel):
    label: Optional[str] = Field(default=None, max_length=240)
    geopin: Optional[GeoPin] = None
    city: Optional[str] = Field(default=None, max_length=120)
    district: Optional[str] = Field(default=None, max_length=120)
    notes: Optional[str] = Field(default=None, max_length=500)

    @field_validator("label", "city", "district", "notes")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)
