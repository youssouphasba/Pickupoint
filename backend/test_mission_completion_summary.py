import unittest
from datetime import datetime, timedelta, timezone

from services.mission_trace import summarize_completion


class MissionCompletionSummaryTests(unittest.TestCase):
    def test_completed_mission_contains_real_durations_and_distance(self):
        assigned_at = datetime(2026, 9, 29, 10, 0, tzinfo=timezone.utc)
        started_at = assigned_at + timedelta(minutes=12)
        completed_at = started_at + timedelta(minutes=28)
        mission = {
            "assigned_at": assigned_at,
            "started_at": started_at,
            "completed_at": completed_at,
        }
        points = [
            {"lat": 14.7000, "lng": -17.4500, "ts": started_at},
            {
                "lat": 14.7010,
                "lng": -17.4500,
                "ts": started_at + timedelta(minutes=1),
            },
        ]

        summary = summarize_completion(mission, points)

        self.assertEqual(summary["assigned_to_pickup_seconds"], 720)
        self.assertEqual(summary["pickup_to_delivery_seconds"], 1680)
        self.assertEqual(summary["total_duration_seconds"], 2400)
        self.assertGreater(summary["recorded_distance_meters"], 100)
        self.assertEqual(summary["gps_points_count"], 2)

    def test_list_summary_does_not_invent_a_distance(self):
        summary = summarize_completion(
            {
                "assigned_at": "2026-09-29T10:00:00Z",
                "completed_at": "2026-09-29T10:30:00Z",
            }
        )

        self.assertEqual(summary["total_duration_seconds"], 1800)
        self.assertIsNone(summary["recorded_distance_meters"])
        self.assertIsNone(summary["gps_points_count"])


if __name__ == "__main__":
    unittest.main()
