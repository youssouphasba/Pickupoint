"""
Router parcels : CRUD colis + toutes les actions de transition de la machine d'états.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query

from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, forbidden_exception, bad_request_exception
from database import db
from models.common import UserRole, ParcelStatus
from models.parcel import ParcelCreate, Parcel, ParcelQuote, QuoteResponse, FailDeliveryRequest, RedirectRelayRequest
from models.delivery import ProofOfDelivery, CodeDelivery
from services.parcel_service import create_parcel, transition_status, get_parcel_timeline
from services.pricing_service import calculate_price, _haversine_km

router = APIRouter()


@router.post("/quote", response_model=QuoteResponse, summary="Calculer un devis (sans créer)")
async def quote_parcel(body: ParcelQuote):
    return await calculate_price(body)


@router.post("", summary="Créer un colis")
async def create_parcel_endpoint(
    body: ParcelCreate,
    current_user: dict = Depends(get_current_user),
):
    parcel = await create_parcel(body, sender_user_id=current_user["user_id"])
    return parcel


@router.get("", summary="Mes colis")
async def list_parcels(
    status: Optional[str] = None,
    skip: int = 0,
    limit: int = 50,
    current_user: dict = Depends(get_current_user),
):
    role = current_user["role"]
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
        query = {"sender_user_id": current_user["user_id"]}

    if status:
        query["status"] = status

    cursor = db.parcels.find(query, {"_id": 0}).skip(skip).limit(limit)
    parcels = await cursor.to_list(length=limit)
    total = await db.parcels.count_documents(query)
    return {"parcels": parcels, "total": total}


@router.get("/{parcel_id}", summary="Détail + timeline")
async def get_parcel(parcel_id: str, current_user: dict = Depends(get_current_user)):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    timeline = await get_parcel_timeline(parcel_id)
    return {"parcel": parcel, "timeline": timeline}


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
    current_user: dict = Depends(require_role(
        UserRole.RELAY_AGENT, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    current_status = parcel["status"]

    if current_status == ParcelStatus.REDIRECTED_TO_RELAY.value:
        # Colis redirigé après échec de livraison → disponible directement
        return await transition_status(
            parcel_id, ParcelStatus.AVAILABLE_AT_RELAY,
            actor_id=current_user["user_id"], actor_role=current_user["role"],
            notes="Réception colis redirigé après échec de livraison",
        )
    else:
        # Colis normal en transit depuis l'origine → relais destination
        await transition_status(
            parcel_id, ParcelStatus.AT_DESTINATION_RELAY,
            actor_id=current_user["user_id"], actor_role=current_user["role"],
        )
        return await transition_status(
            parcel_id, ParcelStatus.AVAILABLE_AT_RELAY,
            actor_id=current_user["user_id"], actor_role=current_user["role"],
        )


@router.post("/{parcel_id}/handout", summary="Remise destinataire (scan + PIN)")
async def handout_parcel(
    parcel_id: str,
    proof: ProofOfDelivery,
    current_user: dict = Depends(require_role(
        UserRole.RELAY_AGENT, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    if proof.proof_type == "pin" and not proof.pin_code:
        raise bad_request_exception("PIN obligatoire pour remise au relais")
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

    # ── Validation du code ─────────────────────────────────────────────
    if parcel.get("delivery_code", "") != body.delivery_code.strip():
        raise bad_request_exception("Code de livraison invalide")

    # ── Géofence : livreur doit être à moins de 500 m du destinataire ──
    if body.driver_lat is not None and body.driver_lng is not None:
        delivery_addr = parcel.get("delivery_address") or {}
        geopin = delivery_addr.get("geopin") or {}
        dest_lat = geopin.get("lat")
        dest_lng = geopin.get("lng")
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
        metadata={"delivery_code_used": True},
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

    return {
        "pickup_code":   parcel.get("pickup_code")   if can_see_pickup else None,
        "delivery_code": parcel.get("delivery_code") if is_admin else parcel.get("delivery_code"),
    }
