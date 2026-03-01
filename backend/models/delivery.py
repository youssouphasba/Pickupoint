from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel
from models.common import GeoPin, Address


class MissionStatus(str, Enum):
    PENDING     = "pending"
    ASSIGNED    = "assigned"
    IN_PROGRESS = "in_progress"
    COMPLETED   = "completed"
    FAILED      = "failed"
    CANCELLED   = "cancelled"


class DeliveryMission(BaseModel):
    mission_id:   str
    parcel_id:    str
    driver_id:    str
    status:       MissionStatus = MissionStatus.PENDING
    pickup_relay_id:  Optional[str]     = None
    delivery_address: Optional[Address] = None
    # Tracking GPS
    driver_location:     Optional[GeoPin]   = None
    location_updated_at: Optional[datetime] = None
    # Preuve de livraison
    proof_type:  Optional[str] = None   # "photo", "signature", "pin"
    proof_data:  Optional[str] = None   # base64 photo ou signature
    pin_code:    Optional[str] = None   # 4 chiffres
    # Raison échec
    failure_reason: Optional[str] = None  # "absent", "address_not_found", "refused"
    # Timestamps
    assigned_at:  Optional[datetime] = None
    started_at:   Optional[datetime] = None
    completed_at: Optional[datetime] = None
    created_at:   datetime
    updated_at:   datetime


class ProofOfDelivery(BaseModel):
    proof_type: str              # "photo", "pin"
    proof_data: Optional[str] = None   # base64
    pin_code:   Optional[str] = None
    location:   Optional[GeoPin] = None


class CodeDelivery(BaseModel):
    delivery_code: str
    driver_lat:    Optional[float] = None   # pour géofence 500m
    driver_lng:    Optional[float] = None


class LocationUpdate(BaseModel):
    lat: float
    lng: float
    accuracy: Optional[float] = None
