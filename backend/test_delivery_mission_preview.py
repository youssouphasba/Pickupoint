import unittest
from unittest.mock import AsyncMock, patch
from types import SimpleNamespace

from routers.deliveries import mission_preview


class DeliveryMissionPreviewTests(unittest.IsolatedAsyncioTestCase):
    async def test_preview_returns_road_distances_and_polylines(self):
        mission = {
            "mission_id": "mission-1",
            "status": "pending",
            "pickup_geopin": {"lat": 48.8566, "lng": 2.3522},
            "delivery_geopin": {"lat": 48.8462, "lng": 2.3742},
        }
        pickup_route = {
            "distance_meters": 3200,
            "distance_text": "3,2 km",
            "duration_seconds": 720,
            "duration_text": "12 min",
            "encoded_polyline": "pickup-route",
        }
        delivery_route = {
            "distance_meters": 4100,
            "distance_text": "4,1 km",
            "duration_seconds": 900,
            "duration_text": "15 min",
            "encoded_polyline": "delivery-route",
        }
        fake_db = SimpleNamespace(
            delivery_missions=SimpleNamespace(
                find_one=AsyncMock(return_value=mission),
            ),
        )

        with (
            patch(
                "routers.deliveries.db",
                new=fake_db,
            ),
            patch(
                "routers.deliveries._attach_commission_requirements",
                new=AsyncMock(),
            ),
            patch(
                "routers.deliveries.get_directions_eta",
                new=AsyncMock(side_effect=[pickup_route, delivery_route]),
            ),
        ):
            result = await mission_preview(
                mission_id="mission-1",
                lat=48.8666,
                lng=2.3422,
                current_user={"user_id": "admin-1", "role": "admin"},
            )

        preview = result["preview"]
        self.assertEqual(preview["pickup_distance_km"], 3.2)
        self.assertEqual(preview["delivery_distance_km"], 4.1)
        self.assertEqual(preview["total_distance_km"], 7.3)
        self.assertEqual(preview["pickup_encoded_polyline"], "pickup-route")
        self.assertEqual(
            preview["delivery_encoded_polyline"],
            "delivery-route",
        )


if __name__ == "__main__":
    unittest.main()
