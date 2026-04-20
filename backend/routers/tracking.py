"""
Router tracking : endpoints publics (sans authentification).
"""
import html
from datetime import datetime
from urllib.parse import urlencode

from config import settings

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from core.exceptions import not_found_exception
from database import db
from services.parcel_service import get_parcel_timeline

router = APIRouter()

from core.limiter import limiter


def _serialize_public_event(event: dict) -> dict:
    return {
        key: value
        for key, value in event.items()
        if key not in ("actor_id", "metadata")
    }


def _format_address_label(address: dict | None) -> str | None:
    if not isinstance(address, dict):
        return None
    return (
        address.get("label")
        or address.get("district")
        or address.get("city")
        or address.get("notes")
    )


def _format_dimensions(dimensions: dict | None) -> str | None:
    if not isinstance(dimensions, dict):
        return None
    parts = []
    for key in ("length", "width", "height", "l", "w", "h"):
        value = dimensions.get(key)
        if value:
            parts.append(str(value))
    return " x ".join(parts[:3]) if parts else None


def _format_dt(value) -> str:
    if not value:
        return "—"
    if isinstance(value, datetime):
        return value.strftime("%d/%m/%Y %H:%M")
    return str(value).replace("T", " ")[:16]


def _delivery_mode_label(mode: str | None) -> str:
    return {
        "relay_to_relay": "Relais vers relais",
        "relay_to_home": "Relais vers domicile",
        "home_to_relay": "Domicile vers relais",
        "home_to_home": "Domicile vers domicile",
    }.get(mode or "", mode or "Non renseigné")


def _current_location_label(parcel: dict, timeline: list[dict]) -> str:
    if parcel.get("status") == "created":
        return "Colis créé, en attente de prise en charge"
    latest = timeline[-1] if timeline else {}
    return (
        latest.get("notes")
        or latest.get("to_status")
        or parcel.get("status")
        or "Position en cours de mise à jour"
    )


def _app_install_url(parcel: dict) -> str:
    params = {
        "tracking": parcel.get("tracking_code") or "",
        "phone": parcel.get("recipient_phone") or "",
    }
    return f"{settings.PUBLIC_SITE_URL.rstrip('/')}/app?{urlencode(params)}"


def _build_public_tracking_payload(parcel: dict, timeline: list[dict]) -> dict:
    return {
        "parcel_id": parcel.get("parcel_id"),
        "tracking_code": parcel.get("tracking_code"),
        "status": parcel.get("status"),
        "delivery_mode": parcel.get("delivery_mode"),
        "delivery_mode_label": _delivery_mode_label(parcel.get("delivery_mode")),
        "sender_name": parcel.get("sender_name"),
        "sender_phone": parcel.get("sender_phone"),
        "recipient_name": parcel.get("recipient_name"),
        "description": parcel.get("description"),
        "weight_kg": parcel.get("weight_kg"),
        "dimensions_label": _format_dimensions(parcel.get("dimensions")),
        "is_express": bool(parcel.get("is_express")),
        "payment_status": parcel.get("payment_status"),
        "app_install_url": _app_install_url(parcel),
        "origin_label": _format_address_label(parcel.get("origin_location")),
        "delivery_label": _format_address_label(parcel.get("delivery_address")),
        "current_location_label": _current_location_label(parcel, timeline),
        "pickup_confirmed": bool(parcel.get("pickup_confirmed")),
        "delivery_confirmed": bool(parcel.get("delivery_confirmed")),
        "created_at": parcel.get("created_at"),
        "updated_at": parcel.get("updated_at"),
        "events": [_serialize_public_event(evt) for evt in timeline],
    }


