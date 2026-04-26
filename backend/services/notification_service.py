"""
Service notification : envoi de notifications push, SMS, WhatsApp aux utilisateurs.
"""
import logging
import re
from datetime import datetime, timezone
from urllib.parse import urlencode
import uuid
from typing import Optional

from config import settings
from core.utils import normalize_phone
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
    ParcelStatus.DELIVERY_FAILED:         "La livraison n'a pas pu être finalisée. Denkma recherche la meilleure solution.",
    ParcelStatus.REDIRECTED_TO_RELAY:     "Votre colis est redirigé vers un relais. Code de retrait : {relay_pin}",
    ParcelStatus.INCIDENT_REPORTED:       "Un incident est en cours de traitement sur votre colis. Denkma vous tiendra informé.",
    ParcelStatus.CANCELLED:               "Votre colis a été annulé.",
    ParcelStatus.EXPIRED:                 "Le délai de retrait de votre colis est expiré.",
    ParcelStatus.RETURNED:                "Votre colis a été retourné à l'expéditeur.",
    ParcelStatus.SUSPENDED:               "Votre colis a été suspendu par l'administration. Vous serez prévenu lorsque son traitement reprendra.",
}


SENDER_STATUS_MESSAGES = {
    ParcelStatus.CREATED:                 "Votre colis {tracking_code} a été créé.",
    ParcelStatus.DROPPED_AT_ORIGIN_RELAY: "Votre colis {tracking_code} a été déposé au point relais de départ.",
    ParcelStatus.IN_TRANSIT:              "Votre colis {tracking_code} est en transit.",
    ParcelStatus.AT_DESTINATION_RELAY:    "Votre colis {tracking_code} est arrivé au relais proche du destinataire.",
    ParcelStatus.AVAILABLE_AT_RELAY:      "Votre colis {tracking_code} est disponible au relais pour le destinataire.",
    ParcelStatus.OUT_FOR_DELIVERY:        "Le livreur est en route pour livrer votre colis {tracking_code}.",
    ParcelStatus.DELIVERED:               "Votre colis {tracking_code} a été livré avec succès.",
    ParcelStatus.DELIVERY_FAILED:         "La livraison du colis {tracking_code} n'a pas pu être finalisée. Denkma recherche la meilleure solution.",
    ParcelStatus.REDIRECTED_TO_RELAY:     "Votre colis {tracking_code} a été redirigé vers un relais proche du destinataire.",
    ParcelStatus.INCIDENT_REPORTED:       "Un incident est en cours de traitement sur votre colis {tracking_code}.",
    ParcelStatus.CANCELLED:               "Votre colis {tracking_code} a été annulé.",
    ParcelStatus.EXPIRED:                 "Le délai de retrait du colis {tracking_code} est expiré.",
    ParcelStatus.RETURNED:                "Votre colis {tracking_code} vous a été retourné.",
    ParcelStatus.SUSPENDED:               "Votre colis {tracking_code} a été suspendu par l'administration. Nous vous tiendrons informé.",
}

# Statuts pour lesquels le code (PIN/retrait/livraison) doit être inclus dans
# le message du destinataire. Pour tout autre statut (annulation, expiration,
# retour, suspension, etc.), le code n'est plus pertinent et serait trompeur.
_RECIPIENT_CODE_STATUSES = {
    ParcelStatus.CREATED,
    ParcelStatus.AVAILABLE_AT_RELAY,
    ParcelStatus.OUT_FOR_DELIVERY,
    ParcelStatus.REDIRECTED_TO_RELAY,
}

# Mapping ParcelStatus -> template WhatsApp approuvé (notifs proactives).
# Les templates qui ne figurent pas ici retombent sur le texte libre
# (qui n'est livré que si l'user a écrit dans les 24 h).
STATUS_TEMPLATES = {
    ParcelStatus.CREATED:          settings.WHATSAPP_TEMPLATE_PARCEL_CREATED,
    ParcelStatus.OUT_FOR_DELIVERY: settings.WHATSAPP_TEMPLATE_PARCEL_ASSIGNED,
    ParcelStatus.IN_TRANSIT:       settings.WHATSAPP_TEMPLATE_PARCEL_ASSIGNED,
    ParcelStatus.DELIVERED:        settings.WHATSAPP_TEMPLATE_PARCEL_DELIVERED,
}

