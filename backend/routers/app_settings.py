"""
Router public pour les parametres de lecture seule de l'application.
"""
import re
from urllib.parse import quote

from fastapi import APIRouter

from config import settings as app_config
from database import db
from services.user_service import (
    REFERRAL_ELIGIBLE_ROLES,
    describe_referral_reward_rule,
    get_referral_role_config,
    get_referral_share_base_url,
    is_referral_globally_enabled,
)

router = APIRouter()


def _support_whatsapp_payload(settings_doc: dict) -> dict:
    phone = str(
        settings_doc.get("support_whatsapp_phone")
        or app_config.SUPPORT_WHATSAPP_PHONE
        or ""
    ).strip()
    digits = re.sub(r"\D", "", phone)
    message = "Bonjour Denkma, j'ai besoin d'aide."
    return {
        "support_whatsapp_phone": phone,
        "support_whatsapp_url": f"https://wa.me/{digits}?text={quote(message)}" if digits else None,
    }


@router.get("", summary="Lire les parametres publics de l'app")
async def get_public_app_settings():
    settings_doc = await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}
    express_enabled = bool(settings_doc.get("express_enabled", False))
    express_percent = int(round((app_config.EXPRESS_MULTIPLIER - 1) * 100))
    return {
        "express_enabled": express_enabled,
        "express_multiplier": app_config.EXPRESS_MULTIPLIER,
        "express_percent": express_percent,
        "referral_enabled": is_referral_globally_enabled(settings_doc),
        "referral_share_base_url": get_referral_share_base_url(settings_doc),
        "referral_roles": {
            role: {
                "enabled": get_referral_role_config(settings_doc, role).get("enabled", False),
                "referred_bonus_xof": get_referral_role_config(settings_doc, role).get("referred_bonus_xof", 500),
                "reward_rule": describe_referral_reward_rule(settings_doc, role),
            }
            for role in REFERRAL_ELIGIBLE_ROLES
        },
        **_support_whatsapp_payload(settings_doc),
    }
