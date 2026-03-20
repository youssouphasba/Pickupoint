"""
Helpers fidelite clients : points, paliers, parrainage.
"""
import random
import string
from urllib.parse import quote_plus

from config import settings
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
DEFAULT_REFERRAL_ALLOWED_ROLES = ["client", "driver", "relay_agent"]
DEFAULT_REFERRAL_SPONSOR_BONUS_XOF = DEFAULT_REFERRAL_BONUS_XOF
DEFAULT_REFERRAL_REFERRED_BONUS_XOF = DEFAULT_REFERRAL_BONUS_XOF
DEFAULT_REFERRAL_SPONSOR_ALLOWED_ROLES = DEFAULT_REFERRAL_ALLOWED_ROLES.copy()
DEFAULT_REFERRAL_REFERRED_ALLOWED_ROLES = DEFAULT_REFERRAL_ALLOWED_ROLES.copy()
DEFAULT_REFERRAL_APPLY_METRIC = "sent_parcels"
DEFAULT_REFERRAL_APPLY_MAX_COUNT = 0
DEFAULT_REFERRAL_REWARD_METRIC = "delivered_sender_parcels"
DEFAULT_REFERRAL_REWARD_COUNT = 1
REFERRAL_METRIC_LABELS = {
    "sent_parcels": ("colis envoye", "colis envoyes"),
    "delivered_sender_parcels": ("colis livre", "colis livres"),
    "completed_driver_deliveries": ("livraison effectuee", "livraisons effectuees"),
}


async def get_global_app_settings() -> dict:
    return await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}


def _normalize_int_setting(
    value,
    default: int,
    *,
    minimum: int = 0,
) -> int:
    try:
        return max(int(value), minimum)
    except (TypeError, ValueError):
        return default


def _normalize_roles(
    raw_roles,
    default_roles: list[str],
) -> list[str]:
    if not isinstance(raw_roles, list):
        return default_roles.copy()

    normalized = []
    for role in raw_roles:
        value = str(role or "").strip()
        if value and value not in normalized:
            normalized.append(value)

    return normalized or default_roles.copy()


def get_referral_bonus_xof(settings_doc: dict | None) -> int:
    raw = (settings_doc or {}).get("referral_bonus_xof", DEFAULT_REFERRAL_BONUS_XOF)
    try:
        return max(int(raw), 0)
    except (TypeError, ValueError):
        return DEFAULT_REFERRAL_BONUS_XOF


def get_referral_sponsor_bonus_xof(settings_doc: dict | None) -> int:
    raw = (settings_doc or {}).get(
        "referral_sponsor_bonus_xof",
        (settings_doc or {}).get("referral_bonus_xof", DEFAULT_REFERRAL_SPONSOR_BONUS_XOF),
    )
    return _normalize_int_setting(raw, DEFAULT_REFERRAL_SPONSOR_BONUS_XOF)


def get_referral_referred_bonus_xof(settings_doc: dict | None) -> int:
    raw = (settings_doc or {}).get(
        "referral_referred_bonus_xof",
        (settings_doc or {}).get("referral_bonus_xof", DEFAULT_REFERRAL_REFERRED_BONUS_XOF),
    )
    return _normalize_int_setting(raw, DEFAULT_REFERRAL_REFERRED_BONUS_XOF)


def get_referral_share_base_url(settings_doc: dict | None) -> str | None:
    raw = str((settings_doc or {}).get("referral_share_base_url") or "").strip()
    return raw or None


def get_default_referral_share_base_url() -> str:
    base_url = str(settings.BASE_URL or "").strip().rstrip("/")
    return f"{base_url}/api/users/referral/{{code}}"


def get_effective_referral_share_base_url(settings_doc: dict | None) -> str:
    return get_referral_share_base_url(settings_doc) or get_default_referral_share_base_url()


def get_referral_allowed_roles(settings_doc: dict | None) -> list[str]:
    return get_referral_sponsor_allowed_roles(settings_doc)


def get_referral_sponsor_allowed_roles(settings_doc: dict | None) -> list[str]:
    raw_roles = (settings_doc or {}).get(
        "referral_sponsor_allowed_roles",
        (settings_doc or {}).get("referral_allowed_roles"),
    )
    return _normalize_roles(raw_roles, DEFAULT_REFERRAL_SPONSOR_ALLOWED_ROLES)


def get_referral_referred_allowed_roles(settings_doc: dict | None) -> list[str]:
    raw_roles = (settings_doc or {}).get(
        "referral_referred_allowed_roles",
        (settings_doc or {}).get("referral_allowed_roles"),
    )
    return _normalize_roles(raw_roles, DEFAULT_REFERRAL_REFERRED_ALLOWED_ROLES)


def get_referral_metric_options() -> list[dict[str, str]]:
    return [
        {"value": value, "label": format_referral_metric_threshold(value, 2)}
        for value in REFERRAL_METRIC_LABELS
    ]


def get_referral_metric_label(metric: str, count: int = 2) -> str:
    singular, plural = REFERRAL_METRIC_LABELS.get(
        metric,
        REFERRAL_METRIC_LABELS[DEFAULT_REFERRAL_APPLY_METRIC],
    )
    return singular if count == 1 else plural


def format_referral_metric_threshold(metric: str, count: int) -> str:
    normalized_count = max(int(count), 0)
    return f"{normalized_count} {get_referral_metric_label(metric, normalized_count)}"


def _normalize_referral_metric(metric: str | None, default_metric: str) -> str:
    value = str(metric or "").strip()
    if value in REFERRAL_METRIC_LABELS:
        return value
    return default_metric


