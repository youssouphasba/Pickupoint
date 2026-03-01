"""
Service colis : machine d'états, event sourcing, transitions métier.
"""
import logging
import math
import uuid
from datetime import datetime, timezone, timedelta
from typing import Optional

from database import db
from core.exceptions import bad_request_exception
from core.security import generate_tracking_code
from models.common import ParcelStatus, DeliveryMode
from models.parcel import ParcelCreate, ParcelEvent, QuoteResponse
from services.pricing_service import calculate_price
from services.wallet_service import distribute_delivery_revenue
from services.notification_service import notify_parcel_status_change, notify_delivery_code

import random
logger = logging.getLogger(__name__)

def _generate_code() -> str:
    """Génère un code numérique à 6 chiffres."""
    return f"{random.randint(100000, 999999)}"

# ── Machine d'états ───────────────────────────────────────────────────────────
ALLOWED_TRANSITIONS: dict[ParcelStatus, list[ParcelStatus]] = {
    ParcelStatus.CREATED: [
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
        ParcelStatus.OUT_FOR_DELIVERY,   # HOME_TO_* : driver vient chercher chez l'expéditeur
        ParcelStatus.CANCELLED,
    ],
    ParcelStatus.DROPPED_AT_ORIGIN_RELAY: [
        ParcelStatus.IN_TRANSIT,
        ParcelStatus.CANCELLED,
    ],
    ParcelStatus.IN_TRANSIT: [
        ParcelStatus.AT_DESTINATION_RELAY,
        ParcelStatus.OUT_FOR_DELIVERY,
    ],
    ParcelStatus.AT_DESTINATION_RELAY: [
        ParcelStatus.AVAILABLE_AT_RELAY,
        ParcelStatus.OUT_FOR_DELIVERY,
    ],
    ParcelStatus.AVAILABLE_AT_RELAY: [
        ParcelStatus.DELIVERED,
        ParcelStatus.EXPIRED,
    ],
    ParcelStatus.OUT_FOR_DELIVERY: [
        ParcelStatus.DELIVERED,
        ParcelStatus.DELIVERY_FAILED,
    ],
    ParcelStatus.DELIVERY_FAILED: [
        ParcelStatus.REDIRECTED_TO_RELAY,
        ParcelStatus.RETURNED,
    ],
    ParcelStatus.REDIRECTED_TO_RELAY: [
        ParcelStatus.AVAILABLE_AT_RELAY,
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


async def find_nearest_relay(lat: float, lng: float) -> Optional[dict]:
    """Retourne le relais actif le plus proche d'une coordonnée GPS."""
    relays = await db.relay_points.find(
        {"is_active": True},
        {"_id": 0, "relay_id": 1, "name": 1, "address": 1},
    ).to_list(length=500)

    nearest, min_dist = None, float("inf")
    for relay in relays:
        geopin = (relay.get("address") or {}).get("geopin")
        if geopin and geopin.get("lat") is not None and geopin.get("lng") is not None:
            dist = _haversine_km(lat, lng, geopin["lat"], geopin["lng"])
            if dist < min_dist:
                min_dist, nearest = dist, relay
    return nearest


async def create_parcel(data: ParcelCreate, sender_user_id: str) -> dict:
    """Crée un nouveau colis avec devis et tracking code."""
    from models.parcel import ParcelQuote
    quote_req = ParcelQuote(
        delivery_mode=data.delivery_mode,
        origin_relay_id=data.origin_relay_id,
        destination_relay_id=data.destination_relay_id,
        origin_location=data.origin_location,
        delivery_address=data.delivery_address,
        weight_kg=data.weight_kg,
        is_insured=data.is_insured,
        declared_value=data.declared_value,
        is_express=data.is_express,
        who_pays=data.who_pays,
    )
    quote: QuoteResponse = await calculate_price(quote_req)

    now = datetime.now(timezone.utc)
    parcel_id     = _parcel_id()
    tracking_code = generate_tracking_code()
    expires_at    = now + timedelta(days=7)

    parcel_doc = {
        "parcel_id":             parcel_id,
        "tracking_code":         tracking_code,
        "sender_user_id":        sender_user_id,
        "recipient_phone":       data.recipient_phone,
        "recipient_name":        data.recipient_name,
        "delivery_mode":         data.delivery_mode.value,
        "origin_relay_id":       data.origin_relay_id,
        "destination_relay_id":  data.destination_relay_id,
        "delivery_address":      data.delivery_address.model_dump() if data.delivery_address else None,
        "origin_location":       data.origin_location.model_dump() if data.origin_location else None,
        "weight_kg":             data.weight_kg,
        "dimensions":            data.dimensions,
        "declared_value":        data.declared_value,
        "is_insured":            data.is_insured,
        "description":           data.description,
        "is_express":            data.is_express,
        "who_pays":              data.who_pays,
        "quote_breakdown":       quote.breakdown,
        "quoted_price":          quote.price,
        "pickup_code":           _generate_code(),
        "delivery_code":         _generate_code(),
        "paid_price":            None,
        "payment_status":        "pending",
        "payment_method":        None,
        "payment_ref":           None,
        "status":                ParcelStatus.CREATED.value,
        "assigned_driver_id":    None,
        "redirect_relay_id":     None,
        "external_ref":          None,
        "created_at":            now,
        "updated_at":            now,
        "expires_at":            expires_at,
    }
    await db.parcels.insert_one(parcel_doc)
    await _record_event(
        parcel_id=parcel_id,
        event_type="PARCEL_CREATED",
        to_status=ParcelStatus.CREATED,
        actor_id=sender_user_id,
        actor_role="client",
    )

    # ── Envoyer le code de livraison au destinataire par SMS/WhatsApp ──
    await notify_delivery_code(
        phone=data.recipient_phone,
        recipient_name=data.recipient_name,
        tracking_code=tracking_code,
        delivery_code=parcel_doc["delivery_code"],
    )

    return {k: v for k, v in parcel_doc.items() if k != "_id"}


async def transition_status(
    parcel_id: str,
    new_status: ParcelStatus,
    actor_id: str,
    actor_role: str,
    notes: Optional[str] = None,
    metadata: Optional[dict] = None,
) -> dict:
    """
    Transition officielle de la machine d'états.
    Valide la transition, met à jour MongoDB, enregistre l'événement.
    """
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise bad_request_exception("Colis introuvable")

    current_status = ParcelStatus(parcel["status"])
    allowed = ALLOWED_TRANSITIONS.get(current_status, [])
    if new_status not in allowed:
        raise bad_request_exception(
            f"Transition interdite : {current_status.value} → {new_status.value}"
        )

    now = datetime.now(timezone.utc)
    await db.parcels.update_one(
        {"parcel_id": parcel_id},
        {"$set": {"status": new_status.value, "updated_at": now}},
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

    # Créer mission livreur quand le colis passe en OUT_FOR_DELIVERY (livraison domicile)
    # OU quand le colis est déposé au relais origine (pour le transit relay_to_relay)
    if new_status == ParcelStatus.OUT_FOR_DELIVERY:
        await _create_delivery_mission(parcel, current_status)
    elif new_status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY:
        await _create_relay_transit_mission(parcel)

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


    # Notifier le changement
    await notify_parcel_status_change(parcel, new_status)

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

    # Éviter les doublons
    existing = await db.delivery_missions.find_one({"parcel_id": parcel["parcel_id"]})
    if existing:
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
    else:
        # Livreur va chercher chez l'expéditeur (HOME_TO_*)
        pickup_loc = parcel.get("pickup_location") or {}
        pickup_type  = "gps"
        pickup_relay_id   = None
        pickup_label = (pickup_loc.get("label") or pickup_loc.get("notes") or "Position expéditeur")
        pickup_city  = pickup_loc.get("city", "Dakar")
        pickup_geopin = pickup_loc.get("geopin")

    # ── Point de livraison ────────────────────────────────────────────────────
    delivery_addr = parcel.get("delivery_address") or {}
    delivery_label = (delivery_addr.get("label") or delivery_addr.get("notes") or "Adresse destinataire")
    delivery_city  = delivery_addr.get("city", "Dakar")
    delivery_geopin = delivery_addr.get("geopin")

    # ── Rémunération livreur selon le taux configuré ──────────────────────────
    from config import settings
    quoted = parcel.get("quoted_price") or parcel.get("paid_price") or 0
    mode   = parcel.get("delivery_mode", "")
    # HOME_TO_HOME : driver reçoit 85 % (pas de relais), sinon 70 %
    driver_rate = (settings.DRIVER_RATE + settings.RELAY_RATE
                   if mode == "home_to_home" else settings.DRIVER_RATE)
    earn_amount = round(quoted * driver_rate)

    now = datetime.now(timezone.utc)
    mission_doc = {
        "mission_id":       f"msn_{uuid.uuid4().hex[:12]}",
        "parcel_id":        parcel["parcel_id"],
        "tracking_code":    parcel.get("tracking_code"),
        "driver_id":        None,          # rempli quand un livreur accepte
        "status":           MissionStatus.PENDING.value,
        # Pickup
        "pickup_type":      pickup_type,   # 'relay' | 'gps'
        "pickup_relay_id":  pickup_relay_id,
        "pickup_label":     pickup_label,
        "pickup_city":      pickup_city,
        "pickup_geopin":    pickup_geopin,
        # Livraison
        "delivery_label":   delivery_label,
        "delivery_city":    delivery_city,
        "delivery_geopin":  delivery_geopin,
        # Infos destinataire (pour appeler)
        "recipient_name":   parcel.get("recipient_name"),
        "recipient_phone":  parcel.get("recipient_phone"),
        # Rémunération
        "earn_amount":      earn_amount,
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
    await db.delivery_missions.insert_one(mission_doc)
    logger.info("Mission créée: %s pour colis %s", mission_doc["mission_id"], parcel["parcel_id"])


async def _create_relay_transit_mission(parcel: dict) -> None:
    """
    Crée une mission de transit relay_to_relay quand le colis passe en DROPPED_AT_ORIGIN_RELAY.
    Le livreur transporte du relais origine au relais destination.
    """
    from models.delivery import MissionStatus

    # Éviter les doublons
    existing = await db.delivery_missions.find_one({"parcel_id": parcel["parcel_id"]})
    if existing:
        return

    # Pickup = relais origine
    origin_id = parcel.get("origin_relay_id")
    origin = await db.relay_points.find_one({"relay_id": origin_id}, {"_id": 0}) if origin_id else None
    pickup_label  = origin["name"] if origin else "Relais origine"
    pickup_city   = (origin or {}).get("address", {}).get("city", "Dakar")
    pickup_geopin = ((origin or {}).get("address") or {}).get("geopin")

    # Livraison = relais destination
    dest_id = parcel.get("destination_relay_id")
    dest    = await db.relay_points.find_one({"relay_id": dest_id}, {"_id": 0}) if dest_id else None
    delivery_label  = dest["name"] if dest else "Relais destination"
    delivery_city   = (dest or {}).get("address", {}).get("city", "Dakar")
    delivery_geopin = ((dest or {}).get("address") or {}).get("geopin")

    from config import settings
    quoted      = parcel.get("quoted_price") or 0
    earn_amount = round(quoted * settings.DRIVER_RATE)

    now = datetime.now(timezone.utc)
    mission_doc = {
        "mission_id":       f"msn_{uuid.uuid4().hex[:12]}",
        "parcel_id":        parcel["parcel_id"],
        "tracking_code":    parcel.get("tracking_code"),
        "driver_id":        None,
        "status":           MissionStatus.PENDING.value,
        "pickup_type":      "relay",
        "pickup_relay_id":  origin_id,
        "pickup_label":     pickup_label,
        "pickup_city":      pickup_city,
        "pickup_geopin":    pickup_geopin,
        "delivery_label":   delivery_label,
        "delivery_city":    delivery_city,
        "delivery_geopin":  delivery_geopin,
        "recipient_name":   parcel.get("recipient_name"),
        "recipient_phone":  parcel.get("recipient_phone"),
        "earn_amount":      earn_amount,
        "driver_location":     None,
        "location_updated_at": None,
        "proof_type":    None,
        "proof_data":    None,
        "failure_reason": None,
        "assigned_at":   None,
        "completed_at":  None,
        "created_at":    now,
        "updated_at":    now,
    }
    await db.delivery_missions.insert_one(mission_doc)
    logger.info("Mission transit relay_to_relay: %s pour colis %s",
                mission_doc["mission_id"], parcel["parcel_id"])


async def _record_event(
    parcel_id: str,
    event_type: str,
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
