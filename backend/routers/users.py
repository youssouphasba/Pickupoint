"""
Router users : gestion utilisateurs, enregistrement driver/agent relais.
"""
from html import escape
import mimetypes
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, File, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse
from pydantic import BaseModel, Field

from config import UPLOADS_DIR, settings
from core.dependencies import get_current_user, require_role
from core.exceptions import bad_request_exception, forbidden_exception, not_found_exception
from core.limiter import limiter
from core.utils import normalize_phone
from database import db
from models.common import UserRole
from models.user import FavoriteAddress, ProfileUpdate, User
from services.parcel_service import _record_event
from services.user_service import (
    build_referral_share_message,
    build_referral_url,
    check_sponsor_referral_limit,
    describe_referral_apply_rule,
    describe_referral_reward_rule,
    get_effective_referral_share_base_url,
    get_global_app_settings,
    get_referral_metric_count,
    get_referral_metric_label,
    get_referral_metric_options,
    get_referral_role_config,
    get_referral_share_base_url,
    is_referral_referred_enabled_for_user,
    is_referral_sponsor_enabled_for_user,
)

router = APIRouter()

MAX_AVATAR_SIZE = 5 * 1024 * 1024
MAX_KYC_SIZE = 10 * 1024 * 1024
PRIVATE_UPLOADS_DIR = UPLOADS_DIR.parent / "private_uploads"
PRIVATE_KYC_DIR = PRIVATE_UPLOADS_DIR / "kyc"
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


async def _build_referral_payload(user_doc: dict) -> dict:
    settings_doc = await get_global_app_settings()
    user_role = str(user_doc.get("role") or "client")
    config = get_referral_role_config(settings_doc, user_role)
    code = user_doc.get("referral_code", "")
    effective_share_base_url = get_effective_referral_share_base_url(settings_doc)
    referral_url = build_referral_url(code, effective_share_base_url)
    sponsor_enabled = is_referral_sponsor_enabled_for_user(user_doc, settings_doc)
    referred_enabled = is_referral_referred_enabled_for_user(user_doc, settings_doc)

    apply_metric = config["apply_metric"]
    apply_max_count = config["apply_max_count"]
    apply_current_count = await get_referral_metric_count(user_doc.get("user_id", ""), apply_metric)
    can_apply_now = (
        referred_enabled
        and not user_doc.get("referred_by")
        and apply_current_count <= apply_max_count
    )
    return {
        "enabled": sponsor_enabled,
        "enabled_override": user_doc.get("referral_enabled_override"),
        "referral_code": code,
        "referral_sponsor_bonus_xof": config["sponsor_bonus_xof"],
        "referral_referred_bonus_xof": config["referred_bonus_xof"],
        "referral_bonus_xof": config["referred_bonus_xof"],
        "share_base_url": get_referral_share_base_url(settings_doc),
        "effective_share_base_url": effective_share_base_url,
        "can_sponsor": sponsor_enabled,
        "can_be_referred": referred_enabled,
        "referral_url": referral_url,
        "apply_metric": apply_metric,
        "apply_metric_label": get_referral_metric_label(apply_metric),
        "apply_max_count": apply_max_count,
        "apply_current_count": apply_current_count,
        "can_apply_now": can_apply_now,
        "apply_rule": describe_referral_apply_rule(settings_doc, user_role),
        "reward_metric": config["reward_metric"],
        "reward_metric_label": get_referral_metric_label(config["reward_metric"]),
        "reward_count": config["reward_count"],
        "reward_rule": describe_referral_reward_rule(settings_doc, user_role),
        "metric_options": get_referral_metric_options(user_role),
        "share_message": build_referral_share_message(
            code=code,
            referral_url=referral_url,
            referred_bonus_xof=config["referred_bonus_xof"],
            reward_rule=describe_referral_reward_rule(settings_doc, user_role),
        ),
        "message": (
            "Le parrainage est disponible pour ce compte."
            if sponsor_enabled or referred_enabled
            else "Le parrainage est desactive pour ce compte."
        ),
    }


