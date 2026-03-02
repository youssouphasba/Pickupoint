import httpx
import logging
from typing import Optional, Dict

logger = logging.getLogger(__name__)

from config import settings

GOOGLE_DIRECTIONS_API_URL = "https://maps.googleapis.com/maps/api/directions/json"
API_KEY = settings.GOOGLE_DIRECTIONS_API_KEY

async def get_directions_eta(origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float) -> Optional[Dict]:
    """
    Appelle l'API Google Directions pour obtenir la durée estimée et la distance.
    """
    params = {
        "origin": f"{origin_lat},{origin_lng}",
        "destination": f"{dest_lat},{dest_lng}",
        "mode": "driving",
        "key": API_KEY
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
                }
            else:
                logger.error(f"Google Directions API error: {data.get('status')} - {data.get('error_message')}")
                return None
    except Exception as e:
        logger.error(f"Failed to call Google Directions API: {e}")
        return None
