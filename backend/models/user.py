from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel, field_validator
from models.common import UserRole

class UserType(str, Enum):
    INDIVIDUAL = "individual"
    MERCHANT = "merchant"
    ENTERPRISE = "enterprise"


class FavoriteAddress(BaseModel):
    name: str
    address: str
    lat: float
    lng: float


class NotificationPrefs(BaseModel):
    push: bool = True
    email: bool = True
    whatsapp: bool = True
    parcel_updates: bool = True
    promotions: bool = True


class User(BaseModel):
    user_id:           str
    phone:             str        # E.164 : "+221XXXXXXXXX"
    name:              str
    email:             Optional[str] = None
    profile_picture_url: Optional[str] = None
    role:              UserRole   = UserRole.CLIENT
    user_type:         Optional[UserType] = None
    is_active:         bool       = True
    is_banned:         bool       = False
    is_phone_verified: bool       = False
    is_available:      bool       = False   # driver disponible
    # Pour relay agents
    relay_point_id:    Optional[str] = None
    # Connexion future projet_stock
    store_id:          Optional[str] = None
    external_ref:      Optional[str] = None
    # Préférences
    language:          str = "fr"
    currency:          str = "XOF"
    country_code:      str = "SN"
    notification_prefs: NotificationPrefs = NotificationPrefs()
    favorite_addresses: list[FavoriteAddress] = []
    bio:               Optional[str] = None
    # KYC
    kyc_status:        str          = "none"  # "none" | "pending" | "verified" | "rejected"
    kyc_id_card_url:   Optional[str] = None
    kyc_license_url:   Optional[str] = None
    # Programme fidélité
    loyalty_points:    int          = 0
    loyalty_tier:      str          = "bronze"   # "bronze" | "silver" | "gold"
    referral_code:     str          = ""
    referred_by:       Optional[str] = None      # user_id du parrain
    referral_credited: bool          = False
    referral_enabled_override: Optional[bool] = None
    # Driver specific (Phase 7 & 8)
    last_driver_location:    Optional[dict] = None  # {"lat": float, "lng": float}
    last_driver_location_at: Optional[datetime] = None
    xp:                      int            = 0
    level:                   int            = 1
    total_earned:            float          = 0.0
    badges:                  list[str]      = []
    deliveries_completed:    int            = 0
    on_time_deliveries:      int            = 0
    total_rating_sum:        float          = 0.0
    total_ratings_count:     int            = 0
    average_rating:          float          = 0.0
    cod_balance:             float          = 0.0  # Cash on Delivery balance (to be settled)
    # Legal acceptance
    accepted_legal:          bool           = False
    accepted_legal_at:       Optional[datetime] = None
    # Security
    pin_hash:                Optional[str]  = None
    # Timestamps
    created_at:        datetime
    updated_at:        datetime


class UserCreate(BaseModel):
    phone: str
    name:  str
    email: Optional[str] = None
    fcm_token: Optional[str] = None
    role:  UserRole = UserRole.CLIENT

    @field_validator("phone")
    @classmethod
    def phone_must_be_e164(cls, v: str) -> str:
        if not v.startswith("+"):
            raise ValueError("Le téléphone doit être au format E.164 (ex: +221XXXXXXXXX)")
        return v


class OTPRequest(BaseModel):
    phone: str   # E.164

    @field_validator("phone")
    @classmethod
    def phone_must_be_e164(cls, v: str) -> str:
        if not v.startswith("+"):
            raise ValueError("Le téléphone doit être au format E.164 (ex: +221XXXXXXXXX)")
        return v


class OTPVerify(BaseModel):
    phone: str
    otp:   str
    accepted_legal: bool = False


class TokenResponse(BaseModel):
    access_token:  str
    refresh_token: str
    token_type:    str = "bearer"
    user:          User


class RefreshRequest(BaseModel):
    refresh_token: str


class ProfileUpdate(BaseModel):
    email:              Optional[str] = None
    language:           Optional[str] = None
    user_type:          Optional[UserType] = None
    bio:                Optional[str] = None
    notification_prefs: Optional[NotificationPrefs] = None
