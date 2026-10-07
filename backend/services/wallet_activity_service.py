from core.mission_privacy import serialize_mission
from services.wallet_service import get_or_create_wallet


async def wallet_activity(database, user, period_filter, *, category="balance", skip=0, limit=20):
    wallet = await get_or_create_wallet(user["user_id"], user.get("role", "client"))
    revenue_query = {"wallet_id": wallet["wallet_id"], "tx_type": "revenue", **period_filter}
    totals = await database.wallet_transactions.aggregate([
        {"$match": revenue_query},
        {"$group": {"_id": None, "amount": {"$sum": "$amount"}, "parcels": {"$addToSet": "$parcel_id"}}},
    ]).to_list(length=1)
    summary = totals[0] if totals else {}
    earnings = {"amount": float(summary.get("amount") or 0),
                "courses_count": len([value for value in summary.get("parcels", []) if value])}
    size = skip + limit
    if category == "revenues":
        rows = await database.wallet_transactions.find(revenue_query, {"_id": 0}).sort([("created_at", -1), ("tx_id", -1)]).skip(skip).limit(limit).to_list(length=limit)
        total = await database.wallet_transactions.count_documents(revenue_query)
        parcel_ids = [row.get("parcel_id") for row in rows if row.get("parcel_id")]
        missions = await database.delivery_missions.find(
            {"parcel_id": {"$in": parcel_ids}, "driver_id": user["user_id"], "status": "completed"},
            {"_id": 0, "mission_id": 1, "parcel_id": 1, "financial_rounding": 1, "financial_contract": 1},
        ).to_list(length=None) if parcel_ids else []
        by_parcel = {mission["parcel_id"]: mission["mission_id"] for mission in missions}
        financials = {mission["parcel_id"]: (mission.get("financial_contract") or {}).get("breakdown") or mission.get("financial_rounding") for mission in missions}
        items = [{**row, "kind": "revenue", "status": "recorded", "effect": 0,
                  "financial_rounding": financials.get(row.get("parcel_id")) if str(row.get("reference") or "").startswith("driver_revenue:") else None,
                  "mission_id": by_parcel.get(row.get("parcel_id"))} for row in rows]
    else:
        tx_query = {"wallet_id": wallet["wallet_id"], "tx_type": {"$ne": "revenue"},
                    "reference": {"$not": {"$regex": "^pay_"}}, **period_filter}
        payout_query = {"wallet_id": wallet["wallet_id"], "status": {"$in": ["approved", "rejected"]}, **period_filter}
        failed_topup_query = {"wallet_id": wallet["wallet_id"], "status": {"$in": ["failed", "expired"]}, **period_filter}
        transactions = await database.wallet_transactions.find(tx_query, {"_id": 0}).sort([("created_at", -1), ("tx_id", -1)]).limit(size).to_list(length=size)
        payouts = await database.payout_requests.find(payout_query, {"_id": 0}).sort([("created_at", -1), ("payout_id", -1)]).limit(size).to_list(length=size)
        topups = await database.wallet_topups.find(failed_topup_query, {"_id": 0}).sort([("created_at", -1), ("topup_id", -1)]).limit(size).to_list(length=size)
        items = [{**row, "kind": "transaction", "status": "recorded",
                  "effect": row["amount"] if row["tx_type"] == "credit" else -row["amount"]} for row in transactions]
        items.extend({"tx_id": payout["payout_id"], "kind": "payout", "amount": payout["amount"],
                      "effect": -payout["amount"] if payout["status"] == "approved" else 0,
                      "status": payout["status"], "description": "Retrait du solde", "method": payout.get("method"),
                      "rejection_reason": payout.get("rejection_reason"), "created_at": payout["created_at"]} for payout in payouts)
        items.extend({"tx_id": topup["topup_id"], "kind": "topup", "amount": topup["amount"], "effect": 0,
                      "status": topup["status"], "description": "Recharge par carte non créditée", "created_at": topup["created_at"]} for topup in topups)
        items.sort(key=lambda item: (item["created_at"], item["tx_id"]), reverse=True)
        items = items[skip:skip + limit]
        total = sum([await database.wallet_transactions.count_documents(tx_query),
                     await database.payout_requests.count_documents(payout_query),
                     await database.wallet_topups.count_documents(failed_topup_query)])
    pending_payouts = await database.payout_requests.find(
        {"wallet_id": wallet["wallet_id"], "status": "pending"}, {"_id": 0},
    ).sort("created_at", -1).to_list(length=None)
    pending_topups = await database.wallet_topups.find(
        {"wallet_id": wallet["wallet_id"], "status": "pending"}, {"_id": 0},
    ).sort("created_at", -1).to_list(length=None)
    return {"items": [serialize_mission(item, user) for item in items],
            "total": total, "skip": skip, "limit": limit, "earnings": earnings,
            "pending_payouts": pending_payouts,
            "pending_topups": [{key: row[key] for key in ("topup_id", "amount", "status", "created_at")} for row in pending_topups]}
