import asyncio
import hashlib
import hmac
import json
import logging
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Optional
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import httpx
from fastapi import HTTPException

from config import settings
from core.exceptions import bad_request_exception, not_found_exception
from database import db
from pymongo import ReturnDocument
from pymongo.errors import DuplicateKeyError
from services.wallet_service import get_or_create_wallet

logger = logging.getLogger(__name__)

STRIPE_BASE_URL = "https://api.stripe.com/v1"


def _topup_id() -> str:
    return f"top_{uuid.uuid4().hex[:12]}"


def _stripe_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {settings.STRIPE_SECRET_KEY}",
        "Content-Type": "application/x-www-form-urlencoded",
    }


def _wallet_redirect_url(kind: str, topup_id: str) -> str:
    configured = (
        settings.STRIPE_WALLET_SUCCESS_URL
        if kind == "success"
        else settings.STRIPE_WALLET_CANCEL_URL
    )
    public_url = str(settings.PUBLIC_SITE_URL).rstrip("/")
    parts = urlsplit(configured or f"{public_url}/app/")
    query = dict(parse_qsl(parts.query, keep_blank_values=True))
    query.update(wallet_return=kind, topup_id=topup_id)
    return urlunsplit(parts._replace(query=urlencode(query)))


def wallet_topup_options() -> dict[str, Any]:
    return {
        "enabled": bool(settings.STRIPE_SECRET_KEY),
        "currency": "XOF",
        "minimum_amount": settings.WALLET_TOPUP_MIN_XOF,
        "maximum_amount": settings.WALLET_TOPUP_MAX_XOF,
        "verification_retry_seconds": settings.STRIPE_RECONCILE_INTERVAL_SECONDS,
        "verification_retry_attempts": settings.STRIPE_RETURN_RETRY_ATTEMPTS,
    }


def _public_topup(topup: dict) -> dict[str, Any]:
    return {key: topup.get(key) for key in (
        "topup_id", "amount", "currency", "status", "created_at", "paid_at",
        "verification_message",
    )}


async def get_wallet_topups(owner_id: str) -> list[dict[str, Any]]:
    topups = await db.wallet_topups.find(
        {"owner_id": owner_id}, {"_id": 0},
    ).sort("created_at", -1).limit(settings.WALLET_TOPUP_HISTORY_LIMIT).to_list(
        length=settings.WALLET_TOPUP_HISTORY_LIMIT,
    )
    return [_public_topup(topup) for topup in topups]


