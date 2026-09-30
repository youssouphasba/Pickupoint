from datetime import datetime, timedelta, timezone
from math import isfinite

from config import settings
from core.exceptions import bad_request_exception
from services.mission_trace import timestamp


def client_live_tracking_allowed(parcel, mission=None, *, is_recipient=False):
    mode = parcel.get("delivery_mode")
    if mode == "home_to_home":
        return True
    return bool(
        mode == "relay_to_home"
        and is_recipient
        and parcel.get("status") in {"in_transit", "out_for_delivery", "incident_reported"}
        and mission
        and mission.get("status") in {"in_progress", "incident_reported"}
        and mission.get("delivery_type") == "gps"
        and timestamp(mission.get("started_at")) is not None
        and not mission.get("completed_at")
    )


def location_captured_after_collection(mission):
    started_at = timestamp(mission.get("started_at"))
    captured_at = timestamp(mission.get("location_updated_at"))
    return started_at is not None and captured_at is not None and captured_at >= started_at


def validate_capture(accuracy, captured_at=None, *, now=None, historical=False, strict=False):
    now = now or datetime.now(timezone.utc)
    limit = settings.STRICT_GPS_MAX_ACCURACY_METERS if strict else settings.DRIVER_GPS_MAX_ACCURACY_METERS
    if accuracy is not None and (not isfinite(accuracy) or accuracy < 0 or accuracy > limit):
        raise bad_request_exception("Position GPS trop imprécise. Attendez une meilleure précision puis réessayez.")
    if strict and accuracy is None:
        raise bad_request_exception("Précision GPS indisponible. Actualisez votre position puis réessayez.")
    measured_at = timestamp(captured_at) if captured_at is not None else now
    if measured_at is None:
        raise bad_request_exception("Date de mesure GPS invalide.")
    max_age = timedelta(hours=settings.GPS_OFFLINE_BUFFER_HOURS) if historical else timedelta(seconds=settings.GPS_CAPTURE_MAX_AGE_SECONDS)
    if measured_at < now - max_age or measured_at > now + timedelta(seconds=settings.GPS_CLOCK_TOLERANCE_SECONDS):
        raise bad_request_exception("Position GPS périmée. Actualisez votre position puis réessayez.")
    return min(measured_at, now)


def location_is_live(location, captured_at, *, now=None, max_age_seconds=None):
    measured_at = timestamp(captured_at)
    if not isinstance(location, dict) or measured_at is None:
        return False
    if any(
        not isinstance(location.get(key), (int, float))
        or not isfinite(location[key])
        or abs(location[key]) > bound
        for key, bound in (("lat", 90), ("lng", 180))
    ):
        return False
    now = now or datetime.now(timezone.utc)
    age = (now - measured_at).total_seconds()
    accuracy = location.get("accuracy")
    return (
        -settings.GPS_CLOCK_TOLERANCE_SECONDS <= age <= (
            max_age_seconds if max_age_seconds is not None else settings.GPS_CAPTURE_MAX_AGE_SECONDS
        )
        and (accuracy is None or (isinstance(accuracy, (int, float)) and isfinite(accuracy)
                                 and 0 <= accuracy <= settings.DRIVER_GPS_MAX_ACCURACY_METERS))
    )
