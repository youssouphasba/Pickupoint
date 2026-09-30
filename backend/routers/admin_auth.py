"""
Authentification du dashboard admin web.
Login email+password, cookie httpOnly cross-subdomain (denkma.com).
"""
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, EmailStr, Field
import pyotp

from config import settings
from core.dependencies import ADMIN_COOKIE_NAME, get_current_user
from core.admin_mfa import admin_mfa_key_id
from core.private_documents import can_access_kyc_documents
from core.datetime_utils import as_aware_utc
from core.exceptions import forbidden_exception, bad_request_exception
from core.limiter import limiter
from core.security import (
    create_access_token,
    hash_password,
    verify_password,
)
from database import db
from models.common import UserRole

router = APIRouter()

ADMIN_ROLES = {UserRole.ADMIN.value, UserRole.SUPERADMIN.value}


class AdminLoginPayload(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    otp: Optional[str] = Field(default=None, pattern=r"^\d{6}$")


class AdminSetPasswordPayload(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)


def _cookie_settings() -> dict:
    """httpOnly, Secure en prod, SameSite Lax, scope .denkma.com pour cross-subdomain."""
    base = {
        "key": ADMIN_COOKIE_NAME,
        "httponly": True,
        "samesite": "lax",
        "path": "/",
        "max_age": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    }
    if not settings.DEBUG or settings.APP_ENV.lower() in {"production", "prod"}:
        base["secure"] = True
        base["domain"] = ".denkma.com"
    return base


@router.post("/login", summary="Login admin web (email + password)")
@limiter.limit("10/minute")
async def admin_login(payload: AdminLoginPayload, request: Request, response: Response):
    email_norm = payload.email.strip().lower()
    user = await db.users.find_one({"email": email_norm}, {"_id": 0})
    if not user or user.get("role") not in ADMIN_ROLES:
        raise forbidden_exception("Identifiants invalides")

    hashed = user.get("admin_password_hash")
    if not hashed or not verify_password(payload.password, hashed):
        raise forbidden_exception("Identifiants invalides")

    if user.get("is_banned") or not user.get("is_active", True):
        raise forbidden_exception("Compte désactivé")

    mfa_secret = settings.ADMIN_MFA_TOTP_SECRETS.get(email_norm)
    if settings.ADMIN_REQUIRE_MFA and not mfa_secret:
        raise forbidden_exception("La double authentification doit être configurée pour ce compte administrateur.")
    mfa_counter = None
    mfa_key_id = admin_mfa_key_id(email_norm)
    if mfa_secret:
        now = datetime.now(timezone.utc)
        locked_until = as_aware_utc(user.get("admin_mfa_locked_until"))
        if locked_until and locked_until > now:
            raise forbidden_exception("Trop de codes incorrects. Réessayez dans quelques minutes.")
        if locked_until:
            await db.users.update_one({"user_id": user["user_id"], "admin_mfa_locked_until": user.get("admin_mfa_locked_until")}, {
                "$set": {"admin_mfa_failed_attempts": 0, "admin_mfa_locked_until": None},
            })
        if not payload.otp:
            return {"ok": False, "mfa_required": True}
        totp = pyotp.TOTP(mfa_secret)
        previous_counter = (user.get("admin_mfa_last_counter") or -1) if user.get("admin_mfa_key_id") == mfa_key_id else -1
        current_counter = totp.timecode(now)
        for counter in (current_counter, current_counter - 1, current_counter + 1):
            if counter > previous_counter and pyotp.utils.strings_equal(totp.at(counter * totp.interval), payload.otp):
                mfa_counter = counter
                break
        if mfa_counter is None:
            failures = await db.users.find_one_and_update(
                {"user_id": user["user_id"]}, {"$inc": {"admin_mfa_failed_attempts": 1}},
                return_document=True, projection={"admin_mfa_failed_attempts": 1},
            )
            if (failures or {}).get("admin_mfa_failed_attempts", 0) >= settings.ADMIN_MFA_MAX_ATTEMPTS:
                await db.users.update_one({"user_id": user["user_id"]}, {"$set": {
                    "admin_mfa_locked_until": now + timedelta(seconds=settings.ADMIN_MFA_LOCK_SECONDS),
                }})
            raise forbidden_exception("Code de double authentification invalide ou déjà utilisé.")
        accepted = await db.users.update_one({"user_id": user["user_id"],
            "admin_mfa_last_counter": user.get("admin_mfa_last_counter"),
            "admin_mfa_key_id": user.get("admin_mfa_key_id"),
            "is_active": {"$ne": False}, "is_banned": {"$ne": True}}, {"$set": {
                "admin_mfa_last_counter": mfa_counter, "admin_mfa_failed_attempts": 0,
                "admin_mfa_locked_until": None, "admin_mfa_key_id": mfa_key_id,
            }})
        if accepted.modified_count != 1:
            raise forbidden_exception("Ce code vient d’être utilisé. Attendez le prochain code.")

    token = create_access_token({
        "sub": user["user_id"],
        "role": user["role"],
        "admin_mfa": mfa_counter is not None,
        "admin_mfa_key_id": mfa_key_id,
    })
    response.set_cookie(value=token, **_cookie_settings())

    await db.users.update_one(
        {"user_id": user["user_id"]},
        {"$set": {"admin_last_login_at": datetime.now(timezone.utc)}},
    )

    return {
        "ok": True,
        "user": {
            "id": user["user_id"],
            "email": user.get("email"),
            "full_name": user.get("full_name"),
            "role": user["role"],
        },
    }


@router.post("/logout", summary="Logout admin web")
async def admin_logout(response: Response):
    opts = _cookie_settings()
    opts.pop("max_age", None)
    response.delete_cookie(
        key=opts["key"],
        path=opts.get("path", "/"),
        domain=opts.get("domain"),
    )
    return {"ok": True}


@router.get("/me", summary="Info admin connecté (via cookie)")
async def admin_me(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") not in ADMIN_ROLES:
        raise forbidden_exception()
    return {
        "id": current_user["user_id"],
        "email": current_user.get("email"),
        "full_name": current_user.get("full_name"),
        "role": current_user["role"],
        "avatar_url": current_user.get("profile_picture_url"),
        "can_access_kyc_documents": can_access_kyc_documents(current_user),
    }


@router.post("/set-password", summary="Définit/réinitialise le mot de passe admin (superadmin uniquement)")
async def admin_set_password(
    payload: AdminSetPasswordPayload,
    current_user: dict = Depends(get_current_user),
):
    if current_user.get("role") != UserRole.SUPERADMIN.value:
        raise forbidden_exception("Seul un superadmin peut définir un mot de passe admin")

    email_norm = payload.email.strip().lower()
    target = await db.users.find_one({"email": email_norm}, {"_id": 0})
    if not target or target.get("role") not in ADMIN_ROLES:
        raise bad_request_exception("Aucun administrateur avec cet email")

    await db.users.update_one(
        {"user_id": target["user_id"]},
        {"$set": {
            "admin_password_hash": hash_password(payload.password),
            "admin_password_set_at": datetime.now(timezone.utc),
        }},
    )
    return {"ok": True}
