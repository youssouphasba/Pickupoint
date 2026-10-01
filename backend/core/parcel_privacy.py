from copy import deepcopy

from core.utils import phones_match


PARCEL_CODES = {"pickup_code", "delivery_code", "relay_pin", "return_code", "pin_code",
                "sender_confirm_token", "recipient_confirm_token"}


def allowed_parcel_codes(parcel: dict, viewer: dict) -> set[str]:
    if viewer.get("role") in {"admin", "superadmin"}:
        return PARCEL_CODES.copy()
    user_id = viewer.get("user_id")
    sender = bool(user_id and parcel.get("sender_user_id") == user_id)
    recipient = bool(user_id and parcel.get("recipient_user_id") == user_id) or phones_match(
        parcel.get("recipient_phone"), viewer.get("phone"),
    )
    origin_relay = (
        viewer.get("role") == "relay_agent" and viewer.get("relay_point_id")
        and viewer["relay_point_id"] == parcel.get("origin_relay_id")
    )
    allowed = set()
    if sender or origin_relay:
        allowed.add("pickup_code")
    if sender:
        allowed.add("return_code")
        allowed.add("sender_confirm_token")
    if recipient:
        allowed.add("recipient_confirm_token")
        mode = str(parcel.get("delivery_mode") or "")
        if mode.endswith("_to_home"):
            allowed.add("delivery_code")
        elif mode.endswith("_to_relay"):
            allowed.add("relay_pin")
    return allowed


def redact_codes(value, allowed: set[str]):
    if isinstance(value, dict):
        return {key: redact_codes(item, allowed) for key, item in value.items()
                if key not in PARCEL_CODES or key in allowed}
    if isinstance(value, list):
        return [redact_codes(item, allowed) for item in value]
    return value


def serialize_parcel(parcel: dict, viewer: dict) -> dict:
    return redact_codes(deepcopy(parcel), allowed_parcel_codes(parcel, viewer))
