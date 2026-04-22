"""
Flux d'événements pour la cloche admin.

Chaque événement critique du système (payout demandé, incident signalé, litige ouvert,
candidature driver/relay, etc.) écrit ici un document immutable. Le dashboard admin lit
ce flux pour la cloche, affiche le compteur de non lus par admin, et peut "marquer lu".

L'état "lu" est stocké comme un set d'admin_id sur chaque événement → chaque admin a
son propre compteur de non lus sans collection séparée.
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from database import db

logger = logging.getLogger(__name__)


# Types d'événements (constantes pour éviter les typos).
class AdminEventType:
    PAYOUT_REQUESTED = "payout_requested"
    PAYOUT_APPROVED = "payout_approved"
    PAYOUT_REJECTED = "payout_rejected"
    INCIDENT_REPORTED = "incident_reported"
    PARCEL_DISPUTED = "parcel_disputed"
    APPLICATION_SUBMITTED = "application_submitted"
    MISSION_CRITICAL_DELAY = "mission_critical_delay"
    SIGNAL_LOST = "signal_lost"
    PARCEL_STALE = "parcel_stale"
    PARCEL_REDIRECTED = "parcel_redirected"
    PARCEL_CANCELLED = "parcel_cancelled"
    MISSION_RELEASED = "mission_released"


# Sévérité : critical → rouge + son, warning → orange, info → gris.
SEVERITY_BY_TYPE: dict[str, str] = {
    AdminEventType.PAYOUT_REQUESTED: "warning",
    AdminEventType.PAYOUT_APPROVED: "info",
    AdminEventType.PAYOUT_REJECTED: "info",
    AdminEventType.INCIDENT_REPORTED: "critical",
    AdminEventType.PARCEL_DISPUTED: "critical",
    AdminEventType.APPLICATION_SUBMITTED: "info",
    AdminEventType.MISSION_CRITICAL_DELAY: "warning",
    AdminEventType.SIGNAL_LOST: "warning",
    AdminEventType.PARCEL_STALE: "info",
    AdminEventType.PARCEL_REDIRECTED: "warning",
    AdminEventType.PARCEL_CANCELLED: "info",
    AdminEventType.MISSION_RELEASED: "info",
}


def _event_id() -> str:
    return f"adm_{uuid.uuid4().hex[:14]}"


async def record_admin_event(
    event_type: str,
    title: str,
    message: str = "",
    *,
    severity: Optional[str] = None,
    href: Optional[str] = None,
    metadata: Optional[dict[str, Any]] = None,
) -> str:
    """
    Écrit un événement admin dans `admin_events`. Non bloquant : en cas d'erreur
    on log et on retourne une chaîne vide pour ne pas casser l'appelant.
    """
    try:
        now = datetime.now(timezone.utc)
        doc = {
            "event_id": _event_id(),
            "event_type": event_type,
            "severity": severity or SEVERITY_BY_TYPE.get(event_type, "info"),
            "title": title,
            "message": message,
            "href": href,
            "metadata": metadata or {},
            "created_at": now,
            "read_by": [],  # liste des admin_id ayant marqué comme lu
        }
        await db.admin_events.insert_one(doc)
        return doc["event_id"]
    except Exception as exc:
        logger.warning("record_admin_event failed: %s", exc)
        return ""


async def list_admin_events(
    admin_id: str,
    *,
    limit: int = 50,
    before_created_at: Optional[datetime] = None,
    after_created_at: Optional[datetime] = None,
    unread_only: bool = False,
) -> list[dict[str, Any]]:
    query: dict[str, Any] = {}
    date_clause: dict[str, Any] = {}
    if before_created_at:
        date_clause["$lt"] = before_created_at
    if after_created_at:
        date_clause["$gte"] = after_created_at
    if date_clause:
        query["created_at"] = date_clause
    if unread_only:
        query["read_by"] = {"$ne": admin_id}

    cursor = db.admin_events.find(query, {"_id": 0}).sort("created_at", -1).limit(limit)
    events: list[dict[str, Any]] = []
    async for ev in cursor:
        ev["is_read"] = admin_id in (ev.get("read_by") or [])
        ev.pop("read_by", None)
        events.append(ev)
    return events


async def count_unread(admin_id: str) -> int:
    return await db.admin_events.count_documents({"read_by": {"$ne": admin_id}})


async def mark_event_read(admin_id: str, event_id: str) -> bool:
    result = await db.admin_events.update_one(
        {"event_id": event_id},
        {"$addToSet": {"read_by": admin_id}},
    )
    return result.matched_count > 0


async def mark_all_read(admin_id: str) -> int:
    result = await db.admin_events.update_many(
        {"read_by": {"$ne": admin_id}},
        {"$addToSet": {"read_by": admin_id}},
    )
    return result.modified_count
