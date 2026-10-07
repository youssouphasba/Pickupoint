import copy
import unittest
from contextlib import ExitStack
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch

from core.mission_privacy import serialize_mission
from routers import deliveries
from services import notification_service, wallet_activity_service
from services.delivery_rounding import build_financial_rounding
from services.wallet_service import default_commission_rules
from tests.fake_database import Database


DRIVER = {
    "user_id": "driver",
    "role": "driver",
    "is_available": True,
    "profile_picture_url": "https://example.test/avatar",
    "profile_picture_status": "approved",
}


class DriverMissionFinancialPrivacyTests(unittest.TestCase):
    def setUp(self):
        self.split = build_financial_rounding(2337, "home_to_relay", default_commission_rules())
        self.mission = {
            "mission_id": "mission", "parcel_id": "parcel", "earn_amount": 1650,
            "quoted_price": 2300, "paid_price": 2300,
            "financial_rounding": self.split,
            "wallet_balance_required_xof": 650, "total_commission_xof": 650,
            "recipient_collection_plan": {
                "collector": "relay", "status": "collection_required", "revision": 2,
                "amount_due_xof": 1800, "amount_received_xof": 500,
                "receipts": [{"amount_xof": 500}],
            },
            "delivery_blocked_by_payment": False,
        }

    def test_driver_only_receives_own_gain_rounding_and_required_balance(self):
        result = serialize_mission(self.mission, DRIVER)
        self.assertNotIn("quoted_price", result)
        self.assertNotIn("paid_price", result)
        self.assertEqual(result["earn_amount"], 1650)
        self.assertEqual(result["wallet_balance_required_xof"], 650)
        self.assertEqual(result["total_commission_xof"], 650)
        self.assertEqual(result["financial_rounding"], {"rounding": {
            "version": self.split["rounding"]["version"], "driver_bonus_xof": 14.1,
        }})
        self.assertEqual(result["recipient_collection_plan"], {
            "collector": "relay", "status": "collection_required", "revision": 2,
        })
        self.assertFalse(result["delivery_blocked_by_payment"])

    def test_serialization_never_changes_stored_prices_or_payment_plan(self):
        before = copy.deepcopy(self.mission)
        result = serialize_mission(self.mission, DRIVER)
        result["financial_rounding"]["rounding"]["driver_bonus_xof"] = 0
        result["recipient_collection_plan"]["status"] = "paid"
        self.assertEqual(self.mission, before)

    def test_admin_and_superadmin_keep_the_full_financial_view(self):
        for role in ("admin", "superadmin"):
            with self.subTest(role=role):
                self.assertEqual(serialize_mission(self.mission, {"role": role}), self.mission)

    def test_financial_contract_keeps_only_driver_offer_without_client_price(self):
        result = serialize_mission({**self.mission,
            "financial_contract": {"breakdown": self.split},
            "quote_breakdown": {"price_xof": 2300},
            "commission_rules_snapshot": default_commission_rules(),
        }, DRIVER)
        for key in ("financial_contract", "quote_breakdown", "commission_rules_snapshot"):
            self.assertNotIn(key, result)
        self.assertEqual(result["financial_rounding"]["rounding"]["driver_bonus_xof"], 14.1)

    def test_legacy_mission_keeps_its_gain_without_an_invented_rounding_offer(self):
        result = serialize_mission({"earn_amount": 1635.9, "quoted_price": 2337}, DRIVER)
        self.assertEqual(result, {"earn_amount": 1635.9})

    def test_payment_status_and_handover_block_remain_authoritative(self):
        result = serialize_mission({**self.mission,
            "payment_status": "pending", "payment_override": False,
            "delivery_blocked_by_payment": True,
        }, DRIVER)
        self.assertEqual(result["payment_status"], "pending")
        self.assertFalse(result["payment_override"])
        self.assertTrue(result["delivery_blocked_by_payment"])


class DriverMissionFinancialRouteTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.database = Database()
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(deliveries, "db", self.database))
        self.stack.enter_context(patch.object(notification_service, "db", self.database))
        self.stack.enter_context(patch.object(deliveries, "get_assigned_mission_auto_release_minutes", AsyncMock(return_value=30)))
        self.stack.enter_context(patch.object(deliveries, "_hydrate_mission_area_labels", AsyncMock()))
        self.stack.enter_context(patch.object(deliveries, "get_directions_eta", AsyncMock(return_value=None)))
        self.stack.enter_context(patch.object(deliveries, "load_trace", AsyncMock(return_value=[])))
        self.split = build_financial_rounding(2337, "home_to_relay", default_commission_rules())
        now = datetime.now(timezone.utc)
        await self.database.parcels.insert_one({
            "parcel_id": "parcel", "status": "created", "delivery_mode": "home_to_relay",
            "quoted_price": 2300, "financial_rounding": self.split,
            "payment_status": "pending", "who_pays": "recipient",
            "recipient_collection_plan": {
                "collector": "relay", "status": "collection_required",
                "amount_due_xof": 1800, "amount_received_xof": 500,
            },
        })
        await self.database.delivery_missions.insert_one({
            "mission_id": "mission", "parcel_id": "parcel", "status": "pending",
            "driver_id": "driver", "created_at": now, "delivery_type": "relay",
            "pickup_geopin": {"lat": 14.7, "lng": -17.4},
            "delivery_geopin": {"lat": 14.71, "lng": -17.4},
            "is_broadcast": True, "candidate_drivers": ["driver"],
            "quoted_price": 2300, "earn_amount": 1650, "financial_rounding": self.split,
        })

    def assert_driver_finances(self, mission):
        self.assertNotIn("quoted_price", mission)
        self.assertNotIn("paid_price", mission)
        self.assertNotIn("financial_contract", mission)
        self.assertNotIn("price_xof", mission["financial_rounding"])
        self.assertEqual(mission["earn_amount"], 1650)
        self.assertEqual(mission["wallet_balance_required_xof"], 650)
        self.assertEqual(mission["financial_rounding"]["rounding"]["driver_bonus_xof"], 14.1)

    async def test_available_and_preview_do_not_send_client_price(self):
        listing = await deliveries.available_missions(lat=14.7, lng=-17.4, radius_km=5, current_user=DRIVER)
        self.assertEqual(len(listing["missions"]), 1)
        self.assert_driver_finances(listing["missions"][0])
        preview = await deliveries.mission_preview("mission", lat=14.7, lng=-17.4, current_user=DRIVER)
        self.assert_driver_finances(preview["mission"])

    async def test_accepted_and_completed_missions_do_not_send_client_price(self):
        for status in ("assigned", "in_progress", "completed", "failed"):
            with self.subTest(status=status):
                await self.database.delivery_missions.update_one({"mission_id": "mission"}, {"$set": {"status": status}})
                listing = await deliveries.my_missions(limit=10, skip=0, finished_only=False, current_user=DRIVER)
                self.assert_driver_finances(listing["missions"][0])
                detail = await deliveries.get_mission("mission", current_user=DRIVER)
                self.assert_driver_finances(detail)
                self.assertNotIn("amount_due_xof", detail["recipient_collection_plan"])
                self.assertNotIn("amount_received_xof", detail["recipient_collection_plan"])
                self.assertFalse(detail["delivery_blocked_by_payment"])
        saved = await self.database.delivery_missions.find_one({"mission_id": "mission"})
        self.assertEqual(saved["quoted_price"], 2300)
        self.assertEqual(saved["financial_rounding"], self.split)

    async def test_admin_detail_still_has_client_price_and_collection_amounts(self):
        detail = await deliveries.get_mission("mission", current_user={"user_id": "admin", "role": "admin"})
        self.assertEqual(detail["quoted_price"], 2300)
        self.assertEqual(detail["financial_rounding"], self.split)
        self.assertEqual(detail["recipient_collection_plan"]["amount_due_xof"], 1800)

    async def test_revenue_history_only_sends_driver_offer(self):
        await self.database.delivery_missions.update_one({"mission_id": "mission"}, {"$set": {"status": "completed"}})
        await self.database.wallet_transactions.insert_one({
            "wallet_id": "wallet", "tx_id": "revenue", "tx_type": "revenue", "amount": 1650,
            "parcel_id": "parcel", "reference": "driver_revenue:parcel", "created_at": datetime.now(timezone.utc),
        })
        with patch.object(wallet_activity_service, "get_or_create_wallet", AsyncMock(return_value={"wallet_id": "wallet"})):
            history = await wallet_activity_service.wallet_activity(self.database, DRIVER, {}, category="revenues")
        self.assertEqual(history["earnings"]["amount"], 1650)
        item = history["items"][0]
        self.assertEqual(item["amount"], 1650)
        self.assertNotIn("price_xof", item["financial_rounding"])
        self.assertEqual(item["financial_rounding"]["rounding"]["driver_bonus_xof"], 14.1)

    async def collection_notifications(self, *, paid=False):
        parcel = await self.database.parcels.find_one({"parcel_id": "parcel"}, {"_id": 0})
        parcel.update({"sender_user_id": "sender", "recipient_user_id": "recipient",
                       "assigned_driver_id": "driver", "destination_relay_id": "relay",
                       "tracking_code": "PKP-EXEMPLE", "payment_status": "paid" if paid else "pending"})
        with patch.object(notification_service, "_store_and_send", AsyncMock()) as send, \
             patch.object(notification_service, "_notify_relay_users", AsyncMock()) as relay_send:
            await notification_service.notify_recipient_collection_plan(parcel)
        return {call.kwargs["user_id"]: call.kwargs for call in send.await_args_list}, relay_send

    async def test_collection_notification_hides_amounts_only_for_driver(self):
        notifications, relay_send = await self.collection_notifications()
        driver = notifications["driver"]
        self.assertNotIn("FCFA", driver["body"])
        self.assertNotIn("1800", driver["body"])
        self.assertEqual(driver["target_view"], "driver")
        self.assertIn("Règlement en attente", driver["body"])
        for user_id in ("sender", "recipient"):
            self.assertIn("1800 FCFA", notifications[user_id]["body"])
            self.assertEqual(notifications[user_id]["target_view"], "client")
        self.assertIn("1800 FCFA", relay_send.await_args.kwargs["body"])

    async def test_driver_notification_never_reveals_amount_even_if_mission_is_missing(self):
        await self.database.delivery_missions.delete_one({"mission_id": "mission"})
        notifications, _ = await self.collection_notifications()
        self.assertNotIn("FCFA", notifications["driver"]["body"])

    async def test_paid_collection_notification_never_asks_for_another_payment(self):
        notifications, relay_send = await self.collection_notifications(paid=True)
        for notification in (*notifications.values(), relay_send.await_args.kwargs):
            self.assertIn("aucun nouvel encaissement", notification["body"])
            self.assertNotIn("Reste à régler", notification["body"])
