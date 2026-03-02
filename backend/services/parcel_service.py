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
from services.payment_service import create_payment_link

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
        ParcelStatus.IN_TRANSIT,         # HOME_TO_RELAY : driver part de l'expéditeur vers le relais
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


async def create_parcel(data: ParcelCreate, sender_user_id: str, sender_phone: str = "") -> dict:
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
        "recipient_user_id":     None,  # Lié ci-dessous
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

    # ── Gestion de la confirmation de position destinataire ──
    requires_recipient_gps = data.delivery_mode.value.endswith("_to_home")
    recipient_token = None
    if requires_recipient_gps:
        from routers.confirm import generate_confirm_tokens
        recipient_token, sender_token = generate_confirm_tokens()
        parcel_doc["recipient_confirm_token"] = recipient_token
        parcel_doc["sender_confirm_token"]    = sender_token
        parcel_doc["delivery_confirmed"]      = False
        parcel_doc["pickup_confirmed"]        = True # Saisi dans l'app direct

    # ── Liaison automatique du destinataire si compte existant ──
    recipient_user = await db.users.find_one({"phone": data.recipient_phone}, {"user_id": 1})
    if recipient_user:
        parcel_doc["recipient_user_id"] = recipient_user["user_id"]

    await db.parcels.insert_one(parcel_doc)
    
    # Trigger mission immediately for Home-top-Relay or Home-to-Home
    # Payment status does not block mission creation
    if requires_recipient_gps or data.delivery_mode.value == "home_to_relay":
        # Note: requires_recipient_gps is true for *_to_home, which covers home_to_home
        # home_to_relay also needs an immediate pickup mission
        if data.delivery_mode.value.startswith("home_to_"):
            await _create_delivery_mission(parcel_doc, ParcelStatus.CREATED)

    await _record_event(
        parcel_id=parcel_id,
        event_type="PARCEL_CREATED",
        to_status=ParcelStatus.CREATED,
        actor_id=sender_user_id,
        actor_role="client",
    )

    # ── Générer le lien de paiement Flutterwave (si l'expéditeur paye) ──
    payment_url = None
    if data.who_pays == "sender":
        payment_res = await create_payment_link(
            parcel_id=parcel_id,
            tracking_code=tracking_code,
            amount=quote.price,
            customer_phone=sender_phone,
            customer_name=data.recipient_name if data.initiated_by == "recipient" else "L'expéditeur",
        )
        if payment_res.get("success"):
            payment_url = payment_res["payment_link"]
            # Optionnel : stocker le tx_ref dans le doc
            await db.parcels.update_one(
                {"parcel_id": parcel_id},
                {"$set": {"payment_ref": payment_res.get("tx_ref")}}
            )

    # ── Envoyer le code de livraison au destinataire par SMS/WhatsApp ──
    await notify_delivery_code(
        phone=data.recipient_phone,
        recipient_name=data.recipient_name,
        tracking_code=tracking_code,
        delivery_code=parcel_doc["delivery_code"],
        payment_url=payment_url if data.who_pays == "recipient" else None, # On envoie le lien au destinataire s'il paye
    )

    # ── Envoyer le lien de confirmation GPS (SMS / WhatsApp) ──
    from config import settings
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
            from services.notification_service import _send_sms
            await _send_sms(data.recipient_phone, msg)
        except Exception as e:
            logger.warning(f"SMS de confirmation GPS non envoyé : {e}")

    result = {k: v for k, v in parcel_doc.items() if k != "_id"}
    result["payment_url"] = payment_url
    if recipient_confirm_url:
        result["recipient_confirm_url"] = recipient_confirm_url

    # Générer la mission immédiatement UNIQUEMENT pour home_to_relay 
    # (car home_to_home doit attendre la validation GPS du destinataire)
    if data.delivery_mode.value == "home_to_relay":
        await _create_delivery_mission(parcel_doc, ParcelStatus.CREATED)

    return result


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
        # ── Gamification (Phase 8) ──
        driver_id = parcel.get("assigned_driver_id")
        if driver_id:
            from services.gamification_service import update_driver_gamification
            await update_driver_gamification(driver_id, "delivery_completed")

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

    # ── Mettre à jour la mission de livraison si elle se termine au relais ──
    relay_arrival_statuses = {
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
        ParcelStatus.AT_DESTINATION_RELAY,
        ParcelStatus.AVAILABLE_AT_RELAY
    }
    if new_status in relay_arrival_statuses:
        from models.delivery import MissionStatus
        mission = await db.delivery_missions.find_one({
            "parcel_id": parcel_id,
            "status": {"$in": [MissionStatus.ASSIGNED.value, MissionStatus.IN_PROGRESS.value]}
        })
        if mission:
            # Si le point de chute final de cette mission est un relais
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
    delivery_addr = parcel.get("delivery_address") or {}
    delivery_label = (delivery_addr.get("label") or delivery_addr.get("notes") or "Adresse destinataire")
    delivery_city  = delivery_addr.get("city", "Dakar")
    delivery_geopin = delivery_addr.get("geopin")
    delivery_type   = "gps"
    delivery_relay_id = None

    # Si la destination est un relais (H2R ou R2R local)
    dest_relay_id = parcel.get("destination_relay_id")
    mode = parcel.get("delivery_mode", "")
    
    # Pour H2R et R2R, si ce n'est pas une livraison finale à domicile
    if dest_relay_id and not mode.endswith("_to_home"):
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
        "delivery_type":    delivery_type,             # 'gps' = domicile, 'relay' = relais
        "delivery_relay_id": delivery_relay_id,
        "delivery_label":   delivery_label,
        "delivery_city":    delivery_city,
        "delivery_geopin":  delivery_geopin,
        # Infos destinataire (pour appeler)
        "recipient_name":   parcel.get("recipient_name"),
        "recipient_phone":  parcel.get("recipient_phone"),
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