if settings.WHATSAPP_TEMPLATE_RELAY_READY:
    STATUS_TEMPLATES[ParcelStatus.AVAILABLE_AT_RELAY] = settings.WHATSAPP_TEMPLATE_RELAY_READY
if settings.WHATSAPP_TEMPLATE_RELAY_REDIRECTED:
    STATUS_TEMPLATES[ParcelStatus.REDIRECTED_TO_RELAY] = settings.WHATSAPP_TEMPLATE_RELAY_REDIRECTED

DELIVERY_CODE_TEMPLATE = settings.WHATSAPP_TEMPLATE_DELIVERY_CODE
RECIPIENT_CREATED_TEMPLATE = settings.WHATSAPP_TEMPLATE_RECIPIENT_CREATED
RECIPIENT_CREATED_RELAY_TEMPLATE = settings.WHATSAPP_TEMPLATE_RECIPIENT_CREATED_RELAY
RELAY_CHOICE_TEMPLATE = settings.WHATSAPP_TEMPLATE_RELAY_CHOICE_REQUEST


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
    if not prefs.get("whatsapp", True):
        return False

    has_app = bool(user_doc.get("fcm_token"))
    push_enabled = prefs.get("push", True)

    # Push prioritaire : si l'app peut recevoir la notif, on ne double pas avec WhatsApp.
    # WhatsApp reste le canal de secours pour les users sans app ou avec push désactivé.
    return not (has_app and push_enabled)


def _first_name(full_name: Optional[str], fallback: str = "Client") -> str:
    if not full_name:
        return fallback
    return full_name.strip().split(" ")[0] or fallback


def _tracking_url(tracking_code: str) -> str:
    return f"{settings.BASE_URL.rstrip('/')}/api/tracking/view/{tracking_code}"


def _app_url(parcel: dict) -> str:
    params = {
        "tracking": parcel.get("tracking_code") or "",
        "phone": parcel.get("recipient_phone") or "",
    }
    return f"{settings.PUBLIC_SITE_URL.rstrip('/')}/app?{urlencode(params)}"


def _whatsapp_to(phone: str | None) -> str:
    return re.sub(r"\D", "", normalize_phone(phone))


def _display_phone(phone: str | None) -> str:
    return (phone or "").strip() or "non renseigné"


def _recipient_access_code(parcel: dict) -> tuple[str | None, str | None]:
    mode = parcel.get("delivery_mode") or ""
    if mode.endswith("_to_relay"):
        return parcel.get("relay_pin"), "Code de retrait"
    if mode.endswith("_to_home"):
        return parcel.get("delivery_code"), "Code de livraison"
    return None, None


def _is_relay_delivery(parcel: dict) -> bool:
    mode = parcel.get("delivery_mode") or ""
    return mode.endswith("_to_relay") or bool(parcel.get("redirect_relay_id"))


def _body_with_recipient_code(body: str, parcel: dict, status: ParcelStatus) -> str:
    if status not in _RECIPIENT_CODE_STATUSES:
        return body
    code, label = _recipient_access_code(parcel)
    if not code or not label:
        return body
    if str(code) in body:
        return body
    return f"{body} {label} : {code}."


def _status_body(messages: dict, status: ParcelStatus, tracking_code: str, relay_pin: str) -> str:
    template = messages.get(status, f"Statut mis à jour : {status.value}")
    return template.format(tracking_code=tracking_code, relay_pin=relay_pin)


def _phone_lookup_values(phone: str | None) -> list[str]:
    if not phone:
        return []
    normalized = normalize_phone(phone)
    digits = re.sub(r"\D", "", normalized or phone)
    values = {phone, normalized}
    if digits:
        values.add(digits)
        values.add(f"+{digits}")
    return [value for value in values if value]


async def _find_user_by_phone(phone: str | None) -> dict | None:
    values = _phone_lookup_values(phone)
    if not values:
        return None
    return await db.users.find_one({"phone": {"$in": values}}, {"user_id": 1})


