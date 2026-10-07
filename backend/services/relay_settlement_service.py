from decimal import Decimal

from core.exceptions import DeliveryCommissionDataError
from core.delivery_destination import effective_delivery_mode, effective_relay_id
from models.common import DeliveryMode, ParcelStatus
from services.wallet_service import build_relay_financial_summary, resolve_delivery_commission_mode


RELAY_FINANCIAL_STATUSES = {
    "in_transit", "at_destination_relay", "available_at_relay", "out_for_delivery",
    "delivered", "redirected_to_relay", "suspended", "disputed",
}
SETTLEMENT_STATUSES = {"pending", "declared", "validated", "rejected"}
SETTLEMENT_DIRECTIONS = ("to_relay", "to_denkma", "to_driver")
TERMINAL_STATUSES = {"cancelled", "expired", "returned"}
FINANCIAL_PROJECTION = {
    "_id": 0, "parcel_id": 1, "tracking_code": 1, "status": 1,
    "delivery_mode": 1, "mode": 1, "quoted_price": 1, "paid_price": 1,
    "delivery_commissions_enabled": 1, "commission_rules_snapshot": 1,
    "commission_rules": 1, "origin_relay_id": 1, "destination_relay_id": 1,
    "redirect_relay_id": 1, "assigned_driver_id": 1, "relay_settlement": 1,
    "created_at": 1, "updated_at": 1,
    "financial_contract": 1, "financial_rounding": 1, "redirect_relay_commission_xof": 1,
    "recipient_collection_plan": 1,
    "recipient_collection_remittances": 1,
}


def settlement_actions(parcel: dict) -> list[dict]:
    mode = resolve_delivery_commission_mode(parcel)
    if mode.startswith("relay_to_") and not parcel.get("origin_relay_id"):
        raise ValueError("Le relais de départ est manquant.")
    if effective_delivery_mode(parcel).endswith("_to_relay") and not effective_relay_id(parcel):
        raise ValueError("Le relais d’arrivée est manquant.")
    relay_ids = list(dict.fromkeys(filter(None, (
        parcel.get("origin_relay_id"),
        parcel.get("redirect_relay_id") or parcel.get("destination_relay_id"),
        *(receipt.get("collector_id") for receipt in (parcel.get("recipient_collection_plan") or {}).get("receipts", []) if receipt.get("collector") == "relay"),
    ))))
    settlement = parcel.get("relay_settlement") or {}
    if not isinstance(settlement, dict):
        raise ValueError("Les informations de règlement sont invalides.")
    result = []
    for relay_id in relay_ids:
        summary = build_relay_financial_summary(parcel, relay_id)
        for item in summary["actions"]:
            if item["amount_xof"] <= 0:
                continue
            action = item["key"]
            if action == "relay_commission":
                action = item["settlement_action"]
            direction = "to_relay" if item["key"] == "relay_commission" else "to_denkma" if action in {"denkma_payment", "recipient_collection_payment"} else "to_driver"
            field = f"{action}_status"
            status = item["status"] if action == "recipient_collection_payment" else settlement.get(field) or "pending"
            record = (parcel.get("recipient_collection_remittances") or {}).get(relay_id, {}) if action == "recipient_collection_payment" else settlement
            record_field = "status" if action == "recipient_collection_payment" else field
            if not isinstance(status, str) or status not in SETTLEMENT_STATUSES:
                raise ValueError("Le statut d’un règlement est invalide.")
            due = parcel.get("status") == ParcelStatus.DELIVERED.value if direction == "to_relay" else parcel.get("status") in RELAY_FINANCIAL_STATUSES
            # Une déclaration existante reste à contrôler même après annulation ou retour.
            due = due or status in {"declared", "validated", "rejected"}
            due = due or action == "recipient_collection_payment"
            if not due and parcel.get("status") in TERMINAL_STATUSES:
                continue
            result.append({
                "action": action, "relay_id": relay_id, "direction": direction,
                "label": {
                    "driver_payment": "Relais → livreur",
                    "denkma_payment": "Relais → Denkma",
                     "origin_relay_payment": "Denkma → relais de départ",
                     "destination_relay_payment": "Denkma → relais d’arrivée",
                    "recipient_collection_payment": "Encaissement destinataire → Denkma",
                }[action],
                "amount_xof": round(item["amount_xof"], 2), "status": status,
                "stage": "due" if due else "upcoming",
                "can_validate": due and (status == "declared" or direction == "to_relay" and status in {"pending", "rejected"}),
                "can_reject": due and status == "declared",
                "parcel_id": parcel["parcel_id"],
                "tracking_code": parcel.get("tracking_code") or parcel["parcel_id"],
                "parcel_status": parcel.get("status"), "delivery_mode": summary["mode"],
                "driver_id": parcel.get("assigned_driver_id") if direction == "to_driver" else None,
                "updated_at": parcel.get("updated_at"),
                "declared_at": record.get(f"{record_field}_declared_at"),
                "reviewed_at": record.get(f"{record_field}_validated_at"),
                "reviewed_by": record.get(f"{record_field}_validated_by"),
                "note": record.get(f"{record_field}_note"),
                "funding_review_required": action == "destination_relay_payment" and summary.get("redirect_funding_review_required", False),
                "settlement_field": item.get("settlement_field") or f"relay_settlement.{field}",
                "validated_amount_xof": item.get("validated_amount_xof", 0),
            })
    return result


