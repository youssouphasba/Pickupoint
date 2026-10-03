import hashlib
import json
import logging
import math
import secrets
from datetime import datetime, timezone, timedelta

from config import settings
from core.delivery_destination import effective_delivery_mode, effective_relay_id, effective_delivery_location
from core.exceptions import bad_request_exception, conflict_exception
from database import db
from models.common import ParcelStatus
from models.parcel import ParcelQuote
from services.wallet_service import _run_in_transaction, compute_delivery_commission_breakdown

logger = logging.getLogger(__name__)
EARLY_STATUSES = {"created", "dropped_at_origin_relay"}
ACTIVE_MISSIONS = {"pending", "assigned", "in_progress", "incident_reported"}


async def _relay(relay_id, *, session=None, require_open=False):
    from services.parcel_service import _relay_is_open, _normalize_geopin
    relay = await db.relay_points.find_one(
        {"relay_id": relay_id, "is_active": True, "is_verified": True}, {"_id": 0}, session=session,
    )
    try:
        point = _normalize_geopin(relay.get("address")) if relay and isinstance(relay.get("address"), dict) else None
    except (TypeError, ValueError):
        point = None
    if not point or not all(math.isfinite(point[key]) and abs(point[key]) <= limit for key, limit in (("lat", 90), ("lng", 180))):
        raise bad_request_exception("Ce relais n'est pas actif, validé ou correctement géolocalisé.")
    try:
        capacity = int(relay["max_capacity"])
        load = int(relay.get("current_load") or 0)
    except (KeyError, TypeError, ValueError, OverflowError):
        raise bad_request_exception("La capacité de ce relais doit être vérifiée par le support.")
    if capacity <= 0 or load < 0 or load >= capacity:
        raise bad_request_exception("Ce relais n'a plus de place disponible.")
    if require_open and not _relay_is_open(relay, datetime.now(timezone.utc)):
        raise bad_request_exception("Ce relais est fermé. Choisissez un relais ouvert.")
    return relay


def _locked(parcel, mission):
    settlement = parcel.get("relay_settlement") or {}
    return bool(
        parcel.get("financial_contract") or parcel.get("payment_status") == "paid"
        or parcel.get("paid_price") is not None or parcel.get("payment_override")
        or parcel.get("payment_ref") or parcel.get("assigned_driver_id")
        or float((parcel.get("recipient_collection_plan") or {}).get("amount_received_xof") or 0) > 0
        or mission and mission.get("status") != "pending"
        or any(value in {"declared", "validated"} for key, value in settlement.items() if key.endswith("_status"))
    )


def _contract(parcel, mission):
    return parcel.get("financial_contract") or {
        "delivery_mode": parcel["delivery_mode"],
        "origin_relay_id": parcel.get("origin_relay_id"),
        "destination_relay_id": effective_relay_id(parcel),
        "price_xof": compute_delivery_commission_breakdown(parcel, mission)["price_xof"],
        "breakdown": compute_delivery_commission_breakdown(parcel, mission),
    }


def _recipient_collection(parcel, *, previous_relay_id=None):
    price = _contract(parcel, None)["price_xof"]
    paid = parcel.get("payment_status") == "paid" or bool(parcel.get("payment_override"))
    plan = dict(parcel.get("recipient_collection_plan") or {
        "status": "paid" if paid else "admin_review",
        "collector": None, "amount_received_xof": price if paid else 0,
        "amount_due_xof": 0 if paid else price,
    })
    if paid:
        plan.update(status="paid", amount_due_xof=0)
    elif plan.get("collector") == "relay" and previous_relay_id != effective_relay_id(parcel):
        plan.update(status="admin_review", collector=None, revision=int(plan.get("revision") or 0) + 1)
    return plan


