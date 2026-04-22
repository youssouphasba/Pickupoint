"""Services WhatsApp liés aux appels livreur.

La Calling API Meta exige une autorisation explicite du destinataire avant de
lancer un appel sortant. Le backend doit donc demander cette permission via le
format interactif Meta, puis seulement ensuite tenter l'appel WebRTC.
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
WHATSAPP_CALL_PERMISSION_ACTION = "call_permission_request"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _whatsapp_to(phone: str | None) -> str:
    return re.sub(r"\D", "", phone or "")


def _call_api_base_url() -> str:
    version = settings.WHATSAPP_CALL_API_VERSION or settings.WHATSAPP_API_VERSION
    return f"https://graph.facebook.com/{version}/{settings.WHATSAPP_PHONE_NUMBER_ID}"


def _graph_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {settings.WHATSAPP_ACCESS_TOKEN}",
        "Content-Type": "application/json",
    }


def _permission_allows_call(permission: dict[str, Any]) -> bool:
    for action in permission.get("actions") or []:
        if action.get("action_name") == "start_call" and action.get("can_perform_action") is True:
            return True
    status = str(permission.get("status") or permission.get("permission_status") or "").lower()
    return status in {"granted", "approved", "active"}


def _can_request_call_permission(permission: dict[str, Any]) -> bool:
    for action in permission.get("actions") or []:
        if action.get("action_name") == "send_call_permission_request":
            return action.get("can_perform_action") is True
    status = str(permission.get("status") or permission.get("permission_status") or "").lower()
    return status not in {"pending", "denied"}


def _permission_limit_message(permission: dict[str, Any]) -> str:
    for action in permission.get("actions") or []:
        if action.get("action_name") != "send_call_permission_request":
            continue
        limits = action.get("limits") or []
        if limits:
            return "Autorisation d'appel en attente côté destinataire. Réessayez après le délai Meta."
        if action.get("can_perform_action") is False:
            return "Meta bloque temporairement une nouvelle demande d'autorisation d'appel pour ce destinataire."
    return "Le destinataire doit d'abord autoriser les appels WhatsApp de Denkma."


async def get_driver_call_permission(recipient_phone: str) -> dict[str, Any]:
    """Vérifie si le destinataire a autorisé les appels WhatsApp de Denkma."""
    if not settings.WHATSAPP_PHONE_NUMBER_ID or not settings.WHATSAPP_ACCESS_TOKEN:
        return {
            "checked": False,
            "approved": False,
            "reason": "whatsapp_not_configured",
            "message": "WhatsApp Cloud API n'est pas configurée.",
        }

    to_number = _whatsapp_to(recipient_phone)
    if not to_number:
        return {
            "checked": False,
            "approved": False,
            "reason": "recipient_phone_missing",
            "message": "Numéro destinataire manquant.",
        }

    url = f"{_call_api_base_url()}/call_permissions"
    params = {"user_wa_id": to_number}
    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.get(url, headers=_graph_headers(), params=params)

    if response.status_code != 200:
        logger.warning("Vérification permission appel refusée: %s %s", response.status_code, response.text)
        return {
            "checked": False,
            "approved": False,
            "status_code": response.status_code,
            "reason": "call_permission_check_failed",
            "message": "Impossible de vérifier l'autorisation d'appel WhatsApp.",
            "meta_error": response.text,
        }

    data = response.json()
    permissions = data.get("data") if isinstance(data.get("data"), list) else []
    permission = permissions[0] if permissions else data
    approved = _permission_allows_call(permission)
    return {
        "checked": True,
        "approved": approved,
        "can_request_permission": _can_request_call_permission(permission),
        "permission": permission,
        "raw": data,
    }


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
    driver_name = driver.get("name") or "Votre livreur"
    payload = {
        "messaging_product": "whatsapp",
        "recipient_type": "individual",
        "to": to_number,
        "type": "interactive",
        "interactive": {
            "type": "call_permission_request",
            "body": {
                "text": (
                    f"{driver_name} souhaite vous appeler via Denkma au sujet du colis "
                    f"{tracking_code}. Si un bouton d'autorisation s'affiche, appuyez dessus. "
                    "Sinon, ouvrez les infos de cette discussion WhatsApp et autorisez les appels."
                )
            },
            "action": {
                "name": WHATSAPP_CALL_PERMISSION_ACTION,
            },
        },
    }
    url = f"{_call_api_base_url()}/messages"

    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(url, headers=_graph_headers(), json=payload)

    if response.status_code != 200:
        logger.warning("Demande contact WhatsApp refusée: %s %s", response.status_code, response.text)
        return {
            "sent": False,
            "channel": "whatsapp",
            "status_code": response.status_code,
            "reason": "whatsapp_send_failed",
            "message": "La demande d'autorisation WhatsApp n'a pas pu être envoyée.",
            "meta_error": response.text,
            "requested_at": _now(),
            "template": None,
            "action": WHATSAPP_CALL_PERMISSION_ACTION,
        }

    data = response.json()
    message_id = ((data.get("messages") or [{}])[0]).get("id")
    return {
        "sent": True,
        "channel": "whatsapp",
        "message_id": message_id,
        "message": "Autorisation d'appel demandée au destinataire.",
        "requested_at": _now(),
        "template": None,
        "action": WHATSAPP_CALL_PERMISSION_ACTION,
    }


async def ensure_driver_call_permission_request(
    *,
    recipient_phone: str,
    parcel: dict,
    mission: dict,
    driver: dict,
) -> dict[str, Any]:
    """Vérifie l'autorisation d'appel et envoie la demande si nécessaire."""
    permission = await get_driver_call_permission(recipient_phone)
    if permission.get("approved"):
        return {
            "approved": True,
            "sent": False,
            "channel": "whatsapp",
            "reason": "call_permission_already_granted",
            "message": "Le destinataire a déjà autorisé les appels WhatsApp de Denkma.",
            "permission": permission.get("permission"),
        }

    if permission.get("checked") and not permission.get("can_request_permission", True):
        return {
            "approved": False,
            "sent": False,
            "channel": "whatsapp",
            "reason": "call_permission_request_limited",
            "message": _permission_limit_message(permission.get("permission") or {}),
            "permission": permission.get("permission"),
            "permission_status_code": permission.get("status_code"),
            "permission_error": permission.get("meta_error"),
        }

    request_result = await send_driver_contact_request(
        recipient_phone=recipient_phone,
        parcel=parcel,
        mission=mission,
        driver=driver,
    )
    return {
        "approved": False,
        "sent": bool(request_result.get("sent")),
        "channel": "whatsapp",
        "reason": (
            "call_permission_required"
            if request_result.get("sent")
            else request_result.get("reason")
        ),
        "message": request_result.get("message"),
        "permission": permission.get("permission"),
        "permission_status_code": permission.get("status_code"),
        "permission_error": permission.get("meta_error"),
        **request_result,
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

    permission = await get_driver_call_permission(recipient_phone)
    if not permission.get("approved"):
        request_result = await ensure_driver_call_permission_request(
            recipient_phone=recipient_phone,
            parcel=parcel,
            mission=mission,
            driver=driver,
        )
        return {
            "connected": False,
            "channel": "whatsapp_call",
            "reason": "call_permission_required",
            "message": (
                "Autorisation d'appel en attente côté destinataire."
                if request_result.get("sent")
                else request_result.get("message")
                or "Le destinataire doit d'abord autoriser l'appel WhatsApp."
            ),
            "permission_request_sent": bool(request_result.get("sent")),
            "permission_status_code": permission.get("status_code"),
            "permission_error": permission.get("meta_error"),
            "request_status_code": request_result.get("status_code"),
            "request_error": request_result.get("meta_error"),
            "requested_at": _now(),
            "action": WHATSAPP_CALL_PERMISSION_ACTION,
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
    url = f"{_call_api_base_url()}/calls"

    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(url, headers=_graph_headers(), json=payload)

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
