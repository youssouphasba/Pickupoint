"""
Router webhooks : callbacks paiement et WhatsApp.

Flutterwave envoie un POST avec le tx_ref et le statut de la transaction.
Meta valide WhatsApp avec un GET qui doit renvoyer exactement hub.challenge.
"""
import hashlib
import hmac
import json
import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Query, Request, Response

from config import settings
from database import db
from services.parcel_service import _record_event
from services.payment_service import verify_payment
from services.stripe_service import handle_stripe_event
from services.whatsapp_support_service import record_whatsapp_inbound_message

logger = logging.getLogger(__name__)
router = APIRouter()


def _verify_whatsapp_signature(payload: bytes, signature: Optional[str]) -> None:
    secret = settings.WHATSAPP_APP_SECRET
    if not secret:
        raise HTTPException(status_code=503, detail="WhatsApp webhook app secret missing")
    if not signature or not signature.startswith("sha256="):
        raise HTTPException(status_code=401, detail="Signature WhatsApp manquante")
    received = signature.split("=", 1)[1].strip()
    expected = hmac.new(
        secret.encode(),
        payload,
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(received, expected):
        raise HTTPException(status_code=401, detail="Signature WhatsApp invalide")


@router.get("/whatsapp", summary="Validation webhook WhatsApp Cloud API")
async def verify_whatsapp_webhook(
    hub_mode: Optional[str] = Query(None, alias="hub.mode"),
    hub_verify_token: Optional[str] = Query(None, alias="hub.verify_token"),
    hub_challenge: Optional[str] = Query(None, alias="hub.challenge"),
):
    expected_token = settings.WHATSAPP_VERIFY_TOKEN
    if not expected_token:
        logger.warning("Webhook WhatsApp refus?: WHATSAPP_VERIFY_TOKEN non configur?")
        raise HTTPException(status_code=503, detail="WhatsApp webhook verify token missing")

    if hub_mode == "subscribe" and hub_challenge and hmac.compare_digest(hub_verify_token or "", expected_token):
        return Response(content=hub_challenge, media_type="text/plain")

    logger.warning("Webhook WhatsApp validation invalide: mode=%s", hub_mode)
    raise HTTPException(status_code=403, detail="Invalid WhatsApp webhook verification token")


@router.post("/whatsapp", summary="R?ception webhook WhatsApp Cloud API")
async def whatsapp_webhook(
    request: Request,
    x_hub_signature_256: Optional[str] = Header(None, alias="X-Hub-Signature-256"),
):
    payload_bytes = await request.body()
    _verify_whatsapp_signature(payload_bytes, x_hub_signature_256)

    try:
        payload = json.loads(payload_bytes.decode("utf-8"))
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
                try:
                    await record_whatsapp_inbound_message(value, message)
                except Exception as exc:
                    logger.warning("WhatsApp message non associ? au support: %s", exc)
                logger.info(
                    "WhatsApp message re?u: from=%s id=%s type=%s timestamp=%s",
                    message.get("from"),
                    message.get("id"),
                    message.get("type"),
                    message.get("timestamp"),
                )
            for call in value.get("calls") or []:
                call_doc = {
                    "call_event_id": call.get("id") or call.get("call_id"),
                    "phone_number_id": (value.get("metadata") or {}).get("phone_number_id"),
                    "display_phone_number": (value.get("metadata") or {}).get("display_phone_number"),
                    "from": call.get("from"),
                    "to": call.get("to"),
                    "direction": call.get("direction"),
                    "status": call.get("status"),
                    "event": call.get("event"),
                    "timestamp": call.get("timestamp"),
                    "raw_call": call,
                    "created_at": datetime.now(timezone.utc),
                }
                await db.whatsapp_call_events.insert_one(call_doc)
                logger.info(
                    "WhatsApp call event: id=%s from=%s status=%s event=%s",
                    call_doc["call_event_id"],
                    call_doc["from"],
                    call_doc["status"],
                    call_doc["event"],
                )

    return {"received": True}


@router.post("/stripe", summary="Callback Stripe wallet")
async def stripe_webhook(
    request: Request,
    stripe_signature: Optional[str] = Header(None, alias="Stripe-Signature"),
):
    payload = await request.body()
    return await handle_stripe_event(payload, stripe_signature)


@router.post("/flutterwave", summary="Callback paiement Flutterwave")
async def flutterwave_webhook(
    request: Request,
    verif_hash: Optional[str] = Header(None, alias="verif-hash"),
):
    if not settings.FLUTTERWAVE_WEBHOOK_SECRET:
        logger.warning("Webhook Flutterwave ignor?: secret non configur?")
        return {"received": False, "ignored": "webhook_secret_missing"}

    if not hmac.compare_digest(verif_hash or "", settings.FLUTTERWAVE_WEBHOOK_SECRET):
        raise HTTPException(status_code=401, detail="Signature invalide")

    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="JSON invalide")

    logger.info("Flutterwave webhook re?u")

    event = payload.get("event")
    data = payload.get("data", {})
    tx_ref = data.get("tx_ref", "")
    status = data.get("status", "")
    amount = data.get("amount")
    tx_id = data.get("id")
    logger.info(
        "Flutterwave webhook details: event=%s tx_ref=%s status=%s amount=%s",
        event,
        tx_ref,
        status,
        amount,
    )

    if not tx_ref:
        return {"received": True}

    parts = tx_ref.split("-")
    parcel_id = None
    if len(parts) >= 2 and parts[0] == "PKP":
        parcel_id = parts[1]

    parcel = None
    if parcel_id:
        parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        parcel = await db.parcels.find_one({"payment_ref": tx_ref}, {"_id": 0})

    if not parcel:
        logger.warning("Aucun colis trouv? pour tx_ref=%s", tx_ref)
        return {"received": True}

    now = datetime.now(timezone.utc)

    if status == "successful" and event == "charge.completed":
        if parcel.get("payment_status") == "paid" and parcel.get("payment_ref") == tx_ref:
            return {"received": True, "status": "already_processed"}

        if not tx_id:
            raise HTTPException(status_code=400, detail="Transaction ID manquant")

        verified = await verify_payment(str(tx_id))
        if verified.get("status") != "successful":
            logger.warning("V?rification Flutterwave ?chou?e pour tx_id=%s: %s", tx_id, verified)
            raise HTTPException(status_code=400, detail="Transaction non v?rifi?e")

        if verified.get("tx_ref") != tx_ref:
            logger.warning("Mismatch tx_ref webhook=%s verified=%s", tx_ref, verified.get("tx_ref"))
            raise HTTPException(status_code=400, detail="R?f?rence transaction incoh?rente")

        verified_amount = verified.get("amount")
        if verified_amount is not None:
            quoted_price = float(parcel.get("quoted_price") or 0)
            if quoted_price and abs(float(verified_amount) - quoted_price) > 1:
                logger.warning(
                    "Montant incoh?rent pour %s: webhook=%s verified=%s quoted=%s",
                    parcel["parcel_id"],
                    amount,
                    verified_amount,
                    quoted_price,
                )
                raise HTTPException(status_code=400, detail="Montant transaction incoh?rent")

        update_result = await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"], "payment_status": {"$ne": "paid"}},
            {"$set": {
                "payment_status": "paid",
                "paid_price": float(verified_amount) if verified_amount is not None else (float(amount) if amount else parcel.get("quoted_price")),
                "payment_method": verified.get("payment_type", data.get("payment_type", "mobile_money")),
                "payment_ref": tx_ref,
                "updated_at": now,
            }},
        )
        if update_result.modified_count == 0:
            return {"received": True, "status": "already_processed"}
        await _record_event(
            parcel_id=parcel["parcel_id"],
            event_type="PAYMENT_RECEIVED",
            actor_role="system",
            notes=f"Paiement confirm? Flutterwave ? tx_ref={tx_ref}",
            metadata={"tx_ref": tx_ref, "tx_id": tx_id, "amount": amount},
        )
        logger.info("Paiement confirm? pour %s", parcel["parcel_id"])

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
                notes=f"Paiement ?chou? Flutterwave ? tx_ref={tx_ref}",
                metadata={"tx_ref": tx_ref, "status": status},
            )

    return {"received": True}