async def preview_destination_change(parcel, *, new_mode, relay_id=None, address=None):
    from services.pricing_service import calculate_price
    if parcel.get("status") not in EARLY_STATUSES:
        raise bad_request_exception("La destination ne peut plus être modifiée après la collecte.")
    if parcel.get("transit_relay_id"):
        raise bad_request_exception("Cette livraison comporte un transit. Contactez le support pour modifier son parcours.")
    mission = await db.delivery_missions.find_one(
        {"parcel_id": parcel["parcel_id"], "status": {"$in": list(ACTIVE_MISSIONS)}}, {"_id": 0},
    )
    if mission and mission.get("status") not in {"pending", "assigned"}:
        raise conflict_exception("Le livreur a déjà collecté le colis. Actualisez son suivi.")
    origin = str(parcel.get("delivery_mode") or "").split("_to_")[0]
    if origin not in {"home", "relay"} or new_mode not in {"home", "relay"}:
        raise bad_request_exception("Mode de livraison invalide.")
    relay = None
    if new_mode == "relay":
        relay = await _relay(relay_id)
        if relay_id == parcel.get("origin_relay_id"):
            raise bad_request_exception("Le relais d'arrivée doit être différent du relais de départ.")
        address = {**relay["address"], "label": relay.get("name")}
    elif not address or not (address.get("geopin") or {}):
        raise bad_request_exception("Choisissez une adresse précise sur la carte.")
    mode = f"{origin}_to_{new_mode}"
    locked = _locked(parcel, mission)
    quote = None
    if not locked:
        user = await db.users.find_one({"user_id": parcel.get("sender_user_id")}) or {}
        total = await db.parcels.count_documents({"sender_user_id": parcel.get("sender_user_id"), "status": "delivered"})
        from datetime import timedelta
        recent = await db.parcels.count_documents({"sender_user_id": parcel.get("sender_user_id"), "status": "delivered", "created_at": {"$gte": datetime.now(timezone.utc) - timedelta(days=30)}})
        quote = await calculate_price(
            ParcelQuote(delivery_mode=mode, origin_relay_id=parcel.get("origin_relay_id"),
                        destination_relay_id=relay_id if relay else None,
                        origin_location=parcel.get("origin_location") or parcel.get("pickup_location") or parcel.get("pickup_address"),
                        delivery_address=address if new_mode == "home" else None,
                        weight_kg=parcel.get("weight_kg") or ParcelQuote.model_fields["weight_kg"].default, declared_value=parcel.get("declared_value"),
                        is_express=bool(parcel.get("requested_express", parcel.get("is_express"))),
                        who_pays=parcel.get("who_pays") or "sender", promo_code=parcel.get("promo_code")),
            sender_tier=user.get("loyalty_tier", "bronze"), is_frequent=recent >= 10,
            user_id=parcel.get("sender_user_id"), is_first_delivery=total == 0, reserved_promo=parcel.get("promo_snapshot"),
        )
        if quote.price is None:
            raise bad_request_exception("Le devis ne peut pas être calculé. Confirmez d'abord l'adresse de collecte.")
    price = _contract(parcel, mission)["price_xof"] if locked else quote.price
    preview = {
        "delivery_mode": mode, "relay_id": relay_id if relay else None, "address": address,
        "price_xof": price, "previous_price_xof": parcel.get("paid_price") or parcel.get("quoted_price"),
        "payment_preserved": locked, "additional_payment_xof": 0,
        "destination_revision": int(parcel.get("destination_revision") or 0),
        "quote_breakdown": quote.breakdown if quote else parcel.get("quote_breakdown"),
        "promo_snapshot": quote.promo_applied if quote else parcel.get("promo_snapshot"),
    }
    preview["preview_token"] = hashlib.sha256(json.dumps(preview, sort_keys=True, default=str).encode()).hexdigest()
    return preview


