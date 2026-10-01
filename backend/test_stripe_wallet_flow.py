import asyncio
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import hmac
import json
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch
from urllib.parse import parse_qs, urlsplit

from fastapi import FastAPI, HTTPException
import httpx
import mongomock
from pydantic import ValidationError

from config import Settings, settings
from core.dependencies import get_current_user
from routers import wallets
from services import stripe_service, wallet_service

HTTP_CLIENT = httpx.AsyncClient


class Cursor:
    def __init__(self, cursor):
        self.cursor = cursor

    def sort(self, *args):
        self.cursor = self.cursor.sort(*args)
        return self

    def limit(self, value):
        self.cursor = self.cursor.limit(value)
        return self

    async def to_list(self, length=None):
        rows = list(self.cursor)
        return rows if length is None else rows[:length]


class Collection:
    def __init__(self, collection):
        self.collection = collection

    def find(self, *args, **kwargs):
        return Cursor(self.collection.find(*args, **kwargs))

    async def find_one(self, *args, **kwargs):
        await asyncio.sleep(0)
        return self.collection.find_one(*args, **kwargs)

    async def find_one_and_update(self, *args, **kwargs):
        await asyncio.sleep(0)
        return self.collection.find_one_and_update(*args, **kwargs)

    async def update_one(self, *args, **kwargs):
        await asyncio.sleep(0)
        return self.collection.update_one(*args, **kwargs)

    async def insert_one(self, document):
        return self.collection.insert_one(document)


class StripeWalletTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.storage = mongomock.MongoClient(tz_aware=True).synthetic
        self.storage.wallet_transactions.create_index("tx_id", unique=True)
        self.database = SimpleNamespace(**{name: Collection(self.storage[name]) for name in (
            "wallets", "wallet_topups", "wallet_transactions", "delivery_missions", "users",
        )})
        self.user = {"user_id": "driver", "role": "driver"}
        self.now = datetime.now(timezone.utc)
        self.topup = {"topup_id": "top_synthetic", "owner_id": "driver", "wallet_id": "wallet",
            "amount": 500, "currency": "XOF", "status": "pending", "created_at": self.now,
            "provider_session_id": "cs_test_synthetic"}
        self.session = {"id": "cs_test_synthetic", "mode": "payment", "status": "complete",
            "payment_status": "paid", "currency": "xof", "amount_total": 500,
            "client_reference_id": "top_synthetic", "payment_intent": "pi_synthetic",
            "metadata": {"topup_id": "top_synthetic", "user_id": "driver", "wallet_id": "wallet"}}
        self.storage.wallets.insert_one({"wallet_id": "wallet", "owner_id": "driver", "balance": 6306,
            "owner_type": "driver", "currency": "XOF"})
        self.storage.wallet_topups.insert_one(deepcopy(self.topup))
        for module in (stripe_service, wallet_service, wallets):
            patcher = patch.object(module, "db", self.database)
            patcher.start()
            self.addCleanup(patcher.stop)
        for name, value in (("STRIPE_SECRET_KEY", "synthetic-only"), ("STRIPE_WEBHOOK_SECRET", "synthetic-webhook"),
                ("STRIPE_WALLET_SUCCESS_URL", None), ("STRIPE_WALLET_CANCEL_URL", None),
                ("PUBLIC_SITE_URL", "https://denkma.com"), ("WALLET_TOPUP_MIN_XOF", 500.0), ("WALLET_TOPUP_MAX_XOF", 500000.0)):
            patcher = patch.object(settings, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.provider = SimpleNamespace(get=AsyncMock(side_effect=self.retrieve), post=AsyncMock(side_effect=self.create))
        self.manager = AsyncMock()
        self.manager.__aenter__.return_value = self.provider
        self.manager.__aexit__.return_value = None
        patcher = patch.object(stripe_service.httpx, "AsyncClient", return_value=self.manager)
        patcher.start()
        self.addCleanup(patcher.stop)

    async def retrieve(self, url, **kwargs):
        session = deepcopy(self.session)
        if isinstance(session.get("payment_intent"), str):
            session["payment_intent"] = {"id": "pi_synthetic", "status": "succeeded", "amount_received": 500,
                "latest_charge": {"id": "ch_synthetic", "refunded": False, "amount_refunded": 0, "disputed": False}}
        return httpx.Response(200, json=session, request=httpx.Request("GET", url))

    async def create(self, url, **kwargs):
        return httpx.Response(200, json={"id": "cs_test_new", "url": "https://checkout.stripe.com/c/pay/synthetic"},
            request=httpx.Request("POST", url))

    def event(self):
        payload = json.dumps({"type": "checkout.session.completed", "data": {"object": self.session}}).encode()
        timestamp = str(int(self.now.timestamp()))
        signature = hmac.new(b"synthetic-webhook", timestamp.encode() + b"." + payload, hashlib.sha256).hexdigest()
        return payload, f"t={timestamp},v1={signature}"

    def assert_credit_once(self):
        self.assertEqual(self.storage.wallets.find_one({"wallet_id": "wallet"})["balance"], 6806)
        self.assertEqual(self.storage.wallet_transactions.count_documents({}), 1)
        self.assertEqual(self.storage.wallet_topups.find_one({"topup_id": "top_synthetic"})["status"], "paid")
        self.assertEqual(self.storage.users.count_documents({}), 0)

    async def test_refresh_recovers_paid_session_without_webhook(self):
        result = await wallets.get_my_wallet(self.user)
        self.assert_credit_once()
        self.assertEqual(result["balance"], 6806)
        self.assertEqual(result["topups"][0]["status"], "paid")
        self.assertNotIn("stripe_credited_topups", result)
        self.assertNotIn("provider_session_id", result["topups"][0])

    async def test_webhook_and_refresh_concurrently_credit_once(self):
        payload, signature = self.event()
        await asyncio.gather(stripe_service.reconcile_wallet_topups("driver"), *(
            stripe_service.handle_stripe_event(payload, signature) for _ in range(12)))
        self.assert_credit_once()
        await stripe_service.handle_stripe_event(payload, signature)
        self.assert_credit_once()

    async def test_recover_after_interrupt_between_balance_and_transaction(self):
        with patch.object(self.database.wallet_transactions, "update_one", AsyncMock(side_effect=RuntimeError("synthetic interrupt"))):
            with self.assertRaises(RuntimeError):
                await stripe_service._fulfill_paid_session(self.topup, self.session)
        self.assertEqual(self.storage.wallets.find_one({})["balance"], 6806)
        await stripe_service._fulfill_paid_session(self.topup, self.session)
        self.assert_credit_once()

    async def test_legacy_transaction_is_not_credited_twice(self):
        self.storage.wallets.update_one({}, {"$set": {"balance": 6806}})
        self.storage.wallet_transactions.insert_one({"tx_id": "legacy", "wallet_id": "wallet",
            "reference": "cs_test_synthetic", "tx_type": "credit", "amount": 500})
        await stripe_service._fulfill_paid_session(self.topup, self.session)
        self.assert_credit_once()

    async def test_mismatched_payment_is_never_credited(self):
        for field, value in (("currency", "eur"), ("amount_total", 501), ("amount_total", None),
                ("id", "cs_test_other"), ("payment_status", "unpaid"), ("client_reference_id", "other"),
                ("mode", "subscription")):
            with self.subTest(field=field):
                session = {**self.session, field: value}
                with self.assertRaises(HTTPException):
                    await stripe_service._fulfill_paid_session(self.topup, session)
        for field in ("topup_id", "user_id", "wallet_id"):
            with self.subTest(metadata=field):
                session = {**self.session, "metadata": {**self.session["metadata"], field: "other"}}
                with self.assertRaises(HTTPException):
                    await stripe_service._fulfill_paid_session(self.topup, session)
        self.assertEqual(self.storage.wallets.find_one({})["balance"], 6306)
        self.assertEqual(self.storage.wallet_transactions.count_documents({}), 0)

    async def test_wrong_provider_confirmation_is_visible_without_hiding_balance(self):
        self.session["currency"] = "eur"
        result = await wallets.get_my_wallet(self.user)
        self.assertEqual(result["balance"], 6306)
        self.assertIn("support", result["topups"][0]["verification_message"])

    async def test_refunded_or_disputed_payment_is_not_recovered_as_a_new_credit(self):
        for charge in ({"refunded": True, "amount_refunded": 500, "disputed": False},
                {"refunded": False, "amount_refunded": 100, "disputed": False},
                {"refunded": False, "amount_refunded": 0, "disputed": True}):
            self.session["payment_intent"] = {"id": "pi_synthetic", "status": "succeeded", "amount_received": 500,
                "latest_charge": charge}
            self.storage.wallet_topups.update_one({}, {"$unset": {"last_checked_at": ""}})
            result = await wallets.get_my_wallet(self.user)
            self.assertEqual(result["balance"], 6306)
            self.assertIn("support", result["topups"][0]["verification_message"])

    async def test_provider_outage_keeps_payment_pending_and_balance_readable(self):
        self.provider.get.side_effect = httpx.ConnectError("synthetic outage")
        result = await wallets.get_my_wallet(self.user)
        self.assertEqual(result["balance"], 6306)
        self.assertEqual(result["topups"][0]["status"], "pending")
        self.assertIn("Ne payez pas", result["topups"][0]["verification_message"])
        await wallets.get_my_wallet(self.user)
        self.assertEqual(self.provider.get.await_count, 1)

    async def test_invalid_provider_payload_keeps_balance_readable(self):
        self.provider.get.side_effect = None
        self.provider.get.return_value = httpx.Response(200, json=[],
            request=httpx.Request("GET", "https://synthetic.local"))
        result = await wallets.get_my_wallet(self.user)
        self.assertEqual(result["balance"], 6306)
        self.assertEqual(result["topups"][0]["status"], "pending")
        self.assertIn("Ne payez pas", result["topups"][0]["verification_message"])

    async def test_missing_wallet_credit_never_creates_paid_ledger_entry(self):
        with patch.object(self.database.wallets, "update_one", AsyncMock(
                return_value=SimpleNamespace(matched_count=0))):
            with self.assertRaises(HTTPException):
                await stripe_service._fulfill_paid_session(self.topup, self.session)
        self.assertEqual(self.storage.wallet_topups.find_one({})["status"], "pending")
        self.assertEqual(self.storage.wallet_transactions.count_documents({}), 0)
        self.assertEqual(self.storage.wallets.find_one({})["balance"], 6306)

    async def test_incomplete_checkout_is_failed_and_not_exposed_as_a_payment(self):
        self.provider.post.side_effect = None
        self.provider.post.return_value = httpx.Response(200, json={"id": "cs_test_incomplete"},
            request=httpx.Request("POST", "https://synthetic.local"))
        with self.assertRaises(HTTPException) as error:
            await stripe_service.create_wallet_topup_checkout(user=self.user, amount=500)
        self.assertEqual(error.exception.detail, "Stripe indisponible pour le moment")
        self.assertEqual(self.storage.wallet_topups.count_documents({"status": "failed"}), 1)
        self.assertEqual(self.storage.wallet_transactions.count_documents({}), 0)

    async def test_unpaid_and_expired_sessions_never_credit(self):
        self.session.update(payment_status="unpaid", status="expired")
        await stripe_service.reconcile_wallet_topups("driver")
        self.assertEqual(self.storage.wallets.find_one({})["balance"], 6306)
        self.assertEqual(self.storage.wallet_topups.find_one({})["status"], "expired")

    async def test_other_owner_cannot_verify_or_read_payment(self):
        with self.assertRaises(HTTPException) as error:
            await stripe_service.get_wallet_topup("other", "top_synthetic")
        self.assertEqual(error.exception.status_code, 404)
        self.provider.get.assert_not_awaited()
        self.assertEqual(await stripe_service.get_wallet_topups("other"), [])

    async def test_return_url_uses_existing_app_link_and_preserves_configuration(self):
        for kind in ("success", "cancel"):
            parts = urlsplit(stripe_service._wallet_redirect_url(kind, "top_synthetic"))
            self.assertEqual(parts.path, "/app/")
            self.assertEqual(parse_qs(parts.query), {"wallet_return": [kind], "topup_id": ["top_synthetic"]})
        with patch.object(settings, "STRIPE_WALLET_SUCCESS_URL", "https://denkma.com/wallet/stripe/success?source=old"):
            parts = urlsplit(stripe_service._wallet_redirect_url("success", "top_synthetic"))
            self.assertEqual(parts.path, "/wallet/stripe/success")
            self.assertEqual(parse_qs(parts.query)["source"], ["old"])

    async def test_creation_uses_idempotency_and_return_reference(self):
        result = await stripe_service.create_wallet_topup_checkout(user=self.user, amount=500)
        sent = self.provider.post.call_args.kwargs
        self.assertEqual(sent["headers"]["Idempotency-Key"], result["topup_id"])
        self.assertEqual(parse_qs(urlsplit(sent["data"]["success_url"]).query)["topup_id"], [result["topup_id"]])
        self.assertEqual(sent["data"]["line_items[0][price_data][unit_amount]"], "500")

    async def test_amount_validation_uses_server_configuration(self):
        for amount in (300, 500001, 500.5):
            with self.assertRaises(HTTPException):
                await stripe_service.create_wallet_topup_checkout(user=self.user, amount=amount)
        with patch.object(settings, "WALLET_TOPUP_MIN_XOF", 1200.0):
            with self.assertRaises(HTTPException) as error:
                await wallets.create_stripe_wallet_topup(wallets.StripeTopupRequest(amount=500), self.user)
            self.assertIn("1 200", error.exception.detail)
            self.assertEqual(stripe_service.wallet_topup_options()["minimum_amount"], 1200)
        self.provider.post.assert_not_awaited()
        for amount in (float("nan"), float("inf"), -500, 0):
            with self.assertRaises(ValidationError):
                wallets.StripeTopupRequest(amount=amount)

    async def test_signed_webhook_supports_secret_rotation_and_rejects_bad_timestamp(self):
        payload, signature = self.event()
        stripe_service.verify_stripe_signature(payload, signature + ",v1=invalid")
        for invalid in ("t=bad,v1=invalid", "t=0,v1=invalid", None):
            with self.assertRaises(HTTPException):
                stripe_service.verify_stripe_signature(payload, invalid)

    async def test_http_routes_reconcile_only_authenticated_account(self):
        app = FastAPI()
        app.include_router(wallets.router, prefix="/api/wallets")
        app.dependency_overrides[get_current_user] = lambda: self.user
        async with HTTP_CLIENT(transport=httpx.ASGITransport(app=app), base_url="https://synthetic.local") as client:
            response = await client.get("/api/wallets/me")
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json()["balance"], 6806)
            self.assertEqual(response.json()["topups"][0]["status"], "paid")
            missing = await client.get("/api/wallets/me/topups/stripe/top_other")
            self.assertEqual(missing.status_code, 404)
            app.dependency_overrides[get_current_user] = lambda: {"user_id": "other", "role": "driver"}
            forbidden = await client.get("/api/wallets/me/topups/stripe/top_synthetic")
            self.assertEqual(forbidden.status_code, 404)

    async def test_http_amount_error_is_a_french_message_not_a_schema_dump(self):
        app = FastAPI()
        app.include_router(wallets.router, prefix="/api/wallets")
        app.dependency_overrides[get_current_user] = lambda: self.user
        async with HTTP_CLIENT(transport=httpx.ASGITransport(app=app), base_url="https://synthetic.local") as client:
            response = await client.post("/api/wallets/me/topups/stripe", json={"amount": 300})
            self.assertEqual(response.status_code, 400)
            self.assertEqual(response.json()["detail"], "Le montant minimum de recharge est de 500 FCFA")
            self.provider.post.assert_not_awaited()


class StripeConfigurationTests(unittest.TestCase):
    def test_invalid_recharge_limits_are_rejected(self):
        for minimum, maximum in ((1000, 500), (500.5, 1000), (0, 1000)):
            with self.assertRaises(ValidationError):
                Settings(_env_file=None, WALLET_TOPUP_MIN_XOF=minimum, WALLET_TOPUP_MAX_XOF=maximum)


if __name__ == "__main__":
    unittest.main()
