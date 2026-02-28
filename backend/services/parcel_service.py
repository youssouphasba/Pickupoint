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
from services.notification_service import notify_parcel_status_change
from services.otp_service import _send_via_twilio

logger = logging.getLogger(__name__)

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


async def _send_confirmation_sms(phone: str, token: str, role: str, base_url: str) -> None:
    """Envoie le lien de confirmation GPS par WhatsApp puis SMS en fallback."""
    url   = f"{base_url}/confirm/{token}"
    emoji = "📦" if role == "recipient" else "📤"
    msg   = (
        f"{emoji} Votre colis PickuPoint est prêt !\n"
        f"Confirmez votre position de {'livraison' if role == 'recipient' else 'collecte'} :\n"
        f"{url}\n"
        f"(Appuyez sur le lien, puis sur le grand bouton 📍)"
    )
    await _send_via_twilio(phone, msg)


async def create_parcel(data: ParcelCreate, sender_user_id: str) -> dict:
    """Crée un nouveau colis avec devis et tracking code."""
    from models.parcel import ParcelQuote
    quote_req = ParcelQuote(
        delivery_mode=data.delivery_mode,
        origin_relay_id=data.origin_relay_id,
        destination_relay_id=data.destination_relay_id,
        delivery_address=data.delivery_address,
        weight_kg=data.weight_kg,
        is_insured=data.is_insured,
        declared_value=data.declared_value,
    )
    quote: QuoteResponse = await calculate_price(quote_req)

    from config import settings
    from routers.confirm import generate_confirm_tokens

    now = datetime.now(timezone.utc)
    parcel_id     = _parcel_id()
    tracking_code = generate_tracking_code()
    expires_at    = now + timedelta(days=7)

    recipient_token, sender_token = generate_confirm_tokens()

    # Mode : expéditeur initie (normal) ou destinataire initie (inverse)
    initiated_by = getattr(data, "initiated_by", "sender")

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
        "weight_kg":             data.weight_kg,
        "dimensions":            data.dimensions,
        "declared_value":        data.declared_value,
        "is_insured":            data.is_insured,
        "description":           data.description,
        "quoted_price":          quote.price,
        "paid_price":            None,
        "payment_status":        "pending",
        "payment_method":        None,
        "payment_ref":           None,
        "status":                ParcelStatus.CREATED.value,
        "assigned_driver_id":    None,
        "redirect_relay_id":     None,
        "external_ref":          None,
        # ── Confirmation GPS bidirectionnelle ──
        "initiated_by":          initiated_by,
        "recipient_confirm_token": recipient_token,
        "sender_confirm_token":    sender_token,
        "delivery_confirmed":    False,
        "pickup_confirmed":      bool(data.origin_location),   # True si GPS déjà fourni dans l'app
        "delivery_location":     None,  # confirmé par destinataire
        "pickup_location":       data.origin_location.model_dump() if data.origin_location else None,
        "delivery_voice_note":   None,
        "pickup_voice_note":     None,
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

    # ── Envoi SMS/WhatsApp automatique ──────────────────────────────────────
    base_url = getattr(settings, "BASE_URL", "https://pickupoint-production.up.railway.app")

    # Modes domicile → envoyer lien GPS au destinataire pour confirmer sa position
    _home_dest_modes = {DeliveryMode.RELAY_TO_HOME, DeliveryMode.HOME_TO_HOME}
    if data.delivery_mode in _home_dest_modes:
        await _send_confirmation_sms(data.recipient_phone, recipient_token, "recipient", base_url)

    # Modes collecte domicile → envoyer lien GPS à l'expéditeur (si pas déjà capturé dans l'app)
    _home_origin_modes = {DeliveryMode.HOME_TO_HOME, DeliveryMode.HOME_TO_RELAY}
    if data.delivery_mode in _home_origin_modes and not data.origin_location:
        # Envoyer le lien de confirmation de collecte à l'expéditeur lui-même
        sender_phone = getattr(data, "sender_phone", None)
        if sender_phone:
            await _send_confirmation_sms(sender_phone, sender_token, "sender", base_url)

    if initiated_by == "recipient":
        # Flux inverse : envoyer lien à l'expéditeur physique pour confirmer le pickup
        sender_phone = getattr(data, "sender_phone", None)
        if sender_phone:
            await _send_confirmation_sms(sender_phone, sender_token, "sender", base_url)

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
