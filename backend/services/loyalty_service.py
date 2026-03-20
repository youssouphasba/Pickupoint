import logging
import uuid
from datetime import datetime, timezone

from database import db
from services.user_service import (
    get_global_app_settings,
    get_referral_metric_count,
    get_referral_role_config,
)

logger = logging.getLogger(__name__)

# Config from PLAN_RECOMPENSES_PROMOTIONS.md
POINTS_PER_DELIVERY = 10

# Tiers thresholds and discounts
TIER_BRONZE = "bronze"
TIER_SILVER = "silver"
TIER_GOLD = "gold"

THRESHOLD_SILVER = 200
THRESHOLD_GOLD = 500


def compute_tier(points: int) -> str:
    if points >= THRESHOLD_GOLD:
        return TIER_GOLD
    if points >= THRESHOLD_SILVER:
        return TIER_SILVER
    return TIER_BRONZE


def get_tier_discount(tier: str) -> float:
    """Returns the discount coefficient (e.g., 0.90 for 10% off)."""
    return {
        TIER_BRONZE: 1.0,
        TIER_SILVER: 0.90,
        TIER_GOLD: 0.80,
    }.get(tier, 1.0)


async def credit_loyalty_points(user_id: str):
    """Credits points after a successful delivery and checks for tier up."""
    user = await db.users.find_one({"user_id": user_id})
    if not user:
        return

    now = datetime.now(timezone.utc)
    new_points = user.get("loyalty_points", 0) + POINTS_PER_DELIVERY
    new_tier = compute_tier(new_points)

    await db.users.update_one(
        {"user_id": user_id},
        {
            "$set": {
                "loyalty_points": new_points,
                "loyalty_tier": new_tier,
                "updated_at": now,
            }
        },
    )

    await db.loyalty_events.insert_one(
        {
            "event_id": f"loy_{uuid.uuid4().hex[:12]}",
            "user_id": user_id,
            "type": "delivery_completed",
            "points": POINTS_PER_DELIVERY,
            "balance": new_points,
            "created_at": now,
        }
    )

    if new_tier != user.get("loyalty_tier"):
        logger.info("User %s promoted to %s tier", user_id, new_tier)

    await _check_referral_bonus(user_id)


async def _check_referral_bonus(user_id: str):
    """Credits referral rewards using per-role config for the referred user."""
    user = await db.users.find_one({"user_id": user_id})
    if not user or not user.get("referred_by") or user.get("referral_credited"):
        return

    settings_doc = await get_global_app_settings()
    user_role = str(user.get("role") or "client")
    config = get_referral_role_config(settings_doc, user_role)

    reward_metric = config["reward_metric"]
    reward_count = config["reward_count"]
    current_count = await get_referral_metric_count(user_id, reward_metric)
    if current_count < reward_count:
        return

    now = datetime.now(timezone.utc)
    referred_bonus_xof = config["referred_bonus_xof"]
    sponsor_bonus_xof = config["sponsor_bonus_xof"]
    if referred_bonus_xof <= 0 and sponsor_bonus_xof <= 0:
        logger.info("Referral bonus disabled by settings for user %s (role=%s)", user_id, user_role)
        await db.users.update_one(
            {"user_id": user_id},
            {"$set": {"referral_credited": True, "referral_rewarded_at": now, "updated_at": now}},
        )
        return

    sponsor_user_id = user["referred_by"]

    if referred_bonus_xof > 0:
        await _add_to_wallet_once(
            user_id=user_id,
            amount=referred_bonus_xof,
            tx_type="referral_bonus",
            description=f"Bonus parrainage ({user_role}) - seuil atteint",
            now=now,
            tx_id=f"ref_bonus_self_{user_id}",
        )
    if sponsor_bonus_xof > 0:
        await _add_to_wallet_once(
            user_id=sponsor_user_id,
            amount=sponsor_bonus_xof,
            tx_type="referral_bonus",
            description=f"Bonus parrainage ({user_role}) - filleul qualifie",
            now=now,
            tx_id=f"ref_bonus_sponsor_{user_id}",
        )

    await db.users.update_one(
        {"user_id": user_id},
        {"$set": {"referral_credited": True, "referral_rewarded_at": now, "updated_at": now}},
    )
    logger.info("Referral credits paid for user %s (role=%s) and referrer %s", user_id, user_role, sponsor_user_id)


async def _add_to_wallet(user_id: str, amount: float, tx_type: str, description: str, now: datetime):
    await db.wallets.update_one(
        {"user_id": user_id},
        {"$inc": {"balance": amount}},
        upsert=True,
    )
    await db.wallet_transactions.insert_one(
        {
            "tx_id": f"tx_{uuid.uuid4().hex[:12]}",
            "user_id": user_id,
            "type": tx_type,
            "amount": amount,
            "description": description,
            "created_at": now,
        }
    )


async def _add_to_wallet_once(
    *,
    user_id: str,
    amount: float,
    tx_type: str,
    description: str,
    now: datetime,
    tx_id: str,
):
    result = await db.wallet_transactions.update_one(
        {"tx_id": tx_id},
        {
            "$setOnInsert": {
                "tx_id": tx_id,
                "user_id": user_id,
                "type": tx_type,
                "amount": amount,
                "description": description,
                "created_at": now,
            }
        },
        upsert=True,
    )
    if result.upserted_id is None:
        return

    await db.wallets.update_one(
        {"user_id": user_id},
        {
            "$inc": {"balance": amount},
            "$set": {"updated_at": now},
        },
        upsert=True,
    )
