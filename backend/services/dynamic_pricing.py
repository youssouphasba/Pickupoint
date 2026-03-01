"""
Pricing dynamique — Phase 1 : coefficient contextuel par règles.
Phase 2 : régression ML sur delivery_logs quand 5 000+ livraisons.

Le coefficient multiplie le prix de base calculé (distance + poids).
Plafond : 0.80 (promo creux) à 2.00 (pénurie extrême).
"""
import logging
from datetime import datetime, timezone
from typing import Optional

from database import db

logger = logging.getLogger(__name__)


async def get_dynamic_coefficient(
    pickup_city: str = "Dakar",
    is_express: bool = False,
) -> tuple[float, dict]:
    """
    Retourne (coefficient, detail_breakdown).
    Le breakdown explique chaque facteur — affiché dans le devis Flutter.
    """
    now = datetime.now(timezone.utc)
    # Heure locale Dakar = UTC (pas de décalage horaire)
    hour = now.hour
    weekday = now.weekday()  # 0=lundi … 6=dimanche

    factors: dict = {}
    coeff = 1.0

    # ── Heure de pointe (embouteillages Dakar) ────────────────────────────────
    if (7 <= hour < 9) or (17 <= hour < 20):
        factors["rush_hour"] = 1.25
        coeff *= 1.25
    elif 12 <= hour < 14:
        factors["lunch_rush"] = 1.10
        coeff *= 1.10

    # ── Nuit / dimanche ────────────────────────────────────────────────────────
    if hour >= 20 or hour < 7:
        factors["night"] = 1.20
        coeff *= 1.20
    if weekday == 6:  # dimanche
        factors["sunday"] = 1.20
        coeff *= 1.20

    # ── Offre/demande temps réel ───────────────────────────────────────────────
    try:
        pending_count = await db.delivery_missions.count_documents({"status": "pending"})
        available_drivers = await db.users.count_documents({
            "role": "driver",
            "is_available": True,
            "is_active": True,
        })
        ratio = pending_count / max(available_drivers, 1)

        if ratio >= 5:
            factors["surge_high"] = 1.50
            coeff *= 1.50
        elif ratio >= 3:
            factors["surge_medium"] = 1.30
            coeff *= 1.30
        elif ratio < 0.5 and pending_count > 0:
            factors["low_demand"] = 0.90
            coeff *= 0.90

        factors["_supply_ratio"] = round(ratio, 2)
    except Exception:
        pass  # pas de modification si la DB est inaccessible

    # ── Express ────────────────────────────────────────────────────────────────
    # L'express est géré séparément dans pricing_service (multiplicateur fixe)
    # On le note ici pour le breakdown mais on ne l'applique pas deux fois.

    # ── Plafond ────────────────────────────────────────────────────────────────
    coeff = max(0.80, min(coeff, 2.00))
    coeff = round(coeff, 2)

    return coeff, factors


async def log_delivery_data(
    parcel_id: str,
    mode: str,
    distance_km: float,
    quoted_price: float,
    paid_price: float,
    coefficient: float,
    hour_of_day: int,
    day_of_week: int,
    pickup_lat: Optional[float],
    pickup_lng: Optional[float],
    delivery_lat: Optional[float],
    delivery_lng: Optional[float],
    driver_earn: float,
    delivery_duration_minutes: Optional[int] = None,
    failed: bool = False,
    failure_reason: Optional[str] = None,
) -> None:
    """
    Enregistre les métriques de chaque livraison terminée.
    Ces logs alimenteront le modèle ML en Phase 2.
    """
    try:
        await db.delivery_logs.insert_one({
            "parcel_id":           parcel_id,
            "mode":                mode,
            "distance_km":         distance_km,
            "quoted_price":        quoted_price,
            "paid_price":          paid_price,
            "coefficient":         coefficient,
            "hour_of_day":         hour_of_day,
            "day_of_week":         day_of_week,
            "pickup_lat":          pickup_lat,
            "pickup_lng":          pickup_lng,
            "delivery_lat":        delivery_lat,
            "delivery_lng":        delivery_lng,
            "driver_earn":         driver_earn,
            "delivery_duration_min": delivery_duration_minutes,
            "failed":              failed,
            "failure_reason":      failure_reason,
            "logged_at":           datetime.now(timezone.utc),
        })
    except Exception as e:
        logger.warning("Impossible d'enregistrer delivery_log: %s", e)