@router.get("/{tracking_code}", summary="Statut public d'un colis")
@limiter.limit("5/minute")
async def track_parcel(tracking_code: str, request: Request):
    parcel = await db.parcels.find_one({"tracking_code": tracking_code}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    parcel_id = parcel.get("parcel_id")
    timeline = await get_parcel_timeline(parcel_id) if parcel_id else []
    return _build_public_tracking_payload(parcel, timeline)


@router.get("/{tracking_code}/events", summary="Historique complet du colis")
@limiter.limit("5/minute")
async def track_parcel_events(tracking_code: str, request: Request):
    parcel = await db.parcels.find_one(
        {"tracking_code": tracking_code},
        {"_id": 0, "parcel_id": 1},
    )
    if not parcel:
        raise not_found_exception("Colis")

    timeline = await get_parcel_timeline(parcel["parcel_id"])
    public_timeline = [_serialize_public_event(evt) for evt in timeline]
    return {"tracking_code": tracking_code, "events": public_timeline}


@router.get("/view/{tracking_code}", response_class=HTMLResponse, summary="Page de suivi Web (sans app)")
@limiter.limit("5/minute")
async def view_parcel_web(tracking_code: str, request: Request):
    """Affiche une page HTML publique pour le suivi d'un colis."""
    parcel = await track_parcel(tracking_code, request)

    status_map = {
        "created": ("Créé", "📦"),
        "dropped_at_origin_relay": ("Déposé au relais", "🏪"),
        "in_transit": ("En transit", "🚚"),
        "at_destination_relay": ("Arrivé au relais destination", "📍"),
        "available_at_relay": ("Prêt pour retrait", "✅"),
        "out_for_delivery": ("En cours de livraison", "🛵"),
        "delivered": ("Livré", "🎉"),
        "delivery_failed": ("Livraison échouée", "⚠️"),
        "redirected_to_relay": ("Redirigé vers un relais", "🏪"),
        "cancelled": ("Annulé", "❌"),
        "expired": ("Expiré", "⏱️"),
        "returned": ("Retourné", "↩️"),
    }

    current_status = parcel.get("status", "created")
    status_label, status_emoji = status_map.get(current_status, (current_status, "📦"))
    safe_tracking_code = html.escape(str(tracking_code))
    safe_status_label = html.escape(str(status_label))
    safe_status_emoji = html.escape(str(status_emoji))
    safe_sender_name = html.escape(str(parcel.get("sender_name") or "Non renseigné"))
    safe_sender_phone = html.escape(str(parcel.get("sender_phone") or "Non renseigné"))
    safe_recipient_name = html.escape(str(parcel.get("recipient_name") or "Non renseigné"))
    safe_mode = html.escape(str(parcel.get("delivery_mode_label") or "Non renseigné"))
    safe_current_location = html.escape(str(parcel.get("current_location_label") or "En attente de mise à jour"))
    safe_description = html.escape(str(parcel.get("description") or "Colis Denkma"))
    safe_weight = html.escape(str(parcel.get("weight_kg") or "—"))
    safe_dimensions = html.escape(str(parcel.get("dimensions_label") or "—"))
    safe_payment = html.escape(str(parcel.get("payment_status") or "—"))
    safe_app_install_url = html.escape(
        str(parcel.get("app_install_url") or f"{settings.PUBLIC_SITE_URL.rstrip('/')}/app"),
        quote=True,
    )
    safe_origin = html.escape(str(parcel.get("origin_label") or "À confirmer"))
    safe_delivery = html.escape(str(parcel.get("delivery_label") or "À confirmer"))
    safe_created_at = html.escape(_format_dt(parcel.get("created_at")))
    safe_updated_at = html.escape(_format_dt(parcel.get("updated_at")))

    events_html = ""
    for evt in reversed(parcel.get("events", [])):
        event_time = html.escape(_format_dt(evt.get("created_at")))
        event_title = html.escape(str(evt.get("notes") or evt.get("to_status") or "Mise à jour"))
        events_html += f"""
        <div class="event">
            <div class="event-dot"></div>
            <div class="event-content">
                <div class="event-time">{event_time}</div>
                <div class="event-title">{event_title}</div>
            </div>
        </div>
        """
    if not events_html:
        events_html = '<div class="empty">Aucun événement public pour le moment.</div>'

    page = f"""
    <!DOCTYPE html>
    <html lang="fr">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Suivi Denkma - {safe_tracking_code}</title>
        <style>
            :root {{
                --primary: #087f4f;
                --bg: #f5f8f4;
                --card: #ffffff;
                --text: #171b18;
                --muted: #66736b;
                --line: #dfe8e1;
                --soft: #eaf6ef;
            }}
            * {{ box-sizing: border-box; }}
            body {{
                margin: 0;
                font-family: Verdana, Geneva, sans-serif;
                background: radial-gradient(circle at top right, #e1f4ea, transparent 38%), var(--bg);
                color: var(--text);
                padding: 18px;
            }}
            .container {{ width: 100%; max-width: 760px; margin: 0 auto; }}
            .header {{ display: flex; align-items: center; justify-content: space-between; margin: 8px 0 22px; }}
            .logo {{ font-size: 24px; font-weight: 800; color: var(--primary); }}
            .badge {{ display: inline-flex; padding: 7px 12px; background: var(--soft); color: var(--primary); border-radius: 999px; font-weight: 700; font-size: 13px; }}
            .card {{ background: var(--card); border: 1px solid var(--line); border-radius: 22px; padding: 22px; box-shadow: 0 16px 40px rgba(22, 72, 43, 0.08); margin-bottom: 16px; }}
            h1 {{ font-size: clamp(28px, 8vw, 48px); margin: 16px 0 8px; letter-spacing: -0.04em; }}
            .status {{ font-size: 20px; font-weight: 700; display: flex; gap: 10px; align-items: center; }}
            .current {{ margin-top: 16px; padding: 14px; border-radius: 16px; background: #f7faf8; color: var(--muted); }}
            .grid {{ display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }}
            .info {{ border: 1px solid var(--line); border-radius: 16px; padding: 14px; background: #fbfdfb; }}
            .label {{ font-size: 12px; text-transform: uppercase; letter-spacing: .08em; color: var(--muted); margin-bottom: 6px; }}
            .value {{ font-weight: 700; line-height: 1.35; overflow-wrap: anywhere; }}
            .timeline {{ margin-top: 8px; position: relative; padding-left: 28px; }}
            .timeline::before {{ content: ''; position: absolute; left: 9px; top: 8px; bottom: 8px; width: 2px; background: var(--line); }}
            .event {{ position: relative; margin-bottom: 18px; }}
            .event-dot {{ position: absolute; left: -24px; top: 5px; width: 10px; height: 10px; background: var(--primary); border-radius: 50%; border: 3px solid white; box-shadow: 0 0 0 2px var(--primary); }}
            .event-time {{ font-size: 12px; color: var(--muted); margin-bottom: 4px; }}
            .event-title {{ font-weight: 700; }}
            .app-link {{ display: block; text-decoration: none; background: var(--primary); color: white; border-radius: 18px; padding: 16px; font-weight: 800; text-align: center; margin-top: 14px; }}
            .app-note {{ color: var(--muted); line-height: 1.5; margin: 0; }}
            .empty {{ color: var(--muted); }}
            .footer {{ text-align: center; color: var(--muted); font-size: 12px; margin: 28px 0 8px; }}
            @media (max-width: 640px) {{ .grid {{ grid-template-columns: 1fr; }} .card {{ padding: 18px; }} }}
        </style>
    </head>
    <body>
        <main class="container">
            <div class="header">
                <div class="logo">Denkma</div>
                <div class="badge">Suivi public</div>
            </div>

            <section class="card">
                <div class="badge">{safe_tracking_code}</div>
                <h1>{safe_status_label}</h1>
                <div class="status"><span>{safe_status_emoji}</span><span>{safe_current_location}</span></div>
                <div class="current">Dernière mise à jour : {safe_updated_at}</div>
            </section>

            <section class="card">
                <div class="grid">
                    <div class="info"><div class="label">Expéditeur</div><div class="value">{safe_sender_name}</div></div>
                    <div class="info"><div class="label">Téléphone expéditeur</div><div class="value">{safe_sender_phone}</div></div>
                    <div class="info"><div class="label">Destinataire</div><div class="value">{safe_recipient_name}</div></div>
                    <div class="info"><div class="label">Mode</div><div class="value">{safe_mode}</div></div>
                    <div class="info"><div class="label">Départ</div><div class="value">{safe_origin}</div></div>
                    <div class="info"><div class="label">Arrivée</div><div class="value">{safe_delivery}</div></div>
                    <div class="info"><div class="label">Colis</div><div class="value">{safe_description}</div></div>
                    <div class="info"><div class="label">Poids</div><div class="value">{safe_weight} kg</div></div>
                    <div class="info"><div class="label">Dimensions</div><div class="value">{safe_dimensions}</div></div>
                    <div class="info"><div class="label">Paiement</div><div class="value">{safe_payment}</div></div>
                    <div class="info"><div class="label">Créé le</div><div class="value">{safe_created_at}</div></div>
                </div>
            </section>

            <section class="card">
                <div class="label">Historique</div>
                <div class="timeline">{events_html}</div>
            </section>

            <section class="card">
                <div class="label">Application Denkma</div>
                <p class="app-note">
                    Si vous créez un compte avec le numéro du destinataire,
                    Denkma affichera automatiquement les colis liés à ce numéro,
                    avec les détails et le suivi en direct quand une mission est active.
                </p>
                <a class="app-link" href="{safe_app_install_url}">Ouvrir ou télécharger l'application</a>
            </section>

            <div class="footer">© 2026 Denkma - Suivi sécurisé</div>
        </main>
    </body>
    </html>
    """
    return page