async def _resolve_recipient_relay(parcel: dict) -> dict | None:
    """Récupère le point relais pertinent pour le destinataire :
    redirect_relay_id si présent (livraison redirigée), sinon destination_relay_id."""
    relay_id = parcel.get("redirect_relay_id") or parcel.get("destination_relay_id")
    if not relay_id:
        return None
    return await db.relay_points.find_one({"relay_id": relay_id}, {"_id": 0})


def _relay_label_parts(relay: dict | None) -> tuple[str, str]:
    """Renvoie (nom, adresse) du relais pour les templates v4. Fallback safe."""
    if not relay:
        return "Point relais Denkma", "Adresse à confirmer"
    name = (relay.get("name") or "Point relais Denkma").strip()
    addr = relay.get("address") or {}
    label = (addr.get("label") or "").strip()
    city = (addr.get("city") or "").strip()
    if label and city and city.lower() not in label.lower():
        full_addr = f"{label}, {city}"
    else:
        full_addr = label or city or "Adresse à confirmer"
    return name, full_addr


def _is_v4_template(template_name: Optional[str]) -> bool:
    return bool(template_name) and template_name.endswith("_v4")


def _created_recipient_template_payload(
    parcel: dict,
    tracking_code: str,
    tracking_url: str,
    app_url: str,
    relay: dict | None = None,
) -> tuple[list[str], list[str]]:
    parcel_code, _ = _recipient_access_code(parcel)
    template = RECIPIENT_CREATED_RELAY_TEMPLATE if _is_relay_delivery(parcel) else None
    if template and _is_v4_template(template):
        # parcel_created_recipient_relay_v4 : 7 vars (avec nom + adresse relais)
        relay_name, relay_addr = _relay_label_parts(relay)
        return [
            _first_name(parcel.get("recipient_name")),
            parcel.get("sender_name") or "l'expéditeur",
            relay_name,
            relay_addr,
            tracking_code,
            str(parcel_code or "à confirmer"),
            tracking_url,
        ], []
    if template:
        # v3 : 5 vars
        return [
            _first_name(parcel.get("recipient_name")),
            parcel.get("sender_name") or "l'expéditeur",
            tracking_code,
            str(parcel_code or "à confirmer"),
            tracking_url,
        ], []

    body_variables = [
        _first_name(parcel.get("recipient_name")),
        parcel.get("sender_name") or "l'expéditeur",
        tracking_code,
        _display_phone(parcel.get("sender_phone")),
        str(parcel_code or "à confirmer"),
    ]
    button_variables = [tracking_url, app_url]
    return body_variables, button_variables


def _recipient_created_template(parcel: dict) -> str:
    if _is_relay_delivery(parcel) and RECIPIENT_CREATED_RELAY_TEMPLATE:
        return RECIPIENT_CREATED_RELAY_TEMPLATE
    return RECIPIENT_CREATED_TEMPLATE


def _relay_status_template_vars(
    template_name: Optional[str],
    parcel: dict,
    first_name: str,
    tracking_code: str,
    tracking_url: str,
    relay: dict | None = None,
) -> list[str]:
    relay_templates = {
        value
        for value in (
            settings.WHATSAPP_TEMPLATE_RELAY_READY,
            settings.WHATSAPP_TEMPLATE_RELAY_REDIRECTED,
        )
        if value
    }
    if not template_name or template_name not in relay_templates:
        return _template_vars(template_name, first_name, tracking_code, tracking_url)
    code, _ = _recipient_access_code(parcel)
    if _is_v4_template(template_name):
        # parcel_relay_ready_v4 / parcel_relay_redirected_v4 : 6 vars
        relay_name, relay_addr = _relay_label_parts(relay)
        return [first_name, tracking_code, relay_name, relay_addr, str(code or "à confirmer"), tracking_url]
    # v3 : 4 vars
    return [first_name, tracking_code, str(code or "à confirmer"), tracking_url]


async def _send_recipient_access_code(parcel: dict, recipient_phone: str | None) -> None:
    if not settings.WHATSAPP_SEND_SEPARATE_RECIPIENT_CODE or not recipient_phone:
        return
    code, _ = _recipient_access_code(parcel)
    if not code:
        return
    await _send_whatsapp_auth_code(recipient_phone, str(code))


