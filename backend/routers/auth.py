"""
Router auth : OTP flow complet + gestion session JWT.
"""
import uuid
from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Depends

from config import settings
from core.exceptions import bad_request_exception, not_found_exception
from core.security import (
    create_access_token,
    create_refresh_token,
    verify_refresh_token,
)
from core.dependencies import get_current_user
from database import db
from models.user import OTPRequest, OTPVerify, TokenResponse, RefreshRequest, ProfileUpdate, User
from services.otp_service import send_otp, verify_otp

router = APIRouter()


@router.post("/request-otp", summary="Envoyer OTP")
async def request_otp(body: OTPRequest):
    ok = await send_otp(body.phone)
    return {"sent": ok, "phone": body.phone}


@router.post("/verify-otp", response_model=TokenResponse, summary="Vérifier OTP → JWT")
async def verify_otp_endpoint(body: OTPVerify):
    valid = await verify_otp(body.phone, body.otp)
    if not valid:
        raise bad_request_exception("OTP invalide ou expiré")

    # Trouver ou créer l'utilisateur
    user_doc = await db.users.find_one({"phone": body.phone}, {"_id": 0})
    if not user_doc:
        now = datetime.now(timezone.utc)
        user_doc = {
            "user_id":           f"usr_{uuid.uuid4().hex[:12]}",
            "phone":             body.phone,
            "name":              body.phone,   # mis à jour après
            "email":             None,
            "role":              "client",
            "is_active":         True,
            "is_phone_verified": True,
            "relay_point_id":    None,
            "store_id":          None,
            "external_ref":      None,
            "language":          "fr",
            "currency":          "XOF",
            "country_code":      "SN",
            "created_at":        now,
            "updated_at":        now,
        }
        await db.users.insert_one(user_doc)
    else:
        await db.users.update_one(
            {"phone": body.phone},
            {"$set": {"is_phone_verified": True, "updated_at": datetime.now(timezone.utc)}},
        )
        user_doc["is_phone_verified"] = True

    token_data = {"sub": user_doc["user_id"], "role": user_doc["role"]}
    access_token  = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)

    # Stocker le refresh token
    await db.user_sessions.insert_one({
        "user_id":       user_doc["user_id"],
        "refresh_token": refresh_token,
        "created_at":    datetime.now(timezone.utc),
        "expires_at":    datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    })

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=User(**user_doc),
    )


@router.post("/refresh", response_model=TokenResponse, summary="Rafraîchir access token")
async def refresh_token(body: RefreshRequest):
    payload = verify_refresh_token(body.refresh_token)
    if not payload:
        raise bad_request_exception("Refresh token invalide ou expiré")

    # Vérifier que le token existe en base
    session = await db.user_sessions.find_one({"refresh_token": body.refresh_token})
    if not session:
        raise bad_request_exception("Session invalide")

    user_doc = await db.users.find_one({"user_id": payload["sub"]}, {"_id": 0})
    if not user_doc:
        raise not_found_exception("Utilisateur")

    token_data    = {"sub": user_doc["user_id"], "role": user_doc["role"]}
    access_token  = create_access_token(token_data)
    new_refresh   = create_refresh_token(token_data)

    # Remplacer le refresh token (rotation)
    await db.user_sessions.replace_one(
        {"refresh_token": body.refresh_token},
        {
            "user_id":       user_doc["user_id"],
            "refresh_token": new_refresh,
            "created_at":    datetime.now(timezone.utc),
            "expires_at":    datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        },
    )

    return TokenResponse(
        access_token=access_token,
        refresh_token=new_refresh,
        user=User(**user_doc),
    )


@router.post("/logout", summary="Invalider refresh token")
async def logout(body: RefreshRequest):
    await db.user_sessions.delete_one({"refresh_token": body.refresh_token})
    return {"message": "Déconnecté avec succès"}


@router.get("/me", response_model=User, summary="Profil courant")
async def me(current_user: dict = Depends(get_current_user)):
    return User(**current_user)


@router.put("/profile", response_model=User, summary="Mettre à jour profil")
async def update_profile(
    body: ProfileUpdate,
    current_user: dict = Depends(get_current_user),
):
    updates = body.model_dump(exclude_none=True)
    if not updates:
        return User(**current_user)
    updates["updated_at"] = datetime.now(timezone.utc)
    await db.users.update_one({"user_id": current_user["user_id"]}, {"$set": updates})
    updated = await db.users.find_one({"user_id": current_user["user_id"]}, {"_id": 0})
    return User(**updated)
