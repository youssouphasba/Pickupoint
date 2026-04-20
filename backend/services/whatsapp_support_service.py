import logging
import mimetypes
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import httpx

from config import UPLOADS_DIR, settings
from database import db
from models.common import ParcelStatus

logger = logging.getLogger(__name__)

TRACKING_CODE_RE = re.compile(r"\b(?:PKP|DMK|DENKMA)[-_]?[A-Z0-9][A-Z0-9\-_]{4,}\b", re.IGNORECASE)
PRIVATE_WHATSAPP_DIR = UPLOADS_DIR.parent / "private_uploads" / "whatsapp"
MAX_WHATSAPP_MEDIA_BYTES = 16 * 1024 * 1024

ACTIVE_STATUSES = {
    ParcelStatus.CREATED.value,
    ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value,
    ParcelStatus.IN_TRANSIT.value,
    ParcelStatus.AT_DESTINATION_RELAY.value,
    ParcelStatus.AVAILABLE_AT_RELAY.value,
    ParcelStatus.OUT_FOR_DELIVERY.value,
    ParcelStatus.DELIVERY_FAILED.value,
    ParcelStatus.REDIRECTED_TO_RELAY.value,
    ParcelStatus.SUSPENDED.value,
    ParcelStatus.DISPUTED.value,
    ParcelStatus.INCIDENT_REPORTED.value,
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def normalize_whatsapp_phone(phone: str | None) -> str:
    digits = re.sub(r"\D", "", phone or "")
    return f"+{digits}" if digits else ""


def extract_tracking_code(text: str | None) -> Optional[str]:
    match = TRACKING_CODE_RE.search(text or "")
    if not match:
        return None
    return match.group(0).replace(" ", "").upper()


def _conversation_id(phone: str) -> str:
    return f"wa_{re.sub(r'\\D', '', phone)}"


def _safe_media_extension(mime_type: str | None) -> str:
    if mime_type == "audio/ogg":
        return ".ogg"
    if mime_type == "audio/mpeg":
        return ".mp3"
    if mime_type == "audio/aac":
        return ".aac"
    if mime_type == "audio/mp4":
        return ".m4a"
    guessed = mimetypes.guess_extension(mime_type or "")
    return guessed if guessed in {".ogg", ".mp3", ".aac", ".m4a", ".opus", ".wav"} else ".bin"


async def _post_whatsapp_message(payload: dict) -> dict:
    if not settings.WHATSAPP_PHONE_NUMBER_ID or not settings.WHATSAPP_ACCESS_TOKEN:
        raise RuntimeError("WhatsApp Cloud API non configurée")

    headers = {
        "Authorization": f"Bearer {settings.WHATSAPP_ACCESS_TOKEN}",
        "Content-Type": "application/json",
    }
    url = (
        f"https://graph.facebook.com/{settings.WHATSAPP_API_VERSION}/"
        f"{settings.WHATSAPP_PHONE_NUMBER_ID}/messages"
    )
    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(url, headers=headers, json=payload)
    if response.status_code != 200:
        raise RuntimeError(f"WhatsApp API error {response.status_code}: {response.text}")
    return response.json()


async def _upload_whatsapp_media(content: bytes, filename: str, mime_type: str) -> str:
    if not settings.WHATSAPP_PHONE_NUMBER_ID or not settings.WHATSAPP_ACCESS_TOKEN:
        raise RuntimeError("WhatsApp Cloud API non configurée")
    if not content or len(content) > MAX_WHATSAPP_MEDIA_BYTES:
        raise ValueError("Audio WhatsApp invalide ou trop volumineux")

    headers = {"Authorization": f"Bearer {settings.WHATSAPP_ACCESS_TOKEN}"}
    url = (
        f"https://graph.facebook.com/{settings.WHATSAPP_API_VERSION}/"
        f"{settings.WHATSAPP_PHONE_NUMBER_ID}/media"
    )
    async with httpx.AsyncClient(timeout=30) as client:
        response = await client.post(
            url,
            headers=headers,
            data={"messaging_product": "whatsapp", "type": mime_type},
            files={"file": (filename, content, mime_type)},
        )
    if response.status_code != 200:
        raise RuntimeError(f"WhatsApp media upload error {response.status_code}: {response.text}")
    media_id = response.json().get("id")
    if not media_id:
        raise RuntimeError("Meta n'a pas retourné de media_id")
    return media_id


async def _store_outbound_message(
    conversation: dict,
    *,
    admin_user: dict,
    text: str,
    message_type: str,
    whatsapp_message_id: Optional[str],
    media: Optional[dict] = None,
) -> dict:
    now = _now()
    message_doc = {
        "message_id": f"wmsg_{uuid.uuid4().hex[:16]}",
        "conversation_id": conversation["conversation_id"],
        "whatsapp_message_id": whatsapp_message_id,
        "direction": "outbound",
        "phone": conversation["phone"],
        "message_type": message_type,
        "text": text,
        "media": media,
        "admin_user_id": admin_user.get("user_id"),
        "admin_name": admin_user.get("name") or admin_user.get("email"),
        "matched_user_id": conversation.get("matched_user_id"),
        "matched_parcel_id": conversation.get("matched_parcel_id"),
        "matched_tracking_code": (conversation.get("matched_parcel") or {}).get("tracking_code"),
        "created_at": now,
    }
    await db.whatsapp_support_messages.insert_one(message_doc)
    await db.whatsapp_support_conversations.update_one(
        {"conversation_id": conversation["conversation_id"]},
        {"$set": {
            "last_message_text": text,
            "last_message_at": now,
            "last_outbound_at": now,
            "last_media": media,
            "status": "pending",
            "updated_at": now,
        }},
    )
    return message_doc


async def _download_whatsapp_media(media_id: str | None) -> dict | None:
    if not media_id or not settings.WHATSAPP_ACCESS_TOKEN:
        return None

    headers = {"Authorization": f"Bearer {settings.WHATSAPP_ACCESS_TOKEN}"}
    base = f"https://graph.facebook.com/{settings.WHATSAPP_API_VERSION}"

    async with httpx.AsyncClient(timeout=20) as client:
        meta_response = await client.get(
            f"{base}/{media_id}",
            params={"fields": "id,mime_type,sha256,file_size,url"},
            headers=headers,
        )
        if meta_response.status_code != 200:
            logger.warning("WhatsApp media metadata error %s: %s", meta_response.status_code, meta_response.text)
            return None

        meta = meta_response.json()
        file_size = int(meta.get("file_size") or 0)
        if file_size and file_size > MAX_WHATSAPP_MEDIA_BYTES:
            logger.warning("WhatsApp media ignored: %s bytes > limit", file_size)
            return None

        media_url = meta.get("url")
        if not media_url:
            return None

        media_response = await client.get(media_url, headers=headers)
        if media_response.status_code != 200:
            logger.warning("WhatsApp media download error %s", media_response.status_code)
            return None

    content = media_response.content
    if not content or len(content) > MAX_WHATSAPP_MEDIA_BYTES:
        return None

    mime_type = meta.get("mime_type") or media_response.headers.get("content-type")
    ext = _safe_media_extension(mime_type)
    PRIVATE_WHATSAPP_DIR.mkdir(parents=True, exist_ok=True)
    filename = f"{media_id}_{uuid.uuid4().hex[:10]}{ext}"
    path = PRIVATE_WHATSAPP_DIR / filename
    path.write_bytes(content)

    return {
        "media_id": media_id,
        "mime_type": mime_type,
        "sha256": meta.get("sha256"),
        "file_size": len(content),
        "storage_path": str(path),
        "download_url": f"{settings.BASE_URL}/api/admin/support/whatsapp/media/{filename}",
    }


async def _find_related_user(phone: str) -> dict | None:
    return await db.users.find_one(
        {"phone": phone},
        {
            "_id": 0,
            "user_id": 1,
            "name": 1,
            "phone": 1,
            "email": 1,
            "role": 1,
            "profile_picture_url": 1,
            "is_active": 1,
            "is_banned": 1,
            "kyc_status": 1,
            "relay_point_id": 1,
        },
    )


async def _find_related_parcels(phone: str, tracking_code: Optional[str]) -> tuple[list[dict], dict | None]:
    projection = {
        "_id": 0,
        "parcel_id": 1,
        "tracking_code": 1,
        "status": 1,
        "sender_user_id": 1,
        "sender_phone": 1,
        "sender_name": 1,
        "recipient_phone": 1,
        "recipient_name": 1,
        "delivery_mode": 1,
        "origin_relay_id": 1,
        "destination_relay_id": 1,
        "assigned_driver_id": 1,
        "payment_status": 1,
        "created_at": 1,
        "updated_at": 1,
    }

    if tracking_code:
        parcel = await db.parcels.find_one({"tracking_code": tracking_code}, projection)
        return ([parcel] if parcel else []), parcel

    user = await db.users.find_one({"phone": phone}, {"_id": 0, "user_id": 1})
    query: dict[str, Any] = {"$or": [{"recipient_phone": phone}, {"sender_phone": phone}]}
    if user:
        query["$or"].append({"sender_user_id": user["user_id"]})
        query["$or"].append({"recipient_user_id": user["user_id"]})

    cursor = db.parcels.find(query, projection).sort("updated_at", -1).limit(10)
    parcels = await cursor.to_list(length=10)
    active = next((parcel for parcel in parcels if parcel.get("status") in ACTIVE_STATUSES), None)
    return parcels, active or (parcels[0] if parcels else None)


async def record_whatsapp_inbound_message(value: dict, message: dict) -> dict:
    """Stocke un message entrant WhatsApp et associe client/colis si possible."""
    phone = normalize_whatsapp_phone(message.get("from"))
    if not phone:
        raise ValueError("WhatsApp sender phone missing")

    text = ""
    msg_type = message.get("type")
    if msg_type == "text":
        text = ((message.get("text") or {}).get("body") or "").strip()
    elif msg_type == "audio":
        text = "[note vocale]"
    elif msg_type:
        text = f"[{msg_type}]"

    media = None
    if msg_type == "audio":
        audio_payload = message.get("audio") or {}
        media = await _download_whatsapp_media(audio_payload.get("id"))

    tracking_code = extract_tracking_code(text)
    user = await _find_related_user(phone)
    parcels, primary_parcel = await _find_related_parcels(phone, tracking_code)

    now = _now()
    conversation_id = _conversation_id(phone)
    message_doc = {
        "message_id": f"wmsg_{uuid.uuid4().hex[:16]}",
        "conversation_id": conversation_id,
        "whatsapp_message_id": message.get("id"),
        "direction": "inbound",
        "phone": phone,
        "message_type": msg_type or "unknown",
        "text": text,
        "media": media,
        "raw_message": message,
        "matched_user_id": user.get("user_id") if user else None,
        "matched_parcel_id": primary_parcel.get("parcel_id") if primary_parcel else None,
        "matched_tracking_code": primary_parcel.get("tracking_code") if primary_parcel else tracking_code,
        "created_at": now,
    }

    conversation_update = {
        "conversation_id": conversation_id,
        "phone": phone,
        "source": "whatsapp",
        "matched_user": user,
        "matched_user_id": user.get("user_id") if user else None,
        "matched_parcel": primary_parcel,
        "matched_parcel_id": primary_parcel.get("parcel_id") if primary_parcel else None,
        "related_parcels": parcels,
        "last_message_text": text,
        "last_media": media,
        "last_message_at": now,
        "last_inbound_at": now,
        "status": "open",
        "updated_at": now,
    }

    await db.whatsapp_support_messages.update_one(
        {"whatsapp_message_id": message.get("id")},
        {"$setOnInsert": message_doc},
        upsert=True,
    )
    await db.whatsapp_support_conversations.update_one(
        {"conversation_id": conversation_id},
        {"$set": conversation_update, "$setOnInsert": {"created_at": now}},
        upsert=True,
    )

    logger.info(
        "WhatsApp support message: phone=%s user=%s parcel=%s type=%s",
        phone,
        message_doc["matched_user_id"],
        message_doc["matched_parcel_id"],
        msg_type,
    )
    return message_doc


def serialize_support_doc(doc: dict | None) -> dict | None:
    if not doc:
        return None
    result = {k: v for k, v in doc.items() if k != "_id"}
    return result


async def send_support_text_reply(conversation: dict, text: str, admin_user: dict) -> dict:
    clean_text = text.strip()
    if not clean_text:
        raise ValueError("Message vide")
    payload = {
        "messaging_product": "whatsapp",
        "to": conversation["phone"].lstrip("+"),
        "type": "text",
        "text": {"body": clean_text},
    }
    response = await _post_whatsapp_message(payload)
    whatsapp_message_id = ((response.get("messages") or [{}])[0]).get("id")
    return await _store_outbound_message(
        conversation,
        admin_user=admin_user,
        text=clean_text,
        message_type="text",
        whatsapp_message_id=whatsapp_message_id,
    )


async def send_support_audio_reply(
    conversation: dict,
    *,
    content: bytes,
    filename: str,
    mime_type: str,
    admin_user: dict,
) -> dict:
    media_id = await _upload_whatsapp_media(content, filename, mime_type)
    payload = {
        "messaging_product": "whatsapp",
        "to": conversation["phone"].lstrip("+"),
        "type": "audio",
        "audio": {"id": media_id},
    }
    response = await _post_whatsapp_message(payload)
    whatsapp_message_id = ((response.get("messages") or [{}])[0]).get("id")

    PRIVATE_WHATSAPP_DIR.mkdir(parents=True, exist_ok=True)
    ext = _safe_media_extension(mime_type)
    stored_filename = f"out_{media_id}_{uuid.uuid4().hex[:10]}{ext}"
    path = PRIVATE_WHATSAPP_DIR / stored_filename
    path.write_bytes(content)

    media = {
        "media_id": media_id,
        "mime_type": mime_type,
        "file_size": len(content),
        "storage_path": str(path),
        "download_url": f"{settings.BASE_URL}/api/admin/support/whatsapp/media/{stored_filename}",
    }
    return await _store_outbound_message(
        conversation,
        admin_user=admin_user,
        text="[note vocale envoyée]",
        message_type="audio",
        whatsapp_message_id=whatsapp_message_id,
        media=media,
    )
