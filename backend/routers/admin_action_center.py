"""
Admin Action Center : agrège tout ce qui demande une action admin.

Un seul endpoint alimente la sidebar (badges), la section "À traiter" du home,
et sert de source de vérité pour les compteurs d'urgence. Chaque item retourne
assez d'infos pour être traité inline sans navigation supplémentaire.
"""
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends, Query

from core.dependencies import require_role
from core.exceptions import not_found_exception
from core.date_filters import parse_date_range
from database import db
from models.common import UserRole, ParcelStatus
from services.admin_events_service import (
    count_unread,
    list_admin_events,
    mark_all_read,
    mark_event_read,
)

router = APIRouter()

require_admin_dep = require_role(UserRole.ADMIN, UserRole.SUPERADMIN)


# SLA par catégorie (en heures). Au-delà de "warning" → orange, au-delà de "critical" → rouge.
DEFAULT_SLAS = {
    "payout": {"warning": 24, "critical": 48},
    "application": {"warning": 24, "critical": 72},
    "incident": {"warning": 1, "critical": 4},
    "mission_delay": {"warning": 3, "critical": 6},
    "signal_lost": {"warning": 0.33, "critical": 1},  # 20 min / 1 h
    "stale_parcel": {"warning": 168, "critical": 336},  # 7 j / 14 j
    "payment_blocked": {"warning": 2, "critical": 12},
    "support": {"warning": 1, "critical": 6},
    "dispute": {"warning": 2, "critical": 24},
}


def _age_hours(ts: Optional[datetime], now: datetime) -> float:
    if not ts:
        return 0.0
    if isinstance(ts, str):
        try:
            ts = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except ValueError:
            return 0.0
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return (now - ts).total_seconds() / 3600.0


def _urgency(age_h: float, sla: dict[str, float]) -> str:
    if age_h >= sla["critical"]:
        return "critical"
    if age_h >= sla["warning"]:
        return "warning"
    return "normal"


async def _enrich_user_names(items: list[dict[str, Any]], id_key: str, out_key: str) -> None:
    ids = {it.get(id_key) for it in items if it.get(id_key)}
    if not ids:
        return
    cursor = db.users.find(
        {"user_id": {"$in": list(ids)}},
        {"_id": 0, "user_id": 1, "name": 1, "phone": 1, "full_name": 1},
    )
    index = {u["user_id"]: u async for u in cursor}
    for it in items:
        u = index.get(it.get(id_key))
        if u:
            it[out_key] = u.get("full_name") or u.get("name") or u.get("phone")


async def _enrich_parcel_tracking(items: list[dict[str, Any]]) -> None:
    pids = {it.get("parcel_id") for it in items if it.get("parcel_id")}
    if not pids:
        return
    cursor = db.parcels.find(
        {"parcel_id": {"$in": list(pids)}},
        {"_id": 0, "parcel_id": 1, "tracking_code": 1, "status": 1},
    )
    index = {p["parcel_id"]: p async for p in cursor}
    for it in items:
        p = index.get(it.get("parcel_id"))
        if p:
            it.setdefault("tracking_code", p.get("tracking_code"))
            it.setdefault("parcel_status", p.get("status"))


# ── Récupération par catégorie ───────────────────────────────────────────────

async def _fetch_payouts(now: datetime) -> list[dict[str, Any]]:
    sla = DEFAULT_SLAS["payout"]
    cursor = db.payout_requests.find({"status": "pending"}, {"_id": 0}).sort("created_at", 1)
    items: list[dict[str, Any]] = []
    async for p in cursor:
        age_h = _age_hours(p.get("created_at"), now)
        items.append({
            "id": p["payout_id"],
            "payout_id": p["payout_id"],
            "owner_id": p.get("owner_id"),
            "amount": p.get("amount"),
            "method": p.get("method"),
            "phone": p.get("phone"),
            "created_at": p.get("created_at"),
            "age_hours": round(age_h, 2),
            "urgency": _urgency(age_h, sla),
            "href": "/dashboard/payouts",
        })
    await _enrich_user_names(items, "owner_id", "owner_name")
    return items


async def _fetch_applications(now: datetime) -> list[dict[str, Any]]:
    sla = DEFAULT_SLAS["application"]
    cursor = db.users.find(
        {
            "role": UserRole.CLIENT.value,
            "kyc_status": {"$in": ["pending", "verified"]},
        },
        {"_id": 0, "user_id": 1, "full_name": 1, "name": 1, "phone": 1, "kyc_status": 1, "created_at": 1, "updated_at": 1},
    ).sort("updated_at", 1)
    items: list[dict[str, Any]] = []
    async for u in cursor:
        ref_date = u.get("updated_at") or u.get("created_at")
        age_h = _age_hours(ref_date, now)
        items.append({
            "id": u["user_id"],
            "user_id": u["user_id"],
            "full_name": u.get("full_name") or u.get("name"),
            "phone": u.get("phone"),
            "kyc_status": u.get("kyc_status"),
            "submitted_at": ref_date,
            "age_hours": round(age_h, 2),
            "urgency": _urgency(age_h, sla),
            "href": "/dashboard/applications",
        })
    return items


