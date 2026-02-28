"""
Router tracking : endpoints publics (sans authentification).
"""
from fastapi import APIRouter

from core.exceptions import not_found_exception
from database import db
from services.parcel_service import get_parcel_timeline

router = APIRouter()


@router.get("/{tracking_code}", summary="Statut public d'un colis")
async def track_parcel(tracking_code: str):
    parcel = await db.parcels.find_one(
        {"tracking_code": tracking_code},
        {
            "_id": 0,
            "parcel_id": 0,       # On n'expose jamais le parcel_id en public
            "sender_user_id": 0,
            "payment_ref": 0,
        },
    )
    if not parcel:
        raise not_found_exception("Colis")
    return parcel


@router.get("/{tracking_code}/events", summary="Historique complet du colis")
async def track_parcel_events(tracking_code: str):
    parcel = await db.parcels.find_one(
        {"tracking_code": tracking_code},
        {"_id": 0, "parcel_id": 1},
    )
    if not parcel:
        raise not_found_exception("Colis")

    timeline = await get_parcel_timeline(parcel["parcel_id"])
    # On retire actor_id des événements publics
    public_timeline = [
        {k: v for k, v in evt.items() if k not in ("actor_id", "metadata")}
        for evt in timeline
    ]
    return {"tracking_code": tracking_code, "events": public_timeline}
