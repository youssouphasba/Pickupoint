from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status

from core.dependencies import get_current_user, require_role
from database import db
from models.common import UserRole
from models.in_app_campaign import (
    CampaignActionType,
    CampaignTargetRole,
    InAppCampaign,
    InAppCampaignCreate,
    InAppCampaignUpdate,
)

router = APIRouter(tags=["In-app Campaigns"])
require_admin = require_role(UserRole.ADMIN, UserRole.SUPERADMIN)


def _clean(document: dict) -> dict:
    document.pop("_id", None)
    return document


def _campaign_payload(campaign: InAppCampaign) -> dict:
    payload = campaign.model_dump()
    payload["target_roles"] = [role.value for role in campaign.target_roles]
    payload["action_type"] = campaign.action_type.value
    if payload.get("image_url") is not None:
        payload["image_url"] = str(payload["image_url"])
    return payload


def _allowed_view_roles(user: dict) -> set[str]:
    role = user.get("role") or UserRole.CLIENT.value
    allowed = {role}
    if role in {UserRole.DRIVER.value, UserRole.RELAY_AGENT.value}:
        allowed.add(UserRole.CLIENT.value)
    return allowed


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
    if body.end_date <= body.start_date:
        raise HTTPException(status_code=400, detail="La date de fin doit suivre la date de debut")
    _validate_action(body.action_type.value, body.action_value)
    campaign = InAppCampaign(**body.model_dump(), created_by=current_user["user_id"])
    await db.in_app_campaigns.insert_one(_campaign_payload(campaign))
    return {"campaign_id": campaign.campaign_id, "message": "Campagne creee"}


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
    if not updates:
        raise HTTPException(status_code=400, detail="Aucun champ a mettre a jour")
    if "image_url" in updates and updates["image_url"] is not None:
        updates["image_url"] = str(updates["image_url"])
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
    start_date = updates.get("start_date", existing.get("start_date"))
    end_date = updates.get("end_date", existing.get("end_date"))
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


@router.get("/campaigns/active", response_model=dict)
async def active_campaigns(
    role: Optional[str] = Query(None),
    current_user: dict = Depends(get_current_user),
):
    notification_prefs = current_user.get("notification_prefs") or {}
    if notification_prefs.get("promotions") is False:
        return {"campaigns": []}

    requested_role = (role or current_user.get("role") or UserRole.CLIENT.value).strip()
    if requested_role not in _allowed_view_roles(current_user):
        requested_role = current_user.get("role") or UserRole.CLIENT.value

    now = datetime.now(timezone.utc)
    query = {
        "is_active": True,
        "start_date": {"$lte": now},
        "end_date": {"$gte": now},
        "$or": [
            {"target_roles": CampaignTargetRole.ALL.value},
            {"target_roles": requested_role},
        ],
    }
    campaigns = await db.in_app_campaigns.find(query).sort(
        [("priority", -1), ("created_at", -1)]
    ).to_list(10)
    return {"campaigns": [_clean(c) for c in campaigns]}


@router.post("/campaigns/{campaign_id}/impression", response_model=dict)
async def mark_campaign_impression(
    campaign_id: str,
    role: Optional[str] = Query(None),
    current_user: dict = Depends(get_current_user),
):
    campaign = await db.in_app_campaigns.find_one({"campaign_id": campaign_id})
    if not campaign:
        raise HTTPException(status_code=404, detail="Campagne introuvable")
    requested_role = (role or current_user.get("role") or UserRole.CLIENT.value).strip()
    if requested_role not in _allowed_view_roles(current_user):
        requested_role = current_user.get("role") or UserRole.CLIENT.value
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
