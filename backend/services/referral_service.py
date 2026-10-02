import logging
import uuid
from datetime import datetime, timezone

from fastapi import HTTPException
from pymongo import ReturnDocument

from core.exceptions import bad_request_exception, not_found_exception
from database import db, get_client
from services.user_service import (
    get_global_app_settings, get_referral_metric_count, get_referral_role_config, get_referral_metric_label,
    is_referral_referred_enabled_for_user, is_referral_sponsor_enabled_for_user, is_referral_pair_allowed,
)

BENEFICIARIES = ("sponsor", "referred")
SETTLED_PAYMENT_STATUSES = ("confirmed", "legacy_confirmed", "legacy_wallet", "not_due")
EXTERNAL_PAYMENT_STATUSES = ("confirmed", "legacy_confirmed")
logger = logging.getLogger(__name__)


def utc(value):
    if isinstance(value, str):
        value = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def payment_status(referral, qualified=True):
    if not qualified:
        return "pending"
    payments = referral["payments"]
    if all(payments[key]["status"] == "not_due" for key in BENEFICIARIES):
        return "qualified_no_bonus"
    if all(payments[key]["status"] in SETTLED_PAYMENT_STATUSES for key in BENEFICIARIES):
        return "rewarded"
    if any(payments[key]["status"] in SETTLED_PAYMENT_STATUSES and payments[key]["status"] != "not_due" for key in BENEFICIARIES):
        return "partially_paid"
    return "qualified"


def payment_entries(referral, transactions=None, user=None):
    entries = {}
    transactions = transactions or {}
    historical_paid = referral.get("status") == "rewarded"
    for key in BENEFICIARIES:
        amount = int(referral.get(f"{key}_bonus_xof") or 0)
        reference = referral.get(f"{key}_transaction_reference")
        reference = reference or f"ref_bonus_{'sponsor' if key == 'sponsor' else 'self'}_{referral['referred_user_id']}"
        transaction = transactions.get(reference)
        status = "pending" if amount > 0 else "not_due"
        entry = {"beneficiary_user_id": referral[f"{key}_user_id"], "amount_xof": amount, "status": status}
        if transaction:
            entry.update(status="legacy_wallet", amount_xof=int(transaction["amount"]),
                         paid_amount_xof=int(transaction["amount"]), paid_at=transaction.get("created_at"),
                         reference=reference)
        elif referral.get("status") == "qualified_no_bonus":
            entry.update(status="not_due", amount_xof=0)
        elif historical_paid and referral.get("payment_confirmed_at") and amount > 0 and not referral.get(f"{key}_transaction_reference"):
            entry.update(status="legacy_confirmed", paid_amount_xof=amount,
                         paid_at=referral.get("payment_confirmed_at") or referral.get("rewarded_at"),
                         confirmed_at=referral.get("payment_confirmed_at"),
                         confirmed_by=referral.get("payment_confirmed_by"),
                         note=referral.get("payment_confirmation_note"))
        elif amount > 0 and (historical_paid or referral.get(f"{key}_transaction_reference") or (user or {}).get("referral_credited")):
            entry.update(status="needs_review")
        entries[key] = entry
    return entries


def historical_transactions(transactions):
    by_reference = {}
    for transaction in transactions:
        reference = transaction["reference"]
        existing = by_reference.get(reference)
        if existing is None:
            by_reference[reference] = dict(transaction)
        else:
            existing["amount"] += transaction["amount"]
            paid_at = transaction.get("created_at")
            if paid_at and (not existing.get("created_at") or utc(paid_at) > utc(existing["created_at"])):
                existing["created_at"] = paid_at
    return by_reference


def public_referral(referral, beneficiary=None):
    if not referral:
        return None
    result = {key: value for key, value in referral.items() if key in {
        "referral_id", "referred_role", "status", "reward_metric", "reward_count",
        "reward_metric_count", "reward_metric_label", "sponsor_bonus_xof", "referred_bonus_xof",
        "created_at", "qualified_at", "rewarded_at", "rules_frozen_at",
    }}
    result["payments"] = {
        key: {field: value for field, value in payment.items() if field in {
            "amount_xof", "paid_amount_xof", "status", "paid_at", "confirmed_at",
        }} for key, payment in referral.get("payments", {}).items() if beneficiary is None or key == beneficiary
    }
    return result


def build_referral_id(referred_user_id: str) -> str:
    return f"ref_{referred_user_id}"


