"""
Router parcels : CRUD colis + toutes les actions de transition de la machine d'états.
"""
import logging
import uuid
from datetime import datetime, timezone
logger = logging.getLogger(__name__)
from typing import Optional

from fastapi import APIRouter, Depends, Query

from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, forbidden_exception, bad_request_exception
from database import db
from models.common import UserRole, ParcelStatus
from models.parcel import ParcelCreate, Parcel, ParcelQuote, QuoteResponse, FailDeliveryRequest, RedirectRelayRequest, ParcelRatingRequest, LocationConfirmPayload
from models.delivery import ProofOfDelivery, CodeDelivery
from services.parcel_service import create_parcel, transition_status, get_parcel_timeline, _create_delivery_mission
from services.pricing_service import calculate_price, _haversine_km
from services.wallet_service import credit_wallet, debit_wallet

router = APIRouter()


@router.post("/quote", response_model=QuoteResponse, summary="Calculer un devis (sans créer)")
async def quote_parcel(body: ParcelQuote):
    return await calculate_price(body)


@router.post("/check-promo", summary="Vérifier un code promo (Client)")
async def check_promo(
    body: dict,
    current_user: dict = Depends(get_current_user),
):
    code = body.get("promo_code", "").upper().strip()
    price = body.get("price", 0)
    mode  = body.get("delivery_mode", "relay_to_relay")

    if not code:
        raise bad_request_exception("Code promo manquant")

    from services.promotion_service import find_best_promo
    # Pour check-promo, on peut être moins strict sur is_first_delivery s'il ne s'agit que d'une vérification
    # Mais if faut quand même le bon tier
    user = await db.users.find_one({"user_id": current_user["user_id"]})
    sender_tier = user.get("loyalty_tier", "bronze") if user else "bronze"
    
    result = await find_best_promo(
        db, 
        delivery_mode=mode, 
        original_price=price,
        user_id=current_user["user_id"],
        user_tier=sender_tier,
        is_first_delivery=False, # Simplification pour le check
        promo_code=code,
    )
    if not result:
        raise not_found_exception("Code promo invalide ou non applicable")

    return {
        "valid":         True,
        "promo_title":   result["promo"]["title"],
        "discount_xof":  result["discount_xof"],
        "final_price":   result["final_price"],
    }


@router.post("", summary="Créer un colis")
async def create_parcel_endpoint(
    body: ParcelCreate,
    current_user: dict = Depends(get_current_user),
):
    parcel = await create_parcel(
        body, 
        sender_user_id=current_user["user_id"],
        sender_phone=current_user.get("phone", "")
    )
    return parcel


@router.get("", summary="Mes colis")
async def list_parcels(
    status: Optional[str] = None,
    role_view: Optional[str] = None,
    skip: int = 0,
    limit: int = 50,
    current_user: dict = Depends(get_current_user),
):
    role = current_user["role"]
    if role_view == "client":
        role = UserRole.CLIENT.value

    if role in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]:
        query: dict = {}
    elif role == UserRole.DRIVER.value:
        query = {"assigned_driver_id": current_user["user_id"]}
    elif role == UserRole.RELAY_AGENT.value:
        relay_id = current_user.get("relay_point_id")
        query = {
            "$or": [{"origin_relay_id": relay_id}, {"destination_relay_id": relay_id}]
        } if relay_id else {"sender_user_id": current_user["user_id"]}
    else:
        # Client : voit ses colis ENVOYÉS et les colis qu'il reçoit (recipient_phone)
        query = {
            "$or": [
                {"sender_user_id": current_user["user_id"]},
                {"recipient_user_id": current_user["user_id"]},
                {"recipient_phone": current_user.get("phone")},
            ]
        }

    if status:
        query["status"] = status

    cursor = db.parcels.find(query, {"_id": 0}).skip(skip).limit(limit)
    parcels = await cursor.to_list(length=limit)
    total = await db.parcels.count_documents(query)

    # Enrichir chaque colis avec is_recipient pour Flutter
    if role not in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]:
        uid = current_user["user_id"]
        uphone = current_user.get("phone", "")
        for p in parcels:
            p["is_recipient"] = (
                p.get("recipient_user_id") == uid
                or (p.get("recipient_phone") and uphone and p["recipient_phone"].endswith(uphone[-9:]))
            )

    return {"parcels": parcels, "total": total}