# ── Régles métier : qui doit recevoir une notif pour quel statut ─────────────
#
# Principe : un acteur ne reçoit une notif QUE sur les évènements qui le
# concernent, en tenant compte du mode de livraison. Les statuts opérationnels
# internes (transit, transfert relais) ne génèrent pas de bruit côté client.

# Sender ne reçoit jamais ces statuts (purement côté recipient)
_SENDER_SKIP_STATUSES = {
    ParcelStatus.AT_DESTINATION_RELAY,
    ParcelStatus.AVAILABLE_AT_RELAY,
}

# Recipient ne reçoit jamais ces statuts (purement opérationnels)
_RECIPIENT_SKIP_STATUSES = {
    ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
    ParcelStatus.IN_TRANSIT,
    ParcelStatus.AT_DESTINATION_RELAY,
}

# Statuts qui impactent directement la mission active du livreur : on le
# prévient explicitement (pause, clôture forcée). Les autres transitions sont
# déjà visibles dans son flux de mission ou l'app le re-synchronisera.
_DRIVER_NOTIFY_STATUSES = {
    ParcelStatus.SUSPENDED,
    ParcelStatus.CANCELLED,
    ParcelStatus.RETURNED,
}

_DRIVER_STATUS_MESSAGES = {
    ParcelStatus.SUSPENDED: (
        "Mission suspendue",
        "La mission pour le colis {tracking_code} est suspendue par l'administration. Aucune action n'est possible pour le moment.",
    ),
    ParcelStatus.CANCELLED: (
        "Mission annulée",
        "La mission pour le colis {tracking_code} a été annulée. Vous pouvez la retirer de votre liste.",
    ),
    ParcelStatus.RETURNED: (
        "Mission clôturée",
        "Le colis {tracking_code} est marqué comme retourné à l'expéditeur. La mission est clôturée.",
    ),
}


def _should_notify_sender(parcel: dict, status: ParcelStatus) -> bool:
    if status in _SENDER_SKIP_STATUSES:
        return False
    mode = parcel.get("delivery_mode", "") or ""
    # DROPPED_AT_ORIGIN_RELAY n'a de sens que pour les modes relay_to_*
    if status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY:
        return mode.startswith("relay_")
    # OUT_FOR_DELIVERY côté sender = livreur en route pour collecter chez lui,
    # donc seulement pour les modes home_to_*
    if status == ParcelStatus.OUT_FOR_DELIVERY:
        return mode.startswith("home_")
    return True


def _should_notify_recipient(parcel: dict, status: ParcelStatus) -> bool:
    if status in _RECIPIENT_SKIP_STATUSES:
        return False
    mode = parcel.get("delivery_mode", "") or ""
    # OUT_FOR_DELIVERY côté recipient = livreur en route chez lui, donc
    # uniquement pour les modes *_to_home
    if status == ParcelStatus.OUT_FOR_DELIVERY:
        return mode.endswith("_to_home")
    return True


async def _notify_driver_parcel_change(parcel: dict, new_status: ParcelStatus) -> None:
    """Notifie le livreur affecté quand le colis change d'état d'une manière
    qui impacte sa mission (suspension, annulation, retour)."""
    if new_status not in _DRIVER_NOTIFY_STATUSES:
        return
    driver_id = parcel.get("assigned_driver_id")
    if not driver_id:
        return
    title, body_template = _DRIVER_STATUS_MESSAGES[new_status]
    tracking_code = parcel.get("tracking_code") or parcel.get("parcel_id") or ""
    body = body_template.format(tracking_code=tracking_code)
    await _store_and_send(
        user_id=driver_id,
        title=title,
        body=body,
        ref_type="parcel",
        ref_id=parcel.get("parcel_id"),
        category="parcel_updates",
        skip_whatsapp=True,
    )


async def notify_driver_mission_resumed(parcel: dict, new_status: ParcelStatus) -> None:
    """Notifie le livreur quand la suspension est levée et qu'il peut reprendre."""
    driver_id = parcel.get("assigned_driver_id")
    if not driver_id:
        return
    tracking_code = parcel.get("tracking_code") or parcel.get("parcel_id") or ""
    body = (
        f"La suspension du colis {tracking_code} est levée. "
        "Vous pouvez reprendre la mission depuis votre app."
    )
    await _store_and_send(
        user_id=driver_id,
        title="Mission reprise",
        body=body,
        ref_type="parcel",
        ref_id=parcel.get("parcel_id"),
        category="parcel_updates",
        skip_whatsapp=True,
    )


