"""
Service notification : envoi de notifications push, SMS, WhatsApp aux utilisateurs.
"""
import logging
import math
import re
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode
import uuid
from typing import Optional

from config import settings
from core.utils import normalize_phone
from database import db
from models.notification import NotificationChannel, NotificationStatus
from models.common import ParcelStatus
from models.delivery import ACTIVE_MISSION_STATUSES
from services.mission_trace import timestamp
from services.location_quality import location_is_live

logger = logging.getLogger(__name__)


def _mission_elapsed_label(assigned_at: object) -> str | None:
    if isinstance(assigned_at, str):
        try:
            assigned_at = datetime.fromisoformat(assigned_at.replace("Z", "+00:00"))
        except ValueError:
            return None
    if not isinstance(assigned_at, datetime):
        return None
    if assigned_at.tzinfo is None:
        assigned_at = assigned_at.replace(tzinfo=timezone.utc)
    total_minutes = max(
        0,
        int((datetime.now(timezone.utc) - assigned_at.astimezone(timezone.utc)).total_seconds() // 60),
    )
    hours, minutes = divmod(total_minutes, 60)
    return f"{hours} h {minutes:02d}" if hours else f"{minutes} min"

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
        elif settings.FIREBASE_CREDENTIALS_PATH and os.path.exists(settings.FIREBASE_CREDENTIALS_PATH):
            cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
        elif os.path.exists("firebase-service-account.json"):
            cred = credentials.Certificate("firebase-service-account.json")
        else:
            cred = None
        if cred:
            firebase_admin.initialize_app(cred)
        _firebase_initialized = True
    except Exception as e:
        logger.warning(f"Firebase Admin non initialisé (push désactivé) : {e}")


def _push_tokens_from_user(
    user: dict | None,
    platform: str | None = None,
) -> list[str]:
    if not user:
        return []
    normalized_platform = (platform or "").strip().lower()
    tokens: list[str] = []
    for item in user.get("fcm_tokens") or []:
        if not isinstance(item, dict):
            continue
        if item.get("is_active") is False:
            continue
        token_platform = (item.get("platform") or "").strip().lower()
        if normalized_platform and token_platform != normalized_platform:
            continue
        token = (item.get("token") or "").strip()
        if token and token not in tokens:
            tokens.append(token)
    if not normalized_platform:
        legacy_token = (user.get("fcm_token") or "").strip()
        if legacy_token and legacy_token not in tokens:
            tokens.append(legacy_token)
    return tokens[:10]


def _is_invalid_fcm_token_error(exc: Exception) -> bool:
    code = getattr(exc, "code", None)
    if code in {"registration-token-not-registered", "invalid-registration-token"}:
        return True
    message = str(exc).lower()
    return (
        "registration token is not a valid" in message
        or "requested entity was not found" in message
        or "not a valid fcm registration token" in message
        or "registration-token-not-registered" in message
    )


def _notif_id() -> str:
    return f"ntf_{uuid.uuid4().hex[:12]}"


_PUSH_ALERT_PROFILES = {
    "mission": {
        "android_channel_id": "denkma_missions_v3",
        "android_sound": "denkma_mission",
        "ios_sound": "denkma_mission.wav",
    },
    "message": {
        "android_channel_id": "denkma_messages_v4",
        "android_sound": "denkma_message",
        "ios_sound": "denkma_message.wav",
    },
    "status": {
        "android_channel_id": "denkma_updates_v3",
        "android_sound": "denkma_status",
        "ios_sound": "denkma_status.wav",
    },
    "mission_update": {
        "android_channel_id": "denkma_mission_updates_v1",
        "android_sound": "denkma_mission",
        "ios_sound": "denkma_mission.wav",
    },
    "other": {
        "android_channel_id": "denkma_other_alerts_v1",
        "android_sound": "denkma_status",
        "ios_sound": "denkma_status.wav",
    },
}


def _push_alert_profile(
    event_type: Optional[str],
    ref_type: Optional[str],
    category: Optional[str],
    *,
    target_view: Optional[str] = None,
    parcel_status: Optional[str] = None,
    alert_kind: Optional[str] = None,
) -> dict[str, str]:
    normalized_event = (event_type or "").strip().lower()
    normalized_ref = (ref_type or "").strip().lower()
    normalized_category = (category or "").strip().lower()
    normalized_view = (target_view or "").strip().lower()
    if normalized_category == "messages" or normalized_event == "parcel_message":
        return _PUSH_ALERT_PROFILES["message"]
    if normalized_event == "mission_available" and normalized_view in {"", "driver"}:
        return _PUSH_ALERT_PROFILES["mission"]
    if normalized_ref == "mission" or normalized_event in {
        "mission_detail",
        "mission_unavailable",
    }:
        return _PUSH_ALERT_PROFILES["mission_update"]
    if normalized_view == "client" and (
        (normalized_event == "parcel_detail" and parcel_status)
        or alert_kind == "delivery_step"
    ):
        return _PUSH_ALERT_PROFILES["status"]
    return _PUSH_ALERT_PROFILES["other"]


def _android_alert_channel_id(profile: dict[str, str], user: dict) -> str:
    channel_id = profile["android_channel_id"]
    if (user.get("notification_prefs") or {}).get("android_vibration") is False:
        return f"{channel_id}_no_vibration"
    return channel_id


STATUS_MESSAGES = {
    ParcelStatus.CREATED:                 "Vous avez un colis à recevoir ! Code de suivi : {tracking_code}",
    ParcelStatus.DROPPED_AT_ORIGIN_RELAY: "Votre colis a été déposé au point relais.",
    ParcelStatus.IN_TRANSIT:              "Votre colis est en route.",
    ParcelStatus.AT_DESTINATION_RELAY:    "Votre colis est arrivé au relais destination.",
    ParcelStatus.AVAILABLE_AT_RELAY:      "Votre colis vous attend au relais. Présentez votre code de retrait pour le récupérer.",
    ParcelStatus.OUT_FOR_DELIVERY:        "Un livreur est en route pour livrer votre colis.",
    ParcelStatus.DELIVERED:               "Votre colis a été livré avec succès. Consultez le récapitulatif et laissez votre avis.",
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
    ParcelStatus.IN_TRANSIT:              "Votre colis {tracking_code} est en route.",
    ParcelStatus.AT_DESTINATION_RELAY:    "Votre colis {tracking_code} est arrivé au relais proche du destinataire.",
    ParcelStatus.AVAILABLE_AT_RELAY:      "Votre colis {tracking_code} est disponible au relais pour le destinataire.",
    ParcelStatus.OUT_FOR_DELIVERY:        "Le livreur est en route pour livrer votre colis {tracking_code}.",
    ParcelStatus.DELIVERED:               "Votre colis {tracking_code} a été livré avec succès. Consultez le récapitulatif et laissez votre avis.",
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
        "messages": "messages",
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

    has_app = bool(_push_tokens_from_user(user_doc))
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


def _status_title(status: ParcelStatus, *, recipient: bool = False) -> str:
    return {
        ParcelStatus.CREATED: "Vous avez un colis à recevoir !" if recipient else "Colis créé",
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY: "Colis déposé au relais",
        ParcelStatus.IN_TRANSIT: "Colis en route",
        ParcelStatus.AT_DESTINATION_RELAY: "Colis arrivé au relais",
        ParcelStatus.AVAILABLE_AT_RELAY: "Colis prêt à être retiré",
        ParcelStatus.OUT_FOR_DELIVERY: "Livraison en cours",
        ParcelStatus.DELIVERED: "Colis livré",
        ParcelStatus.DELIVERY_FAILED: "Livraison non terminée",
        ParcelStatus.REDIRECTED_TO_RELAY: "Colis redirigé vers un relais",
        ParcelStatus.INCIDENT_REPORTED: "Incident signalé",
        ParcelStatus.CANCELLED: "Colis annulé",
        ParcelStatus.EXPIRED: "Délai de retrait dépassé",
        ParcelStatus.RETURNED: "Colis retourné",
        ParcelStatus.SUSPENDED: "Livraison suspendue",
    }.get(status, "Suivi de votre colis")


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
    mission = await db.delivery_missions.find_one(
        {"parcel_id": parcel.get("parcel_id"), "driver_id": driver_id},
        {"_id": 0, "mission_id": 1, "assigned_at": 1},
        sort=[("updated_at", -1)],
    )
    mission_id = (mission or {}).get("mission_id")
    elapsed_label = _mission_elapsed_label((mission or {}).get("assigned_at"))
    if elapsed_label:
        body = f"{body} Mission en cours depuis {elapsed_label}."
    is_unavailable = new_status in {ParcelStatus.CANCELLED, ParcelStatus.RETURNED}
    await _store_and_send(
        user_id=driver_id,
        title=title,
        body=body,
        ref_type="mission" if mission_id else "parcel",
        ref_id=mission_id or parcel.get("parcel_id"),
        category="parcel_updates",
        skip_whatsapp=True,
        event_type="mission_unavailable" if is_unavailable else "mission_detail",
        target_view="driver",
        dedupe_key=f"driver_parcel_status:{parcel.get('parcel_id')}:{new_status.value}",
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
    mission = await db.delivery_missions.find_one(
        {"parcel_id": parcel.get("parcel_id"), "driver_id": driver_id},
        {"_id": 0, "mission_id": 1, "assigned_at": 1},
        sort=[("updated_at", -1)],
    )
    mission_id = (mission or {}).get("mission_id")
    elapsed_label = _mission_elapsed_label((mission or {}).get("assigned_at"))
    if elapsed_label:
        body = f"{body} Mission en cours depuis {elapsed_label}."
    await _store_and_send(
        user_id=driver_id,
        title="Mission reprise",
        body=body,
        ref_type="mission" if mission_id else "parcel",
        ref_id=mission_id or parcel.get("parcel_id"),
        category="parcel_updates",
        skip_whatsapp=True,
        event_type="mission_detail",
        target_view="driver",
        dedupe_key=f"mission_resumed:{mission_id or parcel.get('parcel_id')}",
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
            title=_status_title(new_status),
            body=sender_body,
            ref_type="parcel",
            ref_id=parcel.get("parcel_id"),
            category="parcel_updates",
            whatsapp_template=sender_template,
            whatsapp_variables=sender_template_vars,
            skip_whatsapp=not is_creation,
            metadata={"parcel_status": new_status.value},
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

    if new_status in {
        ParcelStatus.DELIVERED,
        ParcelStatus.DELIVERY_FAILED,
        ParcelStatus.CANCELLED,
        ParcelStatus.RETURNED,
        ParcelStatus.EXPIRED,
        ParcelStatus.SUSPENDED,
        ParcelStatus.DISPUTED,
    }:
        await notify_tracking_ended(
            [uid for uid in (sender_id, recipient_user_id) if uid],
            parcel_id=parcel.get("parcel_id", ""),
        )

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
            title=_status_title(new_status, recipient=True),
            body=recipient_body,
            ref_type="parcel",
            ref_id=parcel.get("parcel_id"),
            category="parcel_updates",
            whatsapp_template=recipient_template,
            whatsapp_variables=template_vars_recipient,
            whatsapp_button_variables=recipient_button_vars,
            metadata={"parcel_status": new_status.value},
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
        title="Un livreur a accepté votre colis",
        metadata={"alert_kind": "delivery_step"},
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
    metadata: Optional[dict] = None,
    store_in_app: bool = True,
    event_type: Optional[str] = None,
    target_view: Optional[str] = None,
    dedupe_key: Optional[str] = None,
    push_platform: Optional[str] = None,
):
    """Stocke la notification en base et tente l'envoi.

    skip_whatsapp: si True, n'envoie ni template ni texte libre WhatsApp.
    Utile quand on veut limiter une notif à push + in-app seulement.
    """
    user = await db.users.find_one(
        {"user_id": user_id},
        {"notification_prefs": 1, "phone": 1, "fcm_token": 1, "fcm_tokens": 1, "role": 1,
         "is_active": 1, "is_available": 1, "is_banned": 1,
         "last_driver_location": 1, "last_driver_location_at": 1},
    )
    if not _notification_category_enabled(user, category):
        return {
            "stored": False,
            "push_status": "skipped",
            "push_reason": "category_disabled",
        }

    if event_type == "mission_available":
        reason = await _mission_availability_skip_reason(user_id, ref_id, user, metadata)
        if reason:
            return {"stored": False, "push_status": "skipped", "push_reason": reason}

    if not event_type:
        if ref_type == "parcel":
            event_type = "parcel_detail"
            target_view = target_view or (
                "admin"
                if (user or {}).get("role") in {"admin", "superadmin"}
                else "client"
            )
        elif ref_type == "mission":
            event_type = "mission_detail"
            target_view = target_view or "driver"
        elif ref_type == "payout":
            event_type = "wallet"
            target_view = target_view or (user or {}).get("role")
        elif ref_type == "application":
            event_type = "application_status"
            target_view = target_view or "client"

    notif_id = None
    notification_created = False
    if store_in_app:
        notif_id, notification_created = await _store_notification(
            user_id=user_id,
            channel=NotificationChannel.IN_APP,
            title=title,
            body=body,
            ref_type=ref_type,
            ref_id=ref_id,
            metadata=metadata,
            event_type=event_type,
            target_view=target_view,
            dedupe_key=dedupe_key,
        )

    if store_in_app and dedupe_key and not notification_created:
        push_result = {
            "push_status": "skipped",
            "push_reason": "duplicate_event",
        }
    else:
        push_result = await _send_push(
            user_id=user_id,
            title=title,
            body=body,
            ref_type=ref_type,
            ref_id=ref_id,
            category=category,
            notif_id=notif_id,
            event_type=event_type,
            target_view=target_view,
            dedupe_key=dedupe_key,
            metadata=metadata,
            push_platform=push_platform,
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

    return {"stored": store_in_app, "notif_id": notif_id, **push_result}


async def _store_notification(
    user_id: str,
    channel: NotificationChannel,
    title: str,
    body: str,
    ref_type: Optional[str] = None,
    ref_id: Optional[str] = None,
    metadata: Optional[dict] = None,
    status: NotificationStatus = NotificationStatus.SENT,
    event_type: Optional[str] = None,
    target_view: Optional[str] = None,
    dedupe_key: Optional[str] = None,
):
    now = datetime.now(timezone.utc)
    notif_id = _notif_id()
    notif = {
        "notif_id": notif_id,
        "user_id": user_id,
        "channel": channel.value,
        "title": title,
        "body": body,
        "status": status.value,
        "metadata": metadata or {},
        "ref_type": ref_type,
        "ref_id": ref_id,
        "event_type": event_type,
        "target_view": target_view,
        "dedupe_key": dedupe_key,
        "created_at": now,
        "sent_at": now if status == NotificationStatus.SENT else None,
        "read_at": None,
    }
    if not dedupe_key:
        await db.notifications.insert_one(notif)
        return notif_id, True

    result = await db.notifications.update_one(
        {"user_id": user_id, "dedupe_key": dedupe_key},
        {
            "$set": {
                "title": title,
                "body": body,
                "status": status.value,
                "metadata": metadata or {},
                "ref_type": ref_type,
                "ref_id": ref_id,
                "event_type": event_type,
                "target_view": target_view,
                "sent_at": now if status == NotificationStatus.SENT else None,
                "updated_at": now,
            },
            "$setOnInsert": {
                "notif_id": notif_id,
                "user_id": user_id,
                "channel": channel.value,
                "dedupe_key": dedupe_key,
                "created_at": now,
                "read_at": None,
            },
        },
        upsert=True,
    )
    stored = await db.notifications.find_one(
        {"user_id": user_id, "dedupe_key": dedupe_key},
        {"_id": 0, "notif_id": 1},
    )
    return (stored or {}).get("notif_id") or notif_id, result.upserted_id is not None


async def _driver_has_active_mission(user_id: str) -> bool:
    return await db.delivery_missions.find_one(
        {"driver_id": user_id, "status": {"$in": ACTIVE_MISSION_STATUSES}},
        {"_id": 0, "mission_id": 1},
    ) is not None


async def _mission_availability_skip_reason(
    user_id: str, mission_id: Optional[str], user: Optional[dict], metadata: Optional[dict],
) -> Optional[str]:
    if await _driver_has_active_mission(user_id):
        return "active_mission"
    if not mission_id:
        return None
    if not user or user.get("is_active") is not True or user.get("is_available") is not True or user.get("is_banned") is True:
        return "driver_unavailable"
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission or mission.get("status") != "pending" or user_id in (mission.get("declined_driver_ids") or []):
        return "mission_unavailable"
    if mission.get("parcel_id"):
        parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"status": 1})
        if not parcel or parcel.get("status") in {
            ParcelStatus.CANCELLED.value, ParcelStatus.RETURNED.value, ParcelStatus.DELIVERED.value,
            ParcelStatus.EXPIRED.value, ParcelStatus.DISPUTED.value, ParcelStatus.SUSPENDED.value,
        }:
            return "mission_unavailable"
    requested = mission.get("admin_requested_driver_id")
    if requested:
        return None if requested == user_id else "mission_unavailable"
    now = datetime.now(timezone.utc)
    max_age = min(settings.DRIVER_DISPATCH_LOCATION_MAX_AGE_MINUTES * 60, settings.GPS_CAPTURE_MAX_AGE_SECONDS)
    location = user.get("last_driver_location")
    if not location_is_live(location, user.get("last_driver_location_at"), now=now, max_age_seconds=max_age):
        return "driver_location_stale"
    from services.parcel_service import (
        _haversine_km, _normalize_geopin, get_delivery_dispatch_settings, resolve_delivery_dispatch_state,
    )
    try:
        pickup = _normalize_geopin(mission.get("pickup_geopin"))
        if not pickup:
            return "driver_location_unavailable"
        if not all(math.isfinite(pickup[key]) and abs(pickup[key]) <= bound
                   for key, bound in (("lat", 90), ("lng", 180))):
            return "driver_location_unavailable"
        radius = mission.get("dispatch_radius_km")
        if radius is None:
            radius = (metadata or {}).get("dispatch_radius_km")
        if radius is None:
            dispatch = mission.get("delivery_dispatch") or await get_delivery_dispatch_settings()
            started_at = timestamp(mission.get("dispatch_started_at")) or timestamp(mission.get("created_at")) or now
            radius = resolve_delivery_dispatch_state(dispatch, started_at, now=now)["radius_km"]
        radius = float(radius)
        if not math.isfinite(radius) or radius <= 0:
            return "mission_unavailable"
        if _haversine_km(location["lat"], location["lng"], pickup["lat"], pickup["lng"]) > radius:
            return "driver_outside_dispatch_radius"
    except (TypeError, ValueError, AttributeError):
        return "driver_location_unavailable"
    return None


async def _send_push(
    user_id: str,
    title: str,
    body: str,
    ref_type: Optional[str] = None,
    ref_id: Optional[str] = None,
    category: Optional[str] = None,
    notif_id: Optional[str] = None,
    event_type: Optional[str] = None,
    target_view: Optional[str] = None,
    dedupe_key: Optional[str] = None,
    metadata: Optional[dict] = None,
    push_platform: Optional[str] = None,
):
    user = await db.users.find_one(
        {"user_id": user_id},
        {"fcm_token": 1, "fcm_tokens": 1, "notification_prefs": 1,
         "is_active": 1, "is_available": 1, "is_banned": 1,
         "last_driver_location": 1, "last_driver_location_at": 1},
    )
    fcm_tokens = _push_tokens_from_user(user, push_platform)
    push_enabled = ((user or {}).get("notification_prefs") or {}).get("push", True)

    if not user:
        return {"push_status": "skipped", "push_reason": "user_not_found"}
    if not fcm_tokens:
        return {"push_status": "skipped", "push_reason": "missing_fcm_token"}
    if not push_enabled:
        return {"push_status": "skipped", "push_reason": "push_disabled"}
    if not _notification_category_enabled(user, category):
        return {"push_status": "skipped", "push_reason": "category_disabled"}
    if event_type == "mission_available":
        reason = await _mission_availability_skip_reason(user_id, ref_id, user, metadata)
        if reason:
            return {"push_status": "skipped", "push_reason": reason}

    _ensure_firebase()
    if not _firebase_initialized:
        return {"push_status": "skipped", "push_reason": "firebase_not_configured"}

    try:
        import firebase_admin.messaging as _messaging

        sent_count = 0
        invalid_tokens: list[str] = []
        failed_reasons: list[str] = []
        data = {
            "ref_type": ref_type or "",
            "ref_id": ref_id or "",
            "notif_id": notif_id or "",
            "event_type": event_type or "",
            "target_view": target_view or "",
            "dedupe_key": dedupe_key or "",
            "category": category or "",
        }
        for key in (
            "message_id",
            "parcel_id",
            "parcel_status",
            "alert_kind",
            "store_url",
            "platform",
            "version",
        ):
            value = (metadata or {}).get(key)
            if value is not None:
                data[key] = str(value)
        collapse_id = (dedupe_key or event_type or ref_id or "").strip()[:64]
        alert_profile = _push_alert_profile(
            event_type, ref_type, category, target_view=target_view,
            parcel_status=(metadata or {}).get("parcel_status"),
            alert_kind=(metadata or {}).get("alert_kind"),
        )
        apns_headers = {"apns-collapse-id": collapse_id} if collapse_id else {}
        offer_ttl = None
        if event_type == "mission_available":
            offer_ttl = timedelta(seconds=min(
                settings.GPS_CAPTURE_MAX_AGE_SECONDS,
                settings.DRIVER_DISPATCH_LOCATION_MAX_AGE_MINUTES * 60,
            ))
            apns_headers["apns-expiration"] = str(int((datetime.now(timezone.utc) + offer_ttl).timestamp()))
        for token in fcm_tokens:
            message = _messaging.Message(
                notification=_messaging.Notification(title=title, body=body),
                data=data,
                android=_messaging.AndroidConfig(
                    collapse_key=collapse_id or None,
                    priority="high",
                    ttl=offer_ttl,
                    notification=_messaging.AndroidNotification(
                        channel_id=_android_alert_channel_id(alert_profile, user),
                        sound=alert_profile["android_sound"],
                        tag=collapse_id or None,
                    ),
                ),
                apns=_messaging.APNSConfig(
                    headers=apns_headers or None,
                    payload=_messaging.APNSPayload(
                        aps=_messaging.Aps(sound=alert_profile["ios_sound"]),
                    ),
                ),
                token=token,
            )
            try:
                _messaging.send(message)
                sent_count += 1
            except Exception as token_error:
                if _is_invalid_fcm_token_error(token_error):
                    invalid_tokens.append(token)
                failed_reasons.append(str(token_error)[:160])

        if invalid_tokens:
            await db.users.update_one(
                {"user_id": user_id},
                {
                    "$pull": {"fcm_tokens": {"token": {"$in": invalid_tokens}}},
                    "$unset": {"fcm_token": ""},
                },
            )
            latest_token = next(
                (token for token in fcm_tokens if token not in invalid_tokens),
                None,
            )
            if latest_token:
                await db.users.update_one(
                    {"user_id": user_id},
                    {"$set": {"fcm_token": latest_token}},
                )

        if not sent_count:
            reason = failed_reasons[0] if failed_reasons else "all_tokens_failed"
            logger.warning("Echec envoi Push FCM a %s: %s", user_id, reason)
            return {"push_status": "failed", "push_reason": reason[:240]}
        logger.info("Push FCM envoyé à %s", user_id)
        if event_type == "mission_available":
            try:
                await db.users.update_one(
                    {"user_id": user_id},
                    {"$max": {"last_mission_alert_at": datetime.now(timezone.utc)}},
                )
            except Exception:
                logger.warning("Impossible d'enregistrer le délai de rappel du livreur %s", user_id)
        return {"push_status": "sent", "push_reason": None}
    except Exception as e:
        logger.warning("Échec envoi Push FCM à %s: %s", user_id, e)
        return {"push_status": "failed", "push_reason": str(e)[:240]}


async def _send_data_push(
    user_id: str,
    data: dict[str, str],
    *,
    push_platform: str | None = None,
    category: str | None = None,
) -> None:
    user = await db.users.find_one(
        {"user_id": user_id},
        {"fcm_token": 1, "fcm_tokens": 1, "notification_prefs": 1},
    )
    if not user or not ((user.get("notification_prefs") or {}).get("push", True)):
        return
    if category and not _notification_category_enabled(user, category):
        return
    tokens = _push_tokens_from_user(user, push_platform)
    if not tokens:
        return

    _ensure_firebase()
    if not _firebase_initialized:
        return

    import firebase_admin.messaging as _messaging

    collapse_id = (data.get("dedupe_key") or data.get("ref_id") or "")[:64]
    for token in tokens:
        try:
            _messaging.send(
                _messaging.Message(
                    data={key: str(value) for key, value in data.items()},
                    android=_messaging.AndroidConfig(
                        collapse_key=collapse_id or None,
                        priority="high",
                        ttl=(
                            timedelta(seconds=90)
                            if data.get("event_type") == "tracking_progress"
                            else None
                        ),
                    ),
                    apns=_messaging.APNSConfig(
                        headers={
                            **({"apns-collapse-id": collapse_id} if collapse_id else {}),
                            "apns-priority": "5",
                        },
                        payload=_messaging.APNSPayload(
                            aps=_messaging.Aps(content_available=True),
                        ),
                    ),
                    # Android clients update one ongoing, silent notification;
                    # iOS requires a separate Live Activity implementation.
                    token=token,
                )
            )
        except Exception as exc:
            if _is_invalid_fcm_token_error(exc):
                await db.users.update_one(
                    {"user_id": user_id},
                    {"$pull": {"fcm_tokens": {"token": token}}},
                )


async def notify_tracking_progress(
    user_ids: list[str],
    *,
    parcel_id: str,
    tracking_code: str,
    phase: str,
    distance_text: str,
    eta_text: str,
) -> None:
    data = {
        "event_type": "tracking_progress",
        "ref_type": "parcel",
        "ref_id": parcel_id,
        "target_view": "client",
        "dedupe_key": f"tracking_progress:{parcel_id}",
        "tracking_code": tracking_code,
        "phase": phase,
        "distance_text": distance_text,
        "eta_text": eta_text,
    }
    for user_id in set(user_ids):
        await _send_data_push(
            user_id,
            data,
            push_platform="android",
            category="parcel_updates",
        )


async def notify_tracking_ended(user_ids: list[str], *, parcel_id: str) -> None:
    data = {
        "event_type": "tracking_ended",
        "ref_type": "parcel",
        "ref_id": parcel_id,
        "target_view": "client",
        "dedupe_key": f"tracking_progress:{parcel_id}",
    }
    for user_id in set(user_ids):
        await _send_data_push(
            user_id,
            data,
            push_platform="android",
            category="parcel_updates",
        )


async def expire_mission_availability_notifications(
    mission: dict,
    accepted_by_user_id: Optional[str] = None,
) -> None:
    mission_id = mission.get("mission_id")
    if not mission_id:
        return

    now = datetime.now(timezone.utc)
    dedupe_key = f"mission_available:{mission_id}"
    user_ids = list(
        {
            *list(mission.get("candidate_drivers") or []),
            *list(mission.get("dispatch_notified_driver_ids") or []),
        }
    )
    await db.notifications.update_many(
        {
            "user_id": {"$in": user_ids},
            "$or": [
                {"dedupe_key": dedupe_key},
                {
                    "ref_type": "mission",
                    "ref_id": mission_id,
                    "event_type": "mission_available",
                },
                {
                    "ref_type": "mission",
                    "ref_id": mission_id,
                    "title": {
                        "$in": [
                            "Nouvelle course près de vous",
                            "Course toujours disponible",
                            "Nouvelle Mission Disponible (Exclusivité 30s)",
                            "Nouvelle mission proposée",
                        ]
                    },
                },
            ],
        },
        {
            "$set": {
                "status": "cancelled",
                "read_at": now,
                "expired_at": now,
                "updated_at": now,
            }
        },
    )
    if accepted_by_user_id:
        await db.notifications.update_many(
            {
                "ref_type": "mission",
                "ref_id": mission_id,
            },
            {
                "$set": {
                    "metadata.accepted_by_user_id": accepted_by_user_id,
                }
            },
        )

    data = {
        "event_type": "mission_unavailable",
        "target_view": "driver",
        "ref_type": "mission",
        "ref_id": mission_id,
        "dedupe_key": dedupe_key,
    }
    for user_id in user_ids:
        if user_id and user_id != accepted_by_user_id:
            await _send_data_push(
                user_id,
                {**data, "dedupe_key": f"mission_reminder:{user_id}"},
            )


async def expire_mission_availability_for_user(
    mission_id: str,
    user_id: str,
) -> None:
    if not mission_id or not user_id:
        return
    now = datetime.now(timezone.utc)
    dedupe_key = f"mission_available:{mission_id}"
    await db.notifications.update_many(
        {
            "user_id": user_id,
            "ref_type": "mission",
            "ref_id": mission_id,
            "$or": [
                {"dedupe_key": dedupe_key},
                {"event_type": "mission_available"},
                {
                    "title": {
                        "$in": [
                            "Nouvelle course près de vous",
                            "Course toujours disponible",
                            "Nouvelle Mission Disponible (Exclusivité 30s)",
                            "Nouvelle mission proposée",
                        ]
                    }
                },
            ],
        },
        {
            "$set": {
                "status": "cancelled",
                "read_at": now,
                "expired_at": now,
                "updated_at": now,
            }
        },
    )
    await _send_data_push(
        user_id,
        {
            "event_type": "mission_unavailable",
            "target_view": "driver",
            "ref_type": "mission",
            "ref_id": mission_id,
            "dedupe_key": f"mission_reminder:{user_id}",
        },
    )


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
        f"Vous avez un colis à recevoir ! Référence : {tracking_code}.\n"
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
                metadata={"alert_kind": "delivery_step"},
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
        metadata={"alert_kind": "delivery_step"},
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
        event_type="mission_available",
        target_view="driver",
        dedupe_key=f"mission_available:{mission.get('mission_id')}",
    )


async def notify_driver_admin_assignment(user_id: str, mission: dict, assignment_mode: str):
    tracking_code = mission.get("tracking_code", "N/A")
    if assignment_mode == "driver_debt":
        title = "Mission assignée par l'administration"
        body = (
            f"La mission pour le colis {tracking_code} vous a été attribuée. "
            "La commission est enregistrée comme dette livreur."
        )
    elif assignment_mode == "platform_sponsored":
        title = "Mission assignée par l'administration"
        body = (
            f"La mission pour le colis {tracking_code} vous a été attribuée. "
            "La commission est prise en charge par Denkma."
        )
    else:
        title = "Nouvelle mission proposée"
        body = (
            f"La mission pour le colis {tracking_code} vous est proposée. "
            "Acceptez-la dans l'application."
        )

    await _store_and_send(
        user_id=user_id,
        title=title,
        body=body,
        ref_type="mission",
        ref_id=mission.get("mission_id"),
        event_type=(
            "mission_available"
            if assignment_mode not in {"driver_debt", "platform_sponsored"}
            else "mission_detail"
        ),
        target_view="driver",
        dedupe_key=(
            f"mission_available:{mission.get('mission_id')}"
            if assignment_mode not in {"driver_debt", "platform_sponsored"}
            else f"mission_assigned:{mission.get('mission_id')}"
        ),
    )


async def notify_driver_pickup_confirmation_reminder(
    *,
    user_id: str,
    mission: dict,
    minutes_remaining: int,
) -> None:
    tracking_code = mission.get("tracking_code", "N/A")
    body = (
        f"Confirmez la collecte du colis {tracking_code} dans {minutes_remaining} min. "
        "Sinon la mission sera réattribuée."
    )
    await _store_and_send(
        user_id=user_id,
        title="Collecte à confirmer",
        body=body,
        ref_type="mission",
        ref_id=mission.get("mission_id"),
        category="parcel_updates",
        skip_whatsapp=True,
        event_type="mission_detail",
        target_view="driver",
        dedupe_key=f"mission_pickup_reminder:{mission.get('mission_id')}",
    )


async def notify_driver_mission_auto_released(
    *,
    user_id: str,
    mission: dict,
) -> None:
    tracking_code = mission.get("tracking_code", "N/A")
    body = (
        f"La mission du colis {tracking_code} a été retirée faute de confirmation "
        "de la collecte dans les délais."
    )
    await _store_and_send(
        user_id=user_id,
        title="Mission réattribuée",
        body=body,
        ref_type="mission",
        ref_id=mission.get("mission_id"),
        category="parcel_updates",
        skip_whatsapp=True,
        event_type="mission_unavailable",
        target_view="driver",
        dedupe_key=f"mission_released:{mission.get('mission_id')}",
    )


async def notify_new_mission_dispatch_wave(
    *,
    user_ids: list[str],
    mission: dict,
    radius_km: float,
) -> dict:
    tracking_code = mission.get("tracking_code", "N/A")
    radius_label = f"{radius_km:.0f}" if float(radius_km).is_integer() else f"{radius_km:.1f}"
    return await send_targeted_notifications(
        user_ids=user_ids,
        title="Nouvelle course près de vous",
        body=(
            f"Une course pour le colis {tracking_code} est disponible dans un rayon de "
            f"{radius_label} km."
        ),
        category="parcel_updates",
        ref_type="mission",
        ref_id=mission.get("mission_id"),
        metadata={"dispatch_radius_km": radius_km},
        event_type="mission_available",
        target_view="driver",
        dedupe_key=f"mission_available:{mission.get('mission_id')}",
    )


async def notify_pending_mission_dispatch_reminder(
    *,
    user_ids: list[str],
    mission: dict,
    radius_km: float,
) -> dict:
    radius_label = f"{radius_km:.0f}" if float(radius_km).is_integer() else f"{radius_km:.1f}"
    results = []
    for user_id in dict.fromkeys(user_ids):
        now = datetime.now(timezone.utc)
        cutoff = now - timedelta(seconds=settings.DRIVER_MISSION_REMINDER_INTERVAL_SECONDS)
        previous = await db.users.find_one_and_update(
            {
                "user_id": user_id,
                "is_active": True,
                "is_available": True,
                "is_banned": {"$ne": True},
                "$or": [
                    {"last_mission_alert_at": {"$exists": False}},
                    {"last_mission_alert_at": None},
                    {"last_mission_alert_at": {"$lte": cutoff}},
                ],
            },
            {"$set": {"last_mission_alert_at": now}},
            projection={"last_mission_alert_at": 1},
        )
        if previous is None:
            results.append({"push_status": "skipped", "push_reason": "reminder_cooldown_or_unavailable"})
            continue
        result = None
        try:
            result = await _store_and_send(
                user_id=user_id,
                title="Courses toujours disponibles",
                body=(
                    f"Des courses sont toujours disponibles dans un rayon de {radius_label} km. "
                    "Ouvrez l'application pour les consulter."
                ),
                ref_type="mission",
                ref_id=mission.get("mission_id"),
                category="parcel_updates",
                skip_whatsapp=True,
                metadata={"dispatch_radius_km": radius_km, "reminder": True},
                store_in_app=False,
                event_type="mission_available",
                target_view="driver",
                dedupe_key=f"mission_reminder:{user_id}",
            )
            results.append(result)
        finally:
            if result is None or result.get("push_status") != "sent":
                previous_at = previous.get("last_mission_alert_at")
                restore = (
                    {"$set": {"last_mission_alert_at": previous_at}}
                    if previous_at is not None
                    else {"$unset": {"last_mission_alert_at": ""}}
                )
                await db.users.update_one(
                    {"user_id": user_id, "last_mission_alert_at": now}, restore,
                )
    return {
        "requested": len(user_ids),
        "push_sent": sum(result.get("push_status") == "sent" for result in results),
        "push_failed": sum(result.get("push_status") == "failed" for result in results),
    }


async def notify_new_parcel_message(
    parcel: dict,
    sender_id: str,
    sender_name: str,
    message_text: str,
    message_id: str,
):
    """Notifie les autres participants du colis (sender, recipient, driver) qu'un nouveau message est arrivé.

    Push + in-app uniquement (pas de WhatsApp pour éviter le spam — la conversation reste dans l'app).
    """
    parcel_id = parcel.get("parcel_id")
    tracking_code = parcel.get("tracking_code", "")
    participants = {
        parcel.get("sender_user_id"),
        parcel.get("recipient_user_id"),
        parcel.get("assigned_driver_id"),
    }
    participants.discard(None)
    participants.discard(sender_id)

    title = f"Nouveau message — {tracking_code}" if tracking_code else "Nouveau message"
    preview = (message_text or "").strip()
    if len(preview) > 120:
        preview = preview[:117] + "…"
    name = (sender_name or "").strip() or "Quelqu'un"
    body = f"{name} : {preview}" if preview else f"{name} vous a envoyé un message."
    driver_id = parcel.get("assigned_driver_id")
    mission = None
    if driver_id:
        mission = await db.delivery_missions.find_one(
            {"parcel_id": parcel_id, "driver_id": driver_id},
            {"_id": 0, "mission_id": 1},
            sort=[("updated_at", -1)],
        )
    mission_id = (mission or {}).get("mission_id")

    for uid in participants:
        is_driver = uid == driver_id and mission_id
        await _store_and_send(
            user_id=uid,
            title=title,
            body=body,
            ref_type="mission" if is_driver else "parcel",
            ref_id=mission_id if is_driver else parcel_id,
            category="messages",
            skip_whatsapp=True,
            metadata={
                "message_id": message_id,
                "parcel_id": parcel_id,
            },
            event_type="parcel_message",
            target_view="driver" if is_driver else "client",
            dedupe_key=f"parcel_message:{message_id}",
        )


async def send_targeted_notifications(
    *,
    user_ids: list[str],
    title: str,
    body: str,
    category: str = "admin",
    ref_type: Optional[str] = None,
    ref_id: Optional[str] = None,
    metadata: Optional[dict] = None,
    store_in_app: bool = True,
    event_type: Optional[str] = None,
    target_view: Optional[str] = None,
    dedupe_key: Optional[str] = None,
    push_platform: Optional[str] = None,
) -> dict:
    unique_user_ids = []
    seen = set()
    for user_id in user_ids:
        clean_id = (user_id or "").strip()
        if clean_id and clean_id not in seen:
            seen.add(clean_id)
            unique_user_ids.append(clean_id)

    stored = 0
    push_sent = 0
    push_failed = 0
    push_skipped = 0
    push_reasons: dict[str, int] = {}
    for user_id in unique_user_ids:
        result = await _store_and_send(
            user_id=user_id,
            title=title,
            body=body,
            ref_type=ref_type,
            ref_id=ref_id,
            category=category,
            skip_whatsapp=True,
            metadata=metadata,
            store_in_app=store_in_app,
            event_type=event_type,
            target_view=target_view,
            dedupe_key=dedupe_key,
            push_platform=push_platform,
        )
        if result.get("stored"):
            stored += 1
        push_status = result.get("push_status")
        push_reason = result.get("push_reason") or "none"
        if push_status == "sent":
            push_sent += 1
        elif push_status == "failed":
            push_failed += 1
            push_reasons[push_reason] = push_reasons.get(push_reason, 0) + 1
        else:
            push_skipped += 1
            push_reasons[push_reason] = push_reasons.get(push_reason, 0) + 1

    return {
        "requested": len(user_ids),
        "deduplicated": len(unique_user_ids),
        "sent": push_sent if not store_in_app else stored,
        "in_app_sent": stored,
        "push_sent": push_sent,
        "push_failed": push_failed,
        "push_skipped": push_skipped,
        "push_reasons": push_reasons,
    }


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


async def _relay_agent_user_ids(relay_id: str) -> list[str]:
    relay = await db.relay_points.find_one(
        {"relay_id": relay_id},
        {"_id": 0, "owner_user_id": 1, "agent_user_ids": 1},
    )
    user_ids = {
        str(user_id)
        for user_id in ((relay or {}).get("agent_user_ids") or [])
        if user_id
    }
    owner_user_id = (relay or {}).get("owner_user_id")
    if owner_user_id:
        user_ids.add(str(owner_user_id))
    cursor = db.users.find(
        {"relay_point_id": relay_id, "role": "relay_agent"},
        {"_id": 0, "user_id": 1},
    )
    async for agent in cursor:
        if agent.get("user_id"):
            user_ids.add(str(agent["user_id"]))
    return sorted(user_ids)


async def notify_location_updated(parcel: dict, *, actor: str) -> None:
    tracking_code = parcel.get("tracking_code", "")
    parcel_id = parcel.get("parcel_id")
    sender_id = parcel.get("sender_user_id")
    driver_id = parcel.get("assigned_driver_id")
    label = "livraison" if actor == "recipient" else "collecte"
    recipients: list[tuple[str, str]] = []
    if sender_id and actor == "recipient":
        recipients.append((sender_id, "client"))
    if driver_id:
        recipients.append((driver_id, "driver"))
    mission_id = None
    if driver_id:
        mission = await db.delivery_missions.find_one(
            {"parcel_id": parcel_id, "driver_id": driver_id},
            {"_id": 0, "mission_id": 1},
            sort=[("updated_at", -1)],
        )
        mission_id = (mission or {}).get("mission_id")
    changed_at = parcel.get("updated_at")
    change_marker = (
        changed_at.isoformat()
        if isinstance(changed_at, datetime)
        else str(changed_at or datetime.now(timezone.utc).isoformat())
    )
    for user_id, target_view in recipients:
        await _store_and_send(
            user_id=user_id,
            title=f"Position de {label} mise à jour",
            body=f"La position de {label} du colis {tracking_code} a été confirmée ou modifiée.",
            ref_type="mission" if target_view == "driver" else "parcel",
            ref_id=mission_id if target_view == "driver" else parcel_id,
            category="parcel_updates",
            skip_whatsapp=True,
            event_type="mission_detail" if target_view == "driver" else "parcel_detail",
            target_view=target_view,
            dedupe_key=f"location_updated:{parcel_id}:{actor}:{target_view}:{change_marker}",
        )


async def notify_incident_resolved(parcel: dict, *, resolution: str) -> None:
    tracking_code = parcel.get("tracking_code", "")
    body = f"L'incident du colis {tracking_code} est résolu. Décision : {resolution}."
    user_ids = {
        parcel.get("sender_user_id"),
        parcel.get("recipient_user_id"),
    }
    for user_id in {item for item in user_ids if item}:
        await _store_and_send(
            user_id=user_id,
            title="Incident résolu",
            body=body,
            ref_type="parcel",
            ref_id=parcel.get("parcel_id"),
            category="parcel_updates",
            skip_whatsapp=True,
            event_type="parcel_detail",
            target_view="client",
            dedupe_key=f"incident_resolved:{parcel.get('parcel_id')}:{resolution}:{user_id}",
        )


async def notify_driver_mission_completed(mission: dict, parcel: dict) -> None:
    driver_id = mission.get("driver_id")
    if not driver_id:
        return
    tracking_code = parcel.get("tracking_code") or mission.get("tracking_code", "")
    gain = float(mission.get("earn_amount") or 0)
    await _store_and_send(
        user_id=driver_id,
        title="Mission terminée",
        body=f"Mission {tracking_code} terminée. Gain prévu : {int(round(gain))} XOF. Consultez le récapitulatif.",
        ref_type="mission",
        ref_id=mission.get("mission_id"),
        category="parcel_updates",
        skip_whatsapp=True,
        event_type="mission_detail",
        target_view="driver",
        dedupe_key=f"mission_completed:{mission.get('mission_id')}",
    )


async def notify_driver_low_balance(
    user_id: str,
    *,
    balance_xof: float,
    required_xof: float,
) -> None:
    await _store_and_send(
        user_id=user_id,
        title="Solde bientôt insuffisant",
        body=(
            f"Votre solde est de {int(round(balance_xof))} XOF. "
            f"Une mission similaire demande environ {int(round(required_xof))} XOF."
        ),
        ref_type="wallet",
        category="parcel_updates",
        skip_whatsapp=True,
        event_type="wallet",
        target_view="driver",
        dedupe_key=f"driver_low_balance:{user_id}:{datetime.now(timezone.utc).date().isoformat()}",
    )


async def notify_driver_relay_closing(
    user_id: str,
    mission: dict,
    relay: dict,
    *,
    status_label: str,
) -> None:
    await _store_and_send(
        user_id=user_id,
        title="Attention aux horaires du relais",
        body=f"{relay.get('name') or 'Le relais'} : {status_label}. Vérifiez l'itinéraire de la mission.",
        ref_type="mission",
        ref_id=mission.get("mission_id"),
        category="parcel_updates",
        skip_whatsapp=True,
        event_type="mission_detail",
        target_view="driver",
        dedupe_key=f"relay_hours:{mission.get('mission_id')}:{relay.get('relay_id')}:{datetime.now(timezone.utc).date().isoformat()}",
    )


async def notify_driver_document_expiry(
    user_id: str,
    *,
    document_label: str,
    days_remaining: int,
) -> None:
    await _store_and_send(
        user_id=user_id,
        title=f"{document_label} bientôt expiré",
        body=f"Votre {document_label.lower()} expire dans {days_remaining} jour(s). Mettez votre document à jour.",
        ref_type="profile",
        category="admin",
        skip_whatsapp=True,
        event_type="driver_document",
        target_view="driver",
        dedupe_key=f"driver_document_expiry:{user_id}:{document_label}:{days_remaining}",
    )


async def _notify_relay_users(
    relay_id: str,
    *,
    title: str,
    body: str,
    parcel_id: str | None = None,
    event_type: str = "relay_parcel",
    dedupe_key: str,
    metadata: Optional[dict] = None,
) -> None:
    for user_id in await _relay_agent_user_ids(relay_id):
        await _store_and_send(
            user_id=user_id,
            title=title,
            body=body,
            ref_type="parcel" if parcel_id else "relay",
            ref_id=parcel_id or relay_id,
            category="parcel_updates",
            skip_whatsapp=True,
            event_type=event_type,
            target_view="relay_agent",
            dedupe_key=f"{dedupe_key}:{user_id}",
            metadata={"relay_id": relay_id, **(metadata or {})},
        )


async def notify_relay_parcel_incoming(relay_id: str, parcel: dict) -> None:
    tracking_code = parcel.get("tracking_code", "")
    await _notify_relay_users(
        relay_id,
        title="Un colis arrive bientôt",
        body=f"Le colis {tracking_code} est en route vers votre relais. Préparez sa réception.",
        parcel_id=parcel.get("parcel_id"),
        dedupe_key=f"relay_incoming:{parcel.get('parcel_id')}",
    )


async def notify_relay_driver_approaching(
    relay_id: str,
    parcel: dict,
    *,
    accepted: bool = False,
) -> None:
    tracking_code = parcel.get("tracking_code", "")
    await _notify_relay_users(
        relay_id,
        title=("Collecte relais planifiée" if accepted else "Le livreur arrive au relais"),
        body=(
            f"Un livreur a accepté la collecte du colis {tracking_code}. Gardez le code de collecte disponible."
            if accepted
            else f"Le livreur approche pour récupérer le colis {tracking_code}. Préparez le colis et son code."
        ),
        parcel_id=parcel.get("parcel_id"),
        dedupe_key=(
            f"relay_pickup_assigned:{parcel.get('parcel_id')}"
            if accepted
            else f"relay_pickup_approaching:{parcel.get('parcel_id')}"
        ),
    )


async def notify_relay_financial_action(
    relay_id: str,
    parcel: dict,
    *,
    action: str,
    amount_xof: float,
) -> None:
    labels = {
        "driver_payment": (
            "Paiement au livreur à effectuer",
            "Remettez {amount} XOF au livreur pour le colis {tracking} puis déclarez l'action.",
        ),
        "denkma_payment": (
            "Règlement Denkma à déclarer",
            "Le règlement de {amount} XOF lié au colis {tracking} doit être déclaré à Denkma.",
        ),
    }
    if action not in labels or amount_xof <= 0:
        return
    title, template = labels[action]
    tracking_code = parcel.get("tracking_code", "")
    await _notify_relay_users(
        relay_id,
        title=title,
        body=template.format(amount=int(round(amount_xof)), tracking=tracking_code),
        parcel_id=parcel.get("parcel_id"),
        event_type="relay_finance",
        dedupe_key=f"relay_financial_action:{parcel.get('parcel_id')}:{action}",
        metadata={"financial_action": action, "amount_xof": amount_xof},
    )


async def notify_relay_settlement_update(
    relay_id: str,
    parcel: dict,
    *,
    action: str,
    status: str,
    note: str | None = None,
) -> None:
    summary_labels = {
        "denkma_payment": "Règlement Denkma",
        "driver_payment": "Paiement au livreur",
        "origin_relay_payment": "Commission du relais de départ",
        "destination_relay_payment": "Commission du relais d'arrivée",
    }
    label = summary_labels.get(action, "Règlement")
    approved = status == "validated"
    title = f"{label} validé" if approved else f"{label} refusé"
    tracking_code = parcel.get("tracking_code", "")
    body = f"{label} pour le colis {tracking_code} : {'validé' if approved else 'refusé'} par Denkma."
    if note:
        body = f"{body} Motif : {note}"
    await _notify_relay_users(
        relay_id,
        title=title,
        body=body,
        parcel_id=parcel.get("parcel_id"),
        event_type="relay_finance",
        dedupe_key=f"relay_settlement:{parcel.get('parcel_id')}:{action}:{status}",
        metadata={"financial_action": action, "settlement_status": status},
    )


async def notify_relay_parcel_expiry_reminder(
    relay_id: str,
    parcel: dict,
    *,
    hours_remaining: int,
) -> None:
    tracking_code = parcel.get("tracking_code", "")
    await _notify_relay_users(
        relay_id,
        title="Colis bientôt expiré",
        body=f"Le colis {tracking_code} expire dans environ {hours_remaining} h. Contactez le destinataire si nécessaire.",
        parcel_id=parcel.get("parcel_id"),
        dedupe_key=f"relay_expiry:{parcel.get('parcel_id')}:{hours_remaining}",
        metadata={"hours_remaining": hours_remaining},
    )


async def notify_relay_capacity_warning(relay: dict) -> None:
    relay_id = relay.get("relay_id")
    capacity = int(relay.get("max_capacity") or 0)
    load = max(0, int(relay.get("current_load") or 0))
    if not relay_id or capacity <= 0:
        return
    percentage = round(load / capacity * 100)
    await _notify_relay_users(
        relay_id,
        title="Capacité du relais atteinte" if load >= capacity else "Capacité du relais presque atteinte",
        body=f"Votre relais contient {load} colis sur {capacity} places ({percentage} %).",
        event_type="relay_stock",
        dedupe_key=(
            f"relay_capacity:{relay_id}:"
            f"{'full' if load >= capacity else 'warning'}:"
            f"{datetime.now(timezone.utc).date().isoformat()}"
        ),
        metadata={"current_load": load, "max_capacity": capacity, "percentage": percentage},
    )
    from services.admin_events_service import AdminEventType, record_admin_event

    await record_admin_event(
        AdminEventType.RELAY_CAPACITY_WARNING,
        title=(
            "Capacité relais atteinte"
            if load >= capacity
            else "Capacité relais presque atteinte"
        ),
        message=(
            f"{relay.get('name') or relay_id} contient {load} colis sur "
            f"{capacity} places ({percentage} %)."
        ),
        href=f"/dashboard/relays/{relay_id}",
        metadata={
            "relay_id": relay_id,
            "current_load": load,
            "max_capacity": capacity,
            "percentage": percentage,
        },
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
        event_type="wallet",
        dedupe_key=f"payout_result:{user_id}:{int(amount)}:{approved}",
    )


async def notify_application_result(
    user_id: str,
    application_id: str,
    application_type: str,
    approved: bool,
    admin_notes: Optional[str] = None,
):
    kind = "livreur" if application_type == "driver" else "point relais"
    if approved:
        title = "Candidature approuvée"
        body = f"Votre candidature {kind} a été approuvée."
    else:
        title = "Candidature rejetée"
        body = f"Votre candidature {kind} n'a pas été retenue."
    note = (admin_notes or "").strip()
    if note:
        body = f"{body} Motif : {note}"

    result = await _store_and_send(
        user_id=user_id,
        title=title,
        body=body,
        ref_type="application",
        ref_id=application_id,
        category="admin",
        skip_whatsapp=True,
        event_type="application_status",
        target_view="client",
        dedupe_key=f"application_result:{application_id}",
        metadata={
            "application_id": application_id,
            "application_type": application_type,
            "approved": approved,
        },
    )

    user = await db.users.find_one(
        {"user_id": user_id},
        {"phone": 1, "notification_prefs": 1, "full_name": 1, "name": 1},
    )
    prefs = (user or {}).get("notification_prefs") or {}
    phone = (user or {}).get("phone")
    if phone and prefs.get("whatsapp", True):
        template_name = (
            settings.WHATSAPP_TEMPLATE_APPLICATION_APPROVED
            if approved
            else settings.WHATSAPP_TEMPLATE_APPLICATION_REJECTED
        )
        detail = note or (
            "Consultez votre compte Denkma pour la suite."
            if approved
            else "Vous pouvez contacter le support Denkma si besoin."
        )
        if template_name:
            sent = await _send_whatsapp_template(
                phone,
                template_name,
                [
                    _first_name((user or {}).get("full_name") or (user or {}).get("name")),
                    kind,
                    detail,
                ],
            )
            if not sent:
                await _send_whatsapp(phone, body)
        else:
            await _send_whatsapp(phone, body)

    return result


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


async def notify_parcel_expiry_reminder(
    parcel: dict,
    *,
    hours_remaining: int,
) -> None:
    recipient_user_id = parcel.get("recipient_user_id")
    if not recipient_user_id and parcel.get("recipient_phone"):
        user = await _find_user_by_phone(parcel.get("recipient_phone"))
        recipient_user_id = (user or {}).get("user_id")
    if recipient_user_id:
        await _store_and_send(
            user_id=recipient_user_id,
            title="Retirez votre colis avant expiration",
            body=(
                f"Le colis {parcel.get('tracking_code', '')} expire dans environ "
                f"{hours_remaining} h. Consultez les horaires et l'itinéraire du relais."
            ),
            ref_type="parcel",
            ref_id=parcel.get("parcel_id"),
            category="parcel_updates",
            skip_whatsapp=True,
            event_type="parcel_detail",
            target_view="client",
            dedupe_key=f"parcel_expiry:{parcel.get('parcel_id')}:{hours_remaining}",
        )

    relay_id = parcel.get("redirect_relay_id") or parcel.get("destination_relay_id")
    if relay_id:
        await notify_relay_parcel_expiry_reminder(
            relay_id,
            parcel,
            hours_remaining=hours_remaining,
        )


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