async def _fetch_incidents(now: datetime) -> list[dict[str, Any]]:
    sla = DEFAULT_SLAS["incident"]
    cursor = db.parcels.find(
        {"status": ParcelStatus.INCIDENT_REPORTED.value},
        {"_id": 0, "parcel_id": 1, "tracking_code": 1, "assigned_driver_id": 1, "updated_at": 1, "created_at": 1, "status": 1},
    ).sort("updated_at", -1)
    items: list[dict[str, Any]] = []
    async for p in cursor:
        ref_date = p.get("updated_at") or p.get("created_at")
        age_h = _age_hours(ref_date, now)
        items.append({
            "id": p["parcel_id"],
            "parcel_id": p["parcel_id"],
            "tracking_code": p.get("tracking_code"),
            "driver_id": p.get("assigned_driver_id"),
            "reported_at": ref_date,
            "age_hours": round(age_h, 2),
            "urgency": _urgency(age_h, sla),
            "parcel_status": p.get("status"),
            "href": f"/dashboard/parcels/{p['parcel_id']}",
        })
    await _enrich_user_names(items, "driver_id", "driver_name")
    return items


async def _fetch_mission_anomalies(now: datetime) -> list[dict[str, Any]]:
    signal_sla = DEFAULT_SLAS["signal_lost"]
    delay_sla = DEFAULT_SLAS["mission_delay"]
    signal_cutoff = now - timedelta(minutes=20)
    delay_cutoff = now - timedelta(hours=delay_sla["warning"])

    seen: dict[str, dict[str, Any]] = {}

    async for m in db.delivery_missions.find(
        {"status": {"$in": ["assigned", "in_progress"]}, "location_updated_at": {"$lt": signal_cutoff}},
        {"_id": 0},
    ):
        mid = m["mission_id"]
        ref_date = m.get("location_updated_at") or m.get("assigned_at")
        age_h = _age_hours(ref_date, now)
        seen[mid] = {
            "id": mid,
            "mission_id": mid,
            "parcel_id": m.get("parcel_id"),
            "driver_id": m.get("driver_id"),
            "type": "signal_lost",
            "last_seen": ref_date,
            "age_hours": round(age_h, 2),
            "urgency": _urgency(age_h, signal_sla),
            "mission_status": m.get("status"),
            "href": "/dashboard/fleet?filter=signal_lost",
        }

    async for m in db.delivery_missions.find(
        {"status": {"$in": ["assigned", "in_progress"]}, "assigned_at": {"$lt": delay_cutoff}},
        {"_id": 0},
    ):
        mid = m["mission_id"]
        if mid in seen:
            continue
        age_h = _age_hours(m.get("assigned_at"), now)
        seen[mid] = {
            "id": mid,
            "mission_id": mid,
            "parcel_id": m.get("parcel_id"),
            "driver_id": m.get("driver_id"),
            "type": "critical_delay",
            "assigned_at": m.get("assigned_at"),
            "age_hours": round(age_h, 2),
            "urgency": _urgency(age_h, delay_sla),
            "mission_status": m.get("status"),
            "href": "/dashboard/stale",
        }

    items = list(seen.values())
    items.sort(key=lambda x: x["age_hours"], reverse=True)
    await _enrich_user_names(items, "driver_id", "driver_name")
    await _enrich_parcel_tracking(items)
    return items


async def _fetch_stale_parcels(now: datetime) -> list[dict[str, Any]]:
    sla = DEFAULT_SLAS["stale_parcel"]
    cutoff = now - timedelta(hours=sla["warning"])
    stale_statuses = [
        ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value,
        ParcelStatus.AT_DESTINATION_RELAY.value,
        ParcelStatus.AVAILABLE_AT_RELAY.value,
        ParcelStatus.REDIRECTED_TO_RELAY.value,
    ]
    cursor = db.parcels.find(
        {"status": {"$in": stale_statuses}, "updated_at": {"$lt": cutoff}},
        {"_id": 0, "parcel_id": 1, "tracking_code": 1, "status": 1, "updated_at": 1, "destination_relay_id": 1, "origin_relay_id": 1},
    ).sort("updated_at", 1)
    items: list[dict[str, Any]] = []
    async for p in cursor:
        age_h = _age_hours(p.get("updated_at"), now)
        items.append({
            "id": p["parcel_id"],
            "parcel_id": p["parcel_id"],
            "tracking_code": p.get("tracking_code"),
            "parcel_status": p.get("status"),
            "last_move_at": p.get("updated_at"),
            "age_hours": round(age_h, 2),
            "age_days": round(age_h / 24, 1),
            "urgency": _urgency(age_h, sla),
            "href": "/dashboard/stale",
        })
    return items


