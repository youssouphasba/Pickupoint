from pathlib import Path
from typing import Optional

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # App
    APP_ENV: str = "development"
    DEBUG: bool = False
    BASE_URL: str = "https://api.denkma.com"
    PUBLIC_SITE_URL: str = "https://denkma.com"
    APP_DOWNLOAD_URL: Optional[str] = None
    ANDROID_STORE_URL: Optional[str] = None
    IOS_STORE_URL: Optional[str] = None
    IOS_TEAM_ID: Optional[str] = None
    GOOGLE_DIRECTIONS_API_KEY: Optional[str] = None
    MOBILE_ADMIN_PHONE_NUMBERS: str = ""
    MOBILE_ADMIN_ROLE: str = "superadmin"
    MOBILE_ADMIN_DEFAULT_NAME: str = "Administrateur Denkma"
    SUPPORT_WHATSAPP_PHONE: Optional[str] = None

    # MongoDB
    MONGO_URL: str = "mongodb://localhost:27017"
    DB_NAME: str = "Pickupoint"
    GPS_TRACE_GAP_SECONDS: int = 180
    GPS_TRACE_MAX_SPEED_KMH: float = 160

    # JWT
    JWT_SECRET: str = "changeme_minimum_32_chars_here_please"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 120
    REFRESH_TOKEN_EXPIRE_DAYS: int = 365
    ADMIN_MFA_TOTP_SECRETS: dict[str, str] = Field(default_factory=dict, repr=False)
    ADMIN_REQUIRE_MFA: bool = False
    ADMIN_MFA_MAX_ATTEMPTS: int = 5
    ADMIN_MFA_LOCK_SECONDS: int = 600

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
    WHATSAPP_APP_SECRET: Optional[str] = None
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
    WHATSAPP_TEMPLATE_SUPPORT_REOPEN: Optional[str] = None
    WHATSAPP_TEMPLATE_SUPPORT_REOPEN_VARIABLES: str = "name"
    WHATSAPP_TEMPLATE_CALL_PERMISSION: Optional[str] = None
    WHATSAPP_TEMPLATE_CALL_PERMISSION_LANGUAGE: str = "fr"
    WHATSAPP_TEMPLATE_CALL_PERMISSION_VARIABLES: str = "name,driver_name,tracking_code"
    WHATSAPP_TEMPLATE_APPLICATION_APPROVED: str = "application_approved_v1"
    WHATSAPP_TEMPLATE_APPLICATION_REJECTED: str = "application_rejected_v1"
    WHATSAPP_SEND_SEPARATE_RECIPIENT_CODE: bool = True

    # Flutterwave
    FLUTTERWAVE_SECRET_KEY:    Optional[str] = None
    FLUTTERWAVE_PUBLIC_KEY:    Optional[str] = None
    FLUTTERWAVE_WEBHOOK_SECRET: Optional[str] = None  # verif-hash header

    # Stripe wallet top-up
    STRIPE_SECRET_KEY: Optional[str] = None
    STRIPE_WEBHOOK_SECRET: Optional[str] = None
    STRIPE_WALLET_SUCCESS_URL: Optional[str] = None
    STRIPE_WALLET_CANCEL_URL: Optional[str] = None
    WALLET_TOPUP_MIN_XOF: float = Field(500.0, gt=0, allow_inf_nan=False)
    WALLET_TOPUP_MAX_XOF: float = Field(500000.0, gt=0, allow_inf_nan=False)
    STRIPE_HTTP_TIMEOUT_SECONDS: float = Field(6.0, ge=1, le=10)
    STRIPE_RECONCILE_INTERVAL_SECONDS: int = Field(10, ge=1)
    STRIPE_RECONCILE_LIMIT: int = Field(5, ge=1, le=20)
    STRIPE_RETURN_RETRY_ATTEMPTS: int = Field(3, ge=0, le=10)
    WALLET_TOPUP_HISTORY_LIMIT: int = Field(10, ge=1, le=100)

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
    STRICT_GPS_MAX_ACCURACY_METERS: float = 60.0
    DRIVER_GPS_MAX_ACCURACY_METERS: float = 150.0
    GPS_CAPTURE_MAX_AGE_SECONDS: int = 60
    GPS_CLOCK_TOLERANCE_SECONDS: int = 30
    GPS_UPLOAD_INTERVAL_SECONDS: int = 15
    GPS_HEARTBEAT_INTERVAL_SECONDS: int = 30
    GPS_ETA_REFRESH_SECONDS: int = 300
    GPS_ETA_RETRY_SECONDS: int = 30
    GPS_OFFLINE_BUFFER_HOURS: int = 24
    GEOCODING_CACHE_SECONDS: int = 900
    GEOCODING_CACHE_MAX_ENTRIES: int = 1000
    ASSIGNED_MISSION_AUTO_RELEASE_MINUTES: int = 30
    PUBLIC_TRACKING_RETENTION_DAYS: int = 30
    DRIVER_DISPATCH_LOCATION_MAX_AGE_MINUTES: int = 5
    DRIVER_MISSION_REMINDER_INTERVAL_SECONDS: int = Field(default=300, ge=60)
    DRIVER_LOCATION_PURGE_AFTER_HOURS: int = 24
    RELAY_PARCEL_REMINDER_HOURS: str = "48,24"
    RELAY_CAPACITY_WARNING_PERCENT: int = 80
    RELAY_CLOSING_SOON_MINUTES: int = 60
    DRIVER_DOCUMENT_REMINDER_DAYS: str = "30,7"
    OPERATIONAL_DATA_RETENTION_DAYS: int = 1095
    GPS_TRACE_RETENTION_DAYS: int = 365
    NOTIFICATION_RETENTION_DAYS: int = 365
    CAMPAIGN_EVENT_RETENTION_DAYS: int = 730
    SUPPORT_RETENTION_DAYS: int = 1095
    AUDIT_LOG_RETENTION_DAYS: int = 730
    TECHNICAL_LOG_RETENTION_DAYS: int = 365
    PROOF_MEDIA_RETENTION_DAYS: int = 365
    CAMPAIGN_MEDIA_ORPHAN_GRACE_DAYS: int = 30
    KYC_RETENTION_DAYS: int = 1825
    KYC_MAX_UPLOAD_BYTES: int = 10 * 1024 * 1024
    KYC_MAX_IMAGE_PIXELS: int = 24_000_000
    KYC_JPEG_QUALITY: int = 90
    KYC_ORPHAN_GRACE_HOURS: int = 24
    KYC_CLAMAV_HOST: Optional[str] = None
    KYC_CLAMAV_PORT: int = 3310
    KYC_CLAMAV_TIMEOUT_SECONDS: int = 20
    KYC_REQUIRE_ANTIVIRUS: bool = False
    KYC_ENCRYPTION_KEYS: str = Field(default="", repr=False)
    KYC_REQUIRE_ENCRYPTION: bool = False

    # Commission splits — 15 % plateforme, 15 % relais, 70 % livreur = 100 %
    PLATFORM_RATE:    float = 0.15
    RELAY_RATE:       float = 0.15
    DRIVER_RATE:      float = 0.70


    @model_validator(mode="after")
    def validate_production_security(self):
        if (self.WALLET_TOPUP_MAX_XOF < self.WALLET_TOPUP_MIN_XOF
                or not self.WALLET_TOPUP_MIN_XOF.is_integer()
                or not self.WALLET_TOPUP_MAX_XOF.is_integer()):
            raise ValueError("Wallet top-up limits must be whole FCFA amounts with maximum >= minimum")
        is_prod = self.APP_ENV.lower() in {"production", "prod"}
        if is_prod and self.DEBUG:
            pass # raise ValueError("DEBUG must be disabled in production")

        weak_default_secret = "changeme_minimum_32_chars_here_please"
        if is_prod and (not self.JWT_SECRET or self.JWT_SECRET == weak_default_secret or len(self.JWT_SECRET) < 32):
            raise ValueError("JWT_SECRET must be configured with at least 32 chars in production")
        if self.ADMIN_MFA_MAX_ATTEMPTS < 1 or self.ADMIN_MFA_LOCK_SECONDS < 1:
            raise ValueError("Invalid admin MFA attempt settings")
        if self.ADMIN_REQUIRE_MFA and not self.ADMIN_MFA_TOTP_SECRETS:
            raise ValueError("Configure admin MFA secrets before requiring MFA")
        if self.ADMIN_MFA_TOTP_SECRETS:
            import base64
            normalized_secrets = {}
            try:
                for email, secret in self.ADMIN_MFA_TOTP_SECRETS.items():
                    value = secret.replace(" ", "").upper()
                    if len(base64.b32decode(value + "=" * (-len(value) % 8))) < 20:
                        raise ValueError("Insufficient MFA secret length")
                    normalized_secrets[email.strip().lower()] = value
            except (ValueError, UnicodeError):
                raise ValueError("Invalid admin MFA secret configuration") from None
            self.ADMIN_MFA_TOTP_SECRETS = normalized_secrets

        if self.GPS_REMINDER_INITIAL_MINUTES < 1 or self.GPS_REMINDER_ESCALATION_MINUTES < 1:
            raise ValueError("GPS reminder delays must be >= 1 minute")

        if self.GPS_REMINDER_MAX_COUNT < 1:
            raise ValueError("GPS_REMINDER_MAX_COUNT must be >= 1")
        if self.STRICT_GPS_MAX_ACCURACY_METERS <= 0:
            raise ValueError("STRICT_GPS_MAX_ACCURACY_METERS must be > 0")
        if self.DRIVER_GPS_MAX_ACCURACY_METERS < self.STRICT_GPS_MAX_ACCURACY_METERS:
            raise ValueError("DRIVER_GPS_MAX_ACCURACY_METERS must be >= STRICT_GPS_MAX_ACCURACY_METERS")
        if any(getattr(self, key) <= 0 for key in (
            "GPS_CAPTURE_MAX_AGE_SECONDS", "GPS_CLOCK_TOLERANCE_SECONDS",
            "GPS_UPLOAD_INTERVAL_SECONDS", "GPS_HEARTBEAT_INTERVAL_SECONDS",
            "GPS_ETA_REFRESH_SECONDS", "GPS_ETA_RETRY_SECONDS", "GPS_OFFLINE_BUFFER_HOURS",
            "GEOCODING_CACHE_SECONDS", "GEOCODING_CACHE_MAX_ENTRIES",
        )):
            raise ValueError("GPS timing settings must be > 0")
        if self.ASSIGNED_MISSION_AUTO_RELEASE_MINUTES < 5:
            raise ValueError("ASSIGNED_MISSION_AUTO_RELEASE_MINUTES must be >= 5")
        if self.PUBLIC_TRACKING_RETENTION_DAYS < 1:
            raise ValueError("PUBLIC_TRACKING_RETENTION_DAYS must be >= 1")
        if self.DRIVER_DISPATCH_LOCATION_MAX_AGE_MINUTES < 1:
            raise ValueError("DRIVER_DISPATCH_LOCATION_MAX_AGE_MINUTES must be >= 1")
        if self.DRIVER_LOCATION_PURGE_AFTER_HOURS < 1:
            raise ValueError("DRIVER_LOCATION_PURGE_AFTER_HOURS must be >= 1")
        if not 1 <= self.RELAY_CAPACITY_WARNING_PERCENT <= 100:
            raise ValueError("RELAY_CAPACITY_WARNING_PERCENT must be between 1 and 100")
        if self.RELAY_CLOSING_SOON_MINUTES < 1:
            raise ValueError("RELAY_CLOSING_SOON_MINUTES must be >= 1")
        retention_settings = (
            "OPERATIONAL_DATA_RETENTION_DAYS",
            "GPS_TRACE_RETENTION_DAYS",
            "NOTIFICATION_RETENTION_DAYS",
            "CAMPAIGN_EVENT_RETENTION_DAYS",
            "SUPPORT_RETENTION_DAYS",
            "AUDIT_LOG_RETENTION_DAYS",
            "TECHNICAL_LOG_RETENTION_DAYS",
            "PROOF_MEDIA_RETENTION_DAYS",
            "CAMPAIGN_MEDIA_ORPHAN_GRACE_DAYS",
            "KYC_RETENTION_DAYS",
        )
        if any(getattr(self, key) < 1 for key in retention_settings):
            raise ValueError("Retention settings must be >= 1")
        if any(getattr(self, key) < 1 for key in (
            "KYC_MAX_UPLOAD_BYTES", "KYC_MAX_IMAGE_PIXELS", "KYC_ORPHAN_GRACE_HOURS",
            "KYC_CLAMAV_TIMEOUT_SECONDS",
        )) or not 1 <= self.KYC_CLAMAV_PORT <= 65535 or not 1 <= self.KYC_JPEG_QUALITY <= 100:
            raise ValueError("Invalid KYC security settings")
        if self.KYC_REQUIRE_ANTIVIRUS and not self.KYC_CLAMAV_HOST:
            raise ValueError("KYC_CLAMAV_HOST is required when KYC_REQUIRE_ANTIVIRUS is enabled")
        if self.KYC_REQUIRE_ENCRYPTION and not self.KYC_ENCRYPTION_KEYS.strip():
            raise ValueError("KYC_ENCRYPTION_KEYS is required when KYC_REQUIRE_ENCRYPTION is enabled")
        if self.KYC_ENCRYPTION_KEYS.strip():
            from cryptography.fernet import Fernet
            try:
                for key in self.KYC_ENCRYPTION_KEYS.split(","):
                    Fernet(key.strip().encode("ascii"))
            except (ValueError, UnicodeError):
                raise ValueError("Invalid KYC encryption key configuration") from None

        if is_prod and self.WHATSAPP_ACCESS_TOKEN and not self.WHATSAPP_APP_SECRET:
            raise ValueError("WHATSAPP_APP_SECRET must be configured in production when WhatsApp webhooks are enabled")

        if is_prod and self.FLUTTERWAVE_SECRET_KEY and not self.FLUTTERWAVE_WEBHOOK_SECRET:
            raise ValueError("FLUTTERWAVE_WEBHOOK_SECRET must be configured in production when Flutterwave is enabled")
        if is_prod and self.STRIPE_SECRET_KEY and not self.STRIPE_WEBHOOK_SECRET:
            raise ValueError("STRIPE_WEBHOOK_SECRET must be configured in production when Stripe is enabled")
        return self

    model_config = SettingsConfigDict(
        env_file=[".env", "../.env"],  # cherche dans backend/ puis dans la racine
        case_sensitive=True,
        extra="ignore",
        hide_input_in_errors=True,
    )


settings = Settings()

BACKEND_DIR = Path(__file__).resolve().parent
UPLOADS_DIR = BACKEND_DIR / "uploads"
