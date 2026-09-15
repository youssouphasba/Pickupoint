import unittest
from unittest.mock import AsyncMock, patch

from routers.deliveries import _hydrate_mission_area_labels


class MissionAreaLabelsTests(unittest.IsolatedAsyncioTestCase):
    async def test_resolves_mission_coordinates_when_parcel_has_no_locations(self):
        pickup = {"lat": 48.85, "lng": 2.35}
        delivery = {"lat": 48.86, "lng": 2.36}
        mission = {
            "pickup_geopin": pickup,
            "delivery_geopin": delivery,
            "pickup_label": "Position expéditeur",
            "delivery_label": "Adresse destinataire",
        }
        enrich = AsyncMock(side_effect=[
            {"district": "Quartier A", "city": "Paris"},
            {"district": "Quartier B", "city": "Paris"},
        ])
        with patch("routers.deliveries._enrich_location_from_geopin", enrich):
            await _hydrate_mission_area_labels(mission, {})
        self.assertEqual(enrich.await_args_list[0].args[0]["geopin"], pickup)
        self.assertEqual(enrich.await_args_list[1].args[0]["geopin"], delivery)
        self.assertEqual(mission["pickup_area_label"], "Quartier A, Paris")
        self.assertEqual(mission["delivery_area_label"], "Quartier B, Paris")
