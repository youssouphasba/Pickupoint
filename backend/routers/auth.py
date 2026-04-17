"""
Router auth : Firebase Auth + OTP flow + gestion session JWT.
"""
import uuid
import logging
from datetime import datetime, timezone, timedelta

from typing import Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from config import settings
from core.exceptions import bad_request_exception, not_found_exception
from core.security import (
    create_access_token,
    create_refresh_token,
    create_registration_token,
    verify_refresh_token,
)
from core.dependencies import get_current_user
from core.utils import normalize_phone, is_supported_phone
from database import db
from models.user import OTPRequest, TokenResponse, RefreshRequest, ProfileUpdate, User
from services.parcel_service import _record_event
from services.user_service import (
    generate_unique_referral_code,
    get_global_app_settings,
    is_referral_referred_enabled_for_user,
    is_referral_sponsor_enabled_for_user,
)

router = APIRouter()
logger = logging.getLogger(__name__)

# Utilisation du limiter global défini dans core/limiter
from core.limiter import limiter

# ── Firebase Admin SDK init ──────────────────────────────────────────────────
import firebase_admin
from firebase_admin import credentials, auth as firebase_auth

if not firebase_admin._apps:
    import os, json
    firebase_creds_env = os.environ.get("FIREBASE_CREDENTIALS")
    if firebase_creds_env:
        # Railway: JSON complet dans la variable d'env
        cred = credentials.Certificate(json.loads(firebase_creds_env))
    elif settings.FIREBASE_CREDENTIALS_PATH and os.path.exists(settings.FIREBASE_CREDENTIALS_PATH):
        cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
    else:
        cred = None
        logger.warning("Firebase credentials not found — /auth/firebase will not work")
    if cred:
        firebase_admin.initialize_app(cred)


# ── Firebase Auth endpoint ───────────────────────────────────────────────────

class FirebaseAuthRequest(BaseModel):
    id_token: str

@router.post("/firebase", summary="Authentification via Firebase Phone Auth")
@limiter.limit("10/minute")
async def firebase_login(body: FirebaseAuthRequest, request: Request):
    """
    Reçoit un Firebase ID token après vérification téléphone côté Flutter.
    Crée ou connecte l'utilisateur et renvoie les JWT Denkma.
    """
    try:
        decoded = firebase_auth.verify_id_token(body.id_token)
    except Exception as e:
        logger.warning("Firebase token verification failed: %s", e)
        raise bad_request_exception("Token Firebase invalide ou expiré")

    phone = normalize_phone(decoded.get("phone_number"))
    if not phone:
        raise bad_request_exception("Le token Firebase ne contient pas de numéro de téléphone")
    if not is_supported_phone(phone):
        raise bad_request_exception("Denkma est disponible au Sénégal et en France uniquement")

    user_doc = await db.users.find_one({"phone": phone}, {"_id": 0})

    # Nouvel utilisateur → renvoyer un registration_token
    if not user_doc:
        temp_token = create_registration_token(
            phone,
            expires_delta=timedelta(hours=1),
        )
        return {"is_new_user": True, "registration_token": temp_token}

    # Utilisateur banni
    if user_doc.get("is_banned"):
        from core.exceptions import forbidden_exception
        raise forbidden_exception("Votre compte a été suspendu par l'administration.")

    # Marquer le téléphone comme vérifié
    await db.users.update_one(
        {"phone": phone},
        {"$set": {"is_phone_verified": True, "updated_at": datetime.now(timezone.utc)}},
    )
    user_doc["is_phone_verified"] = True

    token_data = {"sub": user_doc["user_id"], "role": user_doc["role"]}
    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)

    await db.user_sessions.insert_one({
        "user_id":       user_doc["user_id"],
        "refresh_token": refresh_token,
        "created_at":    datetime.now(timezone.utc),
        "expires_at":    datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    })

    return {
        "is_new_user": False,
        "session": {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "user": User(**user_doc).model_dump(),
        },
    }


@router.post("/check-phone", summary="Vérifier si un numéro est inscrit")
@limiter.limit("10/minute")
async def check_phone(body: OTPRequest, request: Request):
    """
    Retourne { "exists": bool, "has_pin": bool }
    Permet à l'app mobile de savoir si elle doit afficher l'écran de Login PIN
    ou envoyer un OTP pour une nouvelle inscription.
    """
    phone = normalize_phone(body.phone)
    user_doc = await db.users.find_one({"phone": phone}, {"_id": 0, "pin_hash": 1})
    if not user_doc:
        return {"exists": False, "has_pin": False}
    
    has_pin = user_doc.get("pin_hash") is not None
    return {"exists": True, "has_pin": has_pin}



class PINLoginRequest(BaseModel):
    phone: str
    pin: str

@router.post("/login-pin", response_model=TokenResponse, summary="Connexion par PIN")
@limiter.limit("10/minute")
async def login_pin(body: PINLoginRequest, request: Request):
    phone = normalize_phone(body.phone)
    user_doc = await db.users.find_one({"phone": phone}, {"_id": 0})
    if not user_doc:
        raise bad_request_exception("Utilisateur introuvable")
    
    if user_doc.get("is_banned"):
        from core.exceptions import forbidden_exception
        raise forbidden_exception("Votre compte a été suspendu par l'administration.")
        
    pin_hash = user_doc.get("pin_hash")
    if not pin_hash:
        raise bad_request_exception("Aucun code PIN configuré pour ce compte. Veuillez utiliser la réinitialisation.")
        
    from core.security import verify_password
    if not verify_password(body.pin, pin_hash):
        raise bad_request_exception("Code PIN incorrect")
        
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


