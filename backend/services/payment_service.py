"""
Service paiement : integration Flutterwave pour Wave, Orange Money et cartes.
"""
import logging
from typing import Optional

import httpx

from config import settings

logger = logging.getLogger(__name__)

FLUTTERWAVE_BASE_URL = "https://api.flutterwave.com/v3"


def _headers() -> dict:
    return {
        "Authorization": f"Bearer {settings.FLUTTERWAVE_SECRET_KEY}",
        "Content-Type": "application/json",
    }


async def create_payment_link(
    parcel_id: str,
    tracking_code: str,
    amount: float,
    customer_phone: str,
    customer_name: str = "Client Denkma",
    customer_email: str = "client@denkma.app",
    redirect_url: str = "https://pickupoint.sn/payment/callback",
) -> dict:
    """
    Cree un lien de paiement Flutterwave.

    Si Flutterwave n'est pas configure, aucun faux lien n'est genere :
    le paiement reste simplement disponible plus tard.
    """
    if not settings.FLUTTERWAVE_SECRET_KEY:
        logger.warning(
            "Flutterwave non configure - aucun lien de paiement genere"
        )
        return {
            "success": False,
            "tx_ref": None,
            "payment_link": None,
            "simulated": True,
        }

    tx_ref = f"PKP-{parcel_id}-{tracking_code}"

    payload = {
        "tx_ref": tx_ref,
        "amount": int(amount),
        "currency": "XOF",
        "redirect_url": redirect_url,
        "payment_options": "mobilemoneyfranco,card",
        "customer": {
            "email": customer_email,
            "phone_number": customer_phone,
            "name": customer_name,
        },
        "customizations": {
            "title": "Denkma",
            "description": f"Paiement colis {tracking_code}",
            "logo": "https://pickupoint.sn/logo.png",
        },
        "meta": {
            "parcel_id": parcel_id,
            "tracking_code": tracking_code,
        },
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                f"{FLUTTERWAVE_BASE_URL}/payments",
                json=payload,
                headers=_headers(),
            )
            resp.raise_for_status()
            data = resp.json()
            if data.get("status") == "success":
                return {
                    "success": True,
                    "tx_ref": tx_ref,
                    "payment_link": data["data"]["link"],
                }
            logger.error("Flutterwave erreur : %s", data)
            return {"success": False, "error": data.get("message")}
    except Exception as exc:
        logger.error("Erreur reseau Flutterwave : %s", exc)
        return {"success": False, "error": str(exc)}


async def verify_payment(transaction_id: str) -> dict:
    """Verifie le statut d'une transaction Flutterwave via son ID."""
    if not settings.FLUTTERWAVE_SECRET_KEY:
        return {"status": "successful", "simulated": True}

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{FLUTTERWAVE_BASE_URL}/transactions/{transaction_id}/verify",
                headers=_headers(),
            )
            resp.raise_for_status()
            data = resp.json()
            if data.get("status") == "success":
                return data.get("data", {})
            return {"status": "error", "message": data.get("message")}
    except Exception as exc:
        logger.error("Erreur verification Flutterwave : %s", exc)
        return {"status": "error", "error": str(exc)}


async def verify_by_tx_ref(tx_ref: str) -> dict:
    """Recherche une transaction par tx_ref."""
    if not settings.FLUTTERWAVE_SECRET_KEY:
        return {"status": "successful", "simulated": True}

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{FLUTTERWAVE_BASE_URL}/transactions",
                params={"tx_ref": tx_ref},
                headers=_headers(),
            )
            resp.raise_for_status()
            data = resp.json()
            items = data.get("data", [])
            if items:
                return items[0]
            return {"status": "not_found"}
    except Exception as exc:
        logger.error("Erreur recherche tx_ref : %s", exc)
        return {"status": "error", "error": str(exc)}
