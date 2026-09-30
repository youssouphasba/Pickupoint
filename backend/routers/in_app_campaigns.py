import os
import asyncio
import logging
import re
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from fastapi.responses import Response
from gridfs.errors import NoFile
from motor.motor_asyncio import AsyncIOMotorGridFSBucket

from core.dependencies import get_current_user, require_role
from core.exceptions import bad_request_exception
from config import settings
from database import db
from database import get_db
from models.common import UserRole
from models.in_app_campaign import (
    CampaignActionType,
    CampaignTargetRole,
    InAppCampaign,
    InAppCampaignCreate,
    InAppCampaignUpdate,
)
from services.notification_service import send_targeted_notifications
from services.campaign_targeting import (
    AUDIENCE_LABELS, CampaignAudience, CampaignTargeting, targeting_for,
    sender_activity, audience_matches, campaign_audience_matches,
    campaign_state, exposure_allowed, claim_exposure, release_exposure, utc,
)

router = APIRouter(tags=["In-app Campaigns"])
logger = logging.getLogger(__name__)
require_admin = require_role(UserRole.ADMIN, UserRole.SUPERADMIN)
MAX_CAMPAIGN_IMAGE_SIZE = 4 * 1024 * 1024
MAX_CAMPAIGN_VIDEO_SIZE = 12 * 1024 * 1024
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
VIDEO_EXTENSIONS = {".mp4", ".webm"}


def _campaign_images_bucket() -> AsyncIOMotorGridFSBucket:
    database = get_db()
    if database is None:
        raise RuntimeError("Database not connected")
    return AsyncIOMotorGridFSBucket(database, bucket_name="campaign_images")


def _clean(document: dict) -> dict:
    document.pop("_id", None)
    return document


def _campaign_payload(campaign: InAppCampaign) -> dict:
    payload = campaign.model_dump()
    payload["target_roles"] = [role.value for role in campaign.target_roles]
    payload["action_type"] = campaign.action_type.value
    payload["targeting"] = campaign.targeting.model_dump(mode="json")
    if payload.get("image_url") is not None:
        payload["image_url"] = str(payload["image_url"])
    if payload.get("video_url") is not None:
        payload["video_url"] = str(payload["video_url"])
    return payload


async def _read_upload_bytes(file: UploadFile, max_size: int) -> bytes:
    content = await file.read(max_size + 1)
    if not content:
        raise bad_request_exception("Fichier vide")
    if len(content) > max_size:
        raise bad_request_exception(f"Image trop volumineuse (max {max_size // (1024 * 1024)} Mo)")
    return content


def _guess_image_extension(content: bytes) -> Optional[str]:
    if content.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if content.startswith(b"RIFF") and content[8:12] == b"WEBP":
        return ".webp"
    return None


def _image_content_type(ext: str) -> str:
    return {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
    }[ext]


def _validate_campaign_image(file: UploadFile, content: bytes) -> tuple[str, str]:
    if not (file.content_type or "").startswith("image/"):
        raise bad_request_exception("Le fichier doit etre une image")
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext and ext not in IMAGE_EXTENSIONS:
        raise bad_request_exception("Format non supporte (.jpg, .png, .webp uniquement)")
    detected_ext = _guess_image_extension(content)
    if not detected_ext:
        raise bad_request_exception("Image invalide ou format non reconnu")
    return detected_ext, _image_content_type(detected_ext)


def _validate_campaign_video(file: UploadFile) -> tuple[str, str]:
    ext = os.path.splitext(file.filename or "")[1].lower()
    content_type = (file.content_type or "").lower()
    if ext not in VIDEO_EXTENSIONS or content_type not in {"video/mp4", "video/webm"}:
        raise bad_request_exception("Format vidéo non supporté (.mp4 ou .webm uniquement)")
    return ext, {".mp4": "video/mp4", ".webm": "video/webm"}[ext]


def _allowed_view_roles(user: dict) -> set[str]:
    role = user.get("role") or UserRole.CLIENT.value
    allowed = {role}
    if role in {UserRole.DRIVER.value, UserRole.RELAY_AGENT.value}:
        allowed.add(UserRole.CLIENT.value)
    return allowed


