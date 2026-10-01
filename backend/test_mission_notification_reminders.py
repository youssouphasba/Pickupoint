import asyncio
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

from services import notification_service as service


class AtomicUsers:
    def __init__(self):
        self.document = {"user_id": "driver", "is_active": True, "is_available": True}
        self.lock = asyncio.Lock()

    async def find_one_and_update(self, query, update, projection=None):
        async with self.lock:
            for key in ("user_id", "is_active", "is_available"):
                if self.document.get(key) != query[key]:
                    return None
            if self.document.get("is_banned"):
                return None
            last = self.document.get("last_mission_alert_at")
            cutoff = query["$or"][2]["last_mission_alert_at"]["$lte"]
            if last is not None and last > cutoff:
                return None
            previous = deepcopy(self.document)
            self.document.update(update["$set"])
            return previous

    async def update_one(self, query, update):
        async with self.lock:
            if any(self.document.get(key) != value for key, value in query.items()):
                return
            self.document.update(update.get("$set", {}))
            for key in update.get("$unset", {}):
                self.document.pop(key, None)


class MissionReminderTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.users = AtomicUsers()
        self.send = AsyncMock(return_value={"push_status": "sent"})
        for patcher in (
            patch.object(service, "db", SimpleNamespace(users=self.users)),
            patch.object(service, "_store_and_send", self.send),
            patch.object(service.settings, "DRIVER_MISSION_REMINDER_INTERVAL_SECONDS", 300),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    async def remind(self, mission="mission-a", ids=None):
        return await service.notify_pending_mission_dispatch_reminder(
            user_ids=ids or ["driver"], mission={"mission_id": mission}, radius_km=5,
        )

    async def test_multiple_courses_share_one_reminder_cooldown(self):
        first = await self.remind()
        second = await self.remind("mission-b")
        self.assertEqual(first["push_sent"], 1)
        self.assertEqual(second["push_sent"], 0)
        self.assertEqual(self.send.await_count, 1)

    async def test_concurrent_workers_only_send_once(self):
        results = await asyncio.gather(self.remind(), self.remind("mission-b"), self.remind())
        self.assertEqual(sum(result["push_sent"] for result in results), 1)
        self.assertEqual(self.send.await_count, 1)

    async def test_recent_new_course_also_delays_reminder(self):
        self.users.document["last_mission_alert_at"] = datetime.now(timezone.utc) - timedelta(seconds=50)
        self.assertEqual((await self.remind())["push_sent"], 0)
        self.send.assert_not_awaited()

    async def test_cooldown_expires_and_duplicate_targets_do_not_repeat(self):
        self.users.document["last_mission_alert_at"] = datetime.now(timezone.utc) - timedelta(seconds=301)
        self.assertEqual((await self.remind(ids=["driver", "driver"]))["push_sent"], 1)
        self.assertEqual(self.send.await_count, 1)

    async def test_unavailable_inactive_and_banned_drivers_receive_no_reminder(self):
        for field, value in (("is_available", False), ("is_active", False), ("is_banned", True)):
            previous = deepcopy(self.users.document)
            self.users.document[field] = value
            self.assertEqual((await self.remind())["push_sent"], 0)
            self.users.document = previous
        self.send.assert_not_awaited()

    async def test_failed_or_disabled_push_restores_previous_cooldown(self):
        for status in ("failed", "skipped"):
            previous = datetime.now(timezone.utc) - timedelta(seconds=301)
            self.users.document["last_mission_alert_at"] = previous
            self.send.return_value = {"push_status": status}
            await self.remind()
            self.assertEqual(self.users.document["last_mission_alert_at"], previous)

    async def test_exception_releases_reservation(self):
        self.send.side_effect = RuntimeError("simulated failure")
        with self.assertRaises(RuntimeError):
            await self.remind()
        self.assertNotIn("last_mission_alert_at", self.users.document)

    async def test_failure_does_not_overwrite_newer_alert(self):
        newer = datetime.now(timezone.utc) + timedelta(seconds=1)

        async def failure(**kwargs):
            self.users.document["last_mission_alert_at"] = newer
            return {"push_status": "failed"}

        self.send.side_effect = failure
        await self.remind()
        self.assertEqual(self.users.document["last_mission_alert_at"], newer)


if __name__ == "__main__":
    unittest.main()
