from models.common import Address
from services.google_maps_service import geocode_address_suggestions, reverse_geocode


async def geocode_relay_address(address: Address) -> Address:
    if address.geopin is not None:
        if address.label and address.city:
            return address
        reverse_result = await reverse_geocode(address.geopin.lat, address.geopin.lng)
        if not reverse_result:
            return address
        address_data = address.model_dump()
        if not address_data.get("label"):
            address_data["label"] = reverse_result.get("formatted_address")
        if not address_data.get("city"):
            address_data["city"] = reverse_result.get("city")
        if not address_data.get("district"):
            address_data["district"] = reverse_result.get("district")
        return Address.model_validate(address_data)

    query = ", ".join(
        part
        for part in (address.label, address.district, address.city, address.notes)
        if part
    )
    if not query:
        return address

    suggestions = await geocode_address_suggestions(query, limit=1)
    if not suggestions:
        return address

    suggestion = suggestions[0]
    address_data = address.model_dump()
    address_data["geopin"] = {"lat": suggestion["lat"], "lng": suggestion["lng"]}
    if not address_data.get("label"):
        address_data["label"] = suggestion.get("label")
    if not address_data.get("city") and suggestion.get("subtitle"):
        address_data["city"] = suggestion["subtitle"].split(",", 1)[0]
    return Address.model_validate(address_data)