async def upsert_referral_record(
    *,
    sponsor_user_id: str,
    referred_user_id: str,
    referred_role: str,
    referral_code: str,
    source: str,
    settings_doc: dict | None,
    created_at: datetime | None = None,
    session=None,
    legacy_user=None,
) -> None:
    now = datetime.now(timezone.utc)
    config = get_referral_role_config(settings_doc, referred_role)
    fields = {
        "referral_id": build_referral_id(referred_user_id), "sponsor_user_id": sponsor_user_id,
        "referred_user_id": referred_user_id, "referred_role": referred_role,
        "referral_code": referral_code, "source": source, "status": "pending",
        "created_at": created_at or now, "updated_at": now,
        "rules_frozen_at": now, "schema_version": 2, "payment_revision": 0,
        "payment_mode": "external", "payment_history": [],
        **{key: config[key] for key in ("reward_metric", "reward_count", "apply_metric", "apply_max_count", "sponsor_bonus_xof", "referred_bonus_xof")},
    }
    fields["payments"] = payment_entries(fields)
    if legacy_user is not None:
        refs = [f"ref_bonus_{'sponsor' if key == 'sponsor' else 'self'}_{referred_user_id}" for key in BENEFICIARIES]
        transactions = await db.wallet_transactions.find({"reference": {"$in": refs}}, {"_id": 0}, session=session).to_list(length=None)
        fields["payments"] = payment_entries(fields, historical_transactions(transactions), legacy_user)
        if transactions or legacy_user.get("referral_credited"):
            fields["status"] = payment_status(fields)
    await db.referrals.update_one(
        {"referred_user_id": referred_user_id},
        {"$setOnInsert": fields}, upsert=True, session=session,
    )


async def normalize_referral(referral, settings_doc=None, user=None):
    if referral.get("schema_version") == 2:
        return referral
    settings_doc = settings_doc if settings_doc is not None else await get_global_app_settings()
    user = user or await db.users.find_one({"user_id": referral["referred_user_id"]}, {"_id": 0}) or {}
    role = referral.get("referred_role") or user.get("role") or "client"
    config = get_referral_role_config(settings_doc, role)
    frozen = {**referral, "referred_role": role}
    for key in ("reward_metric", "reward_count", "apply_metric", "apply_max_count", "sponsor_bonus_xof", "referred_bonus_xof"):
        if frozen.get(key) is None:
            frozen[key] = config[key]
    refs = [referral.get(f"{key}_transaction_reference") or f"ref_bonus_{'sponsor' if key == 'sponsor' else 'self'}_{referral['referred_user_id']}" for key in BENEFICIARIES]
    transactions = await db.wallet_transactions.find({"reference": {"$in": refs}}, {"_id": 0}).to_list(length=None)
    frozen["payments"] = payment_entries(frozen, historical_transactions(transactions), user)
    qualified = referral.get("status", "pending") != "pending" or any(item["status"] == "legacy_wallet" for item in frozen["payments"].values())
    updates = {key: value for key, value in frozen.items() if key not in {"_id", "referral_id"}}
    updates.update(schema_version=2, payment_mode="external", payment_revision=0,
                   rules_frozen_at=referral.get("created_at") or datetime.now(timezone.utc),
                   status=payment_status(frozen, qualified), payment_history=referral.get("payment_history") or [])
    result = await db.referrals.find_one_and_update(
        {"referral_id": referral["referral_id"], "schema_version": {"$ne": 2}},
        {"$set": updates}, return_document=ReturnDocument.AFTER,
    )
    return result or await db.referrals.find_one({"referral_id": referral["referral_id"]}, {"_id": 0})


async def ensure_referral_record_for_user(
    user_doc: dict,
    settings_doc: dict | None,
    source: str = "legacy",
) -> dict | None:
    referred_user_id = user_doc.get("user_id")
    sponsor_user_id = user_doc.get("referred_by")
    if not referred_user_id or not sponsor_user_id:
        return None

    existing = await db.referrals.find_one({"referred_user_id": referred_user_id}, {"_id": 0})
    if existing:
        return await normalize_referral(existing, settings_doc, user_doc)

    sponsor = await db.users.find_one(
        {"user_id": sponsor_user_id},
        {"_id": 0, "referral_code": 1},
    )
    referral_code = str((sponsor or {}).get("referral_code") or user_doc.get("referral_code_used") or "")
    created_at = user_doc.get("referral_applied_at") or user_doc.get("created_at")
    await upsert_referral_record(
        sponsor_user_id=sponsor_user_id,
        referred_user_id=referred_user_id,
        referred_role=str(user_doc.get("role") or "client"),
        referral_code=referral_code,
        source=source,
        settings_doc=settings_doc,
        created_at=created_at,
        legacy_user=user_doc,
    )
    referral = await db.referrals.find_one({"referred_user_id": referred_user_id}, {"_id": 0})
    return referral


