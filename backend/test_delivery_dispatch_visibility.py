import unittest

from routers.deliveries import _can_driver_preview_pending_mission


class DeliveryDispatchVisibilityTests(unittest.TestCase):
    def test_all_candidates_in_the_current_wave_can_preview_the_mission(self):
        mission = {
            "status": "pending",
            "candidate_drivers": ["driver-a", "driver-b"],
            "dispatch_notified_driver_ids": ["driver-a", "driver-b"],
            "dispatch_radius_km": 2.0,
            "pickup_geopin": {"lat": 14.7167, "lng": -17.4677},
        }

        self.assertTrue(
            _can_driver_preview_pending_mission(
                mission,
                "driver-a",
                14.7167,
                -17.4677,
            )
        )
        self.assertTrue(
            _can_driver_preview_pending_mission(
                mission,
                "driver-b",
                14.7167,
                -17.4677,
            )
        )

    def test_driver_outside_the_wave_cannot_preview_the_mission(self):
        mission = {
            "status": "pending",
            "candidate_drivers": ["driver-a"],
            "dispatch_notified_driver_ids": ["driver-a"],
            "dispatch_radius_km": 2.0,
            "pickup_geopin": {"lat": 14.7167, "lng": -17.4677},
        }

        self.assertFalse(
            _can_driver_preview_pending_mission(
                mission,
                "driver-b",
                14.7167,
                -17.4677,
            )
        )

    def test_admin_assignment_is_only_visible_to_the_selected_driver(self):
        mission = {
            "status": "pending",
            "is_broadcast": True,
            "admin_requested_driver_id": "driver-a",
        }

        self.assertTrue(
            _can_driver_preview_pending_mission(
                mission,
                "driver-a",
                None,
                None,
            )
        )
        self.assertFalse(
            _can_driver_preview_pending_mission(
                mission,
                "driver-b",
                None,
                None,
            )
        )


if __name__ == "__main__":
    unittest.main()
