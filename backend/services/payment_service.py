"""
Service paiement : intégration Flutterwave pour Wave, Orange Money, Mobile Money (XOF).
Docs : https://developer.flutterwave.com/docs
"""
import logging
import httpx
from typing import Optional
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
    customer_name: str = "Client PickuPoint",
    customer_email: str = "client@pickupoint.sn",
    redirect_url: str = "https://pickupoint.sn/payment/callback",
) -> dict:
    """
    Crée un lien de paiement Flutterwave (Standard Payment Link).
    Retourne l'URL de paiement à rediriger côté client.
    """
    if not settings.FLUTTERWAVE_SECRET_KEY:
        logger.warning("Flutterwave non configuré — paiement simulé")
        return {
            "success": True,
            "tx_ref": f"PKP-{parcel_id[:8]}",
            "payment_link": f"https://pay.example.com/{tracking_code}",
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
            "email":       customer_email,
            "phone_number": customer_phone,
            "name":        customer_name,
        },
        "customizations": {
            "title":       "PickuPoint",
            "description": f"Paiement colis {tracking_code}",
            "logo":        "https://pickupoint.sn/logo.png",
        },
        "meta": {
            "parcel_id":     parcel_id,
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
            data = resp.json()
            if data.get("status") == "success":
                return {
                    "success": True,
                    "tx_ref": tx_ref,
                    "payment_link": data["data"]["link"],
                }
            else:
                logger.error(f"Flutterwave erreur : {data}")
                return {"success": False, "error": data.get("message")}
    except Exception as e:
        logger.error(f"Erreur réseau Flutterwave : {e}")
        return {"success": False, "error": str(e)}


async def verify_payment(transaction_id: str) -> dict:
    """
    Vérifie le statut d'une transaction Flutterwave via son ID.
    À appeler après le redirect ou dans le webhook.
    """
    if not settings.FLUTTERWAVE_SECRET_KEY:
        return {"status": "successful", "simulated": True}

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{FLUTTERWAVE_BASE_URL}/transactions/{transaction_id}/verify",
                headers=_headers(),
            )
            data = resp.json()
            if data.get("status") == "success":
                return data.get("data", {})
            return {"status": "error", "message": data.get("message")}
    except Exception as e:
        logger.error(f"Erreur vérification Flutterwave : {e}")
        return {"status": "error", "error": str(e)}


async def verify_by_tx_ref(tx_ref: str) -> dict:
    """Recherche une transaction par tx_ref (utile dans le webhook)."""
    if not settings.FLUTTERWAVE_SECRET_KEY:
        return {"status": "successful", "simulated": True}

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{FLUTTERWAVE_BASE_URL}/transactions",
                params={"tx_ref": tx_ref},
                headers=_headers(),
            )
            data = resp.json()
            items = data.get("data", [])
            if items:
                return items[0]
            return {"status": "not_found"}
    except Exception as e:
        logger.error(f"Erreur recherche tx_ref : {e}")
        return {"status": "error", "error": str(e)}
