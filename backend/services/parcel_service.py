"""
Service colis : machine d'états, event sourcing, transitions métier.
"""
import logging
import math
import re
import uuid
from datetime import datetime, timezone, timedelta
from typing import Optional

from config import settings
from database import db
from core.exceptions import bad_request_exception
from core.utils import normalize_phone
from core.security import generate_tracking_code
from models.common import ParcelStatus, DeliveryMode
from models.parcel import ParcelCreate, ParcelEvent, ParcelQuote, QuoteResponse
from services.pricing_service import calculate_price
from services.wallet_service import distribute_delivery_revenue
from services.notification_service import notify_parcel_status_change, notify_delivery_code
from services.payment_service import create_payment_link
from services.admin_events_service import AdminEventType, record_admin_event

import random
logger = logging.getLogger(__name__)

def _generate_code() -> str:
    """Génère un code numérique à 6 chiffres (pickup_code livreur)."""
    return f"{random.randint(100000, 999999)}"


def _generate_delivery_code() -> str:
    """Génère un code numérique à 6 chiffres (delivery_code destinataire domicile)."""
    return f"{random.randint(100000, 999999)}"

# ── Machine d'états ───────────────────────────────────────────────────────────
ALLOWED_TRANSITIONS: dict[ParcelStatus, list[ParcelStatus]] = {
    ParcelStatus.CREATED: [
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
        ParcelStatus.OUT_FOR_DELIVERY,
        ParcelStatus.IN_TRANSIT,         # HOME_TO_RELAY / HOME_TO_HOME : driver collecte chez l'expéditeur → transit
        ParcelStatus.INCIDENT_REPORTED,
        ParcelStatus.CANCELLED,
        ParcelStatus.SUSPENDED,
    ],
    ParcelStatus.DROPPED_AT_ORIGIN_RELAY: [
        ParcelStatus.IN_TRANSIT,
        ParcelStatus.OUT_FOR_DELIVERY,  # relay_to_home : driver va directement au domicile
        ParcelStatus.CANCELLED,
        ParcelStatus.SUSPENDED,
    ],
    ParcelStatus.IN_TRANSIT: [
        ParcelStatus.AT_DESTINATION_RELAY,
        ParcelStatus.AVAILABLE_AT_RELAY,  # scan_in relais dest → directement disponible
        ParcelStatus.OUT_FOR_DELIVERY,
        ParcelStatus.INCIDENT_REPORTED,
        ParcelStatus.SUSPENDED,
    ],
    ParcelStatus.AT_DESTINATION_RELAY: [
        ParcelStatus.AVAILABLE_AT_RELAY,
        ParcelStatus.OUT_FOR_DELIVERY,
        ParcelStatus.SUSPENDED,
    ],
    ParcelStatus.AVAILABLE_AT_RELAY: [
        ParcelStatus.DELIVERED,
        ParcelStatus.EXPIRED,
        ParcelStatus.SUSPENDED,
    ],
    ParcelStatus.OUT_FOR_DELIVERY: [
        ParcelStatus.DELIVERED,
        ParcelStatus.DELIVERY_FAILED,
        ParcelStatus.AT_DESTINATION_RELAY,   # H2R : fallback anciens colis
        ParcelStatus.AVAILABLE_AT_RELAY,     # H2R : scan_in relais dest → directement disponible
        ParcelStatus.INCIDENT_REPORTED,
        ParcelStatus.SUSPENDED,
    ],
    ParcelStatus.DELIVERY_FAILED: [
        ParcelStatus.INCIDENT_REPORTED,
        ParcelStatus.REDIRECTED_TO_RELAY,
        ParcelStatus.RETURNED,
    ],
    ParcelStatus.REDIRECTED_TO_RELAY: [
        ParcelStatus.AVAILABLE_AT_RELAY,
    ],
    ParcelStatus.INCIDENT_REPORTED: [
        ParcelStatus.OUT_FOR_DELIVERY,   # Réassignation
        ParcelStatus.RETURNED,           # Retour obligé
        ParcelStatus.CANCELLED,
    ],
    ParcelStatus.DISPUTED: [
        ParcelStatus.DELIVERED,
        ParcelStatus.RETURNED,
        ParcelStatus.CANCELLED,
    ],
    # États terminaux
    ParcelStatus.DELIVERED: [],
    ParcelStatus.CANCELLED: [],
    ParcelStatus.EXPIRED:   [],
    ParcelStatus.RETURNED:  [],
    ParcelStatus.SUSPENDED: [
        ParcelStatus.CREATED,
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
        ParcelStatus.IN_TRANSIT,
        ParcelStatus.AT_DESTINATION_RELAY,
        ParcelStatus.AVAILABLE_AT_RELAY,
        ParcelStatus.OUT_FOR_DELIVERY,
        ParcelStatus.CANCELLED,
    ],
}


def _parcel_id() -> str:
    return f"prc_{uuid.uuid4().hex[:12]}"


def _event_id() -> str:
    return f"evt_{uuid.uuid4().hex[:12]}"


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Distance en km entre deux coordonnées GPS."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng / 2) ** 2
    return R * 2 * math.asin(math.sqrt(a))


def _parse_hhmm(value: str) -> Optional[tuple[int, int]]:
    normalized = value.strip().lower().replace("h", ":")
    parts = normalized.split(":")
    if not parts or not parts[0].isdigit():
        return None
    hour = int(parts[0])
    minute = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        return None
    return hour, minute


def _time_in_range(now: datetime, value: str) -> bool:
    if not value or value.strip().lower() in {"closed", "fermé", "ferme"}:
        return False
    normalized = value.lower().replace("h", ":")
    ranges = [
        f"{match.group(1)}-{match.group(2)}"
        for match in re.finditer(r"(\d{1,2}(?::\d{2})?)\s*-\s*(\d{1,2}(?::\d{2})?)", normalized)
    ]
    if not ranges:
        ranges = [item.strip() for item in normalized.replace(";", ",").split(",") if item.strip()]
    current = now.hour * 60 + now.minute
    for item in ranges:
        if "-" not in item:
            continue
        start_raw, end_raw = item.split("-", 1)
        start = _parse_hhmm(start_raw)
        end = _parse_hhmm(end_raw)
        if not start or not end:
            continue
        start_min = start[0] * 60 + start[1]
        end_min = end[0] * 60 + end[1]
        if start_min <= end_min and start_min <= current <= end_min:
            return True
        if start_min > end_min and (current >= start_min or current <= end_min):
            return True
    return False


