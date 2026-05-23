import hashlib
import hmac
import json
import logging
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

import httpx

from config import settings
from core.exceptions import bad_request_exception
from database import db
from services.wallet_service import get_or_create_wallet, credit_wallet

logger = logging.getLogger(__name__)

STRIPE_BASE_URL = "https://api.stripe.com/v1"


def _topup_id() -> str:
    return f"top_{uuid.uuid4().hex[:12]}"


def _stripe_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {settings.STRIPE_SECRET_KEY}",
        "Content-Type": "application/x-www-form-urlencoded",
    }


def _wallet_redirect_url(kind: str) -> str:
    configured = (
        settings.STRIPE_WALLET_SUCCESS_URL
        if kind == "success"
        else settings.STRIPE_WALLET_CANCEL_URL
    )
    if configured:
        return configured
    public_url = str(settings.PUBLIC_SITE_URL).rstrip("/")
    return f"{public_url}/wallet/stripe/{kind}"


async def create_wallet_topup_checkout(
    *,
    user: dict[str, Any],
    amount: float,
) -> dict[str, Any]:
    if not settings.STRIPE_SECRET_KEY:
        raise bad_request_exception("Stripe n'est pas encore configuré")
    if amount < settings.WALLET_TOPUP_MIN_XOF:
        raise bad_request_exception(
            f"Montant minimum: {int(settings.WALLET_TOPUP_MIN_XOF)} XOF"
        )
    if amount > settings.WALLET_TOPUP_MAX_XOF:
        raise bad_request_exception(
            f"Montant maximum: {int(settings.WALLET_TOPUP_MAX_XOF)} XOF"
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
        "success_url": _wallet_redirect_url("success"),
        "cancel_url": _wallet_redirect_url("cancel"),
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
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                f"{STRIPE_BASE_URL}/checkout/sessions",
                data=data,
                headers=_stripe_headers(),
            )
            response.raise_for_status()
            session = response.json()
    except httpx.HTTPStatusError as exc:
        detail = exc.response.text
        await db.wallet_topups.update_one(
            {"topup_id": topup_id},
            {"$set": {"status": "failed", "provider_error": detail, "updated_at": now}},
        )
        logger.error("Stripe checkout error: %s", detail)
        raise bad_request_exception("Création du paiement Stripe impossible")
    except Exception as exc:
        await db.wallet_topups.update_one(
            {"topup_id": topup_id},
            {"$set": {"status": "failed", "provider_error": str(exc), "updated_at": now}},
        )
        logger.error("Stripe checkout network error: %s", exc)
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

    parts = dict(
        item.split("=", 1)
        for item in signature_header.split(",")
        if "=" in item
    )
    timestamp = parts.get("t")
    signature = parts.get("v1")
    if not timestamp or not signature:
        raise bad_request_exception("Signature Stripe invalide")
    if abs(int(time.time()) - int(timestamp)) > 300:
        raise bad_request_exception("Signature Stripe expirée")

    signed_payload = f"{timestamp}.".encode("utf-8") + payload
    expected = hmac.new(
        settings.STRIPE_WEBHOOK_SECRET.encode("utf-8"),
        signed_payload,
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(expected, signature):
        raise bad_request_exception("Signature Stripe invalide")


async def handle_stripe_event(payload: bytes, signature_header: Optional[str]) -> dict[str, Any]:
    verify_stripe_signature(payload, signature_header)
    try:
        event = json.loads(payload.decode("utf-8"))
    except Exception:
        raise bad_request_exception("Payload Stripe invalide")

    if event.get("type") != "checkout.session.completed":
        return {"received": True, "ignored": event.get("type")}

    session = event.get("data", {}).get("object", {})
    if session.get("payment_status") != "paid":
        return {"received": True, "status": "not_paid"}

    metadata = session.get("metadata") or {}
    topup_id = metadata.get("topup_id") or session.get("client_reference_id")
    if not topup_id:
        return {"received": True, "ignored": "missing_topup_id"}

    topup = await db.wallet_topups.find_one({"topup_id": topup_id}, {"_id": 0})
    if not topup:
        return {"received": True, "ignored": "unknown_topup"}
    if topup.get("status") == "paid":
        return {"received": True, "status": "already_processed"}

    amount = float(topup.get("amount") or 0)
    session_amount = session.get("amount_total")
    if session_amount is not None and abs(float(session_amount) - amount) > 1:
        raise bad_request_exception("Montant Stripe incohérent")

    await credit_wallet(
        owner_id=topup["owner_id"],
        owner_type="driver",
        amount=amount,
        description="Recharge wallet Stripe",
        reference=session.get("id") or topup_id,
        count_as_earned=False,
        ensure_unique=True,
    )
    await db.wallet_topups.update_one(
        {"topup_id": topup_id},
        {
            "$set": {
                "status": "paid",
                "provider_session_id": session.get("id"),
                "provider_payment_intent": session.get("payment_intent"),
                "paid_at": datetime.now(timezone.utc),
                "updated_at": datetime.now(timezone.utc),
            }
        },
    )
    return {"received": True, "status": "credited", "topup_id": topup_id}
