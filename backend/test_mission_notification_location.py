import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, Mock, patch

from config import settings
from services import notification_service, parcel_service
from tests.fake_database import Database


class MissionNotificationLocationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.database = Database()
        self.now = datetime.now(timezone.utc)
        self.database.raw.users.insert_one({
            "user_id": "driver", "role": "driver", "is_active": True, "is_available": True,
            "fcm_token": "test-token", "last_driver_location_at": self.now,
            "last_driver_location": {"lat": 14.7, "lng": -17.4, "accuracy": 20},
        })
        self.database.raw.parcels.insert_one({"parcel_id": "parcel", "status": "created"})
        self.database.raw.delivery_missions.insert_one({
            "mission_id": "offer", "parcel_id": "parcel", "status": "pending", "is_broadcast": True,
            "dispatch_radius_km": 2, "pickup_geopin": {"lat": 14.7, "lng": -17.4},
            "candidate_drivers": ["driver"], "dispatch_notified_driver_ids": ["driver"],
        })
        for service in (notification_service, parcel_service):
            patcher = patch.object(service, "db", self.database)
            patcher.start()
            self.addCleanup(patcher.stop)

    def move_outside(self):
        self.database.raw.users.update_one({"user_id": "driver"}, {
            "$set": {"last_driver_location": {"lat": 14.8, "lng": -17.4, "accuracy": 20}}
        })

    async def reason(self):
        user = await self.database.users.find_one({"user_id": "driver"})
        return await notification_service._mission_availability_skip_reason("driver", "offer", user, None)

    async def test_previously_notified_broadcast_driver_leaving_the_zone_is_not_alerted(self):
        self.move_outside()
        with patch.object(notification_service, "_store_notification", AsyncMock()) as store, \
             patch.object(notification_service, "_send_push", AsyncMock()) as push:
            result = await notification_service._store_and_send(
                "driver", "Course", "Près de vous", ref_id="offer", ref_type="mission",
                event_type="mission_available", skip_whatsapp=True,
            )
        self.assertEqual(result["push_reason"], "driver_outside_dispatch_radius")
        store.assert_not_awaited()
        push.assert_not_awaited()

    async def test_movement_between_selection_and_final_push_is_rechecked(self):
        async def store(**kwargs):
            self.move_outside()
            return "notification", True

        with patch.object(notification_service, "_store_notification", AsyncMock(side_effect=store)), \
             patch.object(notification_service, "_ensure_firebase", Mock()) as firebase:
            result = await notification_service._store_and_send(
                "driver", "Course", "Près de vous", ref_id="offer", ref_type="mission",
                event_type="mission_available", skip_whatsapp=True,
            )
        self.assertEqual(result["push_reason"], "driver_outside_dispatch_radius")
        firebase.assert_not_called()

    async def test_location_older_than_gps_policy_is_not_used_even_inside_dispatch_grace_period(self):
        age = min(settings.GPS_CAPTURE_MAX_AGE_SECONDS, settings.DRIVER_DISPATCH_LOCATION_MAX_AGE_MINUTES * 60) + 1
        self.database.raw.users.update_one({"user_id": "driver"}, {
            "$set": {"last_driver_location_at": self.now - timedelta(seconds=age)}
        })
        self.assertEqual(await self.reason(), "driver_location_stale")
        self.assertEqual(await parcel_service._find_candidate_drivers_within_radius(14.7, -17.4, 2), [])

    async def test_eligible_driver_inside_zone_remains_a_candidate(self):
        self.assertIsNone(await self.reason())
        self.assertEqual(await parcel_service._find_candidate_drivers_within_radius(14.7, -17.4, 2), ["driver"])

    async def test_rejected_and_imprecise_positions_cannot_trigger_a_push(self):
        for changes in (
            {"last_driver_location": {"lat": float("nan"), "lng": -17.4}},
            {"last_driver_location": {"lat": 14.7, "lng": -17.4, "accuracy": settings.DRIVER_GPS_MAX_ACCURACY_METERS + 1}},
            {"last_driver_location_at": self.now + timedelta(seconds=settings.GPS_CLOCK_TOLERANCE_SECONDS + 1)},
        ):
            with self.subTest(changes=changes):
                self.database.raw.users.update_one({"user_id": "driver"}, {"$set": changes})
                self.assertEqual(await self.reason(), "driver_location_stale")

    async def test_taken_or_cancelled_course_is_not_alerted(self):
        self.database.raw.delivery_missions.update_one({"mission_id": "offer"}, {"$set": {"status": "assigned"}})
        self.assertEqual(await self.reason(), "mission_unavailable")
        self.database.raw.delivery_missions.update_one({"mission_id": "offer"}, {"$set": {"status": "pending"}})
        self.database.raw.parcels.update_one({"parcel_id": "parcel"}, {"$set": {"status": "cancelled"}})
        self.assertEqual(await self.reason(), "mission_unavailable")

    async def test_unavailable_driver_cannot_receive_offer(self):
        self.database.raw.users.update_one({"user_id": "driver"}, {"$set": {"is_available": False}})
        self.assertEqual(await self.reason(), "driver_unavailable")

    async def test_outside_zone_reminder_releases_its_cooldown_without_push(self):
        self.move_outside()
        with patch.object(notification_service, "_send_push", AsyncMock()) as push:
            result = await notification_service.notify_pending_mission_dispatch_reminder(
                user_ids=["driver"], mission={"mission_id": "offer"}, radius_km=2,
            )
        self.assertEqual(result["push_sent"], 0)
        push.assert_not_awaited()
        user = await self.database.users.find_one({"user_id": "driver"})
        self.assertNotIn("last_mission_alert_at", user)


if __name__ == "__main__":
    unittest.main()