def _relay_is_open(relay: dict, now: datetime) -> bool:
    """Vérifie les horaires quand ils sont renseignés. Les anciens relais sans horaires restent éligibles."""
    opening_hours = relay.get("opening_hours")
    if not opening_hours:
        return True

    if isinstance(opening_hours, dict):
        keys_by_weekday = [
            ("mon", "monday", "lun", "lundi"),
            ("tue", "tuesday", "mar", "mardi"),
            ("wed", "wednesday", "mer", "mercredi"),
            ("thu", "thursday", "jeu", "jeudi"),
            ("fri", "friday", "ven", "vendredi"),
            ("sat", "saturday", "sam", "samedi"),
            ("sun", "sunday", "dim", "dimanche"),
        ]
        value = None
        for key in keys_by_weekday[now.weekday()]:
            value = opening_hours.get(key)
            if value:
                break
        return _time_in_range(now, str(value)) if value else False

    if isinstance(opening_hours, str):
        return _time_in_range(now, opening_hours)

    return True


async def find_nearest_relay(lat: float, lng: float) -> Optional[dict]:
    """Retourne le relais actif, ouvert et proche d'une coordonnée GPS."""
    settings_doc = await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}
    configured_distance = settings_doc.get("redirect_relay_max_distance_km")
    max_distance_km = max(
        0.1,
        float(configured_distance if configured_distance is not None else settings.REDIRECT_RELAY_MAX_DISTANCE_KM),
    )
    now = datetime.now(timezone.utc)
    relays = await db.relay_points.find(
        {"is_active": True},
        {
            "_id": 0,
            "relay_id": 1,
            "name": 1,
            "address": 1,
            "coverage_radius_km": 1,
            "current_load": 1,
            "max_capacity": 1,
            "opening_hours": 1,
        },
    ).to_list(length=500)

    nearest, min_dist = None, float("inf")
    for relay in relays:
        max_capacity = relay.get("max_capacity")
        current_load = relay.get("current_load")
        if max_capacity is not None and current_load is not None and current_load >= max_capacity:
            continue
        if not _relay_is_open(relay, now):
            continue
        geopin = (relay.get("address") or {}).get("geopin")
        if geopin and geopin.get("lat") is not None and geopin.get("lng") is not None:
            dist = _haversine_km(lat, lng, geopin["lat"], geopin["lng"])
            relay_radius = float(relay.get("coverage_radius_km") or max_distance_km)
            allowed_distance = min(max_distance_km, relay_radius)
            if dist > allowed_distance:
                continue
            if dist < min_dist:
                min_dist, nearest = dist, relay
    if nearest:
        nearest["distance_km"] = round(min_dist, 2)
    return nearest


async def _find_nearest_candidate_drivers(lat: float, lng: float, limit: int = 5) -> list[str]:
    """Trouve les X livreurs les plus proches actifs récemment."""
    from models.common import UserRole
    # Actif depuis < 30 min et disponible
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=30)
    
    cursor = db.users.find({
        "role": UserRole.DRIVER.value,
        "is_active": True,
        "is_available": True,
        "last_driver_location_at": {"$gte": cutoff}
    })
    drivers = await cursor.to_list(length=100)
    
    candidates = []
    for d in drivers:
        loc = d.get("last_driver_location")
        if loc and loc.get("lat") and loc.get("lng"):
            dist = _haversine_km(lat, lng, loc["lat"], loc["lng"])
            candidates.append({"id": d["user_id"], "dist": dist})
    
    candidates.sort(key=lambda x: x["dist"])
    return [c["id"] for c in candidates[:limit]]


def _round_to_50(value: float) -> float:
    return math.ceil(value / 50) * 50 if value > 0 else 0.0


def _normalize_geopin(source: Optional[dict]) -> Optional[dict]:
    if not source:
        return None

    geopin = source.get("geopin") or source
    lat = geopin.get("lat")
    lng = geopin.get("lng")
    if lat is None or lng is None:
        return None

    return {
        "lat": float(lat),
        "lng": float(lng),
        "accuracy": geopin.get("accuracy"),
    }


def _current_delivery_location(parcel: dict) -> dict:
    return parcel.get("delivery_location") or parcel.get("delivery_address") or {}


async def _require_active_relay(relay_id: Optional[str], field_name: str) -> Optional[dict]:
    if not relay_id:
        return None

    relay = await db.relay_points.find_one(
        {"relay_id": relay_id, "is_active": True},
        {"_id": 0},
    )
    if not relay:
        raise bad_request_exception(f"{field_name} invalide ou inactif")

    geopin = ((relay.get("address") or {}).get("geopin") or {})
    if geopin.get("lat") is None or geopin.get("lng") is None:
        raise bad_request_exception(f"{field_name} sans coordonnées GPS exploitables")

    return relay


async def sync_active_mission_with_parcel(
    parcel: dict,
    *,
    earn_amount: Optional[float] = None,
) -> None:
    mission = await db.delivery_missions.find_one(
        {
            "parcel_id": parcel["parcel_id"],
            "status": {"$in": ["pending", "assigned", "in_progress"]},
        },
        {"_id": 0},
    )
    if not mission:
        return

    delivery_source = _current_delivery_location(parcel)
    delivery_geopin = _normalize_geopin(delivery_source)
    delivery_label = (
        delivery_source.get("label")
        or delivery_source.get("notes")
        or mission.get("delivery_label")
        or "Adresse destinataire"
    )
    delivery_city = delivery_source.get("city") or mission.get("delivery_city") or "Dakar"

    update_doc = {
        "delivery_geopin": delivery_geopin,
        "delivery_label": delivery_label,
        "delivery_city": delivery_city,
        "payment_status": parcel.get("payment_status"),
        "payment_method": parcel.get("payment_method"),
        "who_pays": parcel.get("who_pays"),
        "pickup_voice_note": parcel.get("pickup_voice_note"),
        "delivery_voice_note": parcel.get("delivery_voice_note"),
        "updated_at": datetime.now(timezone.utc),
    }
    if earn_amount is not None:
        update_doc["earn_amount"] = earn_amount

    await db.delivery_missions.update_one(
        {"mission_id": mission["mission_id"]},
        {"$set": update_doc},
    )