def _guess_image_extension(content: bytes) -> str | None:
    if content.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if content.startswith(b"RIFF") and content[8:12] == b"WEBP":
        return ".webp"
    return None


async def _read_upload_bytes(file: UploadFile, max_size: int) -> bytes:
    content = await file.read(max_size + 1)
    if not content:
        raise bad_request_exception("Fichier vide")
    if len(content) > max_size:
        raise bad_request_exception(
            f"Fichier trop volumineux (max {max_size // (1024 * 1024)} Mo)"
        )
    return content


def _validate_image_upload(file: UploadFile, content: bytes) -> str:
    if not (file.content_type or "").startswith("image/"):
        raise bad_request_exception("Le fichier doit etre une image")

    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext and ext not in IMAGE_EXTENSIONS:
        raise bad_request_exception(
            "Format d'image non supporte (.jpg, .png, .webp uniquement)"
        )

    detected_ext = _guess_image_extension(content)
    if not detected_ext:
        raise bad_request_exception("Image invalide ou format binaire non reconnu")

    return detected_ext


def _validate_kyc_upload(file: UploadFile, content: bytes) -> tuple[str, str]:
    ext = os.path.splitext(file.filename or "")[1].lower()
    if (file.content_type or "") == "application/pdf":
        if ext and ext != ".pdf":
            raise bad_request_exception("Extension PDF invalide")
        if not content.startswith(b"%PDF-"):
            raise bad_request_exception("PDF invalide ou corrompu")
        return ".pdf", "application/pdf"

    detected_ext = _validate_image_upload(file, content)
    content_type = {
        ".jpg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
    }[detected_ext]
    return detected_ext, content_type


def _kyc_fields(doc_type: Literal["id_card", "license"]) -> tuple[str, str, str]:
    if doc_type == "id_card":
        return "kyc_id_card_url", "kyc_id_card_path", "kyc_id_card_content_type"
    return "kyc_license_url", "kyc_license_path", "kyc_license_content_type"


def _resolve_kyc_file(
    user_doc: dict,
    doc_type: Literal["id_card", "license"],
) -> tuple[Path, str | None]:
    _, path_field, content_type_field = _kyc_fields(doc_type)
    stored_path = user_doc.get(path_field)
    if stored_path:
        candidate = Path(stored_path)
        if candidate.is_file():
            return candidate, user_doc.get(content_type_field)

    raise not_found_exception("Document KYC")


async def _serve_kyc_file(
    user_id: str,
    doc_type: Literal["id_card", "license"],
    current_user: dict,
):
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin and current_user["user_id"] != user_id:
        raise forbidden_exception("Vous ne pouvez consulter que vos propres documents KYC.")

    user_doc = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not user_doc:
        raise not_found_exception("Utilisateur")

    absolute_path, media_type = _resolve_kyc_file(user_doc, doc_type)
    guessed_type = (
        media_type
        or mimetypes.guess_type(str(absolute_path))[0]
        or "application/octet-stream"
    )
    filename = f"{doc_type}{absolute_path.suffix}"
    return FileResponse(path=absolute_path, media_type=guessed_type, filename=filename)


