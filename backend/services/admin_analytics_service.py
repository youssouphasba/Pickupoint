from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta, timezone
from math import asin, cos, radians, sin, sqrt
from typing import Any

from database import db


def _dt(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            return None
    return None


def _seconds(start: Any, end: Any) -> int | None:
    first = _dt(start)
    last = _dt(end)
    if not first or not last:
        return None
    value = int((last - first).total_seconds())
    return value if value >= 0 else None


def _stats(values: list[int]) -> dict[str, int | None]:
    if not values:
        return {"sample_count": 0, "average_seconds": None, "median_seconds": None, "p90_seconds": None, "fastest_seconds": None, "slowest_seconds": None}
    ordered = sorted(values)
    median = ordered[(len(ordered) - 1) // 2]
    p90 = ordered[min(len(ordered) - 1, int(len(ordered) * 0.9))]
    return {
        "sample_count": len(values),
        "average_seconds": round(sum(values) / len(values)),
        "median_seconds": median,
        "p90_seconds": p90,
        "fastest_seconds": ordered[0],
        "slowest_seconds": ordered[-1],
    }


def _round_amount(value: Any) -> float:
    try:
        return round(float(value or 0), 2)
    except (TypeError, ValueError):
        return 0.0


def _distance_km(points: Any) -> float | None:
    if not isinstance(points, list) or len(points) < 2:
        return None
    total = 0.0
    valid = 0
    previous = None
    for point in points:
        if not isinstance(point, dict):
            continue
        try:
            current = (float(point["lat"]), float(point["lng"]))
        except (KeyError, TypeError, ValueError):
            continue
        if previous:
            lat1, lon1 = map(radians, previous)
            lat2, lon2 = map(radians, current)
            delta_lat = lat2 - lat1
            delta_lon = lon2 - lon1
            value = 2 * 6371 * asin(sqrt(sin(delta_lat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(delta_lon / 2) ** 2))
            if value < 20:
                total += value
                valid += 1
        previous = current
    return round(total, 2) if valid else None


def _duration_seconds(values: list[int]) -> dict[str, int | None]:
    return _stats(values)


async def build_admin_analytics(start: datetime, end: datetime) -> dict[str, Any]:
    date_query = {"$gte": start, "$lte": end}
    parcels = await db.parcels.find(
        {"created_at": date_query},
        {
            "_id": 0,
            "parcel_id": 1,
            "delivery_mode": 1,
            "status": 1,
            "paid_price": 1,
            "quoted_price": 1,
            "sender_user_id": 1,
            "origin_relay_id": 1,
            "destination_relay_id": 1,
            "redirect_relay_id": 1,
            "transit_relay_id": 1,
            "created_at": 1,
            "updated_at": 1,
            "paid_at": 1,
        },
    ).to_list(length=10000)
    parcel_by_id = {p.get("parcel_id"): p for p in parcels if p.get("parcel_id")}

    missions = await db.delivery_missions.find(
        {
            "$or": [
                {"created_at": date_query},
                {"completed_at": date_query},
            ]
        },
        {
            "_id": 0,
            "mission_id": 1,
            "parcel_id": 1,
            "driver_id": 1,
            "status": 1,
            "assigned_at": 1,
            "dispatch_started_at": 1,
            "started_at": 1,
            "completed_at": 1,
            "gps_trail": 1,
            "eta_seconds": 1,
            "eta_updated_at": 1,
            "earn_amount": 1,
            "platform_commission_xof": 1,
            "relay_commission_xof": 1,
            "origin_relay_commission_xof": 1,
            "destination_relay_commission_xof": 1,
        },
    ).to_list(length=10000)

    delivered = sum(1 for p in parcels if p.get("status") == "delivered")
    failed = sum(1 for p in parcels if p.get("status") == "delivery_failed")
    cancelled = sum(1 for p in parcels if p.get("status") == "cancelled")
    terminal = delivered + failed + cancelled
    gross_revenue = sum(_round_amount(p.get("paid_price") or p.get("quoted_price")) for p in parcels if p.get("status") == "delivered")

    duration_values: list[int] = []
    before_pickup_values: list[int] = []
    delivery_values: list[int] = []
    acceptance_values: list[int] = []
    distance_values: list[float] = []
    eta_samples = 0
    by_mode: dict[str, dict[str, Any]] = defaultdict(lambda: {"parcels": 0, "delivered": 0, "failed": 0, "cancelled": 0, "gross_revenue_xof": 0.0, "duration": [], "distance_km": []})
    mode_durations: dict[str, list[int]] = defaultdict(list)
    for parcel in parcels:
        mode = str(parcel.get("delivery_mode") or "unknown")
        row = by_mode[mode]
        row["parcels"] += 1
        row["delivered"] += int(parcel.get("status") == "delivered")
        row["failed"] += int(parcel.get("status") == "delivery_failed")
        row["cancelled"] += int(parcel.get("status") == "cancelled")
        if parcel.get("status") == "delivered":
            row["gross_revenue_xof"] += _round_amount(parcel.get("paid_price") or parcel.get("quoted_price"))

    driver_data: dict[str, dict[str, Any]] = defaultdict(lambda: {"missions": 0, "completed": 0, "failed": 0, "duration": [], "before_pickup": [], "delivery": [], "acceptance": [], "distance_km": [], "earned_xof": 0.0})
    for mission in missions:
        driver_id = mission.get("driver_id")
        if not driver_id:
            continue
        row = driver_data[driver_id]
        row["missions"] += 1
        row["completed"] += int(mission.get("status") == "completed")
        row["failed"] += int(mission.get("status") == "failed")
        row["earned_xof"] += _round_amount(mission.get("earn_amount"))
        before = _seconds(mission.get("assigned_at"), mission.get("started_at"))
        acceptance = _seconds(mission.get("dispatch_started_at"), mission.get("assigned_at"))
        delivery = _seconds(mission.get("started_at"), mission.get("completed_at"))
        total = _seconds(mission.get("assigned_at"), mission.get("completed_at"))
        distance = _distance_km(mission.get("gps_trail"))
        if mission.get("eta_seconds") is not None:
            eta_samples += 1
        if acceptance is not None:
            row["acceptance"].append(acceptance)
            acceptance_values.append(acceptance)
        if before is not None:
            row["before_pickup"].append(before)
            before_pickup_values.append(before)
        if delivery is not None:
            row["delivery"].append(delivery)
            delivery_values.append(delivery)
        if total is not None:
            row["duration"].append(total)
            duration_values.append(total)
            parcel = parcel_by_id.get(mission.get("parcel_id")) or {}
            mode_durations[str(parcel.get("delivery_mode") or "unknown")].append(total)
            by_mode[str(parcel.get("delivery_mode") or "unknown")]["duration"].append(total)
        if distance is not None:
            row["distance_km"].append(distance)
            distance_values.append(distance)
            by_mode[str((parcel_by_id.get(mission.get("parcel_id")) or {}).get("delivery_mode") or "unknown")]["distance_km"].append(distance)

    driver_ids = list(driver_data)
    driver_docs = await db.users.find(
        {"user_id": {"$in": driver_ids}},
        {"_id": 0, "user_id": 1, "name": 1, "full_name": 1, "phone": 1},
    ).to_list(length=len(driver_ids)) if driver_ids else []
    driver_names = {d["user_id"]: (d.get("full_name") or d.get("name") or d.get("phone") or d["user_id"]) for d in driver_docs}
    security_rows = await db.admin_events.find(
        {"event_type": "security_gps_blocked", "created_at": date_query},
        {"_id": 0, "metadata": 1},
    ).to_list(length=10000)
    security_by_driver: dict[str, int] = defaultdict(int)
    for event in security_rows:
        driver_id = (event.get("metadata") or {}).get("driver_id")
        if driver_id:
            security_by_driver[driver_id] += 1

    driver_stats = []
    for driver_id, row in driver_data.items():
        completed_or_failed = row["completed"] + row["failed"]
        driver_stats.append({
            "driver_id": driver_id,
            "name": driver_names.get(driver_id, driver_id),
            "missions": row["missions"],
            "completed": row["completed"],
            "failed": row["failed"],
            "success_rate": round(row["completed"] / completed_or_failed * 100, 1) if completed_or_failed else 0,
            "earned_xof": round(row["earned_xof"], 2),
            "average_before_pickup_seconds": _stats(row["before_pickup"])["average_seconds"],
            "average_delivery_seconds": _stats(row["delivery"])["average_seconds"],
            "average_total_seconds": _stats(row["duration"])["average_seconds"],
            "average_acceptance_seconds": _stats(row["acceptance"])["average_seconds"],
            "average_distance_km": round(sum(row["distance_km"]) / len(row["distance_km"]), 2) if row["distance_km"] else None,
            "earnings_per_hour_xof": round(row["earned_xof"] / (sum(row["duration"]) / 3600), 2) if row["duration"] and sum(row["duration"]) else None,
            "security_blocks": security_by_driver.get(driver_id, 0),
        })
    driver_stats.sort(key=lambda item: (-item["completed"], -item["success_rate"], item["name"]))

    relay_ids = set()
    for parcel in parcels:
        relay_ids.update(parcel.get(key) for key in ("origin_relay_id", "destination_relay_id", "redirect_relay_id", "transit_relay_id") if parcel.get(key))
    relay_docs = await db.relay_points.find(
        {"relay_id": {"$in": list(relay_ids)}},
        {"_id": 0, "relay_id": 1, "name": 1, "current_load": 1, "max_capacity": 1},
    ).to_list(length=len(relay_ids)) if relay_ids else []
    relay_stats = []
    for relay in relay_docs:
        relay_id = relay["relay_id"]
        related = [p for p in parcels if relay_id in {p.get("origin_relay_id"), p.get("destination_relay_id"), p.get("redirect_relay_id"), p.get("transit_relay_id")}]
        relay_stats.append({
            "relay_id": relay_id,
            "name": relay.get("name") or relay_id,
            "processed": len(related),
            "delivered": sum(1 for p in related if p.get("status") == "delivered"),
            "current_load": int(relay.get("current_load") or 0),
            "max_capacity": relay.get("max_capacity"),
            "occupancy_rate": round(int(relay.get("current_load") or 0) / float(relay["max_capacity"]) * 100, 1) if relay.get("max_capacity") else None,
        })
    relay_stats.sort(key=lambda item: (-item["processed"], item["name"]))

    payout_docs = await db.payout_requests.find({"created_at": date_query}, {"_id": 0, "status": 1, "amount": 1, "created_at": 1}).to_list(length=10000)
    payouts = defaultdict(lambda: {"count": 0, "amount_xof": 0.0})
    for payout in payout_docs:
        status = str(payout.get("status") or "unknown")
        payouts[status]["count"] += 1
        payouts[status]["amount_xof"] += _round_amount(payout.get("amount"))

    pending_payout_ages = [_seconds(payout.get("created_at"), datetime.now(timezone.utc)) for payout in payout_docs if str(payout.get("status") or "") in {"pending", "processing"}]
    client_counts: dict[str, int] = defaultdict(int)
    for parcel in parcels:
        if parcel.get("sender_user_id"):
            client_counts[parcel["sender_user_id"]] += 1
    returning_clients = sum(1 for count in client_counts.values() if count >= 2)
    new_clients = sum(1 for count in client_counts.values() if count == 1)
    average_client_spend = round(gross_revenue / len(client_counts), 2) if client_counts else 0.0

    event_docs = await db.parcel_events.find(
        {"parcel_id": {"$in": list(parcel_by_id)}, "created_at": date_query},
        {"_id": 0, "parcel_id": 1, "event_type": 1, "to_status": 1, "created_at": 1, "actor_id": 1},
    ).sort("created_at", 1).to_list(length=30000) if parcel_by_id else []
    declined_count = sum(1 for event in event_docs if event.get("event_type") == "MISSION_DECLINED")
    relay_dwell_values: list[int] = []
    events_by_parcel: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for event in event_docs:
        events_by_parcel[event.get("parcel_id")].append(event)
    for parcel_events in events_by_parcel.values():
        for index, event in enumerate(parcel_events):
            if event.get("to_status") not in {"dropped_at_origin_relay", "at_destination_relay", "available_at_relay", "redirected_to_relay"}:
                continue
            for following in parcel_events[index + 1:]:
                elapsed = _seconds(event.get("created_at"), following.get("created_at"))
                if elapsed is not None:
                    relay_dwell_values.append(elapsed)
                    break

    status_funnel = {
        "created": len(parcels),
        "assigned": sum(1 for mission in missions if mission.get("assigned_at")),
        "accepted": sum(1 for event in event_docs if event.get("event_type") == "MISSION_ACCEPTED"),
        "picked_up": sum(1 for mission in missions if mission.get("started_at")),
        "delivered": delivered,
    }
    by_mode_payload = {}
    for mode, row in by_mode.items():
        terminal_for_mode = row["delivered"] + row["failed"] + row["cancelled"]
        by_mode_payload[mode] = {
            key: value for key, value in row.items() if key not in {"duration", "distance_km"}
        }
        by_mode_payload[mode]["success_rate"] = round(row["delivered"] / terminal_for_mode * 100, 1) if terminal_for_mode else 0
        by_mode_payload[mode]["duration"] = _stats(row["duration"])
        by_mode_payload[mode]["average_distance_km"] = round(sum(row["distance_km"]) / len(row["distance_km"]), 2) if row["distance_km"] else None

    daily: dict[str, dict[str, int]] = defaultdict(lambda: {"created": 0, "delivered": 0, "failed": 0})
    for parcel in parcels:
        created = _dt(parcel.get("created_at"))
        if not created:
            continue
        key = created.date().isoformat()
        daily[key]["created"] += 1
        daily[key]["delivered"] += int(parcel.get("status") == "delivered")
        daily[key]["failed"] += int(parcel.get("status") == "delivery_failed")

    return {
        "period": {"from": start, "to": end},
        "overview": {
            "parcels": len(parcels),
            "delivered": delivered,
            "failed": failed,
            "cancelled": cancelled,
            "terminal": terminal,
            "success_rate": round(delivered / terminal * 100, 1) if terminal else 0,
            "gross_revenue_xof": round(gross_revenue, 2),
            "active_drivers": len(driver_data),
            "active_relays": len(relay_docs),
            "clients": len(client_counts),
            "returning_clients": returning_clients,
            "security_blocks": len(security_rows),
            "new_clients": new_clients,
            "acceptance_rate": round(status_funnel["accepted"] / len(parcels) * 100, 1) if parcels else 0,
            "average_client_spend_xof": average_client_spend,
            "average_distance_km": round(sum(distance_values) / len(distance_values), 2) if distance_values else None,
            "eta_samples": eta_samples,
        },
        "durations": {
            "before_pickup": _stats(before_pickup_values),
            "delivery": _stats(delivery_values),
            "total": _stats(duration_values),
            "by_mode": {mode: _stats(values) for mode, values in mode_durations.items()},
            "acceptance": _duration_seconds(acceptance_values),
            "relay_dwell": _duration_seconds(relay_dwell_values),
            "distance_km": {"sample_count": len(distance_values), "average": round(sum(distance_values) / len(distance_values), 2) if distance_values else None, "fastest": min(distance_values) if distance_values else None, "longest": max(distance_values) if distance_values else None},
        },
        "by_mode": by_mode_payload,
        "funnel": status_funnel,
        "operations": {
            "declined_missions": declined_count,
            "failure_rate": round(failed / len(parcels) * 100, 1) if parcels else 0,
            "cancellation_rate": round(cancelled / len(parcels) * 100, 1) if parcels else 0,
            "eta_samples": eta_samples,
        },
        "clients": {
            "active": len(client_counts),
            "new": new_clients,
            "returning": returning_clients,
            "repeat_rate": round(returning_clients / len(client_counts) * 100, 1) if client_counts else 0,
            "average_spend_xof": average_client_spend,
        },
        "drivers": driver_stats,
        "relays": relay_stats,
        "finance": {
            "payouts": dict(payouts),
            "platform_commission_xof": round(sum(_round_amount(m.get("platform_commission_xof")) for m in missions if m.get("status") == "completed"), 2),
            "driver_commission_xof": round(sum(_round_amount(m.get("earn_amount")) for m in missions if m.get("status") == "completed"), 2),
            "relay_commission_xof": round(sum(
                _round_amount(m.get("relay_commission_xof"))
                + _round_amount(m.get("origin_relay_commission_xof"))
                + _round_amount(m.get("destination_relay_commission_xof"))
                for m in missions
                if m.get("status") == "completed"
            ), 2),
            "pending_age": _stats([value for value in pending_payout_ages if value is not None]),
        },
        "daily": [{"date": date, **values} for date, values in sorted(daily.items())],
    }