def _parcel_query(relay_id: str | None = None) -> dict:
    if relay_id:
        return {"$or": [{key: relay_id} for key in ("origin_relay_id", "destination_relay_id", "redirect_relay_id")] + [{"recipient_collection_plan.receipts": {"$elemMatch": {"collector": "relay", "collector_id": relay_id}}}]}
    relay_modes = [mode.value for mode in DeliveryMode if mode != DeliveryMode.HOME_TO_HOME]
    return {"$or": [
        *[{key: {"$exists": True, "$nin": [None, ""]}} for key in ("origin_relay_id", "destination_relay_id", "redirect_relay_id")],
        {"delivery_mode": {"$in": relay_modes}}, {"mode": {"$in": relay_modes}},
        {"recipient_collection_plan.receipts.collector": "relay"},
    ]}


def empty_totals() -> dict:
    return {
        **{f"{direction}_xof": 0 for direction in SETTLEMENT_DIRECTIONS},
        **{f"{direction}_declared_xof": 0 for direction in SETTLEMENT_DIRECTIONS},
        **{f"{direction}_validated_xof": 0 for direction in SETTLEMENT_DIRECTIONS},
        "upcoming_to_relay_xof": 0, "pending_count": 0, "declared_count": 0,
        "rejected_count": 0, "outstanding_count": 0, "unavailable_count": 0,
    }


def _add_action(totals: dict, action: dict) -> None:
    direction, status = action["direction"], action["status"]
    amount = Decimal(str(action["amount_xof"]))
    previously_validated = Decimal(str(action.get("validated_amount_xof") or 0))
    def add(key):
        totals[key] = Decimal(str(totals[key])) + amount
    if action["stage"] == "upcoming":
        if direction == "to_relay":
            add("upcoming_to_relay_xof")
        return
    if status == "validated":
        add(f"{direction}_validated_xof")
        return
    if previously_validated:
        key = f"{direction}_validated_xof"
        totals[key] = Decimal(str(totals[key])) + previously_validated
    add(f"{direction}_xof")
    totals["outstanding_count"] += 1
    totals[f"{status}_count"] += 1
    if status == "declared":
        add(f"{direction}_declared_xof")


def _serialize_totals(totals: dict) -> dict:
    return {key: float(round(value, 2)) if isinstance(value, Decimal) else value for key, value in totals.items()}