async def _fetch_payment_blocked(now: datetime) -> list[dict[str, Any]]:
    sla = DEFAULT_SLAS["payment_blocked"]
    statuses = [
        ParcelStatus.AT_DESTINATION_RELAY.value,
        ParcelStatus.AVAILABLE_AT_RELAY.value,
        ParcelStatus.OUT_FOR_DELIVERY.value,
        ParcelStatus.REDIRECTED_TO_RELAY.value,
    ]
    cursor = db.parcels.find(
        {
            "status": {"$in": statuses},
            "payment_status": {"$ne": "paid"},
            "payment_override": {"$ne": True},
        },
        {"_id": 0, "parcel_id": 1, "tracking_code": 1, "status": 1, "updated_at": 1, "quoted_price": 1, "payment_status": 1},
    ).sort("updated_at", 1).limit(200)
    items: list[dict[str, Any]] = []
    async for p in cursor:
        age_h = _age_hours(p.get("updated_at"), now)
        items.append({
            "id": p["parcel_id"],
            "parcel_id": p["parcel_id"],
            "tracking_code": p.get("tracking_code"),
            "parcel_status": p.get("status"),
            "payment_status": p.get("payment_status"),
            "amount": p.get("quoted_price"),
            "blocked_since": p.get("updated_at"),
            "age_hours": round(age_h, 2),
            "urgency": _urgency(age_h, sla),
            "href": f"/dashboard/parcels/{p['parcel_id']}",
        })
    return items


async def _fetch_support(now: datetime) -> list[dict[str, Any]]:
    sla = DEFAULT_SLAS["support"]
    if "whatsapp_support_conversations" not in await db.list_collection_names():
        return []
    cursor = db.whatsapp_support_conversations.find(
        {"status": {"$in": ["pending", "open"]}},
        {"_id": 0, "conversation_id": 1, "phone": 1, "full_name": 1, "status": 1, "last_message_at": 1, "updated_at": 1, "last_incoming_preview": 1},
    ).sort("last_message_at", -1).limit(200)
    items: list[dict[str, Any]] = []
    async for c in cursor:
        ref_date = c.get("last_message_at") or c.get("updated_at")
        age_h = _age_hours(ref_date, now)
        items.append({
            "id": c["conversation_id"],
            "conversation_id": c["conversation_id"],
            "phone": c.get("phone"),
            "full_name": c.get("full_name"),
            "status": c.get("status"),
            "last_message_at": ref_date,
            "preview": c.get("last_incoming_preview"),
            "age_hours": round(age_h, 2),
            "urgency": _urgency(age_h, sla),
            "href": f"/dashboard/support?c={c['conversation_id']}",
        })
    return items


async def _fetch_disputes(now: datetime) -> list[dict[str, Any]]:
    sla = DEFAULT_SLAS["dispute"]
    cursor = db.parcels.find(
        {"status": ParcelStatus.DISPUTED.value},
        {"_id": 0, "parcel_id": 1, "tracking_code": 1, "updated_at": 1, "status": 1},
    ).sort("updated_at", -1).limit(200)
    items: list[dict[str, Any]] = []
    async for p in cursor:
        age_h = _age_hours(p.get("updated_at"), now)
        items.append({
            "id": p["parcel_id"],
            "parcel_id": p["parcel_id"],
            "tracking_code": p.get("tracking_code"),
            "opened_at": p.get("updated_at"),
            "age_hours": round(age_h, 2),
            "urgency": _urgency(age_h, sla),
            "href": f"/dashboard/parcels/{p['parcel_id']}",
        })
    return items


# ── Endpoint principal ──────────────────────────────────────────────────────

