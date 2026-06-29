from datetime import datetime
from typing import Any, Dict, Optional

from pydantic import BaseModel, Field, field_validator, model_validator

from models.common import Address, DeliveryMode, GeoPin, ParcelStatus, clean_optional_text


def clean_required_text(value: str) -> str:
    cleaned = clean_optional_text(value)
    if not cleaned:
        raise ValueError("Champ requis")
    return cleaned


class Parcel(BaseModel):
    parcel_id: str
    tracking_code: str
    sender_user_id: str
    recipient_phone: str
    recipient_name: str
    delivery_mode: DeliveryMode
    origin_relay_id: Optional[str] = None
    destination_relay_id: Optional[str] = None
    delivery_address: Optional[Address] = None
    weight_kg: float = 0.5
    dimensions: Optional[Dict[str, float]] = None
    declared_value: Optional[float] = None
    description: Optional[str] = None
    parcel_photo_url: Optional[str] = None
    parcel_photo_path: Optional[str] = None
    parcel_photo_file_id: Optional[str] = None
    parcel_photo_filename: Optional[str] = None
    parcel_photo_storage: Optional[str] = None
    parcel_photo_content_type: Optional[str] = None
    parcel_photo_uploaded_at: Optional[datetime] = None
    is_express: bool = False
    who_pays: str = "sender"
    quoted_price: float
    paid_price: Optional[float] = None
    payment_status: str = "pending"
    payment_method: Optional[str] = None
    payment_ref: Optional[str] = None
    promo_id: Optional[str] = None
    pickup_code: str = ""
    delivery_code: str = ""
    return_code: Optional[str] = None
    status: ParcelStatus = ParcelStatus.CREATED
    assigned_driver_id: Optional[str] = None
    redirect_relay_id: Optional[str] = None
    transit_relay_id: Optional[str] = None
    rating: Optional[int] = None
    rating_comment: Optional[str] = None
    driver_tip: float = 0.0
    external_ref: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    expires_at: Optional[datetime] = None


class ParcelCreate(BaseModel):
    recipient_phone: str = Field(..., min_length=8, max_length=32)
    recipient_name: str = Field(..., min_length=2, max_length=120)
    delivery_mode: DeliveryMode
    origin_relay_id: Optional[str] = Field(default=None, max_length=80)
    destination_relay_id: Optional[str] = Field(default=None, max_length=80)
    delivery_address: Optional[Address] = None
    transit_relay_id: Optional[str] = Field(default=None, max_length=80)
    origin_location: Optional[Address] = None
    weight_kg: float = Field(default=0.5, gt=0, le=1000)
    dimensions: Optional[Dict[str, float]] = None
    declared_value: Optional[float] = Field(default=None, ge=0, le=1_000_000_000)
    description: Optional[str] = Field(default=None, max_length=1000)
    external_ref: Optional[str] = Field(default=None, max_length=120)
    is_express: bool = False
    who_pays: str = Field(default="sender", pattern="^(sender|recipient)$")
    promo_id: Optional[str] = Field(default=None, max_length=80)
    initiated_by: str = Field(default="sender", pattern="^(sender|recipient)$")
    sender_phone: Optional[str] = Field(default=None, max_length=32)
    pickup_voice_note: Optional[str] = None
    delivery_voice_note: Optional[str] = None

    @field_validator("recipient_phone", "recipient_name")
    @classmethod
    def normalize_required_text_fields(cls, value: str) -> str:
        return clean_required_text(value)

    @field_validator(
        "origin_relay_id",
        "destination_relay_id",
        "transit_relay_id",
        "description",
        "external_ref",
        "promo_id",
        "sender_phone",
    )
    @classmethod
    def normalize_optional_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)

    @model_validator(mode="after")
    def validate_delivery_mode_requirements(self):
        has_origin_gps = bool(self.origin_location and self.origin_location.geopin)
        has_delivery_address = self.delivery_address is not None

        if self.delivery_mode == DeliveryMode.RELAY_TO_RELAY:
            if not self.origin_relay_id or not self.destination_relay_id:
                raise ValueError("relay_to_relay requires origin_relay_id and destination_relay_id")
        elif self.delivery_mode == DeliveryMode.RELAY_TO_HOME:
            if not self.origin_relay_id:
                raise ValueError("relay_to_home requires origin_relay_id")
            if not has_delivery_address:
                raise ValueError("relay_to_home requires delivery_address")
        elif self.delivery_mode == DeliveryMode.HOME_TO_RELAY:
            if not has_origin_gps:
                raise ValueError("home_to_relay requires origin_location.geopin")
            if not self.destination_relay_id:
                raise ValueError("home_to_relay requires destination_relay_id")
        elif self.delivery_mode == DeliveryMode.HOME_TO_HOME:
            if not has_origin_gps:
                raise ValueError("home_to_home requires origin_location.geopin")
            if not has_delivery_address:
                raise ValueError("home_to_home requires delivery_address")

        return self


