"""
Router tracking : endpoints publics (sans authentification).
"""
import html
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

from config import settings
from fastapi import APIRouter, Request, Response
from fastapi.responses import HTMLResponse

from core.datetime_utils import as_aware_utc
from core.exceptions import not_found_exception
from core.limiter import limiter
from database import db
from services.parcel_service import get_parcel_timeline

router = APIRouter()

_STATUS_LABELS = {
    "created": "Créé",
    "dropped_at_origin_relay": "Déposé au relais",
    "in_transit": "En transit",
    "at_destination_relay": "Arrivé au relais de destination",
    "available_at_relay": "Prêt pour le retrait",
    "out_for_delivery": "En cours de livraison",
    "delivered": "Livré",
    "delivery_failed": "Échec de la livraison",
    "redirected_to_relay": "Redirigé vers un relais",
    "cancelled": "Annulé",
    "expired": "Expiré",
    "returned": "Retourné",
}

_PUBLIC_TRACKING_TERMINAL_STATUSES = {
    "delivered",
    "cancelled",
    "expired",
    "returned",
}

_PUBLIC_RESPONSE_HEADERS = {
    "Cache-Control": "no-store, private, max-age=0",
    "Pragma": "no-cache",
    "X-Robots-Tag": "noindex, nofollow, noarchive",
}


def _serialize_public_event(event: dict) -> dict:
    to_status = event.get("to_status")
    event_type = str(event.get("event_type") or "").strip()
    label = _STATUS_LABELS.get(to_status or "")
    if not label and event_type:
        label = event_type.replace("_", " ").strip().capitalize()
    return {
        "event_type": event_type or None,
        "from_status": event.get("from_status"),
        "to_status": to_status,
        "created_at": event.get("created_at"),
        "label": label or "Mise à jour du colis",
    }


def _format_public_area_label(address: dict | None) -> str | None:
    if not isinstance(address, dict):
        return None
    parts: list[str] = []
    for key in ("district", "city", "commune", "region"):
        value = address.get(key)
        if isinstance(value, str):
            clean = value.strip()
            if clean and clean not in parts:
                parts.append(clean)
    return ", ".join(parts[:2]) if parts else None


def _format_dt(value) -> str:
    if not value:
        return "Non disponible"
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
    latest_public = _serialize_public_event(latest) if latest else {}
    return (
        latest_public.get("label")
        or _STATUS_LABELS.get(parcel.get("status") or "")
        or "Position en cours de mise à jour"
    )


def _app_install_url(parcel: dict) -> str:
    params = {"tracking": parcel.get("tracking_code") or ""}
    return f"{settings.PUBLIC_SITE_URL.rstrip('/')}/app?{urlencode(params)}"


def _parse_public_datetime(value) -> datetime | None:
    if isinstance(value, datetime):
        return as_aware_utc(value)
    if isinstance(value, str):
        try:
            return as_aware_utc(datetime.fromisoformat(value.replace("Z", "+00:00")))
        except ValueError:
            return None
    return None


def _public_tracking_expires_at(
    parcel: dict,
    timeline: list[dict],
) -> datetime | None:
    status = str(parcel.get("status") or "").lower()
    if status not in _PUBLIC_TRACKING_TERMINAL_STATUSES:
        return None

    closed_at = None
    for event in reversed(timeline):
        if event.get("to_status") == status:
            closed_at = _parse_public_datetime(event.get("created_at"))
            if closed_at:
                break
    closed_at = (
        closed_at
        or _parse_public_datetime(parcel.get("updated_at"))
        or _parse_public_datetime(parcel.get("created_at"))
    )
    if not closed_at:
        return None
    return closed_at + timedelta(days=settings.PUBLIC_TRACKING_RETENTION_DAYS)


def _public_tracking_has_expired(
    parcel: dict,
    timeline: list[dict],
    *,
    now: datetime | None = None,
) -> bool:
    expires_at = _public_tracking_expires_at(parcel, timeline)
    current_time = as_aware_utc(now) if now else datetime.now(timezone.utc)
    return bool(expires_at and current_time and current_time >= expires_at)


