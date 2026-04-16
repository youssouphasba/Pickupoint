"""
Service notification : envoi de notifications push, SMS, WhatsApp aux utilisateurs.
"""
import logging
from datetime import datetime, timezone
import uuid
from typing import Optional

from config import settings
from database import db
from models.notification import NotificationChannel, NotificationStatus
from models.common import ParcelStatus

logger = logging.getLogger(__name__)

# Firebase Admin — initialisé à la demande (pas à l'import) pour éviter
# tout blocage réseau au démarrage (Railway tourne sur GCP, le metadata server
# est accessible et peut ralentir firebase_admin.initialize_app() sans creds).
_firebase_initialized = False


def _ensure_firebase():
    """Vérifie que Firebase Admin est initialisé (par auth.py ou ici)."""
    global _firebase_initialized
    if _firebase_initialized:
        return
    try:
        import firebase_admin
        # Vérifier si déjà initialisé par auth.py
        if firebase_admin._apps:
            _firebase_initialized = True
            return
        # Sinon, initialiser
        import os, json
        from firebase_admin import credentials
        firebase_creds_env = os.environ.get("FIREBASE_CREDENTIALS")
        if firebase_creds_env:
            cred = credentials.Certificate(json.loads(firebase_creds_env))
        elif os.path.exists("firebase-service-account.json"):
            cred = credentials.Certificate("firebase-service-account.json")
        else:
            cred = None
        if cred:
            firebase_admin.initialize_app(cred)
        _firebase_initialized = True
    except Exception as e:
        logger.warning(f"Firebase Admin non initialisé (push désactivé) : {e}")


def _notif_id() -> str:
    return f"ntf_{uuid.uuid4().hex[:12]}"


STATUS_MESSAGES = {
    ParcelStatus.CREATED:                 "Votre colis a été créé. Code de suivi : {tracking_code}",
    ParcelStatus.DROPPED_AT_ORIGIN_RELAY: "Votre colis a été déposé au point relais.",
    ParcelStatus.IN_TRANSIT:              "Votre colis est en transit.",
    ParcelStatus.AT_DESTINATION_RELAY:    "Votre colis est arrivé au relais destination.",
    ParcelStatus.AVAILABLE_AT_RELAY:      "Votre colis est disponible pour retrait au relais. Code PIN requis.",
    ParcelStatus.OUT_FOR_DELIVERY:        "Un livreur est en route pour livrer votre colis.",
    ParcelStatus.DELIVERED:               "Votre colis a été livré avec succès. Merci d'avoir utilisé Denkma !",
    ParcelStatus.DELIVERY_FAILED:         "La livraison a échoué. Votre colis sera redirigé vers un relais.",
    ParcelStatus.REDIRECTED_TO_RELAY:     "Votre colis est disponible au relais. Votre code de retrait : {relay_pin}",
    ParcelStatus.CANCELLED:               "Votre colis a été annulé.",
    ParcelStatus.EXPIRED:                 "Le délai de retrait de votre colis est expiré.",
    ParcelStatus.RETURNED:                "Votre colis a été retourné à l'expéditeur.",
}

# Mapping ParcelStatus -> template WhatsApp approuvé (notifs proactives).
# Les templates qui ne figurent pas ici retombent sur le texte libre
# (qui n'est livré que si l'user a écrit dans les 24 h).
STATUS_TEMPLATES = {
    ParcelStatus.CREATED:          "parcel_created",
    ParcelStatus.OUT_FOR_DELIVERY: "parcel_assigned",
    ParcelStatus.IN_TRANSIT:       "parcel_assigned",
    ParcelStatus.DELIVERED:        "parcel_delivered",
}


def _category_pref_key(category: Optional[str]) -> str | None:
    return {
        "parcel_updates": "parcel_updates",
        "promotions": "promotions",
    }.get(category)


def _notification_category_enabled(user_doc: dict | None, category: Optional[str]) -> bool:
    pref_key = _category_pref_key(category)
    if not pref_key:
        return True
    prefs = (user_doc or {}).get("notification_prefs") or {}
    return bool(prefs.get(pref_key, True))