async def refresh_referral_progress(user_id: str, settings_doc: dict | None = None) -> dict | None:
    referral = await db.referrals.find_one({"referred_user_id": user_id}, {"_id": 0})
    user = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not referral or not user:
        return None

    referral = await normalize_referral(referral, settings_doc, user)
    metric = referral["reward_metric"]
    count = await get_referral_metric_count(user_id, metric)
    count = max(count, int(referral.get("reward_metric_count") or 0))
    now = datetime.now(timezone.utc)
    await db.referrals.update_one({"referral_id": referral["referral_id"]}, {"$max": {"reward_metric_count": count}, "$set": {"updated_at": now}})
    if count >= referral["reward_count"]:
        await db.referrals.update_one({"referral_id": referral["referral_id"], "status": "pending"}, {"$set": {
            "status": payment_status(referral), "qualified_at": now, "updated_at": now,
        }})
    return await db.referrals.find_one({"referral_id": referral["referral_id"]}, {"_id": 0})


async def _record_payment_audit_event(referral, payment_event):
    try:
        await db.parcel_events.update_one(
            {"_id": payment_event["event_id"]},
            {"$setOnInsert": {
                "event_id": payment_event["event_id"], "parcel_id": None,
                "event_type": "ADMIN_REFERRAL_PAYMENT_CONFIRMED",
                "actor_id": payment_event["confirmed_by"],
                "actor_role": payment_event.get("confirmed_by_role") or "admin",
                "created_at": payment_event["confirmed_at"],
                "notes": "Paiement hors plateforme d’une prime de parrainage confirmé",
                "metadata": {"referral_id": referral["referral_id"],
                             "beneficiary": payment_event["beneficiary"],
                             "beneficiary_user_id": payment_event["beneficiary_user_id"],
                             "amount_xof": payment_event["paid_amount_xof"],
                             "paid_at": payment_event["paid_at"]},
            }}, upsert=True,
        )
    except Exception:
        logger.exception("Copie de l’audit de parrainage différée pour %s", referral["referral_id"])


async def confirm_external_payment(referral_id, beneficiary, amount_xof, paid_at, reference, note, admin):
    if beneficiary not in BENEFICIARIES:
        raise bad_request_exception("Bénéficiaire invalide")
    now = datetime.now(timezone.utc)
    paid_at = utc(paid_at)
    if paid_at > now:
        raise bad_request_exception("La date du paiement ne peut pas être dans le futur")
    for _ in range(8):
        referral = await db.referrals.find_one({"referral_id": referral_id}, {"_id": 0})
        if not referral:
            raise not_found_exception("Parrainage")
        referral = await normalize_referral(referral)
        referral = await refresh_referral_progress(referral["referred_user_id"]) or referral
        payment = referral["payments"][beneficiary]
        if payment["status"] in SETTLED_PAYMENT_STATUSES:
            for event in referral.get("payment_history", []):
                if event.get("beneficiary") == beneficiary:
                    await _record_payment_audit_event(referral, event)
                    break
            return {"already_confirmed": True, "referral": referral}
        if payment["status"] == "needs_review":
            raise bad_request_exception("Ce bonus possède un historique incomplet. Vérifiez les anciens paiements avant toute nouvelle confirmation.")
        if referral["status"] not in {"qualified", "partially_paid"}:
            raise bad_request_exception("L’objectif du parrainage n’est pas encore atteint")
        if amount_xof != payment["amount_xof"] or amount_xof <= 0:
            raise bad_request_exception("Le montant doit correspondre exactement au bonus de ce bénéficiaire")
        confirmed = {**payment, "status": "confirmed", "paid_amount_xof": amount_xof, "paid_at": paid_at,
                     "confirmed_at": now, "confirmed_by": admin["user_id"],
                     "confirmed_by_role": admin.get("role"),
                     "confirmed_by_name": admin.get("name") or admin.get("email"),
                     "reference": (reference or "").strip() or None, "note": (note or "").strip() or None}
        latest = {**referral, "payments": {**referral["payments"], beneficiary: confirmed}}
        status = payment_status(latest)
        revision = referral.get("payment_revision", 0)
        update = {"payments." + beneficiary: confirmed, "status": status, "updated_at": now}
        if status == "rewarded":
            update["rewarded_at"] = now
        history = {"event_id": f"refpay_{uuid.uuid4().hex}", "beneficiary": beneficiary, **confirmed}
        saved = await db.referrals.find_one_and_update(
            {"referral_id": referral_id, "payment_revision": revision, f"payments.{beneficiary}.status": "pending"},
            {"$set": update, "$inc": {"payment_revision": 1}, "$push": {"payment_history": history}},
            return_document=ReturnDocument.AFTER,
        )
        if saved:
            await _record_payment_audit_event(saved, history)
            return {"already_confirmed": False, "referral": saved}
    raise HTTPException(status_code=409, detail="Une autre confirmation est en cours. Actualisez et réessayez.")