class ParcelEvent(BaseModel):
    event_id: str
    parcel_id: str
    event_type: str
    from_status: Optional[ParcelStatus] = None
    to_status: Optional[ParcelStatus] = None
    actor_id: Optional[str] = None
    actor_role: Optional[str] = None
    location: Optional[GeoPin] = None
    notes: Optional[str] = Field(default=None, max_length=1000)
    metadata: Dict[str, Any] = Field(default_factory=dict)
    created_at: datetime

    @field_validator("notes")
    @classmethod
    def normalize_notes(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class ParcelQuote(BaseModel):
    delivery_mode: DeliveryMode
    origin_relay_id: Optional[str] = Field(default=None, max_length=80)
    destination_relay_id: Optional[str] = Field(default=None, max_length=80)
    origin_location: Optional[Address] = None
    delivery_address: Optional[Address] = None
    weight_kg: float = Field(default=0.5, gt=0, le=1000)
    declared_value: Optional[float] = Field(default=None, ge=0, le=1_000_000_000)
    is_express: bool = False
    who_pays: str = Field(default="sender", pattern="^(sender|recipient)$")
    promo_code: Optional[str] = Field(default=None, max_length=80)

    @field_validator("origin_relay_id", "destination_relay_id", "promo_code")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)

    @model_validator(mode="after")
    def validate_quote_requirements(self):
        has_origin_gps = bool(self.origin_location and self.origin_location.geopin)
        has_delivery_address = self.delivery_address is not None

        if self.delivery_mode == DeliveryMode.RELAY_TO_RELAY:
            if not self.origin_relay_id or not self.destination_relay_id:
                raise ValueError("relay_to_relay requires origin_relay_id and destination_relay_id")
        elif self.delivery_mode == DeliveryMode.RELAY_TO_HOME:
            if not self.origin_relay_id:
                raise ValueError("relay_to_home requires origin_relay_id")
            if not has_delivery_address:
                raise ValueError("relay_to_home requires delivery_address")
        elif self.delivery_mode == DeliveryMode.HOME_TO_RELAY:
            if not has_origin_gps:
                raise ValueError("home_to_relay requires origin_location.geopin")
            if not self.destination_relay_id:
                raise ValueError("home_to_relay requires destination_relay_id")
        elif self.delivery_mode == DeliveryMode.HOME_TO_HOME:
            if not has_origin_gps:
                raise ValueError("home_to_home requires origin_location.geopin")
            if not has_delivery_address:
                raise ValueError("home_to_home requires delivery_address")

        return self


class QuoteResponse(BaseModel):
    price: Optional[float] = None
    currency: str = "XOF"
    breakdown: Dict[str, Any] = Field(default_factory=dict)
    original_price: Optional[float] = None
    discount_xof: float = 0.0
    promo_applied: Optional[Dict[str, Any]] = None


class FailDeliveryRequest(BaseModel):
    failure_reason: str = Field(..., min_length=2, max_length=80)
    notes: Optional[str] = Field(default=None, max_length=1000)

    @field_validator("failure_reason")
    @classmethod
    def normalize_failure_reason(cls, value: str) -> str:
        return clean_required_text(value)

    @field_validator("notes")
    @classmethod
    def normalize_notes(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class RedirectRelayRequest(BaseModel):
    redirect_relay_id: str = Field(..., min_length=3, max_length=80)
    notes: Optional[str] = Field(default=None, max_length=1000)

    @field_validator("redirect_relay_id")
    @classmethod
    def normalize_redirect_relay_id(cls, value: str) -> str:
        return clean_required_text(value)

    @field_validator("notes")
    @classmethod
    def normalize_notes(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class ParcelRatingRequest(BaseModel):
    rating: int = Field(..., ge=1, le=5)
    comment: Optional[str] = Field(default=None, max_length=1000)
    tip: float = Field(default=0.0, ge=0, le=1_000_000)

    @field_validator("comment")
    @classmethod
    def normalize_comment(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class LocationConfirmPayload(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    accuracy: Optional[float] = Field(None, ge=0, le=10000)
    voice_note: Optional[str] = None
    label: Optional[str] = Field(default=None, max_length=240)
    district: Optional[str] = Field(default=None, max_length=120)
    city: Optional[str] = Field(default=None, max_length=120)
    notes: Optional[str] = Field(default=None, max_length=500)

    @field_validator("label", "district", "city", "notes")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class AddressChangePreviewRequest(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    accuracy: Optional[float] = Field(None, ge=0, le=10000)
    voice_note: Optional[str] = None
    label: Optional[str] = Field(default=None, max_length=240)
    district: Optional[str] = Field(default=None, max_length=120)
    city: Optional[str] = Field(default=None, max_length=120)
    notes: Optional[str] = Field(default=None, max_length=500)

    @field_validator("label", "district", "city", "notes")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class AddressChangeApplyRequest(AddressChangePreviewRequest):
    accept_surcharge: bool = False
