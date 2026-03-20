"""
Helpers fidelite clients : points, paliers, parrainage per-role.
"""
import logging
import random
import string
from urllib.parse import quote_plus

from config import settings
from database import db

logger = logging.getLogger(__name__)


# ── Referral per-role defaults ───────────────────────────────────────────────

REFERRAL_ELIGIBLE_ROLES = ["client", "driver"]

REFERRAL_ROLE_DEFAULTS: dict[str, dict] = {
    "client": {
        "enabled": True,
        "sponsor_bonus_xof": 500,
        "referred_bonus_xof": 500,
        "apply_metric": "sent_parcels",
        "apply_max_count": 0,
        "reward_metric": "delivered_sender_parcels",
        "reward_count": 1,
        "max_referrals_per_sponsor": 0,
    },
    "driver": {
        "enabled": True,
        "sponsor_bonus_xof": 1000,
        "referred_bonus_xof": 1000,
        "apply_metric": "completed_driver_deliveries",
        "apply_max_count": 0,
        "reward_metric": "completed_driver_deliveries",
        "reward_count": 5,
        "max_referrals_per_sponsor": 0,
    },
}

REFERRAL_METRIC_LABELS = {
    "sent_parcels": ("colis envoye", "colis envoyes"),
    "delivered_sender_parcels": ("colis livre", "colis livres"),
    "completed_driver_deliveries": ("livraison effectuee", "livraisons effectuees"),
}

# Metrics relevant to each role (for UI filtering)
REFERRAL_ROLE_METRICS = {
    "client": ["sent_parcels", "delivered_sender_parcels"],
    "driver": ["completed_driver_deliveries"],
}


# ── Legacy compat constants (kept for old callers) ──────────────────────────

DEFAULT_REFERRAL_BONUS_XOF = 500
DEFAULT_REFERRAL_ENABLED = True
DEFAULT_REFERRAL_ALLOWED_ROLES = ["client", "driver"]
DEFAULT_REFERRAL_APPLY_METRIC = "sent_parcels"
DEFAULT_REFERRAL_APPLY_MAX_COUNT = 0
DEFAULT_REFERRAL_REWARD_METRIC = "delivered_sender_parcels"
DEFAULT_REFERRAL_REWARD_COUNT = 1
POINTS_PER_DELIVERY = 10


# ── Referral code generation ────────────────────────────────────────────────

def _build_referral_code(name: str, suffix_len: int = 4) -> str:
    """Build a code like DAOUDA-4F2K from a name."""
    suffix = "".join(random.choices(string.ascii_uppercase + string.digits, k=suffix_len))
    clean = "".join(c for c in (name or "") if c.isalnum() or c == " ")
    prefix = (clean or "USER")[:6].upper().replace(" ", "")
    return f"{prefix}-{suffix}"


def generate_referral_code(name: str) -> str:
    """Sync version (no uniqueness check). Kept for backward compat."""
    return _build_referral_code(name)


async def generate_unique_referral_code(name: str) -> str:
    """Generate a unique referral code, checking DB for collisions."""
    for _ in range(10):
        code = _build_referral_code(name)
        if not await db.users.find_one({"referral_code": code}, {"_id": 0, "user_id": 1}):
            return code
    # Fallback: longer suffix to reduce collision odds
    return _build_referral_code(name, suffix_len=6)


# ── Tier helpers ─────────────────────────────────────────────────────────────

def compute_tier(points: int) -> str:
    if points >= 500:
        return "gold"
    if points >= 200:
        return "silver"
    return "bronze"


def tier_discount_coeff(tier: str) -> float:
    """Coefficient de reduction fidelite (1.0 = aucune reduction)."""
    return {"bronze": 1.0, "silver": 0.90, "gold": 0.80}.get(tier, 1.0)


# ── App settings ─────────────────────────────────────────────────────────────

async def get_global_app_settings() -> dict:
    return await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}


# ── Central per-role config resolver ─────────────────────────────────────────

