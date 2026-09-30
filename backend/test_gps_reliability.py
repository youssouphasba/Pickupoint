import inspect
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from fastapi import HTTPException
from starlette.requests import Request

from models.common import Address
from models.delivery import LocationUpdate, LocationTraceBatch
from routers import admin, confirm, deliveries, parcels, relay_points
from services import data_retention_service, google_maps_service, parcel_service, relay_geocoding_service
from services.location_quality import client_live_tracking_allowed, location_is_live, validate_capture


NOW = datetime.now(timezone.utc)
DRIVER = {"user_id": "driver-1", "role": "driver", "is_available": False}
ADMIN = {"user_id": "admin-1", "role": "admin"}
RECIPIENT = {"user_id": "recipient-1", "role": "client", "phone": "+221771111111"}
REQUEST = Request({"type": "http", "method": "POST", "path": "/test", "headers": [], "client": ("127.0.0.1", 1234)})


class Cursor:
    def __init__(self, rows):
        self.rows = rows
    def sort(self, *args):
        return self
    async def to_list(self, length=None):
        return self.rows if length is None else self.rows[:length]


class LocationQualityTests(unittest.TestCase):
    def test_relay_to_home_policy_requires_recipient_and_collected_home_delivery(self):
        parcel = {"delivery_mode": "relay_to_home", "status": "in_transit"}
        mission = {"status": "in_progress", "started_at": NOW, "delivery_type": "gps"}
        self.assertTrue(client_live_tracking_allowed(parcel, mission, is_recipient=True))
        self.assertFalse(client_live_tracking_allowed(parcel, mission, is_recipient=False))
        for changes in ({"status": "assigned"}, {"started_at": None}, {"delivery_type": "relay"}, {"completed_at": NOW}, {"status": "completed"}):
            self.assertFalse(client_live_tracking_allowed(parcel, {**mission, **changes}, is_recipient=True))
        for status in ("created", "dropped_at_origin_relay", "at_destination_relay", "delivered", "cancelled", "returned"):
            self.assertFalse(client_live_tracking_allowed({**parcel, "status": status}, mission, is_recipient=True))

    def test_imprecise_capture_is_rejected(self):
        with self.assertRaises(HTTPException):
            validate_capture(5000, NOW)

    def test_cached_capture_is_not_live(self):
        with self.assertRaises(HTTPException):
            validate_capture(20, NOW - timedelta(hours=2))
        self.assertFalse(location_is_live({"accuracy": 20}, NOW - timedelta(hours=2)))

    def test_old_clients_are_compatible_but_new_strict_actions_require_accuracy(self):
        self.assertIsNotNone(validate_capture(None))
        with self.assertRaises(HTTPException):
            validate_capture(None, NOW, strict=True)

    def test_future_and_non_finite_captures_are_rejected(self):
        for accuracy in (float("inf"), float("nan"), -1):
            with self.assertRaises(HTTPException):
                validate_capture(accuracy)
        with self.assertRaises(HTTPException):
            validate_capture(20, NOW + timedelta(hours=1))

    def test_historical_capture_keeps_measurement_time(self):
        old = NOW - timedelta(hours=2)
        self.assertEqual(validate_capture(20, old, historical=True), old)

    def test_invalid_coordinates_cannot_be_marked_live(self):
        for location in ({"lat": float("nan"), "lng": -17}, {"lat": 91, "lng": -17}, {"lat": 14, "lng": 181}, {"lat": "14", "lng": -17}, {}):
            self.assertFalse(location_is_live(location, NOW, now=NOW))
        self.assertTrue(location_is_live({"lat": 0, "lng": 0}, NOW, now=NOW))