from core.utils import mask_phone

@router.get("/{parcel_id}/driver-location", summary="Position GPS du livreur actif pour ce colis")
async def get_driver_location(parcel_id: str, current_user: dict = Depends(get_current_user)):
    mission = await db.delivery_missions.find_one(
        {"parcel_id": parcel_id, "status": {"$in": ["assigned", "in_progress"]}},
        {"_id": 0, "driver_location": 1, "eta_text": 1, "distance_text": 1, "eta_seconds": 1},
    )
    if not mission or not mission.get("driver_location"):
        raise not_found_exception("No driver location available")
    return mission


@router.get("/{parcel_id}", summary="Détail + timeline")
async def get_parcel(parcel_id: str, current_user: dict = Depends(get_current_user)):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    
    # Déterminer le rôle du viewer AVANT le masquage
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    is_sender = parcel.get("sender_user_id") == current_user["user_id"]
    is_recipient = (
        parcel.get("recipient_user_id") == current_user["user_id"]
        or (
            parcel.get("recipient_phone")
            and current_user.get("phone")
            and parcel["recipient_phone"].endswith(current_user["phone"][-9:])
        )
    )

    # Injecter le flag dans la réponse (Flutter l'utilise pour l'UX)
    parcel["is_recipient"] = bool(is_recipient)

    if not is_admin:
        # Masquer le téléphone
        if "recipient_phone" in parcel:
            parcel["recipient_phone"] = mask_phone(parcel["recipient_phone"])

        # Sécurité des codes :
        # L'expéditeur ne doit pas voir le delivery_code/relay_pin (PIN du destinataire)
        # Le destinataire ne doit pas voir le pickup_code (PIN de collecte)
        if is_sender and not is_recipient:
            parcel.pop("delivery_code", None)
            parcel.pop("relay_pin", None)
        if is_recipient and not is_sender:
            parcel.pop("pickup_code", None)

        # Filtrage par mode : ne montrer que le code pertinent pour le destinataire/admin
        mode = parcel.get("delivery_mode", "")
        if mode.endswith("_to_home"):
            parcel.pop("relay_pin", None)
        elif mode.endswith("_to_relay"):
            parcel.pop("delivery_code", None)

    timeline = await get_parcel_timeline(parcel_id)
    
    # ── Enrichissement avec Photos ──
    # Sender
    sender = await db.users.find_one({"user_id": parcel.get("sender_user_id")}, {"profile_picture_url": 1})
    if sender:
        parcel["sender_photo_url"] = sender.get("profile_picture_url")
    
    # Recipient (le chercher par phone s'il n'est pas lié par ID)
    recipient_uid = parcel.get("recipient_user_id")
    if not recipient_uid and parcel.get("recipient_phone"):
        # Match exact ou par les 9 derniers chiffres
        phone = parcel["recipient_phone"]
        recipient_user = await db.users.find_one({
            "$or": [
                {"phone": phone},
                {"phone": {"$regex": f"{phone[-9:]}$"}}
            ]
        }, {"profile_picture_url": 1})
        if recipient_user:
            parcel["recipient_photo_url"] = recipient_user.get("profile_picture_url")
    elif recipient_uid:
        recipient_user = await db.users.find_one({"user_id": recipient_uid}, {"profile_picture_url": 1})
        if recipient_user:
            parcel["recipient_photo_url"] = recipient_user.get("profile_picture_url")

    # Driver
    driver_id = parcel.get("assigned_driver_id")
    if driver_id:
        driver = await db.users.find_one({"user_id": driver_id}, {"profile_picture_url": 1})
        if driver:
            parcel["driver_photo_url"] = driver.get("profile_picture_url")

    return {"parcel": parcel, "timeline": timeline}


