import json
import logging
import mimetypes
import os
import re
import shutil
import subprocess
import tempfile
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
SUPPORTED_OUTBOUND_AUDIO_MIME_TYPES = {
    "audio/aac",
    "audio/amr",
    "audio/mp4",
    "audio/mpeg",
    "audio/ogg",
}
TRANSCODABLE_OUTBOUND_AUDIO_MIME_TYPES = {
    "audio/webm",
    "audio/wav",
    "application/octet-stream",
}

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


def _base_mime_type(mime_type: str | None) -> str:
    return (mime_type or "").split(";", 1)[0].strip().lower()


def _outbound_audio_mime_type(mime_type: str | None) -> str:
    clean_mime = _base_mime_type(mime_type)
    if clean_mime not in SUPPORTED_OUTBOUND_AUDIO_MIME_TYPES:
        raise ValueError("Format audio non supporté par WhatsApp Cloud API.")
    return clean_mime


def _prepare_outbound_audio(content: bytes, filename: str, mime_type: str) -> tuple[bytes, str, str]:
    clean_mime = _base_mime_type(mime_type)
    if clean_mime in SUPPORTED_OUTBOUND_AUDIO_MIME_TYPES:
        return content, filename, clean_mime
    if clean_mime not in TRANSCODABLE_OUTBOUND_AUDIO_MIME_TYPES:
        raise ValueError("Format audio non supporté par WhatsApp Cloud API.")

    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise ValueError(
            "Le serveur ne peut pas convertir cet audio. Répondez en texte ou réessayez après le déploiement avec ffmpeg."
        )

    source_suffix = Path(filename or "note-vocale.webm").suffix or ".webm"
    with tempfile.TemporaryDirectory() as tmpdir:
        source = Path(tmpdir) / f"source{source_suffix}"
        target = Path(tmpdir) / "note-vocale.ogg"
        source.write_bytes(content)
        command = [
            ffmpeg,
            "-y",
            "-i",
            str(source),
            "-vn",
            "-acodec",
            "libopus",
            "-b:a",
            "32k",
            str(target),
        ]
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        if result.returncode != 0 or not target.is_file():
            logger.warning("WhatsApp support audio conversion failed: %s", result.stderr[-500:])
            raise ValueError("La conversion de la note vocale a échoué. Envoyez une réponse texte.")
        converted = target.read_bytes()

    if not converted or len(converted) > MAX_WHATSAPP_MEDIA_BYTES:
        raise ValueError("Audio WhatsApp invalide ou trop volumineux après conversion.")
    return converted, "note-vocale.ogg", "audio/ogg"


def _whatsapp_error_message(status_code: int, body: str) -> str:
    try:
        meta_error = (json.loads(body).get("error") or {})
        message = meta_error.get("message") or body
        code = str(meta_error.get("code") or "")
    except Exception:
        message = body
        code = ""

    lower_message = message.lower()
    if code == "131047" or "24 hour" in lower_message or "24-hour" in lower_message:
        return (
            "Meta a refusé l'envoi : la fenêtre WhatsApp de 24 h est fermée. "
            "Le client doit d'abord renvoyer un message, ou il faut utiliser un modèle approuvé."
        )
    return f"Meta a refusé l'envoi WhatsApp ({status_code}) : {message}"


async def _log_whatsapp_support_attempt(
    *,
    payload: dict,
    status: str,
    status_code: Optional[int] = None,
    response_body: Optional[str] = None,
    meta_message_id: Optional[str] = None,
    conversation: Optional[dict] = None,
    admin_user: Optional[dict] = None,
    error: Optional[str] = None,
) -> None:
    try:
        now = _now()
        await db.whatsapp_delivery_logs.insert_one(
            {
                "attempt_id": f"wa_support_{uuid.uuid4().hex[:16]}",
                "source": "admin_support",
                "conversation_id": conversation.get("conversation_id") if conversation else None,
                "admin_user_id": admin_user.get("user_id") if admin_user else None,
                "phone_input": conversation.get("phone") if conversation else payload.get("to"),
                "to": payload.get("to"),
                "message_type": payload.get("type"),
                "template": None,
                "status": status,
                "status_code": status_code,
                "meta_message_id": meta_message_id,
                "meta_error": response_body or error,
                "created_at": now,
                "updated_at": now,
            }
        )
    except Exception as exc:
        logger.warning("Failed to audit WhatsApp support attempt: %s", exc)


