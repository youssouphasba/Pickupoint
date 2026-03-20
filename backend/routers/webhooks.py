"""
Router webhooks : callback paiement Flutterwave.
Flutterwave envoie un POST avec le tx_ref et le statut de la transaction.
Docs : https://developer.flutterwave.com/docs/integration-guides/webhooks
"""
import hmac
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Request, HTTPException, Header
from typing import Optional

from config import settings
from database import db
from services.parcel_service import _record_event
from services.payment_service import verify_payment

logger = logging.getLogger(__name__)
router = APIRouter()


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