@router.get("/action-center", summary="Centre d'action admin : compteurs + items urgents")
async def admin_action_center(_admin=Depends(require_admin_dep)):
    """
    Agrège tout ce qui demande une action admin en un seul appel.
    Utilisé par la sidebar (badges) et la section "À traiter" du dashboard home.

    Renvoie pour chaque catégorie :
      - `count` : total d'items en attente
      - `urgent_count` : items dont l'âge dépasse le SLA "critical"
      - `warning_count` : items dont l'âge dépasse le SLA "warning"
      - `items` : liste complète triée par urgence décroissante (pas de cap)
    """
    now = datetime.now(timezone.utc)

    payouts = await _fetch_payouts(now)
    applications = await _fetch_applications(now)
    incidents = await _fetch_incidents(now)
    anomalies = await _fetch_mission_anomalies(now)
    stale = await _fetch_stale_parcels(now)
    payment_blocked = await _fetch_payment_blocked(now)
    support = await _fetch_support(now)
    disputes = await _fetch_disputes(now)

    def _pack(items: list[dict[str, Any]], label: str, href: str) -> dict[str, Any]:
        items_sorted = sorted(items, key=lambda x: x["age_hours"], reverse=True)
        return {
            "label": label,
            "href": href,
            "count": len(items_sorted),
            "urgent_count": sum(1 for it in items_sorted if it["urgency"] == "critical"),
            "warning_count": sum(1 for it in items_sorted if it["urgency"] == "warning"),
            "items": items_sorted,
        }

    categories = {
        "payouts": _pack(payouts, "Retraits à valider", "/dashboard/payouts"),
        "applications": _pack(applications, "Candidatures à traiter", "/dashboard/applications"),
        "incidents": _pack(incidents, "Incidents signalés", "/dashboard/parcels?status=incident_reported"),
        "anomalies": _pack(anomalies, "Anomalies flotte", "/dashboard/anomalies"),
        "stale_parcels": _pack(stale, "Colis stagnants", "/dashboard/stale"),
        "payment_blocked": _pack(payment_blocked, "Paiements bloqués", "/dashboard/parcels?payment_blocked=true"),
        "support": _pack(support, "Support WhatsApp", "/dashboard/support"),
        "disputes": _pack(disputes, "Litiges ouverts", "/dashboard/parcels?status=disputed"),
    }

    total = sum(c["count"] for c in categories.values())
    total_urgent = sum(c["urgent_count"] for c in categories.values())
    total_warning = sum(c["warning_count"] for c in categories.values())

    return {
        "generated_at": now,
        "total": total,
        "total_urgent": total_urgent,
        "total_warning": total_warning,
        "categories": categories,
        "sla": DEFAULT_SLAS,
    }


# ── Flux cloche 🔔 ──────────────────────────────────────────────────────────

def _admin_id(admin: Any) -> str:
    if isinstance(admin, dict):
        return admin.get("user_id") or admin.get("admin_id") or "admin"
    return "admin"


@router.get("/events", summary="Flux d'événements admin (cloche)")
async def admin_events_feed(
    limit: int = Query(50, ge=1, le=200),
    before: Optional[str] = Query(None, description="ISO timestamp pour paginer avant"),
    from_date: Optional[str] = Query(None, description="Date début YYYY-MM-DD (UTC)"),
    to_date: Optional[str] = Query(None, description="Date fin YYYY-MM-DD (UTC)"),
    unread_only: bool = False,
    _admin=Depends(require_admin_dep),
):
    before_dt: Optional[datetime] = None
    if before:
        try:
            before_dt = datetime.fromisoformat(before.replace("Z", "+00:00"))
        except ValueError:
            before_dt = None

    range_start, range_end = parse_date_range(from_date, to_date)
    # Combine before/to_date — on prend la borne la plus restrictive.
    if range_end:
        before_dt = range_end if not before_dt else min(before_dt, range_end)

    admin_id = _admin_id(_admin)
    events = await list_admin_events(
        admin_id,
        limit=limit,
        before_created_at=before_dt,
        after_created_at=range_start,
        unread_only=unread_only,
    )
    unread = await count_unread(admin_id)
    return {"events": events, "unread_count": unread}


@router.get("/events/unread-count", summary="Nombre d'événements non lus")
async def admin_events_unread_count(_admin=Depends(require_admin_dep)):
    return {"unread_count": await count_unread(_admin_id(_admin))}


@router.post("/events/{event_id}/read", summary="Marquer un événement comme lu")
async def admin_event_mark_read(event_id: str, _admin=Depends(require_admin_dep)):
    ok = await mark_event_read(_admin_id(_admin), event_id)
    if not ok:
        raise not_found_exception("Événement")
    return {"ok": True, "unread_count": await count_unread(_admin_id(_admin))}


@router.post("/events/read-all", summary="Marquer tous les événements comme lus")
async def admin_events_mark_all_read(_admin=Depends(require_admin_dep)):
    marked = await mark_all_read(_admin_id(_admin))
    return {"marked": marked, "unread_count": 0}
