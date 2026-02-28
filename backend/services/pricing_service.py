"""
Service de tarification : calcul du prix d'un colis selon les zones et règles configurées.
"""
import logging
from typing import Optional, Dict, Any

from config import settings
from database import db
from models.common import DeliveryMode
from models.parcel import ParcelQuote, QuoteResponse

logger = logging.getLogger(__name__)


async def get_zone_for_relay(relay_id: str) -> Optional[str]:
    """Retourne le zone_id de la première zone contenant ce relay_id."""
    zone = await db.pricing_zones.find_one(
        {"relay_ids": relay_id, "is_active": True},
        {"_id": 0, "zone_id": 1},
    )
    return zone["zone_id"] if zone else None


async def find_pricing_rule(
    delivery_mode: DeliveryMode,
    origin_zone_id: Optional[str],
    destination_zone_id: Optional[str],
) -> Optional[dict]:
    """
    Cherche la règle de prix la plus spécifique (zones exactes), puis fallback
    sans zones (règle globale du mode).
    """
    # Règle exacte : mode + zones
    query = {
        "delivery_mode": delivery_mode.value,
        "is_active": True,
        "origin_zone_id": origin_zone_id,
        "destination_zone_id": destination_zone_id,
    }
    rule = await db.pricing_rules.find_one(query, {"_id": 0})
    if rule:
        return rule

    # Fallback : règle globale sans zones
    query_global = {
        "delivery_mode": delivery_mode.value,
        "is_active": True,
        "origin_zone_id": None,
        "destination_zone_id": None,
    }
    return await db.pricing_rules.find_one(query_global, {"_id": 0})


async def calculate_price(quote: ParcelQuote) -> QuoteResponse:
    """
    Calcule le prix total selon :
    1. Base price + poids × price_per_kg
    2. Assurance : declared_value × insurance_rate
    3. Clamp entre min_price et max_price
    Si aucune règle n'est trouvée, retourne les prix par défaut depuis .env
    """
    breakdown: Dict[str, Any] = {}

    # Identifier les zones
    origin_zone_id = None
    dest_zone_id = None
    if quote.origin_relay_id:
        origin_zone_id = await get_zone_for_relay(quote.origin_relay_id)
    if quote.destination_relay_id:
        dest_zone_id = await get_zone_for_relay(quote.destination_relay_id)

    rule = await find_pricing_rule(quote.delivery_mode, origin_zone_id, dest_zone_id)

    if rule:
        base_price   = rule["base_price"]
        price_per_kg = rule.get("price_per_kg", 0.0)
        min_price    = rule.get("min_price", settings.MIN_PRICE)
        max_price    = rule.get("max_price", None)
        insurance_rate = rule.get("insurance_rate", 0.02)
        breakdown["rule_id"] = rule.get("rule_id")
    else:
        # Valeurs par défaut ENV
        # Modes avec livraison domicile ou collecte domicile = tarif HOME
        _home_modes = {DeliveryMode.RELAY_TO_HOME, DeliveryMode.HOME_TO_HOME, DeliveryMode.HOME_TO_RELAY}
        base_price = (
            settings.BASE_PRICE_HOME
            if quote.delivery_mode in _home_modes
            else settings.BASE_PRICE_RELAY
        )
        price_per_kg   = 0.0
        min_price      = settings.MIN_PRICE
        max_price      = None
        insurance_rate = 0.02
        breakdown["rule_id"] = None

    weight_cost = quote.weight_kg * price_per_kg
    insurance_cost = 0.0
    if quote.is_insured and quote.declared_value:
        insurance_cost = quote.declared_value * insurance_rate

    total = base_price + weight_cost + insurance_cost

    if max_price is not None:
        total = min(total, max_price)
    total = max(total, min_price)

    breakdown.update({
        "base_price":      base_price,
        "weight_cost":     weight_cost,
        "insurance_cost":  insurance_cost,
        "origin_zone_id":  origin_zone_id,
        "dest_zone_id":    dest_zone_id,
    })

    return QuoteResponse(price=round(total), currency="XOF", breakdown=breakdown)
