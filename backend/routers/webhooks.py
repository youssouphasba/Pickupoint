"""
Router webhooks : callbacks paiement et WhatsApp.

Flutterwave envoie un POST avec le tx_ref et le statut de la transaction.
Meta valide WhatsApp avec un GET qui doit renvoyer exactement hub.challenge.
"""
import hmac
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Request, HTTPException, Header, Query, Response
from typing import Optional

from config import settings
from database import db
from services.parcel_service import _record_event
from services.payment_service import verify_payment

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/whatsapp", summary="Validation webhook WhatsApp Cloud API")
async def verify_whatsapp_webhook(
    hub_mode: Optional[str] = Query(None, alias="hub.mode"),
    hub_verify_token: Optional[str] = Query(None, alias="hub.verify_token"),
    hub_challenge: Optional[str] = Query(None, alias="hub.challenge"),
):
    """Endpoint appelé par Meta lors de la configuration du webhook WhatsApp."""
    expected_token = settings.WHATSAPP_VERIFY_TOKEN
    if not expected_token:
        logger.warning("Webhook WhatsApp refusé: WHATSAPP_VERIFY_TOKEN non configuré")
        raise HTTPException(status_code=503, detail="WhatsApp webhook verify token missing")

    if hub_mode == "subscribe" and hub_challenge and hmac.compare_digest(hub_verify_token or "", expected_token):
        return Response(content=hub_challenge, media_type="text/plain")

    logger.warning("Webhook WhatsApp validation invalide: mode=%s", hub_mode)
    raise HTTPException(status_code=403, detail="Invalid WhatsApp webhook verification token")


@router.post("/whatsapp", summary="Réception webhook WhatsApp Cloud API")
async def whatsapp_webhook(request: Request):
    """Reçoit les statuts et messages WhatsApp.

    Le traitement est volontairement tolérant : Meta attend un 200 rapide.
    Les événements détaillés sont journalisés pour permettre l'audit sans
    casser la réception si Meta change légèrement le payload.
    """
    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="JSON invalide")

    entries = payload.get("entry") or []
    for entry in entries:
        for change in entry.get("changes") or []:
            value = change.get("value") or {}
            for status in value.get("statuses") or []:
                logger.info(
                    "WhatsApp status: id=%s recipient=%s status=%s timestamp=%s",
                    status.get("id"),
                    status.get("recipient_id"),
                    status.get("status"),
                    status.get("timestamp"),
                )
            for message in value.get("messages") or []:
                logger.info(
                    "WhatsApp message reçu: from=%s id=%s type=%s timestamp=%s",
                    message.get("from"),
                    message.get("id"),
                    message.get("type"),
                    message.get("timestamp"),
                )

    return {"received": True}


@router.post("/flutterwave", summary="Callback paiement Flutterwave")
async def flutterwave_webhook(
    request: Request,
    verif_hash: Optional[str] = Header(None, alias="verif-hash"),
):
    if not settings.FLUTTERWAVE_WEBHOOK_SECRET:
        logger.warning("Webhook Flutterwave ignoré: secret non configuré")
        return {"received": False, "ignored": "webhook_secret_missing"}

    if not hmac.compare_digest(verif_hash or "", settings.FLUTTERWAVE_WEBHOOK_SECRET):
        raise HTTPException(status_code=401, detail="Signature invalide")

    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="JSON invalide")

    logger.info("Flutterwave webhook reçu")

    event = payload.get("event")           # "charge.completed"
    data  = payload.get("data", {})
    tx_ref  = data.get("tx_ref", "")
    status  = data.get("status", "")       # "successful", "failed"
    amount  = data.get("amount")
    tx_id   = data.get("id")
    logger.info(
        "Flutterwave webhook details: event=%s tx_ref=%s status=%s amount=%s",
        event,
        tx_ref,
        status,
        amount,
    )

    if not tx_ref:
        return {"received": True}

    # tx_ref format : "PKP-{parcel_id}-{tracking_code}"
    parts = tx_ref.split("-")
    parcel_id = None
    if len(parts) >= 2 and parts[0] == "PKP":
        parcel_id = parts[1]

    # Retrouver le colis
    parcel = None
    if parcel_id:
        parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        # Fallback : chercher par payment_ref
        parcel = await db.parcels.find_one({"payment_ref": tx_ref}, {"_id": 0})

    if not parcel:
        logger.warning(f"Aucun colis trouvé pour tx_ref={tx_ref}")
        return {"received": True}

    now = datetime.now(timezone.utc)

    if status == "successful" and event == "charge.completed":
        if parcel.get("payment_status") == "paid" and parcel.get("payment_ref") == tx_ref:
            return {"received": True, "status": "already_processed"}

        if not tx_id:
            raise HTTPException(status_code=400, detail="Transaction ID manquant")

        verified = await verify_payment(str(tx_id))
        if verified.get("status") != "successful":
            logger.warning("Vérification Flutterwave échouée pour tx_id=%s: %s", tx_id, verified)
            raise HTTPException(status_code=400, detail="Transaction non vérifiée")

        if verified.get("tx_ref") != tx_ref:
            logger.warning("Mismatch tx_ref webhook=%s verified=%s", tx_ref, verified.get("tx_ref"))
            raise HTTPException(status_code=400, detail="Référence transaction incohérente")

        verified_amount = verified.get("amount")
        if verified_amount is not None:
            quoted_price = float(parcel.get("quoted_price") or 0)
            if quoted_price and abs(float(verified_amount) - quoted_price) > 1:
                logger.warning(
                    "Montant incohérent pour %s: webhook=%s verified=%s quoted=%s",
                    parcel["parcel_id"],
                    amount,
                    verified_amount,
                    quoted_price,
                )
                raise HTTPException(status_code=400, detail="Montant transaction incohérent")

        update_result = await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"], "payment_status": {"$ne": "paid"}},
            {"$set": {
                "payment_status": "paid",
                "paid_price":     float(verified_amount) if verified_amount is not None else (float(amount) if amount else parcel.get("quoted_price")),
                "payment_method": verified.get("payment_type", data.get("payment_type", "mobile_money")),
                "payment_ref":    tx_ref,
                "updated_at":     now,
            }},
        )
        if update_result.modified_count == 0:
            return {"received": True, "status": "already_processed"}
        await _record_event(
            parcel_id=parcel["parcel_id"],
            event_type="PAYMENT_RECEIVED",
            actor_role="system",
            notes=f"Paiement confirmé Flutterwave — tx_ref={tx_ref}",
            metadata={"tx_ref": tx_ref, "tx_id": tx_id, "amount": amount},
        )
        logger.info(f"Paiement confirmé pour {parcel['parcel_id']}")

    elif status in ("failed", "cancelled"):
        update_result = await db.parcels.update_one(
            {
                "parcel_id": parcel["parcel_id"],
                "payment_status": {"$nin": ["paid", "failed"]},
            },
            {"$set": {"payment_status": "failed", "updated_at": now}},
        )
        if update_result.modified_count:
            await _record_event(
                parcel_id=parcel["parcel_id"],
                event_type="PAYMENT_FAILED",
                actor_role="system",
                notes=f"Paiement échoué Flutterwave — tx_ref={tx_ref}",
                metadata={"tx_ref": tx_ref, "status": status},
            )

    return {"received": True}