@router.get("", summary="Liste utilisateurs (admin)")
async def list_users(
    skip: int = 0,
    limit: int = 50,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    cursor = db.users.find({}, {"_id": 0}).skip(skip).limit(limit)
    users = await cursor.to_list(length=limit)
    return {"users": users, "total": await db.users.count_documents({})}


@router.get("/{user_id}", response_model=User, summary="Detail utilisateur")
async def get_user(user_id: str, current_user: dict = Depends(get_current_user)):
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin and current_user["user_id"] != user_id:
        raise forbidden_exception("Vous ne pouvez consulter que votre propre profil.")

    user_doc = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not user_doc:
        raise not_found_exception("Utilisateur")
    return User(**user_doc)


@router.put("/{user_id}/role", summary="Changer role (admin)")
async def change_role(
    user_id: str,
    role: UserRole,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    result = await db.users.update_one(
        {"user_id": user_id},
        {"$set": {"role": role.value, "updated_at": datetime.now(timezone.utc)}},
    )
    if result.matched_count == 0:
        raise not_found_exception("Utilisateur")

    await _record_event(
        event_type="USER_ROLE_CHANGED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Changement de role pour {user_id} -> {role.value}",
        metadata={"target_user_id": user_id, "new_role": role.value},
    )

    return {"message": f"Role mis a jour -> {role.value}"}


@router.get("/{user_id}/driver-stats", summary="Statistiques livreur (admin)")
async def driver_stats(
    user_id: str,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    total = await db.delivery_missions.count_documents({"driver_id": user_id})
    completed = await db.delivery_missions.count_documents(
        {"driver_id": user_id, "status": "completed"}
    )
    failed = await db.delivery_missions.count_documents(
        {"driver_id": user_id, "status": "failed"}
    )
    scan_rate = round(completed / max(total, 1) * 100, 1)
    return {
        "total_missions": total,
        "completed": completed,
        "failed": failed,
        "scan_rate_pct": scan_rate,
    }


@router.put("/me/availability", summary="Basculer la disponibilite (driver)")
async def toggle_availability(
    current_user: dict = Depends(get_current_user),
):
    """Permet au livreur de se mettre disponible ou hors-ligne."""
    current = current_user.get("is_available", False)
    new_val = not current
    if (
        new_val
        and current_user.get("role") == UserRole.DRIVER.value
        and (
            not (current_user.get("profile_picture_url") or "").strip()
            or current_user.get("profile_picture_status") != "approved"
        )
    ):
        raise bad_request_exception("Votre photo de profil doit être ajoutée puis approuvée avant de vous mettre disponible.")
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {"is_available": new_val, "updated_at": datetime.now(timezone.utc)}},
    )
    return {"is_available": new_val}


@router.put("/me/fcm-token", summary="Mettre a jour le token FCM (push)")
async def update_fcm_token(
    token_body: dict,
    current_user: dict = Depends(get_current_user),
):
    """Enregistre le token Firebase Cloud Messaging de l'appareil."""
    token = token_body.get("fcm_token")
    if not token:
        raise bad_request_exception("fcm_token manquant")

    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {"fcm_token": token, "updated_at": datetime.now(timezone.utc)}},
    )
    return {"message": "Token FCM mis a jour"}


@router.put("/me/profile", summary="Mise a jour profil (Bio, Email, Prefs)")
async def update_my_profile(
    body: ProfileUpdate,
    current_user: dict = Depends(get_current_user),
):
    updates = body.model_dump(exclude_none=True)
    if not updates:
        return current_user

    updates["updated_at"] = datetime.now(timezone.utc)
    if body.email:
        existing = await db.users.find_one(
            {"email": body.email, "user_id": {"$ne": current_user["user_id"]}}
        )
        if existing:
            raise bad_request_exception("Cet email est deja utilise")

    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": updates},
    )

    updated_user = await db.users.find_one(
        {"user_id": current_user["user_id"]},
        {"_id": 0},
    )
    return updated_user


@router.get("/me/favorite-addresses", summary="Mes adresses favorites")
async def get_favorites(current_user: dict = Depends(get_current_user)):
    return current_user.get("favorite_addresses", [])


@router.post("/me/favorite-addresses", summary="Ajouter une adresse favorite")
async def add_favorite(
    addr: FavoriteAddress,
    current_user: dict = Depends(get_current_user),
):
    favs = current_user.get("favorite_addresses", [])
    if any(f["name"] == addr.name for f in favs):
        raise bad_request_exception(f"Une adresse nommee '{addr.name}' existe deja")

    if len(favs) >= 10:
        raise bad_request_exception("Maximum 10 adresses favorites autorisees")

    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$push": {"favorite_addresses": addr.model_dump()}},
    )
    return {"message": f"Adresse '{addr.name}' ajoutee"}