async def _post_whatsapp_message(
    payload: dict,
    *,
    conversation: Optional[dict] = None,
    admin_user: Optional[dict] = None,
) -> dict:
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
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.post(url, headers=headers, json=payload)
    except Exception as exc:
        await _log_whatsapp_support_attempt(
            payload=payload,
            status="failed",
            conversation=conversation,
            admin_user=admin_user,
            error=str(exc),
        )
        raise RuntimeError(f"Impossible de contacter Meta WhatsApp : {exc}") from exc

    if response.status_code != 200:
        await _log_whatsapp_support_attempt(
            payload=payload,
            status="failed",
            status_code=response.status_code,
            response_body=response.text,
            conversation=conversation,
            admin_user=admin_user,
        )
        raise RuntimeError(_whatsapp_error_message(response.status_code, response.text))

    data = response.json()
    whatsapp_message_id = ((data.get("messages") or [{}])[0]).get("id")
    await _log_whatsapp_support_attempt(
        payload=payload,
        status="sent",
        status_code=response.status_code,
        response_body=response.text,
        meta_message_id=whatsapp_message_id,
        conversation=conversation,
        admin_user=admin_user,
    )
    return data


async def _upload_whatsapp_media(content: bytes, filename: str, mime_type: str) -> str:
    if not settings.WHATSAPP_PHONE_NUMBER_ID or not settings.WHATSAPP_ACCESS_TOKEN:
        raise RuntimeError("WhatsApp Cloud API non configurée")
    if not content or len(content) > MAX_WHATSAPP_MEDIA_BYTES:
        raise ValueError("Audio WhatsApp invalide ou trop volumineux")

    clean_mime_type = _outbound_audio_mime_type(mime_type)
    headers = {"Authorization": f"Bearer {settings.WHATSAPP_ACCESS_TOKEN}"}
    url = (
        f"https://graph.facebook.com/{settings.WHATSAPP_API_VERSION}/"
        f"{settings.WHATSAPP_PHONE_NUMBER_ID}/media"
    )
    async with httpx.AsyncClient(timeout=30) as client:
        response = await client.post(
            url,
            headers=headers,
            data={"messaging_product": "whatsapp", "type": clean_mime_type},
            files={"file": (filename, content, clean_mime_type)},
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


async def ensure_whatsapp_support_media_file(filename: str) -> tuple[Path, str] | None:
    path = (PRIVATE_WHATSAPP_DIR / filename).resolve()
    base = PRIVATE_WHATSAPP_DIR.resolve()
    if base in path.parents and path.is_file():
        media_type = mimetypes.guess_type(str(path))[0] or "application/octet-stream"
        return path, media_type

    escaped_filename = re.escape(filename)
    message = await db.whatsapp_support_messages.find_one(
        {
            "$or": [
                {"media.download_url": {"$regex": escaped_filename}},
                {"media.storage_path": {"$regex": escaped_filename}},
            ]
        },
        {"_id": 0, "media": 1},
    )
    media_id = ((message or {}).get("media") or {}).get("media_id")
    restored = await _download_whatsapp_media(media_id)
    if not restored:
        return None

    await db.whatsapp_support_messages.update_many(
        {"media.media_id": media_id},
        {"$set": {"media": restored}},
    )
    await db.whatsapp_support_conversations.update_many(
        {"last_media.media_id": media_id},
        {"$set": {"last_media": restored}},
    )

    restored_path = Path(restored["storage_path"]).resolve()
    if base not in restored_path.parents or not restored_path.is_file():
        return None
    media_type = restored.get("mime_type") or mimetypes.guess_type(str(restored_path))[0] or "application/octet-stream"
    return restored_path, media_type


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
    response = await _post_whatsapp_message(payload, conversation=conversation, admin_user=admin_user)
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
    prepared_content, prepared_filename, clean_mime_type = _prepare_outbound_audio(
        content,
        filename,
        mime_type,
    )
    media_id = await _upload_whatsapp_media(prepared_content, prepared_filename, clean_mime_type)
    payload = {
        "messaging_product": "whatsapp",
        "to": conversation["phone"].lstrip("+"),
        "type": "audio",
        "audio": {"id": media_id},
    }
    response = await _post_whatsapp_message(payload, conversation=conversation, admin_user=admin_user)
    whatsapp_message_id = ((response.get("messages") or [{}])[0]).get("id")

    PRIVATE_WHATSAPP_DIR.mkdir(parents=True, exist_ok=True)
    ext = _safe_media_extension(clean_mime_type)
    stored_filename = f"out_{media_id}_{uuid.uuid4().hex[:10]}{ext}"
    path = PRIVATE_WHATSAPP_DIR / stored_filename
    path.write_bytes(prepared_content)

    media = {
        "media_id": media_id,
        "mime_type": clean_mime_type,
        "file_size": len(prepared_content),
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
