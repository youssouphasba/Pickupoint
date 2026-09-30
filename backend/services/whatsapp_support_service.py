import json
import logging
import mimetypes
import os
import re
import shutil
import subprocess
import tempfile
import uuid
import asyncio
import hashlib
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

import httpx
from bson import ObjectId
from bson.errors import InvalidId
from gridfs.errors import NoFile
from motor.motor_asyncio import AsyncIOMotorGridFSBucket

from config import UPLOADS_DIR, settings
from database import db, get_db, get_client
from pymongo import ReturnDocument
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
    return "wa_" + re.sub(r"\D", "", phone)


def _aware(value):
    if isinstance(value, str):
        value = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


async def find_support_conversation(conversation_id):
    conversation = await db.whatsapp_support_conversations.find_one({"conversation_id": conversation_id}, {"_id": 0})
    if not conversation and str(conversation_id).startswith("wa_"):
        phone = normalize_whatsapp_phone(str(conversation_id)[3:])
        conversation = await db.whatsapp_support_conversations.find_one({"phone": phone}, {"_id": 0})
    return conversation


class WhatsAppSendUncertain(RuntimeError):
    pass


def _safe_media_extension(mime_type: str | None) -> str:
    supported = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "application/pdf": ".pdf"}
    if mime_type in supported:
        return supported[mime_type]
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


def _whatsapp_media_bucket() -> AsyncIOMotorGridFSBucket:
    database = get_db()
    if database is None:
        raise RuntimeError("Database not connected")
    return AsyncIOMotorGridFSBucket(database, bucket_name="whatsapp_support_media")


async def _store_whatsapp_media_blob(
    *,
    filename: str,
    content: bytes,
    mime_type: str | None,
    media_id: str | None,
    direction: str,
) -> str | None:
    if not content:
        return None
    file_id = await _whatsapp_media_bucket().upload_from_stream(
        filename,
        content,
        metadata={
            "content_type": mime_type or "application/octet-stream",
            "media_id": media_id,
            "direction": direction,
            "created_at": _now(),
        },
    )
    return str(file_id)


