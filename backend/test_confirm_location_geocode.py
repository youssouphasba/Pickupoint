import unittest
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from routers.confirm import (
    _apply_reverse_geocode_location,
    _confirmation_response,
    _html_page,
    _relay_picker_page,
)
from config import settings
from services.parcel_service import build_location_area_label


class ConfirmLocationGeocodeTests(unittest.TestCase):
    def test_confirmation_page_allows_only_its_nonce_script(self):
        nonce = "test-nonce"
        page = _html_page(
            token="token-123",
            role="recipient",
            recipient_name="Awa",
            script_nonce=nonce,
        )
        response = _confirmation_response(page, script_nonce=nonce)

        self.assertIn('nonce="test-nonce"', page)
        self.assertNotIn("onclick=", page)
        self.assertIn(
            "addEventListener('click', getLocation)",
            page,
        )
        self.assertIn(
            f'href="{settings.PUBLIC_SITE_URL.rstrip("/")}/app"',
            page,
        )
        self.assertIn(
            "Télécharger l'application Denkma",
            page,
        )
        self.assertIn(
            "script-src 'nonce-test-nonce'",
            response.headers["content-security-policy"],
        )
        self.assertEqual(
            response.headers["permissions-policy"],
            "camera=(), microphone=(self), geolocation=(self)",
        )

    def test_relay_picker_uses_the_same_nonce_policy(self):
        page = _relay_picker_page(
            token="token-123",
            recipient_name="Awa",
            tracking_code="DNK-123",
            relays=[],
            current_relay_id="",
            is_locked=False,
            current_relay_name="",
            script_nonce="relay-nonce",
        )

        self.assertIn('nonce="relay-nonce"', page)

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
