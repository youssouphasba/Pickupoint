"""
Router webhooks : callback paiement Flutterwave.
Flutterwave envoie un POST avec le tx_ref et le statut de la transaction.
Docs : https://developer.flutterwave.com/docs/integration-guides/webhooks
"""
import hashlib
import hmac
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Request, HTTPException, Header
from typing import Optional

from config import settings
from database import db
from services.parcel_service import _record_event
from services.payment_service import verify_by_tx_ref

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/flutterwave", summary="Callback paiement Flutterwave")
async def flutterwave_webhook(
    request: Request,
    verif_hash: Optional[str] = Header(None, alias="verif-hash"),
):
    # Vérifier la signature Flutterwave
    if settings.FLUTTERWAVE_WEBHOOK_SECRET:
        if verif_hash != settings.FLUTTERWAVE_WEBHOOK_SECRET:
            raise HTTPException(status_code=401, detail="Signature invalide")

    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="JSON invalide")

    logger.info(f"Flutterwave webhook reçu : {payload}")

    event = payload.get("event")           # "charge.completed"
    data  = payload.get("data", {})
    tx_ref  = data.get("tx_ref", "")
    status  = data.get("status", "")       # "successful", "failed"
    amount  = data.get("amount")
    tx_id   = data.get("id")

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
        await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"]},
            {"$set": {
                "payment_status": "paid",
                "paid_price":     float(amount) if amount else parcel.get("quoted_price"),
                "payment_method": data.get("payment_type", "mobile_money"),
                "payment_ref":    tx_ref,
                "updated_at":     now,
            }},
        )
        await _record_event(
            parcel_id=parcel["parcel_id"],
            event_type="PAYMENT_RECEIVED",
            actor_role="system",
            notes=f"Paiement confirmé Flutterwave — tx_ref={tx_ref}",
            metadata={"tx_ref": tx_ref, "tx_id": tx_id, "amount": amount},
        )
        logger.info(f"Paiement confirmé pour {parcel['parcel_id']}")

    elif status in ("failed", "cancelled"):
        await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"]},
            {"$set": {"payment_status": "failed", "updated_at": now}},
        )
        await _record_event(
            parcel_id=parcel["parcel_id"],
            event_type="PAYMENT_FAILED",
            actor_role="system",
            notes=f"Paiement échoué Flutterwave — tx_ref={tx_ref}",
            metadata={"tx_ref": tx_ref, "status": status},
        )

    return {"received": True}