async def refresh_quote_if_ready(parcel: dict) -> tuple[dict, bool]:
    """Recalcule le devis dès que les adresses GPS nécessaires sont disponibles."""
    sender_user_id = parcel.get("sender_user_id")
    user = await db.users.find_one({"user_id": sender_user_id}) if sender_user_id else None
    sender_tier = user.get("loyalty_tier", "bronze") if user else "bronze"

    month_ago = datetime.now(timezone.utc) - timedelta(days=30)
    delivered_count = await db.parcels.count_documents({
        "sender_user_id": sender_user_id,
        "status": "delivered",
        "created_at": {"$gte": month_ago},
    })
    total_delivered = await db.parcels.count_documents({
        "sender_user_id": sender_user_id,
        "status": "delivered",
    })

    quote_req = ParcelQuote(
        delivery_mode=parcel["delivery_mode"],
        origin_relay_id=parcel.get("origin_relay_id"),
        destination_relay_id=parcel.get("destination_relay_id"),
        origin_location=parcel.get("origin_location"),
        delivery_address=parcel.get("delivery_address"),
        weight_kg=float(parcel.get("weight_kg") or 0.5),
        declared_value=parcel.get("declared_value"),
        is_express=bool(parcel.get("is_express")),
        who_pays=parcel.get("who_pays") or "sender",
        promo_code=None,
    )

    quote = await calculate_price(
        quote_req,
        sender_tier=sender_tier,
        is_frequent=delivered_count >= 10,
        user_id=sender_user_id,
        is_first_delivery=(total_delivered == 0),
    )

    previous_price = parcel.get("quoted_price")

    if quote.price is None:
        await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"]},
            {"$set": {
                "quote_breakdown": quote.breakdown,
                "updated_at": datetime.now(timezone.utc),
            }},
        )
        refreshed = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0}) or parcel
        return refreshed, False

    if previous_price is not None:
        await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"]},
            {"$set": {
                "quoted_price": quote.price,
                "quote_breakdown": quote.breakdown,
                "updated_at": datetime.now(timezone.utc),
            }},
        )
        refreshed = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0}) or parcel
        return refreshed, False

    now = datetime.now(timezone.utc)
    lock_result = await db.parcels.update_one(
        {"parcel_id": parcel["parcel_id"], "quoted_price": None},
        {"$set": {
            "quoted_price": quote.price,
            "quote_breakdown": quote.breakdown,
            "updated_at": now,
        }},
    )
    if lock_result.modified_count == 0:
        refreshed = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0}) or parcel
        return refreshed, False

    payer_phone = parcel.get("sender_phone") if parcel.get("who_pays") == "sender" else parcel.get("recipient_phone")
    payer_name = parcel.get("sender_name") if parcel.get("who_pays") == "sender" else parcel.get("recipient_name")
    payment_res = await create_payment_link(
        parcel_id=parcel["parcel_id"],
        tracking_code=parcel["tracking_code"],
        amount=quote.price,
        customer_phone=payer_phone or "",
        customer_name=payer_name or "Client Denkma",
    )
    if payment_res.get("success"):
        await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"], "payment_ref": None},
            {"$set": {
                "payment_url": payment_res.get("payment_link"),
                "payment_ref": payment_res.get("tx_ref"),
                "updated_at": datetime.now(timezone.utc),
            }},
        )

    refreshed = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0}) or parcel
    return refreshed, True


async def preview_address_change(parcel: dict, lat: float, lng: float, accuracy: Optional[float] = None) -> dict:
    mission = await db.delivery_missions.find_one(
        {
            "parcel_id": parcel["parcel_id"],
            "status": {"$in": ["pending", "assigned", "in_progress"]},
        },
        {"_id": 0},
    )

    proposed_location = {
        "label": None,
        "district": None,
        "city": "Dakar",
        "notes": None,
        "geopin": {"lat": lat, "lng": lng, "accuracy": accuracy},
        "source": "app_recipient",
        "confirmed": True,
    }

    if not mission or mission.get("status") != "in_progress":
        return {
            "requires_acceptance": False,
            "distance_delta_km": 0.0,
            "surcharge_xof": 0.0,
            "new_location": proposed_location,
        }

    current_dest = _normalize_geopin(mission.get("delivery_geopin")) or _normalize_geopin(_current_delivery_location(parcel))
    if not current_dest:
        return {
            "requires_acceptance": False,
            "distance_delta_km": 0.0,
            "surcharge_xof": 0.0,
            "new_location": proposed_location,
        }

    driver_point = _normalize_geopin(mission.get("driver_location")) or _normalize_geopin(mission.get("pickup_geopin"))
    if not driver_point:
        assigned_driver_id = parcel.get("assigned_driver_id")
        if assigned_driver_id:
            driver = await db.users.find_one(
                {"user_id": assigned_driver_id},
                {"_id": 0, "last_driver_location": 1},
            )
            driver_point = _normalize_geopin((driver or {}).get("last_driver_location"))

    if not driver_point:
        driver_point = _normalize_geopin(mission.get("pickup_geopin"))

    if not driver_point:
        return {
            "requires_acceptance": False,
            "distance_delta_km": 0.0,
            "surcharge_xof": 0.0,
            "new_location": proposed_location,
        }

    current_remaining_km = _haversine_km(
        driver_point["lat"],
        driver_point["lng"],
        current_dest["lat"],
        current_dest["lng"],
    )
    new_remaining_km = _haversine_km(
        driver_point["lat"],
        driver_point["lng"],
        lat,
        lng,
    )
    delta_km = round(max(0.0, new_remaining_km - current_remaining_km), 2)
    surcharge_xof = _round_to_50(delta_km * settings.PRICE_PER_KM) if delta_km > 1 else 0.0

    return {
        "requires_acceptance": surcharge_xof > 0,
        "distance_delta_km": delta_km,
        "current_remaining_km": round(current_remaining_km, 2),
        "new_remaining_km": round(new_remaining_km, 2),
        "surcharge_xof": surcharge_xof,
        "new_location": proposed_location,
    }


