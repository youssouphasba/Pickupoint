from datetime import datetime, timedelta, timezone
import uuid

from bson import ObjectId
from gridfs.errors import NoFile
from motor.motor_asyncio import AsyncIOMotorGridFSBucket

from config import settings
from database import db, get_db


TERMINAL_PARCEL_STATUSES = {"delivered", "cancelled", "returned", "expired", "disputed"}
ACTIVE_MISSION_STATUSES = {"assigned", "in_progress", "incident_reported"}


def _cutoff(days: int, now: datetime) -> datetime:
    return now - timedelta(days=days)


async def _purge_collection(collection_name: str, field: str, cutoff: datetime, query: dict | None = None) -> int:
    criteria = dict(query or {})
    criteria[field] = {"$lt": cutoff}
    result = await db[collection_name].delete_many(criteria)
    return result.deleted_count


async def _purge_mission_traces(cutoff: datetime) -> dict[str, int]:
    points_deleted = 0
    missions_updated = 0
    last_id = None
    while True:
        query = {
            "status": {"$nin": [*ACTIVE_MISSION_STATUSES, "pending"]},
            "gps_trace_purged_at": {"$exists": False},
            "$or": [
                {"completed_at": {"$lt": cutoff}},
                {"completed_at": None, "updated_at": {"$lt": cutoff}},
            ],
        }
        if last_id is not None:
            query["mission_id"] = {"$gt": last_id}
        missions = await db.delivery_missions.find(query, {"_id": 0, "mission_id": 1}).sort("mission_id", 1).to_list(length=500)
        mission_ids = [item["mission_id"] for item in missions if item.get("mission_id")]
        if not mission_ids:
            break
        last_id = mission_ids[-1]
        points_deleted += (await db.mission_gps_points.delete_many({"mission_id": {"$in": mission_ids}, "ts": {"$lt": cutoff}})).deleted_count
        result = await db.delivery_missions.update_many(
            {**query, "mission_id": {"$in": mission_ids}},
            {"$unset": {"gps_trail": "", "driver_location": "", "encoded_polyline": ""},
             "$set": {"gps_trace_purged_at": datetime.now(timezone.utc)}},
        )
        missions_updated += result.modified_count
    return {"mission_points": points_deleted, "missions": missions_updated}


async def _purge_old_proof_media(cutoff: datetime) -> int:
    bucket = AsyncIOMotorGridFSBucket(get_db(), bucket_name="parcel_photos")
    parcels = await db.parcels.find(
        {
            "status": {"$in": list(TERMINAL_PARCEL_STATUSES)},
            "updated_at": {"$lt": cutoff},
            "$or": [
                {"parcel_photo_file_id": {"$exists": True}},
                {"proof_data": {"$exists": True}},
                {"pickup_voice_note": {"$exists": True}},
                {"delivery_voice_note": {"$exists": True}},
            ],
        },
        {"_id": 0, "parcel_id": 1, "parcel_photo_file_id": 1},
    ).to_list(length=5000)
    modified = 0
    for parcel in parcels:
        file_id = parcel.get("parcel_photo_file_id")
        if file_id:
            try:
                await bucket.delete(ObjectId(file_id))
            except (NoFile, ValueError):
                pass
        result = await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"]},
            {
                "$unset": {
                    "parcel_photo_file_id": "",
                    "parcel_photo_path": "",
                    "parcel_photo_url": "",
                    "proof_data": "",
                    "pickup_voice_note": "",
                    "delivery_voice_note": "",
                }
            },
        )
        modified += result.modified_count
    return modified


async def _purge_campaign_media(cutoff: datetime) -> int:
    bucket = AsyncIOMotorGridFSBucket(get_db(), bucket_name="campaign_images")
    referenced: set[str] = set()
    async for campaign in db.in_app_campaigns.find({}, {"image_url": 1, "video_url": 1}):
        for field in ("image_url", "video_url"):
            value = campaign.get(field)
            if value:
                referenced.add(str(value).rsplit("/", 1)[-1])
    deleted = 0
    async for grid_file in bucket.find({"uploadDate": {"$lt": cutoff}}):
        if grid_file.filename in referenced:
            continue
        try:
            await bucket.delete(grid_file._id)
            deleted += 1
        except NoFile:
            continue
    return deleted


