from datetime import datetime, timedelta, timezone

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
    missions = await db.delivery_missions.find(
        {
            "status": {"$nin": list(ACTIVE_MISSION_STATUSES)},
            "completed_at": {"$lt": cutoff},
        },
        {"_id": 0, "mission_id": 1},
    ).to_list(length=5000)
    mission_ids = [item["mission_id"] for item in missions if item.get("mission_id")]
    points_deleted = 0
    for start in range(0, len(mission_ids), 500):
        batch = mission_ids[start : start + 500]
        if not batch:
            continue
        result = await db.mission_gps_points.delete_many({"mission_id": {"$in": batch}})
        points_deleted += result.deleted_count
    missions_updated = 0
    if mission_ids:
        result = await db.delivery_missions.update_many(
            {"mission_id": {"$in": mission_ids}},
            {"$unset": {"gps_trail": "", "driver_location": "", "encoded_polyline": ""}},
        )
        missions_updated = result.modified_count
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
    referenced: set[str] = set()
    async for message in db.whatsapp_support_messages.find(
        {"media.file_id": {"$exists": True}},
        {"media.file_id": 1},
    ):
        file_id = ((message.get("media") or {}).get("file_id"))
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
    result = await db.whatsapp_support_conversations.update_many(
        {"status": "resolved", "updated_at": {"$lt": cutoff}},
        {
            "$set": {
                "phone": "anonymized",
                "full_name": "Contact anonymisé",
                "last_incoming_preview": None,
            },
            "$unset": {"matched_user_id": "", "matched_parcel_id": ""},
        },
    )
    return result.modified_count


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
    result["campaign_media"] = await _purge_campaign_media(
        _cutoff(settings.CAMPAIGN_MEDIA_ORPHAN_GRACE_DAYS, now)
    )
    return result