async def notify_parcel_status_change(parcel: dict, new_status: ParcelStatus):
    """Notifie l'expéditeur, le destinataire et le livreur affecté du changement de statut."""
    tracking_code = parcel.get("tracking_code", "")
    relay_pin = parcel.get("relay_pin", "—")
    recipient_body_base = _status_body(STATUS_MESSAGES, new_status, tracking_code, relay_pin)
    sender_body = _status_body(SENDER_STATUS_MESSAGES, new_status, tracking_code, relay_pin)

    template_name = STATUS_TEMPLATES.get(new_status)
    tracking_url = _tracking_url(tracking_code)
    app_url = _app_url(parcel)

    notify_sender = _should_notify_sender(parcel, new_status)
    notify_recipient = _should_notify_recipient(parcel, new_status)

    # Notifier le livreur si la transition impacte directement sa mission
    # (suspension, annulation, retour). Ne dépend ni du sender ni du recipient.
    await _notify_driver_parcel_change(parcel, new_status)

    # Notifier expéditeur — règle : un seul WhatsApp à la création (template
    # parcel_created avec lien de tracking). Tous les autres changements de
    # statut pertinents restent en push + in-app uniquement.
    sender_id = parcel.get("sender_user_id")
    if sender_id and notify_sender:
        sender_first = _first_name(parcel.get("sender_name"))
        is_creation = (new_status == ParcelStatus.CREATED)
        sender_template = settings.WHATSAPP_TEMPLATE_PARCEL_CREATED if is_creation else None
        sender_template_vars = (
            _template_vars(sender_template, sender_first, tracking_code, tracking_url)
            if sender_template else []
        )
        await _store_and_send(
            user_id=sender_id,
            title="Mise à jour colis",
            body=sender_body,
            ref_type="parcel",
            ref_id=parcel.get("parcel_id"),
            category="parcel_updates",
            whatsapp_template=sender_template,
            whatsapp_variables=sender_template_vars,
            skip_whatsapp=not is_creation,
        )

    # Notifier destinataire
    if not notify_recipient:
        return

    recipient_phone = parcel.get("recipient_phone")
    recipient_user_id = parcel.get("recipient_user_id")
    if not recipient_user_id and recipient_phone:
        # Recherche tardive (si inscrit entre temps)
        user = await _find_user_by_phone(recipient_phone)
        if user:
            recipient_user_id = user["user_id"]

    recipient_first = _first_name(parcel.get("recipient_name"))
    recipient_body = _body_with_recipient_code(recipient_body_base, parcel, new_status)
    recipient_template = template_name
    # On résout le relais une fois pour éviter les requêtes en double
    recipient_relay = await _resolve_recipient_relay(parcel) if _is_relay_delivery(parcel) else None
    template_vars_recipient = _relay_status_template_vars(
        template_name,
        parcel,
        recipient_first,
        tracking_code,
        tracking_url,
        relay=recipient_relay,
    )
    recipient_button_vars: list[str] = []
    if new_status == ParcelStatus.CREATED:
        recipient_template = _recipient_created_template(parcel)
        template_vars_recipient, recipient_button_vars = _created_recipient_template_payload(
            parcel,
            tracking_code,
            tracking_url,
            app_url,
            relay=recipient_relay,
        )

    if recipient_user_id:
        # Pour CREATED, le template recipient_created_* contient déjà toutes les
        # infos (nom expéditeur, tracking, code, lien de confirmation). On le
        # passe directement à _store_and_send pour ne pas envoyer aussi le
        # body en texte libre (qui faisait doublon WhatsApp).
        await _store_and_send(
            user_id=recipient_user_id,
            title="Mise à jour colis",
            body=recipient_body,
            ref_type="parcel",
            ref_id=parcel.get("parcel_id"),
            category="parcel_updates",
            whatsapp_template=recipient_template,
            whatsapp_variables=template_vars_recipient,
            whatsapp_button_variables=recipient_button_vars,
        )
        # Le code de retrait/livraison est déjà inclus dans le template principal
        # pour CREATED, AVAILABLE_AT_RELAY et REDIRECTED_TO_RELAY. On envoie un
        # message séparé uniquement pour OUT_FOR_DELIVERY (template parcel_assigned
        # qui n'a pas de variable code).
        if new_status == ParcelStatus.OUT_FOR_DELIVERY:
            await _send_recipient_access_code(parcel, recipient_phone)
    elif recipient_phone:
        if recipient_template:
            sent = await _send_whatsapp_template(
                recipient_phone,
                recipient_template,
                template_vars_recipient,
                button_variables=recipient_button_vars,
            )
            if not sent and recipient_template != template_name and template_name:
                await _send_whatsapp_template(
                    recipient_phone,
                    template_name,
                    _relay_status_template_vars(
                        template_name,
                        parcel,
                        recipient_first,
                        tracking_code,
                        tracking_url,
                        relay=recipient_relay,
                    ),
                )
        else:
            await _send_whatsapp(recipient_phone, recipient_body)
        # Le code de retrait/livraison est déjà inclus dans le template principal
        # pour CREATED, AVAILABLE_AT_RELAY et REDIRECTED_TO_RELAY. On envoie un
        # message séparé uniquement pour OUT_FOR_DELIVERY (template parcel_assigned
        # qui n'a pas de variable code).
        if new_status == ParcelStatus.OUT_FOR_DELIVERY:
            await _send_recipient_access_code(parcel, recipient_phone)