async def create_parcel(data: ParcelCreate, sender_user_id: str, sender_phone: str = "") -> dict:
    """Crée un nouveau colis avec devis et tracking code."""
    from models.parcel import ParcelQuote
    
    # ── Récupérer infos fidélité pour le recalcul du prix ──
    user = await db.users.find_one({"user_id": sender_user_id})
    sender_tier = user.get("loyalty_tier", "bronze") if user else "bronze"
    
    # Check for frequent sender
    month_ago = datetime.now(timezone.utc) - timedelta(days=30)
    delivered_count = await db.parcels.count_documents({
        "sender_user_id": sender_user_id,
        "status": "delivered",
        "created_at": {"$gte": month_ago}
    })
    is_frequent = delivered_count >= 10
    
    # Check for first delivery
    total_delivered = await db.parcels.count_documents({
        "sender_user_id": sender_user_id,
        "status": "delivered"
    })
    is_first = (total_delivered == 0)

    quote_req = ParcelQuote(
        delivery_mode=data.delivery_mode,
        origin_relay_id=data.origin_relay_id,
        destination_relay_id=data.destination_relay_id,
        origin_location=data.origin_location,
        delivery_address=data.delivery_address,
        weight_kg=data.weight_kg,
        declared_value=data.declared_value,
        is_express=data.is_express,
        who_pays=data.who_pays,
        promo_code=data.promo_id, # Dans ParcelCreate c'est souvent promo_id ou promo_code qui est envoyé. 
                                   # Dans le plan on a ajouté promo_id à ParcelCreate.
    )
    # Recalculer le prix pour être sûr
    quote: QuoteResponse = await calculate_price(
        quote_req, 
        sender_tier=sender_tier, 
        is_frequent=is_frequent,
        user_id=sender_user_id,
        is_first_delivery=is_first
    )

    sender_name_str = (user or {}).get("name", "Expéditeur")
    sender_phone_value = normalize_phone(sender_phone or data.sender_phone or (user or {}).get("phone", ""))
    recipient_phone = normalize_phone(data.recipient_phone)

    # Vérifications métier complémentaires: relais existants et actifs.
    if data.origin_relay_id:
        await _require_active_relay(data.origin_relay_id, "origin_relay_id")
    if data.destination_relay_id:
        await _require_active_relay(data.destination_relay_id, "destination_relay_id")
    if data.transit_relay_id:
        await _require_active_relay(data.transit_relay_id, "transit_relay_id")

    now = datetime.now(timezone.utc)
    parcel_id     = _parcel_id()
    tracking_code = generate_tracking_code()
    expires_at    = now + timedelta(days=7)
    has_origin_gps = bool(data.origin_location and data.origin_location.geopin)
    requires_sender_confirmation = data.delivery_mode.value.startswith("home_to_") and not has_origin_gps
    requires_recipient_gps = data.delivery_mode.value.endswith("_to_home")
    requires_recipient_relay_choice = data.delivery_mode.value.endswith("_to_relay")
    delivery_confirmed = data.delivery_mode.value.endswith("_to_relay")
    pickup_confirmed = has_origin_gps if data.delivery_mode.value.startswith("home_to_") else False

    parcel_doc = {
        "parcel_id":             parcel_id,
        "tracking_code":         tracking_code,
        "sender_user_id":        sender_user_id,
        "sender_name":           sender_name_str,
        "sender_phone":          sender_phone_value or None,
        "recipient_phone":       recipient_phone,
        "recipient_name":        data.recipient_name,
        "recipient_user_id":     None,  # Lié ci-dessous
        "delivery_mode":         data.delivery_mode.value,
        "origin_relay_id":       data.origin_relay_id,
        "destination_relay_id":  data.destination_relay_id,
        "transit_relay_id":      data.transit_relay_id,
        "delivery_address":      data.delivery_address.model_dump() if data.delivery_address else None,
        "origin_location":       data.origin_location.model_dump() if data.origin_location else None,
        "weight_kg":             data.weight_kg,
        "dimensions":            data.dimensions,
        "declared_value":        data.declared_value,
        "description":           data.description,
        "is_express":            data.is_express,
        "who_pays":              data.who_pays,
        "quote_breakdown":       quote.breakdown,
        "quoted_price":          quote.price,
        # pickup_code (6ch) : toujours — remis au driver par l'agent relais ou l'expéditeur
        # delivery_code (6ch) : *_to_home uniquement — destinataire le donne au driver
        # relay_pin (6ch) : *_to_relay uniquement — destinataire le donne à l'agent relais
        "pickup_code":           _generate_code(),
        "delivery_code":         _generate_delivery_code() if data.delivery_mode.value.endswith("_to_home") else None,
        "relay_pin":             _generate_delivery_code() if data.delivery_mode.value.endswith("_to_relay") else None,
        "return_code":           None,
        "paid_price":            None,
        "payment_status":        "pending",
        "payment_method":        None,
        "payment_ref":           None,
        "payment_override":      False,
        "payment_override_reason": None,
        "payment_override_by":   None,
        "payment_override_at":   None,
        "initiated_by":          data.initiated_by if hasattr(data, 'initiated_by') else "sender",
        "delivery_confirmed":    delivery_confirmed,
        "pickup_confirmed":      pickup_confirmed,
        "gps_reminders": {
            "sender": {
                "count": 0,
                "last_sent_at": None,
                "last_channel": None,
                "confirmed_at": now if pickup_confirmed else None,
            },
            "recipient": {
                "count": 0,
                "last_sent_at": None,
                "last_channel": None,
                "confirmed_at": now if delivery_confirmed else None,
            },
        },
        "pickup_voice_note":     getattr(data, "pickup_voice_note", None),
        "delivery_voice_note":   getattr(data, "delivery_voice_note", None),
        "status":                ParcelStatus.CREATED.value,
        "promo_id":              quote.promo_applied.get("promo_id") if quote.promo_applied else None,
        "assigned_driver_id":    None,
        "redirect_relay_id":     None,
        "address_change_surcharge_xof": 0.0,
        "driver_bonus_xof":      0.0,
        "external_ref":          None,
        "created_at":            now,
        "updated_at":            now,
        "expires_at":            expires_at,
    }

    # ── Enregistrer l'usage de la promotion ──
    if quote.promo_applied:
        from services.promotion_service import record_promo_use
        await record_promo_use(
            db, 
            promo_id=quote.promo_applied["promo_id"], 
            user_id=sender_user_id, 
            parcel_id=parcel_id
        )

    # ── Gestion des confirmations GPS expéditeur / destinataire ──
    recipient_token = None
    sender_token = None
    if requires_sender_confirmation or requires_recipient_gps or requires_recipient_relay_choice:
        from routers.confirm import generate_confirm_tokens
        generated_recipient_token, generated_sender_token = generate_confirm_tokens()
        if requires_recipient_gps or requires_recipient_relay_choice:
            recipient_token = generated_recipient_token
            parcel_doc["recipient_confirm_token"] = recipient_token
            if requires_recipient_gps:
                parcel_doc["delivery_confirmed"] = False
        if requires_sender_confirmation:
            sender_token = generated_sender_token
            parcel_doc["sender_confirm_token"] = sender_token
            parcel_doc["pickup_confirmed"] = False

    # ── Liaison automatique du destinataire si compte existant ──
    recipient_user = await db.users.find_one({"phone": recipient_phone}, {"user_id": 1})
    if recipient_user:
        parcel_doc["recipient_user_id"] = recipient_user["user_id"]

    await db.parcels.insert_one(parcel_doc)
    
    # ── Déclenchement automatique de la mission de collecte ──
    # Uniquement pour les modes commençant par 'home_to_' (pickup chez l'expéditeur)
    if data.delivery_mode.value.startswith("home_to_"):
        # Note: _create_delivery_mission vérifiera elle-même si la confirmation GPS 
        # est requise (home_to_home) avant de réellement créer la mission.
        await _create_delivery_mission(parcel_doc, ParcelStatus.CREATED)

    await _record_event(
        parcel_id=parcel_id,
        event_type="PARCEL_CREATED",
        to_status=ParcelStatus.CREATED,
        actor_id=sender_user_id,
        actor_role="client",
    )

    try:
        await notify_parcel_status_change(parcel_doc, ParcelStatus.CREATED)
    except Exception as exc:
        logger.warning("Notification WhatsApp de création non envoyée pour %s: %s", parcel_id, exc)

    # ── Générer le lien de paiement Flutterwave (pour le payeur désigné) ──
    payment_url = None
    payer_phone = sender_phone if data.who_pays == "sender" else data.recipient_phone
    payer_name  = sender_name_str if data.who_pays == "sender" else data.recipient_name

    if quote.price is not None:
        payment_res = await create_payment_link(
            parcel_id=parcel_id,
            tracking_code=tracking_code,
            amount=quote.price,
            customer_phone=payer_phone,
            customer_name=payer_name,
        )
        if payment_res.get("success"):
            payment_url = payment_res["payment_link"]
            await db.parcels.update_one(
                {"parcel_id": parcel_id},
                {"$set": {
                    "payment_url": payment_url,
                    "payment_ref": payment_res.get("tx_ref")
                }}
            )

    # Le code de retrait/remise est intégré dans le template WhatsApp de création
    # destiné au bénéficiaire. On évite ainsi un message "code de vérification"
    # ambigu côté destinataire.

    # ── Envoyer le lien de confirmation GPS (SMS / WhatsApp) ──
    recipient_confirm_url = None
    if requires_recipient_gps and recipient_token:
        # On utilise BASE_URL car le site web vitrine n'est pas encore en place
        recipient_confirm_url = f"{settings.BASE_URL}/confirm/{recipient_token}"
        
        # Récupérer le nom de l'expéditeur
        sender_name = "L'expéditeur"
        sender_user = await db.users.find_one({"user_id": sender_user_id}, {"_id": 0, "full_name": 1})
        if sender_user and sender_user.get("full_name"):
            sender_name = sender_user["full_name"]

        msg = (
            f"{sender_name} veut vous envoyer un colis ({tracking_code}).\n"
            f"Veuillez confirmer votre position via ce lien pour recevoir le colis : {recipient_confirm_url}"
        )
        try:
            from services.notification_service import notify_location_confirmation_request

            await notify_location_confirmation_request(
                parcel_doc,
                actor="recipient",
                confirm_url=recipient_confirm_url,
            )
            await db.parcels.update_one(
                {"parcel_id": parcel_id},
                {"$set": {
                    "gps_reminders.recipient.count": 1,
                    "gps_reminders.recipient.last_sent_at": now,
                    "gps_reminders.recipient.last_channel": (
                        "in_app_push" if parcel_doc.get("recipient_user_id") else "sms_whatsapp"
                    ),
                }},
            )
        except Exception as e:
            logger.warning(f"SMS de confirmation GPS non envoyé : {e}")

    if requires_recipient_relay_choice and recipient_token:
        relay_choice_url = f"{settings.BASE_URL}/confirm/{recipient_token}"
        try:
            from services.notification_service import notify_relay_choice_request

            await notify_relay_choice_request(
                parcel_doc,
                confirm_url=relay_choice_url,
            )
            await db.parcels.update_one(
                {"parcel_id": parcel_id},
                {"$set": {
                    "gps_reminders.recipient.count": 1,
                    "gps_reminders.recipient.last_sent_at": now,
                    "gps_reminders.recipient.last_channel": (
                        "in_app_push" if parcel_doc.get("recipient_user_id") else "sms_whatsapp"
                    ),
                }},
            )
        except Exception as e:
            logger.warning(f"Lien de choix de relais non envoyé : {e}")

    sender_confirm_url = None
    if requires_sender_confirmation and sender_token:
        sender_confirm_url = f"{settings.BASE_URL}/confirm/{sender_token}"
        try:
            from services.notification_service import notify_location_confirmation_request

            await notify_location_confirmation_request(
                parcel_doc,
                actor="sender",
                confirm_url=sender_confirm_url,
            )
            await db.parcels.update_one(
                {"parcel_id": parcel_id},
                {"$set": {
                    "gps_reminders.sender.count": 1,
                    "gps_reminders.sender.last_sent_at": now,
                    "gps_reminders.sender.last_channel": (
                        "in_app_push" if parcel_doc.get("sender_user_id") else "sms_whatsapp"
                    ),
                }},
            )
        except Exception as e:
            logger.warning("Confirmation GPS expéditeur non envoyée : %s", e)

    result = {k: v for k, v in parcel_doc.items() if k != "_id"}
    result["payment_url"] = payment_url
    if recipient_confirm_url:
        result["recipient_confirm_url"] = recipient_confirm_url
    if sender_confirm_url:
        result["sender_confirm_url"] = sender_confirm_url

    return result


