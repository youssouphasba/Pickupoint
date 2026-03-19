"""
Helpers fidélité clients : points, paliers, parrainage.
"""
import random
import string
from urllib.parse import quote_plus

from database import db


def generate_referral_code(name: str) -> str:
    """Génère un code parrainage unique. Ex: DAOUDA-4F2K"""
    suffix = "".join(random.choices(string.ascii_uppercase + string.digits, k=4))
    prefix = (name or "USER")[:6].upper().replace(" ", "")
    return f"{prefix}-{suffix}"


def compute_tier(points: int) -> str:
    if points >= 500:
        return "gold"
    if points >= 200:
        return "silver"
    return "bronze"


def tier_discount_coeff(tier: str) -> float:
    """Coefficient de réduction fidélité (1.0 = aucune réduction)."""
    return {"bronze": 1.0, "silver": 0.90, "gold": 0.80}.get(tier, 1.0)


POINTS_PER_DELIVERY = 10
DEFAULT_REFERRAL_BONUS_XOF = 500
DEFAULT_REFERRAL_ENABLED = True


async def get_global_app_settings() -> dict:
    return await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}


def get_referral_bonus_xof(settings_doc: dict | None) -> int:
    raw = (settings_doc or {}).get("referral_bonus_xof", DEFAULT_REFERRAL_BONUS_XOF)
    try:
        return max(int(raw), 0)
    except (TypeError, ValueError):
        return DEFAULT_REFERRAL_BONUS_XOF


def get_referral_share_base_url(settings_doc: dict | None) -> str | None:
    raw = str((settings_doc or {}).get("referral_share_base_url") or "").strip()
    return raw or None


def is_referral_globally_enabled(settings_doc: dict | None) -> bool:
    return bool((settings_doc or {}).get("referral_enabled", DEFAULT_REFERRAL_ENABLED))


def is_referral_enabled_for_user(user_doc: dict | None, settings_doc: dict | None) -> bool:
    override = (user_doc or {}).get("referral_enabled_override")
    if override is None:
        return is_referral_globally_enabled(settings_doc)
    return bool(override)


def build_referral_url(code: str, base_url: str | None) -> str | None:
    normalized_code = (code or "").strip().upper()
    normalized_base = (base_url or "").strip()
    if not normalized_code or not normalized_base:
        return None

    separator = "&" if "?" in normalized_base else "?"
    return f"{normalized_base}{separator}ref={quote_plus(normalized_code)}"


def build_referral_share_message(
    *,
    code: str,
    referral_url: str | None,
    bonus_xof: int,
) -> str:
    message = f"Utilise mon code parrainage Denkma {code} pour rejoindre l'app."
    if bonus_xof > 0:
        message += f" Bonus prevu apres la 1ere livraison livree : {bonus_xof} XOF."
    if referral_url:
        message += f" Lien d'inscription : {referral_url}"
    return message