async def _purge_support_media(cutoff: datetime) -> int:
    from services.whatsapp_support_service import PRIVATE_WHATSAPP_DIR
    referenced: set[str] = set()
    filenames: set[str] = set()
    async for message in db.whatsapp_support_messages.find(
        {"media": {"$ne": None}},
        {"media": 1},
    ):
        media = message.get("media") or {}
        for field in ("download_url", "storage_path"):
            value = media.get(field)
            if value:
                filenames.add(str(value).replace("\\", "/").rsplit("/", 1)[-1])
        file_id = media.get("file_id")
        if file_id:
            referenced.add(str(file_id))
    bucket = AsyncIOMotorGridFSBucket(get_db(), bucket_name="whatsapp_support_media")
    deleted = 0
    async for grid_file in bucket.find({"uploadDate": {"$lt": cutoff}}):
        if str(grid_file._id) in referenced:
            continue
        try:
            await bucket.delete(grid_file._id)
            deleted += 1
        except NoFile:
            continue
    base = PRIVATE_WHATSAPP_DIR.resolve()
    if base.is_dir():
        for path in base.iterdir():
            if (path.is_file() and not path.is_symlink() and path.resolve().parent == base
                    and path.name not in filenames
                    and datetime.fromtimestamp(path.stat().st_mtime, timezone.utc) < cutoff):
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
    return deleted


async def _anonymize_old_closed_parcels(cutoff: datetime) -> int:
    result = await db.parcels.update_many(
        {
            "status": {"$in": list(TERMINAL_PARCEL_STATUSES)},
            "updated_at": {"$lt": cutoff},
        },
        {
            "$set": {
                "recipient_name": "Destinataire anonymisé",
                "sender_name": "Expéditeur anonymisé",
            },
            "$unset": {
                "recipient_phone": "",
                "sender_phone": "",
                "origin_location.geopin": "",
                "delivery_address.geopin": "",
                "pickup_geopin": "",
                "delivery_geopin": "",
            },
        },
    )
    return result.modified_count


async def _anonymize_resolved_support(cutoff: datetime) -> int:
    conversations = await db.whatsapp_support_conversations.find(
        {"status": "resolved", "updated_at": {"$lt": cutoff}, "anonymized_at": {"$exists": False}},
        {"_id": 0, "conversation_id": 1}).to_list(length=5000)
    modified = 0
    for conversation in conversations:
        conversation_id = conversation["conversation_id"]
        if await db.whatsapp_support_messages.count_documents({"conversation_id": conversation_id}):
            continue
        if await db.whatsapp_support_notes.count_documents({"conversation_id": conversation_id}):
            continue
        archive_id = "wa_archived_" + uuid.uuid4().hex
        result = await db.whatsapp_support_conversations.update_one(
            {"conversation_id": conversation_id, "status": "resolved", "updated_at": {"$lt": cutoff}},
            {"$set": {"conversation_id": archive_id, "phone": "anonymized", "full_name": "Contact anonymisé",
                      "anonymized_at": datetime.now(timezone.utc)},
             "$unset": {field: "" for field in ("matched_user_id", "matched_parcel_id", "matched_user",
                       "matched_parcel", "related_parcels", "last_message_text", "last_incoming_preview",
                       "last_media", "last_inbound_message_id", "status_changed_by")}})
        modified += result.modified_count
    return modified


async def _purge_deleted_account_kyc(cutoff: datetime) -> int:
    users = await db.users.find(
        {
            "deleted_account": True,
            "deleted_at": {"$lt": cutoff},
            "$or": [
                {"kyc_id_card_file_id": {"$exists": True}},
                {"kyc_license_file_id": {"$exists": True}},
            ],
        },
        {"_id": 0, "user_id": 1, "kyc_id_card_file_id": 1, "kyc_license_file_id": 1},
    ).to_list(length=5000)
    bucket = AsyncIOMotorGridFSBucket(get_db(), bucket_name="kyc_documents")
    modified = 0
    for user in users:
        for field in ("kyc_id_card_file_id", "kyc_license_file_id"):
            file_id = user.get(field)
            if file_id:
                try:
                    await bucket.delete(ObjectId(file_id))
                except (NoFile, ValueError):
                    pass
        result = await db.users.update_one(
            {"user_id": user["user_id"]},
            {
                "$unset": {
                    "kyc_id_card_file_id": "",
                    "kyc_license_file_id": "",
                    "kyc_id_card_url": "",
                    "kyc_license_url": "",
                    "kyc_id_card_path": "",
                    "kyc_license_path": "",
                }
            },
        )
        modified += result.modified_count
    return modified


async def _purge_orphaned_kyc(cutoff: datetime) -> int:
    bucket = AsyncIOMotorGridFSBucket(get_db(), bucket_name="kyc_documents")
    deleted = 0
    cursor = db["kyc_documents.files"].find({"uploadDate": {"$lt": cutoff}}, {"_id": 1})
    async for document in cursor:
        file_id = document["_id"]
        referenced = await db.users.find_one({"$or": [
            {"kyc_id_card_file_id": str(file_id)}, {"kyc_license_file_id": str(file_id)},
        ]}, {"_id": 1})
        if referenced:
            continue
        try:
            await bucket.delete(file_id)
            deleted += 1
        except NoFile:
            pass
    return deleted