async def change_destination(parcel, preview, *, actor_id, actor_role, expected_token=None):
    from services.parcel_service import sync_active_mission_with_parcel, _record_event
    if expected_token is not None and expected_token != preview["preview_token"]:
        raise conflict_exception("Le devis ou la destination a changé. Vérifiez le nouveau récapitulatif.")
    now = datetime.now(timezone.utc)

    async def apply(session):
        if preview["relay_id"]:
            await _relay(preview["relay_id"], session=session)
        mission = await db.delivery_missions.find_one({"parcel_id": parcel["parcel_id"], "status": {"$in": list(ACTIVE_MISSIONS)}}, {"_id": 0}, session=session)
        if mission and mission.get("status") not in {"pending", "assigned"}:
            raise conflict_exception("La collecte a commencé. La destination n'a pas été modifiée.")
        if not preview["payment_preserved"] and _locked(parcel, mission):
            raise conflict_exception("Le paiement ou l'affectation a changé. Vérifiez le récapitulatif.")
        previous = {"delivery_mode": effective_delivery_mode(parcel), "relay_id": effective_relay_id(parcel), "address": effective_delivery_location(parcel)}
        updates = {
            "delivery_mode": preview["delivery_mode"], "destination_relay_id": preview["relay_id"], "redirect_relay_id": None,
            "delivery_address": preview["address"], "delivery_location": preview["address"],
            "delivery_destination": {"type": "relay" if preview["relay_id"] else "home", "relay_id": preview["relay_id"], "address": preview["address"], "changed_at": now},
            "delivery_confirmed": True, "destination_revision": preview["destination_revision"] + 1,
            "relay_pin": f"{secrets.randbelow(900000) + 100000}" if preview["relay_id"] else None,
            "delivery_code": None if preview["relay_id"] else f"{secrets.randbelow(900000) + 100000}",
            "expires_at": None, "updated_at": now,
            "redirect_relay_commission_xof": 0,
            "destination_financial_review": None,
        }
        if preview["payment_preserved"]:
            updates["financial_contract"] = _contract(parcel, mission)
            if preview["relay_id"] and updates["financial_contract"]["delivery_mode"].endswith("_to_home"):
                updates["redirect_relay_commission_xof"] = compute_delivery_commission_breakdown({**parcel, "delivery_mode": preview["delivery_mode"], "financial_contract": None})["destination_relay_commission_xof"]
            elif not preview["relay_id"] and updates["financial_contract"]["breakdown"]["destination_relay_commission_xof"] > 0:
                updates["destination_financial_review"] = {"status": "pending", "reason": "unused_destination_relay_commission", "amount_xof": updates["financial_contract"]["breakdown"]["destination_relay_commission_xof"], "previous_relay_id": previous["relay_id"]}
        else:
            updates.update(quoted_price=preview["price_xof"], quote_breakdown=preview["quote_breakdown"], promo_snapshot=preview["promo_snapshot"])
        if parcel.get("who_pays") == "recipient" and (preview["relay_id"] or parcel.get("recipient_collection_plan")):
            updates["recipient_collection_plan"] = _recipient_collection({**parcel, **updates}, previous_relay_id=previous["relay_id"])
        result = await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"], "status": {"$in": list(EARLY_STATUSES)}, "updated_at": parcel.get("updated_at")},
            {"$set": updates}, session=session,
        )
        if result.matched_count != 1:
            raise conflict_exception("Le colis a changé. Actualisez avant de confirmer.")
        updated = {**parcel, **updates}
        await sync_active_mission_with_parcel(updated, session=session, refresh_finances=not preview["payment_preserved"])
        await _record_event(parcel_id=parcel["parcel_id"], event_type="DELIVERY_MODE_CHANGED",
                            from_status=ParcelStatus(parcel["status"]), to_status=ParcelStatus(parcel["status"]),
                            actor_id=actor_id, actor_role=actor_role, notes="Destination modifiée avant la collecte.",
                            metadata={"previous_destination": previous, "destination": updates["delivery_destination"], "payment_preserved": preview["payment_preserved"]}, session=session)
        await _queue_change(updated, previous, session=session)
        return updated
    updated = await _run_in_transaction(apply)
    await process_destination_jobs(parcel["parcel_id"])
    return updated