async def transition_status(
    parcel_id: str,
    new_status: ParcelStatus,
    actor_id: str,
    actor_role: str = "system",
    notes: Optional[str] = None,
    metadata: Optional[dict] = None,
    force: bool = False,
) -> dict:
    """
    Transition officielle de la machine d'états.
    Valide la transition, met à jour MongoDB, enregistre l'événement.
    Si force=True, on court-circuite la validation des étapes autorisées.
    """
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise bad_request_exception("Colis introuvable")

    current_status = ParcelStatus(parcel["status"])
    if not force:
        allowed = ALLOWED_TRANSITIONS.get(current_status, [])
        if new_status not in allowed:
            raise bad_request_exception(
                f"Transition interdite : {current_status.value} → {new_status.value} (Utilisez l'override admin pour forcer)"
            )

    now = datetime.now(timezone.utc)
    update_fields = {"status": new_status.value, "updated_at": now}
    # Renouveler le délai de retrait quand le colis arrive au relais (7 jours)
    if new_status in (ParcelStatus.AVAILABLE_AT_RELAY, ParcelStatus.REDIRECTED_TO_RELAY):
        update_fields["expires_at"] = now + timedelta(days=7)
    await db.parcels.update_one(
        {"parcel_id": parcel_id},
        {"$set": update_fields},
    )

    await _record_event(
        parcel_id=parcel_id,
        event_type="STATUS_CHANGED",
        from_status=current_status,
        to_status=new_status,
        actor_id=actor_id,
        actor_role=actor_role,
        notes=notes,
        metadata=metadata or {},
    )

    # Créditer wallets si livraison réussie
    if new_status == ParcelStatus.DELIVERED:
        await distribute_delivery_revenue(parcel)
        # ── Gamification (Phase 8) ──
        driver_id = parcel.get("assigned_driver_id")
        if driver_id:
            from services.gamification_service import update_driver_gamification
            await update_driver_gamification(driver_id, "delivery_completed")
            
        # ── Fidélité (Phase 8) ──
        sender_user_id = parcel.get("sender_user_id")
        if sender_user_id:
            from services.loyalty_service import credit_loyalty_points
            await credit_loyalty_points(sender_user_id)

    # Générer la mission du livreur quand le colis est déposé au relais d'origine
    if new_status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY:
            # Le livreur prend au relais origine et dépose au relais destination (transit ou direct)
            await _create_delivery_mission(parcel, ParcelStatus.DROPPED_AT_ORIGIN_RELAY)

    # Arrivée au relais de destination -> Déclencher la livraison finale si c'est un flux Home
    if new_status == ParcelStatus.AT_DESTINATION_RELAY:
        if parcel.get("delivery_mode", "").endswith("_to_home"):
            if parcel.get("delivery_confirmed"):
                await _create_delivery_mission(parcel, ParcelStatus.AT_DESTINATION_RELAY)
            else:
                logger.info(f"Colis {parcel['parcel_id']} au relais destination, en attente GPS destinataire.")

    # Échec livraison → trouver le relais de repli le plus proche automatiquement
    if new_status == ParcelStatus.DELIVERY_FAILED:
        delivery_loc = parcel.get("delivery_location")
        if delivery_loc:
            geopin = delivery_loc.get("geopin") or delivery_loc
            lat = geopin.get("lat")
            lng = geopin.get("lng")
            if lat is not None and lng is not None:
                nearest = await find_nearest_relay(lat, lng)
                if nearest:
                    await db.parcels.update_one(
                        {"parcel_id": parcel_id},
                        {"$set": {
                            "redirect_relay_id": nearest["relay_id"],
                            "updated_at": datetime.now(timezone.utc),
                        }},
                    )
                    logger.info(
                        "Relais de repli auto-assigné: %s pour colis %s",
                        nearest["relay_id"], parcel_id,
                    )
                    # Auto-transition vers REDIRECTED_TO_RELAY (le driver n'a pas à rappeler)
                    await transition_status(
                        parcel_id, ParcelStatus.REDIRECTED_TO_RELAY,
                        actor_id=actor_id, actor_role=actor_role,
                        notes=f"Redirection automatique vers relais {nearest['relay_id']}",
                        metadata={"redirect_relay_id": nearest["relay_id"]},
                    )

    # ── Mettre à jour la mission de livraison ──────────────────────────────────
    from models.delivery import MissionStatus

    # 1. Arrivée relais : compléter la mission si le point de chute est un relais
    relay_arrival_statuses = {
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
        ParcelStatus.AT_DESTINATION_RELAY,
        ParcelStatus.AVAILABLE_AT_RELAY
    }
    if new_status in relay_arrival_statuses:
        mission = await db.delivery_missions.find_one({
            "parcel_id": parcel_id,
            "status": {"$in": [MissionStatus.ASSIGNED.value, MissionStatus.IN_PROGRESS.value]}
        })
        if mission:
            if mission.get("delivery_type") == "relay":
                now = datetime.now(timezone.utc)
                await db.delivery_missions.update_one(
                    {"mission_id": mission["mission_id"]},
                    {"$set": {
                        "status": MissionStatus.COMPLETED.value,
                        "completed_at": now,
                        "updated_at":   now
                    }}
                )
                logger.info(f"Mission {mission['mission_id']} complétée via scan relais pour {parcel_id}")
            if mission.get("driver_id"):
                from services.loyalty_service import _check_referral_bonus

                await _check_referral_bonus(mission["driver_id"])

                # --- Déclenchement Phase 2 Transit ---
                p = await db.parcels.find_one({"parcel_id": parcel_id})
                if p and p.get("transit_relay_id") and p.get("status") == ParcelStatus.AT_DESTINATION_RELAY:
                    # On est au transit, on lance la mission vers la destination finale
                    logger.info(f"Handoff Transit : Déclenchement mission finale pour {parcel_id}")
                    await _create_delivery_mission(p, ParcelStatus.AT_DESTINATION_RELAY)

    # 2. États terminaux : TOUJOURS compléter/échouer la mission active
    if new_status == ParcelStatus.DELIVERED:
        mission = await db.delivery_missions.find_one({
            "parcel_id": parcel_id,
            "status": {"$in": [MissionStatus.ASSIGNED.value, MissionStatus.IN_PROGRESS.value]}
        })
        if mission:
            now = datetime.now(timezone.utc)
            await db.delivery_missions.update_one(
                {"mission_id": mission["mission_id"]},
                {"$set": {
                    "status": MissionStatus.COMPLETED.value,
                    "completed_at": now,
                    "updated_at":   now
                }}
            )
            logger.info(f"Mission {mission['mission_id']} complétée (colis livré) pour {parcel_id}")
            if mission.get("driver_id"):
                from services.loyalty_service import _check_referral_bonus

                await _check_referral_bonus(mission["driver_id"])

    elif new_status == ParcelStatus.DELIVERY_FAILED:
        mission = await db.delivery_missions.find_one({
            "parcel_id": parcel_id,
            "status": {"$in": [MissionStatus.ASSIGNED.value, MissionStatus.IN_PROGRESS.value]}
        })
        if mission:
            now = datetime.now(timezone.utc)
            # Au lieu d'échouer la mission, on la redirige vers le relais de repli
            # On récupère le relais assigné juste au-dessus
            updated_p = await db.parcels.find_one({"parcel_id": parcel_id}, {"redirect_relay_id": 1})
            rid = (updated_p or {}).get("redirect_relay_id")

            if rid:
                relay = await db.relay_points.find_one({"relay_id": rid}, {"_id": 0})
                if relay:
                    await db.delivery_missions.update_one(
                        {"mission_id": mission["mission_id"]},
                        {"$set": {
                            "delivery_type":    "relay",
                            "delivery_relay_id": rid,
                            "delivery_label":   relay.get("name", "Relais de repli"),
                            "delivery_city":    (relay.get("address") or {}).get("city", "Dakar"),
                            "delivery_geopin":  (relay.get("address") or {}).get("geopin"),
                            "updated_at":       now
                        }}
                    )
                    logger.info(f"Mission {mission['mission_id']} redirigée vers relais {rid} après échec livraison")
                    # On sort sans mettre FAILED
                    return await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})

            return_code = parcel.get("return_code") or _generate_delivery_code()
            await db.parcels.update_one(
                {"parcel_id": parcel_id},
                {"$set": {
                    "return_code": return_code,
                    "updated_at": now,
                }},
            )
            await db.delivery_missions.update_one(
                {"mission_id": mission["mission_id"]},
                {"$set": {
                    "status": MissionStatus.INCIDENT_REPORTED.value,
                    "failure_reason": "no_redirect_relay_available_return_to_sender",
                    "updated_at": now,
                }},
            )
            logger.info(
                "Aucun relais de repli proche/ouvert trouvé pour la mission %s / colis %s. "
                "Retour à l'expéditeur déclenché.",
                mission["mission_id"],
                parcel_id,
            )
            return await transition_status(
                parcel_id,
                ParcelStatus.INCIDENT_REPORTED,
                actor_id=actor_id,
                actor_role=actor_role,
                notes="Aucun relais de repli proche/ouvert. Retour à l'expéditeur requis.",
                metadata={
                    "fallback_action": "return_to_sender",
                    "reason": "no_nearby_open_relay",
                },
            )


    # Notifier le changement
    await notify_parcel_status_change(parcel, new_status)

    if new_status == ParcelStatus.DISPUTED:
        tracking = parcel.get("tracking_code") or parcel_id
        await record_admin_event(
            AdminEventType.PARCEL_DISPUTED,
            title=f"Litige ouvert — colis {tracking}",
            message=(notes or "Le colis est passé en litige"),
            href=f"/dashboard/parcels/{parcel_id}",
            metadata={
                "parcel_id": parcel_id,
                "tracking_code": tracking,
                "from_status": current_status.value,
                "actor_id": actor_id,
                "actor_role": actor_role,
            },
        )
    elif new_status == ParcelStatus.REDIRECTED_TO_RELAY:
        tracking = parcel.get("tracking_code") or parcel_id
        redirect_relay_id = (metadata or {}).get("redirect_relay_id") or parcel.get("redirect_relay_id")
        await record_admin_event(
            AdminEventType.PARCEL_REDIRECTED,
            title=f"Colis redirigé — {tracking}",
            message=(notes or "Livraison échouée, colis redirigé vers un relais de repli"),
            href=f"/dashboard/parcels/{parcel_id}",
            metadata={
                "parcel_id": parcel_id,
                "tracking_code": tracking,
                "redirect_relay_id": redirect_relay_id,
                "from_status": current_status.value,
            },
        )
    elif new_status == ParcelStatus.INCIDENT_REPORTED:
        tracking = parcel.get("tracking_code") or parcel_id
        await record_admin_event(
            AdminEventType.INCIDENT_REPORTED,
            title=f"Retour à l'expéditeur requis — {tracking}",
            message=(notes or "Incident signalé sur le colis"),
            href=f"/dashboard/parcels/{parcel_id}",
            metadata={
                "parcel_id": parcel_id,
                "tracking_code": tracking,
                "from_status": current_status.value,
                "actor_id": actor_id,
                "actor_role": actor_role,
                **(metadata or {}),
            },
        )
    elif new_status == ParcelStatus.CANCELLED:
        tracking = parcel.get("tracking_code") or parcel_id
        await record_admin_event(
            AdminEventType.PARCEL_CANCELLED,
            title=f"Colis annulé — {tracking}",
            message=(notes or "Colis annulé"),
            href=f"/dashboard/parcels/{parcel_id}",
            metadata={
                "parcel_id": parcel_id,
                "tracking_code": tracking,
                "from_status": current_status.value,
                "actor_id": actor_id,
                "actor_role": actor_role,
            },
        )

    updated = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    return updated


