from config import settings
from core.security import fingerprint_token


def admin_mfa_key_id(email: str) -> str | None:
    normalized = email.strip().lower()
    secret = settings.ADMIN_MFA_TOTP_SECRETS.get(normalized)
    return fingerprint_token(f"admin-mfa:{normalized}:{secret}") if secret else None


def valid_admin_mfa_session(user: dict, payload: dict) -> bool:
    key_id = admin_mfa_key_id(user.get("email") or "")
    if not key_id and not settings.ADMIN_REQUIRE_MFA:
        return True
    return bool(key_id and payload.get("admin_mfa") is True and payload.get("admin_mfa_key_id") == key_id)