async def assign_referral(user_id, sponsor_id, code, settings_doc, source, new_user_doc=None):
    now = datetime.now(timezone.utc)
    async def assign(session):
        sponsor = await db.users.find_one({"user_id": sponsor_id}, {"_id": 0}, session=session)
        if not is_referral_sponsor_enabled_for_user(sponsor, settings_doc):
            raise bad_request_exception("Ce code parrainage n’est pas actif")
        if sponsor.get("referral_code") != code:
            raise bad_request_exception("Ce code parrainage n’est plus actif")
        if await db.users.count_documents({"referral_code": code}, session=session) != 1:
            raise bad_request_exception("Ce code doit être vérifié par l’administration")
        await db.users.update_one({"user_id": sponsor_id}, {"$inc": {"referral_assignment_revision": 1}}, session=session)
        user = new_user_doc or await db.users.find_one({"user_id": user_id}, {"_id": 0}, session=session)
        if not user or user.get("referred_by"):
            raise bad_request_exception("Vous avez déjà un parrain")
        if await db.referrals.find_one({"referred_user_id": user_id}, session=session):
            raise bad_request_exception("Un parrainage existe déjà pour ce compte. Contactez le support.")
        if sponsor_id == user_id or not is_referral_referred_enabled_for_user(user, settings_doc):
            raise bad_request_exception("Ce parrainage n’est pas disponible pour ce compte")
        if not is_referral_pair_allowed(sponsor, user):
            raise bad_request_exception("Un client peut parrainer uniquement un client. Pour un filleul livreur, utilisez le code d’un livreur.")
        ancestor = sponsor
        seen = {user_id}
        while ancestor:
            if ancestor["user_id"] in seen:
                raise bad_request_exception("Un parrainage réciproque n’est pas autorisé")
            seen.add(ancestor["user_id"])
            parent_id = ancestor.get("referred_by")
            ancestor = await db.users.find_one({"user_id": parent_id}, {"_id": 0}, session=session) if parent_id else None
        role = user.get("role") or "client"
        config = get_referral_role_config(settings_doc, role)
        metric_query = {"sender_user_id": user_id}
        collection = db.parcels
        if config["apply_metric"] == "delivered_sender_parcels":
            metric_query["status"] = "delivered"
        elif config["apply_metric"] == "completed_driver_deliveries":
            collection, metric_query = db.delivery_missions, {"driver_id": user_id, "status": "completed"}
        count = await collection.count_documents(metric_query, session=session)
        if count > config["apply_max_count"]:
            raise bad_request_exception("Le code parrainage ne peut plus être appliqué pour ce compte")
        maximum = config["max_referrals_per_sponsor"]
        if maximum and await db.referrals.count_documents({"sponsor_user_id": sponsor_id, "referred_role": role}, session=session) >= maximum:
            raise bad_request_exception("Ce parrain a atteint le nombre maximum de filleuls de ce type")
        if new_user_doc:
            await db.users.insert_one({**new_user_doc, "referred_by": None}, session=session)
        result = await db.users.update_one({"user_id": user_id, "referred_by": {"$in": [None, ""]}}, {"$set": {
            "referred_by": sponsor_id, "referral_applied_at": now, "referral_source": source, "updated_at": now,
        }}, session=session)
        if not result.modified_count:
            raise bad_request_exception("Vous avez déjà un parrain")
        await upsert_referral_record(sponsor_user_id=sponsor_id, referred_user_id=user_id,
                                     referred_role=role, referral_code=code, source=source,
                                     settings_doc=settings_doc, created_at=now, session=session)
        return {**user, "referred_by": sponsor_id, "referral_applied_at": now, "referral_source": source}
    async with await get_client().start_session() as session:
        return await session.with_transaction(assign)