def get_referral_role_config(settings_doc: dict | None, role: str) -> dict:
    """
    Returns the effective referral config for a given role.
    Priority: referral_roles.{role} > legacy flat fields > hardcoded defaults.
    Roles not in REFERRAL_ELIGIBLE_ROLES get enabled=False.
    """
    if role not in REFERRAL_ELIGIBLE_ROLES:
        return {"enabled": False, "sponsor_bonus_xof": 0, "referred_bonus_xof": 0,
                "apply_metric": "sent_parcels", "apply_max_count": 0,
                "reward_metric": "delivered_sender_parcels", "reward_count": 1,
                "max_referrals_per_sponsor": 0}

    doc = settings_doc or {}
    defaults = REFERRAL_ROLE_DEFAULTS[role]

    # New per-role structure
    role_config = doc.get("referral_roles", {}).get(role)
    if isinstance(role_config, dict):
        return {
            "enabled": bool(role_config.get("enabled", defaults["enabled"])),
            "sponsor_bonus_xof": _safe_int(role_config.get("sponsor_bonus_xof"), defaults["sponsor_bonus_xof"]),
            "referred_bonus_xof": _safe_int(role_config.get("referred_bonus_xof"), defaults["referred_bonus_xof"]),
            "apply_metric": _safe_metric(role_config.get("apply_metric"), defaults["apply_metric"]),
            "apply_max_count": _safe_int(role_config.get("apply_max_count"), defaults["apply_max_count"]),
            "reward_metric": _safe_metric(role_config.get("reward_metric"), defaults["reward_metric"]),
            "reward_count": max(_safe_int(role_config.get("reward_count"), defaults["reward_count"]), 1),
            "max_referrals_per_sponsor": _safe_int(role_config.get("max_referrals_per_sponsor"), defaults["max_referrals_per_sponsor"]),
        }

    # Legacy flat fields fallback
    if doc.get("referral_enabled") is not None or doc.get("referral_bonus_xof") is not None:
        legacy_enabled = bool(doc.get("referral_enabled", True))
        allowed_roles = doc.get("referral_sponsor_allowed_roles",
                                doc.get("referral_allowed_roles", DEFAULT_REFERRAL_ALLOWED_ROLES))
        role_enabled = legacy_enabled and role in (allowed_roles or [])
        return {
            "enabled": role_enabled,
            "sponsor_bonus_xof": _safe_int(doc.get("referral_sponsor_bonus_xof", doc.get("referral_bonus_xof")), defaults["sponsor_bonus_xof"]),
            "referred_bonus_xof": _safe_int(doc.get("referral_referred_bonus_xof", doc.get("referral_bonus_xof")), defaults["referred_bonus_xof"]),
            "apply_metric": _safe_metric(doc.get("referral_apply_metric"), defaults["apply_metric"]),
            "apply_max_count": _safe_int(doc.get("referral_apply_max_count"), defaults["apply_max_count"]),
            "reward_metric": _safe_metric(doc.get("referral_reward_metric"), defaults["reward_metric"]),
            "reward_count": max(_safe_int(doc.get("referral_reward_count"), defaults["reward_count"]), 1),
            "max_referrals_per_sponsor": 0,
        }

    # Pure defaults
    return dict(defaults)


def _safe_int(val, default: int) -> int:
    try:
        return max(int(val), 0)
    except (TypeError, ValueError):
        return default


def _safe_metric(val, default: str) -> str:
    s = str(val or "").strip()
    return s if s in REFERRAL_METRIC_LABELS else default


# ── Convenience getters (role-aware) ─────────────────────────────────────────

def get_referral_sponsor_bonus_xof(settings_doc: dict | None, role: str = "client") -> int:
    return get_referral_role_config(settings_doc, role)["sponsor_bonus_xof"]


def get_referral_referred_bonus_xof(settings_doc: dict | None, role: str = "client") -> int:
    return get_referral_role_config(settings_doc, role)["referred_bonus_xof"]


def get_referral_apply_metric(settings_doc: dict | None, role: str = "client") -> str:
    return get_referral_role_config(settings_doc, role)["apply_metric"]


def get_referral_apply_max_count(settings_doc: dict | None, role: str = "client") -> int:
    return get_referral_role_config(settings_doc, role)["apply_max_count"]


def get_referral_reward_metric(settings_doc: dict | None, role: str = "client") -> str:
    return get_referral_role_config(settings_doc, role)["reward_metric"]


def get_referral_reward_count(settings_doc: dict | None, role: str = "client") -> int:
    return get_referral_role_config(settings_doc, role)["reward_count"]


def get_referral_bonus_xof(settings_doc: dict | None, role: str = "client") -> int:
    return get_referral_referred_bonus_xof(settings_doc, role)


# ── Share URL helpers ────────────────────────────────────────────────────────

def get_referral_share_base_url(settings_doc: dict | None) -> str | None:
    raw = str((settings_doc or {}).get("referral_share_base_url") or "").strip()
    return raw or None


def get_default_referral_share_base_url() -> str:
    base_url = str(settings.BASE_URL or "").strip().rstrip("/")
    return f"{base_url}/api/users/referral/{{code}}"


def get_effective_referral_share_base_url(settings_doc: dict | None) -> str:
    return get_referral_share_base_url(settings_doc) or get_default_referral_share_base_url()


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


# ── Metric helpers ───────────────────────────────────────────────────────────

def get_referral_metric_options(role: str | None = None) -> list[dict[str, str]]:
    if role and role in REFERRAL_ROLE_METRICS:
        metrics = REFERRAL_ROLE_METRICS[role]
    else:
        metrics = list(REFERRAL_METRIC_LABELS.keys())
    return [
        {"value": m, "label": format_referral_metric_threshold(m, 2)}
        for m in metrics
    ]