@router.post("/{parcel_id}/confirm-location", summary="Confirmer sa position (App Destinataire)")
async def confirm_location_authenticated(
    parcel_id: str,
    payload: LocationConfirmPayload,
    current_user: dict = Depends(get_current_user),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    # Vérification : l'utilisateur est bien le destinataire
    # On compare par ID si lié, sinon par téléphone
    is_recipient = parcel.get("recipient_user_id") == current_user["user_id"]
    if not is_recipient and parcel.get("recipient_phone"):
        is_recipient = parcel["recipient_phone"].endswith(current_user["phone"][-9:])

    if not is_recipient:
        raise forbidden_exception("Seul le destinataire peut confirmer la position de livraison")

    location = {
        "label":    None,
        "district": None,
        "city":     "Dakar",
        "notes":    None,
        "geopin": {
            "lat":      payload.lat,
            "lng":      payload.lng,
            "accuracy": payload.accuracy,
        },
        "source":    "app_recipient",
        "confirmed": True,
    }

    updates = {
        "delivery_location":  location,
        "delivery_confirmed": True,
        "updated_at": datetime.now(timezone.utc),
    }
    if payload.voice_note:
        updates["delivery_voice_note"] = payload.voice_note

    await db.parcels.update_one({"parcel_id": parcel_id}, {"$set": updates})
    
    # Recharger pour avoir les champs à jour pour la mission
    updated_parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    
    # ── Déclenchement automatique de la mission si prêt ──
    mode = updated_parcel.get("delivery_mode", "")
    status = updated_parcel.get("status", "")
    
    if mode.endswith("_to_home"):
        if status == ParcelStatus.CREATED.value and mode == "home_to_home":
            await _create_delivery_mission(updated_parcel, ParcelStatus.CREATED)
        elif status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value and mode == "relay_to_home":
            await _create_delivery_mission(updated_parcel, ParcelStatus.DROPPED_AT_ORIGIN_RELAY)
        elif status == ParcelStatus.AT_DESTINATION_RELAY.value:
            await _create_delivery_mission(updated_parcel, ParcelStatus.AT_DESTINATION_RELAY)

    return {"ok": True, "message": "Position de livraison confirmée"}


@router.put("/{parcel_id}/delivery-address", summary="Mettre à jour l'adresse/position de livraison (destinataire)")
async def update_delivery_address(
    parcel_id: str,
    payload: LocationConfirmPayload,
    current_user: dict = Depends(get_current_user),
):
    """Permet au destinataire de mettre à jour sa position GPS et note vocale à tout moment
    (avant ou après la confirmation initiale, tant que le colis n'est pas livré)."""
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    is_recipient = parcel.get("recipient_user_id") == current_user["user_id"]
    if not is_recipient and parcel.get("recipient_phone"):
        is_recipient = parcel["recipient_phone"].endswith(current_user["phone"][-9:])
    if not is_recipient:
        raise forbidden_exception("Seul le destinataire peut mettre à jour l'adresse de livraison")

    if parcel.get("status") in ("delivered", "cancelled", "returned"):
        raise bad_request_exception("Colis déjà terminé, modification impossible")

    location = {
        "label":    None,
        "district": None,
        "city":     "Dakar",
        "notes":    None,
        "geopin": {
            "lat":      payload.lat,
            "lng":      payload.lng,
            "accuracy": payload.accuracy,
        },
        "source":    "app_recipient",
        "confirmed": True,
    }
    updates = {
        "delivery_location":  location,
        "delivery_confirmed": True,
        "updated_at": datetime.now(timezone.utc),
    }
    if payload.voice_note:
        updates["delivery_voice_note"] = payload.voice_note

    await db.parcels.update_one({"parcel_id": parcel_id}, {"$set": updates})

    # Déclencher une mission si les conditions sont réunies (premier appel)
    updated_parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    mode   = updated_parcel.get("delivery_mode", "")
    status = updated_parcel.get("status", "")
    if mode.endswith("_to_home"):
        if status == ParcelStatus.CREATED.value and mode == "home_to_home":
            await _create_delivery_mission(updated_parcel, ParcelStatus.CREATED)
        elif status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value and mode == "relay_to_home":
            await _create_delivery_mission(updated_parcel, ParcelStatus.DROPPED_AT_ORIGIN_RELAY)
        elif status == ParcelStatus.AT_DESTINATION_RELAY.value:
            await _create_delivery_mission(updated_parcel, ParcelStatus.AT_DESTINATION_RELAY)

    return {"ok": True, "message": "Adresse de livraison mise à jour"}


@router.put("/{parcel_id}/cancel", summary="Annuler un colis (si CREATED)")
async def cancel_parcel(parcel_id: str, current_user: dict = Depends(get_current_user)):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    if parcel["sender_user_id"] != current_user["user_id"]:
        raise forbidden_exception()
    updated = await transition_status(
        parcel_id, ParcelStatus.CANCELLED,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
    )
    return updated


# ── Actions agents relais ─────────────────────────────────────────────────────
@router.post("/{parcel_id}/drop-at-relay", summary="Scan entrée relais origine (agent)")
async def drop_at_relay(
    parcel_id: str,
    body: Optional[dict] = None,
    current_user: dict = Depends(require_role(
        UserRole.RELAY_AGENT, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    updated = await transition_status(
        parcel_id, ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
        notes="Scan relais entrée",
    )
    return updated


@router.post("/{parcel_id}/arrive-relay", summary="Réceptionner un colis au relais (normal ou redirigé)")
async def arrive_relay(
    parcel_id: str,
    body: Optional[dict] = None,
    current_user: dict = Depends(require_role(
        UserRole.RELAY_AGENT, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    current_status = parcel["status"]
    actor = {"actor_id": current_user["user_id"], "actor_role": current_user["role"]}

    if current_status == ParcelStatus.REDIRECTED_TO_RELAY.value:
        # Colis redirigé après échec → disponible directement
        return await transition_status(
            parcel_id, ParcelStatus.AVAILABLE_AT_RELAY,
            notes="Réception colis redirigé après échec de livraison", **actor,
        )

    elif current_status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value:
        delivery_mode = parcel.get("delivery_mode", "")
        if delivery_mode == "relay_to_home":
            # R2H : le driver vient chercher au relais origine → seulement IN_TRANSIT
            return await transition_status(parcel_id, ParcelStatus.IN_TRANSIT, notes="Transit confirmé (R2H)", **actor)
        else:
            # R2R / autres : DROPPED → IN_TRANSIT → AT_DESTINATION_RELAY → AVAILABLE_AT_RELAY
            await transition_status(parcel_id, ParcelStatus.IN_TRANSIT, notes="Transit confirmé", **actor)
            await transition_status(parcel_id, ParcelStatus.AT_DESTINATION_RELAY, **actor)
            return await transition_status(parcel_id, ParcelStatus.AVAILABLE_AT_RELAY, **actor)

    elif current_status == ParcelStatus.IN_TRANSIT.value:
        # Arrivée au relais destination depuis le transit
        await transition_status(parcel_id, ParcelStatus.AT_DESTINATION_RELAY, **actor)
        return await transition_status(parcel_id, ParcelStatus.AVAILABLE_AT_RELAY, **actor)

    elif current_status == ParcelStatus.AT_DESTINATION_RELAY.value:
        # Déjà au relais, juste marquer disponible
        return await transition_status(parcel_id, ParcelStatus.AVAILABLE_AT_RELAY, **actor)

    elif current_status == ParcelStatus.OUT_FOR_DELIVERY.value:
        # H2R : le livreur livre le colis directement au relais destinataire
        await transition_status(parcel_id, ParcelStatus.AT_DESTINATION_RELAY, notes="Livreur dépose au relais destinataire (H2R)", **actor)
        return await transition_status(parcel_id, ParcelStatus.AVAILABLE_AT_RELAY, **actor)

    else:
        raise bad_request_exception(
            f"Impossible de réceptionner un colis en statut '{current_status}'"
        )


@router.post("/bulk-action", summary="Actions en masse pour les relais (Batch Scanning)")
async def bulk_relay_action(
    codes: list[str],
    current_user: dict = Depends(require_role(
        UserRole.RELAY_AGENT, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    """
    Traite une liste de codes de suivi pour un relais (entrée ou réception).
    """
    results = []
    actor = {"actor_id": current_user["user_id"], "actor_role": current_user["role"]}
    
    for code in codes:
        try:
            parcel = await db.parcels.find_one({"tracking_code": code.strip().upper()})
            if not parcel:
                results.append({"code": code, "success": False, "error": "Introuvable"})
                continue
            
            parcel_id = parcel["parcel_id"]
            status = parcel["status"]
            
            # Logique simplifiée identique à arrive_relay / drop_at_relay
            arrive_statuses = {
                ParcelStatus.REDIRECTED_TO_RELAY.value,
                ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value,
                ParcelStatus.IN_TRANSIT.value,
                ParcelStatus.AT_DESTINATION_RELAY.value,
                ParcelStatus.OUT_FOR_DELIVERY.value,  # H2R : driver livre au relais
            }
            
            if status in arrive_statuses:
                # Réutiliser la même logique que arrive_relay (transitions chaînées selon statut)
                if status == ParcelStatus.REDIRECTED_TO_RELAY.value:
                    await transition_status(parcel_id, ParcelStatus.AVAILABLE_AT_RELAY, notes="Batch scan: Colis redirigé", **actor)
                elif status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value:
                    delivery_mode = parcel.get("delivery_mode", "")
                    if delivery_mode == "relay_to_home":
                        await transition_status(parcel_id, ParcelStatus.IN_TRANSIT, notes="Batch scan: Transit R2H", **actor)
                    else:
                        await transition_status(parcel_id, ParcelStatus.IN_TRANSIT, notes="Batch scan: Transit", **actor)
                        await transition_status(parcel_id, ParcelStatus.AT_DESTINATION_RELAY, **actor)
                        await transition_status(parcel_id, ParcelStatus.AVAILABLE_AT_RELAY, **actor)
                elif status in {ParcelStatus.IN_TRANSIT.value, ParcelStatus.AT_DESTINATION_RELAY.value}:
                    if status == ParcelStatus.IN_TRANSIT.value:
                        await transition_status(parcel_id, ParcelStatus.AT_DESTINATION_RELAY, **actor)
                    await transition_status(parcel_id, ParcelStatus.AVAILABLE_AT_RELAY, notes="Batch scan: Arrivée", **actor)
                elif status == ParcelStatus.OUT_FOR_DELIVERY.value:
                    await transition_status(parcel_id, ParcelStatus.AT_DESTINATION_RELAY, notes="Batch scan: H2R depot relais", **actor)
                    await transition_status(parcel_id, ParcelStatus.AVAILABLE_AT_RELAY, **actor)
            else:
                await transition_status(parcel_id, ParcelStatus.DROPPED_AT_ORIGIN_RELAY, notes="Batch scan: Dépôt", **actor)
                
            results.append({"code": code, "success": True})
        except Exception as e:
            results.append({"code": code, "success": False, "error": str(e)})
            
    return {"results": results}


@router.post("/{parcel_id}/handout", summary="Remise destinataire (scan + PIN)")
async def handout_parcel(
    parcel_id: str,
    proof: ProofOfDelivery,
    current_user: dict = Depends(require_role(
        UserRole.RELAY_AGENT, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    if proof.proof_type == "pin":
        if not proof.pin_code:
            raise bad_request_exception("PIN obligatoire pour remise au relais")
        parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"relay_pin": 1, "delivery_code": 1})
        if not parcel:
            raise not_found_exception("Colis")
        stored_pin = parcel.get("relay_pin") or parcel.get("delivery_code", "")
        if stored_pin and proof.pin_code.strip() != stored_pin.strip():
            raise bad_request_exception("PIN incorrect")
    updated = await transition_status(
        parcel_id, ParcelStatus.DELIVERED,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
        notes=f"Remise relais — {proof.proof_type}",
        metadata={"pin_code": proof.pin_code},
    )
    return updated


# ── Actions livreurs ──────────────────────────────────────────────────────────
@router.post("/{parcel_id}/pickup", summary="Prise en charge par driver")
async def pickup_parcel(
    parcel_id: str,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id})
    if not parcel:
        raise not_found_exception("Colis")
    
    if parcel.get("status") == ParcelStatus.SUSPENDED.value:
        raise forbidden_exception("Ce colis est suspendu par l'administration. Action impossible.")

    now = datetime.now(timezone.utc)
    await db.parcels.update_one(
        {"parcel_id": parcel_id},
        {"$set": {"assigned_driver_id": current_user["user_id"], "updated_at": now}},
    )
    return await transition_status(
        parcel_id, ParcelStatus.OUT_FOR_DELIVERY,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
    )


@router.post("/{parcel_id}/deliver", summary="Marquer livré — code 6 chiffres obligatoire")
async def deliver_parcel(
    parcel_id: str,
    body: CodeDelivery,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    # ── Validation du paiement (Informationnelle) ──────────────────────
    if parcel.get("payment_status") != "paid":
        logger.warning(f"Livraison effectuée pour {parcel_id} sans confirmation de paiement (status: {parcel.get('payment_status')})")
        # On ne bloque plus : raise bad_request_exception(...) enlevé

    # ── Validation du code ─────────────────────────────────────────────
    if parcel.get("status") == ParcelStatus.SUSPENDED.value:
        raise forbidden_exception("Ce colis est suspendu par l'administration. Livraison impossible.")

    if parcel.get("delivery_code", "") != body.delivery_code.strip():
        raise bad_request_exception("Code de livraison invalide. Vérifiez le code à 4 chiffres.")

    # ── Géofence : livreur doit être à moins de 10km (MVP) ─────────────
    if parcel.get("is_simulation"):
        logger.info(f"Bypass geofence pour colis de simulation {parcel_id}")
    elif body.driver_lat is not None and body.driver_lng is not None:
        # Priorité : delivery_location (confirmé GPS) puis delivery_address.geopin (saisi texte)
        delivery_loc = parcel.get("delivery_location") or {}
        geo = delivery_loc.get("geopin") or delivery_loc or (parcel.get("delivery_address") or {}).get("geopin") or {}
        dest_lat = geo.get("lat")
        dest_lng = geo.get("lng")
        if dest_lat is not None and dest_lng is not None:
            dist_m = _haversine_km(body.driver_lat, body.driver_lng, dest_lat, dest_lng) * 1000
            if dist_m > 10000: # 10 km
                raise bad_request_exception(
                    f"Vous êtes trop loin de l'adresse de livraison ({int(dist_m/1000)} km). Rapprochez-vous (< 10 km)."
                )

    updated = await transition_status(
        parcel_id, ParcelStatus.DELIVERED,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
        notes=f"Livré — code validé",
        metadata={
            "delivery_code_used": True,
            "proof_type": body.proof_type,
            "proof_data": body.proof_data, # stocké en DB (optimisé webp via mobile)
        },
    )
    return updated


@router.post("/{parcel_id}/fail-delivery", summary="Échec livraison + raison")
async def fail_delivery(
    parcel_id: str,
    body: FailDeliveryRequest,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    return await transition_status(
        parcel_id, ParcelStatus.DELIVERY_FAILED,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
        notes=body.notes,
        metadata={"failure_reason": body.failure_reason},
    )


@router.post("/{parcel_id}/redirect-relay", summary="Rediriger vers relais après échec")
async def redirect_to_relay(
    parcel_id: str,
    body: RedirectRelayRequest,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    now = datetime.now(timezone.utc)
    await db.parcels.update_one(
        {"parcel_id": parcel_id},
        {"$set": {"redirect_relay_id": body.redirect_relay_id, "updated_at": now}},
    )
    return await transition_status(
        parcel_id, ParcelStatus.REDIRECTED_TO_RELAY,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
        notes=body.notes,
        metadata={"redirect_relay_id": body.redirect_relay_id},
    )

@router.get("/{parcel_id}/codes", summary="Codes de validation du colis")
async def get_parcel_codes(
    parcel_id: str,
    current_user: dict = Depends(get_current_user),
):
    """
    Retourne les codes de collecte et de livraison.
    - Expéditeur/Relais : voit pickup_code (pour donner au livreur)
    - Admin : voit les deux
    """
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    role    = current_user["role"]
    user_id = current_user["user_id"]
    is_admin = role in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]

    # L'expéditeur ou le relais origine voient le pickup_code
    can_see_pickup = (
        is_admin
        or parcel.get("sender_user_id") == user_id
        or (role == UserRole.RELAY_AGENT.value
            and current_user.get("relay_point_id") == parcel.get("origin_relay_id"))
    )

    mode = parcel.get("delivery_mode", "")
    show_delivery = mode.endswith("_to_home")
    show_relay    = mode.endswith("_to_relay")

    return {
        "pickup_code":   parcel.get("pickup_code")   if can_see_pickup else None,
        "delivery_code": parcel.get("delivery_code") if (is_admin or show_delivery) else None,
        "relay_pin":     parcel.get("relay_pin")     if (is_admin or show_relay)    else None,
    }

@router.post("/{parcel_id}/rate", summary="Noter le livreur + Pourboire")
async def rate_parcel(
    parcel_id: str,
    body: ParcelRatingRequest,
    current_user: dict = Depends(get_current_user),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id})
    if not parcel:
        raise not_found_exception("Colis")
    
    if parcel["status"] != ParcelStatus.DELIVERED.value:
        raise bad_request_exception("Seul un colis livré peut être noté")

    # Mise à jour des infos de notation
    await db.parcels.update_one(
        {"parcel_id": parcel_id},
        {"$set": {
            "rating": body.rating,
            "rating_comment": body.comment,
            "driver_tip": body.tip,
            "updated_at": datetime.now(timezone.utc)
        }}
    )

    # Gestion du pourboire (si > 0)
    if body.tip > 0 and parcel.get("assigned_driver_id"):
        try:
            from services.wallet_service import debit_wallet, credit_wallet
            # On débite le donateur (celui qui note)
            await debit_wallet(
                owner_id=current_user["user_id"],
                amount=body.tip,
                description=f"Pourboire versé pour le colis {parcel_id}",
                parcel_id=parcel_id
            )
            # On crédite le livreur
            await credit_wallet(
                owner_id=parcel["assigned_driver_id"],
                owner_type="driver",
                amount=body.tip,
                description=f"Pourboire reçu pour le colis {parcel_id}",
                parcel_id=parcel_id
            )
        except ValueError as e:
            # Si solde insuffisant, on n'arrête pas la notation mais on prévient
            return {"message": "Notation enregistrée, mais solde insuffisant pour le pourboire", "rating": body.rating}

    # ── Gamification (Phase 8) ──
    if parcel.get("assigned_driver_id"):
        from services.gamification_service import update_driver_gamification
        await update_driver_gamification(
            parcel["assigned_driver_id"], 
            "rating_received", 
            rating=body.rating
        )

    return {"message": "Merci pour votre avis !", "rating": body.rating}

