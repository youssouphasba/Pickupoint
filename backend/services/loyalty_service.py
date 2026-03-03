import logging
import uuid
from datetime import datetime, timezone
from database import db

logger = logging.getLogger(__name__)

# Config from PLAN_RECOMPENSES_PROMOTIONS.md
POINTS_PER_DELIVERY = 10
REFERRAL_BONUS_XOF = 500

# Tiers thresholds and discounts
TIER_BRONZE = "bronze"
TIER_SILVER = "silver"
TIER_GOLD   = "gold"

THRESHOLD_SILVER = 200
THRESHOLD_GOLD   = 500

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
        TIER_SILVER: 0.90,  # -10% from text
        TIER_GOLD:   0.80   # -20% from text
    }.get(tier, 1.0)

async def credit_loyalty_points(user_id: str):
    """Credits points after a successful delivery and checks for tier up."""
    user = await db.users.find_one({"user_id": user_id})
    if not user:
        return

    new_points = user.get("loyalty_points", 0) + POINTS_PER_DELIVERY
    new_tier = compute_tier(new_points)
    
    update_query = {
        "$set": {
            "loyalty_points": new_points,
            "loyalty_tier":   new_tier,
            "updated_at":     datetime.now(timezone.utc)
        }
    }
    
    await db.users.update_one({"user_id": user_id}, update_query)
    
    # Record event
    await db.loyalty_events.insert_one({
        "event_id":   f"loy_{uuid.uuid4().hex[:12]}",
        "user_id":    user_id,
        "type":       "delivery_completed",
        "points":     POINTS_PER_DELIVERY,
        "balance":    new_points,
        "created_at": datetime.now(timezone.utc),
    })

    if new_tier != user.get("loyalty_tier"):
        logger.info(f"User {user_id} promoted to {new_tier} tier!")

    # Check for referral credit if it's the first delivery
    await _check_referral_bonus(user_id)

async def _check_referral_bonus(user_id: str):
    """Check if the user has a referrer and if this is their first delivery."""
    user = await db.users.find_one({"user_id": user_id})
    if not user or not user.get("referred_by") or user.get("referral_credited"):
        return

    # Check if this is the first successful delivery
    delivery_count = await db.parcels.count_documents({
        "sender_user_id": user_id,
        "status": "delivered"
    })
    
    if delivery_count == 1:
        parrain_id = user["referred_by"]
        now = datetime.now(timezone.utc)

        # Credit filleul
        await _add_to_wallet(user_id, REFERRAL_BONUS_XOF, "referral_bonus", "Bonus parrainage — 1ère livraison", now)
        
        # Credit parrain
        await _add_to_wallet(parrain_id, REFERRAL_BONUS_XOF, "referral_bonus", "Bonus parrainage — filleul livré", now)

        # Mark as credited
        await db.users.update_one(
            {"user_id": user_id},
            {"$set": {"referral_credited": True}}
        )
        logger.info(f"Referral credits paid for user {user_id} and referrer {parrain_id}")

async def _add_to_wallet(user_id: str, amount: float, tx_type: str, description: str, now: datetime):
    await db.wallets.update_one(
        {"user_id": user_id},
        {"$inc": {"balance": amount}},
        upsert=True,
    )
    await db.wallet_transactions.insert_one({
        "tx_id": f"tx_{uuid.uuid4().hex[:12]}",
        "user_id": user_id,
        "type": tx_type,
        "amount": amount,
        "description": description,
        "created_at": now,
    })
