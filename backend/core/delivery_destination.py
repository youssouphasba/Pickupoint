def effective_relay_id(parcel: dict):
    return parcel.get("redirect_relay_id") or parcel.get("destination_relay_id")


def effective_delivery_mode(parcel: dict) -> str:
    mode = str(parcel.get("delivery_mode") or parcel.get("mode") or "")
    if parcel.get("redirect_relay_id") and "_to_" in mode:
        return f"{mode.split('_to_')[0]}_to_relay"
    return mode


def effective_delivery_location(parcel: dict) -> dict:
    destination = parcel.get("delivery_destination") or {}
    if destination.get("type") == "relay" and destination.get("address"):
        return destination["address"]
    return parcel.get("delivery_location") or parcel.get("delivery_address") or {}