@router.put("/me/favorite-addresses/{name}", summary="Modifier une adresse favorite")
async def update_favorite(
    name: str,
    addr: FavoriteAddress,
    current_user: dict = Depends(get_current_user),
):
    favs = current_user.get("favorite_addresses", [])
    existing = next((fav for fav in favs if fav["name"] == name), None)
    if not existing:
        raise not_found_exception("Adresse favorite")

    if addr.name != name and any(fav["name"] == addr.name for fav in favs):
        raise bad_request_exception(
            f"Une adresse nommee '{addr.name}' existe deja"
        )

    await db.users.update_one(
        {
            "user_id": current_user["user_id"],
            "favorite_addresses.name": name,
        },
        {
            "$set": {
                "favorite_addresses.$": addr.model_dump(),
                "updated_at": datetime.now(timezone.utc),
            }
        },
    )
    return {"message": f"Adresse '{name}' mise a jour"}


@router.delete("/me/favorite-addresses/{name}", summary="Supprimer une adresse favorite")
async def delete_favorite(
    name: str,
    current_user: dict = Depends(get_current_user),
):
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$pull": {"favorite_addresses": {"name": name}}},
    )
    return {"message": "Adresse supprimee"}


@router.get("/photo/{filename}", summary="Photo de profil (authentifié)")
async def get_profile_photo(
    filename: str,
    current_user: dict = Depends(get_current_user),
):
    """Sert une photo de profil uniquement aux utilisateurs authentifiés.
    Le nom de fichier contient un UUID non énumérable ; l'accès plus fin
    (parties prenantes d'une livraison active) peut être ajouté plus tard."""
    if "/" in filename or "\\" in filename or ".." in filename:
        raise bad_request_exception("Nom de fichier invalide")
    file_path = UPLOADS_DIR / "profiles" / filename
    if not file_path.is_file():
        raise not_found_exception("Photo")
    media_type, _ = mimetypes.guess_type(str(file_path))
    return FileResponse(str(file_path), media_type=media_type or "application/octet-stream")


@router.post("/me/avatar", summary="Uploader photo de profil")
@limiter.limit("10/minute")
async def upload_avatar(
    request: Request,
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    """Enregistre une nouvelle photo de profil."""
    content = await _read_upload_bytes(file, MAX_AVATAR_SIZE)
    ext = _validate_image_upload(file, content)

    filename = f"profile_{uuid.uuid4().hex}{ext}"
    relative_path = Path("profiles") / filename
    absolute_path = UPLOADS_DIR / relative_path
    absolute_path.parent.mkdir(parents=True, exist_ok=True)
    absolute_path.write_bytes(content)

    profile_url = f"{settings.BASE_URL}/api/users/photo/{filename}"
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {
            "profile_picture_url": profile_url,
            "profile_picture_status": "pending",
            "profile_picture_rejected_reason": None,
            "profile_picture_reviewed_by": None,
            "profile_picture_reviewed_at": None,
            "updated_at": datetime.now(timezone.utc),
        }},
    )
    return {"profile_picture_url": profile_url, "profile_picture_status": "pending"}


@router.post("/me/kyc", summary="Uploader piece d'identite (KYC)")
@limiter.limit("5/minute")
async def upload_kyc(
    request: Request,
    doc_type: Literal["id_card", "license"] = "id_card",
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    """Enregistre un document d'identite pour verification."""
    content = await _read_upload_bytes(file, MAX_KYC_SIZE)
    ext, content_type = _validate_kyc_upload(file, content)

    filename = f"kyc_{doc_type}_{uuid.uuid4().hex}{ext}"
    absolute_path = PRIVATE_KYC_DIR / filename
    absolute_path.parent.mkdir(parents=True, exist_ok=True)
    absolute_path.write_bytes(content)

    field_to_update, field_path, field_content_type = _kyc_fields(doc_type)
    doc_url = f"{settings.BASE_URL}/api/users/me/kyc/{doc_type}"
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {
            field_to_update: doc_url,
            field_path: str(absolute_path),
            field_content_type: content_type,
            "kyc_status": "pending",
            "updated_at": datetime.now(timezone.utc),
        }},
    )

    return {"kyc_status": "pending", "doc_url": doc_url, "doc_type": doc_type}


