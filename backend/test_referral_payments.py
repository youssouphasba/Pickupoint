import asyncio
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
import unittest
import importlib
import sys
from unittest.mock import AsyncMock, patch

import mongomock
from fastapi import HTTPException

from services import referral_service as referrals
from services import user_service
from services.loyalty_service import _check_referral_bonus


class AsyncCursor:
    def __init__(self, cursor):
        self.cursor = cursor

    def sort(self, *args):
        self.cursor = self.cursor.sort(*args)
        return self

    def skip(self, count):
        self.cursor = self.cursor.skip(count)
        return self

    def limit(self, count):
        self.cursor = self.cursor.limit(count)
        return self

    async def to_list(self, length=None):
        items = list(self.cursor)
        return items if length is None else items[:length]


class AsyncCollection:
    def __init__(self, collection):
        self.collection = collection

    def __getattr__(self, name):
        if name in {"find", "aggregate"}:
            def cursor(*args, **kwargs):
                kwargs.pop("session", None)
                return AsyncCursor(getattr(self.collection, name)(*args, **kwargs))
            return cursor
        async def operation(*args, **kwargs):
            kwargs.pop("session", None)
            await asyncio.sleep(0)
            return getattr(self.collection, name)(*args, **kwargs)
        return operation


class ReferralTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.raw_db = mongomock.MongoClient(tz_aware=True).referral_tests
        self.db = SimpleNamespace(**{name: AsyncCollection(self.raw_db[name]) for name in (
            "users", "user_sessions", "app_settings", "referrals", "parcels", "parcel_events", "delivery_missions", "wallet_transactions", "wallets",
        )})
        self.settings = {"key": "global", "referral_roles": {
            "client": {"enabled": True, "sponsor_bonus_xof": 750, "referred_bonus_xof": 450,
                       "reward_metric": "delivered_sender_parcels", "reward_count": 2,
                       "apply_metric": "sent_parcels", "apply_max_count": 0, "max_referrals_per_sponsor": 0},
            "driver": {"enabled": True, "sponsor_bonus_xof": 1200, "referred_bonus_xof": 900,
                       "reward_metric": "completed_driver_deliveries", "reward_count": 3,
                       "apply_metric": "completed_driver_deliveries", "apply_max_count": 0, "max_referrals_per_sponsor": 0},
        }}
        self.raw_db.app_settings.insert_one(deepcopy(self.settings))
        self.raw_db.users.insert_many([
            {"user_id": "s1", "name": "Parrain", "role": "driver", "is_active": True, "referral_code": "PARRAIN"},
            {"user_id": "r1", "name": "Filleul", "role": "client", "is_active": True, "referred_by": "s1"},
        ])
        self.now = datetime.now(timezone.utc)
        self.admin = {"user_id": "admin", "name": "Admin", "role": "admin"}
        self.lock = asyncio.Lock()
        owner = self
        class Session:
            async def __aenter__(self): return self
            async def __aexit__(self, *args): return False
            async def with_transaction(self, operation):
                async with owner.lock:
                    before = {name: list(owner.raw_db[name].find()) for name in owner.raw_db.list_collection_names()}
                    try:
                        return await operation(self)
                    except Exception:
                        for name in owner.raw_db.list_collection_names():
                            owner.raw_db[name].delete_many({})
                        for name, documents in before.items():
                            if documents:
                                owner.raw_db[name].insert_many(documents)
                        raise
        self.client = SimpleNamespace(start_session=AsyncMock(side_effect=Session))
        for module in (referrals, user_service):
            patcher = patch.object(module, "db", self.db)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(referrals, "get_client", return_value=self.client)
        patcher.start()
        self.addCleanup(patcher.stop)
        await self.create()

    async def create(self, user_id="r1", role="client"):
        await referrals.upsert_referral_record(sponsor_user_id="s1", referred_user_id=user_id,
            referred_role=role, referral_code="PARRAIN", source="test", settings_doc=self.settings)

    def deliveries(self, user_id="r1", count=2):
        self.raw_db.parcels.insert_many([{"sender_user_id": user_id, "status": "delivered"} for _ in range(count)])

    async def confirm(self, role="sponsor", amount=None):
        return await referrals.confirm_external_payment("ref_r1", role, amount or (750 if role == "sponsor" else 450),
            self.now, "preuve", "note interne", self.admin)

    async def test_conditions_and_paid_amounts_never_follow_new_configuration(self):
        self.deliveries()
        self.raw_db.app_settings.update_one({"key": "global"}, {"$set": {"referral_roles.client.sponsor_bonus_xof": 9999, "referral_roles.client.reward_count": 99}})
        await referrals.refresh_referral_progress("r1")
        result = await self.confirm()
        await self.create()
        await referrals.refresh_referral_progress("r1")
        record = self.raw_db.referrals.find_one({"referral_id": "ref_r1"})
        self.assertEqual(record["reward_count"], 2)
        self.assertEqual(record["sponsor_bonus_xof"], 750)
        self.assertEqual(result["referral"]["payments"]["sponsor"]["paid_amount_xof"], 750)

    async def test_qualification_does_not_credit_any_wallet(self):
        self.deliveries()
        with patch("services.loyalty_service.db", self.db):
            await _check_referral_bonus("r1")
        self.assertEqual(self.raw_db.referrals.find_one()["status"], "qualified")
        self.assertEqual(self.raw_db.wallets.count_documents({}), 0)
        self.assertEqual(self.raw_db.wallet_transactions.count_documents({}), 0)
        self.assertNotIn("referral_credited", self.raw_db.users.find_one({"user_id": "r1"}))

    async def test_beneficiaries_are_confirmed_separately_and_idempotently(self):
        self.deliveries()
        first = await self.confirm()
        self.assertEqual(first["referral"]["status"], "partially_paid")
        self.assertEqual(first["referral"]["payments"]["referred"]["status"], "pending")
        second = await self.confirm("referred")
        self.assertEqual(second["referral"]["status"], "rewarded")
        again = await self.confirm()
        self.assertTrue(again["already_confirmed"])
        self.assertEqual(len(again["referral"]["payment_history"]), 2)
        self.assertEqual(self.raw_db.parcel_events.count_documents({}), 2)
        self.assertEqual(self.raw_db.wallet_transactions.count_documents({}), 0)

    async def test_simultaneous_confirmations_never_lose_a_beneficiary_or_duplicate_history(self):
        self.deliveries()
        results = await asyncio.gather(self.confirm(), self.confirm(), self.confirm("referred"), self.confirm("referred"))
        record = self.raw_db.referrals.find_one()
        self.assertEqual(record["status"], "rewarded")
        self.assertEqual(len(record["payment_history"]), 2)
        self.assertEqual(self.raw_db.parcel_events.count_documents({}), 2)
        self.assertEqual(sum(not result["already_confirmed"] for result in results), 2)

    async def test_invalid_amount_future_date_and_unqualified_referral_rejected(self):
        with self.assertRaises(HTTPException):
            await self.confirm()
        self.deliveries()
        with self.assertRaises(HTTPException):
            await self.confirm(amount=751)
        with self.assertRaises(HTTPException):
            await referrals.confirm_external_payment("ref_r1", "sponsor", 750, self.now + timedelta(days=1), None, None, self.admin)
        self.assertEqual(self.raw_db.referrals.find_one()["payment_history"], [])

    async def test_historical_wallet_credit_is_preserved_and_not_paid_again(self):
        self.raw_db.referrals.update_one({}, {"$unset": {"schema_version": "", "payments": ""}, "$set": {"status": "rewarded", "sponsor_transaction_reference": "ref_bonus_sponsor_r1", "referred_transaction_reference": "ref_bonus_self_r1"}})
        self.raw_db.wallet_transactions.insert_many([
            {"reference": "ref_bonus_sponsor_r1", "amount": 800, "created_at": self.now},
            {"reference": "ref_bonus_self_r1", "amount": 300, "created_at": self.now},
        ])
        self.raw_db.wallets.insert_one({"owner_id": "s1", "balance": 800})
        result = await self.confirm()
        self.assertTrue(result["already_confirmed"])
        self.assertEqual(result["referral"]["payments"]["sponsor"]["status"], "legacy_wallet")
        self.assertEqual(result["referral"]["payments"]["sponsor"]["paid_amount_xof"], 800)
        self.assertEqual(self.raw_db.wallets.find_one()["balance"], 800)
        self.assertEqual((await referrals.referral_totals({}))["total_sponsor_bonus_xof"], 0)

    async def test_ambiguous_history_requires_review_instead_of_new_payment(self):
        self.raw_db.referrals.update_one({}, {"$unset": {"schema_version": "", "payments": ""}, "$set": {"status": "rewarded"}})
        with self.assertRaises(HTTPException):
            await self.confirm()
        self.assertEqual(self.raw_db.referrals.find_one()["payments"]["sponsor"]["status"], "needs_review")

    async def test_confirmed_legacy_external_payment_is_not_rewritten(self):
        self.raw_db.referrals.update_one({}, {"$unset": {"schema_version": "", "payments": ""}, "$set": {"status": "rewarded", "payment_confirmed_at": self.now}})
        totals = await referrals.referral_totals({})
        self.assertEqual(totals["total_sponsor_bonus_xof"], 750)
        record = await referrals.normalize_referral(self.raw_db.referrals.find_one())
        self.assertEqual(record["payments"]["sponsor"]["status"], "legacy_confirmed")
        self.assertTrue((await self.confirm())["already_confirmed"])

    async def test_zero_prime_is_not_a_payment_and_does_not_block_other_beneficiary(self):
        self.raw_db.referrals.delete_many({})
        self.settings["referral_roles"]["client"]["sponsor_bonus_xof"] = 0
        await self.create()
        self.deliveries()
        record = await referrals.refresh_referral_progress("r1")
        self.assertEqual(record["status"], "qualified")
        self.assertEqual(record["payments"]["sponsor"]["status"], "not_due")
        self.assertEqual((await self.confirm("referred"))["referral"]["status"], "rewarded")

    async def test_stats_cover_all_records_not_just_first_page_and_hide_internal_proof(self):
        self.raw_db.referrals.delete_many({})
        for index in range(31):
            user_id = f"r{index}"
            if index != 1:
                self.raw_db.users.insert_one({"user_id": user_id, "name": user_id, "role": "client"})
            await self.create(user_id)
            self.raw_db.referrals.update_one({"referred_user_id": user_id}, {"$set": {
                "status": "rewarded", "payments.sponsor.status": "confirmed", "payments.sponsor.paid_amount_xof": 750,
                "payments.sponsor.reference": "PRIVATE", "payments.sponsor.confirmed_by": "ADMIN",
                "payments.referred.status": "confirmed", "payments.referred.paid_amount_xof": 450,
                "payment_history": [{"event_id": "PRIVATE"}],
            }})
        summary = await referrals.sponsored_referral_summary("s1")
        self.assertEqual(summary["total"], 31)
        self.assertEqual(len(summary["items"]), 10)
        self.assertEqual(summary["total_sponsor_bonus_xof"], 31 * 750)
        self.assertNotIn("payment_history", summary["items"][0])
        self.assertNotIn("reference", summary["items"][0]["payments"]["sponsor"])
        self.assertNotIn("confirmed_by", summary["items"][0]["payments"]["sponsor"])
        self.assertNotIn("referred_phone", summary["items"][0])
        self.assertEqual(set(summary["items"][0]["payments"]), {"sponsor"})
        self.assertEqual(len((await referrals.referral_list({"sponsor_user_id": "s1"}, 10, 10))["items"]), 10)

    async def test_transaction_rejects_double_binding_and_cycles(self):
        self.raw_db.users.insert_one({"user_id": "u1", "role": "client"})
        results = await asyncio.gather(
            referrals.assign_referral("u1", "s1", "PARRAIN", self.settings, "test"),
            referrals.assign_referral("u1", "s1", "PARRAIN", self.settings, "test"), return_exceptions=True)
        self.assertEqual(sum(isinstance(value, HTTPException) for value in results), 1)
        self.assertEqual(self.raw_db.referrals.count_documents({"referred_user_id": "u1"}), 1)
        self.raw_db.users.insert_one({"user_id": "u2", "role": "client"})
        self.raw_db.users.update_one({"user_id": "s1"}, {"$set": {"referred_by": "u2"}})
        with self.assertRaises(HTTPException):
            await referrals.assign_referral("u2", "s1", "PARRAIN", self.settings, "test")

    async def test_signup_quota_is_atomic_and_failed_signup_is_rolled_back(self):
        self.settings["referral_roles"]["client"]["max_referrals_per_sponsor"] = 2
        results = await asyncio.gather(*[
            referrals.assign_referral(f"new{index}", "s1", "PARRAIN", self.settings, "signup",
                new_user_doc={"user_id": f"new{index}", "role": "client"}) for index in range(2)
        ], return_exceptions=True)
        self.assertEqual(sum(isinstance(value, HTTPException) for value in results), 1)
        self.assertEqual(self.raw_db.users.count_documents({"user_id": {"$regex": "^new"}}), 1)
        self.settings["referral_roles"]["client"]["max_referrals_per_sponsor"] = 0
        with patch.object(referrals, "upsert_referral_record", AsyncMock(side_effect=RuntimeError("insert failed"))):
            with self.assertRaises(RuntimeError):
                await referrals.assign_referral("rolled", "s1", "PARRAIN", self.settings, "signup",
                    new_user_doc={"user_id": "rolled", "role": "client"})
        self.assertIsNone(self.raw_db.users.find_one({"user_id": "rolled"}))

    async def test_mobile_endpoint_is_scoped_to_authenticated_sponsor(self):
        from routers.users import get_my_referrals
        result = await get_my_referrals(skip=0, limit=10, current_user={"user_id": "other"})
        self.assertEqual(result["items"], [])
        self.assertEqual(result["total"], 0)

    async def test_driver_invitation_defaults_to_actual_new_client_offer(self):
        from routers.users import _build_referral_payload
        with patch("routers.users.db", self.db):
            payload = await _build_referral_payload(self.raw_db.users.find_one({"user_id": "s1"}))
        self.assertEqual(payload["referral_sponsor_bonus_xof"], 750)
        self.assertIn("450 XOF", payload["share_message"])
        driver = next(offer for offer in payload["invitation_offers"] if offer["referred_role"] == "driver")
        self.assertEqual(driver["label"], "Compte déjà livreur")
        self.assertNotIn("Lien d'inscription", driver["share_message"])

    async def test_signup_router_binds_inside_transaction_and_respects_quota(self):
        firebase = SimpleNamespace(_apps=[True], credentials=SimpleNamespace(), auth=SimpleNamespace())
        with patch.dict(sys.modules, {"firebase_admin": firebase}):
            auth = importlib.import_module("routers.auth")
        self.addCleanup(lambda: sys.modules.pop("routers.auth", None))
        body = auth.CompleteRegistrationRequest(registration_token="x" * 20, name="Nouveau client",
            pin="1234", accepted_legal=True, referral_code="PARRAIN")
        with patch.object(auth, "db", self.db), patch("core.security.decode_token", return_value={"type": "registration_token", "sub": "+221771234567"}), patch("core.security.hash_password", return_value="hash"), patch.object(auth, "create_access_token", return_value="access"), patch.object(auth, "create_refresh_token", return_value="refresh"), patch.object(auth, "_record_event", AsyncMock()):
            response = await auth.complete_registration.__wrapped__(body, None)
        self.assertEqual(response.user.referred_by, "s1")
        record = self.raw_db.referrals.find_one({"referred_user_id": response.user.user_id})
        self.assertEqual(record["referred_role"], "client")
        self.assertEqual(record["sponsor_bonus_xof"], 750)
        self.settings["referral_roles"]["client"]["max_referrals_per_sponsor"] = 2
        self.raw_db.app_settings.replace_one({"key": "global"}, deepcopy(self.settings))
        with patch.object(auth, "db", self.db), patch("core.security.decode_token", return_value={"type": "registration_token", "sub": "+221771234568"}), patch("core.security.hash_password", return_value="hash"):
            with self.assertRaises(HTTPException):
                await auth.complete_registration.__wrapped__(body, None)
        self.assertIsNone(self.raw_db.users.find_one({"phone": "+221771234568"}))

    async def test_settings_preserve_share_url_and_reject_wrong_role_metric(self):
        from routers import admin
        self.raw_db.app_settings.update_one({"key": "global"}, {"$set": {"referral_share_base_url": "https://example.test/invite/{code}"}})
        body = admin.ReferralSettingsRequest(**self.settings["referral_roles"])
        with patch.object(admin, "db", self.db), patch.object(admin, "_record_event", AsyncMock()):
            await admin.update_referral_settings(body, _admin=self.admin)
            self.assertEqual(self.raw_db.app_settings.find_one()["referral_share_base_url"], "https://example.test/invite/{code}")
            body.driver.reward_metric = "sent_parcels"
            with self.assertRaises(HTTPException):
                await admin.update_referral_settings(body, _admin=self.admin)
        self.assertEqual(self.raw_db.app_settings.find_one()["referral_roles"]["driver"]["reward_metric"], "completed_driver_deliveries")

    async def test_note_only_cannot_confirm_both_beneficiaries(self):
        from pydantic import ValidationError
        from routers.admin import ReferralPaymentConfirmRequest
        with self.assertRaises(ValidationError):
            ReferralPaymentConfirmRequest(note="ancien bouton")

    async def test_existing_wallet_history_is_recovered_when_referral_record_missing(self):
        self.raw_db.referrals.delete_many({})
        self.raw_db.users.update_one({"user_id": "r1"}, {"$set": {"referral_credited": True}})
        self.raw_db.wallet_transactions.insert_one({"reference": "ref_bonus_sponsor_r1", "amount": 800, "created_at": self.now})
        record = await referrals.ensure_referral_record_for_user(self.raw_db.users.find_one({"user_id": "r1"}), self.settings)
        self.assertEqual(record["payments"]["sponsor"]["status"], "legacy_wallet")
        self.assertEqual(record["payments"]["sponsor"]["paid_amount_xof"], 800)
        self.assertEqual(record["payments"]["referred"]["status"], "needs_review")

    async def test_ambiguous_code_and_orphan_record_cannot_bind_a_new_sponsor(self):
        self.raw_db.users.insert_one({"user_id": "other_sponsor", "role": "client", "referral_code": "PARRAIN"})
        self.raw_db.users.insert_one({"user_id": "u1", "role": "client"})
        with self.assertRaises(HTTPException):
            await referrals.assign_referral("u1", "s1", "PARRAIN", self.settings, "test")
        self.raw_db.users.delete_one({"user_id": "other_sponsor"})
        await self.create("u1")
        with self.assertRaises(HTTPException):
            await referrals.assign_referral("u1", "s1", "PARRAIN", self.settings, "test")
        self.assertNotIn("referred_by", self.raw_db.users.find_one({"user_id": "u1"}))

    async def test_missing_record_recovers_credit_even_without_old_user_flag(self):
        self.raw_db.referrals.delete_many({})
        self.raw_db.wallet_transactions.insert_one({"reference": "ref_bonus_sponsor_r1", "amount": 800, "created_at": self.now})
        record = await referrals.ensure_referral_record_for_user(self.raw_db.users.find_one({"user_id": "r1"}), self.settings)
        self.assertEqual(record["payments"]["sponsor"]["status"], "legacy_wallet")
        self.assertTrue((await self.confirm())["already_confirmed"])
        self.assertEqual(self.raw_db.wallet_transactions.count_documents({}), 1)

    async def test_historical_duplicate_credits_display_actual_total_without_balance_mutation(self):
        self.raw_db.referrals.update_one({}, {"$unset": {"schema_version": "", "payments": ""}, "$set": {"status": "rewarded"}})
        self.raw_db.wallet_transactions.insert_many([
            {"reference": "ref_bonus_sponsor_r1", "amount": 800, "created_at": self.now - timedelta(days=1)},
            {"reference": "ref_bonus_sponsor_r1", "amount": 800, "created_at": self.now},
        ])
        self.raw_db.wallets.insert_one({"owner_id": "s1", "balance": 1600})
        record = await referrals.normalize_referral(self.raw_db.referrals.find_one())
        self.assertEqual(record["payments"]["sponsor"]["paid_amount_xof"], 1600)
        self.assertEqual(record["payments"]["sponsor"]["paid_at"], self.now.replace(microsecond=self.now.microsecond // 1000 * 1000))
        self.assertEqual(self.raw_db.wallets.find_one()["balance"], 1600)
        self.assertTrue((await self.confirm())["already_confirmed"])

    async def test_confirmation_survives_secondary_audit_failure_and_retry_repairs_it(self):
        self.deliveries()
        with patch.object(self.db.parcel_events, "update_one", AsyncMock(side_effect=RuntimeError("audit unavailable"))), self.assertLogs(referrals.logger, level="ERROR"):
            result = await self.confirm()
        self.assertFalse(result["already_confirmed"])
        self.assertEqual(len(result["referral"]["payment_history"]), 1)
        self.assertEqual(self.raw_db.parcel_events.count_documents({}), 0)
        self.assertTrue((await self.confirm())["already_confirmed"])
        self.assertEqual(self.raw_db.parcel_events.count_documents({}), 1)


if __name__ == "__main__":
    unittest.main()