def _campaign_targets_user(campaign: dict, user: dict) -> bool:
    target_roles = set(
        campaign.get("target_roles") or [CampaignTargetRole.ALL.value]
    )
    return (
        CampaignTargetRole.ALL.value in target_roles
        or bool(target_roles.intersection(_allowed_view_roles(user)))
    )


async def _check_campaign_access(campaign, user):
    if not _campaign_targets_user(campaign, user) or (user.get("notification_prefs") or {}).get("promotions") is False:
        raise HTTPException(status_code=403, detail="Cette communication ne vous est pas destinée")
    now = datetime.now(timezone.utc)
    if not campaign.get("is_active") or not utc(campaign.get("start_date")) or not utc(campaign.get("end_date")) or not utc(campaign["start_date"]) <= now <= utc(campaign["end_date"]):
        raise HTTPException(status_code=410, detail="Cette communication n’est plus disponible")
    if not await campaign_audience_matches(campaign, user["user_id"], now):
        raise HTTPException(status_code=403, detail="Cette communication ne vous est pas destinée")


def _validate_action(action_type: str, action_value: str) -> None:
    value = action_value.strip()
    if action_type == CampaignActionType.INTERNAL_ROUTE.value:
        if not value.startswith("/"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La route interne doit commencer par /",
            )
        return
    if action_type == CampaignActionType.EXTERNAL_URL.value:
        if not (value.startswith("https://") or value.startswith("http://")):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Le lien externe doit commencer par http:// ou https://",
            )


async def _record_campaign_event(
    campaign_id: str,
    user_id: str,
    event_type: str,
    role: str,
) -> None:
    now = datetime.now(timezone.utc)
    result = await db.in_app_campaign_events.update_one(
        {
            "campaign_id": campaign_id,
            "user_id": user_id,
            "event_type": event_type,
        },
        {
            "$setOnInsert": {
                "campaign_id": campaign_id,
                "user_id": user_id,
                "event_type": event_type,
                "role": role,
                "created_at": now,
            }
        },
        upsert=True,
    )
    if result.upserted_id is not None:
        field = "clicks_count" if event_type == "click" else "impressions_count"
        await db.in_app_campaigns.update_one(
            {"campaign_id": campaign_id},
            {"$inc": {field: 1}, "$set": {"updated_at": now}},
        )


@router.post("/admin/campaigns", response_model=dict)
async def create_campaign(
    body: InAppCampaignCreate,
    current_user: dict = Depends(require_admin),
):
    if utc(body.end_date) <= utc(body.start_date):
        raise HTTPException(status_code=400, detail="La date de fin doit suivre la date de debut")
    _validate_action(body.action_type.value, body.action_value)
    campaign = InAppCampaign(**body.model_dump(), created_by=current_user["user_id"])
    await db.in_app_campaigns.insert_one(_campaign_payload(campaign))
    return {"campaign_id": campaign.campaign_id, "message": "Campagne creee"}


@router.get("/admin/campaigns/options", response_model=dict)
async def campaign_options(current_user: dict = Depends(require_admin)):
    return {
        "audiences": [{"value": value, "label": label} for value, label in AUDIENCE_LABELS.items()],
        "targeting_defaults": CampaignTargeting().model_dump(mode="json"),
    }


@router.get("/admin/campaigns", response_model=dict)
async def list_campaigns(
    active_only: bool = Query(False),
    current_user: dict = Depends(require_admin),
):
    query = {}
    if active_only:
        now = datetime.now(timezone.utc)
        query = {
            "is_active": True,
            "start_date": {"$lte": now},
            "end_date": {"$gte": now},
        }
    campaigns = await db.in_app_campaigns.find(query).sort(
        [("priority", -1), ("created_at", -1)]
    ).to_list(200)
    return {"campaigns": [_clean(c) for c in campaigns]}