@router.get("/me/kyc/{doc_type}", summary="Telecharger sa piece d'identite (KYC)")
async def download_my_kyc(
    doc_type: Literal["id_card", "license"],
    current_user: dict = Depends(get_current_user),
):
    return await _serve_kyc_file(current_user["user_id"], doc_type, current_user)


@router.get("/{user_id}/kyc/{doc_type}", summary="Telecharger une piece KYC utilisateur")
async def download_user_kyc(
    user_id: str,
    doc_type: Literal["id_card", "license"],
    current_user: dict = Depends(get_current_user),
):
    return await _serve_kyc_file(user_id, doc_type, current_user)


@router.get("/me/stats", summary="Statistiques d'activite utilisateur")
async def get_my_stats(current_user: dict = Depends(get_current_user)):
    """Retourne des stats sur les colis envoyes/recus."""
    user_id = current_user["user_id"]
    phone_candidates = [
        candidate
        for candidate in {
            current_user.get("phone"),
            normalize_phone(current_user.get("phone")),
        }
        if candidate
    ]

    sent_count = await db.parcels.count_documents({"sender_user_id": user_id})
    received_query = (
        {"recipient_phone": {"$in": phone_candidates}}
        if phone_candidates
        else {"recipient_phone": None}
    )
    received_count = await db.parcels.count_documents(received_query)

    return {
        "parcels_sent": sent_count,
        "parcels_received": received_count,
        "total_parcels": sent_count + received_count,
        "loyalty_points": current_user.get("loyalty_points", 0),
        "loyalty_tier": current_user.get("loyalty_tier", "bronze"),
        "referrals_count": await db.users.count_documents({"referred_by": user_id}),
    }