async def redirect_destination(parcel, relay_id, *, actor_id, actor_role, notes=None):
    from services.parcel_service import sync_active_mission_with_parcel, _record_event
    if parcel.get("status") == "redirected_to_relay" and parcel.get("redirect_relay_id") == relay_id:
        return parcel
    if parcel.get("status") not in {"out_for_delivery", "delivery_failed", "redirected_to_relay"}:
        raise bad_request_exception("La redirection n'est plus possible dans cet état.")
    now = datetime.now(timezone.utc)

    async def apply(session):
        relay = await _relay(relay_id, session=session, require_open=True)
        mission = await db.delivery_missions.find_one({"parcel_id": parcel["parcel_id"], "status": {"$in": list(ACTIVE_MISSIONS)}}, {"_id": 0}, session=session)
        contract = _contract(parcel, mission)
        address = {**relay["address"], "label": relay.get("name")}
        original = parcel.get("original_delivery_destination") or {"delivery_mode": parcel["delivery_mode"], "address": parcel.get("delivery_location") or parcel.get("delivery_address"), "relay_id": parcel.get("destination_relay_id")}
        previous = {"delivery_mode": effective_delivery_mode(parcel), "relay_id": effective_relay_id(parcel), "address": effective_delivery_location(parcel)}
        redirected = {**parcel, "delivery_mode": effective_delivery_mode({**parcel, "redirect_relay_id": relay_id})}
        extra = compute_delivery_commission_breakdown({**redirected, "financial_contract": None}, {"delivery_mode": redirected["delivery_mode"], "financial_contract": None})["destination_relay_commission_xof"]
        updates = {
            "redirect_relay_id": relay_id, "original_delivery_destination": original,
            "delivery_destination": {"type": "relay", "relay_id": relay_id, "address": address, "changed_at": now},
            "financial_contract": contract, "redirect_relay_commission_xof": extra,
            "status": "redirected_to_relay", "relay_pin": f"{secrets.randbelow(900000) + 100000}",
            "delivery_confirmed": True, "expires_at": None, "updated_at": now,
            "destination_revision": int(parcel.get("destination_revision") or 0) + 1,
        }
        if parcel.get("who_pays") == "recipient":
            updates["recipient_collection_plan"] = _recipient_collection({**parcel, **updates}, previous_relay_id=previous["relay_id"])
        result = await db.parcels.update_one({"parcel_id": parcel["parcel_id"], "status": parcel["status"], "updated_at": parcel.get("updated_at")}, {"$set": updates}, session=session)
        if result.matched_count != 1:
            raise conflict_exception("Le colis a changé. Actualisez sa destination.")
        updated = {**parcel, **updates}
        await sync_active_mission_with_parcel(updated, session=session)
        await _record_event(parcel_id=parcel["parcel_id"], event_type="STATUS_CHANGED", from_status=ParcelStatus(parcel["status"]),
                            to_status=ParcelStatus.REDIRECTED_TO_RELAY, actor_id=actor_id, actor_role=actor_role,
                             notes=notes or "Redirection après échec de livraison à domicile.", metadata={"previous_destination": previous, "destination": updates["delivery_destination"], "financial_contract_preserved": True}, session=session)
        await _queue_change(updated, previous, session=session, redirected=True)
        return updated
    updated = await _run_in_transaction(apply)
    await process_destination_jobs(parcel["parcel_id"])
    return updated


async def _queue_change(parcel, previous, *, session, redirected=False):
    key = f"{parcel['parcel_id']}:{parcel['destination_revision']}"
    await db.destination_change_jobs.update_one({"_id": key}, {"$setOnInsert": {"parcel_id": parcel["parcel_id"], "parcel": parcel, "previous": previous, "redirected": redirected, "created_at": datetime.now(timezone.utc), "done": False}}, upsert=True, session=session)


async def request_return(parcel, mission, *, actor_id, actor_role, reason):
    from services.parcel_service import ALLOWED_TRANSITIONS, _record_event
    if parcel["status"] != ParcelStatus.INCIDENT_REPORTED.value and ParcelStatus.INCIDENT_REPORTED not in ALLOWED_TRANSITIONS.get(ParcelStatus(parcel["status"]), []):
        raise conflict_exception("Le colis ne peut pas être retourné dans cet état.")
    now = datetime.now(timezone.utc)
    async def save(session):
        updated = {**parcel, "status": "incident_reported", "return_code": parcel.get("return_code") or f"{secrets.randbelow(900000) + 100000}", "updated_at": now}
        result = await db.parcels.update_one({"parcel_id": parcel["parcel_id"], "status": parcel["status"], "updated_at": parcel.get("updated_at")},
                                            {"$set": {key: updated[key] for key in ("status", "return_code", "updated_at")}}, session=session)
        if result.matched_count != 1:
            raise conflict_exception("Le colis a changé. Actualisez avant de demander le retour.")
        result = await db.delivery_missions.update_one({"mission_id": mission["mission_id"], "status": mission["status"], "updated_at": mission.get("updated_at")},
            {"$set": {"status": "incident_reported", "failure_reason": reason, "updated_at": now,
                      "delivery_geopin": mission.get("pickup_geopin"), "delivery_label": mission.get("pickup_label") or "Retour à l'expéditeur",
                      "delivery_type": mission.get("pickup_type") or "gps", "return_requested": True,
                      "destination_revision": int(mission.get("destination_revision") or 0) + 1},
             "$unset": {key: "" for key in ("encoded_polyline", "eta_text", "eta_seconds", "distance_text", "eta_updated_at", "eta_attempted_at", "approaching_notified")}}, session=session)
        if result.matched_count != 1:
            raise conflict_exception("La mission a changé. Le retour n'a pas été enregistré.")
        await _record_event(parcel_id=parcel["parcel_id"], event_type="STATUS_CHANGED", from_status=ParcelStatus(parcel["status"]), to_status=ParcelStatus.INCIDENT_REPORTED,
                            actor_id=actor_id, actor_role=actor_role, notes=reason, session=session)
        return updated
    return await _run_in_transaction(save)


