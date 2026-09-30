from datetime import datetime, timezone

from database import db, get_client
from services.loyalty_rules import compute_tier, tier_discount_coeff as get_tier_discount
from services.performance_rewards_service import get_performance_rewards_settings
from services.referral_service import (
    ensure_referral_record_for_user,
    refresh_referral_progress,
)
from services.user_service import (
    get_global_app_settings,
)


async def credit_loyalty_points(user_id: str, parcel_id: str):
    """Commit the balance, parcel receipt and event together, once per parcel."""
    now = datetime.now(timezone.utc)
    rewards = await get_performance_rewards_settings()
    points_per_delivery = rewards["client"]["loyalty_points_per_delivered_parcel"]
    async def award(session):
        parcel = await db.parcels.find_one({"parcel_id": parcel_id}, session=session)
        if not parcel or parcel.get("status") != "delivered" or parcel.get("sender_user_id") != user_id:
            return None
        if parcel.get("loyalty_award"):
            return parcel["loyalty_award"]
        user = await db.users.find_one({"user_id": user_id}, session=session)
        if not user:
            return None
        new_points = user.get("loyalty_points", 0) + points_per_delivery
        new_tier = compute_tier(new_points, rewards["client"]["loyalty_tiers"])
        previous_tier = compute_tier(user.get("loyalty_points", 0), rewards["client"]["loyalty_tiers"])
        event = {
            "_id": f"loyalty_delivery:{parcel_id}",
            "event_id": f"loyalty_delivery:{parcel_id}",
            "user_id": user_id,
            "parcel_id": parcel_id,
            "tracking_code": parcel.get("tracking_code"),
            "type": "delivery_completed",
            "points": points_per_delivery,
            "balance": new_points,
            "tier": new_tier,
            "previous_tier": previous_tier,
            "tier_changed": new_tier != previous_tier,
            "created_at": now,
        }
        await db.loyalty_events.insert_one(event, session=session)
        await db.users.update_one({"user_id": user_id}, {"$set": {
            "loyalty_points": new_points, "loyalty_tier": new_tier, "updated_at": now,
        }}, session=session)
        receipt = {key: value for key, value in event.items() if key != "_id"}
        await db.parcels.update_one({"parcel_id": parcel_id}, {"$set": {"loyalty_award": receipt}}, session=session)
        return receipt

    async with await get_client().start_session() as session:
        receipt = await session.with_transaction(award)
    if receipt:
        await _check_referral_bonus(user_id)
    return receipt


async def _check_referral_bonus(user_id: str):
    """Qualify the frozen referral offer without making a payment."""
    user = await db.users.find_one({"user_id": user_id})
    if not user or not user.get("referred_by"):
        return
    settings_doc = await get_global_app_settings()
    await ensure_referral_record_for_user(user, settings_doc, source="legacy_bonus_check")
    await refresh_referral_progress(user_id, settings_doc)
