from datetime import datetime, timedelta, timezone

from core.datetime_utils import as_aware_utc
from core.exceptions import bad_request_exception
from core.security import verify_password
from database import db

PIN_MAX_FAILED_ATTEMPTS = 5
PIN_LOCK_MINUTES = 15


async def verify_user_pin(user: dict, pin: str) -> None:
    if not user.get("pin_hash"):
        raise bad_request_exception("Aucun PIN configuré. Réinitialisez votre PIN avant d’activer la biométrie.")
    now = datetime.now(timezone.utc)
    locked_until = as_aware_utc(user.get("pin_locked_until"))
    if locked_until and locked_until > now:
        raise bad_request_exception("Trop de tentatives incorrectes. Réessayez plus tard ou réinitialisez votre PIN.")
    if not verify_password(pin, user["pin_hash"]):
        if locked_until and locked_until <= now:
            await db.users.update_one({"user_id": user["user_id"], "pin_locked_until": user["pin_locked_until"]},
                                      {"$unset": {"pin_failed_attempts": "", "pin_locked_until": ""}})
        from pymongo import ReturnDocument
        updated = await db.users.find_one_and_update(
            {"user_id": user["user_id"]}, {"$inc": {"pin_failed_attempts": 1}},
            return_document=ReturnDocument.AFTER,
        )
        if int((updated or {}).get("pin_failed_attempts") or 0) >= PIN_MAX_FAILED_ATTEMPTS:
            await db.users.update_one({"user_id": user["user_id"]},
                                      {"$set": {"pin_locked_until": now + timedelta(minutes=PIN_LOCK_MINUTES)}})
        raise bad_request_exception("Code PIN incorrect")
    await db.users.update_one({"user_id": user["user_id"]},
                              {"$unset": {"pin_failed_attempts": "", "pin_locked_until": ""}})