class GpsRouteTests(unittest.IsolatedAsyncioTestCase):
    def database(self, mission=None, parcel=None):
        return SimpleNamespace(
            users=SimpleNamespace(update_one=AsyncMock(return_value=SimpleNamespace(matched_count=1, modified_count=1))),
            delivery_missions=SimpleNamespace(find_one=AsyncMock(return_value=mission), update_one=AsyncMock(return_value=SimpleNamespace(matched_count=1, modified_count=0))),
            parcels=SimpleNamespace(find_one=AsyncMock(return_value=parcel)),
        )

    async def test_presence_stores_capture_time_not_receipt_time(self):
        database = self.database()
        captured = datetime.now(timezone.utc) - timedelta(seconds=20)
        with patch.object(deliveries, "db", database):
            await deliveries._update_driver_presence_location(body=LocationUpdate(lat=14, lng=-17, accuracy=20, captured_at=captured), current_user=DRIVER)
        query, update = database.users.update_one.call_args.args
        self.assertEqual(update["$set"]["last_driver_location_at"], captured)
        self.assertIn("$or", query)

    async def test_bad_presence_has_no_database_write(self):
        database = self.database()
        with patch.object(deliveries, "db", database):
            with self.assertRaises(HTTPException):
                await deliveries._update_driver_presence_location(body=LocationUpdate(lat=14, lng=-17, accuracy=5000), current_user=DRIVER)
        database.users.update_one.assert_not_awaited()

    async def test_completed_mission_rejects_live_updates(self):
        database = self.database({"mission_id": "m1", "status": "completed", "driver_id": "driver-1"})
        with patch.object(deliveries, "db", database):
            with self.assertRaises(HTTPException):
                await deliveries.update_location("m1", LocationUpdate(lat=14, lng=-17, accuracy=20), DRIVER)
        database.delivery_missions.update_one.assert_not_awaited()

    async def test_stale_client_location_is_not_available(self):
        database = self.database(
            {"driver_location": {"lat": 14, "lng": -17, "accuracy": 20}, "location_updated_at": NOW - timedelta(hours=2), "eta_text": "5 min"},
            {"parcel_id": "p1", "sender_user_id": "u1", "delivery_mode": "home_to_home"},
        )
        with patch.object(parcels, "db", database):
            response = await parcels.get_driver_location("p1", {"user_id": "u1", "role": "client"})
        self.assertFalse(response["available"])
        self.assertIsNotNone(response["location"])
        self.assertIsNone(response["eta_text"])

    async def test_no_sender_live_for_any_relay_mode_but_admin_keeps_it(self):
        for mode in ("home_to_relay", "relay_to_home", "relay_to_relay"):
            database = self.database(
                {"driver_location": {"lat": 14, "lng": -17, "accuracy": 20}, "location_updated_at": datetime.now(timezone.utc)},
                {"parcel_id": "p1", "sender_user_id": "u1", "delivery_mode": mode},
            )
            with patch.object(parcels, "db", database):
                response = await parcels.get_driver_location("p1", {"user_id": "u1", "role": "client"})
                self.assertFalse(response["available"])
                database.delivery_missions.find_one.assert_not_awaited()
                response = await parcels.get_driver_location("p1", ADMIN)
                self.assertTrue(response["available"])

    async def test_relay_to_home_recipient_live_starts_after_collection_and_excludes_approach(self):
        start = datetime.now(timezone.utc) - timedelta(seconds=20)
        captured = datetime.now(timezone.utc)
        mission = {"status": "in_progress", "started_at": start, "delivery_type": "gps", "driver_location": {"lat": 14, "lng": -17, "accuracy": 20}, "location_updated_at": captured, "eta_target_status": "in_progress", "eta_text": "5 min", "gps_trail": [{"lat": 13, "lng": -17, "ts": start - timedelta(seconds=10)}, {"lat": 14, "lng": -17, "ts": captured}]}
        parcel = {"parcel_id": "p1", "sender_user_id": "sender-1", "recipient_user_id": RECIPIENT["user_id"], "delivery_mode": "relay_to_home", "status": "in_transit"}
        database = self.database(mission, parcel)
        with patch.object(parcels, "db", database):
            response = await parcels.get_driver_location("p1", RECIPIENT)
        self.assertTrue(response["available"])
        self.assertEqual(response["eta_text"], "5 min")
        self.assertEqual(response["trail"], [{"lat": 14, "lng": -17}])
        self.assertEqual(len(response["trace_summary"]["segments"][0]), 1)

    async def test_relay_to_home_recipient_can_be_identified_by_phone(self):
        captured = datetime.now(timezone.utc)
        mission = {"status": "in_progress", "started_at": captured - timedelta(seconds=20), "delivery_type": "gps", "driver_location": {"lat": 14, "lng": -17, "accuracy": 20}, "location_updated_at": captured}
        parcel = {"parcel_id": "p1", "sender_user_id": "sender-1", "recipient_phone": "771111111", "delivery_mode": "relay_to_home", "status": "in_transit"}
        with patch.object(parcels, "db", self.database(mission, parcel)):
            response = await parcels.get_driver_location("p1", RECIPIENT)
        self.assertTrue(response["available"])

    async def test_relay_to_home_pre_collection_location_and_transit_leg_are_hidden(self):
        now = datetime.now(timezone.utc)
        base_mission = {"status": "in_progress", "started_at": now - timedelta(seconds=20), "delivery_type": "gps", "driver_location": {"lat": 14, "lng": -17, "accuracy": 20}, "location_updated_at": now}
        parcel = {"parcel_id": "p1", "recipient_user_id": RECIPIENT["user_id"], "delivery_mode": "relay_to_home", "status": "in_transit"}
        for changes in ({"status": "assigned", "started_at": None}, {"location_updated_at": now - timedelta(seconds=30)}, {"delivery_type": "relay"}, {"status": "completed"}):
            with patch.object(parcels, "db", self.database({**base_mission, **changes}, parcel)):
                response = await parcels.get_driver_location("p1", RECIPIENT)
            self.assertFalse(response["available"])
            self.assertIsNone(response["location"])

    async def test_other_relay_modes_still_hide_live_for_the_recipient(self):
        for mode in ("home_to_relay", "relay_to_relay"):
            parcel = {"parcel_id": "p1", "recipient_user_id": RECIPIENT["user_id"], "delivery_mode": mode, "status": "in_transit"}
            database = self.database(parcel=parcel)
            with patch.object(parcels, "db", database):
                response = await parcels.get_driver_location("p1", RECIPIENT)
            self.assertIsNone(response["location"])
            database.delivery_missions.find_one.assert_not_awaited()

    async def test_relay_to_home_old_collection_eta_is_hidden_after_pickup(self):
        now = datetime.now(timezone.utc)
        mission = {"status": "in_progress", "started_at": now - timedelta(seconds=20), "delivery_type": "gps", "driver_location": {"lat": 14, "lng": -17, "accuracy": 20}, "location_updated_at": now, "eta_target_status": "assigned", "eta_text": "5 min", "encoded_polyline": "old-route"}
        parcel = {"parcel_id": "p1", "recipient_user_id": RECIPIENT["user_id"], "delivery_mode": "relay_to_home", "status": "in_transit"}
        with patch.object(parcels, "db", self.database(mission, parcel)):
            response = await parcels.get_driver_location("p1", RECIPIENT)
        self.assertTrue(response["available"])
        self.assertIsNone(response["eta_text"])
        self.assertIsNone(response["encoded_polyline"])

    async def test_parcel_detail_has_same_recipient_collection_gate_as_live_endpoint(self):
        now = datetime.now(timezone.utc)
        base_mission = {"status": "in_progress", "started_at": now - timedelta(seconds=20), "delivery_type": "gps", "driver_location": {"lat": 14, "lng": -17, "accuracy": 20}, "location_updated_at": now, "eta_target_status": "in_progress", "eta_text": "5 min"}
        base_parcel = {"parcel_id": "p1", "sender_user_id": "sender-1", "recipient_user_id": RECIPIENT["user_id"], "delivery_mode": "relay_to_home", "status": "in_transit"}
        cases = [(RECIPIENT, base_mission, True), ({"user_id": "sender-1", "role": "client"}, base_mission, False), (RECIPIENT, {**base_mission, "status": "assigned", "started_at": None}, False), (RECIPIENT, {**base_mission, "delivery_type": "relay"}, False)]
        for viewer, mission, allowed in cases:
            database = self.database(mission, dict(base_parcel))
            database.users.find_one = AsyncMock(return_value=None)
            with patch.object(parcels, "db", database), patch.object(parcels, "get_parcel_timeline", AsyncMock(return_value=[])), patch.object(parcels, "_ensure_return_code_for_incident", AsyncMock()):
                response = await parcels.get_parcel("p1", viewer)
            self.assertEqual(response["parcel"]["live_tracking_allowed"], allowed)
            self.assertEqual(response["parcel"]["driver_location"], mission["driver_location"] if allowed else None)

    async def test_offline_trace_is_only_between_pickup_and_delivery(self):
        start = NOW - timedelta(hours=2)
        end = NOW - timedelta(hours=1)
        database = self.database({"mission_id": "m1", "driver_id": "driver-1", "status": "completed", "started_at": start, "completed_at": end})
        body = LocationTraceBatch(points=[LocationUpdate(lat=14, lng=-17, accuracy=20, captured_at=ts) for ts in (start - timedelta(minutes=1), start + timedelta(minutes=1), end + timedelta(minutes=1))])
        with patch.object(deliveries, "db", database), patch.object(deliveries, "archive_position", AsyncMock()) as archive:
            result = await deliveries.upload_location_trace("m1", body, DRIVER)
        self.assertEqual(result["recorded"], 1)
        self.assertEqual(archive.call_args.args[1]["ts"], start + timedelta(minutes=1))
        database.delivery_missions.update_one.assert_not_awaited()
        database.users.update_one.assert_not_awaited()

    async def test_other_driver_cannot_upload_trace(self):
        database = self.database({"driver_id": "other", "started_at": NOW})
        with patch.object(deliveries, "db", database), patch.object(deliveries, "archive_position", AsyncMock()) as archive:
            with self.assertRaises(HTTPException):
                await deliveries.upload_location_trace("m1", LocationTraceBatch(points=[LocationUpdate(lat=14, lng=-17, captured_at=NOW)]), DRIVER)
        archive.assert_not_awaited()

    async def test_eta_failure_uses_short_retry_and_does_not_mark_success(self):
        database = self.database({"mission_id": "m1", "parcel_id": "p1", "driver_id": "driver-1", "status": "assigned", "pickup_geopin": {"lat": 14, "lng": -17}})
        with patch.object(deliveries, "db", database), patch.object(deliveries, "get_directions_eta", AsyncMock(return_value=None)):
            await deliveries.update_location("m1", LocationUpdate(lat=14.1, lng=-17.1, accuracy=20), DRIVER)
        update = database.delivery_missions.update_one.call_args_list[0].args[1]
        self.assertIn("eta_attempted_at", update["$set"])
        self.assertNotIn("eta_updated_at", update["$set"])
        query = database.delivery_missions.update_one.call_args_list[0].args[0]
        self.assertEqual(query["status"], "assigned")
        self.assertEqual(query["pickup_geopin"], {"lat": 14, "lng": -17})

    async def test_concurrent_route_change_does_not_overwrite_eta_or_acknowledge_trace(self):
        database = self.database({"mission_id": "m1", "parcel_id": "p1", "driver_id": "driver-1", "status": "assigned", "pickup_geopin": {"lat": 14, "lng": -17}})
        database.delivery_missions.update_one.return_value = SimpleNamespace(matched_count=0)
        with patch.object(deliveries, "db", database), patch.object(deliveries, "get_directions_eta", AsyncMock(return_value={"duration_seconds": 60, "duration_text": "1 min", "distance_text": "1 km"})):
            response = await deliveries.update_location("m1", LocationUpdate(lat=14.1, lng=-17.1, accuracy=20), DRIVER)
        self.assertFalse(response["trace_recorded"])
        database.users.update_one.assert_not_awaited()

    async def test_relay_mode_does_not_receive_live_client_distance_notifications(self):
        database = self.database({"mission_id": "m1", "parcel_id": "p1", "driver_id": "driver-1", "status": "assigned"}, {"parcel_id": "p1", "delivery_mode": "relay_to_relay", "sender_user_id": "client-1"})
        database.delivery_missions.update_one.return_value = SimpleNamespace(matched_count=1, modified_count=1)
        with patch.object(deliveries, "db", database), patch.object(deliveries, "notify_tracking_progress", AsyncMock()) as notify:
            await deliveries.update_location("m1", LocationUpdate(lat=14.1, lng=-17.1, accuracy=20), DRIVER)
        notify.assert_not_awaited()

    async def test_relay_to_home_progress_notifies_only_recipient_after_collection(self):
        start = datetime.now(timezone.utc) - timedelta(minutes=1)
        base_mission = {"mission_id": "m1", "parcel_id": "p1", "driver_id": "driver-1", "status": "in_progress", "started_at": start, "delivery_type": "gps", "gps_archive_initialized": True}
        parcel = {"parcel_id": "p1", "delivery_mode": "relay_to_home", "status": "in_transit", "sender_user_id": "sender-1", "recipient_user_id": RECIPIENT["user_id"]}
        for changes, should_notify in (({}, True), ({"status": "assigned", "started_at": None}, False), ({"delivery_type": "relay"}, False)):
            database = self.database({**base_mission, **changes}, parcel)
            database.delivery_missions.update_one.return_value = SimpleNamespace(matched_count=1, modified_count=1)
            with patch.object(deliveries, "db", database), patch.object(deliveries, "archive_position", AsyncMock()), patch.object(deliveries, "notify_tracking_progress", AsyncMock()) as notify:
                await deliveries.update_location("m1", LocationUpdate(lat=14.1, lng=-17.1, accuracy=20), DRIVER)
            if should_notify:
                self.assertEqual(notify.call_args.args[0], [RECIPIENT["user_id"]])
                self.assertEqual(notify.call_args.kwargs["phase"], "Livreur en route vers la livraison")
            else:
                notify.assert_not_awaited()

    async def test_target_sync_updates_pickup_delivery_and_invalidates_old_route(self):
        mission = {"mission_id": "m1", "status": "assigned", "pickup_type": "gps", "pickup_geopin": {"lat": 1, "lng": 1}, "delivery_type": "gps", "delivery_geopin": {"lat": 2, "lng": 2}}
        database = self.database(mission)
        parcel = {"parcel_id": "p1", "origin_location": {"label": "Collecte", "geopin": {"lat": 14, "lng": -17}}, "delivery_address": {"label": "Livraison", "geopin": {"lat": 15, "lng": -16}}}
        with patch.object(parcel_service, "db", database):
            await parcel_service.sync_active_mission_with_parcel(parcel)
        update = database.delivery_missions.update_one.call_args.args[1]
        self.assertEqual(update["$set"]["pickup_geopin"]["lat"], 14)
        self.assertEqual(update["$set"]["delivery_geopin"]["lat"], 15)
        self.assertIn("encoded_polyline", update["$unset"])

    async def test_manual_token_confirmation_is_supported_and_syncs_existing_mission(self):
        original = {"parcel_id": "p1", "recipient_confirm_token": "token", "status": "created", "delivery_mode": "home_to_home"}
        refreshed = {**original, "delivery_address": {"geopin": {"lat": 14, "lng": -17}}}
        database = self.database(parcel=original)
        database.parcels.find_one = AsyncMock(side_effect=[original, refreshed])
        database.parcels.update_one = AsyncMock()
        with patch.object(confirm, "db", database), patch.object(confirm, "reverse_geocode", AsyncMock(return_value=None)), patch.object(confirm, "_record_event", AsyncMock()), patch.object(confirm, "_save_confirmation_voice_note", AsyncMock(return_value=None)), patch.object(confirm, "_refresh_quote_if_ready", AsyncMock(return_value=(refreshed, False))), patch.object(confirm, "sync_active_mission_with_parcel", AsyncMock()) as sync, patch.object(parcel_service, "_create_delivery_mission", AsyncMock()), patch("services.notification_service.notify_location_updated", AsyncMock()):
            await inspect.unwrap(confirm.confirm_location)("token", confirm.LocationPayload(lat=14, lng=-17, source="manual", label="Maison"), REQUEST)
        update = database.parcels.update_one.call_args.args[1]["$set"]
        self.assertEqual(update["delivery_address"]["geopin"]["source"], "manual")
        sync.assert_awaited_once_with(refreshed)

    async def test_sync_preserves_known_coordinates_when_legacy_parcel_has_no_address(self):
        mission = {"mission_id": "m1", "status": "assigned", "pickup_geopin": {"lat": 14, "lng": -17}, "delivery_geopin": {"lat": 15, "lng": -16}, "pickup_city": "Dakar", "pickup_area_label": "Dakar, Plateau"}
        database = self.database(mission)
        with patch.object(parcel_service, "db", database):
            await parcel_service.sync_active_mission_with_parcel({"parcel_id": "p1"})
        update = database.delivery_missions.update_one.call_args.args[1]
        self.assertEqual(update["$set"]["pickup_geopin"], mission["pickup_geopin"])
        self.assertEqual(update["$set"]["delivery_geopin"], mission["delivery_geopin"])
        self.assertEqual(update["$set"]["pickup_area_label"], mission["pickup_area_label"])
        self.assertNotIn("$unset", update)

    async def test_relay_city_is_corrected_from_its_actual_coordinates(self):
        with patch.object(relay_geocoding_service, "reverse_geocode", AsyncMock(return_value={"formatted_address": "Paris, France", "city": "Paris"})):
            address = await relay_geocoding_service.geocode_relay_address(Address(label="Paris", city="Dakar", geopin={"lat": 48.8, "lng": 2.3}))
        self.assertEqual(address.city, "Paris")

    async def test_nearby_relays_excludes_outside_circle_and_sorts_before_limit(self):
        relays = [{"relay_id": "outside", "address": {"geopin": {"lat": 14.04, "lng": -17.04}}}, {"relay_id": "inside", "address": {"geopin": {"lat": 14.001, "lng": -17.001}}}]
        database = SimpleNamespace(relay_points=SimpleNamespace(find=lambda *args: Cursor(relays)))
        with patch.object(relay_points, "db", database):
            result = await inspect.unwrap(relay_points.nearby_relay_points)(REQUEST, 14, -17, 5)
        self.assertEqual([relay["relay_id"] for relay in result["relay_points"]], ["inside"])

    async def test_retention_paginate_past_the_first_batch(self):
        batches = [[{"mission_id": f"m{i:04}"} for i in range(500)], [{"mission_id": "m0500"}], []]
        queries = []
        def find(query, projection):
            queries.append(query)
            return Cursor(batches.pop(0))
        database = SimpleNamespace(delivery_missions=SimpleNamespace(find=find, update_many=AsyncMock(return_value=SimpleNamespace(modified_count=1))), mission_gps_points=SimpleNamespace(delete_many=AsyncMock(return_value=SimpleNamespace(deleted_count=1))))
        with patch.object(data_retention_service, "db", database):
            result = await data_retention_service._purge_mission_traces(NOW)
        self.assertEqual(result["mission_points"], 2)
        self.assertEqual(queries[1]["mission_id"], {"$gt": "m0499"})
        self.assertIn("gps_trace_purged_at", queries[0])

    async def test_geocoding_cache_avoids_duplicates_and_returns_independent_data(self):
        google_maps_service._geocode_cache.clear()
        loader = AsyncMock(return_value={"city": "Dakar"})
        first = await google_maps_service._cached_geocode(("test", 1), loader)
        first["city"] = "Other"
        second = await google_maps_service._cached_geocode(("test", 1), loader)
        self.assertEqual(second["city"], "Dakar")
        loader.assert_awaited_once()
        google_maps_service._geocode_cache.clear()

    async def test_admin_selected_trace_loads_complete_archive_beyond_recent_buffer(self):
        start = NOW - timedelta(hours=2)
        mission = {"mission_id": "m1", "started_at": start}
        database = self.database(mission)
        points = [{"lat": 14 + i / 100000, "lng": -17, "ts": start + timedelta(seconds=i * 15)} for i in range(500)]
        with patch.object(admin, "db", database), patch.object(admin, "load_trace", AsyncMock(return_value=points)):
            result = await admin.get_fleet_mission_trace("m1", ADMIN)
        self.assertEqual(len(result["trace_summary"]["segments"][0]), 500)


if __name__ == "__main__":
    unittest.main()
