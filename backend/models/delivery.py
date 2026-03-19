from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field

from models.common import Address, GeoPin


class MissionStatus(str, Enum):
    PENDING = "pending"
    ASSIGNED = "assigned"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    INCIDENT_REPORTED = "incident_reported"


class DeliveryMission(BaseModel):
    mission_id: str
    parcel_id: str
    driver_id: str
    status: MissionStatus = MissionStatus.PENDING
    pickup_relay_id: Optional[str] = None
    delivery_address: Optional[Address] = None
    driver_location: Optional[GeoPin] = None
    location_updated_at: Optional[datetime] = None
    proof_type: Optional[str] = None
    proof_data: Optional[str] = None
    pin_code: Optional[str] = None
    failure_reason: Optional[str] = None
    assigned_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


class ProofOfDelivery(BaseModel):
    proof_type: str
    proof_data: Optional[str] = None
    pin_code: Optional[str] = None
    location: Optional[GeoPin] = None


class CodeDelivery(BaseModel):
    delivery_code: str = Field(..., min_length=6, max_length=6)
    driver_lat: Optional[float] = Field(None, ge=-90, le=90)
    driver_lng: Optional[float] = Field(None, ge=-180, le=180)
    proof_type: Optional[str] = None
    proof_data: Optional[str] = None


class LocationUpdate(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    accuracy: Optional[float] = Field(None, ge=0)