async def create_wallet_topup_checkout(
    *,
    user: dict[str, Any],
    amount: float,
) -> dict[str, Any]:
    if not settings.STRIPE_SECRET_KEY:
        raise bad_request_exception("Stripe n'est pas encore configuré")
    if not float(amount).is_integer():
        raise bad_request_exception("Saisissez un montant entier en FCFA")
    if amount < settings.WALLET_TOPUP_MIN_XOF:
        raise bad_request_exception(
            f"Le montant minimum de recharge est de {int(settings.WALLET_TOPUP_MIN_XOF):,} FCFA".replace(",", " ")
        )
    if amount > settings.WALLET_TOPUP_MAX_XOF:
        raise bad_request_exception(
            f"Le montant maximum de recharge est de {int(settings.WALLET_TOPUP_MAX_XOF):,} FCFA".replace(",", " ")
        )

    wallet = await get_or_create_wallet(user["user_id"], user.get("role", "driver"))
    topup_id = _topup_id()
    now = datetime.now(timezone.utc)
    topup = {
        "topup_id": topup_id,
        "wallet_id": wallet["wallet_id"],
        "owner_id": user["user_id"],
        "amount": round(float(amount)),
        "currency": "XOF",
        "provider": "stripe",
        "status": "pending",
        "created_at": now,
        "updated_at": now,
    }
    await db.wallet_topups.insert_one(topup)

    data = {
        "mode": "payment",
        "client_reference_id": topup_id,
        "success_url": _wallet_redirect_url("success", topup_id),
        "cancel_url": _wallet_redirect_url("cancel", topup_id),
        "payment_method_types[0]": "card",
        "line_items[0][quantity]": "1",
        "line_items[0][price_data][currency]": "xof",
        "line_items[0][price_data][unit_amount]": str(topup["amount"]),
        "line_items[0][price_data][product_data][name]": "Recharge wallet Denkma",
        "metadata[topup_id]": topup_id,
        "metadata[wallet_id]": wallet["wallet_id"],
        "metadata[user_id]": user["user_id"],
    }
    if user.get("email"):
        data["customer_email"] = user["email"]

    try:
        async with httpx.AsyncClient(timeout=settings.STRIPE_HTTP_TIMEOUT_SECONDS) as client:
            response = await client.post(
                f"{STRIPE_BASE_URL}/checkout/sessions",
                data=data,
                headers={**_stripe_headers(), "Idempotency-Key": topup_id},
            )
            response.raise_for_status()
            session = response.json()
            if not isinstance(session, dict):
                raise ValueError("Invalid Stripe session")
            session_id = str(session.get("id") or "")
            checkout_url = urlsplit(str(session.get("url") or ""))
            if (not session_id.startswith("cs_")
                    or not session_id.replace("_", "").isalnum()
                    or checkout_url.scheme != "https"
                    or checkout_url.hostname != "checkout.stripe.com"):
                raise ValueError("Incomplete Stripe checkout")
    except httpx.HTTPStatusError as exc:
        await db.wallet_topups.update_one(
            {"topup_id": topup_id},
            {"$set": {"status": "failed", "updated_at": now}},
        )
        logger.error("Stripe checkout rejected: topup=%s status=%s", topup_id, exc.response.status_code)
        raise bad_request_exception("Création du paiement Stripe impossible")
    except Exception as exc:
        await db.wallet_topups.update_one(
            {"topup_id": topup_id},
            {"$set": {"status": "failed", "updated_at": now}},
        )
        logger.error("Stripe checkout unavailable: topup=%s error=%s", topup_id, type(exc).__name__)
        raise bad_request_exception("Stripe indisponible pour le moment")

    await db.wallet_topups.update_one(
        {"topup_id": topup_id},
        {
            "$set": {
                "provider_session_id": session.get("id"),
                "checkout_url": session.get("url"),
                "updated_at": datetime.now(timezone.utc),
            }
        },
    )
    return {
        "topup_id": topup_id,
        "checkout_url": session.get("url"),
        "provider_session_id": session.get("id"),
        "amount": topup["amount"],
        "currency": "XOF",
    }


def verify_stripe_signature(payload: bytes, signature_header: Optional[str]) -> None:
    if not settings.STRIPE_WEBHOOK_SECRET:
        raise bad_request_exception("Webhook Stripe non configuré")
    if not signature_header:
        raise bad_request_exception("Signature Stripe manquante")

    parts = [item.strip().split("=", 1) for item in signature_header.split(",") if "=" in item]
    timestamp = next((value for key, value in parts if key == "t"), None)
    signatures = [value for key, value in parts if key == "v1"]
    if not timestamp or not signatures:
        raise bad_request_exception("Signature Stripe invalide")
    try:
        timestamp_value = int(timestamp)
    except ValueError:
        raise bad_request_exception("Signature Stripe invalide") from None
    if abs(int(time.time()) - timestamp_value) > 300:
        raise bad_request_exception("Signature Stripe expirée")

    signed_payload = f"{timestamp}.".encode("utf-8") + payload
    expected = hmac.new(
        settings.STRIPE_WEBHOOK_SECRET.encode("utf-8"),
        signed_payload,
        hashlib.sha256,
    ).hexdigest()
    if not any(hmac.compare_digest(expected.encode("ascii"), signature.encode("utf-8")) for signature in signatures):
        raise bad_request_exception("Signature Stripe invalide")


