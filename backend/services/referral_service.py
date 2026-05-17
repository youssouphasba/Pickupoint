from datetime import datetime, timezone

from database import db
from services.user_service import get_referral_metric_count, get_referral_role_config


def build_referral_id(referred_user_id: str) -> str:
    return f"ref_{referred_user_id}"


async def upsert_referral_record(
    *,
    sponsor_user_id: str,
    referred_user_id: str,
    referred_role: str,
    referral_code: str,
    source: str,
    settings_doc: dict | None,
    created_at: datetime | None = None,
) -> None:
    now = datetime.now(timezone.utc)
    config = get_referral_role_config(settings_doc, referred_role)
    await db.referrals.update_one(
        {"referred_user_id": referred_user_id},
        {
            "$setOnInsert": {
                "referral_id": build_referral_id(referred_user_id),
                "sponsor_user_id": sponsor_user_id,
                "referred_user_id": referred_user_id,
                "referred_role": referred_role,
                "referral_code": referral_code,
                "source": source,
                "status": "pending",
                "created_at": created_at or now,
            },
            "$set": {
                "reward_metric": config["reward_metric"],
                "reward_count": config["reward_count"],
                "apply_metric": config["apply_metric"],
                "apply_max_count": config["apply_max_count"],
                "sponsor_bonus_xof": config["sponsor_bonus_xof"],
                "referred_bonus_xof": config["referred_bonus_xof"],
                "updated_at": now,
            },
        },
        upsert=True,
    )


async def refresh_referral_progress(user_id: str, settings_doc: dict | None = None) -> dict | None:
    referral = await db.referrals.find_one({"referred_user_id": user_id}, {"_id": 0})
    user = await db.users.find_one({"user_id": user_id}, {"_id": 0, "role": 1})
    if not referral or not user:
        return None

    role = str(referral.get("referred_role") or user.get("role") or "client")
    config = get_referral_role_config(settings_doc, role)
    metric = config["reward_metric"]
    count = await get_referral_metric_count(user_id, metric)
    now = datetime.now(timezone.utc)
    status = referral.get("status") or "pending"
    if status == "pending" and count >= config["reward_count"]:
        status = "qualified"

    update = {
        "referred_role": role,
        "reward_metric": metric,
        "reward_count": config["reward_count"],
        "reward_metric_count": count,
        "sponsor_bonus_xof": config["sponsor_bonus_xof"],
        "referred_bonus_xof": config["referred_bonus_xof"],
        "status": status,
        "updated_at": now,
    }
    if status == "qualified":
        update["qualified_at"] = now
    await db.referrals.update_one({"referral_id": referral["referral_id"]}, {"$set": update})
    return {**referral, **update}


async def mark_referral_rewarded(
    *,
    referred_user_id: str,
    status: str,
    sponsor_transaction_reference: str | None = None,
    referred_transaction_reference: str | None = None,
) -> None:
    now = datetime.now(timezone.utc)
    update = {
        "status": status,
        "rewarded_at": now,
        "updated_at": now,
    }
    if sponsor_transaction_reference:
        update["sponsor_transaction_reference"] = sponsor_transaction_reference
    if referred_transaction_reference:
        update["referred_transaction_reference"] = referred_transaction_reference
    await db.referrals.update_one(
        {"referred_user_id": referred_user_id},
        {"$set": update},
    )
