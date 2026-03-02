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
from services.wallet_service import credit_wallet, debit_wallet

router = APIRouter()


@router.post("/quote", response_model=QuoteResponse, summary="Calculer un devis (sans créer)")
async def quote_parcel(body: ParcelQuote):
    return await calculate_price(body)


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
        # Client : voit ses colis ENVOYÉS et les colis qu'il reçoit (recipient_phone)
        query = {
            "$or": [
                {"sender_user_id": current_user["user_id"]},
                {"recipient_phone": current_user.get("phone")},
            ]
        }

    if status:
        query["status"] = status

    cursor = db.parcels.find(query, {"_id": 0}).skip(skip).limit(limit)
    parcels = await cursor.to_list(length=limit)
    total = await db.parcels.count_documents(query)
    return {"parcels": parcels, "total": total}


from core.utils import mask_phone

@router.get("/{parcel_id}", summary="Détail + timeline")
async def get_parcel(parcel_id: str, current_user: dict = Depends(get_current_user)):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    
    # Masquage anti-bypass
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin:
        if "recipient_phone" in parcel:
            parcel["recipient_phone"] = mask_phone(parcel["recipient_phone"])
            
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
        # Relais destination réceptionne un colis qui vient du relais origine
        # Chemin obligatoire : DROPPED → IN_TRANSIT → AT_DESTINATION_RELAY → AVAILABLE_AT_RELAY
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
            }
            
            if status in arrive_statuses:
                await transition_status(parcel_id, ParcelStatus.AVAILABLE_AT_RELAY, notes="Batch scan: Arrivée", **actor)
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

    # ── Validation du paiement (si obligatoire) ────────────────────────
    # Si le statut est 'paid', c'est bon. 
    # Si c'est 'pending' et que le paiement est requis (ex: who_pays='sender' ou 'recipient'), bloquer.
    if parcel.get("payment_status") != "paid":
        # Exception : si c'est un paiement Cash on Delivery (COD), on pourrait autoriser, 
        # mais ici on suit la logique Flutterwave/In-App.
        raise bad_request_exception("Le paiement n'a pas encore été confirmé. Demandez au client de régler via le lien reçu.")

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

    return {
        "pickup_code":   parcel.get("pickup_code")   if can_see_pickup else None,
        "delivery_code": parcel.get("delivery_code") if is_admin else parcel.get("delivery_code"),
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