def get_referral_apply_metric(settings_doc: dict | None) -> str:
    return _normalize_referral_metric(
        (settings_doc or {}).get("referral_apply_metric"),
        DEFAULT_REFERRAL_APPLY_METRIC,
    )


def get_referral_apply_max_count(settings_doc: dict | None) -> int:
    raw = (settings_doc or {}).get("referral_apply_max_count", DEFAULT_REFERRAL_APPLY_MAX_COUNT)
    return _normalize_int_setting(raw, DEFAULT_REFERRAL_APPLY_MAX_COUNT)


def get_referral_reward_metric(settings_doc: dict | None) -> str:
    return _normalize_referral_metric(
        (settings_doc or {}).get("referral_reward_metric"),
        DEFAULT_REFERRAL_REWARD_METRIC,
    )


def get_referral_reward_count(settings_doc: dict | None) -> int:
    raw = (settings_doc or {}).get("referral_reward_count", DEFAULT_REFERRAL_REWARD_COUNT)
    return _normalize_int_setting(raw, DEFAULT_REFERRAL_REWARD_COUNT, minimum=1)


def describe_referral_apply_rule(settings_doc: dict | None) -> str:
    metric = get_referral_apply_metric(settings_doc)
    max_count = get_referral_apply_max_count(settings_doc)
    return (
        "Code applicable tant que le compte ne depasse pas "
        f"{format_referral_metric_threshold(metric, max_count)}."
    )


def describe_referral_reward_rule(settings_doc: dict | None) -> str:
    metric = get_referral_reward_metric(settings_doc)
    count = get_referral_reward_count(settings_doc)
    return f"Prime debloquee apres {format_referral_metric_threshold(metric, count)}."


def is_referral_globally_enabled(settings_doc: dict | None) -> bool:
    return bool((settings_doc or {}).get("referral_enabled", DEFAULT_REFERRAL_ENABLED))


def is_referral_role_allowed(role: str | None, settings_doc: dict | None) -> bool:
    normalized_role = str(role or "").strip() or "client"
    return normalized_role in get_referral_sponsor_allowed_roles(settings_doc)


def is_referral_sponsor_role_allowed(role: str | None, settings_doc: dict | None) -> bool:
    normalized_role = str(role or "").strip() or "client"
    return normalized_role in get_referral_sponsor_allowed_roles(settings_doc)


def is_referral_referred_role_allowed(role: str | None, settings_doc: dict | None) -> bool:
    normalized_role = str(role or "").strip() or "client"
    return normalized_role in get_referral_referred_allowed_roles(settings_doc)


def is_referral_enabled_for_user(user_doc: dict | None, settings_doc: dict | None) -> bool:
    return is_referral_sponsor_enabled_for_user(user_doc, settings_doc)


def is_referral_sponsor_enabled_for_user(user_doc: dict | None, settings_doc: dict | None) -> bool:
    if not user_doc:
        return False
    if user_doc.get("is_banned"):
        return False
    if user_doc.get("is_active") is False:
        return False

    override = (user_doc or {}).get("referral_enabled_override")
    if override is True:
        return True
    if override is False:
        return False
    return is_referral_globally_enabled(settings_doc) and is_referral_sponsor_role_allowed(
        (user_doc or {}).get("role"),
        settings_doc,
    )


def is_referral_referred_enabled_for_user(user_doc: dict | None, settings_doc: dict | None) -> bool:
    if not user_doc:
        return False
    if user_doc.get("is_banned"):
        return False
    if user_doc.get("is_active") is False:
        return False

    override = (user_doc or {}).get("referral_enabled_override")
    if override is True:
        return True
    if override is False:
        return False
    return is_referral_globally_enabled(settings_doc) and is_referral_referred_role_allowed(
        (user_doc or {}).get("role"),
        settings_doc,
    )


def build_referral_url(code: str, base_url: str | None) -> str | None:
    normalized_code = (code or "").strip().upper()
    normalized_base = (base_url or get_default_referral_share_base_url()).strip()
    if not normalized_code or not normalized_base:
        return None

    if "{code}" in normalized_base:
        return normalized_base.replace("{code}", quote_plus(normalized_code))

    separator = "&" if "?" in normalized_base else "?"
    return f"{normalized_base}{separator}ref={quote_plus(normalized_code)}"


def build_referral_share_message(
    *,
    code: str,
    referral_url: str | None,
    referred_bonus_xof: int,
    reward_rule: str | None = None,
) -> str:
    message = f"Utilise mon code parrainage Denkma {code} pour rejoindre l'app."
    if referred_bonus_xof > 0:
        message += f" Bonus filleul : {referred_bonus_xof} XOF."
    if reward_rule:
        message += f" {reward_rule}"
    if referral_url:
        message += f" Lien d'inscription : {referral_url}"
    return message


async def get_referral_metric_count(user_id: str, metric: str) -> int:
    normalized_metric = _normalize_referral_metric(metric, DEFAULT_REFERRAL_APPLY_METRIC)
    if normalized_metric == "sent_parcels":
        return await db.parcels.count_documents({"sender_user_id": user_id})
    if normalized_metric == "delivered_sender_parcels":
        return await db.parcels.count_documents(
            {"sender_user_id": user_id, "status": "delivered"}
        )
    if normalized_metric == "completed_driver_deliveries":
        return await db.delivery_missions.count_documents(
            {"driver_id": user_id, "status": "completed"}
        )
    return 0
