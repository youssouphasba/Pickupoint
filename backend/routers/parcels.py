"""
Router parcels : CRUD colis + toutes les actions de transition de la machine d'états.
"""
import logging
import mimetypes
import random
import re
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
logger = logging.getLogger(__name__)
from typing import Optional

from fastapi import APIRouter, Depends, File, Query, Request, UploadFile
from fastapi.responses import FileResponse

from pydantic import BaseModel, Field
from core.dependencies import get_current_user, get_current_user_optional, require_role
from core.exceptions import not_found_exception, forbidden_exception, bad_request_exception
from core.limiter import limiter
from core.utils import (
    check_code_lockout,
    clear_code_attempts,
    mask_phone,
    normalize_phone,
    phone_suffix,
    phones_match,
    record_failed_attempt,
)
from database import db
from models.common import UserRole, ParcelStatus
from models.parcel import (
    ParcelCreate,
    Parcel,
    ParcelQuote,
    QuoteResponse,
    FailDeliveryRequest,
    RedirectRelayRequest,
    ParcelRatingRequest,
    LocationConfirmPayload,
    AddressChangePreviewRequest,
    AddressChangeApplyRequest,
)
from models.delivery import ProofOfDelivery, CodeDelivery
from services.parcel_service import (
    create_parcel,
    transition_status,
    get_parcel_timeline,
    _create_delivery_mission,
    _record_event,
    preview_address_change,
    refresh_quote_if_ready,
    sync_active_mission_with_parcel,
)
from services.pricing_service import calculate_price, _haversine_km
from services.notification_service import notify_quote_finalized, notify_relay_agent_parcel_arrived, notify_new_parcel_message
from services.wallet_service import credit_wallet, debit_wallet
from config import UPLOADS_DIR, settings

router = APIRouter()
PRIVATE_VOICE_DIR = UPLOADS_DIR.parent / "private_uploads" / "voice"


def _is_admin(user: dict) -> bool:
    return user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]


def _relay_matches_parcel(parcel: dict, current_user: dict) -> bool:
    relay_id = current_user.get("relay_point_id")
    if not relay_id:
        return False
    return relay_id in {
        parcel.get("origin_relay_id"),
        parcel.get("destination_relay_id"),
        parcel.get("redirect_relay_id"),
        parcel.get("transit_relay_id"),
    }


def _build_confirmed_location_payload(payload: LocationConfirmPayload | AddressChangePreviewRequest | AddressChangeApplyRequest, *, source: str) -> dict:
    return {
        "label": None,
        "district": None,
        "city": "Dakar",
        "notes": None,
        "geopin": {
            "lat": payload.lat,
            "lng": payload.lng,
            "accuracy": payload.accuracy,
        },
        "source": source,
        "confirmed": True,
    }


def _ensure_relay_action_allowed(parcel: dict, current_user: dict, *allowed_relay_ids: Optional[str]) -> None:
    if _is_admin(current_user):
        return

    relay_id = current_user.get("relay_point_id")
    if not relay_id:
        raise forbidden_exception("Aucun relais n'est associé à cet agent")

    normalized = {relay for relay in allowed_relay_ids if relay}
    if relay_id not in normalized:
        raise forbidden_exception("Cette action n'est autorisée que depuis le relais concerné")


def _ensure_driver_action_allowed(parcel: dict, current_user: dict) -> None:
    if _is_admin(current_user):
        return

    assigned_driver_id = parcel.get("assigned_driver_id")
    if not assigned_driver_id or assigned_driver_id != current_user["user_id"]:
        raise forbidden_exception("Cette action est réservée au livreur assigné")


async def _active_mission_for_parcel(parcel_id: str) -> Optional[dict]:
    return await db.delivery_missions.find_one(
        {"parcel_id": parcel_id, "status": {"$in": ["pending", "assigned", "in_progress"]}},
        {"_id": 0},
    )


def _delivery_is_blocked_by_payment(parcel: dict) -> bool:
    # Le paiement reste suivi, mais ne bloque plus le cycle de vie du colis.
    return False


def _home_mission_ready(parcel: dict) -> bool:
    mode = parcel.get("delivery_mode", "")
    if not mode.endswith("_to_home"):
        return False
    if mode.startswith("home_to_") and not parcel.get("pickup_confirmed"):
        return False
    return bool(parcel.get("delivery_confirmed"))


async def _refresh_quote_sync_and_create_home_mission(
    parcel: dict,
    *,
    earn_amount: Optional[float] = None,
) -> dict:
    mode = parcel.get("delivery_mode", "")
    refreshed = parcel
    quote_became_available = False
    if mode.startswith("home_to_") or mode.endswith("_to_home"):
        refreshed, quote_became_available = await refresh_quote_if_ready(parcel)

    await sync_active_mission_with_parcel(refreshed, earn_amount=earn_amount)

    if quote_became_available:
        payer_user_id = (
            refreshed.get("sender_user_id")
            if refreshed.get("who_pays") == "sender"
            else refreshed.get("recipient_user_id")
        )
        quoted_price = refreshed.get("quoted_price")
        estimated_hours = (refreshed.get("quote_breakdown") or {}).get("estimated_hours")
        if payer_user_id and quoted_price is not None and estimated_hours:
            await notify_quote_finalized(
                user_id=payer_user_id,
                parcel_id=refreshed["parcel_id"],
                tracking_code=refreshed.get("tracking_code", ""),
                amount=float(quoted_price),
                estimated_hours=str(estimated_hours),
            )

    status = refreshed.get("status", "")
    if _home_mission_ready(refreshed):
        if status == ParcelStatus.CREATED.value:
            await _create_delivery_mission(refreshed, ParcelStatus.CREATED)
        elif status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value:
            await _create_delivery_mission(refreshed, ParcelStatus.DROPPED_AT_ORIGIN_RELAY)
        elif status == ParcelStatus.AT_DESTINATION_RELAY.value:
            await _create_delivery_mission(refreshed, ParcelStatus.AT_DESTINATION_RELAY)

    return await db.parcels.find_one({"parcel_id": refreshed["parcel_id"]}, {"_id": 0}) or refreshed