class CompleteRegistrationRequest(BaseModel):
    registration_token: str
    name: str
    pin: str
    accepted_legal: bool
    referral_code: Optional[str] = None

@router.post("/complete-registration", response_model=TokenResponse, summary="Finaliser l'inscription avec Nom et PIN")
@limiter.limit("5/minute")
async def complete_registration(body: CompleteRegistrationRequest, request: Request):
    if not body.accepted_legal:
        raise bad_request_exception("Vous devez accepter les CGU et la Politique de confidentialité.")
        
    from core.security import decode_token
    try:
        payload = decode_token(body.registration_token)
        phone = normalize_phone(payload.get("sub"))
        token_type = payload.get("type")
        is_legacy_registration_token = (
            token_type == "access"
            and not payload.get("role")
            and bool(phone)
        )
        if token_type != "registration_token" and not is_legacy_registration_token:
            raise bad_request_exception("Token d'inscription invalide.")
    except Exception:
        raise bad_request_exception("Token d'inscription expiré ou invalide.")
        
    # Vérifier que le numéro n'est pas déjà inscrit complètement
    existing_user = await db.users.find_one({"phone": phone}, {"_id": 0})
    if existing_user:
        raise bad_request_exception("Cet utilisateur existe déjà.")
        
    if len(body.pin) < 4:
        raise bad_request_exception("Le code PIN doit contenir au moins 4 chiffres.")

    referral_code = (body.referral_code or "").upper().strip() or None
    referred_by = None
    if referral_code:
        app_settings = await get_global_app_settings()
        pending_user = {"role": "client", "is_active": True, "is_banned": False}
        if not is_referral_referred_enabled_for_user(pending_user, app_settings):
            raise bad_request_exception(
                "Le parrainage n'est pas disponible pour les nouveaux comptes clients"
            )
        sponsor = await db.users.find_one({"referral_code": referral_code}, {"_id": 0})
        if not sponsor:
            raise bad_request_exception("Code parrainage invalide")
        if not is_referral_sponsor_enabled_for_user(sponsor, app_settings):
            raise bad_request_exception("Ce code parrainage n'est pas actif")
        referred_by = sponsor["user_id"]

    from core.security import hash_password
    now = datetime.now(timezone.utc)

    user_doc = {
        "user_id":           f"usr_{uuid.uuid4().hex[:12]}",
        "phone":             phone,
        "name":              body.name,
        "email":             None,
        "user_type":         "individual",
        "role":              "client",
        "is_active":         True,
        "is_phone_verified": True,
        "accepted_legal":    True,
        "accepted_legal_at": now,
        "pin_hash":          hash_password(body.pin),
        "relay_point_id":    None,
        "store_id":          None,
        "external_ref":      None,
        "language":          "fr",
        "currency":          "XOF",
        "country_code":      "SN",
        "loyalty_points":    0,
        "loyalty_tier":      "bronze",
        "referral_code":     await generate_unique_referral_code(body.name),
        "referred_by":       referred_by,
        "referral_applied_at": now if referred_by else None,
        "referral_source":   "signup" if referred_by else None,
        "created_at":        now,
        "updated_at":        now,
    }
    await db.users.insert_one(user_doc)

    if referred_by:
        await _record_event(
            event_type="USER_REGISTERED_WITH_REFERRAL",
            actor_id=user_doc["user_id"],
            actor_role=user_doc["role"],
            notes=f"Inscription avec code parrainage: {referral_code}",
            metadata={
                "user_id": user_doc["user_id"],
                "sponsor_user_id": referred_by,
                "referral_code": referral_code,
                "source": "signup",
            },
        )

    token_data = {"sub": user_doc["user_id"], "role": user_doc["role"]}
    access_token  = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)

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


class FirebaseResetPinRequest(BaseModel):
    id_token: str
    new_pin: str


@router.post("/reset-pin-firebase", summary="Reinitialiser le PIN via Firebase")
@limiter.limit("5/minute")
async def reset_pin_firebase(body: FirebaseResetPinRequest, request: Request):
    try:
        decoded = firebase_auth.verify_id_token(body.id_token)
    except Exception as e:
        logger.warning("Firebase reset-pin token verification failed: %s", e)
        raise bad_request_exception("Verification Firebase invalide ou expiree")

    phone = normalize_phone(decoded.get("phone_number"))
    if not phone:
        raise bad_request_exception(
            "Le token Firebase ne contient pas de numero de telephone"
        )

    if len(body.new_pin) < 4:
        raise bad_request_exception(
            "Le code PIN doit contenir au moins 4 chiffres."
        )

    user_doc = await db.users.find_one({"phone": phone}, {"_id": 0})
    if not user_doc:
        raise bad_request_exception("Utilisateur introuvable")

    from core.security import hash_password

    await db.users.update_one(
        {"phone": phone},
        {
            "$set": {
                "pin_hash": hash_password(body.new_pin),
                "is_phone_verified": True,
                "updated_at": datetime.now(timezone.utc),
            }
        },
    )
    return {"message": "Code PIN reinitialise avec succes."}


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
    
    if user_doc.get("is_banned"):
        from core.exceptions import forbidden_exception
        raise forbidden_exception("Session révoquée : compte suspendu.")

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
