"""
Router public pour les parametres de lecture seule de l'application.
"""
from fastapi import APIRouter

from config import settings as app_config
from database import db
from services.user_service import (
    get_referral_bonus_xof,
    get_referral_share_base_url,
    is_referral_globally_enabled,
)

router = APIRouter()


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
        "referral_bonus_xof": get_referral_bonus_xof(settings_doc),
        "referral_share_base_url": get_referral_share_base_url(settings_doc),
    }