async def _find_nearest_active_relay(lat: float, lng: float) -> Optional[dict]:
    relays = await db.relay_points.find(
        {
            "is_active": True,
            "address.geopin.lat": {"$ne": None},
            "address.geopin.lng": {"$ne": None},
        },
        {"_id": 0},
    ).to_list(length=500)
    ranked: list[tuple[float, dict]] = []
    for relay in relays:
        geopin = (relay.get("address") or {}).get("geopin") or {}
        relay_lat = geopin.get("lat")
        relay_lng = geopin.get("lng")
        if relay_lat is None or relay_lng is None:
            continue
        if relay.get("current_load", 0) >= relay.get("max_capacity", 50):
            continue
        ranked.append((_haversine_km(lat, lng, relay_lat, relay_lng), relay))
    if not ranked:
        return None
    ranked.sort(key=lambda item: item[0])
    return ranked[0][1]


@router.post("/quote", response_model=QuoteResponse, summary="Calculer un devis (sans créer)")
async def quote_parcel(
    body: ParcelQuote,
    current_user: Optional[dict] = Depends(get_current_user_optional),
):
    sender_tier = "bronze"
    is_frequent = False
    is_first = False

    if current_user:
        user_id = current_user["user_id"]
        user = await db.users.find_one({"user_id": user_id})
        if user:
            sender_tier = user.get("loyalty_tier", "bronze")

            month_ago = datetime.now(timezone.utc) - timedelta(days=30)
            delivered_count = await db.parcels.count_documents({
                "sender_user_id": user_id,
                "status": "delivered",
                "created_at": {"$gte": month_ago},
            })
            is_frequent = delivered_count >= 10

            total_delivered = await db.parcels.count_documents({
                "sender_user_id": user_id,
                "status": "delivered",
            })
            is_first = total_delivered == 0

    return await calculate_price(
        body,
        sender_tier=sender_tier,
        is_frequent=is_frequent,
        user_id=current_user["user_id"] if current_user else None,
        is_first_delivery=is_first,
    )


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
            "$or": [
                {"origin_relay_id": relay_id},
                {"destination_relay_id": relay_id},
                {"redirect_relay_id": relay_id},
                {"transit_relay_id": relay_id},
            ]
        } if relay_id else {"sender_user_id": current_user["user_id"]}
    else:
        # Client : voit ses colis ENVOYÉS et les colis qu'il reçoit (recipient_phone)
        phone_candidates = [
            candidate
            for candidate in {current_user.get("phone"), normalize_phone(current_user.get("phone"))}
            if candidate
        ]
        query = {
            "$or": [
                {"sender_user_id": current_user["user_id"]},
                {"recipient_user_id": current_user["user_id"]},
                {"recipient_phone": {"$in": phone_candidates}},
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
                or phones_match(p.get("recipient_phone"), uphone)
            )

    for p in parcels:
        if role == UserRole.DRIVER.value and p.get("recipient_phone"):
            p["recipient_phone"] = mask_phone(p["recipient_phone"])
        _mask_payment_fields(p, current_user)

    return {"parcels": parcels, "total": total}


def _mask_payment_fields(parcel: dict, current_user: dict) -> None:
    """Ne laisse payment_url/payment_ref visibles qu'au payeur (sender ou recipient selon who_pays) ou admin."""
    if _is_admin(current_user):
        return
    who_pays = parcel.get("who_pays") or "sender"
    payer_user_id = (
        parcel.get("recipient_user_id") if who_pays == "recipient" else parcel.get("sender_user_id")
    )
    if payer_user_id and payer_user_id == current_user.get("user_id"):
        return
    # Fallback: si payer_user_id inconnu, autoriser si téléphones matchent
    if not payer_user_id:
        payer_phone = parcel.get("recipient_phone") if who_pays == "recipient" else parcel.get("sender_phone")
        if payer_phone and phones_match(payer_phone, current_user.get("phone")):
            return
    parcel.pop("payment_url", None)
    parcel.pop("payment_ref", None)


def _can_access_parcel(parcel: dict, current_user: dict) -> tuple[bool, bool, bool, bool]:
    is_admin = _is_admin(current_user)
    is_sender = parcel.get("sender_user_id") == current_user["user_id"]
    is_recipient = (
        parcel.get("recipient_user_id") == current_user["user_id"]
        or phones_match(parcel.get("recipient_phone"), current_user.get("phone"))
    )
    is_driver = (
        current_user["role"] == UserRole.DRIVER.value
        and parcel.get("assigned_driver_id") == current_user["user_id"]
    )
    is_relay = current_user["role"] == UserRole.RELAY_AGENT.value and _relay_matches_parcel(parcel, current_user)
    return is_admin or is_sender or is_recipient or is_driver or is_relay, is_sender, is_recipient, is_driver


@router.get("/lookup/tracking/{tracking_code}", summary="Lookup authentifie d'un colis par tracking code")
async def lookup_parcel_by_tracking(tracking_code: str, current_user: dict = Depends(get_current_user)):
    parcel = await db.parcels.find_one({"tracking_code": tracking_code}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    allowed, is_sender, is_recipient, _ = _can_access_parcel(parcel, current_user)
    if not allowed:
        raise forbidden_exception("Acces refuse a ce colis")

    payload = {
        "parcel_id": parcel.get("parcel_id"),
        "tracking_code": parcel.get("tracking_code"),
        "status": parcel.get("status"),
        "delivery_mode": parcel.get("delivery_mode"),
        "origin_relay_id": parcel.get("origin_relay_id"),
        "destination_relay_id": parcel.get("destination_relay_id"),
        "redirect_relay_id": parcel.get("redirect_relay_id"),
        "recipient_name": parcel.get("recipient_name"),
        "recipient_phone": parcel.get("recipient_phone"),
        "created_at": parcel.get("created_at"),
    }

    if current_user["role"] == UserRole.DRIVER.value and payload.get("recipient_phone"):
        payload["recipient_phone"] = mask_phone(parcel.get("recipient_phone") or "")

    return payload

@router.get("/{parcel_id}/driver-location", summary="Position GPS du livreur actif pour ce colis")
async def get_driver_location(parcel_id: str, current_user: dict = Depends(get_current_user)):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    allowed, _, _, _ = _can_access_parcel(parcel, current_user)
    if not allowed:
        raise forbidden_exception("Accès refusé à ce suivi live")

    mission = await db.delivery_missions.find_one(
        {
            "parcel_id": parcel_id,
            "status": {"$in": ["assigned", "in_progress", "incident_reported"]},
        },
        {
            "_id": 0,
            "driver_location": 1,
            "eta_text": 1,
            "distance_text": 1,
            "eta_seconds": 1,
            "encoded_polyline": 1,
            "delivery_geopin": 1,
            "delivery_label": 1,
            "location_updated_at": 1,
        },
    )
    if not mission or not mission.get("driver_location"):
        return {"available": False, "location": None}

    return {
        "available": True,
        "location": mission.get("driver_location"),
        "eta_text": mission.get("eta_text"),
        "distance_text": mission.get("distance_text"),
        "eta_seconds": mission.get("eta_seconds"),
        "encoded_polyline": mission.get("encoded_polyline"),
        "destination": {
            "geopin": mission.get("delivery_geopin"),
            "label": mission.get("delivery_label"),
        },
        "location_updated_at": mission.get("location_updated_at"),
    }


@router.get("/{parcel_id}", summary="Détail + timeline")
async def get_parcel(parcel_id: str, current_user: dict = Depends(get_current_user)):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    # Déterminer le rôle du viewer AVANT le masquage
    allowed, is_sender, is_recipient, is_driver = _can_access_parcel(parcel, current_user)
    is_admin = _is_admin(current_user)
    if not allowed:
        raise forbidden_exception("Accès refusé à ce colis")

    # Injecter le flag dans la réponse (Flutter l'utilise pour l'UX)
    parcel["is_recipient"] = bool(is_recipient)

    active_mission = await db.delivery_missions.find_one(
        {
            "parcel_id": parcel_id,
            "status": {"$in": ["assigned", "in_progress", "incident_reported"]},
        },
        {
            "_id": 0,
            "driver_id": 1,
            "driver_location": 1,
            "eta_text": 1,
            "distance_text": 1,
            "eta_seconds": 1,
            "encoded_polyline": 1,
            "payment_status": 1,
            "payment_method": 1,
            "who_pays": 1,
            "pickup_voice_note": 1,
            "delivery_voice_note": 1,
        },
    )
    if active_mission:
        parcel["driver_location"] = active_mission.get("driver_location")
        parcel["eta_text"] = active_mission.get("eta_text")
        parcel["distance_text"] = active_mission.get("distance_text")
        parcel["eta_seconds"] = active_mission.get("eta_seconds")
        parcel["encoded_polyline"] = active_mission.get("encoded_polyline")
        parcel["payment_method"] = active_mission.get("payment_method") or parcel.get("payment_method")
        parcel["who_pays"] = active_mission.get("who_pays") or parcel.get("who_pays")
        parcel["pickup_voice_note"] = active_mission.get("pickup_voice_note") or parcel.get("pickup_voice_note")
        parcel["delivery_voice_note"] = active_mission.get("delivery_voice_note") or parcel.get("delivery_voice_note")

    driver_id = parcel.get("assigned_driver_id")
    if not driver_id and active_mission:
        driver_id = active_mission.get("driver_id")
    if driver_id:
        driver = await db.users.find_one(
            {"user_id": driver_id},
            {"_id": 0, "name": 1, "phone": 1, "profile_picture_url": 1},
        )
        if driver:
            parcel["driver_name"] = driver.get("name")
            parcel["driver_phone"] = driver.get("phone")
            parcel["driver_photo_url"] = parcel.get("driver_photo_url") or driver.get("profile_picture_url")

    parcel["delivery_blocked_by_payment"] = False

    # Numéro du livreur masqué après livraison (sauf admin)
    if not is_admin and parcel.get("status") == "delivered":
        parcel.pop("driver_phone", None)

    if not is_admin:
        # Sécurité des codes :
        # L'expéditeur ne doit pas voir le delivery_code/relay_pin (PIN du destinataire)
        # Le destinataire ne doit pas voir le pickup_code (PIN de collecte)
        if is_sender and not is_recipient:
            parcel.pop("delivery_code", None)
            parcel.pop("relay_pin", None)
        if is_recipient and not is_sender:
            parcel.pop("pickup_code", None)
        if not is_sender:
            parcel.pop("return_code", None)

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
        suffix = phone_suffix(phone)
        phone_query = {"phone": phone}
        if suffix:
            phone_query = {
                "$or": [
                    {"phone": phone},
                    {"phone": {"$regex": f"{re.escape(suffix)}$"}},
                ]
            }
        recipient_user = await db.users.find_one(phone_query, {"profile_picture_url": 1})
        if recipient_user:
            parcel["recipient_photo_url"] = recipient_user.get("profile_picture_url")
    elif recipient_uid:
        recipient_user = await db.users.find_one({"user_id": recipient_uid}, {"profile_picture_url": 1})
        if recipient_user:
            parcel["recipient_photo_url"] = recipient_user.get("profile_picture_url")

    # Driver
    driver_id = parcel.get("assigned_driver_id")
    if driver_id:
        driver = await db.users.find_one({"user_id": driver_id}, {"name": 1, "profile_picture_url": 1})
        if driver:
            parcel["driver_name"] = parcel.get("driver_name") or driver.get("name")
            parcel["driver_photo_url"] = driver.get("profile_picture_url")

    if (
        not is_admin
        and is_driver
        and not is_sender
        and not is_recipient
        and parcel.get("recipient_phone")
    ):
        parcel["recipient_phone"] = mask_phone(parcel["recipient_phone"])

    _mask_payment_fields(parcel, current_user)

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
        is_recipient = phones_match(parcel.get("recipient_phone"), current_user.get("phone"))

    if not is_recipient:
        raise forbidden_exception("Seul le destinataire peut confirmer la position de livraison")

    location = _build_confirmed_location_payload(payload, source="app_recipient")

    updates = {
        "delivery_location":  location,
        "delivery_address":   location,
        "delivery_confirmed": True,
        "gps_reminders.recipient.confirmed_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc),
    }
    if payload.voice_note:
        updates["delivery_voice_note"] = payload.voice_note

    await db.parcels.update_one({"parcel_id": parcel_id}, {"$set": updates})

    # Recharger pour avoir les champs à jour pour la mission
    updated_parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    updated_parcel = await _refresh_quote_sync_and_create_home_mission(updated_parcel)
    await _record_event(
        parcel_id=parcel_id,
        event_type="RECIPIENT_LOCATION_CONFIRMED",
        actor_id=current_user["user_id"],
        actor_role=current_user["role"],
        notes="Position de livraison confirmée via application",
    )

    return {"ok": True, "message": "Position de livraison confirmée"}


@router.post("/{parcel_id}/delivery-address/preview", summary="Prévisualiser un changement d'adresse de livraison")
async def preview_delivery_address_change(
    parcel_id: str,
    payload: AddressChangePreviewRequest,
    current_user: dict = Depends(get_current_user),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    _, _, is_recipient, _ = _can_access_parcel(parcel, current_user)
    if not is_recipient and not _is_admin(current_user):
        raise forbidden_exception("Seul le destinataire peut demander un changement d'adresse")

    if parcel.get("status") in ("delivered", "cancelled", "returned", "expired"):
        raise bad_request_exception("Colis déjà terminé, modification impossible")

    preview = await preview_address_change(parcel, payload.lat, payload.lng, payload.accuracy)
    return {"ok": True, **preview}


@router.put("/{parcel_id}/delivery-address/apply", summary="Appliquer un changement d'adresse de livraison")
async def apply_delivery_address_change(
    parcel_id: str,
    payload: AddressChangeApplyRequest,
    current_user: dict = Depends(get_current_user),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    _, _, is_recipient, _ = _can_access_parcel(parcel, current_user)
    if not is_recipient and not _is_admin(current_user):
        raise forbidden_exception("Seul le destinataire peut appliquer un changement d'adresse")

    if parcel.get("status") in ("delivered", "cancelled", "returned", "expired"):
        raise bad_request_exception("Colis déjà terminé, modification impossible")

    preview = await preview_address_change(parcel, payload.lat, payload.lng, payload.accuracy)
    if preview["requires_acceptance"] and not payload.accept_surcharge:
        raise bad_request_exception("Ce changement nécessite l'acceptation du surcoût avant application")

    location = _build_confirmed_location_payload(payload, source="app_recipient")
    now = datetime.now(timezone.utc)
    updates = {
        "delivery_location": location,
        "delivery_address": location,
        "delivery_confirmed": True,
        "gps_reminders.recipient.confirmed_at": now,
        "updated_at": now,
    }
    if payload.voice_note:
        updates["delivery_voice_note"] = payload.voice_note

    active_mission = await _active_mission_for_parcel(parcel_id)
    new_bonus_total = float(parcel.get("driver_bonus_xof", 0.0))
    if preview["requires_acceptance"]:
        new_bonus_total += float(preview.get("surcharge_xof", 0.0))
        updates["address_change_surcharge_xof"] = float(parcel.get("address_change_surcharge_xof", 0.0)) + float(
            preview.get("surcharge_xof", 0.0)
        )
        updates["driver_bonus_xof"] = new_bonus_total

    await db.parcels.update_one({"parcel_id": parcel_id}, {"$set": updates})

    updated_parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    earn_amount = None
    if active_mission and preview["requires_acceptance"]:
        earn_amount = float(active_mission.get("earn_amount", 0.0)) + float(preview.get("surcharge_xof", 0.0))
    updated_parcel = await _refresh_quote_sync_and_create_home_mission(
        updated_parcel,
        earn_amount=earn_amount,
    )
    await _record_event(
        parcel_id=parcel_id,
        event_type="DELIVERY_ADDRESS_UPDATED",
        actor_id=current_user["user_id"],
        actor_role=current_user["role"],
        notes="Adresse de livraison mise à jour",
        metadata={
            "distance_delta_km": preview.get("distance_delta_km", 0.0),
            "surcharge_xof": preview.get("surcharge_xof", 0.0),
            "surcharge_accepted": bool(preview["requires_acceptance"]),
        },
    )

    return {
        "ok": True,
        "message": "Adresse de livraison mise à jour",
        **preview,
        "delivery_blocked_by_payment": _delivery_is_blocked_by_payment(updated_parcel),
    }


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
        is_recipient = phones_match(parcel.get("recipient_phone"), current_user.get("phone"))
    if not is_recipient:
        raise forbidden_exception("Seul le destinataire peut mettre à jour l'adresse de livraison")

    if parcel.get("status") in ("delivered", "cancelled", "returned"):
        raise bad_request_exception("Colis déjà terminé, modification impossible")

    preview = await preview_address_change(parcel, payload.lat, payload.lng, payload.accuracy)
    if preview["requires_acceptance"]:
        return {
            "ok": False,
            "requires_acceptance": True,
            "message": "Cette modification augmente le trajet restant. Prévisualisez puis acceptez le surcoût.",
            **preview,
        }

    location = _build_confirmed_location_payload(payload, source="app_recipient")
    updates = {
        "delivery_location":  location,
        "delivery_address":   location,
        "delivery_confirmed": True,
        "gps_reminders.recipient.confirmed_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc),
    }
    if payload.voice_note:
        updates["delivery_voice_note"] = payload.voice_note

    await db.parcels.update_one({"parcel_id": parcel_id}, {"$set": updates})

    # Déclencher une mission si les conditions sont réunies (premier appel)
    updated_parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    updated_parcel = await _refresh_quote_sync_and_create_home_mission(updated_parcel)
    await _record_event(
        parcel_id=parcel_id,
        event_type="DELIVERY_ADDRESS_UPDATED",
        actor_id=current_user["user_id"],
        actor_role=current_user["role"],
        notes="Adresse de livraison mise à jour par le destinataire",
        metadata={"distance_delta_km": preview.get("distance_delta_km", 0.0)},
    )
    return {"ok": True, "message": "Adresse de livraison mise à jour"}


class ChangeDeliveryModeRequest(BaseModel):
    new_mode: str  # 'relay' ou 'home'
    relay_id: Optional[str] = None  # requis si new_mode == 'relay'
    lat: Optional[float] = None  # requis si new_mode == 'home'
    lng: Optional[float] = None


@router.put("/{parcel_id}/change-delivery-mode", summary="Changer le mode de livraison (relais↔domicile)")
async def change_delivery_mode(
    parcel_id: str,
    body: ChangeDeliveryModeRequest,
    current_user: dict = Depends(get_current_user),
):
    """Permet au destinataire de basculer entre livraison à domicile et retrait relais.
    Autorisé uniquement avant IN_TRANSIT."""
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    # Vérifier que c'est le destinataire (ou admin)
    is_recipient = parcel.get("recipient_user_id") == current_user["user_id"]
    if not is_recipient and parcel.get("recipient_phone"):
        is_recipient = phones_match(parcel.get("recipient_phone"), current_user.get("phone"))
    if not is_recipient and not _is_admin(current_user):
        raise forbidden_exception("Seul le destinataire peut changer le mode de livraison")

    # Autorisé uniquement aux premiers statuts
    allowed_statuses = {
        ParcelStatus.CREATED.value,
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value,
    }
    if parcel["status"] not in allowed_statuses:
        raise bad_request_exception("Le mode de livraison ne peut être changé qu'avant la prise en charge par le livreur")

    current_mode = parcel.get("delivery_mode", "")
    origin_part = current_mode.split("_to_")[0] if "_to_" in current_mode else "relay"
    now = datetime.now(timezone.utc)
    updates = {"updated_at": now}

    if body.new_mode == "relay":
        if current_mode.endswith("_to_relay"):
            raise bad_request_exception("Le colis est déjà en mode relais")
        relay_id = body.relay_id
        if not relay_id:
            fallback_geopin = ((parcel.get("delivery_address") or {}).get("geopin") or {})
            lookup_lat = body.lat if body.lat is not None else fallback_geopin.get("lat")
            lookup_lng = body.lng if body.lng is not None else fallback_geopin.get("lng")
            if lookup_lat is None or lookup_lng is None:
                raise bad_request_exception("Coordonnées requises pour choisir un relais proche")
            relay = await _find_nearest_active_relay(float(lookup_lat), float(lookup_lng))
            if not relay:
                raise not_found_exception("Relais")
            relay_id = relay.get("relay_id")
        else:
            relay = await db.relay_points.find_one({"relay_id": relay_id, "is_active": True}, {"_id": 0})
        if not relay:
            raise not_found_exception("Relais")
        new_mode = f"{origin_part}_to_relay"
        updates["delivery_mode"] = new_mode
        updates["destination_relay_id"] = relay_id
        updates["redirect_relay_id"] = None
        # Supprimer delivery_code (pas nécessaire en relais), garder relay_pin
        updates["delivery_code"] = None
        updates["relay_pin"] = f"{random.randint(100000, 999999)}"
        updates["delivery_confirmed"] = False

    elif body.new_mode == "home":
        if current_mode.endswith("_to_home"):
            raise bad_request_exception("Le colis est déjà en mode domicile")
        if not body.lat or not body.lng:
            raise bad_request_exception("Coordonnées GPS requises pour la livraison à domicile")
        new_mode = f"{origin_part}_to_home"
        updates["delivery_mode"] = new_mode
        updates["destination_relay_id"] = None
        updates["redirect_relay_id"] = None
        updates["delivery_address"] = {
            "geopin": {"lat": body.lat, "lng": body.lng},
            "source": "app_recipient_mode_change",
            "confirmed": True,
        }
        updates["delivery_confirmed"] = True
        # Générer un delivery_code pour la livraison à domicile
        updates["delivery_code"] = f"{random.randint(100000, 999999)}"
        updates["relay_pin"] = None
    else:
        raise bad_request_exception("new_mode doit être 'relay' ou 'home'")

    # Recalculer le prix via ParcelQuote
    from models.common import Address, GeoPin, DeliveryMode
    origin_addr = None
    if parcel.get("origin_relay_id"):
        origin_addr = None  # calculate_price résout via relay_id
    elif parcel.get("pickup_address"):
        gp = (parcel["pickup_address"] or {}).get("geopin")
        if gp:
            origin_addr = Address(geopin=GeoPin(lat=gp["lat"], lng=gp["lng"]))

    dest_addr = None
    dest_relay = None
    if body.new_mode == "relay":
        dest_relay = updates.get("destination_relay_id")
    elif body.lat and body.lng:
        dest_addr = Address(geopin=GeoPin(lat=body.lat, lng=body.lng))

    try:
        quote = ParcelQuote(
            delivery_mode=DeliveryMode(updates["delivery_mode"]),
            origin_relay_id=parcel.get("origin_relay_id"),
            destination_relay_id=dest_relay,
            origin_location=origin_addr,
            delivery_address=dest_addr,
            weight_kg=parcel.get("weight_kg", 0.5),
            is_express=parcel.get("is_express", False),
            who_pays=parcel.get("who_pays", "sender"),
        )
        price_result = await calculate_price(quote)
        updates["quoted_price"] = price_result.price
    except Exception as e:
        logger.warning(f"Recalcul prix échoué lors du changement de mode: {e}")

    await db.parcels.update_one({"parcel_id": parcel_id}, {"$set": updates})
    await _record_event(
        parcel_id=parcel_id,
        event_type="DELIVERY_MODE_CHANGED",
        actor_id=current_user["user_id"],
        actor_role=current_user["role"],
        notes=f"Mode changé: {current_mode} → {updates['delivery_mode']}",
        metadata={"old_mode": current_mode, "new_mode": updates["delivery_mode"]},
    )
    updated = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    return {"ok": True, "message": f"Mode de livraison changé en {updates['delivery_mode']}", "parcel": updated}


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
async def _scan_departure_from_origin_relay(parcel: dict, current_user: dict, *, batch: bool = False) -> dict:
    _ensure_relay_action_allowed(parcel, current_user, parcel.get("origin_relay_id"))
    note = "Batch scan: depart relais origine" if batch else "Depart du relais origine"
    if parcel.get("delivery_mode") == "relay_to_home":
        note = "Batch scan: depart relais origine vers domicile" if batch else "Depart du relais origine vers domicile"
    return await transition_status(
        parcel["parcel_id"],
        ParcelStatus.IN_TRANSIT,
        actor_id=current_user["user_id"],
        actor_role=current_user["role"],
        notes=note,
    )


async def _scan_arrival_at_relay(parcel: dict, current_user: dict, *, batch: bool = False) -> dict:
    target_relay_id = (
        parcel.get("redirect_relay_id")
        or parcel.get("transit_relay_id")
        or parcel.get("destination_relay_id")
    )
    _ensure_relay_action_allowed(parcel, current_user, target_relay_id)

    # Vérifier capacité du relais
    if target_relay_id:
        relay = await db.relay_points.find_one({"relay_id": target_relay_id}, {"max_capacity": 1, "current_load": 1})
        if relay and relay.get("current_load", 0) >= relay.get("max_capacity", 50):
            raise bad_request_exception("Ce relais est plein (capacité maximale atteinte)")

    current_status = parcel["status"]
    actor = {"actor_id": current_user["user_id"], "actor_role": current_user["role"]}
    prefix = "Batch scan: " if batch else ""

    result = None
    if current_status == ParcelStatus.REDIRECTED_TO_RELAY.value:
        result = await transition_status(
            parcel["parcel_id"], ParcelStatus.AVAILABLE_AT_RELAY,
            notes=f"{prefix}colis redirige disponible au retrait", **actor,
        )
    elif current_status == ParcelStatus.IN_TRANSIT.value:
        result = await transition_status(
            parcel["parcel_id"], ParcelStatus.AVAILABLE_AT_RELAY,
            notes=f"{prefix}arrivee au relais de destination — pret au retrait", **actor,
        )
    elif current_status == ParcelStatus.AT_DESTINATION_RELAY.value:
        result = await transition_status(
            parcel["parcel_id"], ParcelStatus.AVAILABLE_AT_RELAY,
            notes=f"{prefix}colis pret au retrait", **actor,
        )
    elif current_status == ParcelStatus.OUT_FOR_DELIVERY.value and parcel.get("delivery_mode") == "home_to_relay":
        result = await transition_status(
            parcel["parcel_id"], ParcelStatus.AVAILABLE_AT_RELAY,
            notes=f"{prefix}depot du livreur au relais — pret au retrait", **actor,
        )
    else:
        raise bad_request_exception(f"Impossible de receptionner un colis en statut '{current_status}'")

    if target_relay_id:
        await db.relay_points.update_one({"relay_id": target_relay_id}, {"$inc": {"current_load": 1}})
        # Notifier l'agent relais de destination
        await notify_relay_agent_parcel_arrived(target_relay_id, parcel)
    return result


@router.post("/{parcel_id}/drop-at-relay", summary="Scan entrée relais origine (agent)")
async def drop_at_relay(
    parcel_id: str,
    body: Optional[dict] = None,
    current_user: dict = Depends(require_role(
        UserRole.RELAY_AGENT, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    _ensure_relay_action_allowed(parcel, current_user, parcel.get("origin_relay_id"))
    if parcel.get("status") != ParcelStatus.CREATED.value:
        raise bad_request_exception("Seuls les colis créés peuvent être déposés au relais d'origine")

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

    if parcel["status"] == ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value:
        return await _scan_departure_from_origin_relay(parcel, current_user)

    return await _scan_arrival_at_relay(parcel, current_user)


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

    for code in codes:
        try:
            parcel = await db.parcels.find_one({"tracking_code": code.strip().upper()}, {"_id": 0})
            if not parcel:
                results.append({"code": code, "success": False, "error": "Introuvable"})
                continue

            status = parcel["status"]
            if status == ParcelStatus.CREATED.value:
                _ensure_relay_action_allowed(parcel, current_user, parcel.get("origin_relay_id"))
                await transition_status(
                    parcel["parcel_id"],
                    ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
                    actor_id=current_user["user_id"],
                    actor_role=current_user["role"],
                    notes="Batch scan: depot au relais origine",
                )
            elif status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value:
                await _scan_departure_from_origin_relay(parcel, current_user, batch=True)
            else:
                await _scan_arrival_at_relay(parcel, current_user, batch=True)

            results.append({"code": code, "success": True})
        except Exception as e:
            results.append({"code": code, "success": False, "error": str(e)})

    return {"results": results}


@router.post("/{parcel_id}/handout", summary="Remise destinataire (scan + PIN)")
@limiter.limit("10/minute")
async def handout_parcel(
    parcel_id: str,
    proof: ProofOfDelivery,
    request: Request,
    current_user: dict = Depends(require_role(
        UserRole.RELAY_AGENT, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    _ensure_relay_action_allowed(
        parcel,
        current_user,
        parcel.get("redirect_relay_id"),
        parcel.get("destination_relay_id"),
        parcel.get("transit_relay_id"),
    )
    if parcel.get("status") not in {ParcelStatus.AVAILABLE_AT_RELAY.value, ParcelStatus.AT_DESTINATION_RELAY.value}:
        raise bad_request_exception("Le colis doit être au relais pour une remise finale")
    if _delivery_is_blocked_by_payment(parcel):
        raise bad_request_exception("Paiement non confirmé. La remise finale est bloquée.")

    if proof.proof_type == "pin":
        if not proof.pin_code:
            raise bad_request_exception("PIN obligatoire pour remise au relais")
        await check_code_lockout(db, parcel_id, "relay_pin")
        stored_pin = parcel.get("relay_pin") or parcel.get("delivery_code", "")
        if stored_pin and proof.pin_code.strip() != stored_pin.strip():
            await record_failed_attempt(db, parcel_id, "relay_pin")
            raise bad_request_exception("PIN incorrect")
        await clear_code_attempts(db, parcel_id, "relay_pin")
    updated = await transition_status(
        parcel_id, ParcelStatus.DELIVERED,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
        notes=f"Remise relais — {proof.proof_type}",
        metadata={"pin_code": proof.pin_code},
    )
    # Décrémenter le stock du relais
    relay_id = parcel.get("redirect_relay_id") or parcel.get("destination_relay_id")
    if relay_id:
        await db.relay_points.update_one({"relay_id": relay_id}, {"$inc": {"current_load": -1}})
    return updated


# ── Actions livreurs ──────────────────────────────────────────────────────────
@router.post("/{parcel_id}/pickup", summary="Prise en charge par driver")
async def pickup_parcel(
    parcel_id: str,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    if parcel.get("status") == ParcelStatus.SUSPENDED.value:
        raise forbidden_exception("Ce colis est suspendu par l'administration. Action impossible.")
    _ensure_driver_action_allowed(parcel, current_user)

    now = datetime.now(timezone.utc)
    await db.parcels.update_one(
        {"parcel_id": parcel_id, "assigned_driver_id": parcel.get("assigned_driver_id")},
        {"$set": {"assigned_driver_id": current_user["user_id"], "updated_at": now}},
    )

    # H2R : le driver transporte vers un relais, pas vers un domicile → IN_TRANSIT
    # H2H / R2H : le driver livre au domicile → OUT_FOR_DELIVERY
    mode = parcel.get("delivery_mode", "")
    target_status = (
        ParcelStatus.IN_TRANSIT
        if mode == "home_to_relay"
        else ParcelStatus.OUT_FOR_DELIVERY
    )
    return await transition_status(
        parcel_id, target_status,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
    )


class ArriveAtDestinationRequest(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)

@router.post("/{parcel_id}/arrive-at-destination", summary="Driver signale son arrivée au domicile destinataire")
async def arrive_at_destination(
    parcel_id: str,
    body: ArriveAtDestinationRequest,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    """Le driver signale qu'il est arrivé chez le destinataire (R2H / H2H).
    Transition IN_TRANSIT → OUT_FOR_DELIVERY. Vérifie la proximité < 500m."""
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    if parcel.get("status") == ParcelStatus.SUSPENDED.value:
        raise forbidden_exception("Ce colis est suspendu par l'administration.")
    _ensure_driver_action_allowed(parcel, current_user)
    if parcel.get("status") != ParcelStatus.IN_TRANSIT.value:
        raise bad_request_exception("Le colis doit être en transit pour signaler l'arrivée à destination")

    # Vérification proximité : driver doit être à < 500m de la destination
    dest_geopin = (parcel.get("delivery_address") or {}).get("geopin")
    if dest_geopin and dest_geopin.get("lat") and dest_geopin.get("lng"):
        from services.parcel_service import _haversine_km
        dist_m = _haversine_km(body.lat, body.lng, dest_geopin["lat"], dest_geopin["lng"]) * 1000
        if dist_m > 500:
            raise bad_request_exception(
                f"Vous êtes à {int(dist_m)}m de la destination. Rapprochez-vous à moins de 500m."
            )

    return await transition_status(
        parcel_id, ParcelStatus.OUT_FOR_DELIVERY,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
        notes="Arrivée au domicile du destinataire (GPS vérifié)",
    )


@router.post("/{parcel_id}/deliver", summary="Marquer livré — code 6 chiffres obligatoire")
@limiter.limit("10/minute")
async def deliver_parcel(
    parcel_id: str,
    body: CodeDelivery,
    request: Request,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    if parcel.get("status") == ParcelStatus.SUSPENDED.value:
        raise forbidden_exception("Ce colis est suspendu par l'administration. Livraison impossible.")
    _ensure_driver_action_allowed(parcel, current_user)
    if parcel.get("status") != ParcelStatus.OUT_FOR_DELIVERY.value:
        raise bad_request_exception("Le colis doit être en cours de livraison pour être remis")
    if _delivery_is_blocked_by_payment(parcel):
        raise bad_request_exception("Paiement non confirmé. La remise finale est bloquée.")

    await check_code_lockout(db, parcel_id, "delivery_code")
    if parcel.get("delivery_code", "") != body.delivery_code.strip():
        await record_failed_attempt(db, parcel_id, "delivery_code")
        raise bad_request_exception("Code de livraison invalide. Vérifiez le code à 6 chiffres.")
    await clear_code_attempts(db, parcel_id, "delivery_code")

    # ── Géofence : livreur doit être à moins de 500m ───────────────────
    if parcel.get("is_simulation") and settings.DEBUG:
        logger.info(f"Bypass geofence pour colis de simulation {parcel_id}")
    elif body.driver_lat is not None and body.driver_lng is not None:
        # Priorité : delivery_location (confirmé GPS) puis delivery_address.geopin (saisi texte)
        delivery_loc = parcel.get("delivery_location") or {}
        geo = delivery_loc.get("geopin") or delivery_loc or (parcel.get("delivery_address") or {}).get("geopin") or {}
        dest_lat = geo.get("lat")
        dest_lng = geo.get("lng")
        if dest_lat is not None and dest_lng is not None:
            dist_m = _haversine_km(body.driver_lat, body.driver_lng, dest_lat, dest_lng) * 1000
            if dist_m > 500:
                raise bad_request_exception(
                    f"Vous êtes trop loin de l'adresse de livraison ({int(dist_m)} m). Rapprochez-vous (< 500 m)."
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
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    _ensure_driver_action_allowed(parcel, current_user)
    if parcel.get("status") != ParcelStatus.OUT_FOR_DELIVERY.value:
        raise bad_request_exception("L'échec ne peut être déclaré que pendant une livraison active")
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
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    _ensure_driver_action_allowed(parcel, current_user)
    if parcel.get("status") not in {ParcelStatus.DELIVERY_FAILED.value, ParcelStatus.OUT_FOR_DELIVERY.value}:
        raise bad_request_exception("La redirection n'est possible qu'après un échec ou depuis une livraison active")

    relay = await db.relay_points.find_one(
        {"relay_id": body.redirect_relay_id, "is_active": True},
        {"_id": 0, "relay_id": 1},
    )
    if not relay:
        raise bad_request_exception("Relais de redirection invalide ou inactif")

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
    allowed, _, is_recipient, _ = _can_access_parcel(parcel, current_user)
    if not allowed:
        raise forbidden_exception("AccÃ¨s refusÃ© Ã  ce colis")

    # L'expéditeur ou le relais origine voient le pickup_code
    can_see_pickup = (
        is_admin
        or parcel.get("sender_user_id") == user_id
        or (role == UserRole.RELAY_AGENT.value
            and current_user.get("relay_point_id") == parcel.get("origin_relay_id"))
    )

    mode = parcel.get("delivery_mode", "")
    show_delivery = (is_admin or is_recipient) and mode.endswith("_to_home")
    show_relay    = (is_admin or is_recipient) and mode.endswith("_to_relay")
    show_return   = is_admin or parcel.get("sender_user_id") == user_id

    return {
        "pickup_code":   parcel.get("pickup_code")   if can_see_pickup else None,
        "delivery_code": parcel.get("delivery_code") if (is_admin or show_delivery) else None,
        "relay_pin":     parcel.get("relay_pin")     if (is_admin or show_relay)    else None,
        "return_code":   parcel.get("return_code")   if show_return else None,
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



# ── Messagerie temporaire par colis ──────────────────────────────────────────

TERMINAL_STATUSES = {"delivered", "cancelled", "returned", "expired", "disputed"}


def _serialize_parcel_message(message: dict) -> dict:
    payload = {k: v for k, v in message.items() if k not in {"_id", "voice_path", "mime_type"}}
    if payload.get("type") == "voice":
        payload["content"] = None
        payload["voice_url"] = (
            f"{settings.BASE_URL}/api/parcels/{payload['parcel_id']}/messages/{payload['message_id']}/voice"
        )
    return payload


def _resolve_voice_file(message: dict) -> Path:
    voice_path = message.get("voice_path")
    if voice_path:
        candidate = Path(voice_path)
        if candidate.exists():
            return candidate

    content = message.get("content")
    if isinstance(content, str) and "/uploads/voice/" in content:
        filename = content.rsplit("/", 1)[-1]
        legacy_path = Path("uploads") / "voice" / filename
        if legacy_path.exists():
            return legacy_path

    raise not_found_exception("Fichier audio")

async def _check_parcel_access(parcel_id: str, user: dict) -> dict:
    """Vérifie que l'utilisateur est expéditeur, destinataire ou livreur assigné."""
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    uid = user["user_id"]
    role = user.get("role", "")
    is_sender    = parcel.get("sender_user_id") == uid
    is_recipient = parcel.get("recipient_user_id") == uid
    is_driver    = role == "driver" and parcel.get("assigned_driver_id") == uid
    is_admin     = role in ("admin", "superadmin")
    if not (is_sender or is_recipient or is_driver or is_admin):
        raise forbidden_exception("Accès refusé à cette messagerie")
    return parcel


@router.get("/{parcel_id}/messages", summary="Lire les messages du colis")
async def get_parcel_messages(
    parcel_id: str,
    current_user: dict = Depends(get_current_user),
):
    await _check_parcel_access(parcel_id, current_user)
    cursor = db.parcel_messages.find(
        {"parcel_id": parcel_id}, {"_id": 0}
    ).sort("created_at", 1)
    messages = await cursor.to_list(length=200)
    return {"messages": [_serialize_parcel_message(message) for message in messages]}


@router.post("/{parcel_id}/messages", summary="Envoyer un message texte")
@limiter.limit("20/minute")
async def send_parcel_message(
    parcel_id: str,
    body: dict,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    parcel = await _check_parcel_access(parcel_id, current_user)
    if parcel.get("status") in TERMINAL_STATUSES:
        raise bad_request_exception("La messagerie est fermée pour ce colis")

    text = (body.get("text") or "").strip()
    if not text:
        raise bad_request_exception("Message vide")
    if len(text) > 500:
        raise bad_request_exception("Message trop long (max 500 caractères)")

    # Déterminer le rôle de l'expéditeur dans ce colis
    uid = current_user["user_id"]
    if parcel.get("sender_user_id") == uid:
        sender_role = "sender"
    elif parcel.get("recipient_user_id") == uid:
        sender_role = "recipient"
    else:
        sender_role = current_user.get("role", "driver")

    msg = {
        "message_id":  f"msg_{uuid.uuid4().hex[:12]}",
        "parcel_id":   parcel_id,
        "sender_id":   uid,
        "sender_name": current_user.get("name", ""),
        "sender_role": sender_role,
        "type":        "text",
        "content":     text,
        "created_at":  datetime.now(timezone.utc),
    }
    await db.parcel_messages.insert_one(msg)
    try:
        await notify_new_parcel_message(parcel, uid, current_user.get("name", ""), text)
    except Exception:
        pass
    return _serialize_parcel_message(msg)


@router.get("/{parcel_id}/messages/{message_id}/voice", summary="Lire une note vocale du colis")
async def get_parcel_voice(
    parcel_id: str,
    message_id: str,
    current_user: dict = Depends(get_current_user),
):
    await _check_parcel_access(parcel_id, current_user)
    message = await db.parcel_messages.find_one(
        {"parcel_id": parcel_id, "message_id": message_id, "type": "voice"},
        {"_id": 0},
    )
    if not message:
        raise not_found_exception("Message vocal")

    audio_path = _resolve_voice_file(message)
    media_type = (
        message.get("mime_type")
        or mimetypes.guess_type(str(audio_path))[0]
        or "application/octet-stream"
    )
    return FileResponse(path=audio_path, media_type=media_type, filename=audio_path.name)

@router.post("/{parcel_id}/messages/voice", summary="Envoyer une note vocale")
@limiter.limit("10/minute")
async def send_parcel_voice(
    parcel_id: str,
    request: Request,
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    parcel = await _check_parcel_access(parcel_id, current_user)
    if parcel.get("status") in TERMINAL_STATUSES:
        raise bad_request_exception("La messagerie est fermée pour ce colis")

    # Validation type MIME
    allowed = {"audio/mp4", "audio/m4a", "audio/mpeg", "audio/ogg", "audio/webm", "audio/wav", "application/octet-stream"}
    if file.content_type not in allowed:
        raise bad_request_exception(f"Format audio non supporté : {file.content_type}")

    # Taille max 5 Mo
    MAX_SIZE = 5 * 1024 * 1024
    content = await file.read()
    if not content:
        raise bad_request_exception("Fichier audio vide")
    if len(content) > MAX_SIZE:
        raise bad_request_exception("Fichier trop volumineux (max 5 Mo)")

    # Sauvegarde en stockage prive pour eviter une URL publique permanente
    ext = file.filename.rsplit(".", 1)[-1] if "." in (file.filename or "") else "m4a"
    filename = f"voice_{uuid.uuid4().hex}.{ext}"
    PRIVATE_VOICE_DIR.mkdir(parents=True, exist_ok=True)
    filepath = PRIVATE_VOICE_DIR / filename
    with open(filepath, "wb") as f:
        f.write(content)

    uid = current_user["user_id"]
    if parcel.get("sender_user_id") == uid:
        sender_role = "sender"
    elif parcel.get("recipient_user_id") == uid:
        sender_role = "recipient"
    else:
        sender_role = current_user.get("role", "driver")

    msg = {
        "message_id":  f"msg_{uuid.uuid4().hex[:12]}",
        "parcel_id":   parcel_id,
        "sender_id":   uid,
        "sender_name": current_user.get("name", ""),
        "sender_role": sender_role,
        "type":        "voice",
        "content":     None,
        "voice_path":  str(filepath),
        "mime_type":   file.content_type or "audio/m4a",
        "duration_s":  None,  # à enrichir côté client si besoin
        "created_at":  datetime.now(timezone.utc),
    }
    await db.parcel_messages.insert_one(msg)
    try:
        await notify_new_parcel_message(parcel, uid, current_user.get("name", ""), "🎤 Note vocale")
    except Exception:
        pass
    return _serialize_parcel_message(msg)
