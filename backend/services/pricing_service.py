"""
Service de tarification Denkma.

Formule :
  sous_total = base_mode + (distance_km × PRICE_PER_KM)
             + (max(0, weight_kg - FREE_WEIGHT_KG) × PRICE_PER_KG)
  prix = sous_total × coefficient_fidélité × (EXPRESS_MULTIPLIER si express)
  prix = max(prix, MIN_PRICE)  — arrondi à 50 XOF supérieurs
"""
import math
import logging
from typing import Optional

from config import settings
from core.exceptions import bad_request_exception
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


async def _relay_geopin(
    relay_id: Optional[str],
    *,
    field_name: str,
    strict: bool = False,
) -> Optional[tuple[float, float]]:
    """Retourne (lat, lng) du relais ou lève une erreur si strict."""
    if not relay_id:
        return None

    query = {"relay_id": relay_id}
    if strict:
        query["is_active"] = True

    relay = await db.relay_points.find_one(query, {"_id": 0, "address": 1})
    if not relay:
        if strict:
            raise bad_request_exception(f"{field_name} invalide ou inactif")
        return None

    geopin = (relay.get("address") or {}).get("geopin")
    if geopin and geopin.get("lat") is not None and geopin.get("lng") is not None:
        return geopin["lat"], geopin["lng"]

    if strict:
        raise bad_request_exception(f"{field_name} sans coordonnées GPS exploitables")
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
        origin_coords = await _relay_geopin(
            quote.origin_relay_id,
            field_name="origin_relay_id",
            strict=True,
        )
    if not origin_coords and quote.origin_location:
        gp = (quote.origin_location.geopin if hasattr(quote.origin_location, "geopin") else None)
        if gp:
            origin_coords = (gp.lat, gp.lng)

    # Destination
    if quote.destination_relay_id:
        dest_coords = await _relay_geopin(
            quote.destination_relay_id,
            field_name="destination_relay_id",
            strict=True,
        )
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


def _has_delivery_geopin(quote: ParcelQuote) -> bool:
    gp = (
        quote.delivery_address.geopin
        if quote.delivery_address and hasattr(quote.delivery_address, "geopin")
        else None
    )
    return bool(gp and gp.lat is not None and gp.lng is not None)


def _has_origin_geopin(quote: ParcelQuote) -> bool:
    gp = (
        quote.origin_location.geopin
        if quote.origin_location and hasattr(quote.origin_location, "geopin")
        else None
    )
    return bool(gp and gp.lat is not None and gp.lng is not None)


def _quote_requirements_status(quote: ParcelQuote) -> dict:
    missing_points: list[str] = []
    waiting_for_sender = False
    waiting_for_recipient = False

    if not quote.origin_relay_id and not _has_origin_geopin(quote):
        missing_points.append("origin")
        waiting_for_sender = True

    if not quote.destination_relay_id and not _has_delivery_geopin(quote):
        missing_points.append("destination")
        waiting_for_recipient = True

    if not missing_points:
        return {
            "ready": True,
            "missing_points": [],
            "waiting_for_sender_confirmation": False,
            "waiting_for_recipient_confirmation": False,
            "status_label": None,
        }

    if waiting_for_sender and waiting_for_recipient:
        status_label = "En attente de validation des positions"
    elif waiting_for_sender:
        status_label = "En attente de validation du point de collecte"
    else:
        status_label = "En attente de validation de la destination"

    return {
        "ready": False,
        "missing_points": missing_points,
        "waiting_for_sender_confirmation": waiting_for_sender,
        "waiting_for_recipient_confirmation": waiting_for_recipient,
        "status_label": status_label,
    }


# ── Point d'entrée principal ──────────────────────────────────────────────────

