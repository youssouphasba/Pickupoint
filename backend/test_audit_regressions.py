import asyncio
from contextlib import ExitStack
from datetime import datetime, timedelta, timezone
from types import ModuleType
import sys
import unittest
from unittest.mock import AsyncMock, patch

from fastapi import HTTPException
from pydantic import ValidationError
from starlette.requests import Request

try:
    import firebase_admin
except ModuleNotFoundError:
    firebase_admin = ModuleType("firebase_admin")
    firebase_admin._apps = [object()]
    firebase_admin.auth = ModuleType("firebase_admin.auth")
    firebase_admin.credentials = ModuleType("firebase_admin.credentials")
    sys.modules.setdefault("firebase_admin", firebase_admin)
    sys.modules.setdefault("firebase_admin.auth", firebase_admin.auth)
    sys.modules.setdefault("firebase_admin.credentials", firebase_admin.credentials)

from core.parcel_privacy import serialize_parcel, redact_codes
from models.delivery import ProofOfDelivery
from models.parcel import ParcelRatingRequest, ParcelStatus, ParcelQuote, QuoteResponse
from models.user import ProfileUpdate, User
from models.wallet import PayoutRequest
from routers import auth, admin, deliveries, parcels, relay_points, wallets
from services import wallet_service, gamification_service, parcel_service, promotion_service, pricing_service, payout_service, delivery_completion_service, mission_trace, performance_rewards_service
from services.wallet_activity_service import wallet_activity
from tests.fake_database import Database


def account(role="driver", uid="driver"):
    now = datetime.now(timezone.utc)
    return dict(user_id=uid, role=role, phone="+221771234567", name="Test", is_active=True, is_available=True,
                profile_picture_url="https://example.test/photo", profile_picture_status="approved", created_at=now, updated_at=now)


