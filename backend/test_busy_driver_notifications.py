from copy import deepcopy
from datetime import datetime, timezone
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, Mock, patch

from models.delivery import ACTIVE_MISSION_STATUSES
from routers import deliveries
from services import notification_service, parcel_service


class MissionRows:
    def __init__(self):
        self.rows = []

    def matches(self, row, query):
        return all(
            row.get(key) in value["$in"] if isinstance(value, dict)
            else row.get(key) == value
            for key, value in query.items()
        )

    async def find_one(self, query, projection=None):
        return next((deepcopy(row) for row in self.rows if self.matches(row, query)), None)

    async def distinct(self, key, query):
        return list({row[key] for row in self.rows if self.matches(row, query)})


class BusyDriverNotificationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.missions = MissionRows()
        self.user = {"user_id": "driver", "is_available": True, "fcm_token": "test-token"}
        self.database = SimpleNamespace(
            users=SimpleNamespace(find_one=AsyncMock(return_value=self.user)),
            delivery_missions=self.missions,
        )
        patcher = patch.object(notification_service, "db", self.database)
        patcher.start()
        self.addCleanup(patcher.stop)

    async def test_no_new_offer_is_stored_or_sent_in_any_active_state(self):
        for status in ACTIVE_MISSION_STATUSES:
            with self.subTest(status=status):
                self.missions.rows = [{"mission_id": "current", "driver_id": "driver", "status": status}]
                with patch.object(notification_service, "_store_notification", AsyncMock()) as store, \
                     patch.object(notification_service, "_send_push", AsyncMock()) as push:
                    result = await notification_service._store_and_send(
                        "driver", "Nouvelle course", "Course proposée", event_type="mission_available",
                    )
                self.assertEqual(result["push_reason"], "active_mission")
                store.assert_not_awaited()
                push.assert_not_awaited()

    async def test_last_push_guard_blocks_direct_dispatch_or_acceptance_race(self):
        self.missions.rows = [{"mission_id": "current", "driver_id": "driver", "status": "assigned"}]
        with patch.object(notification_service, "_ensure_firebase", Mock()) as firebase:
            result = await notification_service._send_push(
                "driver", "Nouvelle course", "Course proposée", event_type="mission_available",
            )
        self.assertEqual(result["push_reason"], "active_mission")
        firebase.assert_not_called()

    async def test_acceptance_between_storage_and_push_still_prevents_the_alert(self):
        async def store(**kwargs):
            self.missions.rows = [{"mission_id": "current", "driver_id": "driver", "status": "assigned"}]
            return "notification", True

        with patch.object(notification_service, "_store_notification", AsyncMock(side_effect=store)), \
             patch.object(notification_service, "_ensure_firebase", Mock()) as firebase:
            result = await notification_service._store_and_send(
                "driver", "Nouvelle course", "Course proposée", event_type="mission_available", skip_whatsapp=True,
            )
        self.assertEqual(result["push_reason"], "active_mission")
        firebase.assert_not_called()

    async def test_notifications_resume_after_completion_failure_or_cancellation(self):
        for status in ("completed", "failed", "cancelled"):
            with self.subTest(status=status):
                self.missions.rows = [{"mission_id": "old", "driver_id": "driver", "status": status}]
                with patch.object(notification_service, "_store_notification", AsyncMock(return_value=("notif", True))), \
                     patch.object(notification_service, "_send_push", AsyncMock(return_value={"push_status": "sent"})), \
                     patch.object(notification_service, "_send_whatsapp", AsyncMock()):
                    result = await notification_service._store_and_send(
                        "driver", "Nouvelle course", "Course proposée", event_type="mission_available",
                    )
                self.assertEqual(result["push_status"], "sent")

    async def test_other_drivers_active_missions_do_not_block_this_driver(self):
        self.missions.rows = [{"mission_id": "other", "driver_id": "another-driver", "status": "in_progress"}]
        self.assertFalse(await notification_service._driver_has_active_mission("driver"))

    async def test_active_course_messages_and_collection_reminders_are_preserved(self):
        self.missions.rows = [{"mission_id": "current", "driver_id": "driver", "status": "in_progress"}]
        for event in ("mission_detail", "parcel_message", "wallet"):
            with self.subTest(event=event), \
                 patch.object(notification_service, "_store_notification", AsyncMock(return_value=("notif", True))), \
                 patch.object(notification_service, "_send_push", AsyncMock(return_value={"push_status": "sent"})):
                result = await notification_service._store_and_send(
                    "driver", "Mission en cours", "Information importante", event_type=event, skip_whatsapp=True,
                )
            self.assertEqual(result["push_status"], "sent")

    async def test_entering_a_new_dispatch_zone_while_busy_does_not_mark_offers_notified(self):
        self.missions.rows = [{"mission_id": "current", "driver_id": "driver", "status": "in_progress"}]
        with patch.object(deliveries, "db", self.database), \
             patch.object(deliveries, "notify_new_mission_dispatch_wave", AsyncMock()) as send:
            count = await deliveries._notify_driver_when_entering_dispatch_radius(
                driver_user_id="driver", lat=14.7, lng=-17.4, now=datetime.now(timezone.utc),
            )
        self.assertEqual(count, 0)
        send.assert_not_awaited()

    async def test_admin_proposals_do_not_target_a_busy_driver(self):
        self.missions.rows = [{"mission_id": "current", "driver_id": "driver", "status": "incident_reported"}]
        with patch.object(deliveries, "db", self.database):
            result = await deliveries._eligible_driver_ids_for_dispatch_stage(
                {"admin_requested_driver_id": "driver"}, {}, None,
            )
        self.assertEqual(result, [])
        self.missions.rows[0]["status"] = "completed"
        with patch.object(deliveries, "db", self.database):
            result = await deliveries._eligible_driver_ids_for_dispatch_stage(
                {"admin_requested_driver_id": "driver"}, {}, None,
            )
        self.assertEqual(result, ["driver"])

    async def test_nearby_candidate_search_excludes_busy_drivers_then_restores_them(self):
        class Cursor:
            async def to_list(self, length=None):
                return [
                    {"user_id": user_id, "last_driver_location": {"lat": 14.7, "lng": -17.4}}
                    for user_id in ("driver", "free-driver")
                ]

        self.database.users.find = Mock(return_value=Cursor())
        with patch.object(parcel_service, "db", self.database):
            for status in ACTIVE_MISSION_STATUSES:
                self.missions.rows = [{"mission_id": "current", "driver_id": "driver", "status": status}]
                self.assertEqual(await parcel_service._find_candidate_drivers_within_radius(14.7, -17.4, 5), ["free-driver"])
                self.assertEqual(await parcel_service._find_nearest_candidate_drivers(14.7, -17.4), ["free-driver"])
            self.missions.rows[0]["status"] = "completed"
            self.assertEqual(await parcel_service._find_candidate_drivers_within_radius(14.7, -17.4, 5), ["driver", "free-driver"])

    async def test_reminder_does_not_consume_the_cooldown_while_busy(self):
        now = datetime.now(timezone.utc)
        self.database.users.find_one_and_update = AsyncMock(return_value={})
        self.database.users.update_one = AsyncMock()
        self.missions.rows = [{"mission_id": "current", "driver_id": "driver", "status": "in_progress"}]
        with patch.object(notification_service, "_send_push", AsyncMock()) as push:
            result = await notification_service.notify_pending_mission_dispatch_reminder(
                user_ids=["driver"], mission={"mission_id": "available"}, radius_km=5,
            )
        self.assertEqual(result["push_sent"], 0)
        push.assert_not_awaited()
        self.database.users.update_one.assert_awaited_once()
        query, update = self.database.users.update_one.call_args.args
        self.assertGreaterEqual(query["last_mission_alert_at"], now)
        self.assertEqual(update, {"$unset": {"last_mission_alert_at": ""}})


if __name__ == "__main__":
    unittest.main()
