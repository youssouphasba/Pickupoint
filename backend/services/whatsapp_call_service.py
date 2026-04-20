"""Services WhatsApp liés aux demandes de contact livreur.

La Calling API Meta nécessite une session média (SDP/WebRTC) pour initier un
vrai appel sortant. Tant que l'appel direct n'est pas implémenté côté client,
ce service déclenche le flux production robuste : le livreur demande un contact,
Denkma prévient le destinataire via une template WhatsApp approuvée, et l'action
est auditée sans jamais exposer le numéro au livreur.
"""
import logging
import json
import re
from datetime import datetime, timezone
from typing import Any

import httpx

from config import settings

logger = logging.getLogger(__name__)

DRIVER_CALL_PERMISSION_TEMPLATE = "driver_call_permission"
WHATSAPP_CALL_CONNECT_ACTION = "connect"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _whatsapp_to(phone: str | None) -> str:
    return re.sub(r"\D", "", phone or "")


async def send_driver_contact_request(
    *,
    recipient_phone: str,
    parcel: dict,
    mission: dict,
    driver: dict,
) -> dict[str, Any]:
    """Envoie au destinataire une demande de contact via le numéro Denkma."""
    if not settings.WHATSAPP_PHONE_NUMBER_ID or not settings.WHATSAPP_ACCESS_TOKEN:
        return {
            "sent": False,
            "channel": "whatsapp",
            "reason": "whatsapp_not_configured",
            "message": "WhatsApp Cloud API n'est pas configurée.",
            "template": DRIVER_CALL_PERMISSION_TEMPLATE,
        }

    to_number = _whatsapp_to(recipient_phone)
    if not to_number:
        return {
            "sent": False,
            "channel": "whatsapp",
            "reason": "recipient_phone_missing",
            "message": "Numéro destinataire manquant.",
            "template": DRIVER_CALL_PERMISSION_TEMPLATE,
        }

    tracking_code = parcel.get("tracking_code") or mission.get("tracking_code") or "Denkma"
    payload = {
        "messaging_product": "whatsapp",
        "to": to_number,
        "type": "template",
        "template": {
            "name": DRIVER_CALL_PERMISSION_TEMPLATE,
            "language": {"code": "fr"},
            "components": [
                {
                    "type": "body",
                    "parameters": [{"type": "text", "text": str(tracking_code)}],
                }
            ],
        },
    }
    url = (
        f"https://graph.facebook.com/{settings.WHATSAPP_API_VERSION}/"
        f"{settings.WHATSAPP_PHONE_NUMBER_ID}/messages"
    )
    headers = {
        "Authorization": f"Bearer {settings.WHATSAPP_ACCESS_TOKEN}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(url, headers=headers, json=payload)

    if response.status_code != 200:
        logger.warning("Demande contact WhatsApp refusée: %s %s", response.status_code, response.text)
        return {
            "sent": False,
            "channel": "whatsapp",
            "status_code": response.status_code,
            "reason": "whatsapp_send_failed",
            "message": "La demande WhatsApp n'a pas pu être envoyée.",
            "meta_error": response.text,
            "requested_at": _now(),
            "template": DRIVER_CALL_PERMISSION_TEMPLATE,
        }

    data = response.json()
    message_id = ((data.get("messages") or [{}])[0]).get("id")
    return {
        "sent": True,
        "channel": "whatsapp",
        "message_id": message_id,
        "message": "Demande de contact envoyée au destinataire via Denkma.",
        "requested_at": _now(),
        "template": DRIVER_CALL_PERMISSION_TEMPLATE,
    }


async def connect_driver_whatsapp_call(
    *,
    recipient_phone: str,
    parcel: dict,
    mission: dict,
    driver: dict,
    sdp_offer: str,
) -> dict[str, Any]:
    """Initie un vrai appel WhatsApp Cloud API avec une offre SDP WebRTC."""
    if not settings.WHATSAPP_PHONE_NUMBER_ID or not settings.WHATSAPP_ACCESS_TOKEN:
        return {
            "connected": False,
            "channel": "whatsapp_call",
            "reason": "whatsapp_not_configured",
            "message": "WhatsApp Cloud API n'est pas configurée.",
        }

    to_number = _whatsapp_to(recipient_phone)
    if not to_number:
        return {
            "connected": False,
            "channel": "whatsapp_call",
            "reason": "recipient_phone_missing",
            "message": "Numéro destinataire manquant.",
        }

    normalized_sdp = (sdp_offer or "").strip()
    if not normalized_sdp.startswith("v=0"):
        return {
            "connected": False,
            "channel": "whatsapp_call",
            "reason": "invalid_sdp_offer",
            "message": "Offre SDP WebRTC invalide.",
        }

    tracking_code = parcel.get("tracking_code") or mission.get("tracking_code") or "Denkma"
    opaque_data = json.dumps(
        {
            "mission_id": mission.get("mission_id"),
            "parcel_id": mission.get("parcel_id") or parcel.get("parcel_id"),
            "driver_id": driver.get("user_id"),
            "tracking_code": tracking_code,
        },
        separators=(",", ":"),
    )
    payload = {
        "messaging_product": "whatsapp",
        "to": to_number,
        "action": WHATSAPP_CALL_CONNECT_ACTION,
        "session": {
            "sdp_type": "offer",
            "sdp": normalized_sdp,
        },
        "biz_opaque_callback_data": opaque_data[:512],
    }
    url = (
        f"https://graph.facebook.com/{settings.WHATSAPP_API_VERSION}/"
        f"{settings.WHATSAPP_PHONE_NUMBER_ID}/calls"
    )
    headers = {
        "Authorization": f"Bearer {settings.WHATSAPP_ACCESS_TOKEN}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(url, headers=headers, json=payload)

    if response.status_code != 200:
        logger.warning("Appel WhatsApp refusé: %s %s", response.status_code, response.text)
        return {
            "connected": False,
            "channel": "whatsapp_call",
            "status_code": response.status_code,
            "reason": "whatsapp_call_failed",
            "message": "L'appel WhatsApp n'a pas pu être lancé.",
            "meta_error": response.text,
            "requested_at": _now(),
            "action": WHATSAPP_CALL_CONNECT_ACTION,
        }

    data = response.json()
    call = (data.get("calls") or [{}])[0]
    call_id = call.get("id") or call.get("call_id")
    return {
        "connected": True,
        "channel": "whatsapp_call",
        "call_id": call_id,
        "message": "Appel WhatsApp lancé via Denkma.",
        "requested_at": _now(),
        "action": WHATSAPP_CALL_CONNECT_ACTION,
        "raw": data,
    }