class AuditRegressions(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.db = Database()
        self.raw = self.db.raw
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        for module in (auth, admin, deliveries, parcels, relay_points, wallets, wallet_service, gamification_service,
                       parcel_service, promotion_service, pricing_service, payout_service, delivery_completion_service, mission_trace, performance_rewards_service):
            if hasattr(module, "db"):
                self.stack.enter_context(patch.object(module, "db", self.db))
        self.stack.enter_context(patch.object(wallet_service, "get_client", return_value=self.db))
        for name in ("expire_mission_availability_notifications", "notify_sender_driver_assigned", "_record_event", "record_admin_event", "notify_driver_low_balance"):
            self.stack.enter_context(patch.object(deliveries, name, AsyncMock()))
        self.raw.users.insert_one(account())
        self.raw.wallets.insert_one(dict(wallet_id="wallet", owner_id="driver", owner_type="driver", balance=5000, pending=0))

    def mission(self, name="mission", *, commission=True):
        self.raw.parcels.insert_one(dict(parcel_id=name, status="created", delivery_mode="home_to_home",
                                        quoted_price=10000, delivery_commissions_enabled=commission, sender_user_id="sender"))
        self.raw.delivery_missions.insert_one(dict(mission_id=name, parcel_id=name, driver_id=None, status="pending", candidate_drivers=["driver"]))

    async def test_duplicate_credit_debit_and_revenue_are_idempotent(self):
        await asyncio.gather(*(wallet_service.credit_wallet("driver", "driver", 1000, "Credit", reference="credit", ensure_unique=True, count_as_earned=False) for _ in range(3)))
        await asyncio.gather(*(wallet_service.debit_wallet("driver", 200, "Debit", reference="debit", ensure_unique=True) for _ in range(3)))
        await asyncio.gather(*(wallet_service.record_driver_revenue("driver", 700, "Revenue", reference="revenue", ensure_unique=True) for _ in range(3)))
        self.assertEqual(self.raw.wallets.find_one()["balance"], 5800)
        self.assertEqual(self.raw.users.find_one()["total_earned"], 700)
        self.assertEqual(self.raw.wallet_transactions.count_documents({}), 3)

    async def test_ledger_and_balance_roll_back_after_failure(self):
        self.db.wallets.fail_next["update_one"] = RuntimeError("Synthetic interruption")
        with self.assertRaises(RuntimeError):
            await wallet_service.credit_wallet("driver", "driver", 1000, "Credit", reference="retry", ensure_unique=True)
        self.assertEqual(self.raw.wallets.find_one()["balance"], 5000)
        self.assertEqual(self.raw.wallet_transactions.count_documents({}), 0)
        await wallet_service.credit_wallet("driver", "driver", 1000, "Credit", reference="retry", ensure_unique=True)
        self.assertEqual(self.raw.wallets.find_one()["balance"], 6000)

    async def test_accept_release_cycles_never_create_money(self):
        self.mission()
        for _ in range(3):
            await deliveries.accept_mission("mission", body=None, current_user=account())
            balance = self.raw.wallets.find_one()["balance"]
            self.assertLess(balance, 5000)
            await deliveries.release_mission("mission", current_user=account())
            self.assertEqual(self.raw.wallets.find_one()["balance"], 5000)
        self.assertEqual(self.raw.wallet_transactions.count_documents({"tx_type": "debit"}), 3)
        self.assertEqual(self.raw.wallet_transactions.count_documents({"tx_type": "credit"}), 3)

    async def test_competing_acceptances_reserve_one_driver(self):
        for name in ("one", "two"):
            self.mission(name, commission=False)
        results = await asyncio.gather(*(deliveries.accept_mission(name, body=None, current_user=account()) for name in ("one", "two")), return_exceptions=True)
        self.assertEqual(sum(isinstance(result, HTTPException) for result in results), 1)
        self.assertEqual(self.raw.delivery_missions.count_documents({"driver_id": "driver", "status": "assigned"}), 1)

    async def test_incident_and_dispatch_restrictions_block_acceptance(self):
        self.mission(commission=False)
        self.raw.delivery_missions.insert_one(dict(mission_id="incident", driver_id="driver", status="incident_reported"))
        with self.assertRaises(HTTPException):
            await deliveries.accept_mission("mission", body=None, current_user=account())
        self.raw.delivery_missions.delete_one({"mission_id": "incident"})
        self.raw.delivery_missions.update_one({"mission_id": "mission"}, {"$set": {"candidate_drivers": ["other"]}})
        with self.assertRaises(HTTPException):
            await deliveries.accept_mission("mission", body=None, current_user=account())

    async def test_acceptance_failure_rolls_back_mission_parcel_and_money(self):
        self.mission()
        self.db.parcels.fail_next["update_one"] = RuntimeError("Synthetic interruption")
        with self.assertRaises(RuntimeError):
            await deliveries.accept_mission("mission", body=None, current_user=account())
        self.assertEqual(self.raw.delivery_missions.find_one()["status"], "pending")
        self.assertIsNone(self.raw.parcels.find_one().get("assigned_driver_id"))
        self.assertEqual(self.raw.wallets.find_one()["balance"], 5000)
        self.assertEqual(self.raw.wallet_transactions.count_documents({}), 0)

    async def test_delivery_failure_can_be_retried_without_partial_status(self):
        self.raw.parcels.insert_one(dict(parcel_id="finish", status="out_for_delivery", delivery_mode="home_to_home", quoted_price=1000, assigned_driver_id="driver"))
        self.raw.delivery_missions.insert_one(dict(mission_id="finish", parcel_id="finish", status="in_progress", driver_id="driver"))
        with patch.object(parcel_service, "distribute_delivery_revenue", AsyncMock(side_effect=RuntimeError("Synthetic interruption"))):
            with self.assertRaises(RuntimeError):
                await parcel_service.transition_status("finish", ParcelStatus.DELIVERED, actor_id="driver", actor_role="driver")
        self.assertEqual(self.raw.parcels.find_one()["status"], "out_for_delivery")
        self.assertEqual(self.raw.delivery_missions.find_one()["status"], "in_progress")
        with patch.object(delivery_completion_service, "process_delivery_completion", AsyncMock()):
            await parcel_service.transition_status("finish", ParcelStatus.DELIVERED, actor_id="driver", actor_role="driver")
            await parcel_service.transition_status("finish", ParcelStatus.DELIVERED, actor_id="driver", actor_role="driver")
        self.assertEqual(self.raw.delivery_missions.find_one()["status"], "completed")
        self.assertEqual(self.raw.wallet_transactions.count_documents({"tx_type": "revenue"}), 1)
        self.assertEqual(self.raw.delivery_completion_jobs.count_documents({}), 1)

    async def test_pin_proof_requires_a_known_type_and_code(self):
        with self.assertRaises(ValidationError):
            ProofOfDelivery(proof_type="unknown")
        self.raw.parcels.insert_one(dict(parcel_id="handout", status="available_at_relay", destination_relay_id="relay", relay_pin="4321", payment_status="paid", delivery_mode="home_to_relay"))
        request = Request({"type": "http", "headers": [], "client": ("127.0.0.1", 1)})
        with self.assertRaises(HTTPException), patch.object(parcels, "transition_status", AsyncMock()) as transition:
            await parcels.handout_parcel.__wrapped__("handout", ProofOfDelivery(proof_type="pin"), request, {**account("relay_agent", "agent"), "relay_point_id": "relay"})
        transition.assert_not_awaited()

    async def test_rating_authorization_and_single_gamification(self):
        self.raw.parcels.insert_one(dict(parcel_id="rated", status="delivered", sender_user_id="sender", recipient_user_id="recipient", assigned_driver_id="driver"))
        with self.assertRaises(HTTPException):
            await parcels.rate_parcel("rated", ParcelRatingRequest(rating=5), account("client", "outsider"))
        await parcels.rate_parcel("rated", ParcelRatingRequest(rating=5), account("client", "sender"))
        with self.assertRaises(HTTPException):
            await parcels.rate_parcel("rated", ParcelRatingRequest(rating=4), account("client", "recipient"))
        self.assertEqual(self.raw.users.find_one()["total_ratings_count"], 1)

    async def test_profile_omitted_preferences_and_explicit_clear(self):
        client = {**account("client", "client"), "bio": "Old", "pin_hash": "synthetic", "notification_prefs": {"push": False, "whatsapp": False, "promotions": False}}
        self.raw.users.insert_one(client)
        response = await auth.update_profile(ProfileUpdate(bio="", notification_prefs={"android_vibration": False}), client)
        self.assertIsNone(response.bio)
        self.assertFalse(response.notification_prefs.push)
        self.assertFalse(response.notification_prefs.whatsapp)
        self.assertFalse(response.notification_prefs.promotions)
        self.assertNotIn("pin_hash", response.model_dump())

    async def test_validated_relay_payment_is_not_downgraded(self):
        self.raw.relay_points.insert_one(dict(relay_id="relay", owner_user_id="agent"))
        self.raw.parcels.insert_one(dict(parcel_id="settled", status="delivered", delivery_mode="relay_to_relay", origin_relay_id="relay", quoted_price=1000, relay_settlement={"denkma_payment_status": "validated"}))
        await relay_points.relay_financial_action("relay", "settled", {"action": "denkma_payment"}, account("relay_agent", "agent"))
        self.assertEqual(self.raw.parcels.find_one()["relay_settlement"]["denkma_payment_status"], "validated")

    async def test_invalid_configuration_does_not_write_anything(self):
        self.mission()
        self.raw.parcels.update_one({}, {"$set": {"delivery_mode": ""}})
        with self.assertRaises(HTTPException):
            await admin.update_operational_settings({"delivery_commissions_enabled": False}, account("admin", "admin"))
        self.assertIsNone(self.raw.app_settings.find_one())
        self.assertTrue(self.raw.parcels.find_one()["delivery_commissions_enabled"])

    async def test_configuration_failure_rolls_back_global_and_parcels(self):
        self.mission()
        self.db.delivery_missions.fail_next["update_one"] = RuntimeError("Synthetic interruption")
        with self.assertRaises(RuntimeError):
            await admin.update_operational_settings({"delivery_commissions_enabled": False}, account("admin", "admin"))
        self.assertIsNone(self.raw.app_settings.find_one())
        self.assertTrue(self.raw.parcels.find_one()["delivery_commissions_enabled"])

    async def test_promotion_quota_and_repeated_usage_are_atomic(self):
        now = datetime.now(timezone.utc)
        self.raw.promotions.insert_one(dict(promo_id="promo", is_active=True, start_date=now-timedelta(days=1), end_date=now+timedelta(days=1), max_uses_per_user=1, max_uses_total=1, uses_count=0))
        await promotion_service.record_promo_use(self.db, "promo", "sender", "one")
        await promotion_service.record_promo_use(self.db, "promo", "sender", "one")
        with self.assertRaises(HTTPException):
            await promotion_service.record_promo_use(self.db, "promo", "sender", "two")
        self.assertEqual(self.raw.promotions.find_one()["uses_count"], 1)
        self.assertEqual(self.raw.promo_uses.count_documents({}), 1)

    async def test_payout_submission_and_settlement_do_not_double_debit(self):
        request = Request({"type": "http", "headers": [], "client": ("127.0.0.1", 1)})
        body = PayoutRequest(amount=500, method="wave", phone=account()["phone"], request_key="request_key_123456")
        with patch.object(wallets, "record_admin_event", AsyncMock()):
            first = await wallets.request_payout.__wrapped__(body, request, account())
            second = await wallets.request_payout.__wrapped__(body, request, account())
        self.assertEqual(first["payout_id"], second["payout_id"])
        self.assertEqual(self.raw.wallets.find_one()["balance"], 4500)
        await payout_service.settle_payout(first["payout_id"], "approved", {})
        self.assertEqual(self.raw.wallets.find_one()["balance"], 4500)
        self.assertEqual(self.raw.wallets.find_one()["pending"], 0)
        with self.assertRaises(HTTPException):
            await payout_service.settle_payout(first["payout_id"], "approved", {})

    async def test_payout_rejection_rolls_back_on_ledger_failure(self):
        self.raw.payout_requests.insert_one(dict(payout_id="pay_one", wallet_id="wallet", owner_id="driver", amount=500, status="pending"))
        self.raw.wallets.update_one({}, {"$set": {"balance": 4500, "pending": 500}})
        self.db.wallet_transactions.fail_next["insert_one"] = RuntimeError("Synthetic interruption")
        with self.assertRaises(RuntimeError):
            await payout_service.settle_payout("pay_one", "rejected", {})
        self.assertEqual(self.raw.payout_requests.find_one()["status"], "pending")
        self.assertEqual(self.raw.wallets.find_one()["balance"], 4500)

    async def test_wallet_summary_includes_every_revenue_and_groups_payout(self):
        now = datetime.now(timezone.utc)
        self.raw.wallet_transactions.insert_many([dict(tx_id=f"tx_{i}", wallet_id="wallet", parcel_id=f"parcel_{i}", amount=100, tx_type="revenue", description="Course", created_at=now) for i in range(61)])
        self.raw.wallet_transactions.insert_many([dict(tx_id=f"payout_{kind}", wallet_id="wallet", amount=500, tx_type=kind, reference="pay_one", created_at=now) for kind in ("pending", "debit")])
        self.raw.payout_requests.insert_one(dict(payout_id="pay_one", wallet_id="wallet", amount=500, status="approved", created_at=now))
        summary = await wallet_activity(self.db, account(), {}, category="revenues", skip=20, limit=20)
        self.assertEqual(summary["earnings"], {"amount": 6100, "courses_count": 61})
        self.assertEqual(summary["total"], 61)
        self.assertEqual(len(summary["items"]), 20)
        history = await wallet_activity(self.db, account(), {})
        self.assertEqual(history["total"], 1)
        self.assertEqual(history["items"][0]["effect"], -500)

    async def test_admin_gps_trace_starts_at_assignment(self):
        now = datetime.now(timezone.utc)
        mission = dict(mission_id="gps", driver_id="driver", assigned_at=now-timedelta(minutes=10), started_at=now-timedelta(minutes=5), gps_trail=[dict(lat=14.7, lng=-17.4, ts=now-timedelta(minutes=8)), dict(lat=14.71, lng=-17.4, ts=now-timedelta(minutes=3))])
        points = await mission_trace.load_trace(mission)
        self.assertEqual([point["phase"] for point in points], ["approach", "delivery"])

    async def test_failed_notification_does_not_fail_committed_acceptance(self):
        self.mission(commission=False)
        with patch.object(deliveries, "notify_sender_driver_assigned", AsyncMock(side_effect=RuntimeError("Synthetic interruption"))):
            result = await deliveries.accept_mission("mission", body=None, current_user=account())
        self.assertEqual(result["mission_id"], "mission")
        self.assertEqual(self.raw.delivery_missions.find_one()["status"], "assigned")

    async def test_delayed_quote_reserves_promotion_atomically_and_only_once(self):
        now = datetime.now(timezone.utc)
        promo = dict(promo_id="promo", title="Express offert", promo_type="express_upgrade", value=0)
        self.raw.promotions.insert_one({**promo, "is_active": True, "start_date": now-timedelta(days=1), "end_date": now+timedelta(days=1), "max_uses_per_user": 1, "max_uses_total": 1, "uses_count": 0})
        self.raw.parcels.insert_one(dict(parcel_id="quote", tracking_code="TEST-QUOTE", sender_user_id="sender", delivery_mode="home_to_home", origin_location={"geopin": {"lat": 14.7, "lng": -17.4}}, delivery_address={"city": "Dakar", "label": "Adresse du destinataire"}, quoted_price=None, updated_at=now))
        quote = QuoteResponse(price=1000, breakdown={"is_express": True}, promo_applied=promo)
        with patch.object(parcel_service, "calculate_price", AsyncMock(return_value=quote)), patch.object(parcel_service, "create_payment_link", AsyncMock(return_value={"success": False})):
            self.db.promo_uses.fail_next["insert_one"] = RuntimeError("Synthetic interruption")
            with self.assertRaises(RuntimeError):
                await parcel_service.refresh_quote_if_ready(self.raw.parcels.find_one())
            self.assertIsNone(self.raw.parcels.find_one()["quoted_price"])
            self.assertEqual(self.raw.promotions.find_one()["uses_count"], 0)
            refreshed, first = await parcel_service.refresh_quote_if_ready(self.raw.parcels.find_one())
            self.assertTrue(first)
            self.assertTrue(refreshed["is_express"])
            self.assertEqual(refreshed["promo_snapshot"], promo)
            await parcel_service.refresh_quote_if_ready(refreshed)
        self.assertEqual(self.raw.promotions.find_one()["uses_count"], 1)
        self.assertEqual(self.raw.promo_uses.count_documents({}), 1)

    async def test_express_offer_removes_actual_surcharge_and_upgrades_service(self):
        self.raw.app_settings.insert_one({"key": "global", "express_enabled": True, "express_multiplier": 1.5})
        promo = dict(promo_id="promo", title="Express offert", promo_type="express_upgrade", value=0)
        with patch.object(pricing_service, "estimate_distance_km", AsyncMock(return_value=5)):
            standard = await pricing_service.calculate_price(ParcelQuote(delivery_mode="relay_to_relay", origin_relay_id="origin", destination_relay_id="destination"))
            offered = await pricing_service.calculate_price(ParcelQuote(delivery_mode="relay_to_relay", origin_relay_id="origin", destination_relay_id="destination", is_express=True), reserved_promo=promo)
            upgraded = await pricing_service.calculate_price(ParcelQuote(delivery_mode="relay_to_relay", origin_relay_id="origin", destination_relay_id="destination"), reserved_promo=promo)
        self.assertEqual(standard.price, offered.price)
        self.assertEqual(standard.price, upgraded.price)
        self.assertTrue(upgraded.breakdown["is_express"])
        self.assertTrue(offered.breakdown["is_express"])
        self.assertEqual(offered.breakdown["express_cost"], 0)

    async def test_promo_check_uses_real_completed_deliveries(self):
        request = {"promo_code": "FIRST", "delivery_mode": "home_to_home", "price": 1000}
        self.raw.parcels.insert_one({"parcel_id": "past", "sender_user_id": "driver", "status": "delivered"})
        with patch.object(promotion_service, "find_best_promo", AsyncMock(return_value=None)) as finder:
            with self.assertRaises(HTTPException):
                await parcels.check_promo(request, account())
            self.assertFalse(finder.call_args.kwargs["is_first_delivery"])

    async def test_pin_lock_accepts_naive_database_dates_and_resets_expired_counter(self):
        request = Request({"type": "http", "headers": [], "client": ("127.0.0.1", 1)})
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        self.raw.users.update_one({}, {"$set": {"pin_hash": "not-a-real-hash", "pin_failed_attempts": 5, "pin_locked_until": now+timedelta(minutes=1)}})
        with patch("core.security.verify_password", return_value=False):
            with self.assertRaises(HTTPException) as locked:
                await auth.login_pin.__wrapped__(auth.PINLoginRequest(phone=account()["phone"], pin="1234"), request)
            self.assertIn("Trop de tentatives", locked.exception.detail)
            self.raw.users.update_one({}, {"$set": {"pin_locked_until": now-timedelta(minutes=1)}})
            with self.assertRaises(HTTPException):
                await auth.login_pin.__wrapped__(auth.PINLoginRequest(phone=account()["phone"], pin="1234"), request)
        self.assertEqual(self.raw.users.find_one()["pin_failed_attempts"], 1)

    async def test_outbox_claim_failure_does_not_fail_delivered_result(self):
        self.db.delivery_completion_jobs.fail_next["find_one_and_update"] = RuntimeError("Synthetic interruption")
        await delivery_completion_service.process_delivery_completion("delivered")

    async def test_relay_stock_is_decremented_once_with_primary_delivery(self):
        self.raw.parcels.insert_one({"parcel_id": "stock", "status": "available_at_relay", "delivery_mode": "relay_to_relay", "destination_relay_id": "relay", "quoted_price": 1000})
        self.raw.relay_points.insert_one({"relay_id": "relay", "current_load": 1})
        with patch.object(parcel_service, "distribute_delivery_revenue", AsyncMock()), patch.object(delivery_completion_service, "process_delivery_completion", AsyncMock()):
            await parcel_service.transition_status("stock", ParcelStatus.DELIVERED, "agent", "relay_agent")
            await parcel_service.transition_status("stock", ParcelStatus.DELIVERED, "agent", "relay_agent")
        self.assertEqual(self.raw.relay_points.find_one()["current_load"], 0)


class ParcelPrivacyTests(unittest.TestCase):
    def test_codes_are_per_role_and_never_leak_through_metadata(self):
        parcel = dict(sender_user_id="sender", recipient_user_id="recipient", delivery_mode="home_to_home", pickup_code="123456", delivery_code="654321", relay_pin="4321", return_code="000000", sender_confirm_token="secret-sender", recipient_confirm_token="secret-recipient", metadata={"delivery_code": "654321"})
        self.assertNotIn("delivery_code", serialize_parcel(parcel, account()))
        self.assertEqual(serialize_parcel(parcel, account())["metadata"], {})
        self.assertIn("pickup_code", serialize_parcel(parcel, account("client", "sender")))
        self.assertNotIn("delivery_code", serialize_parcel(parcel, account("client", "sender")))
        self.assertIn("delivery_code", serialize_parcel(parcel, account("client", "recipient")))
        self.assertIn("delivery_code", serialize_parcel(parcel, account("admin", "admin")))
        self.assertNotIn("sender_confirm_token", serialize_parcel(parcel, account()))
        self.assertNotIn("recipient_confirm_token", serialize_parcel(parcel, account("client", "sender")))

    def test_refund_of_previous_assignment_does_not_hide_current_charge(self):
        mission = dict(mission_id="mission", platform_commission_wallet_reference="commission:mission:new")
        self.assertFalse(wallet_service.mission_commission_refunded(mission, {"commission_refund:mission:old"}))
        self.assertTrue(wallet_service.mission_commission_refunded(mission, {"commission_refund:mission:new"}))


if __name__ == "__main__":
    unittest.main()