async def _create_delivery_mission(parcel: dict, from_status: ParcelStatus) -> None:
    """
    Crée une delivery_mission quand un colis passe en OUT_FOR_DELIVERY.
    - from AT_DESTINATION_RELAY : livreur prend au relais de destination
    - from CREATED              : livreur va chercher chez l'expéditeur (HOME_TO_*)
    - from IN_TRANSIT           : cas relay_to_home via transit
    """
    from models.delivery import MissionStatus

    # Éviter les doublons — seules les missions actives bloquent (pas les complétées/échouées)
    existing = await db.delivery_missions.find_one({
        "parcel_id": parcel["parcel_id"],
        "status": {"$in": ["pending", "assigned", "in_progress"]},
    })
    if existing:
        return

    mode = parcel.get("delivery_mode", "")
    if mode.startswith("home_to_") and not parcel.get("pickup_confirmed"):
        logger.info("Création mission suspendue pour %s : GPS expéditeur manquant.", parcel["parcel_id"])
        return

    # ── Point de collecte (pickup) ────────────────────────────────────────────
    if from_status == ParcelStatus.AT_DESTINATION_RELAY:
        # Livreur vient chercher au relais de destination
        relay_id = parcel.get("destination_relay_id")
        relay = await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0}) if relay_id else None
        pickup_type  = "relay"
        pickup_relay_id   = relay_id
        pickup_label = relay["name"] if relay else "Relais de destination"
        pickup_city  = (relay or {}).get("address", {}).get("city", "Dakar") if relay else "Dakar"
        pickup_geopin = ((relay or {}).get("address") or {}).get("geopin") if relay else None
    elif from_status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY:
        # Livreur vient chercher au relais d'origine (relay_to_home)
        relay_id = parcel.get("origin_relay_id")
        relay = await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0}) if relay_id else None
        pickup_type  = "relay"
        pickup_relay_id   = relay_id
        pickup_label = relay["name"] if relay else "Relais d'origine"
        pickup_city  = (relay or {}).get("address", {}).get("city", "Dakar") if relay else "Dakar"
        pickup_geopin = ((relay or {}).get("address") or {}).get("geopin") if relay else None
    else:
        # Livreur va chercher chez l'expéditeur (HOME_TO_*)
        pickup_loc = parcel.get("origin_location") or {}
        pickup_type  = "gps"
        pickup_relay_id   = None
        pickup_label = (pickup_loc.get("label") or pickup_loc.get("notes") or "Position expéditeur")
        pickup_city  = pickup_loc.get("city", "Dakar")
        pickup_geopin = pickup_loc.get("geopin")

    # ── Point de livraison ────────────────────────────────────────────────────
    delivery_addr = _current_delivery_location(parcel)
    delivery_label = (delivery_addr.get("label") or delivery_addr.get("notes") or "Adresse destinataire")
    delivery_city  = delivery_addr.get("city", "Dakar")
    delivery_geopin = delivery_addr.get("geopin")
    delivery_type   = "gps"
    delivery_relay_id = None

    # Si la destination est un relais (H2R ou R2R local)
    dest_relay_id = parcel.get("destination_relay_id")
    transit_relay_id = parcel.get("transit_relay_id")
    active_status = parcel.get("status")

    # 1. Cas Transit (Longue distance) : Si on doit passer par un relais scale
    # Uniquement pour le premier trajet (CREATED -> Transit)
    if transit_relay_id and active_status in [ParcelStatus.CREATED, ParcelStatus.OUT_FOR_DELIVERY]:
        transit_relay = await db.relay_points.find_one({"relay_id": transit_relay_id}, {"_id": 0})
        if transit_relay:
            delivery_type   = "relay"
            delivery_relay_id = transit_relay_id
            delivery_label  = f"Transit : {transit_relay['name']}"
            delivery_city   = (transit_relay.get("address") or {}).get("city", "Dakar")
            delivery_geopin = (transit_relay.get("address") or {}).get("geopin")
            logger.info(f"Cible mission : Transit Relay {transit_relay_id}")

    # 2. Cas Normal : Destination Relais (H2R, R2R) ou suite du transit (AT_DESTINATION_RELAY -> Final)
    elif dest_relay_id and not mode.endswith("_to_home"):
        # On ne crée la mission que si c'est R2R ou H2R (pas de confirmation GPS destinataire requise)
        dest_relay = await db.relay_points.find_one({"relay_id": dest_relay_id}, {"_id": 0})
        if dest_relay:
            delivery_type   = "relay"
            delivery_relay_id = dest_relay_id
            delivery_label  = dest_relay.get("name") or "Relais destination"
            delivery_city   = (dest_relay.get("address") or {}).get("city", "Dakar")
            delivery_geopin = (dest_relay.get("address") or {}).get("geopin")
    
    # ── Sécurité : Pour les livraisons à DOMICILE, il faut la confirmation GPS ──
    if delivery_type == "gps" and mode.endswith("_to_home"):
        if not parcel.get("delivery_confirmed"):
            logger.info(f"Création mission suspendue pour {parcel['parcel_id']} : GPS destinataire manquant.")
            return

    # ── Rémunération livreur selon le taux configuré ──────────────────────────
    quoted = parcel.get("quoted_price") or parcel.get("paid_price") or 0
    # HOME_TO_HOME : driver reçoit 85 % (pas de relais), sinon 70 %
    driver_rate = (settings.DRIVER_RATE + settings.RELAY_RATE
                   if mode == "home_to_home" else settings.DRIVER_RATE)
    earn_amount = round(quoted * driver_rate) + round(parcel.get("driver_bonus_xof", 0.0))

    now = datetime.now(timezone.utc)
    mission_doc = {
        "mission_id":       f"msn_{uuid.uuid4().hex[:12]}",
        "parcel_id":        parcel["parcel_id"],
        "tracking_code":    parcel.get("tracking_code"),
        "driver_id":        None,          # rempli quand un livreur accepte
        "status":           MissionStatus.PENDING.value,
        "sender_user_id":   parcel.get("sender_user_id"),
        "sender_name":      parcel.get("sender_name"),
        "recipient_user_id": parcel.get("recipient_user_id"),
        # Pickup
        "pickup_type":      pickup_type,   # 'relay' | 'gps'
        "pickup_relay_id":  pickup_relay_id,
        "pickup_label":     pickup_label,
        "pickup_city":      pickup_city,
        "pickup_geopin":    pickup_geopin,
        # Livraison
        "delivery_type":    delivery_type,             # 'gps' = domicile, 'relay' = relais
        "delivery_relay_id": delivery_relay_id,
        "delivery_label":   delivery_label,
        "delivery_city":    delivery_city,
        "delivery_geopin":  delivery_geopin,
        # Infos destinataire (pour appeler)
        "recipient_name":   parcel.get("recipient_name"),
        "recipient_phone":  parcel.get("recipient_phone"),
        "who_pays":         parcel.get("who_pays"),
        "payment_status":   parcel.get("payment_status"),
        "payment_method":   parcel.get("payment_method"),
        "payment_override": bool(parcel.get("payment_override")),
        "pickup_voice_note": parcel.get("pickup_voice_note"),
        "delivery_voice_note": parcel.get("delivery_voice_note"),
        # Rémunération
        "earn_amount":      earn_amount,
        # Dispatch en Cascade (Phase 7)
        "candidate_drivers": [],  # rempli après calcul
        "ping_index":        0,
        "ping_expires_at":   None,
        "is_broadcast":      False,
        # Tracking livreur
        "driver_location":     None,
        "location_updated_at": None,
        # Preuve
        "proof_type":    None,
        "proof_data":    None,
        "failure_reason": None,
        # Timestamps
        "assigned_at":   None,
        "completed_at":  None,
        "created_at":    now,
        "updated_at":    now,
    }
    
    # ── Calcul du Cascade ──
    if pickup_geopin:
        candidates = await _find_nearest_candidate_drivers(pickup_geopin["lat"], pickup_geopin["lng"])
        if candidates:
            mission_doc["candidate_drivers"] = candidates
            mission_doc["ping_expires_at"]   = now + timedelta(seconds=30)
            # Notifier le premier driver
            from services.notification_service import notify_new_mission_ping
            await notify_new_mission_ping(candidates[0], mission_doc)
        else:
            mission_doc["is_broadcast"] = True # Aucun livreur proche → broadcast immédiat
    else:
        mission_doc["is_broadcast"] = True

    await db.delivery_missions.insert_one(mission_doc)
    logger.info("Mission créée: %s pour colis %s (Cascade: %s)", 
                mission_doc["mission_id"], parcel["parcel_id"], not mission_doc["is_broadcast"])




async def _record_event(
    event_type: str,
    parcel_id: Optional[str] = None,
    from_status: Optional[ParcelStatus] = None,
    to_status: Optional[ParcelStatus] = None,
    actor_id: Optional[str] = None,
    actor_role: Optional[str] = None,
    notes: Optional[str] = None,
    metadata: Optional[dict] = None,
):
    """Insère un ParcelEvent dans la collection parcel_events."""
    event = {
        "event_id":    _event_id(),
        "parcel_id":   parcel_id,
        "event_type":  event_type,
        "from_status": from_status.value if from_status else None,
        "to_status":   to_status.value if to_status else None,
        "actor_id":    actor_id,
        "actor_role":  actor_role,
        "notes":       notes,
        "metadata":    metadata or {},
        "created_at":  datetime.now(timezone.utc),
    }
    await db.parcel_events.insert_one(event)


async def get_parcel_timeline(parcel_id: str) -> list:
    """Retourne les événements triés chronologiquement."""
    cursor = db.parcel_events.find(
        {"parcel_id": parcel_id},
        {"_id": 0},
    ).sort("created_at", 1)
    return await cursor.to_list(length=200)