def _validate_paid_session(topup: dict, session: dict) -> None:
    if not isinstance(session, dict):
        raise bad_request_exception("Confirmation Stripe incohérente. Contactez le support.")
    metadata = session.get("metadata") or {}
    if not isinstance(metadata, dict):
        raise bad_request_exception("Confirmation Stripe incohérente. Contactez le support.")
    expected_session = topup.get("provider_session_id")
    if (
        not session.get("id")
        or session.get("payment_status") != "paid"
        or (expected_session and session["id"] != expected_session)
        or session.get("mode") != "payment"
        or str(session.get("currency") or "").lower() != "xof"
        or session.get("amount_total") != topup.get("amount")
        or metadata.get("topup_id") != topup["topup_id"]
        or metadata.get("user_id") != topup["owner_id"]
        or metadata.get("wallet_id") != topup["wallet_id"]
        or session.get("client_reference_id") != topup["topup_id"]
    ):
        raise bad_request_exception("Confirmation Stripe incohérente. Contactez le support.")
    intent = session.get("payment_intent")
    if isinstance(intent, dict):
        charge = intent.get("latest_charge")
        if (intent.get("status") != "succeeded"
                or intent.get("amount_received") != topup["amount"]
                or not isinstance(charge, dict)
                or charge.get("refunded") is not False
                or charge.get("amount_refunded") != 0
                or charge.get("disputed") is not False):
            raise bad_request_exception("Ce paiement nécessite une vérification par le support.")


async def _fulfill_paid_session(topup: dict, session: dict) -> dict:
    _validate_paid_session(topup, session)
    session_id = session["id"]
    wallet_query = {"wallet_id": topup["wallet_id"], "owner_id": topup["owner_id"]}
    wallet = await db.wallets.find_one(wallet_query, {"_id": 0})
    if not wallet:
        raise not_found_exception("Solde du livreur")
    now = datetime.now(timezone.utc)
    legacy_transaction = await db.wallet_transactions.find_one({
        "wallet_id": topup["wallet_id"], "reference": session_id, "tx_type": "credit",
    }, {"_id": 0})
    if not legacy_transaction:
        # Le marqueur et le crédit sont écrits atomiquement, même sans replica set.
        credit = await db.wallets.update_one(
            {**wallet_query, "stripe_credited_topups": {"$ne": topup["topup_id"]}},
            {"$inc": {"balance": topup["amount"]},
             "$addToSet": {"stripe_credited_topups": topup["topup_id"]},
             "$set": {"updated_at": now}},
        )
        if not credit.matched_count and not await db.wallets.find_one(
            {**wallet_query, "stripe_credited_topups": topup["topup_id"]}, {"_id": 0},
        ):
            raise not_found_exception("Solde du livreur")
        transaction = {
            "tx_id": f"wtx_{topup['topup_id']}", "wallet_id": topup["wallet_id"],
            "parcel_id": None, "amount": topup["amount"], "currency": "XOF",
            "tx_type": "credit", "description": "Recharge du solde par carte",
            "reference": session_id, "created_at": now,
        }
        try:
            await db.wallet_transactions.update_one(
                {"tx_id": transaction["tx_id"]}, {"$setOnInsert": transaction}, upsert=True,
            )
        except DuplicateKeyError:
            if not await db.wallet_transactions.find_one({"tx_id": transaction["tx_id"]}):
                raise
    await db.wallet_topups.update_one(
        {"topup_id": topup["topup_id"]},
        {"$set": {"status": "paid", "provider_session_id": session_id,
                  "provider_payment_intent": session["payment_intent"].get("id") if isinstance(session.get("payment_intent"), dict) else session.get("payment_intent"), "updated_at": now,
                  "paid_at": topup.get("paid_at") or now},
         "$unset": {"verification_message": ""}},
    )
    return await db.wallet_topups.find_one({"topup_id": topup["topup_id"]}, {"_id": 0})


