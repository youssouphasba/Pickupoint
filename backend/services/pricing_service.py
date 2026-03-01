"""
Service de tarification PickuPoint.

Formule :
  sous_total = base_mode + (distance_km × PRICE_PER_KM)
             + (max(0, weight_kg - FREE_WEIGHT_KG) × PRICE_PER_KG)
             + assurance
  prix = sous_total × coefficient_dynamique × (EXPRESS_MULTIPLIER si express)
  prix = max(prix, MIN_PRICE)  — arrondi à 50 XOF supérieurs
"""
import math
import logging
from typing import Optional

from config import settings
from database import db
from models.common import DeliveryMode
from models.parcel import ParcelQuote, QuoteResponse
from services.dynamic_pricing import get_dynamic_coefficient

logger = logging.getLogger(__name__)


# ── Distances ─────────────────────────────────────────────────────────────────

def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng / 2) ** 2
    return R * 2 * math.asin(math.sqrt(a))


async def _relay_geopin(relay_id: Optional[str]) -> Optional[tuple[float, float]]:
    """Retourne (lat, lng) du relais ou None."""
    if not relay_id:
        return None
    relay = await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0, "address": 1})
    if not relay:
        return None
    geopin = (relay.get("address") or {}).get("geopin")
    if geopin and geopin.get("lat") is not None and geopin.get("lng") is not None:
        return geopin["lat"], geopin["lng"]
    return None


async def estimate_distance_km(quote: ParcelQuote) -> float:
    """
    Calcule la distance Haversine entre le point de départ et d'arrivée.
    Fallback : DEFAULT_DISTANCE_KM si les coordonnées sont inconnues.
    """
    origin_coords:  Optional[tuple[float, float]] = None
    dest_coords:    Optional[tuple[float, float]] = None

    # Origine
    if quote.origin_relay_id:
        origin_coords = await _relay_geopin(quote.origin_relay_id)
    if not origin_coords and quote.origin_location:
        gp = (quote.origin_location.geopin if hasattr(quote.origin_location, "geopin") else None)
        if gp:
            origin_coords = (gp.lat, gp.lng)

    # Destination
    if quote.destination_relay_id:
        dest_coords = await _relay_geopin(quote.destination_relay_id)
    if not dest_coords and quote.delivery_address:
        gp = (quote.delivery_address.geopin if hasattr(quote.delivery_address, "geopin") else None)
        if gp:
            dest_coords = (gp.lat, gp.lng)

    if origin_coords and dest_coords:
        km = _haversine_km(*origin_coords, *dest_coords)
        # Minimum 1 km pour ne pas avoir 0 XOF de distance
        return max(1.0, round(km, 2))

    logger.debug("GPS inconnu pour le devis — fallback %.1f km", settings.DEFAULT_DISTANCE_KM)
    return settings.DEFAULT_DISTANCE_KM


def _base_price(mode: DeliveryMode) -> float:
    return {
        DeliveryMode.RELAY_TO_RELAY: settings.BASE_RELAY_TO_RELAY,
        DeliveryMode.RELAY_TO_HOME:  settings.BASE_RELAY_TO_HOME,
        DeliveryMode.HOME_TO_RELAY:  settings.BASE_HOME_TO_RELAY,
        DeliveryMode.HOME_TO_HOME:   settings.BASE_HOME_TO_HOME,
    }[mode]


def _round_to_50(value: float) -> float:
    """Arrondit au multiple de 50 supérieur (propre pour le client)."""
    return math.ceil(value / 50) * 50


# ── Point d'entrée principal ──────────────────────────────────────────────────

async def calculate_price(quote: ParcelQuote) -> QuoteResponse:
    base       = _base_price(quote.delivery_mode)
    distance   = await estimate_distance_km(quote)
    dist_cost  = distance * settings.PRICE_PER_KM
    extra_kg   = max(0.0, quote.weight_kg - settings.FREE_WEIGHT_KG)
    weight_cost = extra_kg * settings.PRICE_PER_KG

    insur_cost = 0.0
    if quote.is_insured and quote.declared_value:
        insur_cost = max(200.0, quote.declared_value * settings.INSURANCE_RATE)

    sous_total = base + dist_cost + weight_cost + insur_cost

    # Coefficient dynamique (heure + offre/demande)
    coeff, coeff_factors = await get_dynamic_coefficient(is_express=quote.is_express)
    price_with_coeff = sous_total * coeff

    # Express
    express_cost = 0.0
    if quote.is_express:
        express_cost = price_with_coeff * (settings.EXPRESS_MULTIPLIER - 1)
        price_with_coeff *= settings.EXPRESS_MULTIPLIER

    # Min + arrondi 50 XOF
    final = _round_to_50(max(price_with_coeff, settings.MIN_PRICE))

    # Estimation du temps de livraison affiché
    estimated_hours = _estimate_delivery_hours(
        distance, quote.delivery_mode, quote.is_express
    )

    breakdown = {
        "base":           base,
        "distance_km":    distance,
        "distance_cost":  round(dist_cost),
        "weight_kg":      quote.weight_kg,
        "weight_extra_kg": extra_kg,
        "weight_cost":    round(weight_cost),
        "insurance_cost": round(insur_cost),
        "sous_total":     round(sous_total),
        "coefficient":    coeff,
        "coeff_factors":  coeff_factors,
        "is_express":     quote.is_express,
        "express_cost":   round(express_cost),
        "who_pays":       quote.who_pays,
        "estimated_hours": estimated_hours,
    }

    return QuoteResponse(price=final, currency="XOF", breakdown=breakdown)


def _estimate_delivery_hours(distance_km: float, mode: DeliveryMode, is_express: bool) -> str:
    """Estimation affichée dans l'app (ex: '1h-2h', 'Express ~45 min')."""
    if is_express:
        mins = int(distance_km / 25 * 60) + 20  # 25 km/h Dakar + 20 min marge
        return f"Express ~{mins} min"
    if mode == DeliveryMode.RELAY_TO_RELAY:
        return "Même jour" if distance_km < 15 else "24h"
    # Livraison domicile
    hours = max(1, int(distance_km / 20))
    return f"{hours}h-{hours + 1}h"
