from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional


class Settings(BaseSettings):
    # App
    APP_ENV: str = "development"
    DEBUG: bool = True

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

    # Pricing defaults (XOF)
    BASE_PRICE_RELAY: float = 500.0
    BASE_PRICE_HOME: float = 1000.0
    PRICE_PER_KM: float = 50.0
    MIN_PRICE: float = 500.0

    # Commission splits (%)
    COMMISSION_DRIVER: float = 20.0
    COMMISSION_ORIGIN_RELAY: float = 10.0
    COMMISSION_DEST_RELAY: float = 15.0

    model_config = SettingsConfigDict(
        env_file=[".env", "../.env"],  # cherche dans backend/ puis dans la racine
        case_sensitive=True,
        extra="ignore",
    )


settings = Settings()