async def referral_totals(query):
    def paid(key):
        historical_confirmed = {"$and": [
            {"$ne": [{"$ifNull": ["$schema_version", 0]}, 2]},
            {"$eq": ["$status", "rewarded"]},
            {"$ne": [{"$ifNull": ["$payment_confirmed_at", None]}, None]},
            {"$eq": [{"$ifNull": [f"${key}_transaction_reference", None]}, None]},
        ]}
        return {"$cond": [{"$or": [{"$in": [{"$ifNull": [f"$payments.{key}.status", ""]}, list(EXTERNAL_PAYMENT_STATUSES)]}, historical_confirmed]},
                         {"$ifNull": [f"$payments.{key}.paid_amount_xof", f"${key}_bonus_xof"]}, 0]}
    due = lambda key: {"$cond": [{"$and": [{"$in": ["$status", ["qualified", "partially_paid"]]}, {"$eq": [{"$ifNull": [f"$payments.{key}.status", "pending"]}, "pending"]}]}, {"$ifNull": [f"$payments.{key}.amount_xof", f"${key}_bonus_xof"]}, 0]}
    rows = await db.referrals.aggregate([
        {"$match": query}, {"$group": {"_id": None, "total": {"$sum": 1},
            "pending_rewards": {"$sum": {"$cond": [{"$in": ["$status", ["pending", "qualified", "partially_paid"]]}, 1, 0]}},
            "rewarded": {"$sum": {"$cond": [{"$eq": ["$status", "rewarded"]}, 1, 0]}},
            "total_sponsor_bonus_xof": {"$sum": paid("sponsor")},
            "total_referred_bonus_xof": {"$sum": paid("referred")},
            "sponsor_due_xof": {"$sum": due("sponsor")}, "referred_due_xof": {"$sum": due("referred")},
        }},
    ]).to_list(length=1)
    return {key: (rows[0] if rows else {}).get(key, 0) for key in (
        "total", "pending_rewards", "rewarded", "total_sponsor_bonus_xof", "total_referred_bonus_xof", "sponsor_due_xof", "referred_due_xof")}


async def referral_list(query, skip=0, limit=20, admin=False):
    referrals = await db.referrals.find(query, {"_id": 0}).sort("created_at", -1).skip(skip).limit(limit).to_list(length=limit)
    settings_doc = await get_global_app_settings()
    normalized = []
    for item in referrals:
        normalized.append(await refresh_referral_progress(item["referred_user_id"], settings_doc) or await normalize_referral(item, settings_doc))
    ids = list({item[key] for item in normalized for key in ("sponsor_user_id", "referred_user_id")})
    users = await db.users.find({"user_id": {"$in": ids}}, {"_id": 0, "user_id": 1, "name": 1, "role": 1, **({"phone": 1} if admin else {})}).to_list(length=len(ids)) if ids else []
    users_by_id = {item["user_id"]: item for item in users}
    items = []
    for item in normalized:
        entry = {**item} if admin else public_referral(item, "sponsor")
        entry.pop("_id", None)
        for key in BENEFICIARIES:
            user = users_by_id.get(item[key + "_user_id"], {})
            entry[key + "_name"] = user.get("name") or "Utilisateur Denkma"
            if admin:
                entry[key + "_phone"] = user.get("phone")
        entry["reward_metric_label"] = get_referral_metric_label(item["reward_metric"], item["reward_count"])
        entry["progress_percent"] = min(100, round((item.get("reward_metric_count", 0) / max(item["reward_count"], 1)) * 100))
        items.append(entry)
    return {"items": items, "shown": len(items), "total": await db.referrals.count_documents(query), "skip": skip, "limit": limit}


async def sponsored_referral_summary(user_id, admin=False):
    query = {"sponsor_user_id": user_id}
    page = await referral_list(query, limit=10, admin=admin)
    return {**page, **await referral_totals(query)}
