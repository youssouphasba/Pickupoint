from typing import Optional

from fastapi import APIRouter, Query

from services.google_maps_service import geocode_address_suggestions

router = APIRouter()


@router.get("/address-suggestions", summary="Suggestions d'adresses")
async def address_suggestions(
    q: str = Query(..., min_length=3, max_length=160),
    lat: Optional[float] = Query(None, ge=-90, le=90),
    lng: Optional[float] = Query(None, ge=-180, le=180),
    limit: int = Query(6, ge=1, le=10),
):
    suggestions = await geocode_address_suggestions(q, lat=lat, lng=lng, limit=limit)
    return {"suggestions": suggestions}
