import logging
from calendar import monthrange
from datetime import datetime, timezone
from uuid import uuid4

from database import db
from services.wallet_service import credit_wallet

logger = logging.getLogger(__name__)


async def compute_driver_stats_for_period(period: str) -> list[dict]:
    year, month = map(int, period.split("-"))
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    _, last_day = monthrange(year, month)
    end = datetime(year, month, last_day, 23, 59, 59, tzinfo=timezone.utc)

    pipeline = [
        {
            "$match": {
                "completed_at": {"$gte": start, "$lte": end},
                "status": "completed",
            }
        },
        {
            "$group": {
                "_id": "$driver_id",
                "total_completed": {"$sum": 1},
                "earned": {"$sum": "$earn_amount"},
            }
        },
    ]

    mission_counts_pipeline = [
        {"$match": {"created_at": {"$gte": start, "$lte": end}}},
        {
            "$group": {
                "_id": "$driver_id",
                "total": {"$sum": 1},
                "success": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
            }
        },
    ]

    results = await db.delivery_missions.aggregate(pipeline).to_list(None)
    counts = await db.delivery_missions.aggregate(mission_counts_pipeline).to_list(None)
    counts_dict = {c["_id"]: c for c in counts if c["_id"]}

    stats_list = []
    for result in results:
        driver_id = result["_id"]
        if not driver_id:
            continue

        count = counts_dict.get(
            driver_id,
            {"total": result["total_completed"], "success": result["total_completed"]},
        )
        total = count["total"]
        success = count["success"]
        rate = round(success / max(total, 1) * 100, 1)

        stats_list.append(
            {
                "stat_id": f"stat_{uuid4().hex[:12]}",
                "driver_id": driver_id,
                "period": period,
                "deliveries_total": total,
                "deliveries_success": success,
                "success_rate": rate,
                "avg_rating": 0.0,
                "total_earned_xof": result["earned"],
                "bonus_paid_xof": 0,
                "rank": 0,
                "badge": "none",
                "created_at": datetime.now(timezone.utc),
                "updated_at": datetime.now(timezone.utc),
            }
        )

    stats_list.sort(key=lambda item: (-item["success_rate"], -item["deliveries_total"]))

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


async def pay_monthly_driver_bonuses(period: str):
    stats = await db.driver_stats.find({"period": period}).to_list(None)

    for stat in stats:
        bonus = 0
        driver_id = stat["driver_id"]
        total = stat["deliveries_success"]
        rate = stat["success_rate"]

        if rate >= 95 and total >= 20:
            bonus += 5000

        if total >= 200:
            bonus += 10000
        elif total >= 100:
            bonus += 5000
        elif total >= 50:
            bonus += 2500

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
        if arrived >= 50:
            bonus += 2000
        elif arrived >= 20:
            bonus += 1000

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
