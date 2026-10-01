import logging
import uuid
from datetime import datetime, timedelta, timezone

from pymongo import ReturnDocument

from database import db

logger = logging.getLogger(__name__)


async def process_delivery_completion(parcel_id: str):
    try:
        await _process_delivery_completion(parcel_id)
    except Exception:
        logger.exception("La reprise des compléments de livraison reste nécessaire : %s", parcel_id)


async def _process_delivery_completion(parcel_id: str):
    now = datetime.now(timezone.utc)
    token = uuid.uuid4().hex
    job = await db.delivery_completion_jobs.find_one_and_update(
        {"_id": parcel_id, "completed_at": None,
         "$or": [{"lease_until": None}, {"lease_until": {"$lte": now}}]},
        {"$set": {"lease_token": token, "lease_until": now + timedelta(minutes=5)}},
        return_document=ReturnDocument.AFTER,
    )
    if not job:
        return
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    from services.gamification_service import update_driver_gamification
    from services.loyalty_service import credit_loyalty_points, _check_referral_bonus
    from services.ranking_service import refresh_driver_stats_for_period
    from services.notification_service import notify_driver_mission_completed, notify_parcel_status_change
    from models.common import ParcelStatus

    async def run_step(name, operation):
        if (job.get("steps") or {}).get(name):
            return
        await operation()
        await db.delivery_completion_jobs.update_one(
            {"_id": parcel_id, "lease_token": token}, {"$set": {f"steps.{name}": True}},
        )

    try:
        driver_id = parcel.get("assigned_driver_id")
        if driver_id:
            await run_step("gamification", lambda: update_driver_gamification(
                driver_id, "delivery_completed", event_id=f"delivery:{parcel_id}"))
            await run_step("referral", lambda: _check_referral_bonus(driver_id))
        sender_id = parcel.get("sender_user_id")
        if sender_id:
            await run_step("loyalty", lambda: credit_loyalty_points(sender_id, parcel_id))
        for mission in job.get("missions") or []:
            await run_step(f"notification_{mission['mission_id']}", lambda: notify_driver_mission_completed(mission, parcel))
        period = job["created_at"].strftime("%Y-%m")
        await run_step("ranking", lambda: refresh_driver_stats_for_period(period))
        await run_step("client_notification", lambda: notify_parcel_status_change(parcel, ParcelStatus.DELIVERED))
        await db.delivery_completion_jobs.update_one(
            {"_id": parcel_id, "lease_token": token},
            {"$set": {"completed_at": datetime.now(timezone.utc)}, "$unset": {"lease_token": "", "lease_until": "", "last_error": ""}},
        )
    except Exception:
        logger.exception("Compléments de livraison à reprendre : %s", parcel_id)
        await db.delivery_completion_jobs.update_one(
            {"_id": parcel_id, "lease_token": token},
            {"$set": {"last_error": "Un complément de livraison doit être repris", "lease_until": datetime.now(timezone.utc) + timedelta(minutes=1)},
             "$unset": {"lease_token": ""}, "$inc": {"attempts": 1}},
        )


async def retry_delivery_completions():
    now = datetime.now(timezone.utc)
    jobs = await db.delivery_completion_jobs.find(
        {"completed_at": None, "$or": [{"lease_until": None}, {"lease_until": {"$lte": now}}]},
        {"_id": 1},
    ).limit(100).to_list(length=100)
    for job in jobs:
        await process_delivery_completion(job["_id"])
