"""
Helpers communs pour filtrer par intervalle de dates sur les endpoints admin.

Convention : les paramètres `from_date` et `to_date` sont des dates ISO (YYYY-MM-DD)
interprétées en UTC. `from_date` = 00:00:00 inclusif, `to_date` = 23:59:59.999 inclusif.
Si seul `from_date` est fourni, on couvre juste ce jour-là. Si seul `to_date` est fourni,
on couvre tout jusqu'à la fin de ce jour. Vide → pas de filtre.
"""
from __future__ import annotations

from datetime import datetime, time, timezone
from typing import Optional

from core.exceptions import bad_request_exception


def _parse_iso_date(raw: str, field: str) -> datetime:
    try:
        # Accepte "2026-04-22" ou "2026-04-22T12:00:00+00:00".
        if "T" in raw:
            parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        else:
            parsed = datetime.strptime(raw, "%Y-%m-%d")
    except ValueError:
        raise bad_request_exception(
            f"Paramètre {field} invalide (format attendu YYYY-MM-DD)"
        )
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def parse_date_range(
    from_date: Optional[str],
    to_date: Optional[str],
) -> tuple[Optional[datetime], Optional[datetime]]:
    """Retourne un couple (start, end) ou (None, None) si aucun filtre."""
    if not from_date and not to_date:
        return None, None

    start: Optional[datetime] = None
    end: Optional[datetime] = None

    if from_date:
        f = _parse_iso_date(from_date, "from_date")
        start = datetime.combine(f.date(), time.min, tzinfo=timezone.utc)

    if to_date:
        t = _parse_iso_date(to_date, "to_date")
        end = datetime.combine(t.date(), time.max, tzinfo=timezone.utc)

    # Si seul from_date : filtre = journée entière de from_date.
    if start and not end:
        end = datetime.combine(start.date(), time.max, tzinfo=timezone.utc)
    # Si seul to_date : pas de borne basse.

    if start and end and end < start:
        raise bad_request_exception("to_date doit être postérieur à from_date")

    return start, end


def date_range_query(
    from_date: Optional[str],
    to_date: Optional[str],
    field: str = "created_at",
) -> dict:
    """Construit la clause MongoDB à fusionner dans le `find`."""
    start, end = parse_date_range(from_date, to_date)
    if not start and not end:
        return {}
    clause: dict = {}
    if start:
        clause["$gte"] = start
    if end:
        clause["$lte"] = end
    return {field: clause}