def _template_vars(
    template_name: Optional[str],
    first_name: str,
    tracking_code: str,
    tracking_url: str,
) -> list[str]:
    if template_name in {
        settings.WHATSAPP_TEMPLATE_PARCEL_CREATED,
        settings.WHATSAPP_TEMPLATE_PARCEL_ASSIGNED,
    }:
        return [first_name, tracking_code, tracking_url]
    if template_name == settings.WHATSAPP_TEMPLATE_PARCEL_DELIVERED:
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
        skip_whatsapp=True,
    )


async def notify_sender_driver_assigned(parcel: dict, driver: dict):
    """Notifie l'expéditeur quand un livreur accepte la mission."""
    sender_id = parcel.get("sender_user_id")
    if not sender_id:
        return

    tracking_code = parcel.get("tracking_code", "")
    driver_name = (driver.get("name") or "Le livreur").strip()
    tracking_url = _tracking_url(tracking_code)
    sender_first = _first_name(parcel.get("sender_name"))
    body = (
        f"{driver_name} a accepté la mission pour le colis {tracking_code}. "
        "Préparez le colis et gardez le code de collecte à portée de main."
    )
    await _store_and_send(
        user_id=sender_id,
        title="Livreur assigné",
        body=body,
        ref_type="parcel",
        ref_id=parcel.get("parcel_id"),
        category="parcel_updates",
        skip_whatsapp=True,
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
    whatsapp_button_variables: Optional[list[str]] = None,
    skip_whatsapp: bool = False,
):
    """Stocke la notification en base et tente l'envoi.

    skip_whatsapp: si True, n'envoie ni template ni texte libre WhatsApp.
    Utile quand on veut limiter une notif à push + in-app seulement.
    """
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

    if not skip_whatsapp and _should_send_whatsapp_tracking(user, category):
        phone = (user or {}).get("phone")
        if phone:
            if whatsapp_template:
                await _send_whatsapp_template(
                    phone,
                    whatsapp_template,
                    whatsapp_variables or [],
                    button_variables=whatsapp_button_variables,
                )
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


