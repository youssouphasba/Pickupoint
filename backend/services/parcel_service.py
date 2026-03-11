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
    """Génère un code numérique à 6 chiffres (pickup_code livreur)."""
    return f"{random.randint(100000, 999999)}"


def _generate_delivery_code() -> str:
    """Génère un code numérique à 4 chiffres (delivery_code destinataire domicile)."""
    return f"{random.randint(1000, 9999)}"

# ── Machine d'états ───────────────────────────────────────────────────────────
ALLOWED_TRANSITIONS: dict[ParcelStatus, list[ParcelStatus]] = {
    ParcelStatus.CREATED: [
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
        ParcelStatus.OUT_FOR_DELIVERY,   # HOME_TO_* : driver vient chercher chez l'expéditeur
        ParcelStatus.IN_TRANSIT,         # HOME_TO_RELAY : driver part de l'expéditeur vers le relais
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
        ParcelStatus.AT_DESTINATION_RELAY,  # H2R : driver livre au relais destinataire
        ParcelStatus.INCIDENT_REPORTED,
        ParcelStatus.SUSPENDED,
    ],
    ParcelStatus.DELIVERY_FAILED: [
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
    from services.user_service import _compute_tier
    
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
        is_insured=data.is_insured,
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

    mode = data.delivery_mode.value

    # GPS prioritaire : pour toute collecte domicile, l'expéditeur doit être géolocalisé
    if mode.startswith("home_to_"):
        if not data.origin_location or not data.origin_location.geopin:
            raise bad_request_exception("La position GPS de l'expéditeur est obligatoire pour ce mode de livraison")

    now = datetime.now(timezone.utc)
    parcel_id     = _parcel_id()
    tracking_code = generate_tracking_code()
    expires_at    = now + timedelta(days=7)

    parcel_doc = {
        "parcel_id":             parcel_id,
        "tracking_code":         tracking_code,
        "sender_user_id":        sender_user_id,
        "sender_name":           sender_name_str,
        "recipient_phone":       data.recipient_phone,
        "recipient_name":        data.recipient_name,
        "recipient_user_id":     None,  # Lié ci-dessous
        "delivery_mode":         data.delivery_mode.value,
        "origin_relay_id":       data.origin_relay_id,
        "destination_relay_id":  data.destination_relay_id,
        "delivery_address":      data.delivery_address.model_dump() if data.delivery_address else None,
        "origin_location":       data.origin_location.model_dump() if data.origin_location else None,
        "pickup_voice_note":    data.pickup_voice_note,
        "delivery_voice_note":  data.delivery_voice_note,
        "weight_kg":             data.weight_kg,
        "dimensions":            data.dimensions,
        "declared_value":        data.declared_value,
        "is_insured":            data.is_insured,
        "description":           data.description,
        "is_express":            data.is_express,
        "who_pays":              data.who_pays,
        "quote_breakdown":       quote.breakdown,
        "quoted_price":          quote.price,
        "pickup_code":           _generate_code(),          # 6 chiffres — livreur collecte
        "delivery_code":         _generate_delivery_code(), # 4 chiffres — destinataire domicile
        "relay_pin":             f"{random.randint(1000, 9999)}",  # 4 chiffres — retrait relais
        "paid_price":            None,
        "payment_status":        "pending",
        "payment_method":        None,
        "payment_ref":           None,
        "initiated_by":          data.initiated_by if hasattr(data, 'initiated_by') else "sender",
        "delivery_confirmed":    data.delivery_mode.value.endswith("_to_relay"), 
        "pickup_confirmed":      False,
        "status":                ParcelStatus.CREATED.value,
        "promo_id":              quote.promo_applied.get("promo_id") if quote.promo_applied else None,
        "assigned_driver_id":    None,
        "redirect_relay_id":     None,
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

    # ── Gestion de la confirmation GPS (destinataire + expéditeur) ──
    requires_recipient_gps = data.delivery_mode.value.endswith("_to_home")
    requires_sender_gps_confirmation = (
        data.delivery_mode.value.startswith("home_to_")
        and data.initiated_by == "recipient"
        and bool(data.sender_phone)
    )

    recipient_token = None
    sender_token = None
    if requires_recipient_gps or requires_sender_gps_confirmation:
        from routers.confirm import generate_confirm_tokens
        recipient_token, sender_token = generate_confirm_tokens()

    if requires_recipient_gps and recipient_token:
        parcel_doc["recipient_confirm_token"] = recipient_token
        parcel_doc["delivery_confirmed"] = False

    if requires_sender_gps_confirmation and sender_token:
        parcel_doc["sender_confirm_token"] = sender_token
        parcel_doc["pickup_confirmed"] = False

    # ── Liaison automatique du destinataire si compte existant ──
    recipient_user = await db.users.find_one({"phone": data.recipient_phone}, {"user_id": 1})
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

    # ── Générer le lien de paiement Flutterwave (pour le payeur désigné) ──
    payment_url = None
    payer_phone = sender_phone if data.who_pays == "sender" else data.recipient_phone
    payer_name  = sender_name_str if data.who_pays == "sender" else data.recipient_name

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

    sender_confirm_url = None
    if requires_sender_gps_confirmation and sender_token and data.sender_phone:
        sender_confirm_url = f"{settings.BASE_URL}/confirm/{sender_token}"
        try:
            from services.notification_service import _send_sms
            await _send_sms(
                data.sender_phone,
                f"Confirmez votre position GPS pour l'enlèvement du colis {tracking_code}: {sender_confirm_url}"
            )
        except Exception as e:
            logger.warning(f"SMS confirmation GPS expéditeur non envoyé : {e}")

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

            await db.delivery_missions.update_one(
                {"mission_id": mission["mission_id"]},
                {"$set": {
                    "status": MissionStatus.FAILED.value,
                    "completed_at": now,
                    "updated_at":   now
                }}
            )
            logger.info(f"Mission {mission['mission_id']} échouée (pas de repli possible) pour {parcel_id}")


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
    

    # ── Sécurité : Pour les collectes à DOMICILE, il faut la confirmation GPS expéditeur ──
    if pickup_type == "gps" and mode.startswith("home_to_"):
        if not parcel.get("pickup_confirmed"):
            logger.info(f"Création mission suspendue pour {parcel['parcel_id']} : GPS expéditeur manquant.")
            return

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