def _should_send_whatsapp_tracking(user_doc: dict | None, category: Optional[str]) -> bool:
    if category != "parcel_updates":
        return False
    if not user_doc:
        return False
    if not _notification_category_enabled(user_doc, category):
        return False

    prefs = user_doc.get("notification_prefs") or {}
    has_app = bool(user_doc.get("fcm_token"))

    # Sans app active: on force le suivi externe.
    if not has_app:
        return True

    # Avec app: WhatsApp reste optionnel.
    return bool(prefs.get("whatsapp", True))


def _first_name(full_name: Optional[str], fallback: str = "Client") -> str:
    if not full_name:
        return fallback
    return full_name.strip().split(" ")[0] or fallback


def _tracking_url(tracking_code: str) -> str:
    return f"{settings.BASE_URL}/api/tracking/{tracking_code}"


async def notify_parcel_status_change(parcel: dict, new_status: ParcelStatus):
    """Notifie l'expéditeur et le destinataire du changement de statut."""
    tracking_code = parcel.get("tracking_code", "")
    relay_pin = parcel.get("relay_pin", "—")
    body = STATUS_MESSAGES.get(new_status, f"Statut mis à jour : {new_status.value}")
    body = body.format(tracking_code=tracking_code, relay_pin=relay_pin)

    template_name = STATUS_TEMPLATES.get(new_status)
    tracking_url = _tracking_url(tracking_code)

    # Notifier expéditeur
    sender_id = parcel.get("sender_user_id")
    if sender_id:
        sender_first = _first_name(parcel.get("sender_name"))
        await _store_and_send(
            user_id=sender_id,
            title="Mise à jour colis",
            body=body,
            ref_type="parcel",
            ref_id=parcel.get("parcel_id"),
            category="parcel_updates",
            whatsapp_template=template_name,
            whatsapp_variables=_template_vars(template_name, sender_first, tracking_code, tracking_url),
        )

    # Notifier destinataire
    recipient_phone = parcel.get("recipient_phone")
    recipient_user_id = parcel.get("recipient_user_id")
    if not recipient_user_id and recipient_phone:
        # Recherche tardive (si inscrit entre temps)
        user = await db.users.find_one({"phone": recipient_phone}, {"user_id": 1})
        if user:
            recipient_user_id = user["user_id"]

    recipient_first = _first_name(parcel.get("recipient_name"))
    template_vars_recipient = _template_vars(template_name, recipient_first, tracking_code, tracking_url)

    if recipient_user_id:
        await _store_and_send(
            user_id=recipient_user_id,
            title="Mise à jour colis",
            body=body,
            ref_type="parcel",
            ref_id=parcel.get("parcel_id"),
            category="parcel_updates",
            whatsapp_template=template_name,
            whatsapp_variables=template_vars_recipient,
        )
    elif recipient_phone:
        if template_name:
            await _send_whatsapp_template(recipient_phone, template_name, template_vars_recipient)
        else:
            await _send_sms_or_whatsapp(recipient_phone, body)


def _template_vars(
    template_name: Optional[str],
    first_name: str,
    tracking_code: str,
    tracking_url: str,
) -> list[str]:
    if template_name in ("parcel_created", "parcel_assigned"):
        return [first_name, tracking_code, tracking_url]
    if template_name == "parcel_delivered":
        return [first_name, tracking_code]
    return []


async def notify_quote_finalized(
    user_id: str,
    parcel_id: str,
    tracking_code: str,
    amount: float,
    estimated_hours: str,
):
    body = (
        f"Le montant de votre colis {tracking_code} est maintenant confirmé : "
        f"{int(amount)} FCFA. Durée approximative : {estimated_hours}."
    )
    await _store_and_send(
        user_id=user_id,
        title="Montant confirmé",
        body=body,
        ref_type="parcel",
        ref_id=parcel_id,
        category="parcel_updates",
    )


async def _store_and_send(
    user_id: str,
    title: str,
    body: str,
    ref_type: Optional[str] = None,
    ref_id: Optional[str] = None,
    category: Optional[str] = None,
    whatsapp_template: Optional[str] = None,
    whatsapp_variables: Optional[list[str]] = None,
):
    """Stocke la notification en base et tente l'envoi."""
    user = await db.users.find_one(
        {"user_id": user_id},
        {"notification_prefs": 1, "phone": 1, "fcm_token": 1},
    )
    if not _notification_category_enabled(user, category):
        return

    await _store_notification(
        user_id=user_id,
        channel=NotificationChannel.IN_APP,
        title=title,
        body=body,
        ref_type=ref_type,
        ref_id=ref_id,
    )

    await _send_push(
        user_id=user_id,
        title=title,
        body=body,
        ref_type=ref_type,
        ref_id=ref_id,
        category=category,
    )

    if _should_send_whatsapp_tracking(user, category):
        phone = (user or {}).get("phone")
        if phone:
            if whatsapp_template:
                await _send_whatsapp_template(phone, whatsapp_template, whatsapp_variables or [])
            else:
                await _send_whatsapp(phone, body)