def get_referral_metric_label(metric: str, count: int = 2) -> str:
    singular, plural = REFERRAL_METRIC_LABELS.get(
        metric, REFERRAL_METRIC_LABELS[DEFAULT_REFERRAL_APPLY_METRIC],
    )
    return singular if count == 1 else plural


def format_referral_metric_threshold(metric: str, count: int) -> str:
    normalized_count = max(int(count), 0)
    return f"{normalized_count} {get_referral_metric_label(metric, normalized_count)}"


async def get_referral_metric_count(user_id: str, metric: str) -> int:
    normalized = _safe_metric(metric, DEFAULT_REFERRAL_APPLY_METRIC)
    if normalized == "sent_parcels":
        return await db.parcels.count_documents({"sender_user_id": user_id})
    if normalized == "delivered_sender_parcels":
        return await db.parcels.count_documents(
            {"sender_user_id": user_id, "status": "delivered"}
        )
    if normalized == "completed_driver_deliveries":
        return await db.delivery_missions.count_documents(
            {"driver_id": user_id, "status": "completed"}
        )
    return 0


# ── Rule description ─────────────────────────────────────────────────────────

def describe_referral_apply_rule(settings_doc: dict | None, role: str = "client") -> str:
    config = get_referral_role_config(settings_doc, role)
    metric = config["apply_metric"]
    max_count = config["apply_max_count"]
    return (
        "Code applicable tant que le compte ne depasse pas "
        f"{format_referral_metric_threshold(metric, max_count)}."
    )


def describe_referral_reward_rule(settings_doc: dict | None, role: str = "client") -> str:
    config = get_referral_role_config(settings_doc, role)
    metric = config["reward_metric"]
    count = config["reward_count"]
    return f"Prime debloquee apres {format_referral_metric_threshold(metric, count)}."


# ── Enablement checks ───────────────────────────────────────────────────────

def is_referral_globally_enabled(settings_doc: dict | None) -> bool:
    """True if at least one role has referral enabled."""
    for role in REFERRAL_ELIGIBLE_ROLES:
        if get_referral_role_config(settings_doc, role).get("enabled"):
            return True
    return False


def is_referral_sponsor_enabled_for_user(user_doc: dict | None, settings_doc: dict | None) -> bool:
    if not user_doc:
        return False
    if user_doc.get("is_banned") or user_doc.get("is_active") is False:
        return False
    override = user_doc.get("referral_enabled_override")
    if override is True:
        return True
    if override is False:
        return False
    role = str(user_doc.get("role") or "client")
    return get_referral_role_config(settings_doc, role).get("enabled", False)


def is_referral_referred_enabled_for_user(user_doc: dict | None, settings_doc: dict | None) -> bool:
    if not user_doc:
        return False
    if user_doc.get("is_banned") or user_doc.get("is_active") is False:
        return False
    override = user_doc.get("referral_enabled_override")
    if override is True:
        return True
    if override is False:
        return False
    role = str(user_doc.get("role") or "client")
    return get_referral_role_config(settings_doc, role).get("enabled", False)


def is_referral_enabled_for_user(user_doc: dict | None, settings_doc: dict | None) -> bool:
    return is_referral_sponsor_enabled_for_user(user_doc, settings_doc)


async def check_sponsor_referral_limit(sponsor_user_id: str, role: str, settings_doc: dict | None) -> bool:
    """Returns True if the sponsor can still accept more referrals."""
    config = get_referral_role_config(settings_doc, role)
    max_count = config.get("max_referrals_per_sponsor", 0)
    if max_count <= 0:
        return True  # unlimited
    current = await db.users.count_documents({"referred_by": sponsor_user_id})
    return current < max_count


# ── Legacy compat wrappers (for callers that don't pass role) ────────────────

def get_referral_allowed_roles(settings_doc: dict | None) -> list[str]:
    return [r for r in REFERRAL_ELIGIBLE_ROLES
            if get_referral_role_config(settings_doc, r).get("enabled")]


def get_referral_sponsor_allowed_roles(settings_doc: dict | None) -> list[str]:
    return get_referral_allowed_roles(settings_doc)


def get_referral_referred_allowed_roles(settings_doc: dict | None) -> list[str]:
    return get_referral_allowed_roles(settings_doc)


def is_referral_role_allowed(role: str | None, settings_doc: dict | None) -> bool:
    r = str(role or "client")
    return get_referral_role_config(settings_doc, r).get("enabled", False)


def is_referral_sponsor_role_allowed(role: str | None, settings_doc: dict | None) -> bool:
    return is_referral_role_allowed(role, settings_doc)


def is_referral_referred_role_allowed(role: str | None, settings_doc: dict | None) -> bool:
    return is_referral_role_allowed(role, settings_doc)
