"""
Router des notifications in-app.
Liste, badge non-lus, mark-as-read.
"""
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query

from core.dependencies import get_current_user
from core.exceptions import not_found_exception
from database import db
from models.notification import NotificationChannel

router = APIRouter()


def _serialize(notif: dict) -> dict:
    """Renvoie le document sans _id et avec les datetimes ISO."""
    out = dict(notif)
    out.pop("_id", None)
    for key in ("created_at", "sent_at", "read_at"):
        value = out.get(key)
        if isinstance(value, datetime):
            out[key] = value.isoformat()
    return out


@router.get("", summary="Liste des notifications de l'utilisateur connecte")
async def list_notifications(
    skip: int = Query(0, ge=0),
    limit: int = Query(30, ge=1, le=100),
    unread_only: bool = Query(False),
    current_user: dict = Depends(get_current_user),
):
    query: dict = {
        "user_id": current_user["user_id"],
        "channel": NotificationChannel.IN_APP.value,
    }
    if unread_only:
        query["read_at"] = None

    cursor = (
        db.notifications.find(query, {"_id": 0})
        .sort("created_at", -1)
        .skip(skip)
        .limit(limit)
    )
    notifs = [_serialize(n) for n in await cursor.to_list(length=limit)]
    total = await db.notifications.count_documents(query)
    return {"notifications": notifs, "total": total}


@router.get("/unread-count", summary="Nombre de notifications non lues")
async def unread_count(current_user: dict = Depends(get_current_user)):
    count = await db.notifications.count_documents(
        {
            "user_id": current_user["user_id"],
            "channel": NotificationChannel.IN_APP.value,
            "read_at": None,
        }
    )
    return {"unread_count": count}


@router.post("/{notif_id}/read", summary="Marquer une notification comme lue")
async def mark_as_read(
    notif_id: str,
    current_user: dict = Depends(get_current_user),
):
    result = await db.notifications.update_one(
        {
            "notif_id": notif_id,
            "user_id": current_user["user_id"],
            "read_at": None,
        },
        {"$set": {"read_at": datetime.now(timezone.utc)}},
    )
    if result.matched_count == 0:
        # Soit déjà lue, soit pas la sienne — on tolère silencieusement les
        # déjà-lues, mais on lève sur les inconnues
        existing = await db.notifications.find_one(
            {"notif_id": notif_id, "user_id": current_user["user_id"]},
            {"_id": 0, "read_at": 1},
        )
        if not existing:
            raise not_found_exception("Notification")
    return {"ok": True}


@router.post("/read-all", summary="Marquer toutes les notifications comme lues")
async def mark_all_as_read(current_user: dict = Depends(get_current_user)):
    result = await db.notifications.update_many(
        {
            "user_id": current_user["user_id"],
            "channel": NotificationChannel.IN_APP.value,
            "read_at": None,
        },
        {"$set": {"read_at": datetime.now(timezone.utc)}},
    )
    return {"ok": True, "updated": result.modified_count}
