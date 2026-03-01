from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional


class Settings(BaseSettings):
    # App
    APP_ENV: str = "development"
    DEBUG: bool = True
    BASE_URL: str = "https://pickupoint-production.up.railway.app"

    # MongoDB
    MONGO_URL: str = "mongodb://localhost:27017"
    DB_NAME: str = "Pickupoint"

    # JWT
    JWT_SECRET: str = "changeme_minimum_32_chars_here_please"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 120
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # OTP
    OTP_EXPIRE_MINUTES: int = 10
    OTP_LENGTH: int = 6

    # Twilio
    TWILIO_ACCOUNT_SID: Optional[str] = None
    TWILIO_AUTH_TOKEN: Optional[str] = None
    TWILIO_WHATSAPP_NUMBER: str = "whatsapp:+14155238886"
    TWILIO_SMS_NUMBER: Optional[str] = None

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
    INSURANCE_RATE:      float = 0.02    # 2 % de la valeur déclarée
    EXPRESS_MULTIPLIER:  float = 1.40    # +40 %
    NIGHT_MULTIPLIER:    float = 1.20    # +20 % (20h-7h et dimanche)
    DEFAULT_DISTANCE_KM: float = 8.0    # fallback si GPS inconnu

    # Commission splits — 15 % plateforme, 15 % relais, 70 % livreur = 100 %
    PLATFORM_RATE:    float = 0.15
    RELAY_RATE:       float = 0.15
    DRIVER_RATE:      float = 0.70

    model_config = SettingsConfigDict(
        env_file=[".env", "../.env"],  # cherche dans backend/ puis dans la racine
        case_sensitive=True,
        extra="ignore",
    )


settings = Settings()