async def settlement_overview(database, *, search: str = "", skip: int = 0, limit: int = 20) -> dict:
    totals, relay_totals = empty_totals(), {}
    async for parcel in database.parcels.find(_parcel_query(), FINANCIAL_PROJECTION):
        try:
            actions = settlement_actions(parcel)
        except (DeliveryCommissionDataError, ValueError):
            totals["unavailable_count"] += 1
            for relay_id in set(filter(None, (parcel.get("origin_relay_id"), parcel.get("redirect_relay_id") or parcel.get("destination_relay_id")))):
                entry = relay_totals.setdefault(relay_id, {"relay_id": relay_id, **empty_totals()})
                entry["unavailable_count"] += 1
            continue
        for action in actions:
            relay_id = action["relay_id"]
            entry = relay_totals.setdefault(relay_id, {"relay_id": relay_id, **empty_totals()})
            _add_action(totals, action)
            _add_action(entry, action)
    relays = {}
    async for relay in database.relay_points.find({}, {"_id": 0, "relay_id": 1, "name": 1, "is_active": 1}):
        if relay.get("relay_id"):
            relays[relay["relay_id"]] = relay
            relay_totals.setdefault(relay["relay_id"], {"relay_id": relay["relay_id"], **empty_totals()})
    rows = []
    for relay_id, amounts in relay_totals.items():
        relay = relays.get(relay_id) or {}
        row = {**_serialize_totals(amounts), "name": relay.get("name") or relay_id, "is_active": relay.get("is_active"), "missing_relay": not bool(relay)}
        if not search.strip() or search.strip().casefold() in f"{row['name']} {relay_id}".casefold():
            rows.append(row)
    rows.sort(key=lambda row: (-row["declared_count"], -row["outstanding_count"], row["name"].casefold(), row["relay_id"]))
    return {"totals": _serialize_totals(totals), "relays": rows[skip:skip + limit], "total": len(rows), "skip": skip, "limit": limit, "has_more": skip + limit < len(rows)}


async def settlement_action_list(database, *, relay_id: str | None = None, status: str = "outstanding", direction: str | None = None, skip: int = 0, limit: int = 20) -> dict:
    items, total, unavailable = [], 0, 0
    cursor = database.parcels.find(_parcel_query(relay_id), FINANCIAL_PROJECTION).sort([("updated_at", -1), ("parcel_id", 1)])
    def for_match(action):
        return (
            (not relay_id or action["relay_id"] == relay_id)
            and (not direction or action["direction"] == direction)
            and (status == "all" or status == "outstanding" and action["stage"] == "due" and action["status"] != "validated"
                 or status == "upcoming" and action["stage"] == "upcoming"
                 or status in SETTLEMENT_STATUSES and action["stage"] == "due" and action["status"] == status)
        )
    async for parcel in cursor:
        try:
            actions = settlement_actions(parcel)
        except (DeliveryCommissionDataError, ValueError) as exc:
            unavailable += 1
            issue = "Répartition financière invalide : vérifier le mode, le prix et les commissions du colis." if isinstance(exc, DeliveryCommissionDataError) else str(exc)
            actions = [{"parcel_id": parcel["parcel_id"], "tracking_code": parcel.get("tracking_code") or parcel["parcel_id"], "issue": issue}] if status == "issues" else []
        for action in actions:
            if status != "issues" and not for_match(action):
                continue
            if status == "issues" and "issue" not in action:
                continue
            if skip <= total < skip + limit:
                items.append(action)
            total += 1
    relay_ids = list({item["relay_id"] for item in items if item.get("relay_id")})
    relays = await database.relay_points.find({"relay_id": {"$in": relay_ids}}, {"_id": 0, "relay_id": 1, "name": 1}).to_list(length=len(relay_ids)) if relay_ids else []
    relay_names = {relay["relay_id"]: relay.get("name") or relay["relay_id"] for relay in relays}
    driver_ids = list({item["driver_id"] for item in items if item.get("driver_id")})
    drivers = await database.users.find({"user_id": {"$in": driver_ids}}, {"_id": 0, "user_id": 1, "name": 1}).to_list(length=len(driver_ids)) if driver_ids else []
    driver_names = {driver["user_id"]: driver.get("name") or driver["user_id"] for driver in drivers}
    for item in items:
        if "issue" not in item:
            item["relay_name"] = relay_names.get(item["relay_id"], item["relay_id"])
            item["beneficiary_name"] = driver_names.get(item.get("driver_id"), "Livreur du colis") if item["direction"] == "to_driver" else "Denkma" if item["direction"] == "to_denkma" else item["relay_name"]
    return {"actions": items, "total": total, "skip": skip, "limit": limit, "unavailable_count": unavailable, "has_more": skip + limit < total}