@router.put("/admin/campaigns/{campaign_id}", response_model=dict)
async def update_campaign(
    campaign_id: str,
    body: InAppCampaignUpdate,
    current_user: dict = Depends(require_admin),
):
    updates = body.model_dump(exclude_unset=True)
    if body.targeting is not None:
        updates["targeting"] = body.targeting.model_dump(mode="json")
    if not updates:
        raise HTTPException(status_code=400, detail="Aucun champ a mettre a jour")
    if "image_url" in updates and updates["image_url"] is not None:
        updates["image_url"] = str(updates["image_url"])
    if "video_url" in updates and updates["video_url"] is not None:
        updates["video_url"] = str(updates["video_url"])
    if "target_roles" in updates and updates["target_roles"] is not None:
        updates["target_roles"] = [
            role.value if hasattr(role, "value") else role
            for role in updates["target_roles"]
        ]
    if "action_type" in updates and hasattr(updates["action_type"], "value"):
        updates["action_type"] = updates["action_type"].value
    existing = await db.in_app_campaigns.find_one({"campaign_id": campaign_id}, {"_id": 0})
    if not existing:
        raise HTTPException(status_code=404, detail="Campagne introuvable")
    start_date = utc(updates.get("start_date", existing.get("start_date")))
    end_date = utc(updates.get("end_date", existing.get("end_date")))
    if start_date and end_date and end_date <= start_date:
        raise HTTPException(status_code=400, detail="La date de fin doit suivre la date de debut")
    action_type = updates.get("action_type", existing.get("action_type"))
    action_value = updates.get("action_value", existing.get("action_value"))
    if action_type and action_value:
        _validate_action(action_type, action_value)
    updates["updated_at"] = datetime.now(timezone.utc)
    await db.in_app_campaigns.update_one({"campaign_id": campaign_id}, {"$set": updates})
    return {"message": "Campagne mise a jour"}


