import httpx
import logging
import hashlib
import asyncio
from collections import OrderedDict
from copy import deepcopy
from time import monotonic
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)

from config import settings

GOOGLE_DIRECTIONS_API_URL = "https://maps.googleapis.com/maps/api/directions/json"
GOOGLE_GEOCODE_API_URL = "https://maps.googleapis.com/maps/api/geocode/json"
_geocode_cache = OrderedDict()
_geocode_requests = {}


async def _cached_geocode(key, loader):
    now = monotonic()
    cached = _geocode_cache.get(key)
    if cached is not None and cached[0] > now:
        _geocode_cache.move_to_end(key)
        return deepcopy(cached[1])
    task = _geocode_requests.get(key)
    if task is None:
        task = asyncio.create_task(loader())
        _geocode_requests[key] = task
        def finished(completed):
            if _geocode_requests.get(key) is completed:
                del _geocode_requests[key]
            if not completed.cancelled():
                completed.exception()
        task.add_done_callback(finished)
    try:
        result = await asyncio.shield(task)
        if result:
            _geocode_cache[key] = (monotonic() + settings.GEOCODING_CACHE_SECONDS, deepcopy(result))
            while len(_geocode_cache) > settings.GEOCODING_CACHE_MAX_ENTRIES:
                _geocode_cache.popitem(last=False)
        return deepcopy(result)
    finally:
        if task.done() and _geocode_requests.get(key) is task:
            del _geocode_requests[key]


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
            
            if data.get("status") == "OK" and data.get("routes"):
                route = data["routes"][0]
                leg = route["legs"][0]
                duration = leg["duration"]
                return {
                    "duration_seconds": duration["value"],
                    "duration_text": duration["text"],
                    "distance_meters": leg["distance"]["value"],
                    "distance_text": leg["distance"]["text"],
                    "encoded_polyline": route["overview_polyline"]["points"],
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
    return await _cached_geocode(("reverse", round(lat, 5), round(lng, 5)), lambda: _reverse_geocode(lat, lng))


async def _reverse_geocode(lat: float, lng: float) -> Optional[Dict]:
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
    return await _cached_geocode(("search", query.strip().casefold(), lat, lng, limit),
        lambda: _geocode_address_suggestions(query, lat=lat, lng=lng, limit=limit))


async def _geocode_address_suggestions(
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
