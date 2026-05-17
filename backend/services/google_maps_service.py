import httpx
import logging
import hashlib
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)

from config import settings

GOOGLE_DIRECTIONS_API_URL = "https://maps.googleapis.com/maps/api/directions/json"
GOOGLE_GEOCODE_API_URL = "https://maps.googleapis.com/maps/api/geocode/json"


def _api_key() -> str:
    return str(settings.GOOGLE_DIRECTIONS_API_KEY or "").strip()


def _api_key_fingerprint(api_key: str) -> str:
    if not api_key:
        return "missing"
    digest = hashlib.sha256(api_key.encode("utf-8")).hexdigest()[:10]
    return f"sha256:{digest}/len:{len(api_key)}/last4:{api_key[-4:]}"

async def get_directions_eta(origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float) -> Optional[Dict]:
    api_key = _api_key()
    if not api_key:
        logger.warning("GOOGLE_DIRECTIONS_API_KEY not set — skipping Directions API call")
        return None
    """
    Appelle l'API Google Directions pour obtenir la durée estimée et la distance.
    """
    params = {
        "origin": f"{origin_lat},{origin_lng}",
        "destination": f"{dest_lat},{dest_lng}",
        "mode": "driving",
        "key": api_key
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(GOOGLE_DIRECTIONS_API_URL, params=params)
            response.raise_for_status()
            data = response.json()
            
            if data.get("status") == "OK":
                route = data["routes"][0]["legs"][0]
                return {
                    "duration_seconds": route["duration"]["value"],
                    "duration_text": route["duration"]["text"],
                    "distance_meters": route["distance"]["value"],
                    "distance_text": route["distance"]["text"],
                    "encoded_polyline": data["routes"][0]["overview_polyline"]["points"],
                }
            else:
                logger.error(
                    "Google Directions API error: %s - %s (key=%s)",
                    data.get("status"),
                    data.get("error_message"),
                    _api_key_fingerprint(api_key),
                )
                return None
    except Exception as e:
        logger.error("Failed to call Google Directions API with key=%s: %s", _api_key_fingerprint(api_key), e)
        return None


def _component_value(components: list[dict], *types: str) -> Optional[str]:
    for component in components:
        component_types = component.get("types") or []
        if any(t in component_types for t in types):
            value = component.get("long_name")
            if isinstance(value, str) and value.strip():
                return value.strip()
    return None


async def reverse_geocode(lat: float, lng: float) -> Optional[Dict]:
    api_key = _api_key()
    if not api_key:
        logger.info("GOOGLE_DIRECTIONS_API_KEY not set — skipping reverse geocoding")
        return None

    params = {
        "latlng": f"{lat},{lng}",
        "language": "fr",
        "key": api_key,
    }

    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.get(GOOGLE_GEOCODE_API_URL, params=params)
            response.raise_for_status()
            data = response.json()

        if data.get("status") != "OK" or not data.get("results"):
            logger.warning(
                "Google Geocoding API error: %s - %s (key=%s)",
                data.get("status"),
                data.get("error_message"),
                _api_key_fingerprint(api_key),
            )
            return None

        result = data["results"][0]
        components = result.get("address_components") or []
        city = (
            _component_value(components, "locality", "postal_town")
            or _component_value(components, "administrative_area_level_2")
            or _component_value(components, "administrative_area_level_1")
        )
        district = _component_value(
            components,
            "sublocality",
            "sublocality_level_1",
            "neighborhood",
        )
        country = _component_value(components, "country")
        formatted = result.get("formatted_address")

        return {
            "formatted_address": formatted.strip() if isinstance(formatted, str) else None,
            "city": city,
            "district": district,
            "country": country,
            "place_id": result.get("place_id"),
            "source": "google_reverse_geocode",
        }
    except Exception as e:
        logger.warning("Failed to reverse geocode GPS position: %s", e)
        return None


def _suggestion_from_geocode_result(result: dict[str, Any]) -> Optional[dict[str, Any]]:
    geometry = result.get("geometry") or {}
    location = geometry.get("location") or {}
    lat = location.get("lat")
    lng = location.get("lng")
    formatted = result.get("formatted_address")
    if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
        return None
    if not isinstance(formatted, str) or not formatted.strip():
        return None

    components = result.get("address_components") or []
    city = (
        _component_value(components, "locality", "postal_town")
        or _component_value(components, "administrative_area_level_2")
        or _component_value(components, "administrative_area_level_1")
    )
    country = _component_value(components, "country")
    label = formatted.strip()
    subtitle_parts = [value for value in (city, country) if value]

    return {
        "label": label,
        "subtitle": ", ".join(subtitle_parts) if subtitle_parts else None,
        "lat": float(lat),
        "lng": float(lng),
        "place_id": result.get("place_id"),
        "source": "google_geocode",
    }


async def geocode_address_suggestions(
    query: str,
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    limit: int = 6,
) -> list[dict[str, Any]]:
    api_key = _api_key()
    if not api_key:
        logger.info("GOOGLE_DIRECTIONS_API_KEY not set — skipping address suggestions")
        return []

    cleaned_query = query.strip()
    if len(cleaned_query) < 3:
        return []

    params: dict[str, Any] = {
        "address": cleaned_query,
        "language": "fr",
        "key": api_key,
    }
    if lat is not None and lng is not None:
        params["bounds"] = f"{lat - 0.5},{lng - 0.5}|{lat + 0.5},{lng + 0.5}"

    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.get(GOOGLE_GEOCODE_API_URL, params=params)
            response.raise_for_status()
            data = response.json()

        if data.get("status") not in ("OK", "ZERO_RESULTS"):
            logger.warning(
                "Google address suggestions error: %s - %s (key=%s)",
                data.get("status"),
                data.get("error_message"),
                _api_key_fingerprint(api_key),
            )
            return []

        suggestions = []
        for result in (data.get("results") or [])[:limit]:
            suggestion = _suggestion_from_geocode_result(result)
            if suggestion:
                suggestions.append(suggestion)
        return suggestions
    except Exception as e:
        logger.warning("Failed to fetch Google address suggestions: %s", e)
        return []
