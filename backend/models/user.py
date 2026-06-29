from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, field_validator

from models.common import UserRole, clean_optional_text


class UserType(str, Enum):
    INDIVIDUAL = "individual"
    MERCHANT = "merchant"
    ENTERPRISE = "enterprise"


class FavoriteAddress(BaseModel):
    name: str = Field(..., min_length=1, max_length=80)
    address: str = Field(..., min_length=1, max_length=240)
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)

    @field_validator("name", "address")
    @classmethod
    def normalize_text_fields(cls, value: str) -> str:
        cleaned = clean_optional_text(value)
        if not cleaned:
            raise ValueError("Champ requis")
        return cleaned


class NotificationPrefs(BaseModel):
    push: bool = True
    email: bool = True
    whatsapp: bool = True
    parcel_updates: bool = True
    promotions: bool = True


class User(BaseModel):
    user_id: str
    phone: str
    name: str
    email: Optional[str] = None
    profile_picture_url: Optional[str] = None
    profile_picture_status: Optional[str] = None
    profile_picture_rejected_reason: Optional[str] = None
    profile_picture_reviewed_by: Optional[str] = None
    profile_picture_reviewed_at: Optional[datetime] = None
    profile_picture_approved_at: Optional[datetime] = None
    role: UserRole = UserRole.CLIENT
    user_type: Optional[UserType] = None
    is_active: bool = True
    is_banned: bool = False
    is_phone_verified: bool = False
    is_available: bool = False
    relay_point_id: Optional[str] = None
    store_id: Optional[str] = None
    external_ref: Optional[str] = None
    language: str = "fr"
    currency: str = "XOF"
    country_code: str = "SN"
    notification_prefs: NotificationPrefs = Field(default_factory=NotificationPrefs)
    favorite_addresses: list[FavoriteAddress] = Field(default_factory=list)
    bio: Optional[str] = None
    kyc_status: str = "none"
    kyc_id_card_url: Optional[str] = None
    kyc_license_url: Optional[str] = None
    loyalty_points: int = 0
    loyalty_tier: str = "bronze"
    referral_code: str = ""
    referred_by: Optional[str] = None
    referral_credited: bool = False
    referral_enabled_override: Optional[bool] = None
    last_driver_location: Optional[dict] = None
    last_driver_location_at: Optional[datetime] = None
    xp: int = 0
    level: int = 1
    total_earned: float = 0.0
    badges: list[str] = Field(default_factory=list)
    deliveries_completed: int = 0
    on_time_deliveries: int = 0
    total_rating_sum: float = 0.0
    total_ratings_count: int = 0
    average_rating: float = 0.0
    cod_balance: float = 0.0
    accepted_legal: bool = False
    accepted_legal_at: Optional[datetime] = None
    pin_hash: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class UserCreate(BaseModel):
    phone: str = Field(..., min_length=8, max_length=32)
    name: str = Field(..., min_length=2, max_length=120)
    email: Optional[str] = Field(default=None, max_length=254)
    fcm_token: Optional[str] = Field(default=None, max_length=512)
    role: UserRole = UserRole.CLIENT

    @field_validator("phone")
    @classmethod
    def phone_must_be_e164(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned.startswith("+") or not cleaned[1:].isdigit():
            raise ValueError("Le téléphone doit être au format E.164 (ex: +221XXXXXXXXX)")
        return cleaned

    @field_validator("name", "email", "fcm_token")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class OTPRequest(BaseModel):
    phone: str = Field(..., min_length=8, max_length=32)

    @field_validator("phone")
    @classmethod
    def phone_must_be_e164(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned.startswith("+") or not cleaned[1:].isdigit():
            raise ValueError("Le téléphone doit être au format E.164 (ex: +221XXXXXXXXX)")
        return cleaned


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: User


class RefreshRequest(BaseModel):
    refresh_token: str = Field(..., min_length=20, max_length=4096)


class ProfileUpdate(BaseModel):
    email: Optional[str] = Field(default=None, max_length=254)
    language: Optional[str] = Field(default=None, min_length=2, max_length=8)
    user_type: Optional[UserType] = None
    bio: Optional[str] = Field(default=None, max_length=500)
    notification_prefs: Optional[NotificationPrefs] = None

    @field_validator("email", "language", "bio")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)
