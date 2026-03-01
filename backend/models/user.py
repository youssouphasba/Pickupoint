from datetime import datetime
from typing import Optional
from pydantic import BaseModel, field_validator
from models.common import UserRole


class User(BaseModel):
    user_id:           str
    phone:             str        # E.164 : "+221XXXXXXXXX"
    name:              str
    email:             Optional[str] = None
    role:              UserRole   = UserRole.CLIENT
    is_active:         bool       = True
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
    # Programme fidélité
    loyalty_points:    int          = 0
    loyalty_tier:      str          = "bronze"   # "bronze" | "silver" | "gold"
    referral_code:     str          = ""
    referred_by:       Optional[str] = None      # user_id du parrain
    referral_credited: bool          = False
    # Timestamps
    created_at:        datetime
    updated_at:        datetime


class UserCreate(BaseModel):
    phone: str
    name:  str
    email: Optional[str] = None
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


class TokenResponse(BaseModel):
    access_token:  str
    refresh_token: str
    token_type:    str = "bearer"
    user:          User


class RefreshRequest(BaseModel):
    refresh_token: str


class ProfileUpdate(BaseModel):
    name:     Optional[str] = None
    email:    Optional[str] = None
    language: Optional[str] = None