async def _store_notification(
    user_id: str,
    channel: NotificationChannel,
    title: str,
    body: str,
    ref_type: Optional[str] = None,
    ref_id: Optional[str] = None,
    metadata: Optional[dict] = None,
    status: NotificationStatus = NotificationStatus.SENT,
):
    now = datetime.now(timezone.utc)
    notif = {
        "notif_id": _notif_id(),
        "user_id": user_id,
        "channel": channel.value,
        "title": title,
        "body": body,
        "status": status.value,
        "metadata": metadata or {},
        "ref_type": ref_type,
        "ref_id": ref_id,
        "created_at": now,
        "sent_at": now if status == NotificationStatus.SENT else None,
        "read_at": None,
    }
    await db.notifications.insert_one(notif)


async def _send_push(
    user_id: str,
    title: str,
    body: str,
    ref_type: Optional[str] = None,
    ref_id: Optional[str] = None,
    category: Optional[str] = None,
):
    user = await db.users.find_one(
        {"user_id": user_id},
        {"fcm_token": 1, "notification_prefs": 1},
    )
    fcm_token = user.get("fcm_token") if user else None
    push_enabled = ((user or {}).get("notification_prefs") or {}).get("push", True)

    if not fcm_token or not push_enabled or not _notification_category_enabled(user, category):
        return

    _ensure_firebase()
    if not _firebase_initialized:
        return

    try:
        import firebase_admin.messaging as _messaging

        message = _messaging.Message(
            notification=_messaging.Notification(title=title, body=body),
            data={"ref_type": ref_type or "", "ref_id": ref_id or ""},
            token=fcm_token,
        )
        _messaging.send(message)
        logger.info("Push FCM envoyé à %s", user_id)
    except Exception as e:
        logger.warning("Échec envoi Push FCM à %s: %s", user_id, e)


async def _send_sms(phone: str, body: str):
    """Envoi SMS via Twilio (best-effort, ne lève pas d'exception)."""
    try:
        if not settings.TWILIO_ACCOUNT_SID or not settings.TWILIO_SMS_NUMBER:
            return
        from twilio.rest import Client
        client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
        client.messages.create(body=body, from_=settings.TWILIO_SMS_NUMBER, to=phone)
    except Exception as e:
        logger.warning(f"SMS non envoyé à {phone} : {e}")


async def _whatsapp_post(payload: dict, phone: str) -> bool:
    if not settings.WHATSAPP_PHONE_NUMBER_ID or not settings.WHATSAPP_ACCESS_TOKEN:
        logger.debug("WhatsApp Cloud API non configuré, message ignoré")
        return False
    import httpx
    url = f"https://graph.facebook.com/{settings.WHATSAPP_API_VERSION}/{settings.WHATSAPP_PHONE_NUMBER_ID}/messages"
    headers = {
        "Authorization": f"Bearer {settings.WHATSAPP_ACCESS_TOKEN}",
        "Content-Type": "application/json",
    }
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(url, json=payload, headers=headers, timeout=10)
            if resp.status_code == 200:
                logger.info("WhatsApp envoyé à %s via Cloud API", phone)
                return True
            logger.warning("WhatsApp Cloud API erreur %s: %s", resp.status_code, resp.text)
            return False
    except Exception as e:
        logger.warning("WhatsApp non envoyé à %s : %s", phone, e)
        return False


async def _send_whatsapp_template(
    phone: str,
    template_name: str,
    variables: list[str],
    lang_code: str = "fr",
) -> bool:
    """Envoi WhatsApp via template approuvé (notification proactive).

    Seule méthode fiable pour pousser un message en dehors de la fenêtre de
    24 h (règle Meta). Les variables doivent être dans l'ordre {{1}}, {{2}}...
    """
    to_number = phone.lstrip("+")
    payload = {
        "messaging_product": "whatsapp",
        "to": to_number,
        "type": "template",
        "template": {
            "name": template_name,
            "language": {"code": lang_code},
            "components": [
                {
                    "type": "body",
                    "parameters": [{"type": "text", "text": str(v)} for v in variables],
                }
            ],
        },
    }
    return await _whatsapp_post(payload, phone)


