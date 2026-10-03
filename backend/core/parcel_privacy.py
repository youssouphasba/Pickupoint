from copy import deepcopy

from core.utils import phones_match
from core.delivery_destination import effective_delivery_mode, effective_relay_id, effective_delivery_location


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
        mode = effective_delivery_mode(parcel)
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
    result = deepcopy(parcel)
    result["effective_delivery_mode"] = effective_delivery_mode(parcel)
    result["effective_destination_relay_id"] = effective_relay_id(parcel)
    if (result.get("delivery_destination") or {}).get("type") == "home":
        result["delivery_destination"]["address"] = deepcopy(effective_delivery_location(parcel))
    if result.get("delivery_destination"):
        address = effective_delivery_location(parcel)
        parts = list(dict.fromkeys(str(address[key]).strip() for key in ("district", "city") if address.get(key)))
        result["delivery_area_label"] = ", ".join(parts) or address.get("label")
    plan = deepcopy(result.get("recipient_collection_plan") or {})
    if plan:
        if result.get("payment_status") == "paid" or result.get("payment_override"):
            plan["status"] = "paid"
            plan["amount_due_xof"] = 0
        if viewer.get("role") not in {"admin", "superadmin"}:
            plan = {key: value for key, value in plan.items() if key in {"collector", "status", "amount_due_xof", "amount_received_xof", "revision"}}
        result["recipient_collection_plan"] = plan
    if viewer.get("role") not in {"admin", "superadmin"}:
        result.pop("destination_financial_review", None)
        remittances = result.pop("recipient_collection_remittances", None)
        relay_id = viewer.get("relay_point_id") if viewer.get("role") == "relay_agent" else None
        if remittances and relay_id in remittances:
            result["recipient_collection_remittances"] = {relay_id: remittances[relay_id]}
    return redact_codes(result, allowed_parcel_codes(parcel, viewer))