async def _whatsapp_post(payload: dict, phone: str) -> bool:
    now = datetime.now(timezone.utc)
    to_number = payload.get("to") or _whatsapp_to(phone)
    template = (
        (payload.get("template") or {}).get("name")
        if isinstance(payload.get("template"), dict)
        else None
    )
    log_doc = {
        "attempt_id": f"wa_{uuid.uuid4().hex[:16]}",
        "phone_input": phone,
        "to": to_number,
        "message_type": payload.get("type"),
        "template": template,
        "status": "pending",
        "status_code": None,
        "meta_message_id": None,
        "meta_error": None,
        "created_at": now,
        "updated_at": now,
    }
    if not settings.WHATSAPP_PHONE_NUMBER_ID or not settings.WHATSAPP_ACCESS_TOKEN:
        logger.debug("WhatsApp Cloud API non configuré, message ignoré")
        log_doc.update({
            "status": "skipped",
            "meta_error": "missing_whatsapp_configuration",
            "updated_at": datetime.now(timezone.utc),
        })
        await db.whatsapp_delivery_logs.insert_one(log_doc)
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
            log_doc["status_code"] = resp.status_code
            if resp.status_code == 200:
                try:
                    data = resp.json()
                    messages = data.get("messages") or []
                    if messages:
                        log_doc["meta_message_id"] = messages[0].get("id")
                except Exception:
                    pass
                log_doc.update({"status": "sent", "updated_at": datetime.now(timezone.utc)})
                await db.whatsapp_delivery_logs.insert_one(log_doc)
                logger.info("WhatsApp envoyé à %s via Cloud API", phone)
                return True
            try:
                log_doc["meta_error"] = resp.json()
            except Exception:
                log_doc["meta_error"] = resp.text[:2000]
            log_doc.update({"status": "failed", "updated_at": datetime.now(timezone.utc)})
            await db.whatsapp_delivery_logs.insert_one(log_doc)
            logger.warning("WhatsApp Cloud API erreur %s: %s", resp.status_code, resp.text)
            return False
    except Exception as e:
        log_doc.update({
            "status": "error",
            "meta_error": str(e),
            "updated_at": datetime.now(timezone.utc),
        })
        await db.whatsapp_delivery_logs.insert_one(log_doc)
        logger.warning("WhatsApp non envoyé à %s : %s", phone, e)
        return False


async def _send_whatsapp_template(
    phone: str,
    template_name: str,
    variables: list[str],
    button_variables: Optional[list[str]] = None,
    lang_code: str = "fr",
) -> bool:
    """Envoi WhatsApp via template approuvé (notification proactive).

    Seule méthode fiable pour pousser un message en dehors de la fenêtre de
    24 h (règle Meta). Les variables doivent être dans l'ordre {{1}}, {{2}}...
    """
    to_number = _whatsapp_to(phone)
    if not to_number:
        logger.warning("WhatsApp template %s ignoré: numéro invalide", template_name)
        return False
    components = [
        {
            "type": "body",
            "parameters": [{"type": "text", "text": str(v)} for v in variables],
        }
    ]
    for index, value in enumerate(button_variables or []):
        components.append(
            {
                "type": "button",
                "sub_type": "url",
                "index": str(index),
                "parameters": [{"type": "text", "text": str(value)}],
            }
        )

    payload = {
        "messaging_product": "whatsapp",
        "to": to_number,
        "type": "template",
        "template": {
            "name": template_name,
            "language": {"code": lang_code},
            "components": components,
        },
    }
    return await _whatsapp_post(payload, phone)


async def _send_whatsapp_auth_code(phone: str, code: str, lang_code: str = "fr") -> bool:
    """Envoie un code WhatsApp via template d'authentification approuvé."""
    to_number = _whatsapp_to(phone)
    if not to_number:
        logger.warning("WhatsApp code ignoré: numéro invalide")
        return False

    payload = {
        "messaging_product": "whatsapp",
        "to": to_number,
        "type": "template",
        "template": {
            "name": DELIVERY_CODE_TEMPLATE,
            "language": {"code": lang_code},
            "components": [
                {
                    "type": "body",
                    "parameters": [{"type": "text", "text": str(code)}],
                },
                {
                    "type": "button",
                    "sub_type": "url",
                    "index": "0",
                    "parameters": [{"type": "text", "text": str(code)}],
                },
            ],
        },
    }
    return await _whatsapp_post(payload, phone)


async def _send_whatsapp(phone: str, body: str):
    """Envoi WhatsApp texte libre (fenêtre 24 h uniquement, best-effort)."""
    to_number = _whatsapp_to(phone)
    if not to_number:
        logger.warning("WhatsApp texte ignoré: numéro invalide")
        return
    payload = {
        "messaging_product": "whatsapp",
        "to": to_number,
        "type": "text",
        "text": {"body": body},
    }
    await _whatsapp_post(payload, phone)


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
        template_sent = await _send_whatsapp_auth_code(phone, delivery_code)
        if template_sent:
            return
        await _send_whatsapp(phone, msg)
    except Exception as e:
        logger.warning("Impossible d'envoyer le code réception: %s", e)


