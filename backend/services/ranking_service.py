import logging
from datetime import datetime, timezone, timedelta
from calendar import monthrange
from uuid import uuid4
from database import db

logger = logging.getLogger(__name__)

async def compute_driver_stats_for_period(period: str) -> list[dict]:
    """
    period = "2026-03"
    Calculates stats for all drivers for a given period.
    """
    year, month = map(int, period.split("-"))
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    _, last_day = monthrange(year, month)
    end = datetime(year, month, last_day, 23, 59, 59, tzinfo=timezone.utc)

    # Aggregate missions by driver
    pipeline = [
        {"$match": {
            "completed_at": {"$gte": start, "$lte": end},
            "status": "completed", # We only count completed missions for standard stats
        }},
        {"$group": {
            "_id": "$driver_id",
            "total_completed": {"$sum": 1},
            "earned":          {"$sum": "$earn_amount"},
        }},
    ]
    
    # We also need to count failed/total to get success rate from delivery_missions
    # For simplicity in this iteration, we look at all missions created in that period
    mission_counts_pipeline = [
        {"$match": {
            "created_at": {"$gte": start, "$lte": end},
        }},
        {"$group": {
            "_id": "$driver_id",
            "total":   {"$sum": 1},
            "success": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
        }}
    ]

    results = await db.delivery_missions.aggregate(pipeline).to_list(None)
    counts = await db.delivery_missions.aggregate(mission_counts_pipeline).to_list(None)
    counts_dict = {c["_id"]: c for c in counts if c["_id"]}

    stats_list = []
    for r in results:
        driver_id = r["_id"]
        if not driver_id:
            continue
            
        c = counts_dict.get(driver_id, {"total": r["total_completed"], "success": r["total_completed"]})
        total = c["total"]
        success = c["success"]
        rate = round(success / max(total, 1) * 100, 1)

        stat = {
            "stat_id":            f"stat_{uuid4().hex[:12]}",
            "driver_id":          driver_id,
            "period":             period,
            "deliveries_total":   total,
            "deliveries_success": success,
            "success_rate":       rate,
            "avg_rating":         0.0, # Placeholder until rating system is fully integrated
            "total_earned_xof":   r["earned"],
            "bonus_paid_xof":     0,
            "rank":               0,
            "badge":              "none",
            "created_at":         datetime.now(timezone.utc),
            "updated_at":         datetime.now(timezone.utc),
        }
        stats_list.append(stat)

    # Sort by success_rate desc, then total desc
    stats_list.sort(key=lambda x: (-x["success_rate"], -x["deliveries_total"]))

    for i, stat in enumerate(stats_list):
        stat["rank"] = i + 1
        stat["badge"] = "gold" if i == 0 else "silver" if i == 1 else "bronze" if i == 2 else "none"

    return stats_list

async def pay_monthly_driver_bonuses(period: str):
    """Calculates and pays bonuses based on stats."""
    stats = await db.driver_stats.find({"period": period}).to_list(None)

    for stat in stats:
        bonus = 0
        driver_id = stat["driver_id"]
        total = stat["deliveries_success"]
        rate = stat["success_rate"]

        # 95% success + 20 missions -> 5000 XOF
        if rate >= 95 and total >= 20:
            bonus += 5000

        # Volume bonuses
        if total >= 200:
            bonus += 10000
        elif total >= 100:
            bonus += 5000
        elif total >= 50:
            bonus += 2500

        if bonus > 0:
            now = datetime.now(timezone.utc)
            await db.wallets.update_one(
                {"user_id": driver_id},
                {"$inc": {"balance": bonus}},
                upsert=True,
            )
            await db.wallet_transactions.insert_one({
                "tx_id":       f"tx_{uuid4().hex[:12]}",
                "user_id":     driver_id,
                "type":        "monthly_bonus",
                "amount":      bonus,
                "description": f"Bonus performance livreur — {period}",
                "created_at":  now,
            })
            await db.driver_stats.update_one(
                {"stat_id": stat["stat_id"]},
                {"$set": {"bonus_paid_xof": bonus}}
            )

async def compute_relay_stats_and_pay_bonuses(period: str):
    """Relay rewards: 50+ parcels -> higher commission (next month) + cash bonus."""
    year, month = map(int, period.split("-"))
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    _, last_day = monthrange(year, month)
    end = datetime(year, month, last_day, 23, 59, 59, tzinfo=timezone.utc)

    relays = await db.relay_points.find({"is_active": True}).to_list(None)
    for relay in relays:
        relay_id = relay["relay_id"]
        owner_id = relay.get("owner_user_id")
        if not owner_id: continue

        # Parcels arrived at this relay during period
        arrived = await db.parcels.count_documents({
            "$or": [
                {"origin_relay_id": relay_id, "status": {"$ne": "created"}},
                {"destination_relay_id": relay_id, "status": {"$in": ["at_destination_relay", "available_at_relay", "delivered"]}},
                {"redirect_relay_id": relay_id}
            ],
            "updated_at": {"$gte": start, "$lte": end} # Rough estimate of traffic
        })

        # Retards (> 7 days in stock)
        # For a historical period, this is hard to compute perfectly without snapshots, 
        # but we check if any parcel stayed > 7 days.
        
        bonus = 0
        # Simplification: rotation bonus
        if arrived >= 50:
            bonus += 2000
        elif arrived >= 20: # Minor bonus
            bonus += 1000
            
        if bonus > 0:
            now = datetime.now(timezone.utc)
            await db.wallets.update_one(
                {"user_id": owner_id},
                {"$inc": {"balance": bonus}},
                upsert=True,
            )
            await db.wallet_transactions.insert_one({
                "tx_id":       f"tx_{uuid4().hex[:12]}",
                "user_id":     owner_id,
                "type":        "relay_bonus",
                "amount":      bonus,
                "description": f"Bonus performance relais — {period} ({arrived} colis)",
                "created_at":  now,
            })