async def _reconcile_topup(topup: dict) -> None:
    session_id = str(topup.get("provider_session_id") or "")
    if not session_id.startswith("cs_") or not session_id.replace("_", "").isalnum():
        return
    now = datetime.now(timezone.utc)
    claimed = await db.wallet_topups.find_one_and_update(
        {"topup_id": topup["topup_id"], "status": "pending", "$or": [
            {"last_checked_at": {"$exists": False}},
            {"last_checked_at": {"$lte": now - timedelta(seconds=settings.STRIPE_RECONCILE_INTERVAL_SECONDS)}},
        ]},
        {"$set": {"last_checked_at": now}}, return_document=ReturnDocument.AFTER,
    )
    if not claimed:
        return
    try:
        async with httpx.AsyncClient(timeout=settings.STRIPE_HTTP_TIMEOUT_SECONDS) as client:
            response = await client.get(
                f"{STRIPE_BASE_URL}/checkout/sessions/{session_id}", headers=_stripe_headers(),
                params={"expand[]": "payment_intent.latest_charge"},
            )
            response.raise_for_status()
            session = response.json()
            if not isinstance(session, dict):
                raise ValueError("Invalid Stripe session")
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("Stripe verification unavailable: topup=%s error=%s", topup["topup_id"], type(exc).__name__)
        await db.wallet_topups.update_one(
            {"topup_id": topup["topup_id"], "status": "pending"},
            {"$set": {"verification_message": "Vérification du paiement momentanément indisponible. Ne payez pas une deuxième fois."}},
        )
        return
    if session.get("payment_status") == "paid":
        try:
            if not isinstance(session.get("payment_intent"), dict):
                raise bad_request_exception("Confirmation Stripe incomplète")
            await _fulfill_paid_session(claimed, session)
        except HTTPException:
            logger.error("Stripe confirmation mismatch: topup=%s", topup["topup_id"])
            await db.wallet_topups.update_one(
                {"topup_id": topup["topup_id"], "status": "pending"},
                {"$set": {"verification_message": "Le paiement nécessite une vérification par le support. Ne payez pas une deuxième fois."}},
            )
    elif session.get("status") == "expired":
        await db.wallet_topups.update_one(
            {"topup_id": topup["topup_id"], "status": "pending"},
            {"$set": {"status": "expired", "updated_at": now}, "$unset": {"verification_message": ""}},
        )
    else:
        await db.wallet_topups.update_one(
            {"topup_id": topup["topup_id"], "status": "pending"}, {"$unset": {"verification_message": ""}},
        )


async def reconcile_wallet_topups(owner_id: str, topup_id: Optional[str] = None) -> None:
    if not settings.STRIPE_SECRET_KEY:
        return
    query = {"owner_id": owner_id, "status": "pending", "provider_session_id": {"$type": "string"}}
    if topup_id:
        query["topup_id"] = topup_id
    topups = await db.wallet_topups.find(query, {"_id": 0}).sort([
        ("last_checked_at", 1), ("created_at", -1),
    ]).limit(settings.STRIPE_RECONCILE_LIMIT).to_list(length=settings.STRIPE_RECONCILE_LIMIT)
    await asyncio.gather(*(_reconcile_topup(topup) for topup in topups))


async def get_wallet_topup(owner_id: str, topup_id: str) -> dict:
    query = {"owner_id": owner_id, "topup_id": topup_id}
    if not await db.wallet_topups.find_one(query, {"_id": 0}):
        raise not_found_exception("Recharge")
    await reconcile_wallet_topups(owner_id, topup_id)
    return _public_topup(await db.wallet_topups.find_one(query, {"_id": 0}))


async def handle_stripe_event(payload: bytes, signature_header: Optional[str]) -> dict[str, Any]:
    verify_stripe_signature(payload, signature_header)
    try:
        event = json.loads(payload.decode("utf-8"))
    except Exception:
        raise bad_request_exception("Payload Stripe invalide")
    if not isinstance(event, dict):
        raise bad_request_exception("Payload Stripe invalide")

    if event.get("type") not in {"checkout.session.completed", "checkout.session.async_payment_succeeded"}:
        return {"received": True, "ignored": event.get("type")}

    data = event.get("data")
    if not isinstance(data, dict) or not isinstance(data.get("object"), dict):
        raise bad_request_exception("Payload Stripe invalide")
    session = data["object"]
    if session.get("payment_status") != "paid":
        return {"received": True, "status": "not_paid"}

    metadata = session.get("metadata") or {}
    if not isinstance(metadata, dict):
        raise bad_request_exception("Payload Stripe invalide")
    topup_id = metadata.get("topup_id") or session.get("client_reference_id")
    if not topup_id:
        return {"received": True, "ignored": "missing_topup_id"}

    topup = await db.wallet_topups.find_one({"topup_id": topup_id}, {"_id": 0})
    if not topup:
        return {"received": True, "ignored": "unknown_topup"}
    if topup.get("status") == "paid":
        return {"received": True, "status": "already_processed"}

    await _fulfill_paid_session(topup, session)
    return {"received": True, "status": "credited", "topup_id": topup_id}