async def notify_approaching_driver(parcel: dict):
    """Notifie le destinataire quand le livreur approche du point de livraison."""
    tracking_code = parcel.get("tracking_code", "")
    parcel_id = parcel.get("parcel_id")

    recipient_phone = parcel.get("recipient_phone")
    if recipient_phone:
        user = await db.users.find_one({"phone": recipient_phone})
        if user:
            await _store_and_send(
                user_id=user["user_id"],
                title="Livreur à proximité",
                body=f"Votre colis {tracking_code} arrive. Préparez votre code de réception.",
                ref_type="parcel",
                ref_id=parcel_id,
                category="parcel_updates",
            )


async def notify_sender_parcel_collected(parcel: dict):
    """Notifie l'expéditeur lorsque le livreur a collecté le colis."""
    sender_id = parcel.get("sender_user_id")
    if not sender_id:
        return
    tracking_code = parcel.get("tracking_code", "")
    await _store_and_send(
        user_id=sender_id,
        title="Colis collecté",
        body=f"Le livreur a récupéré votre colis {tracking_code}. Il est maintenant en route.",
        ref_type="parcel",
        ref_id=parcel.get("parcel_id"),
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
    force_whatsapp: bool = False,
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
        if (force_whatsapp or escalate_external) and phone:
            if whatsapp_template:
                await _send_whatsapp_template(phone, whatsapp_template, whatsapp_variables or [])
            else:
                await _send_whatsapp(phone, body)
        return

    if phone:
        if whatsapp_template:
            await _send_whatsapp_template(phone, whatsapp_template, whatsapp_variables or [])
        else:
            await _send_whatsapp(phone, body)


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
        await _send_whatsapp(recipient_phone, body)


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
        whatsapp_template=settings.WHATSAPP_TEMPLATE_GPS_CONFIRMATION,
        whatsapp_variables=template_vars,
        ref_type="parcel",
        ref_id=parcel_id,
        escalate_external=escalate_external,
        force_whatsapp=True,
    )


async def notify_sender_recipient_position_pending(parcel: dict) -> None:
    """Informe l'expéditeur que le destinataire n'a pas encore validé sa position."""
    sender_id = parcel.get("sender_user_id")
    if not sender_id:
        return

    tracking_code = parcel.get("tracking_code", "")
    body = (
        f"Le destinataire n'a pas encore validé sa position pour le colis {tracking_code}. "
        "Merci de le contacter pour qu'il confirme sa position."
    )
    await _store_and_send(
        user_id=sender_id,
        title="Position du destinataire en attente",
        body=body,
        ref_type="parcel",
        ref_id=parcel.get("parcel_id"),
        category="parcel_updates",
        whatsapp_template=None,
        whatsapp_variables=[],
    )


async def notify_relay_choice_request(parcel: dict, confirm_url: str, escalate_external: bool = False):
    """Invite le destinataire à choisir ou modifier son point relais de retrait."""
    tracking_code = parcel.get("tracking_code", "")
    parcel_id = parcel.get("parcel_id")
    user_id = parcel.get("recipient_user_id")
    phone = parcel.get("recipient_phone")
    target_name = _first_name(parcel.get("recipient_name"))
    sender_full = parcel.get("sender_name") or "Denkma"
    title = "Choisissez votre point relais"
    body = (
        f"Choisissez ou modifiez le point relais de retrait du colis {tracking_code}. "
        f"Ouvrez le lien : {confirm_url}"
    )

    await send_location_confirmation_prompt(
        title=title,
        body=body,
        user_id=user_id,
        phone=phone,
        ref_type="parcel",
        ref_id=parcel_id,
        escalate_external=escalate_external,
        force_whatsapp=True,
        whatsapp_template=RELAY_CHOICE_TEMPLATE,
        whatsapp_variables=[target_name, sender_full, tracking_code, confirm_url] if RELAY_CHOICE_TEMPLATE else None,
    )
