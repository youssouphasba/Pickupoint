from typing import Optional

from fastapi import APIRouter, Query, Request

from config import settings
from core.limiter import limiter

from services.google_maps_service import geocode_address_suggestions, reverse_geocode

router = APIRouter()


@router.get("/address-suggestions", summary="Suggestions d'adresses")
@limiter.limit("30/minute")
async def address_suggestions(
    request: Request,
    q: str = Query(..., min_length=3, max_length=160),
    lat: Optional[float] = Query(None, ge=-90, le=90),
    lng: Optional[float] = Query(None, ge=-180, le=180),
    limit: int = Query(6, ge=1, le=10),
):
    suggestions = await geocode_address_suggestions(q, lat=lat, lng=lng, limit=limit)
    return {"suggestions": suggestions}


@router.get("/reverse", summary="Convertir une position GPS en adresse")
@limiter.limit("30/minute")
async def reverse_address(
    request: Request,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
):
    address = await reverse_geocode(lat, lng)
    return {"address": address}


@router.get("/location-policy", summary="Qualité et fréquence des mesures GPS")
async def location_policy():
    return {
        "strict_accuracy_meters": settings.STRICT_GPS_MAX_ACCURACY_METERS,
        "driver_accuracy_meters": settings.DRIVER_GPS_MAX_ACCURACY_METERS,
        "max_age_seconds": settings.GPS_CAPTURE_MAX_AGE_SECONDS,
        "clock_tolerance_seconds": settings.GPS_CLOCK_TOLERANCE_SECONDS,
        "upload_interval_seconds": settings.GPS_UPLOAD_INTERVAL_SECONDS,
        "heartbeat_interval_seconds": settings.GPS_HEARTBEAT_INTERVAL_SECONDS,
        "offline_buffer_hours": settings.GPS_OFFLINE_BUFFER_HOURS,
    }
