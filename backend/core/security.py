import random
import string
import hashlib
import hmac
from datetime import datetime, timezone, timedelta
from typing import Optional

from jose import jwt, JWTError
from passlib.context import CryptContext

from config import settings

# ── Bcrypt ────────────────────────────────────────────────────────────────────
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


# ── JWT ───────────────────────────────────────────────────────────────────────
ALGORITHM = "HS256"


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode.update({"exp": expire, "type": "access"})
    return jwt.encode(to_encode, settings.JWT_SECRET, algorithm=ALGORITHM)


def create_refresh_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire, "type": "refresh"})
    return jwt.encode(to_encode, settings.JWT_SECRET, algorithm=ALGORITHM)


def decode_token(token: str) -> dict:
    """Lève JWTError si invalide ou expiré."""
    return jwt.decode(token, settings.JWT_SECRET, algorithms=[ALGORITHM])


def verify_access_token(token: str) -> Optional[dict]:
    try:
        payload = decode_token(token)
        if payload.get("type") != "access":
            return None
        return payload
    except JWTError:
        return None


def verify_refresh_token(token: str) -> Optional[dict]:
    try:
        payload = decode_token(token)
        if payload.get("type") != "refresh":
            return None
        return payload
    except JWTError:
        return None


# ── OTP ───────────────────────────────────────────────────────────────────────
def generate_otp(length: int = 6) -> str:
    return "".join(random.choices(string.digits, k=length))


# ── Tracking code ─────────────────────────────────────────────────────────────
def generate_tracking_code() -> str:
    """Génère un code lisible humain : PKP-ABC-1234"""
    chars = string.ascii_uppercase + string.digits
    code = "".join(random.choices(chars, k=7))
    return f"PKP-{code[:3]}-{code[3:]}"


# ── QR HMAC signature ─────────────────────────────────────────────────────────
def sign_parcel_id(parcel_id: str) -> str:
    """Signe le parcel_id avec HMAC-SHA256 pour le QR code."""
    sig = hmac.new(
        settings.JWT_SECRET.encode(),
        parcel_id.encode(),
        hashlib.sha256,
    ).hexdigest()[:16]
    return f"{parcel_id}:{sig}"


def verify_parcel_signature(signed: str) -> Optional[str]:
    """Vérifie la signature et retourne le parcel_id si valide."""
    parts = signed.split(":")
    if len(parts) != 2:
        return None
    parcel_id, sig = parts
    expected = hmac.new(
        settings.JWT_SECRET.encode(),
        parcel_id.encode(),
        hashlib.sha256,
    ).hexdigest()[:16]
    if hmac.compare_digest(sig, expected):
        return parcel_id
    return None