async def _restore_whatsapp_media_blob(file_id: str | None, filename: str) -> tuple[Path, str] | None:
    if not file_id:
        return None
    try:
        object_id = ObjectId(file_id)
    except (InvalidId, TypeError):
        return None

    try:
        stream = await _whatsapp_media_bucket().open_download_stream(object_id)
        content = await stream.read()
    except NoFile:
        return None

    if not content or len(content) > MAX_WHATSAPP_MEDIA_BYTES:
        return None

    PRIVATE_WHATSAPP_DIR.mkdir(parents=True, exist_ok=True)
    path = (PRIVATE_WHATSAPP_DIR / filename).resolve()
    base = PRIVATE_WHATSAPP_DIR.resolve()
    if base not in path.parents:
        return None
    path.write_bytes(content)
    media_type = (stream.metadata or {}).get("content_type") or mimetypes.guess_type(str(path))[0] or "application/octet-stream"
    return path, media_type


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
        template_name = (
            (payload.get("template") or {}).get("name")
            if isinstance(payload.get("template"), dict)
            else None
        )
        await db.whatsapp_delivery_logs.insert_one(
            {
                "attempt_id": f"wa_support_{uuid.uuid4().hex[:16]}",
                "source": "admin_support",
                "conversation_id": conversation.get("conversation_id") if conversation else None,
                "admin_user_id": admin_user.get("user_id") if admin_user else None,
                "phone_input": conversation.get("phone") if conversation else payload.get("to"),
                "to": payload.get("to"),
                "message_type": payload.get("type"),
                "template": template_name,
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
        raise WhatsAppSendUncertain("Envoi incertain : Meta n’a pas confirmé la réponse. Ne la renvoyez pas avant vérification.") from exc

    if response.status_code != 200:
        await _log_whatsapp_support_attempt(
            payload=payload,
            status="failed",
            status_code=response.status_code,
            response_body=response.text,
            conversation=conversation,
            admin_user=admin_user,
        )
        error_type = WhatsAppSendUncertain if response.status_code >= 500 else RuntimeError
        raise error_type(_whatsapp_error_message(response.status_code, response.text))

    try:
        data = response.json()
    except ValueError as exc:
        raise WhatsAppSendUncertain("Confirmation Meta illisible : vérifiez l’envoi avant de réessayer") from exc
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


async def _send_support_message(conversation, *, admin_user, text, message_type, payload, media=None, request_id=None):
    if not normalize_whatsapp_phone(conversation.get("phone")) or conversation.get("anonymized_at"):
        raise ValueError("Ce contact est anonymisé : aucune réponse WhatsApp ne peut être envoyée")
    request_id = request_id or uuid.uuid4().hex
    if not re.fullmatch(r"[A-Za-z0-9_-]{8,80}", request_id):
        raise ValueError("Identifiant d’envoi invalide")
    identity = {"conversation": conversation["conversation_id"], "text": text, "type": message_type,
                "media_hash": (media or {}).get("content_hash"), "template": payload.get("template")}
    fingerprint = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    now = _now()
    message_id = "wmsg_" + request_id
    doc = {"message_id": message_id, "conversation_id": conversation["conversation_id"],
           "direction": "outbound", "phone": conversation["phone"], "text": text, "message_type": message_type,
           "media": media, "delivery_status": "sending", "fingerprint": fingerprint,
           "admin_user_id": admin_user.get("user_id"), "admin_name": admin_user.get("name") or admin_user.get("email"),
           "matched_user_id": conversation.get("matched_user_id"), "matched_parcel_id": conversation.get("matched_parcel_id"),
           "matched_tracking_code": (conversation.get("matched_parcel") or {}).get("tracking_code"),
           "created_at": now, "updated_at": now}
    inserted = await db.whatsapp_support_messages.update_one({"message_id": message_id}, {"$setOnInsert": doc}, upsert=True)
    if not inserted.upserted_id:
        previous = await db.whatsapp_support_messages.find_one({"message_id": message_id}, {"_id": 0})
        if previous.get("fingerprint") != fingerprint:
            raise ValueError("Cet identifiant appartient à une autre réponse")
        if previous.get("delivery_status") != "failed":
            return previous
        claimed = await db.whatsapp_support_messages.update_one(
            {"message_id": message_id, "delivery_status": "failed"}, {"$set": {"delivery_status": "sending", "updated_at": now}})
        if not claimed.modified_count:
            return await db.whatsapp_support_messages.find_one({"message_id": message_id}, {"_id": 0})
    try:
        response = await _post_whatsapp_message(payload, conversation=conversation, admin_user=admin_user)
        whatsapp_id = ((response.get("messages") or [{}])[0]).get("id")
        if not whatsapp_id:
            raise WhatsAppSendUncertain("Meta n’a pas confirmé l’identifiant de cette réponse")
    except Exception as error:
        state = "uncertain" if isinstance(error, WhatsAppSendUncertain) else "failed"
        await db.whatsapp_support_messages.update_one({"message_id": message_id},
            {"$set": {"delivery_status": state, "send_error": str(error), "updated_at": _now()}})
        raise
    await db.whatsapp_support_messages.update_one({"message_id": message_id},
        {"$set": {"whatsapp_message_id": whatsapp_id, "delivery_status": "accepted", "send_error": None, "updated_at": _now()}})
    conversation_id = conversation["conversation_id"]
    await db.whatsapp_support_conversations.update_one(
        {"conversation_id": conversation_id, "$or": [{"last_message_at": {"$lte": now}}, {"last_message_at": {"$exists": False}}]},
        {"$set": {"last_message_text": text, "last_message_at": now, "last_media": media, "updated_at": _now()}})
    await db.whatsapp_support_conversations.update_one(
        {"conversation_id": conversation_id, "last_inbound_at": conversation.get("last_inbound_at"),
         "last_inbound_message_id": conversation.get("last_inbound_message_id"),
         "status_changed_at": conversation.get("status_changed_at")},
        {"$set": {"status": "pending", "unanswered_since": None, "updated_at": _now()}, "$max": {"last_outbound_at": now}})
    return await db.whatsapp_support_messages.find_one({"message_id": message_id}, {"_id": 0})


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

        content = bytearray()
        async with client.stream("GET", media_url, headers=headers) as media_response:
            if media_response.status_code != 200:
                return None
            async for chunk in media_response.aiter_bytes():
                content.extend(chunk)
                if len(content) > MAX_WHATSAPP_MEDIA_BYTES:
                    return None
            response_mime_type = media_response.headers.get("content-type")

    content = bytes(content)
    if not content or len(content) > MAX_WHATSAPP_MEDIA_BYTES:
        return None

    mime_type = meta.get("mime_type") or response_mime_type
    ext = _safe_media_extension(mime_type)
    PRIVATE_WHATSAPP_DIR.mkdir(parents=True, exist_ok=True)
    filename = f"in_{uuid.uuid4().hex}{ext}"
    path = PRIVATE_WHATSAPP_DIR / filename
    path.write_bytes(content)
    file_id = await _store_whatsapp_media_blob(
        filename=filename,
        content=content,
        mime_type=mime_type,
        media_id=media_id,
        direction="inbound",
    )

    return {
        "media_id": media_id,
        "mime_type": mime_type,
        "sha256": meta.get("sha256"),
        "file_size": len(content),
        "storage_path": str(path),
        "file_id": file_id,
        "download_url": f"{settings.BASE_URL}/api/admin/support/whatsapp/media/{filename}",
    }


async def _hydrate_support_message_media(message):
    previous = message.get("media") or {}
    downloaded = await _download_whatsapp_media(previous.get("media_id"))
    if not downloaded:
        raise RuntimeError("Média WhatsApp indisponible pour le moment")
    media = {**downloaded, "download_url": previous.get("download_url") or downloaded["download_url"],
             "filename": previous.get("filename") or Path(downloaded["storage_path"]).name,
             "pending_download": False}
    await db.whatsapp_support_messages.update_one(
        {"message_id": message["message_id"]}, {"$set": {"media": media}})
    await db.whatsapp_support_conversations.update_many(
        {"last_media.media_id": media["media_id"]}, {"$set": {"last_media": media}})
    return Path(media["storage_path"]), media.get("mime_type") or "application/octet-stream"


async def hydrate_pending_support_media():
    for _ in range(10):
        now = _now()
        message = await db.whatsapp_support_messages.find_one_and_update(
            {"media.pending_download": True,
             "$and": [{"$or": [{"media.retry_at": {"$exists": False}}, {"media.retry_at": {"$lte": now}}]},
                      {"$or": [{"media.lease_until": {"$exists": False}}, {"media.lease_until": {"$lte": now}}]}]},
            {"$set": {"media.lease_until": now + timedelta(minutes=2)}},
            return_document=ReturnDocument.AFTER)
        if not message:
            break
        try:
            await _hydrate_support_message_media(message)
        except Exception:
            attempts = int((message.get("media") or {}).get("attempts") or 0) + 1
            await db.whatsapp_support_messages.update_one(
                {"message_id": message["message_id"]},
                {"$set": {"media.attempts": attempts,
                          "media.retry_at": now + timedelta(minutes=min(60, 2 ** min(attempts, 6))),
                          "media.download_error": "Média indisponible, nouvelle tentative prévue"},
                 "$unset": {"media.lease_until": ""}})
            logger.warning("Support media download deferred for %s", message["message_id"])


async def ensure_whatsapp_support_media_file(filename: str) -> tuple[Path, str] | None:
    base = PRIVATE_WHATSAPP_DIR.resolve()
    path = (base / filename).resolve()
    if base not in path.parents:
        return None
    message = await db.whatsapp_support_messages.find_one(
        {"$or": [{"media.download_url": {"$regex": "/" + re.escape(filename) + "$"}},
                 {"media.storage_path": {"$regex": re.escape(filename) + "$"}}]}, {"_id": 0})
    if not message:
        return None
    media = message.get("media") or {}
    if path.is_file():
        return path, media.get("mime_type") or "application/octet-stream"
    stored_path = Path(media.get("storage_path") or path).resolve()
    if base in stored_path.parents and stored_path.is_file():
        return stored_path, media.get("mime_type") or "application/octet-stream"
    restored = await _restore_whatsapp_media_blob(media.get("file_id"), filename)
    if restored:
        return restored
    try:
        return await _hydrate_support_message_media(message)
    except Exception:
        return None


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


async def _find_user_by_id(user_id: str | None) -> dict | None:
    if not user_id:
        return None
    return await db.users.find_one(
        {"user_id": user_id},
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


async def ensure_support_conversation_for_contact(
    *,
    phone: str | None = None,
    user_id: str | None = None,
) -> dict:
    user = await _find_user_by_id(user_id)
    normalized_phone = normalize_whatsapp_phone(phone or (user or {}).get("phone"))
    if not normalized_phone:
        raise ValueError("Numéro WhatsApp requis")
    if not user:
        user = await _find_related_user(normalized_phone)

    parcels, primary_parcel = await _find_related_parcels(normalized_phone, None)
    now = _now()
    existing = await db.whatsapp_support_conversations.find_one({"phone": normalized_phone}, {"_id": 0})
    conversation_id = (existing or {}).get("conversation_id") or _conversation_id(normalized_phone)
    update = {
        "conversation_id": conversation_id,
        "phone": normalized_phone,
        "source": "whatsapp",
        "matched_user": user,
        "matched_user_id": user.get("user_id") if user else None,
        "matched_parcel": primary_parcel,
        "matched_parcel_id": primary_parcel.get("parcel_id") if primary_parcel else None,
        "related_parcels": parcels,
        "updated_at": now,
    }
    await db.whatsapp_support_conversations.update_one(
        {"conversation_id": conversation_id},
        {
            "$set": update,
            "$setOnInsert": {
                "status": "pending",
                "created_at": now,
                "last_message_text": "Conversation support démarrée par l'admin.",
                "last_message_at": now,
            },
        },
        upsert=True,
    )
    conversation = await db.whatsapp_support_conversations.find_one(
        {"conversation_id": conversation_id},
        {"_id": 0},
    )
    if not conversation:
        raise RuntimeError("Conversation WhatsApp introuvable après création")
    return conversation


async def start_support_template_conversation(
    *,
    phone: str | None = None,
    user_id: str | None = None,
    admin_user: dict,
    request_id=None,
) -> dict:
    conversation = await ensure_support_conversation_for_contact(phone=phone, user_id=user_id)
    message = await send_support_reopen_template(conversation, admin_user, request_id)
    refreshed = await db.whatsapp_support_conversations.find_one(
        {"conversation_id": conversation["conversation_id"]},
        {"_id": 0},
    )
    return {
        "conversation": serialize_support_doc(refreshed or conversation),
        "message": serialize_support_doc(message),
    }


async def record_whatsapp_inbound_message(value: dict, message: dict) -> dict:
    phone = normalize_whatsapp_phone(message.get("from"))
    if not phone or not message.get("id"):
        raise ValueError("Identité du message WhatsApp manquante")
    existing = await db.whatsapp_support_messages.find_one({"whatsapp_message_id": message["id"]}, {"_id": 0})
    if existing:
        return existing
    now = _now()
    try:
        sent_at = datetime.fromtimestamp(int(message["timestamp"]), timezone.utc)
    except (ValueError, TypeError, KeyError, OverflowError):
        raise ValueError("Date du message WhatsApp invalide")
    sent_at = min(sent_at, now)
    msg_type = message.get("type") or "unknown"
    content = message.get(msg_type) or {}
    text = str(content.get("body") or content.get("caption") or "").strip()
    if not text:
        text = {"audio": "[note vocale]", "image": "[photo]", "document": "[document]"}.get(msg_type, f"[{msg_type}]")
    media = None
    if msg_type in {"audio", "image", "document"} and content.get("id"):
        filename = "in_" + uuid.uuid4().hex + _safe_media_extension(content.get("mime_type"))
        media = {"media_id": content["id"], "mime_type": content.get("mime_type"),
                 "filename": Path(content.get("filename") or filename).name,
                 "download_url": f"{settings.BASE_URL}/api/admin/support/whatsapp/media/{filename}",
                 "pending_download": True}
    user = await _find_related_user(phone)
    tracking_code = extract_tracking_code(text)
    parcels, primary_parcel = await _find_related_parcels(phone, tracking_code)
    async def save(session):
        duplicate = await db.whatsapp_support_messages.find_one({"whatsapp_message_id": message["id"]}, {"_id": 0}, session=session)
        if duplicate:
            return duplicate
        conversation = await db.whatsapp_support_conversations.find_one({"phone": phone}, {"_id": 0}, session=session)
        conversation_id = (conversation or {}).get("conversation_id") or _conversation_id(phone)
        doc = {"message_id": f"wmsg_{uuid.uuid4().hex}", "conversation_id": conversation_id,
               "whatsapp_message_id": message["id"], "direction": "inbound", "phone": phone,
               "message_type": msg_type, "text": text, "media": media, "raw_message": message,
               "matched_user_id": (user or {}).get("user_id"), "matched_parcel_id": (primary_parcel or {}).get("parcel_id"),
               "matched_tracking_code": (primary_parcel or {}).get("tracking_code") or tracking_code,
               "created_at": sent_at, "received_at": now}
        await db.whatsapp_support_messages.insert_one(doc, session=session)
        updates = {}
        newer_inbound = not (conversation or {}).get("last_inbound_at") or sent_at >= _aware(conversation["last_inbound_at"])
        if newer_inbound:
            updates["last_inbound_at"] = sent_at
            updates["last_inbound_message_id"] = message["id"]
            resolved_at = (conversation or {}).get("resolved_at")
            last_outbound = (conversation or {}).get("last_outbound_at")
            follows_reply = not last_outbound or sent_at >= _aware(last_outbound).replace(microsecond=0)
            if follows_reply and (not resolved_at or sent_at >= _aware(resolved_at).replace(microsecond=0)):
                updates["status"] = "open"
                updates["unanswered_since"] = (conversation or {}).get("unanswered_since") or sent_at
        if not (conversation or {}).get("last_message_at") or sent_at >= _aware(conversation["last_message_at"]):
            updates.update(last_message_text=text, last_media=media, last_message_at=sent_at,
                           matched_user=user, matched_user_id=(user or {}).get("user_id"),
                           matched_parcel=primary_parcel, matched_parcel_id=(primary_parcel or {}).get("parcel_id"),
                           related_parcels=parcels)
        updates["updated_at"] = now
        await db.whatsapp_support_conversations.update_one(
            {"conversation_id": conversation_id},
            {"$set": updates, "$setOnInsert": {"conversation_id": conversation_id, "phone": phone, "source": "whatsapp", "created_at": now}},
            upsert=True, session=session)
        return doc
    async with await get_client().start_session() as session:
        return await session.with_transaction(save)


async def record_whatsapp_delivery_status(status):
    whatsapp_id = status.get("id")
    state = status.get("status")
    ranks = {"sent": 1, "failed": 2, "delivered": 3, "read": 4}
    if not whatsapp_id or state not in ranks:
        return
    try:
        timestamp = datetime.fromtimestamp(int(status["timestamp"]), timezone.utc)
    except (ValueError, KeyError, TypeError, OverflowError):
        timestamp = _now()
    update = {"$max": {"rank": ranks[state], "timestamps." + state: timestamp}, "$set": {"updated_at": _now()}}
    if state == "failed":
        update["$set"]["errors"] = [{"code": error.get("code"), "message": str(error.get("message") or error.get("title") or "")[:500]}
                                   for error in (status.get("errors") or [])]
    await db.whatsapp_support_delivery_statuses.update_one({"_id": whatsapp_id}, update, upsert=True)


async def enrich_delivery_statuses(messages):
    ids = [message["whatsapp_message_id"] for message in messages if message.get("whatsapp_message_id")]
    statuses = await db.whatsapp_support_delivery_statuses.find({"_id": {"$in": ids}}).to_list(length=len(ids)) if ids else []
    by_id = {status["_id"]: status for status in statuses}
    labels = {1: "sent", 2: "failed", 3: "delivered", 4: "read"}
    for message in messages:
        if message.get("delivery_status") == "sending" and _aware(message["updated_at"]) < _now() - timedelta(minutes=2):
            message["delivery_status"] = "uncertain"
        status = by_id.get(message.get("whatsapp_message_id"))
        if status:
            message["delivery_status"] = labels[status["rank"]]
            message["delivery_errors"] = status.get("errors") if status["rank"] == 2 else []
    return messages


def serialize_support_doc(doc: dict | None) -> dict | None:
    if not doc:
        return None
    result = {k: v for k, v in doc.items() if k != "_id"}
    return result


async def send_support_text_reply(conversation: dict, text: str, admin_user: dict, request_id=None) -> dict:
    clean_text = text.strip()
    if not clean_text:
        raise ValueError("Message vide")
    payload = {"messaging_product": "whatsapp", "to": conversation["phone"].lstrip("+"),
               "type": "text", "text": {"body": clean_text}}
    return await _send_support_message(conversation, admin_user=admin_user, text=clean_text,
        message_type="text", payload=payload, request_id=request_id)


def _support_template_variable(token: str, conversation: dict) -> str:
    token = token.strip().lower()
    user = conversation.get("matched_user") or {}
    parcel = conversation.get("matched_parcel") or {}
    if token == "name":
        return str(user.get("name") or "client Denkma")
    if token == "phone":
        return str(conversation.get("phone") or "")
    if token == "tracking_code":
        return str(parcel.get("tracking_code") or "")
    if token == "app_name":
        return "Denkma"
    return token


def _support_template_components(conversation: dict) -> list[dict]:
    tokens = [
        token.strip()
        for token in (settings.WHATSAPP_TEMPLATE_SUPPORT_REOPEN_VARIABLES or "").split(",")
        if token.strip()
    ]
    if not tokens:
        return []
    return [
        {
            "type": "body",
            "parameters": [
                {"type": "text", "text": _support_template_variable(token, conversation)}
                for token in tokens
            ],
        }
    ]


async def send_support_reopen_template(conversation: dict, admin_user: dict, request_id=None) -> dict:
    template_name = settings.WHATSAPP_TEMPLATE_SUPPORT_REOPEN
    if not template_name:
        raise RuntimeError("Modèle WhatsApp de relance support non configuré")
    template_payload = {"name": template_name, "language": {"code": "fr"}}
    components = _support_template_components(conversation)
    if components:
        template_payload["components"] = components
    payload = {"messaging_product": "whatsapp", "to": conversation["phone"].lstrip("+"),
               "type": "template", "template": template_payload}
    return await _send_support_message(conversation, admin_user=admin_user,
        text=f"[relance support via {template_name}]", message_type="template", payload=payload, request_id=request_id)


async def send_support_audio_reply(
    conversation: dict,
    *,
    content: bytes,
    filename: str,
    mime_type: str,
    admin_user: dict,
    request_id=None,
) -> dict:
    content_hash = hashlib.sha256(content).hexdigest()
    if request_id:
        previous = await db.whatsapp_support_messages.find_one({"message_id": "wmsg_" + request_id}, {"_id": 0})
        if previous:
            if (previous.get("conversation_id") != conversation["conversation_id"] or
                    previous.get("message_type") != "audio" or
                    (previous.get("media") or {}).get("content_hash") != content_hash):
                raise ValueError("Cet identifiant appartient à une autre réponse")
            if previous.get("delivery_status") != "failed":
                return previous
    prepared_content, prepared_filename, clean_mime_type = await asyncio.to_thread(
        _prepare_outbound_audio, content, filename, mime_type)
    media_id = await _upload_whatsapp_media(prepared_content, prepared_filename, clean_mime_type)
    payload = {
        "messaging_product": "whatsapp",
        "to": conversation["phone"].lstrip("+"),
        "type": "audio",
        "audio": {"id": media_id},
    }

    PRIVATE_WHATSAPP_DIR.mkdir(parents=True, exist_ok=True)
    ext = _safe_media_extension(clean_mime_type)
    stored_filename = f"out_{uuid.uuid4().hex}{ext}"
    path = PRIVATE_WHATSAPP_DIR / stored_filename
    path.write_bytes(prepared_content)
    file_id = await _store_whatsapp_media_blob(
        filename=stored_filename,
        content=prepared_content,
        mime_type=clean_mime_type,
        media_id=media_id,
        direction="outbound",
    )

    media = {
        "media_id": media_id,
        "mime_type": clean_mime_type,
        "content_hash": content_hash,
        "file_size": len(prepared_content),
        "storage_path": str(path),
        "file_id": file_id,
        "download_url": f"{settings.BASE_URL}/api/admin/support/whatsapp/media/{stored_filename}",
    }
    return await _send_support_message(
        conversation,
        admin_user=admin_user,
        text="[note vocale envoyée]",
        message_type="audio",
        payload=payload, request_id=request_id,
        media=media,
    )
