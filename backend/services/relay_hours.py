from datetime import datetime, time, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo
import re


try:
    RELAY_TIMEZONE = ZoneInfo("Africa/Dakar")
except Exception:
    RELAY_TIMEZONE = timezone(timedelta(hours=0))
RELAY_DAYS = (
    ("monday", "Lundi"),
    ("tuesday", "Mardi"),
    ("wednesday", "Mercredi"),
    ("thursday", "Jeudi"),
    ("friday", "Vendredi"),
    ("saturday", "Samedi"),
    ("sunday", "Dimanche"),
)

_DAY_ALIASES = {
    "mon": "monday", "lun": "monday", "lundi": "monday",
    "tue": "tuesday", "mar": "tuesday", "mardi": "tuesday",
    "wed": "wednesday", "mer": "wednesday", "mercredi": "wednesday",
    "thu": "thursday", "jeu": "thursday", "jeudi": "thursday",
    "fri": "friday", "ven": "friday", "vendredi": "friday",
    "sat": "saturday", "sam": "saturday", "samedi": "saturday",
    "sun": "sunday", "dim": "sunday", "dimanche": "sunday",
}


def _parse_time(value: Any) -> time | None:
    if not isinstance(value, str):
        return None
    match = re.fullmatch(r"\s*(\d{1,2})(?::|h)?(\d{2})?\s*", value.lower())
    if not match:
        return None
    hour = int(match.group(1))
    minute = int(match.group(2) or 0)
    if hour > 23 or minute > 59:
        return None
    return time(hour, minute)


def _parse_range(value: Any) -> tuple[time, time] | None:
    if not isinstance(value, str):
        return None
    match = re.search(
        r"(\d{1,2}(?::|h)?\d{0,2})\s*[-–]\s*(\d{1,2}(?::|h)?\d{0,2})",
        value.lower(),
    )
    if not match:
        return None
    start = _parse_time(match.group(1))
    end = _parse_time(match.group(2))
    return (start, end) if start and end else None


def _legacy_days(value: str) -> set[str]:
    normalized = value.casefold()
    if "lun-sam" in normalized or "lun–sam" in normalized:
        return {day for day, _ in RELAY_DAYS[:-1]}
    if "lun-ven" in normalized or "lun–ven" in normalized:
        return {day for day, _ in RELAY_DAYS[:5]}
    return {day for day, _ in RELAY_DAYS}


def normalize_opening_hours(value: Any) -> Any:
    if not isinstance(value, dict):
        return value if isinstance(value, str) and value.strip() else None

    normalized: dict[str, Any] = {}
    general = value.get("general")
    if isinstance(general, str) and general.strip():
        parsed = _parse_range(general)
        if parsed:
            start, end = parsed
            for day in _legacy_days(general):
                normalized[day] = {
                    "enabled": True,
                    "open": start.strftime("%H:%M"),
                    "close": end.strftime("%H:%M"),
                }

    for key, raw in value.items():
        day = _DAY_ALIASES.get(str(key).casefold(), str(key).casefold())
        if day not in {item[0] for item in RELAY_DAYS}:
            continue
        if isinstance(raw, dict):
            enabled = bool(raw.get("enabled", True))
            start = _parse_time(raw.get("open"))
            end = _parse_time(raw.get("close"))
            normalized[day] = {
                "enabled": enabled and start is not None and end is not None,
                "open": start.strftime("%H:%M") if start else "",
                "close": end.strftime("%H:%M") if end else "",
            }
        elif isinstance(raw, str):
            parsed = _parse_range(raw)
            normalized[day] = (
                {
                    "enabled": True,
                    "open": parsed[0].strftime("%H:%M"),
                    "close": parsed[1].strftime("%H:%M"),
                }
                if parsed
                else {"enabled": False, "open": "", "close": ""}
            )

    return normalized or None


def relay_open_status(relay: dict, now: datetime | None = None) -> dict[str, Any]:
    raw = relay.get("opening_hours")
    if not raw:
        return {"is_open": True, "known": False, "label": "Horaires non renseignés"}

    local_now = (now or datetime.now(timezone.utc)).astimezone(RELAY_TIMEZONE)
    schedule = normalize_opening_hours(raw)
    if isinstance(schedule, str):
        parsed = _parse_range(schedule)
        if not parsed:
            return {"is_open": True, "known": False, "label": schedule}
        day_key, day_label = RELAY_DAYS[local_now.weekday()]
        if day_key not in _legacy_days(schedule):
            return {"is_open": False, "known": True, "label": f"Fermé le {day_label}"}
        start, end = parsed
        is_open = _is_between(local_now.time(), start, end)
        return {
            "is_open": is_open,
            "known": True,
            "label": f"{start.strftime('%H:%M')}–{end.strftime('%H:%M')}",
        }

    day_key, day_label = RELAY_DAYS[local_now.weekday()]
    entry = (schedule or {}).get(day_key)
    if not isinstance(entry, dict) or not entry.get("enabled"):
        return {"is_open": False, "known": True, "label": f"Fermé le {day_label}"}
    start = _parse_time(entry.get("open"))
    end = _parse_time(entry.get("close"))
    if not start or not end:
        return {"is_open": False, "known": True, "label": f"Fermé le {day_label}"}
    is_open = _is_between(local_now.time(), start, end)
    return {
        "is_open": is_open,
        "known": True,
        "label": f"Ouvert {start.strftime('%H:%M')}–{end.strftime('%H:%M')}" if is_open else f"Fermé jusqu'à {start.strftime('%H:%M')}",
    }


def _is_between(current: time, start: time, end: time) -> bool:
    if start <= end:
        return start <= current <= end
    return current >= start or current <= end