async def confirm_return(parcel, mission, *, actor_id, actor_role, notes):
    from services.parcel_service import _record_event
    now = datetime.now(timezone.utc)
    async def save(session):
        updated = {**parcel, "status": "returned", "current_relay_id": None, "expires_at": None, "updated_at": now}
        result = await db.parcels.update_one({"parcel_id": parcel["parcel_id"], "status": "incident_reported", "updated_at": parcel.get("updated_at")},
                                            {"$set": {key: updated[key] for key in ("status", "current_relay_id", "expires_at", "updated_at")}}, session=session)
        if result.matched_count != 1:
            raise conflict_exception("Le colis a changé. Actualisez son retour.")
        result = await db.delivery_missions.update_one({"mission_id": mission["mission_id"], "status": "incident_reported", "updated_at": mission.get("updated_at")},
                {"$set": {"status": "failed", "failure_reason": "retour_expediteur_confirme", "completed_at": now, "updated_at": now}}, session=session)
        if result.matched_count != 1:
            raise conflict_exception("La mission a changé. La confirmation du retour n'a pas été enregistrée.")
        await _record_event(parcel_id=parcel["parcel_id"], event_type="STATUS_CHANGED", from_status=ParcelStatus.INCIDENT_REPORTED, to_status=ParcelStatus.RETURNED,
                            actor_id=actor_id, actor_role=actor_role, notes=notes, session=session)
        return updated
    return await _run_in_transaction(save)


async def process_destination_jobs(parcel_id=None):
    from services.notification_service import notify_destination_changed
    from services.parcel_service import _create_delivery_mission
    query = {"done": False}
    if parcel_id:
        query["parcel_id"] = parcel_id
    async for job in db.destination_change_jobs.find(query).limit(settings.DESTINATION_JOB_BATCH_SIZE):
        now = datetime.now(timezone.utc)
        claim = await db.destination_change_jobs.update_one({"_id": job["_id"], "done": False, "$or": [{"lease_until": None}, {"lease_until": {"$lt": now}}]},
                {"$set": {"lease_until": now + timedelta(seconds=settings.DESTINATION_JOB_LEASE_SECONDS)}})
        if claim.modified_count != 1:
            continue
        try:
            latest = await db.parcels.find_one({"parcel_id": job["parcel_id"]}, {"_id": 0})
            if job.get("kind") == "recipient_collection":
                if latest and (latest.get("recipient_collection_plan") or {}).get("revision") == job["revision"]:
                    from services.notification_service import notify_recipient_collection_plan
                    await notify_recipient_collection_plan(latest)
            elif job.get("kind") == "relay_arrival":
                from services.notification_service import notify_parcel_status_change, notify_driver_mission_completed
                if latest and latest.get("status") == "available_at_relay":
                    await notify_parcel_status_change(latest, ParcelStatus.AVAILABLE_AT_RELAY, dedupe_key=job["_id"])
                mission = job.get("mission")
                if mission:
                    await notify_driver_mission_completed(mission, job["parcel"])
                    from services.loyalty_service import _check_referral_bonus
                    from services.ranking_service import refresh_driver_stats_for_period
                    await _check_referral_bonus(mission["driver_id"])
                    await refresh_driver_stats_for_period(job["created_at"].strftime("%Y-%m"))
            elif latest and latest.get("status") in EARLY_STATUSES | {"in_transit", "out_for_delivery", "redirected_to_relay"} and latest.get("destination_revision") == job["parcel"].get("destination_revision"):
                if latest.get("status") in EARLY_STATUSES and latest.get("pickup_confirmed"):
                    await _create_delivery_mission(latest, ParcelStatus(latest["status"]))
                await notify_destination_changed(latest, job["previous"], redirected=job["redirected"])
            await db.destination_change_jobs.update_one({"_id": job["_id"]}, {"$set": {"done": True, "completed_at": datetime.now(timezone.utc)}, "$unset": {"parcel": "", "previous": "", "mission": "", "lease_until": ""}})
        except Exception:
            logger.exception("Changement de destination à notifier de nouveau : %s", job["_id"])
            await db.destination_change_jobs.update_one({"_id": job["_id"]}, {"$unset": {"lease_until": ""}})
