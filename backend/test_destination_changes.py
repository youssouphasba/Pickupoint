import unittest
from contextlib import ExitStack
from datetime import datetime, timezone, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from fastapi import HTTPException
from core.parcel_privacy import serialize_parcel
from models.common import ParcelStatus
from routers import admin, parcels, confirm, relay_points, tracking, deliveries
from config import settings
from models.delivery import ProofOfDelivery
from services import delivery_destination_service as destinations
from services import parcel_service, pricing_service, notification_service, wallet_service
from services.location_quality import client_live_tracking_allowed
from services.relay_settlement_service import settlement_actions
from tests.fake_database import Database


class DestinationChangesTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.database = Database()
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        for module in (destinations, parcel_service, parcels, admin, wallet_service, relay_points, deliveries):
            self.stack.enter_context(patch.object(module, "db", self.database))
        self.stack.enter_context(patch.object(wallet_service, "get_client", return_value=self.database))
        self.stack.enter_context(patch.object(parcel_service, "_relay_is_open", return_value=True))
        self.notify_destination_original = notification_service.notify_destination_changed
        self.notify_return_original = notification_service.notify_driver_return_requested
        self.notify = self.stack.enter_context(patch.object(notification_service, "notify_destination_changed", AsyncMock()))
        self.stack.enter_context(patch.object(notification_service, "notify_recipient_collection_plan", AsyncMock()))
        self.stack.enter_context(patch.object(notification_service, "notify_parcel_status_change", AsyncMock()))
        self.stack.enter_context(patch.object(notification_service, "notify_driver_mission_completed", AsyncMock()))
        self.stack.enter_context(patch.object(notification_service, "notify_driver_return_requested", AsyncMock()))
        self.stack.enter_context(patch("services.loyalty_service._check_referral_bonus", AsyncMock()))
        self.stack.enter_context(patch("services.ranking_service.refresh_driver_stats_for_period", AsyncMock()))
        self.stack.enter_context(patch.object(admin, "notify_relay_settlement_update", AsyncMock()))
        self.stack.enter_context(patch.object(parcel_service, "_create_delivery_mission", AsyncMock()))
        self.quote = self.stack.enter_context(patch.object(pricing_service, "calculate_price", AsyncMock(return_value=SimpleNamespace(price=900, breakdown={"price": 900}, promo_applied=None))))
        self.now = datetime.now(timezone.utc).replace(microsecond=0)
        self.location = {"label": "Adresse initiale", "geopin": {"lat": 14.72, "lng": -17.46}}
        self.relay = {"relay_id": "relay", "is_active": True, "is_verified": True, "current_load": 0, "max_capacity": 10,
                      "name": "Relais choisi", "address": {"label": "Rue du relais", "geopin": {"lat": 14.73, "lng": -17.45}}}
        await self.database.relay_points.insert_one(dict(self.relay))

    async def seed(self, *, status="created", mission_status="pending", paid=False, who_pays="sender", assigned=False, mode="home_to_home"):
        parcel = {"parcel_id": "parcel", "tracking_code": "SYNTHETIC", "status": status, "delivery_mode": mode,
                  "sender_user_id": "sender", "recipient_user_id": "recipient", "recipient_phone": "+221770000001",
                  "origin_location": self.location, "delivery_address": self.location, "delivery_location": self.location,
                  "pickup_confirmed": True, "delivery_confirmed": True, "weight_kg": 0.5,
                  "quoted_price": 2000, "payment_status": "paid" if paid else "pending", "who_pays": who_pays,
                  "assigned_driver_id": "driver" if assigned else None, "commission_rules_snapshot": wallet_service.default_commission_rules(),
                  "pickup_code": "123456", "delivery_code": "654321", "relay_pin": None, "updated_at": self.now,
                  "sender_confirm_token": "sender-secret", "recipient_confirm_token": "recipient-secret"}
        if paid:
            parcel["paid_price"] = 2000
        if mode.startswith("relay"):
            parcel["origin_relay_id"] = "origin"
        mission = {"mission_id": "mission", "parcel_id": "parcel", "status": mission_status, "driver_id": "driver" if assigned else None,
                   "delivery_mode": mode, "delivery_type": "gps", "pickup_geopin": self.location["geopin"],
                   "delivery_geopin": self.location["geopin"], "quoted_price": 2000, "earn_amount": 1700,
                   "encoded_polyline": "old-route", "gps_trail": [{"lat": 14.72, "lng": -17.46}], "updated_at": self.now}
        await self.database.parcels.insert_one(dict(parcel))
        await self.database.delivery_missions.insert_one(dict(mission))
        return parcel

    async def change(self, parcel):
        preview = await destinations.preview_destination_change(parcel, new_mode="relay", relay_id="relay")
        return await destinations.change_destination(parcel, preview, actor_id="recipient", actor_role="client", expected_token=preview["preview_token"])

    async def redirect(self, parcel):
        return await destinations.redirect_destination(parcel, "relay", actor_id="driver", actor_role="driver")

    async def test_unpaid_pending_change_requotes_and_updates_mission(self):
        updated = await self.change(await self.seed())
        mission = await self.database.delivery_missions.find_one({"mission_id": "mission"})
        self.assertEqual(updated["quoted_price"], 900)
        self.assertEqual(updated["delivery_mode"], "home_to_relay")
        self.assertTrue(updated["delivery_confirmed"])
        self.assertEqual(updated["delivery_location"]["geopin"], self.relay["address"]["geopin"])
        self.assertEqual(mission["delivery_type"], "relay")
        self.assertEqual(mission["delivery_mode"], "home_to_relay")
        self.assertEqual(mission["delivery_relay_id"], "relay")
        self.assertEqual(mission["earn_amount"], 630)
        self.assertNotIn("encoded_polyline", mission)
        self.assertEqual(len(mission["gps_trail"]), 1)
        self.assertIsNone(updated["expires_at"])

    async def test_paid_change_never_reprices_or_requests_second_payment(self):
        updated = await self.change(await self.seed(paid=True))
        self.quote.assert_not_awaited()
        self.assertEqual(updated["paid_price"], 2000)
        self.assertEqual(wallet_service.compute_delivery_commission_breakdown(updated)["driver_revenue_xof"], 1700)
        self.assertEqual(updated["redirect_relay_commission_xof"], 300)

    async def test_assigned_change_preserves_driver_contract_and_hold(self):
        parcel = await self.seed(mission_status="assigned", assigned=True)
        await self.database.delivery_missions.update_one({"mission_id": "mission"}, {"$set": {"platform_commission_wallet_reference": "original-hold"}})
        updated = await self.change(parcel)
        mission = await self.database.delivery_missions.find_one({"mission_id": "mission"})
        self.assertEqual(mission["earn_amount"], 1700)
        self.assertEqual(mission["platform_commission_wallet_reference"], "original-hold")
        self.assertEqual(wallet_service.compute_delivery_commission_breakdown(updated, mission)["total_commission_xof"], 300)

    async def test_changed_quote_rejects_old_preview(self):
        parcel = await self.seed()
        previous = await destinations.preview_destination_change(parcel, new_mode="relay", relay_id="relay")
        self.quote.return_value.price = 1000
        latest = await destinations.preview_destination_change(parcel, new_mode="relay", relay_id="relay")
        with self.assertRaises(HTTPException):
            await destinations.change_destination(parcel, latest, actor_id="recipient", actor_role="client", expected_token=previous["preview_token"])
        self.assertEqual((await self.database.parcels.find_one({"parcel_id": "parcel"}))["delivery_mode"], "home_to_home")

    async def test_full_unverified_and_inactive_relays_are_rejected(self):
        parcel = await self.seed()
        for fields in ({"is_verified": False}, {"is_active": False}, {"current_load": 10}):
            await self.database.relay_points.update_one({"relay_id": "relay"}, {"$set": {**self.relay, **fields}})
            with self.assertRaises(HTTPException):
                await self.change(parcel)
        self.assertEqual((await self.database.parcels.find_one({"parcel_id": "parcel"}))["delivery_mode"], "home_to_home")

    async def test_failure_during_mission_sync_rolls_back_destination_and_codes(self):
        parcel = await self.seed()
        self.database.delivery_missions.fail_next["update_one"] = RuntimeError("interruption")
        with self.assertRaises(RuntimeError):
            await self.change(parcel)
        saved = await self.database.parcels.find_one({"parcel_id": "parcel"})
        self.assertEqual(saved["delivery_code"], "654321")
        self.assertEqual(saved["delivery_mode"], "home_to_home")
        self.assertEqual(await self.database.destination_change_jobs.count_documents({}), 0)

    async def test_race_with_pickup_rejects_change(self):
        parcel = await self.seed()
        preview = await destinations.preview_destination_change(parcel, new_mode="relay", relay_id="relay")
        await self.database.delivery_missions.update_one({"mission_id": "mission"}, {"$set": {"status": "in_progress"}})
        with self.assertRaises(HTTPException):
            await destinations.change_destination(parcel, preview, actor_id="recipient", actor_role="client")

    async def test_redirect_sets_pin_effective_target_without_live_client_tracking(self):
        updated = await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, paid=True))
        mission = await self.database.delivery_missions.find_one({"mission_id": "mission"})
        self.assertEqual(updated["status"], "redirected_to_relay")
        self.assertTrue(updated["relay_pin"].isdigit())
        self.assertEqual(len(updated["relay_pin"]), 6)
        self.assertEqual({key: mission["delivery_geopin"][key] for key in ("lat", "lng")}, self.relay["address"]["geopin"])
        self.assertFalse(client_live_tracking_allowed(updated, mission, is_recipient=True))
        self.assertNotIn("encoded_polyline", mission)
        self.assertIsNone(updated["expires_at"])
        self.assertEqual(wallet_service.compute_delivery_commission_breakdown(updated, mission)["driver_revenue_xof"], 1700)

    async def test_repeated_redirect_is_idempotent(self):
        updated = await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True))
        repeated = await self.redirect(updated)
        self.assertEqual(repeated["relay_pin"], updated["relay_pin"])
        self.assertEqual(await self.database.destination_change_jobs.count_documents({}), 1)
        self.assertEqual(await self.database.parcel_events.count_documents({}), 1)

    async def test_recipient_gets_only_relay_code_after_redirect(self):
        updated = await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True))
        recipient = serialize_parcel(updated, {"user_id": "recipient", "role": "client"})
        self.assertIn("relay_pin", recipient)
        self.assertNotIn("delivery_code", recipient)
        self.assertNotIn("pickup_code", recipient)
        self.assertNotIn("sender_confirm_token", recipient)
        self.assertNotIn("relay_pin", serialize_parcel(updated, {"user_id": "driver", "role": "driver"}))

    async def test_relay_commission_is_visible_to_admin_after_redirect(self):
        updated = await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True))
        actions = settlement_actions({**updated, "status": "delivered"})
        self.assertEqual(len(actions), 1)
        self.assertEqual(actions[0]["amount_xof"], 300)
        self.assertTrue(actions[0]["funding_review_required"])
        self.assertEqual(actions[0]["action"], "destination_relay_payment")

    async def test_recipient_payer_requires_admin_collection_decision(self):
        updated = await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, who_pays="recipient"))
        self.assertEqual(updated["recipient_collection_plan"]["status"], "admin_review")
        self.assertEqual(updated["recipient_collection_plan"]["amount_due_xof"], 2000)
        self.assertIsNone(updated["recipient_collection_plan"]["collector"])

    async def test_paid_recipient_has_nothing_to_pay_again(self):
        updated = await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, who_pays="recipient", paid=True))
        self.assertEqual(updated["recipient_collection_plan"]["amount_due_xof"], 0)
        self.assertEqual(updated["recipient_collection_plan"]["status"], "paid")

    async def test_admin_partial_payment_and_paid_driver_are_preserved(self):
        await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, who_pays="recipient", mode="relay_to_home"))
        parcel = await self.database.parcels.find_one({"parcel_id": "parcel"})
        request = admin.RecipientCollectionRequest(collector="relay", amount_received_xof=500, driver_already_paid=True,
                                                  expected_updated_at=parcel["updated_at"], note="Référence vérifiée")
        await admin.manage_recipient_collection("parcel", request, {"user_id": "admin", "role": "admin"})
        saved = await self.database.parcels.find_one({"parcel_id": "parcel"})
        self.assertEqual(saved["recipient_collection_plan"]["amount_due_xof"], 1500)
        self.assertEqual(saved["relay_settlement"]["driver_payment_status"], "validated")
        actions = settlement_actions(saved)
        self.assertEqual(next(item for item in actions if item["action"] == "driver_payment")["status"], "validated")
        with self.assertRaises(HTTPException):
            await admin.manage_recipient_collection("parcel", request, {"user_id": "admin", "role": "admin"})
        self.assertEqual((await self.database.parcels.find_one({"parcel_id": "parcel"}))["recipient_collection_plan"]["amount_received_xof"], 500)

    async def test_admin_cannot_overcollect_or_collect_paid_parcel(self):
        await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, who_pays="recipient", paid=True))
        saved = await self.database.parcels.find_one({"parcel_id": "parcel"})
        request = admin.RecipientCollectionRequest(collector="relay", amount_received_xof=1, expected_updated_at=saved["updated_at"], note="Référence vérifiée")
        with self.assertRaises(HTTPException):
            await admin.manage_recipient_collection("parcel", request, {"user_id": "admin", "role": "admin"})

    async def receive(self):
        with patch.object(destinations, "process_destination_jobs", AsyncMock()):
            return await parcel_service.transition_status("parcel", ParcelStatus.AVAILABLE_AT_RELAY, "agent", "relay_agent")

    async def test_relay_receipt_starts_retention_and_completes_mission_once(self):
        await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, paid=True))
        before = datetime.now(timezone.utc)
        updated = await self.receive()
        expires = updated["expires_at"].replace(tzinfo=timezone.utc)
        self.assertGreaterEqual(expires, before + timedelta(days=settings.RELAY_PICKUP_RETENTION_DAYS) - timedelta(milliseconds=1))
        self.assertEqual(updated["current_relay_id"], "relay")
        self.assertEqual((await self.database.relay_points.find_one({"relay_id": "relay"}))["current_load"], 1)
        self.assertEqual((await self.database.delivery_missions.find_one({"mission_id": "mission"}))["status"], "completed")
        with self.assertRaises(HTTPException):
            await self.receive()
        self.assertEqual((await self.database.relay_points.find_one({"relay_id": "relay"}))["current_load"], 1)

    async def test_relay_filling_between_redirect_and_receipt_is_rejected(self):
        await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True))
        await self.database.relay_points.update_one({"relay_id": "relay"}, {"$set": {"current_load": 10}})
        with self.assertRaises(HTTPException):
            await self.receive()
        self.assertEqual((await self.database.parcels.find_one({"parcel_id": "parcel"}))["status"], "redirected_to_relay")
        self.assertEqual((await self.database.delivery_missions.find_one({"mission_id": "mission"}))["status"], "in_progress")

    async def test_receipt_failure_rolls_back_custody_capacity_mission_and_event(self):
        await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True))
        self.database.delivery_missions.fail_next["update_one"] = RuntimeError("interruption réception")
        with self.assertRaises(RuntimeError):
            await self.receive()
        self.assertEqual((await self.database.relay_points.find_one({"relay_id": "relay"}))["current_load"], 0)
        self.assertEqual((await self.database.parcels.find_one({"parcel_id": "parcel"}))["status"], "redirected_to_relay")
        self.assertEqual(await self.database.parcel_events.count_documents({"to_status": "available_at_relay"}), 0)

    async def test_return_from_redirect_updates_route_without_payment_reset(self):
        parcel = await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, paid=True))
        mission = await self.database.delivery_missions.find_one({"mission_id": "mission"})
        updated = await destinations.request_return(parcel, mission, actor_id="driver", actor_role="driver", reason="Relais indisponible")
        returning = await self.database.delivery_missions.find_one({"mission_id": "mission"})
        self.assertEqual(returning["delivery_geopin"], mission["pickup_geopin"])
        self.assertTrue(returning["return_requested"])
        self.assertEqual(updated["financial_contract"], parcel["financial_contract"])
        self.assertEqual(updated["payment_status"], "paid")
        returned = await destinations.confirm_return(updated, returning, actor_id="driver", actor_role="driver", notes="Code vérifié")
        self.assertEqual(returned["status"], "returned")
        self.assertIsNone(returned["current_relay_id"])
        self.assertEqual((await self.database.delivery_missions.find_one({"mission_id": "mission"}))["status"], "failed")

    async def test_return_failure_is_atomic(self):
        parcel = await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True))
        mission = await self.database.delivery_missions.find_one({"mission_id": "mission"})
        self.database.delivery_missions.fail_next["update_one"] = RuntimeError("interruption retour")
        with self.assertRaises(RuntimeError):
            await destinations.request_return(parcel, mission, actor_id="driver", actor_role="driver", reason="Retour requis")
        saved = await self.database.parcels.find_one({"parcel_id": "parcel"})
        self.assertEqual(saved["status"], "redirected_to_relay")
        self.assertNotIn("return_code", saved)

    async def test_frozen_contract_survives_later_gps_confirmation(self):
        parcel = await self.change(await self.seed(paid=True))
        for refresh in (parcel_service.refresh_quote_if_ready, confirm._refresh_quote_if_ready):
            updated, payment_created = await refresh(parcel)
            self.assertEqual(updated["financial_contract"]["price_xof"], 2000)
            self.assertFalse(payment_created)
        self.quote.assert_not_awaited()

    async def test_new_home_address_replaces_old_snapshot_and_relay_fee(self):
        parcel = await self.change(await self.seed(paid=True))
        new_address = {"label": "Nouveau domicile", "city": "Thiès", "geopin": {"lat": 14.79, "lng": -16.92}}
        preview = await destinations.preview_destination_change(parcel, new_mode="home", address=new_address)
        updated = await destinations.change_destination(parcel, preview, actor_id="recipient", actor_role="client")
        self.assertEqual(updated["redirect_relay_commission_xof"], 0)
        mission = await self.database.delivery_missions.find_one({"mission_id": "mission"})
        self.assertEqual({key: mission["delivery_geopin"][key] for key in ("lat", "lng")}, new_address["geopin"])
        later_address = {**new_address, "label": "Adresse confirmée plus tard", "geopin": {"lat": 14.80, "lng": -16.91}}
        serialized = serialize_parcel({**updated, "delivery_address": later_address, "delivery_location": later_address}, {"user_id": "recipient", "role": "client"})
        self.assertEqual(serialized["delivery_destination"]["address"], later_address)

    async def test_public_tracking_uses_effective_relay_area_without_codes(self):
        updated = await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True))
        updated["delivery_destination"]["address"]["city"] = "Thiès"
        payload = tracking._build_public_tracking_payload(updated, [])
        self.assertEqual(payload["delivery_mode"], "home_to_relay")
        self.assertEqual(payload["delivery_area_label"], "Thiès")
        self.assertNotIn("relay_pin", payload)
        self.assertNotIn("financial_contract", payload)

    async def record_collection(self, collector, amount):
        parcel = await self.database.parcels.find_one({"parcel_id": "parcel"})
        request = admin.RecipientCollectionRequest(collector=collector, amount_received_xof=amount, expected_updated_at=parcel["updated_at"], note="Paiement vérifié")
        await admin.manage_recipient_collection("parcel", request, {"user_id": "admin", "role": "admin"})
        return await self.database.parcels.find_one({"parcel_id": "parcel"}, {"_id": 0})

    async def test_collection_history_keeps_money_at_original_collector(self):
        await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, who_pays="recipient", mode="relay_to_home"))
        await self.record_collection("relay", 500)
        parcel = await self.record_collection("driver", 1500)
        self.assertEqual(parcel["recipient_collection_plan"]["amount_due_xof"], 0)
        actions = settlement_actions(parcel)
        self.assertFalse(any(item["action"] == "driver_payment" for item in actions))
        payment = next(item for item in actions if item["action"] == "recipient_collection_payment")
        self.assertEqual(payment["amount_xof"], 500)
        self.assertEqual(payment["relay_id"], "relay")
        self.assertNotIn("receipts", serialize_parcel(parcel, {"user_id": "recipient", "role": "client"})["recipient_collection_plan"])

    async def test_partial_remittance_tracks_only_new_cash_without_double_validation(self):
        await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, who_pays="recipient"))
        await self.record_collection("relay", 500)
        actor = {"user_id": "agent", "role": "relay_agent", "relay_point_id": "relay"}
        await relay_points.relay_financial_action("relay", "parcel", {"action": "recipient_collection_payment"}, actor)
        saved = await self.database.parcels.find_one({"parcel_id": "parcel"})
        action = next(item for item in settlement_actions(saved) if item["action"] == "recipient_collection_payment")
        body = {"action": action["action"], "relay_id": "relay", "status": "validated", "expected_status": "declared", "expected_amount_xof": 500,
                "expected_updated_at": saved["updated_at"].isoformat(), "note": "Reversement vérifié"}
        await admin.update_relay_settlement("parcel", body, {"user_id": "admin", "role": "admin"})
        await admin.update_relay_settlement("parcel", body, {"user_id": "admin", "role": "admin"})
        parcel = await self.record_collection("relay", 100)
        action = next(item for item in settlement_actions(parcel) if item["action"] == "recipient_collection_payment")
        self.assertEqual(action["amount_xof"], 100)
        self.assertEqual(action["validated_amount_xof"], 500)
        self.assertEqual(action["status"], "pending")
        self.assertEqual(parcel["recipient_collection_plan"]["amount_due_xof"], 1400)
        self.assertNotIn("recipient_collection_remittances", serialize_parcel(parcel, {"user_id": "recipient", "role": "client"}))
        self.assertIn("recipient_collection_remittances", serialize_parcel(parcel, actor))

    async def test_handout_requires_recipient_payment_and_pin(self):
        await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, who_pays="recipient"))
        parcel = await self.receive()
        actor = {"user_id": "agent", "role": "relay_agent", "relay_point_id": "relay"}
        with self.assertRaises(HTTPException):
            await parcels.handout_parcel.__wrapped__("parcel", ProofOfDelivery(proof_type="pin", pin_code=parcel["relay_pin"]), None, actor)
        await self.record_collection("relay", 2000)
        with self.assertRaises(HTTPException):
            await parcels.handout_parcel.__wrapped__("parcel", ProofOfDelivery(proof_type="pin"), None, actor)
        with patch.object(parcel_service, "distribute_delivery_revenue", AsyncMock()) as distribution, patch("services.delivery_completion_service.process_delivery_completion", AsyncMock()):
            completed = await parcels.handout_parcel.__wrapped__("parcel", ProofOfDelivery(proof_type="pin", pin_code=parcel["relay_pin"]), None, actor)
            self.assertEqual(completed["status"], "delivered")
            self.assertIsNone(completed["current_relay_id"])
            self.assertIsNone(completed["expires_at"])
            distribution.assert_awaited_once()
            with self.assertRaises(HTTPException):
                await parcels.handout_parcel.__wrapped__("parcel", ProofOfDelivery(proof_type="pin", pin_code=parcel["relay_pin"]), None, actor)
        self.assertEqual((await self.database.relay_points.find_one({"relay_id": "relay"}))["current_load"], 0)

    async def test_partial_payment_locks_price_during_another_destination_change(self):
        await self.change(await self.seed(who_pays="recipient"))
        parcel = await self.record_collection("relay", 500)
        self.quote.reset_mock()
        new_address = {"label": "Domicile confirmé", "geopin": {"lat": 14.79, "lng": -16.92}}
        preview = await destinations.preview_destination_change(parcel, new_mode="home", address=new_address)
        self.assertTrue(preview["payment_preserved"])
        self.assertEqual(preview["price_xof"], 900)
        self.quote.assert_not_awaited()

    async def test_admin_return_waits_for_physical_handover(self):
        parcel = await self.seed(status="incident_reported", mission_status="incident_reported", assigned=True, paid=True)
        await admin.admin_resolve_incident("parcel", admin.IncidentResolutionRequest(action="return", notes="Retour demandé"), {"user_id": "admin", "role": "admin"})
        saved = await self.database.parcels.find_one({"parcel_id": "parcel"})
        mission = await self.database.delivery_missions.find_one({"mission_id": "mission"})
        self.assertEqual(saved["status"], "incident_reported")
        self.assertEqual(saved["payment_status"], parcel["payment_status"])
        self.assertTrue(mission["return_requested"])
        self.assertEqual(mission["status"], "incident_reported")
        events = await self.database.parcel_events.count_documents({})
        await admin.admin_resolve_incident("parcel", admin.IncidentResolutionRequest(action="return"), {"user_id": "admin", "role": "admin"})
        self.assertEqual(await self.database.parcel_events.count_documents({}), events)

    async def test_driver_destination_notification_opens_mission_not_client_screen(self):
        parcel = await self.change(await self.seed(mission_status="assigned", assigned=True))
        from services import admin_events_service
        with patch.object(notification_service, "db", self.database), patch.object(notification_service, "_store_and_send", AsyncMock()) as send, patch.object(notification_service, "_notify_relay_users", AsyncMock()), patch.object(notification_service, "notify_relay_parcel_incoming", AsyncMock()), patch.object(admin_events_service, "record_admin_event", AsyncMock()):
            await self.notify_destination_original(parcel, {"relay_id": None})
        payload = next(call.kwargs for call in send.await_args_list if call.kwargs["user_id"] == "driver")
        self.assertEqual(payload["ref_id"], "mission")
        self.assertEqual(payload["target_view"], "driver")
        self.assertEqual(payload["event_type"], "mission_detail")
        self.assertNotIn(parcel["relay_pin"], payload["body"])

    async def test_relay_cash_survives_switch_back_home_without_unused_relay_payout(self):
        await self.change(await self.seed(who_pays="recipient"))
        parcel = await self.record_collection("relay", 500)
        preview = await destinations.preview_destination_change(parcel, new_mode="home", address=self.location)
        updated = await destinations.change_destination(parcel, preview, actor_id="recipient", actor_role="client")
        self.assertEqual(updated["financial_contract"]["delivery_mode"], "home_to_relay")
        self.assertEqual(updated["financial_contract"]["destination_relay_id"], "relay")
        self.assertEqual(updated["recipient_collection_plan"]["amount_received_xof"], 500)
        self.assertEqual(updated["recipient_collection_plan"]["amount_due_xof"], 400)
        self.assertEqual(updated["recipient_collection_plan"]["status"], "admin_review")
        self.assertIsNone(updated["recipient_collection_plan"]["collector"])
        self.assertEqual(updated["destination_financial_review"]["amount_xof"], 135)
        actions = settlement_actions(updated)
        self.assertEqual(len(actions), 1)
        self.assertEqual(actions[0]["action"], "recipient_collection_payment")
        self.assertEqual(actions[0]["relay_id"], "relay")
        self.assertEqual(actions[0]["amount_xof"], 500)
        await self.database.parcels.update_one({"parcel_id": "parcel"}, {"$set": {"status": "out_for_delivery"}})
        with self.assertRaises(HTTPException):
            await parcel_service.transition_status("parcel", ParcelStatus.DELIVERED, "driver", "driver")

    async def test_second_redirect_notifies_actual_previous_relay_and_rechecks_collector(self):
        parcel = await self.redirect(await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, who_pays="recipient"))
        parcel = await self.record_collection("relay", 500)
        await self.database.relay_points.insert_one({**self.relay, "relay_id": "second"})
        self.notify.reset_mock()
        updated = await destinations.redirect_destination(parcel, "second", actor_id="admin", actor_role="admin")
        self.assertEqual(self.notify.await_args.kwargs["redirected"], True)
        self.assertEqual(self.notify.await_args.args[1]["relay_id"], "relay")
        self.assertEqual(updated["original_delivery_destination"]["address"], self.location)
        self.assertEqual(updated["recipient_collection_plan"]["status"], "admin_review")
        self.assertIsNone(updated["recipient_collection_plan"]["collector"])
        action = next(item for item in settlement_actions(updated) if item["action"] == "recipient_collection_payment")
        self.assertEqual(action["relay_id"], "relay")

    async def test_return_notification_never_leaks_pin_in_metadata(self):
        parcel = await self.seed(assigned=True)
        parcel["return_code"] = "987654"
        with patch.object(notification_service, "_store_and_send", AsyncMock()) as send:
            await self.notify_return_original(parcel, "mission")
        self.assertNotIn(parcel["return_code"], str(send.await_args.kwargs))
        self.assertEqual(send.await_args.kwargs["ref_id"], "mission")

    async def test_invalid_relay_coordinates_and_capacity_are_controlled_errors(self):
        parcel = await self.seed()
        for fields in ({"address.geopin.lat": float("nan")}, {"address.geopin.lat": 91}, {"max_capacity": "invalid"}):
            await self.database.relay_points.update_one({"relay_id": "relay"}, {"$set": {**self.relay, **fields}})
            with self.assertRaises(HTTPException) as failure:
                await self.change(parcel)
            self.assertEqual(failure.exception.status_code, 400)

    async def test_mission_collection_privacy_and_final_handover_block(self):
        parcel = await self.seed(status="out_for_delivery", mission_status="in_progress", assigned=True, who_pays="recipient")
        with patch.object(deliveries, "get_assigned_mission_auto_release_minutes", AsyncMock(return_value=15)), patch.object(deliveries, "_hydrate_mission_area_labels", AsyncMock()):
            before = await deliveries.get_mission("mission", {"user_id": "driver", "role": "driver"})
            self.assertIsNone(before["recipient_collection_plan"])
            await self.redirect(parcel)
            await self.record_collection("relay", 500)
            relay_mission = await deliveries.get_mission("mission", {"user_id": "driver", "role": "driver"})
            self.assertFalse(relay_mission["delivery_blocked_by_payment"])
            self.assertEqual(relay_mission["recipient_collection_plan"]["collector"], "relay")
            self.assertNotIn("amount_due_xof", relay_mission["recipient_collection_plan"])
            self.assertNotIn("amount_received_xof", relay_mission["recipient_collection_plan"])
            self.assertNotIn("receipts", relay_mission["recipient_collection_plan"])
            self.assertNotIn("note", relay_mission["recipient_collection_plan"])
            await self.database.delivery_missions.update_one({"mission_id": "mission"}, {"$set": {"delivery_type": "gps"}})
            home_mission = await deliveries.get_mission("mission", {"user_id": "driver", "role": "driver"})
            self.assertTrue(home_mission["delivery_blocked_by_payment"])
            await self.database.delivery_missions.update_one({"mission_id": "mission"}, {"$set": {"return_requested": True}})
            return_mission = await deliveries.get_mission("mission", {"user_id": "driver", "role": "driver"})
            self.assertFalse(return_mission["delivery_blocked_by_payment"])


if __name__ == "__main__":
    unittest.main()
