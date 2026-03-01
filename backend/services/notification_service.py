"""
Service notification : envoi de notifications push, SMS, WhatsApp aux utilisateurs.
"""
import logging
from datetime import datetime, timezone
import uuid
from typing import Optional

from database import db
from models.notification import NotificationChannel, NotificationStatus
from models.common import ParcelStatus

logger = logging.getLogger(__name__)


def _notif_id() -> str:
    return f"ntf_{uuid.uuid4().hex[:12]}"


STATUS_MESSAGES = {
    ParcelStatus.CREATED:                 "Votre colis a été créé. Code de suivi : {tracking_code}",
    ParcelStatus.DROPPED_AT_ORIGIN_RELAY: "Votre colis a été déposé au point relais.",
    ParcelStatus.IN_TRANSIT:              "Votre colis est en transit.",
    ParcelStatus.AT_DESTINATION_RELAY:    "Votre colis est arrivé au relais destination.",
    ParcelStatus.AVAILABLE_AT_RELAY:      "Votre colis est disponible pour retrait au relais. Code PIN requis.",
    ParcelStatus.OUT_FOR_DELIVERY:        "Un livreur est en route pour livrer votre colis.",
    ParcelStatus.DELIVERED:               "Votre colis a été livré avec succès. Merci d'avoir utilisé PickuPoint !",
    ParcelStatus.DELIVERY_FAILED:         "La livraison a échoué. Votre colis sera redirigé vers un relais.",
    ParcelStatus.CANCELLED:               "Votre colis a été annulé.",
    ParcelStatus.EXPIRED:                 "Le délai de retrait de votre colis est expiré.",
    ParcelStatus.RETURNED:                "Votre colis a été retourné à l'expéditeur.",
}


async def notify_parcel_status_change(parcel: dict, new_status: ParcelStatus):
    """Notifie l'expéditeur et le destinataire du changement de statut."""
    tracking_code = parcel.get("tracking_code", "")
    body = STATUS_MESSAGES.get(new_status, f"Statut mis à jour : {new_status.value}")
    body = body.format(tracking_code=tracking_code)

    # Notifier expéditeur
    sender_id = parcel.get("sender_user_id")
    if sender_id:
        await _store_and_send(
            user_id=sender_id,
            title="Mise à jour colis",
            body=body,
            ref_type="parcel",
            ref_id=parcel.get("parcel_id"),
        )

    # Notifier destinataire via SMS (pas forcément inscrit)
    recipient_phone = parcel.get("recipient_phone")
    if recipient_phone:
        await _send_sms(recipient_phone, body)


async def _store_and_send(
    user_id: str,
    title: str,
    body: str,
    ref_type: Optional[str] = None,
    ref_id: Optional[str] = None,
):
    """Stocke la notification en base et tente l'envoi."""
    now = datetime.now(timezone.utc)
    notif = {
        "notif_id":   _notif_id(),
        "user_id":    user_id,
        "channel":    NotificationChannel.IN_APP.value,
        "title":      title,
        "body":       body,
        "status":     NotificationStatus.SENT.value,
        "metadata":   {},
        "ref_type":   ref_type,
        "ref_id":     ref_id,
        "created_at": now,
        "sent_at":    now,
        "read_at":    None,
    }
    await db.notifications.insert_one(notif)


async def _send_sms(phone: str, body: str):
    """Envoi SMS via Twilio (best-effort, ne lève pas d'exception)."""
    try:
        from config import settings
        if not settings.TWILIO_ACCOUNT_SID or not settings.TWILIO_SMS_NUMBER:
            return
        from twilio.rest import Client
        client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
        client.messages.create(body=body, from_=settings.TWILIO_SMS_NUMBER, to=phone)
    except Exception as e:
        logger.warning(f"SMS non envoyé à {phone} : {e}")

async def notify_delivery_code(
    phone: str,
    recipient_name: str,
    tracking_code: str,
    delivery_code: str,
) -> None:
    """Envoie le code de livraison au destinataire par WhatsApp/SMS."""
    msg = (
        f"Bonjour {recipient_name},\n"
        f"Un colis vous est destiné (réf. {tracking_code}).\n"
        f"Votre code de réception : *{delivery_code}*\n"
        f"Donnez ce code au livreur pour valider la remise. Ne le partagez pas."
    )
    try:
        await _send_sms(phone, msg)
    except Exception as e:
        logger.warning("Impossible d'envoyer le code livraison: %s", e)
