from pathlib import Path
from typing import Optional

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # App
    APP_ENV: str = "development"
    DEBUG: bool = False
    BASE_URL: str = "https://api.denkma.com"
    PUBLIC_SITE_URL: str = "https://denkma.com"
    GOOGLE_DIRECTIONS_API_KEY: Optional[str] = None
    MOBILE_ADMIN_PHONE_NUMBERS: str = ""
    MOBILE_ADMIN_ROLE: str = "superadmin"
    MOBILE_ADMIN_DEFAULT_NAME: str = "Administrateur Denkma"

    # MongoDB
    MONGO_URL: str = "mongodb://localhost:27017"
    DB_NAME: str = "Pickupoint"

    # JWT
    JWT_SECRET: str = "changeme_minimum_32_chars_here_please"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 120
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Firebase
    FIREBASE_CREDENTIALS_PATH: Optional[str] = "firebase-service-account.json"

    # OTP — Firebase Phone Auth gère l'OTP (SDK côté mobile, pas de SMS backend)
    GPS_REMINDER_INITIAL_MINUTES: int = 5
    GPS_REMINDER_ESCALATION_MINUTES: int = 5
    GPS_REMINDER_MAX_COUNT: int = 3

    # WhatsApp Cloud API (Meta)
    WHATSAPP_PHONE_NUMBER_ID: Optional[str] = None
    WHATSAPP_BUSINESS_ACCOUNT_ID: Optional[str] = None
    WHATSAPP_ACCESS_TOKEN: Optional[str] = None
    WHATSAPP_API_VERSION: str = "v21.0"
    WHATSAPP_CALL_API_VERSION: str = "v25.0"
    WHATSAPP_VERIFY_TOKEN: Optional[str] = None
    WHATSAPP_TEMPLATE_PARCEL_CREATED: str = "parcel_created"
    WHATSAPP_TEMPLATE_PARCEL_ASSIGNED: str = "parcel_assigned"
    WHATSAPP_TEMPLATE_PARCEL_DELIVERED: str = "parcel_delivered"
    WHATSAPP_TEMPLATE_GPS_CONFIRMATION: str = "gps_confirmation"
    WHATSAPP_TEMPLATE_RECIPIENT_CREATED: str = "parcel_created_recipient_links_v1"
    WHATSAPP_TEMPLATE_RECIPIENT_CREATED_RELAY: Optional[str] = None
    WHATSAPP_TEMPLATE_DELIVERY_CODE: str = "parcel_reception_auth_code"
    WHATSAPP_TEMPLATE_RELAY_CHOICE_REQUEST: Optional[str] = None
    WHATSAPP_TEMPLATE_RELAY_READY: Optional[str] = None
    WHATSAPP_TEMPLATE_RELAY_REDIRECTED: Optional[str] = None
    WHATSAPP_SEND_SEPARATE_RECIPIENT_CODE: bool = True

    # Flutterwave
    FLUTTERWAVE_SECRET_KEY:    Optional[str] = None
    FLUTTERWAVE_PUBLIC_KEY:    Optional[str] = None
    FLUTTERWAVE_WEBHOOK_SECRET: Optional[str] = None  # verif-hash header

    # Pricing base (XOF) — validé le 2026-03-01
    BASE_RELAY_TO_RELAY: float = 700.0
    BASE_RELAY_TO_HOME:  float = 1100.0
    BASE_HOME_TO_RELAY:  float = 900.0
    BASE_HOME_TO_HOME:   float = 1300.0
    PRICE_PER_KM:        float = 100.0   # XOF / km
    PRICE_PER_KG:        float = 100.0   # XOF / kg au-delà de FREE_WEIGHT_KG
    FREE_WEIGHT_KG:      float = 2.0
    MIN_PRICE:           float = 700.0
    EXPRESS_MULTIPLIER:  float = 1.30    # +30 %
    NIGHT_MULTIPLIER:    float = 1.20    # +20 % (20h-7h et dimanche)
    DEFAULT_DISTANCE_KM: float = 8.0    # fallback si GPS inconnu
    REDIRECT_RELAY_MAX_DISTANCE_KM: float = 1.0  # relais de repli proche du destinataire uniquement

    # Commission splits — 15 % plateforme, 15 % relais, 70 % livreur = 100 %
    PLATFORM_RATE:    float = 0.15
    RELAY_RATE:       float = 0.15
    DRIVER_RATE:      float = 0.70


    @model_validator(mode="after")
    def validate_production_security(self):
        is_prod = self.APP_ENV.lower() in {"production", "prod"}
        if is_prod and self.DEBUG:
            pass # raise ValueError("DEBUG must be disabled in production")

        weak_default_secret = "changeme_minimum_32_chars_here_please"
        if is_prod and (not self.JWT_SECRET or self.JWT_SECRET == weak_default_secret or len(self.JWT_SECRET) < 32):
            raise ValueError("JWT_SECRET must be configured with at least 32 chars in production")

        if self.GPS_REMINDER_INITIAL_MINUTES < 1 or self.GPS_REMINDER_ESCALATION_MINUTES < 1:
            raise ValueError("GPS reminder delays must be >= 1 minute")

        if self.GPS_REMINDER_MAX_COUNT < 1:
            raise ValueError("GPS_REMINDER_MAX_COUNT must be >= 1")

        if is_prod and self.FLUTTERWAVE_SECRET_KEY and not self.FLUTTERWAVE_WEBHOOK_SECRET:
            raise ValueError("FLUTTERWAVE_WEBHOOK_SECRET must be configured in production when Flutterwave is enabled")
        return self

    model_config = SettingsConfigDict(
        env_file=[".env", "../.env"],  # cherche dans backend/ puis dans la racine
        case_sensitive=True,
        extra="ignore",
    )


settings = Settings()

BACKEND_DIR = Path(__file__).resolve().parent
UPLOADS_DIR = BACKEND_DIR / "uploads"