async def _send_whatsapp(phone: str, body: str):
    """Envoi WhatsApp texte libre (fenêtre 24 h uniquement, best-effort)."""
    to_number = phone.lstrip("+")
    payload = {
        "messaging_product": "whatsapp",
        "to": to_number,
        "type": "text",
        "text": {"body": body},
    }
    await _whatsapp_post(payload, phone)


async def _send_sms_or_whatsapp(phone: str, body: str):
    await _send_whatsapp(phone, body)
    await _send_sms(phone, body)

async def notify_delivery_code(
    phone: str,
    recipient_name: str,
    tracking_code: str,
    delivery_code: str,
    is_relay_pickup: bool = False,
    payment_url: Optional[str] = None,
) -> None:
    """Envoie le code de réception au destinataire par WhatsApp/SMS."""
    if is_relay_pickup:
        instruction = "Présentez ce code à l'agent du point relais pour retirer votre colis."
    else:
        instruction = "Donnez ce code au livreur pour valider la remise."
    msg = (
        f"Bonjour {recipient_name},\n"
        f"Un colis vous est destiné (réf. {tracking_code}).\n"
        f"Votre code de réception : *{delivery_code}*\n"
    )
    if payment_url:
        msg += f"Paiement requis ({payment_url})\n"
    msg += f"{instruction} Ne le partagez pas."
    try:
        await _send_sms_or_whatsapp(phone, msg)
    except Exception as e:
        logger.warning("Impossible d'envoyer le code réception: %s", e)


async def notify_approaching_driver(parcel: dict):
    """Envoie une notification push au client quand le livreur est proche."""
    tracking_code = parcel.get("tracking_code", "")
    parcel_id = parcel.get("parcel_id")
    
    # 1. Notifier l'expéditeur
    sender_id = parcel.get("sender_user_id")
    if sender_id:
        await _store_and_send(
            user_id=sender_id,
            title="Livreur à proximité",
            body=f"Votre livreur approche avec votre colis {tracking_code} ! Préparez votre code de réception.",
            ref_type="parcel",
            ref_id=parcel_id,
            category="parcel_updates",
        )

    # 2. Notifier le destinataire s'il est un utilisateur enregistré
    recipient_phone = parcel.get("recipient_phone")
    if recipient_phone:
        # Chercher l'utilisateur par téléphone (format normalisé)
        user = await db.users.find_one({"phone": recipient_phone})
        if user:
            await _store_and_send(
                user_id=user["user_id"],
                title="Livreur à proximité",
                body=f"Votre colis {tracking_code} arrive ! Votre livreur est à moins de 500m.",
                ref_type="parcel",
                ref_id=parcel_id,
                category="parcel_updates",
            )


async def notify_new_mission_ping(user_id: str, mission: dict):
    """Notifie un livreur qu'une mission lui est exclusivement proposée (ping cascade)."""
    tracking_code = mission.get("tracking_code", "N/A")
    await _store_and_send(
        user_id=user_id,
        title="Nouvelle Mission Disponible (Exclusivité 30s)",
        body=f"Une mission pour le colis {tracking_code} vous est proposée. Répondez vite !",
        ref_type="mission",
        ref_id=mission.get("mission_id"),
    )


async def send_location_confirmation_prompt(
    *,
    title: str,
    body: str,
    user_id: Optional[str] = None,
    phone: Optional[str] = None,
    ref_type: Optional[str] = None,
    ref_id: Optional[str] = None,
    escalate_external: bool = False,
    whatsapp_template: Optional[str] = None,
    whatsapp_variables: Optional[list[str]] = None,
):
    """Relance de confirmation GPS avec escalade progressive."""
    if user_id:
        await _store_and_send(
            user_id=user_id,
            title=title,
            body=body,
            ref_type=ref_type,
            ref_id=ref_id,
            whatsapp_template=whatsapp_template,
            whatsapp_variables=whatsapp_variables,
        )
        if escalate_external and phone:
            if whatsapp_template:
                await _send_whatsapp_template(phone, whatsapp_template, whatsapp_variables or [])
            await _send_sms(phone, body)
        return

    if phone:
        if whatsapp_template:
            await _send_whatsapp_template(phone, whatsapp_template, whatsapp_variables or [])
        else:
            await _send_whatsapp(phone, body)
        await _send_sms(phone, body)