@router.delete("/admin/campaigns/{campaign_id}", response_model=dict)
async def delete_campaign(
    campaign_id: str,
    current_user: dict = Depends(require_admin),
):
    result = await db.in_app_campaigns.delete_one({"campaign_id": campaign_id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Campagne introuvable")
    await db.in_app_campaign_events.delete_many({"campaign_id": campaign_id})
    return {"message": "Campagne supprimee"}


@router.post("/admin/campaigns/image", response_model=dict)
async def upload_campaign_image(
    file: UploadFile = File(...),
    current_user: dict = Depends(require_admin),
):
    content = await _read_upload_bytes(file, MAX_CAMPAIGN_IMAGE_SIZE)
    ext, content_type = _validate_campaign_image(file, content)
    filename = f"campaign_{uuid.uuid4().hex}{ext}"
    await _campaign_images_bucket().upload_from_stream(
        filename,
        content,
        metadata={
            "content_type": content_type,
            "uploaded_by": current_user["user_id"],
            "created_at": datetime.now(timezone.utc),
        },
    )
    return {
        "image_url": f"{settings.BASE_URL.rstrip('/')}/api/campaigns/assets/{filename}",
        "filename": filename,
    }


@router.post("/admin/campaigns/video", response_model=dict)
async def upload_campaign_video(
    file: UploadFile = File(...),
    current_user: dict = Depends(require_admin),
):
    content = await _read_upload_bytes(file, MAX_CAMPAIGN_VIDEO_SIZE)
    ext, content_type = _validate_campaign_video(file)
    filename = f"campaign_{uuid.uuid4().hex}{ext}"
    await _campaign_images_bucket().upload_from_stream(
        filename,
        content,
        metadata={
            "content_type": content_type,
            "uploaded_by": current_user["user_id"],
            "created_at": datetime.now(timezone.utc),
        },
    )
    return {
        "video_url": f"{settings.BASE_URL.rstrip('/')}/api/campaigns/assets/{filename}",
        "filename": filename,
    }


@router.get("/campaigns/assets/{filename}")
async def get_campaign_image(filename: str):
    if "/" in filename or "\\" in filename or ".." in filename:
        raise bad_request_exception("Nom de fichier invalide")
    try:
        grid_file = await _campaign_images_bucket().open_download_stream_by_name(filename, revision=-1)
        content = await grid_file.read()
        media_type = (grid_file.metadata or {}).get("content_type") or "application/octet-stream"
        return Response(content=content, media_type=media_type)
    except NoFile:
        raise HTTPException(status_code=404, detail="Image introuvable")


@router.get("/campaigns/active", response_model=dict)
async def active_campaigns(
    role: Optional[str] = Query(None),
    placement: str = Query("home", min_length=2, max_length=60),
    current_user: dict = Depends(get_current_user),
):
    notification_prefs = current_user.get("notification_prefs") or {}
    if notification_prefs.get("promotions") is False:
        return {"campaigns": []}

    requested_role = (role or current_user.get("role") or UserRole.CLIENT.value).strip()
    if requested_role not in _allowed_view_roles(current_user):
        requested_role = current_user.get("role") or UserRole.CLIENT.value

    now = datetime.now(timezone.utc)
    normalized_placement = placement.strip().lower()
    if not re.fullmatch(r"[a-z0-9_]{2,60}", normalized_placement):
        raise HTTPException(status_code=400, detail="Emplacement invalide")
    query = {
        "is_active": True,
        "start_date": {"$lte": now},
        "end_date": {"$gte": now},
        "$and": [
            {
                "$or": [
                    {"target_roles": CampaignTargetRole.ALL.value},
                    {"target_roles": requested_role},
                ]
            },
            {
                "$or": [
                    {"placements": "all"},
                    {"placements": normalized_placement},
                    {"placements": {"$exists": False}},
                ]
            },
        ],
    }
    campaigns = await db.in_app_campaigns.find(query).sort(
        [("priority", -1), ("created_at", -1)]
    ).to_list(200)
    uid = current_user["user_id"]
    states = await campaign_state(uid, [item["campaign_id"] for item in campaigns])
    needs_activity = any(targeting_for(item).audience != CampaignAudience.ALL for item in campaigns)
    activity = (await sender_activity([uid])).get(uid, {}) if needs_activity else {}
    visible = [item for item in campaigns if
        audience_matches(targeting_for(item), activity, now)
        and (item["campaign_id"], "dismiss") not in states
        and exposure_allowed(states.get((item["campaign_id"], "impression")), targeting_for(item), now)
    ]
    return {"campaigns": [_clean(c) for c in visible[:10]]}


@router.get("/campaigns/{campaign_id}", response_model=dict)
async def get_campaign(
    campaign_id: str,
    current_user: dict = Depends(get_current_user),
):
    campaign = await db.in_app_campaigns.find_one({"campaign_id": campaign_id}, {"_id": 0})
    if not campaign:
        raise HTTPException(status_code=404, detail="Campagne introuvable")
    await _check_campaign_access(campaign, current_user)
    return {"campaign": _clean(campaign)}


@router.post("/admin/campaigns/{campaign_id}/notify", response_model=dict)
async def notify_campaign(
    campaign_id: str,
    current_user: dict = Depends(require_admin),
):
    campaign = await db.in_app_campaigns.find_one({"campaign_id": campaign_id}, {"_id": 0})
    if not campaign:
        raise HTTPException(status_code=404, detail="Campagne introuvable")
    now = datetime.now(timezone.utc)
    start_date = utc(campaign.get("start_date"))
    end_date = utc(campaign.get("end_date"))
    if (
        not campaign.get("is_active", False)
        or start_date is None
        or end_date is None
        or start_date > now
        or end_date < now
    ):
        raise bad_request_exception("Seule une campagne active peut être envoyée")
    target_roles = set(campaign.get("target_roles") or [CampaignTargetRole.ALL.value])
    query = {"is_active": True, "is_banned": {"$ne": True}, "role": {"$nin": [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]}, "notification_prefs.promotions": {"$ne": False}}
    if CampaignTargetRole.ALL.value not in target_roles and CampaignTargetRole.CLIENT.value not in target_roles:
        query["role"] = {"$in": list(target_roles)}
    users = await db.users.find(query, {"_id": 0, "user_id": 1, "role": 1}).to_list(length=100000)
    users = [user for user in users if _campaign_targets_user(campaign, user)]
    policy = targeting_for(campaign)
    activity = await sender_activity([user["user_id"] for user in users]) if policy.audience != CampaignAudience.ALL else {}
    users = [user for user in users if audience_matches(policy, activity.get(user["user_id"], {}), now)]
    totals = {"matched": len(users), "sent": 0, "in_app_sent": 0, "push_sent": 0, "push_failed": 0, "push_skipped": 0, "frequency_skipped": 0, "failed": 0}
    token = uuid.uuid4().hex
    semaphore = asyncio.Semaphore(16)

    async def send(user):
        async with semaphore:
            uid = user["user_id"]
            claimed = False
            try:
                claimed = await claim_exposure(campaign, uid, "notification", token, now)
                if not claimed:
                    totals["frequency_skipped"] += 1
                    return
                result = await send_targeted_notifications(
                    user_ids=[uid], title=campaign["title"], body=campaign["body"],
                    category="promotions", ref_type="campaign", ref_id=campaign_id,
                    metadata={"campaign_id": campaign_id, "source": "campaign_manager", "admin_user_id": current_user.get("user_id")},
                    dedupe_key=f"campaign_notification:{campaign_id}:{token}",
                )
                for key in ("sent", "in_app_sent", "push_sent", "push_failed", "push_skipped"):
                    totals[key] += result.get(key, 0)
                if not result.get("in_app_sent"):
                    await release_exposure(campaign_id, uid, "notification", token)
            except Exception:
                totals["failed"] += 1
                logger.exception("Campaign notification failed for %s", campaign_id)
                if claimed:
                    try:
                        await release_exposure(campaign_id, uid, "notification", token)
                    except Exception:
                        logger.exception("Campaign notification exposure could not be released")
    for offset in range(0, len(users), 1000):
        await asyncio.gather(*(send(user) for user in users[offset:offset + 1000]))
    return {"ok": True, "campaign_id": campaign_id, **totals}


@router.post("/campaigns/{campaign_id}/impression", response_model=dict)
async def mark_campaign_impression(
    campaign_id: str,
    role: Optional[str] = Query(None),
    count_view: bool = Query(True),
    view_id: Optional[str] = Query(None, max_length=80),
    current_user: dict = Depends(get_current_user),
):
    campaign = await db.in_app_campaigns.find_one({"campaign_id": campaign_id})
    if not campaign:
        raise HTTPException(status_code=404, detail="Campagne introuvable")
    await _check_campaign_access(campaign, current_user)
    requested_role = (role or current_user.get("role") or UserRole.CLIENT.value).strip()
    if requested_role not in _allowed_view_roles(current_user):
        requested_role = current_user.get("role") or UserRole.CLIENT.value
    if count_view:
        allowed = await claim_exposure(campaign, current_user["user_id"], "impression", view_id or uuid.uuid4().hex, datetime.now(timezone.utc))
        return {"ok": True, "allowed": allowed}
    await _record_campaign_event(
        campaign_id,
        current_user["user_id"],
        "impression",
        requested_role,
    )
    return {"ok": True}


@router.post("/campaigns/{campaign_id}/click", response_model=dict)
async def mark_campaign_click(
    campaign_id: str,
    role: Optional[str] = Query(None),
    current_user: dict = Depends(get_current_user),
):
    campaign = await db.in_app_campaigns.find_one({"campaign_id": campaign_id})
    if not campaign:
        raise HTTPException(status_code=404, detail="Campagne introuvable")
    await _check_campaign_access(campaign, current_user)
    requested_role = (role or current_user.get("role") or UserRole.CLIENT.value).strip()
    if requested_role not in _allowed_view_roles(current_user):
        requested_role = current_user.get("role") or UserRole.CLIENT.value
    await _record_campaign_event(
        campaign_id,
        current_user["user_id"],
        "click",
        requested_role,
    )
    return {"ok": True}


@router.post("/campaigns/{campaign_id}/dismiss", response_model=dict)
async def dismiss_campaign(campaign_id: str, current_user: dict = Depends(get_current_user)):
    campaign = await db.in_app_campaigns.find_one({"campaign_id": campaign_id})
    if not campaign or not _campaign_targets_user(campaign, current_user):
        raise HTTPException(status_code=404, detail="Communication introuvable")
    await db.in_app_campaign_events.update_one(
        {"campaign_id": campaign_id, "user_id": current_user["user_id"], "event_type": "dismiss"},
        {"$setOnInsert": {"created_at": datetime.now(timezone.utc)}}, upsert=True,
    )
    return {"ok": True}
