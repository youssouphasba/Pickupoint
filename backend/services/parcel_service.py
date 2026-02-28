"""
Service colis : machine d'états, event sourcing, transitions métier.
"""
import logging
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

logger = logging.getLogger(__name__)

# ── Machine d'états ───────────────────────────────────────────────────────────
ALLOWED_TRANSITIONS: dict[ParcelStatus, list[ParcelStatus]] = {
    ParcelStatus.CREATED: [
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
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

    now = datetime.now(timezone.utc)
    parcel_id = _parcel_id()
    tracking_code = generate_tracking_code()

    # TTL 7 jours pour les colis en relais
    expires_at = now + timedelta(days=7)

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