def _build_public_tracking_payload(parcel: dict, timeline: list[dict]) -> dict:
    expires_at = _public_tracking_expires_at(parcel, timeline)
    return {
        "tracking_code": parcel.get("tracking_code"),
        "status": parcel.get("status"),
        "delivery_mode": parcel.get("delivery_mode"),
        "delivery_mode_label": _delivery_mode_label(parcel.get("delivery_mode")),
        "app_install_url": _app_install_url(parcel),
        "origin_area_label": _format_public_area_label(parcel.get("origin_location")),
        "delivery_area_label": _format_public_area_label(parcel.get("delivery_address")),
        "current_location_label": _current_location_label(parcel, timeline),
        "created_at": parcel.get("created_at"),
        "updated_at": parcel.get("updated_at"),
        "tracking_expires_at": expires_at,
        "events": [_serialize_public_event(evt) for evt in timeline],
    }


async def _load_public_tracking_payload(tracking_code: str) -> dict:
    parcel = await db.parcels.find_one({"tracking_code": tracking_code}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    parcel_id = parcel.get("parcel_id")
    timeline = await get_parcel_timeline(parcel_id) if parcel_id else []
    if _public_tracking_has_expired(parcel, timeline):
        raise not_found_exception("Colis")
    return _build_public_tracking_payload(parcel, timeline)


@router.get("/{tracking_code}", summary="Statut public d'un colis")
@limiter.limit("5/minute")
async def track_parcel(
    tracking_code: str,
    request: Request,
    response: Response,
):
    response.headers.update(_PUBLIC_RESPONSE_HEADERS)
    return await _load_public_tracking_payload(tracking_code)


@router.get("/{tracking_code}/events", summary="Historique public du colis")
@limiter.limit("5/minute")
async def track_parcel_events(
    tracking_code: str,
    request: Request,
    response: Response,
):
    response.headers.update(_PUBLIC_RESPONSE_HEADERS)
    parcel = await db.parcels.find_one(
        {"tracking_code": tracking_code},
        {
            "_id": 0,
            "parcel_id": 1,
            "status": 1,
            "created_at": 1,
            "updated_at": 1,
        },
    )
    if not parcel:
        raise not_found_exception("Colis")

    timeline = await get_parcel_timeline(parcel["parcel_id"])
    if _public_tracking_has_expired(parcel, timeline):
        raise not_found_exception("Colis")
    public_timeline = [_serialize_public_event(evt) for evt in timeline]
    return {"tracking_code": tracking_code, "events": public_timeline}


@router.get("/view/{tracking_code}", response_class=HTMLResponse, summary="Page de suivi Web (sans app)")
@limiter.limit("5/minute")
async def view_parcel_web(tracking_code: str, request: Request):
    parcel = await _load_public_tracking_payload(tracking_code)

    current_status = parcel.get("status", "created")
    status_label = _STATUS_LABELS.get(current_status, current_status)
    safe_tracking_code = html.escape(str(tracking_code))
    safe_status_label = html.escape(str(status_label))
    safe_mode = html.escape(str(parcel.get("delivery_mode_label") or "Non renseigné"))
    safe_current_location = html.escape(
        str(parcel.get("current_location_label") or "En attente de mise à jour")
    )
    safe_app_install_url = html.escape(
        str(parcel.get("app_install_url") or f"{settings.PUBLIC_SITE_URL.rstrip('/')}/app"),
        quote=True,
    )
    safe_origin = html.escape(
        str(parcel.get("origin_area_label") or "Zone non renseignée")
    )
    safe_delivery = html.escape(
        str(parcel.get("delivery_area_label") or "Zone non renseignée")
    )
    safe_created_at = html.escape(_format_dt(parcel.get("created_at")))
    safe_updated_at = html.escape(_format_dt(parcel.get("updated_at")))
    expires_at = parcel.get("tracking_expires_at")
    retention_html = (
        f'<div class="retention">Ce lien public sera désactivé le '
        f'{html.escape(_format_dt(expires_at))}.</div>'
        if expires_at
        else '<div class="retention">Ce lien public reste actif pendant le suivi du colis.</div>'
    )

    events_html = ""
    for evt in reversed(parcel.get("events", [])):
        event_time = html.escape(_format_dt(evt.get("created_at")))
        event_title = html.escape(str(evt.get("label") or "Mise à jour du colis"))
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
        <meta name="robots" content="noindex,nofollow,noarchive">
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
                background: var(--bg);
                color: var(--text);
                padding: 18px;
            }}
            .container {{ width: 100%; max-width: 760px; margin: 0 auto; }}
            .header {{ display: flex; align-items: center; justify-content: space-between; margin: 8px 0 22px; }}
            .logo {{ font-size: 24px; font-weight: 800; color: var(--primary); }}
            .badge {{ display: inline-flex; padding: 7px 12px; background: var(--soft); color: var(--primary); border-radius: 999px; font-weight: 700; font-size: 13px; }}
            .card {{ background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 22px; box-shadow: 0 10px 28px rgba(22, 72, 43, 0.07); margin-bottom: 16px; }}
            h1 {{ font-size: clamp(28px, 8vw, 48px); margin: 16px 0 8px; letter-spacing: 0; }}
            .status {{ font-size: 20px; font-weight: 700; display: flex; gap: 10px; align-items: center; }}
            .status-dot {{ width: 12px; height: 12px; border-radius: 50%; background: var(--primary); flex: 0 0 auto; }}
            .current {{ margin-top: 16px; padding: 14px; border-radius: 8px; background: #f7faf8; color: var(--muted); }}
            .grid {{ display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); column-gap: 22px; }}
            .info {{ border-bottom: 1px solid var(--line); padding: 14px 0; }}
            .label {{ font-size: 12px; text-transform: uppercase; letter-spacing: 0; color: var(--muted); margin-bottom: 6px; }}
            .value {{ font-weight: 700; line-height: 1.35; overflow-wrap: anywhere; }}
            .timeline {{ margin-top: 8px; position: relative; padding-left: 28px; }}
            .timeline::before {{ content: ''; position: absolute; left: 9px; top: 8px; bottom: 8px; width: 2px; background: var(--line); }}
            .event {{ position: relative; margin-bottom: 18px; }}
            .event-dot {{ position: absolute; left: -24px; top: 5px; width: 10px; height: 10px; background: var(--primary); border-radius: 50%; border: 3px solid white; box-shadow: 0 0 0 2px var(--primary); }}
            .event-time {{ font-size: 12px; color: var(--muted); margin-bottom: 4px; }}
            .event-title {{ font-weight: 700; }}
            .app-link {{ display: block; text-decoration: none; background: var(--primary); color: white; border-radius: 8px; padding: 16px; font-weight: 800; text-align: center; margin-top: 14px; }}
            .app-note {{ color: var(--muted); line-height: 1.5; margin: 0; }}
            .retention {{ color: var(--muted); font-size: 12px; line-height: 1.5; margin-top: 12px; }}
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
                <div class="status"><span class="status-dot"></span><span>{safe_current_location}</span></div>
                <div class="current">Dernière mise à jour : {safe_updated_at}</div>
                {retention_html}
                <a class="app-link" href="{safe_app_install_url}">Télécharger l'application Denkma</a>
            </section>

            <section class="card">
                <div class="grid">
                    <div class="info"><div class="label">Mode</div><div class="value">{safe_mode}</div></div>
                    <div class="info"><div class="label">Créé le</div><div class="value">{safe_created_at}</div></div>
                    <div class="info"><div class="label">Zone de collecte</div><div class="value">{safe_origin}</div></div>
                    <div class="info"><div class="label">Zone de livraison</div><div class="value">{safe_delivery}</div></div>
                </div>
            </section>

            <section class="card">
                <div class="label">Historique</div>
                <div class="timeline">{events_html}</div>
            </section>

            <div class="footer">© 2026 Denkma - Suivi sécurisé</div>
        </main>
    </body>
    </html>
    """
    return HTMLResponse(page, headers=_PUBLIC_RESPONSE_HEADERS)