async def calculate_price(
    quote: ParcelQuote, 
    sender_tier: str = "bronze",
    is_frequent: bool = False,
    user_id: Optional[str] = None,
    is_first_delivery: bool = False,
) -> QuoteResponse:
    requirements = _quote_requirements_status(quote)
    if not requirements["ready"]:
        return QuoteResponse(
            price=None,
            currency="XOF",
            breakdown={
                "delivery_mode": quote.delivery_mode.value,
                "who_pays": quote.who_pays,
                "is_express": quote.is_express,
                "weight_kg": quote.weight_kg,
                "price_available": False,
                "duration_available": False,
                "awaiting_recipient_confirmation": requirements["waiting_for_recipient_confirmation"],
                "awaiting_sender_confirmation": requirements["waiting_for_sender_confirmation"],
                "missing_points": requirements["missing_points"],
                "status_label": requirements["status_label"],
            },
        )

    base       = _base_price(quote.delivery_mode)
    distance   = await estimate_distance_km(quote)
    dist_cost  = distance * settings.PRICE_PER_KM
    extra_kg   = max(0.0, quote.weight_kg - settings.FREE_WEIGHT_KG)
    weight_cost = extra_kg * settings.PRICE_PER_KG

    # ── Surcharge Inter-City ──
    inter_city_cost = 0.0
    if distance > 100:
        inter_city_cost += 1000.0
    elif distance > 50:
        inter_city_cost += 500.0

    sous_total = base + dist_cost + weight_cost + inter_city_cost

    # ── Réductions Fidélité & Expéditeur Fréquent (Phase 8) ──
    from services.user_service import tier_discount_coeff
    
    tier_discount = tier_discount_coeff(sender_tier)
    frequent_discount = 0.90 if is_frequent else 1.0 # -10% from text
    
    # Coefficient combiné
    loyalty_coeff = tier_discount * frequent_discount
    
    # Pas de coefficient dynamique
    coeff, coeff_factors = 1.0, []
    price_with_coeff = sous_total * coeff * loyalty_coeff

    # Express — uniquement si activé globalement par l'admin
    express_cost = 0.0
    if quote.is_express:
        express_setting = await db.app_settings.find_one({"key": "global"}, {"express_enabled": 1})
        express_globally_enabled = (express_setting or {}).get("express_enabled", False)
        if express_globally_enabled:
            express_cost = price_with_coeff * (settings.EXPRESS_MULTIPLIER - 1)
            price_with_coeff *= settings.EXPRESS_MULTIPLIER

    # Min + arrondi 50 XOF
    final = _round_to_50(max(price_with_coeff, settings.MIN_PRICE))

    # ── Promotions (Bloc E) ──
    from services.promotion_service import find_best_promo
    
    # On vérifie si c'est la 1ère livraison (pour promo_target="first_delivery")
    # Note: On a déjà current_user_id si on utilise Depends(get_current_user_optional) dans le router
    # Pour l'instant, on suppose que get_quote dans le router a déjà les infos de l'user.
    # On ajoute current_user_id en paramètre de calculate_price.
    
    promo_result = await find_best_promo(
        db,
        delivery_mode=quote.delivery_mode.value,
        original_price=final,
        user_id=user_id or "anonymous",
        user_tier=sender_tier,
        is_first_delivery=is_first_delivery,
        promo_code=quote.promo_code,
    )

    promo_applied_data = None
    discount_xof = 0.0
    original_price = final

    if promo_result:
        discount_xof = promo_result["discount_xof"]
        final = promo_result["final_price"]
        promo_applied_data = {
            "promo_id":     promo_result["promo"]["promo_id"],
            "title":        promo_result["promo"]["title"],
            "promo_type":   promo_result["promo"]["promo_type"],
            "express_free": promo_result.get("express_free", False),
        }

    # Estimation du temps de livraison affiché
    estimated_hours = _estimate_delivery_hours(
        distance, quote.delivery_mode, quote.is_express
    )

    breakdown = {
        "delivery_mode":  quote.delivery_mode.value,
        "base":           base,
        "distance_km":    distance,
        "distance_cost":  round(dist_cost),
        "weight_kg":      quote.weight_kg,
        "weight_extra_kg": extra_kg,
        "weight_cost":    round(weight_cost),
        "sous_total":     round(sous_total),
        "inter_city_cost": round(inter_city_cost),
        "coefficient":    coeff,
        "coeff_factors":  coeff_factors,
        "is_express":     quote.is_express,
        "express_cost":   round(express_cost),
        "loyalty_tier":   sender_tier,
        "is_frequent":    is_frequent,
        "loyalty_coeff":  round(loyalty_coeff, 2),
        "who_pays":       quote.who_pays,
        "estimated_hours": estimated_hours,
        "promo_code":     quote.promo_code,
        "price_available": True,
        "duration_available": True,
        "awaiting_recipient_confirmation": False,
        "awaiting_sender_confirmation": False,
        "missing_points": [],
        "status_label": "Disponible",
    }

    return QuoteResponse(
        price=final, 
        currency="XOF", 
        breakdown=breakdown,
        original_price=original_price if promo_result else None,
        discount_xof=discount_xof,
        promo_applied=promo_applied_data
    )


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