@router.put("/{user_id}/relay-point", summary="Lier un point relais a un agent (admin)")
@limiter.limit("10/minute")
async def assign_relay_point(
    user_id: str,
    relay_id: str,
    request: Request,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    """Associe relay_point_id a l'utilisateur agent relais."""
    relay = await db.relay_points.find_one({"relay_id": relay_id})
    if not relay:
        raise not_found_exception("Point relais")
    result = await db.users.update_one(
        {"user_id": user_id},
        {"$set": {
            "relay_point_id": relay_id,
            "role": UserRole.RELAY_AGENT.value,
            "updated_at": datetime.now(timezone.utc),
        }},
    )
    if result.matched_count == 0:
        raise not_found_exception("Utilisateur")

    await _record_event(
        event_type="USER_RELAY_ASSIGNED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Agent {user_id} lie au relais {relay_id}",
        metadata={"target_user_id": user_id, "relay_id": relay_id},
    )

    return {"message": f"Agent {user_id} lie au relais {relay_id}"}


@router.get("/me/loyalty", summary="Statistiques de fidelite")
async def get_my_loyalty(current_user: dict = Depends(get_current_user)):
    """Retourne les points, le tier et l'historique de fidelite."""
    from services.user_service import compute_tier

    events = await db.loyalty_events.find(
        {"user_id": current_user["user_id"]},
        sort=[("created_at", -1)],
        limit=20,
    ).to_list(length=20)

    points = current_user.get("loyalty_points", 0)
    tier = compute_tier(points)
    next_tier_at = 200 if tier == "bronze" else 500 if tier == "silver" else None

    return {
        "points": points,
        "tier": tier,
        "next_tier_at": next_tier_at,
        "referral_code": current_user.get("referral_code", ""),
        "history": events,
    }


@router.get("/referral/{code}", response_class=HTMLResponse, include_in_schema=False)
async def referral_landing(code: str):
    referral_code = str(code or "").strip().upper()
    if not referral_code:
        raise not_found_exception("Code parrainage")

    sponsor = await db.users.find_one({"referral_code": referral_code}, {"_id": 0})
    if not sponsor:
        raise not_found_exception("Code parrainage")

    settings_doc = await get_global_app_settings()
    if not is_referral_sponsor_enabled_for_user(sponsor, settings_doc):
        raise not_found_exception("Code parrainage")

    referred_bonus_xof = get_referral_referred_bonus_xof(settings_doc)
    sponsor_name = escape(str(sponsor.get("name") or "Un utilisateur Denkma"))
    safe_code = escape(referral_code)
    app_link = f"denkma://app/referral/{quote_plus(referral_code)}"
    safe_app_link = escape(app_link)
    share_message = escape(
        build_referral_share_message(
            code=referral_code,
            referral_url=build_referral_url(
                referral_code,
                get_effective_referral_share_base_url(settings_doc),
            ),
            referred_bonus_xof=referred_bonus_xof,
            reward_rule=describe_referral_reward_rule(settings_doc),
        )
    )

    html = f"""
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Parrainage Denkma</title>
  <style>
    body {{
      margin: 0;
      font-family: Arial, sans-serif;
      background: linear-gradient(180deg, #f5f8fc 0%, #ffffff 100%);
      color: #17324d;
    }}
    .wrap {{
      max-width: 640px;
      margin: 0 auto;
      padding: 32px 20px 48px;
    }}
    .card {{
      background: #ffffff;
      border-radius: 20px;
      padding: 24px;
      box-shadow: 0 18px 48px rgba(20, 52, 91, 0.12);
      border: 1px solid #e4edf7;
    }}
    .badge {{
      display: inline-block;
      padding: 6px 12px;
      border-radius: 999px;
      background: #e9f2ff;
      color: #0d5bd7;
      font-weight: 700;
      font-size: 13px;
    }}
    h1 {{
      margin: 14px 0 10px;
      font-size: 28px;
      line-height: 1.15;
    }}
    p {{
      line-height: 1.55;
      color: #48627d;
    }}
    .code {{
      margin: 18px 0 10px;
      padding: 16px;
      border-radius: 16px;
      background: #0f2239;
      color: #ffffff;
      font-size: 26px;
      font-weight: 700;
      letter-spacing: 1px;
      text-align: center;
    }}
    .hint {{
      font-size: 13px;
      color: #6a8198;
    }}
    .actions {{
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 22px;
    }}
    button {{
      border: 0;
      border-radius: 12px;
      padding: 14px 16px;
      font-weight: 700;
      cursor: pointer;
    }}
    .primary {{
      background: #0d5bd7;
      color: #ffffff;
    }}
    .secondary {{
      background: #eef4fb;
      color: #17324d;
    }}
    .link-button {{
      display: inline-flex;
      align-items: center;
      justify-content: center;
      text-decoration: none;
    }}
    .message {{
      margin-top: 18px;
      padding: 14px;
      border-radius: 14px;
      background: #f6f9fd;
      border: 1px solid #e3ebf5;
      font-size: 14px;
      color: #36516c;
      white-space: pre-wrap;
    }}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <div class="badge">Parrainage Denkma</div>
      <h1>{sponsor_name} vous invite sur Denkma</h1>
      <p>
        Utilisez ce code pendant votre inscription pour activer le parrainage.
        {f"Un bonus filleul de {referred_bonus_xof} XOF est prevu. {escape(describe_referral_reward_rule(settings_doc))}" if referred_bonus_xof > 0 else escape(describe_referral_reward_rule(settings_doc))}
      </p>
      <div class="code" id="referral-code">{safe_code}</div>
      <div class="hint">Conservez ce code et saisissez-le dans l'ecran d'inscription Denkma.</div>
      <div class="actions">
        <a class="primary link-button" href="{safe_app_link}">Ouvrir dans l'application</a>
        <button class="primary" onclick="copyReferralCode()">Copier le code</button>
        <button class="secondary" onclick="copyReferralMessage()">Copier le message complet</button>
      </div>
      <div class="hint" style="margin-top:10px;">
        Si l'application est deja installee, le bouton ci-dessus ouvrira Denkma et pre-remplira le code.
      </div>
      <div class="message" id="share-message">{share_message}</div>
    </div>
  </div>
  <script>
    async function copyText(value) {{
      try {{
        await navigator.clipboard.writeText(value);
        alert('Copie effectuee');
      }} catch (error) {{
        alert('Copie impossible sur cet appareil');
      }}
    }}
    function copyReferralCode() {{
      copyText(document.getElementById('referral-code').innerText.trim());
    }}
    function copyReferralMessage() {{
      copyText(document.getElementById('share-message').innerText.trim());
    }}
  </script>
</body>
</html>
"""
    return HTMLResponse(content=html)


@router.post("/refer", summary="Code parrainage")
async def get_referral_info(current_user: dict = Depends(get_current_user)):
    """Retourne le code parrainage, le lien et l'etat effectif du programme."""
    return await _build_referral_payload(current_user)


class ApplyReferralRequest(BaseModel):
    referral_code: str = Field(..., min_length=3, max_length=20)


@router.post("/apply-referral", summary="Appliquer un parrain")
async def apply_referral_code(
    body: ApplyReferralRequest,
    current_user: dict = Depends(get_current_user),
):
    """Lie l'utilisateur courant a un parrain via son code."""
    code = body.referral_code.upper().strip()

    if current_user.get("referred_by"):
        raise bad_request_exception("Vous avez deja un parrain")

    settings_doc = await get_global_app_settings()
    user_role = str(current_user.get("role") or "client")
    config = get_referral_role_config(settings_doc, user_role)

    apply_metric = config["apply_metric"]
    apply_max_count = config["apply_max_count"]
    current_metric_count = await get_referral_metric_count(current_user["user_id"], apply_metric)
    if current_metric_count > apply_max_count:
        raise bad_request_exception("Le code parrainage ne peut plus etre applique pour ce compte")

    parrain = await db.users.find_one({"referral_code": code}, {"_id": 0})
    if not parrain:
        raise not_found_exception("Code parrainage invalide")

    if parrain["user_id"] == current_user["user_id"]:
        raise bad_request_exception("Action impossible")

    if not is_referral_referred_enabled_for_user(current_user, settings_doc):
        raise bad_request_exception("Le parrainage n'est pas disponible pour ce compte")
    if not is_referral_sponsor_enabled_for_user(parrain, settings_doc):
        raise bad_request_exception("Ce code parrainage n'est pas actif")

    if not await check_sponsor_referral_limit(parrain["user_id"], user_role, settings_doc):
        raise bad_request_exception("Ce parrain a atteint le nombre maximum de filleuls")

    now = datetime.now(timezone.utc)
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {
            "referred_by": parrain["user_id"],
            "referral_applied_at": now,
            "referral_source": "post_signup",
            "updated_at": now,
        }},
    )
    await _record_event(
        event_type="USER_REFERRAL_APPLIED",
        actor_id=current_user["user_id"],
        actor_role=user_role,
        notes=f"Code parrainage applique: {code}",
        metadata={
            "user_id": current_user["user_id"],
            "sponsor_user_id": parrain["user_id"],
            "referral_code": code,
            "source": "post_signup",
            "apply_metric": apply_metric,
            "apply_max_count": apply_max_count,
            "current_metric_count": current_metric_count,
        },
    )
    return {
        "message": (
            "Parrainage applique ! "
            f"{describe_referral_reward_rule(settings_doc, user_role)}"
        )
    }
