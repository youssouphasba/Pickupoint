import logging
from calendar import monthrange
from datetime import datetime, timezone
from uuid import uuid4

from database import db
from services.performance_rewards_service import get_performance_rewards_settings
from services.wallet_service import credit_wallet

logger = logging.getLogger(__name__)

MONTHLY_DRIVER_GOAL = 20


async def compute_driver_stats_for_period(period: str) -> list[dict]:
    year, month = map(int, period.split("-"))
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    _, last_day = monthrange(year, month)
    end = datetime(year, month, last_day, 23, 59, 59, tzinfo=timezone.utc)

    drivers = await db.users.find(
        {"role": "driver"},
        {"_id": 0, "user_id": 1, "average_rating": 1, "total_ratings_count": 1},
    ).to_list(None)

    mission_stats_pipeline = [
        {
            "$match": {
                "driver_id": {"$exists": True, "$ne": None},
                "$or": [
                    {"created_at": {"$gte": start, "$lte": end}},
                    {"completed_at": {"$gte": start, "$lte": end}},
                ],
            }
        },
        {
            "$group": {
                "_id": "$driver_id",
                "total": {"$sum": 1},
                "success": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
                "earned": {
                    "$sum": {
                        "$cond": [
                            {"$eq": ["$status", "completed"]},
                            {"$ifNull": ["$earn_amount", 0]},
                            0,
                        ]
                    }
                },
            }
        },
    ]

    mission_stats = await db.delivery_missions.aggregate(mission_stats_pipeline).to_list(None)
    stats_by_driver = {item["_id"]: item for item in mission_stats if item.get("_id")}

    stats_list = []
    for driver in drivers:
        driver_id = driver.get("user_id")
        if not driver_id:
            continue

        count = stats_by_driver.get(driver_id, {})
        total = int(count.get("total") or 0)
        success = int(count.get("success") or 0)
        rate = round(success / max(total, 1) * 100, 1)

        stats_list.append(
            {
                "stat_id": f"stat_{uuid4().hex[:12]}",
                "driver_id": driver_id,
                "period": period,
                "deliveries_total": total,
                "deliveries_success": success,
                "success_rate": rate,
                "avg_rating": float(driver.get("average_rating") or 0),
                "total_earned_xof": float(count.get("earned") or 0),
                "bonus_paid_xof": 0,
                "rank": 0,
                "badge": "none",
                "created_at": datetime.now(timezone.utc),
                "updated_at": datetime.now(timezone.utc),
            }
        )

    stats_list.sort(
        key=lambda item: (
            -item["deliveries_success"],
            -item["success_rate"],
            -item["deliveries_total"],
            -item["total_earned_xof"],
            item["driver_id"],
        )
    )

    for index, stat in enumerate(stats_list):
        stat["rank"] = index + 1
        stat["badge"] = (
            "gold"
            if index == 0
            else "silver"
            if index == 1
            else "bronze"
            if index == 2
            else "none"
        )

    return stats_list


async def refresh_driver_stats_for_period(period: str) -> list[dict]:
    stats = await compute_driver_stats_for_period(period)
    now = datetime.now(timezone.utc)

    existing = await db.driver_stats.find(
        {"period": period},
        {"_id": 0, "driver_id": 1, "bonus_paid_xof": 1, "stat_id": 1, "created_at": 1},
    ).to_list(None)
    existing_by_driver = {item["driver_id"]: item for item in existing if item.get("driver_id")}

    for stat in stats:
        previous = existing_by_driver.get(stat["driver_id"])
        if previous:
            stat["stat_id"] = previous.get("stat_id", stat["stat_id"])
            stat["bonus_paid_xof"] = previous.get("bonus_paid_xof", stat["bonus_paid_xof"])
            stat["created_at"] = previous.get("created_at", stat["created_at"])
        stat["updated_at"] = now
        await db.driver_stats.update_one(
            {"driver_id": stat["driver_id"], "period": period},
            {"$set": stat},
            upsert=True,
        )

    return stats


async def pay_monthly_driver_bonuses(period: str):
    stats = await db.driver_stats.find({"period": period}).to_list(None)
    rewards = await get_performance_rewards_settings()
    driver_rewards = rewards["driver"]
    success_bonus = driver_rewards["success_bonus"]
    volume_bonuses = driver_rewards["volume_bonuses"]

    for stat in stats:
        bonus = 0
        driver_id = stat["driver_id"]
        total = stat["deliveries_success"]
        rate = stat["success_rate"]

        if (
            success_bonus.get("enabled")
            and rate >= success_bonus["min_success_rate"]
            and total >= success_bonus["min_deliveries"]
        ):
            bonus += success_bonus["amount_xof"]

        best_volume_bonus = 0
        for rule in volume_bonuses:
            if total >= rule["min_deliveries"]:
                best_volume_bonus = max(best_volume_bonus, rule["amount_xof"])
        bonus += best_volume_bonus

        if bonus <= 0:
            continue

        reference = f"monthly_driver_bonus:{period}:{driver_id}"
        existing = await db.wallet_transactions.find_one({"reference": reference}, {"_id": 0})
        if not existing:
            await credit_wallet(
                owner_id=driver_id,
                owner_type="driver",
                amount=bonus,
                description=f"Bonus performance livreur - {period}",
                reference=reference,
            )

        await db.driver_stats.update_one(
            {"stat_id": stat["stat_id"]},
            {"$set": {"bonus_paid_xof": bonus}},
        )


async def compute_relay_stats_and_pay_bonuses(period: str):
    rewards = await get_performance_rewards_settings()
    relay_volume_bonuses = rewards["relay"]["volume_bonuses"]
    year, month = map(int, period.split("-"))
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    _, last_day = monthrange(year, month)
    end = datetime(year, month, last_day, 23, 59, 59, tzinfo=timezone.utc)

    relays = await db.relay_points.find({"is_active": True}).to_list(None)
    for relay in relays:
        relay_id = relay["relay_id"]
        owner_id = relay.get("owner_user_id")
        if not owner_id:
            continue

        arrived = await db.parcels.count_documents(
            {
                "$or": [
                    {"origin_relay_id": relay_id, "status": {"$ne": "created"}},
                    {
                        "destination_relay_id": relay_id,
                        "status": {
                            "$in": [
                                "at_destination_relay",
                                "available_at_relay",
                                "delivered",
                            ]
                        },
                    },
                    {"redirect_relay_id": relay_id},
                ],
                "updated_at": {"$gte": start, "$lte": end},
            }
        )

        bonus = 0
        for rule in relay_volume_bonuses:
            if arrived >= rule["min_parcels"]:
                bonus = max(bonus, rule["amount_xof"])

        if bonus <= 0:
            continue

        reference = f"monthly_relay_bonus:{period}:{relay_id}:{owner_id}"
        existing = await db.wallet_transactions.find_one({"reference": reference}, {"_id": 0})
        if existing:
            continue

        await credit_wallet(
            owner_id=owner_id,
            owner_type="relay",
            amount=bonus,
            description=f"Bonus performance relais - {period} ({arrived} colis)",
            reference=reference,
        )