async def purge_expired_data() -> dict[str, int]:
    now = datetime.now(timezone.utc)
    result: dict[str, int] = {}
    result["notifications"] = await _purge_collection(
        "notifications", "created_at", _cutoff(settings.NOTIFICATION_RETENTION_DAYS, now)
    )
    result["notification_broadcasts"] = await _purge_collection(
        "notification_broadcasts", "created_at", _cutoff(settings.NOTIFICATION_RETENTION_DAYS, now)
    )
    result["campaign_events"] = await _purge_collection(
        "in_app_campaign_events", "created_at", _cutoff(settings.CAMPAIGN_EVENT_RETENTION_DAYS, now)
    )
    result["audit_events"] = await _purge_collection(
        "admin_events", "created_at", _cutoff(settings.AUDIT_LOG_RETENTION_DAYS, now)
    )
    result["kyc_audit_events"] = await _purge_collection(
        "parcel_events", "created_at", _cutoff(settings.AUDIT_LOG_RETENTION_DAYS, now),
        {"event_type": {"$regex": "^KYC_"}},
    )
    result["delivery_logs"] = await _purge_collection(
        "delivery_logs", "created_at", _cutoff(settings.TECHNICAL_LOG_RETENTION_DAYS, now)
    )
    result["whatsapp_delivery_logs"] = await _purge_collection(
        "whatsapp_delivery_logs", "created_at", _cutoff(settings.TECHNICAL_LOG_RETENTION_DAYS, now)
    )
    result["whatsapp_call_events"] = await _purge_collection(
        "whatsapp_call_events", "created_at", _cutoff(settings.TECHNICAL_LOG_RETENTION_DAYS, now)
    )
    result["driver_call_requests"] = await _purge_collection(
        "driver_call_requests", "created_at", _cutoff(settings.TECHNICAL_LOG_RETENTION_DAYS, now)
    )
    result["driver_contact_requests"] = await _purge_collection(
        "driver_contact_requests", "created_at", _cutoff(settings.TECHNICAL_LOG_RETENTION_DAYS, now)
    )
    result["promo_uses"] = await _purge_collection(
        "promo_uses", "created_at", _cutoff(settings.CAMPAIGN_EVENT_RETENTION_DAYS, now)
    )
    result["support_messages"] = await _purge_collection(
        "whatsapp_support_messages",
        "created_at",
        _cutoff(settings.SUPPORT_RETENTION_DAYS, now),
        {"conversation_id": {"$in": await db.whatsapp_support_conversations.distinct(
            "conversation_id",
            {"status": "resolved", "updated_at": {"$lt": _cutoff(settings.SUPPORT_RETENTION_DAYS, now)}},
        )}},
    )
    result["support_notes"] = await _purge_collection(
        "whatsapp_support_notes", "created_at", _cutoff(settings.SUPPORT_RETENTION_DAYS, now),
        {"conversation_id": {"$in": await db.whatsapp_support_conversations.distinct(
            "conversation_id", {"status": "resolved", "updated_at": {"$lt": _cutoff(settings.SUPPORT_RETENTION_DAYS, now)}})}},
    )
    result["support_delivery_statuses"] = await _purge_collection(
        "whatsapp_support_delivery_statuses", "updated_at", _cutoff(settings.SUPPORT_RETENTION_DAYS, now)
    )
    result["support_media"] = await _purge_support_media(
        _cutoff(settings.SUPPORT_RETENTION_DAYS, now)
    )
    result["support_conversations"] = await _anonymize_resolved_support(
        _cutoff(settings.SUPPORT_RETENTION_DAYS, now)
    )
    result.update(await _purge_mission_traces(_cutoff(settings.GPS_TRACE_RETENTION_DAYS, now)))
    result["closed_parcels_anonymized"] = await _anonymize_old_closed_parcels(
        _cutoff(settings.OPERATIONAL_DATA_RETENTION_DAYS, now)
    )
    result["proof_media"] = await _purge_old_proof_media(
        _cutoff(settings.PROOF_MEDIA_RETENTION_DAYS, now)
    )
    result["kyc_files"] = await _purge_deleted_account_kyc(
        _cutoff(settings.KYC_RETENTION_DAYS, now)
    )
    result["kyc_orphans"] = await _purge_orphaned_kyc(now - timedelta(hours=settings.KYC_ORPHAN_GRACE_HOURS))
    result["campaign_media"] = await _purge_campaign_media(
        _cutoff(settings.CAMPAIGN_MEDIA_ORPHAN_GRACE_DAYS, now)
    )
    return result
