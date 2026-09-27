import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

from services.mission_trace import load_trace, summarize_trace


class MissionTraceTests(unittest.IsolatedAsyncioTestCase):
    def point(self, seconds, lng=0):
        return {"lat": 0, "lng": lng, "ts": datetime(2026, 1, 1, tzinfo=timezone.utc) + timedelta(seconds=seconds), "driver_id": "driver"}

    def test_distance_does_not_bridge_missing_signal(self):
        with patch("services.mission_trace.settings", SimpleNamespace(GPS_TRACE_GAP_SECONDS=180, GPS_TRACE_MAX_SPEED_KMH=160)):
            summary = summarize_trace([self.point(0), self.point(30, .001), self.point(600, .1)])
        self.assertEqual(len(summary["segments"]), 2)
        self.assertEqual(len(summary["gaps"]), 1)
        self.assertAlmostEqual(summary["recorded_distance_meters"], 111, delta=2)

    def test_impossible_jump_and_driver_change_are_not_connected(self):
        points = [self.point(0), self.point(1, 1), {**self.point(30, 1.001), "driver_id": "other"}]
        result = summarize_trace(points)
        self.assertEqual(len(result["segments"]), 3)
        self.assertEqual(result["recorded_distance_meters"], 0)

    async def test_history_over_300_points_merges_legacy_without_duplicates(self):
        archived = [self.point(i * 30, i * .001) for i in range(450)]
        collection = MagicMock()
        collection.find.return_value.sort.return_value.to_list = AsyncMock(return_value=archived)
        with patch("services.mission_trace.db", SimpleNamespace(mission_gps_points=collection)):
            result = await load_trace({"mission_id": "mission", "started_at": archived[0]["ts"], "gps_trail": archived[-300:]})
        self.assertEqual(len(result), 450)
        self.assertEqual(result[0]["ts"], archived[0]["ts"])
        self.assertEqual(result[-1]["ts"], archived[-1]["ts"])

    async def test_trace_excludes_before_pickup_and_after_delivery(self):
        points = [self.point(i * 30) for i in range(5)]
        collection = MagicMock()
        collection.find.return_value.sort.return_value.to_list = AsyncMock(return_value=points)
        with patch("services.mission_trace.db", SimpleNamespace(mission_gps_points=collection)):
            result = await load_trace({"mission_id": "mission", "started_at": points[1]["ts"], "completed_at": points[3]["ts"], "gps_trail": points})
        self.assertEqual(len(result), 3)
        self.assertEqual(result[0]["ts"], points[1]["ts"])
        self.assertEqual(result[-1]["ts"], points[3]["ts"])

    async def test_no_trace_before_pickup(self):
        self.assertEqual(await load_trace({"mission_id": "mission"}), [])


if __name__ == "__main__":
    unittest.main()