async def notify_relay_agent_parcel_arrived(relay_id: str, parcel: dict):
    """Notifie l'agent relais qu'un colis est arrivé dans son relais."""
    tracking_code = parcel.get("tracking_code", "")
    parcel_id = parcel.get("parcel_id")

    # Trouver l'agent relais lié à ce relay_point
    agent = await db.users.find_one(
        {"relay_point_id": relay_id, "role": "relay_agent"},
        {"user_id": 1},
    )
    if not agent:
        return

    await _store_and_send(
        user_id=agent["user_id"],
        title="Nouveau colis arrivé",
        body=f"Le colis {tracking_code} est arrivé dans votre relais. Veuillez le réceptionner.",
        ref_type="parcel",
        ref_id=parcel_id,
    )


async def notify_payout_result(user_id: str, amount: float, approved: bool):
    """Notifie un driver/relay du résultat de sa demande de retrait."""
    if approved:
        title = "Retrait approuvé"
        body = f"Votre demande de retrait de {int(amount)} XOF a été approuvée. Le virement est en cours."
    else:
        title = "Retrait refusé"
        body = f"Votre demande de retrait de {int(amount)} XOF a été refusée. Le montant a été recrédité sur votre cagnotte."

    await _store_and_send(
        user_id=user_id,
        title=title,
        body=body,
        ref_type="payout",
    )


async def notify_parcel_expired(parcel: dict):
    """Notifie l'expéditeur et le destinataire qu'un colis a expiré."""
    tracking_code = parcel.get("tracking_code", "")
    parcel_id = parcel.get("parcel_id")
    body = f"Le colis {tracking_code} n'a pas été retiré dans les délais et a expiré."

    sender_id = parcel.get("sender_user_id")
    if sender_id:
        await _store_and_send(
            user_id=sender_id,
            title="Colis expiré",
            body=body,
            ref_type="parcel",
            ref_id=parcel_id,
            category="parcel_updates",
        )

    recipient_phone = parcel.get("recipient_phone")
    recipient_user_id = parcel.get("recipient_user_id")
    if not recipient_user_id and recipient_phone:
        user = await db.users.find_one({"phone": recipient_phone}, {"user_id": 1})
        if user:
            recipient_user_id = user["user_id"]

    if recipient_user_id:
        await _store_and_send(
            user_id=recipient_user_id,
            title="Colis expiré",
            body=body,
            ref_type="parcel",
            ref_id=parcel_id,
            category="parcel_updates",
        )
    elif recipient_phone:
        await _send_sms_or_whatsapp(recipient_phone, body)


async def notify_location_confirmation_request(parcel: dict, actor: str, confirm_url: str, escalate_external: bool = False):
    """Demande ou relance de confirmation GPS pour expéditeur ou destinataire."""
    tracking_code = parcel.get("tracking_code", "")
    parcel_id = parcel.get("parcel_id")
    sender_full = parcel.get("sender_name") or "Denkma"

    if actor == "sender":
        user_id = parcel.get("sender_user_id")
        phone = parcel.get("sender_phone") or parcel.get("sender_phone_e164")
        target_name = _first_name(sender_full)
        title = "Confirmez le point de collecte"
        body = (
            f"Confirmez la position de collecte pour le colis {tracking_code}. "
            f"Ouvrez le lien: {confirm_url}"
        )
    else:
        user_id = parcel.get("recipient_user_id")
        phone = parcel.get("recipient_phone")
        target_name = _first_name(parcel.get("recipient_name"))
        title = "Confirmez votre position de livraison"
        body = (
            f"Confirmez la position de livraison pour le colis {tracking_code}. "
            f"Ouvrez le lien: {confirm_url}"
        )

    template_vars = [target_name, sender_full, tracking_code, confirm_url]

    await send_location_confirmation_prompt(
        title=title,
        body=body,
        user_id=user_id,
        phone=phone,
        whatsapp_template="gps_confirmation",
        whatsapp_variables=template_vars,
        ref_type="parcel",
        ref_id=parcel_id,
        escalate_external=escalate_external,
    )
