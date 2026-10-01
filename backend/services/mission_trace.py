from datetime import datetime, timezone
from math import asin, cos, isfinite, radians, sin, sqrt

from config import settings
from database import db


def timestamp(value):
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    if not isinstance(value, datetime):
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


async def archive_position(mission_id, point, driver_id):
    await db.mission_gps_points.update_one(
        {"mission_id": mission_id, "ts": point["ts"], "driver_id": driver_id},
        {"$setOnInsert": {**point, "driver_id": driver_id}},
        upsert=True,
    )


async def load_trace(mission):
    start = timestamp(mission.get("assigned_at")) or timestamp(mission.get("started_at"))
    end = timestamp(mission.get("completed_at"))
    if start is None:
        return []
    points = await db.mission_gps_points.find(
        {"mission_id": mission["mission_id"]}, {"_id": 0}
    ).sort("ts", 1).to_list(length=None)
    unique = {}
    for point in [*(mission.get("gps_trail") or []), *points]:
        ts = timestamp(point.get("ts"))
        if ts is not None and ts >= start and (end is None or ts <= end):
            unique[(ts, point.get("lat"), point.get("lng"))] = {
                "driver_id": mission.get("driver_id"), **point, "ts": ts,
                "phase": "delivery" if timestamp(mission.get("started_at")) and ts >= timestamp(mission["started_at"]) else "approach",
            }
    return sorted(unique.values(), key=lambda point: point["ts"])


def summarize_trace(points):
    segments, gaps = [], []
    distance = 0.0
    previous = None
    for point in points:
        lat, lng = point.get("lat"), point.get("lng")
        ts = timestamp(point.get("ts"))
        if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
            previous = None
            continue
        if not isfinite(lat) or not isfinite(lng) or not (-90 <= lat <= 90 and -180 <= lng <= 180) or ts is None:
            previous = None
            continue
        gap = None
        meters = 0.0
        if previous:
            seconds = (ts - timestamp(previous["ts"])).total_seconds()
            a = sin(radians(lat - previous["lat"]) / 2) ** 2 + cos(radians(lat)) * cos(radians(previous["lat"])) * sin(radians(lng - previous["lng"]) / 2) ** 2
            meters = 6371000 * 2 * asin(sqrt(min(1, a)))
            if seconds > settings.GPS_TRACE_GAP_SECONDS:
                gap = "Interruption GPS"
            elif previous.get("driver_id") != point.get("driver_id"):
                gap = "Changement de livreur"
            elif meters > 0 and (seconds <= 0 or meters / seconds * 3.6 > settings.GPS_TRACE_MAX_SPEED_KMH):
                gap = "Positions incohérentes"
            if gap:
                gaps.append({"start": previous["ts"], "end": point["ts"], "reason": gap})
        if previous is None or gap:
            segments.append([])
        else:
            distance += meters
        segments[-1].append(point)
        previous = point
    return {"segments": segments, "gaps": gaps, "recorded_distance_meters": round(distance), "gap_threshold_seconds": settings.GPS_TRACE_GAP_SECONDS}


def summarize_completion(mission, points=None):
    assigned_at = timestamp(mission.get("assigned_at"))
    started_at = timestamp(mission.get("started_at"))
    completed_at = timestamp(mission.get("completed_at"))

    def elapsed_seconds(start, end):
        if start is None or end is None:
            return None
        return max(int((end - start).total_seconds()), 0)

    trace_summary = summarize_trace(points) if points is not None else None
    approach_distance = 0.0
    if trace_summary is not None:
        for segment in trace_summary["segments"]:
            for previous, point in zip(segment, segment[1:]):
                first, last = timestamp(previous["ts"]), timestamp(point["ts"])
                pair_distance = summarize_trace([previous, point])["recorded_distance_meters"]
                if started_at is None or last <= started_at:
                    approach_distance += pair_distance
                elif first < started_at and last > first:
                    approach_distance += pair_distance * (started_at - first).total_seconds() / (last - first).total_seconds()
    approach_distance = min(round(approach_distance), (trace_summary or {}).get("recorded_distance_meters", 0))
    return {
        "assigned_to_pickup_seconds": elapsed_seconds(assigned_at, started_at),
        "pickup_to_delivery_seconds": elapsed_seconds(started_at, completed_at),
        "total_duration_seconds": elapsed_seconds(assigned_at, completed_at),
        "recorded_distance_meters": (
            trace_summary["recorded_distance_meters"] if trace_summary is not None else None
        ),
        "gps_points_count": len(points) if points is not None else None,
        "approach_distance_meters": approach_distance if points is not None else None,
        "delivery_distance_meters": trace_summary["recorded_distance_meters"] - approach_distance if trace_summary is not None else None,
        "completed_at": completed_at,
    }
