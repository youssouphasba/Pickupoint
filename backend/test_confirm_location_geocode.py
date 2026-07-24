import unittest
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from routers.confirm import _apply_reverse_geocode_location
from services.parcel_service import build_location_area_label


class ConfirmLocationGeocodeTests(unittest.TestCase):
    def test_reverse_geocode_overwrites_stale_city(self):
        location = {
            "label": "10 rue de Rivoli",
            "city": "Dakar",
            "district": "Plateau",
        }
        reverse_address = {
            "formatted_address": "10 Rue de Rivoli, 75004 Paris, France",
            "city": "Paris",
            "district": "Paris Centre",
            "country": "France",
            "source": "google_reverse_geocode",
        }

        enriched = _apply_reverse_geocode_location(location, reverse_address)

        self.assertEqual(enriched["city"], "Paris")
        self.assertEqual(enriched["district"], "Paris Centre")
        self.assertEqual(enriched["country"], "France")
        self.assertEqual(
            enriched["formatted_address"],
            "10 Rue de Rivoli, 75004 Paris, France",
        )

    def test_area_label_uses_formatted_address_when_city_is_missing(self):
        label = build_location_area_label(
            {
                "label": "Position expéditeur",
                "formatted_address": "10 Rue de Rivoli, 75004 Paris, France",
            },
            "Position expéditeur",
        )

        self.assertEqual(label, "10 Rue de Rivoli, 75004 Paris, France")


if __name__ == "__main__":
    unittest.main()
