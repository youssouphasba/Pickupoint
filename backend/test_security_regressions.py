import hashlib
import hmac
import unittest
from datetime import datetime, timedelta, timezone

from core.datetime_utils import as_aware_utc
from routers.tracking import (
    _build_public_tracking_payload,
    _public_tracking_has_expired,
    _serialize_public_event,
)
from routers.webhooks import _verify_whatsapp_signature
from core.security import fingerprint_token
from config import settings
from fastapi import HTTPException


class SecurityRegressionTests(unittest.TestCase):
    def test_public_tracking_payload_excludes_sensitive_fields(self):
        parcel = {
            "parcel_id": "p1",
            "tracking_code": "PKP-ABC-1234",
            "status": "created",
            "delivery_mode": "home_to_home",
            "sender_name": "Alice",
            "sender_phone": "+221700000000",
            "recipient_name": "Bob",
            "recipient_phone": "+221710000000",
            "delivery_code": "4455",
            "relay_pin": "1122",
            "origin_location": {"label": "Rue 1", "district": "Mermoz", "city": "Dakar"},
            "delivery_address": {"label": "Rue 2", "district": "Almadies", "city": "Dakar"},
        }
        payload = _build_public_tracking_payload(parcel, [])
        for forbidden_key in (
            "parcel_id",
            "sender_name",
            "sender_phone",
            "recipient_name",
            "recipient_phone",
            "recipient_code",
            "recipient_code_label",
            "recipient_code_help",
            "origin_label",
            "delivery_label",
            "payment_status",
            "description",
            "weight_kg",
            "dimensions_label",
            "pickup_confirmed",
            "delivery_confirmed",
        ):
            self.assertNotIn(forbidden_key, payload)
        self.assertEqual(payload["origin_area_label"], "Mermoz, Dakar")
        self.assertEqual(payload["delivery_area_label"], "Almadies, Dakar")

    def test_public_tracking_expires_after_terminal_retention(self):
        closed_at = datetime(2026, 6, 1, 12, tzinfo=timezone.utc)
        parcel = {
            "status": "delivered",
            "created_at": closed_at - timedelta(days=2),
            "updated_at": closed_at,
        }
        timeline = [
            {
                "to_status": "delivered",
                "created_at": closed_at,
            }
        ]

        self.assertFalse(
            _public_tracking_has_expired(
                parcel,
                timeline,
                now=closed_at
                + timedelta(days=settings.PUBLIC_TRACKING_RETENTION_DAYS - 1),
            )
        )
        self.assertTrue(
            _public_tracking_has_expired(
                parcel,
                timeline,
                now=closed_at
                + timedelta(days=settings.PUBLIC_TRACKING_RETENTION_DAYS),
            )
        )

    def test_active_public_tracking_does_not_expire(self):
        parcel = {
            "status": "in_transit",
            "created_at": datetime(2025, 1, 1, tzinfo=timezone.utc),
            "updated_at": datetime(2025, 1, 2, tzinfo=timezone.utc),
        }

        self.assertFalse(
            _public_tracking_has_expired(
                parcel,
                [],
                now=datetime(2026, 7, 1, tzinfo=timezone.utc),
            )
        )

    def test_public_event_drops_sensitive_notes(self):
        event = {
            "event_type": "PARCEL_UPDATED",
            "to_status": "in_transit",
            "notes": "Code destinataire 4455",
            "metadata": {"secret": True},
        }
        public_event = _serialize_public_event(event)
        self.assertNotIn("notes", public_event)
        self.assertNotIn("metadata", public_event)
        self.assertEqual(public_event["label"], "En transit")

    def test_fingerprint_token_is_deterministic(self):
        token = "refresh-token"
        expected = hmac.new(
            settings.JWT_SECRET.encode(),
            token.encode(),
            hashlib.sha256,
        ).hexdigest()
        self.assertEqual(fingerprint_token(token), expected)

    def test_naive_session_expiry_is_normalized_to_utc(self):
        value = datetime(2026, 6, 29, 23, 35, 38)
        normalized = as_aware_utc(value)
        self.assertEqual(normalized.tzinfo, timezone.utc)
        self.assertEqual(normalized.hour, 23)

    def test_whatsapp_signature_validation(self):
        payload = b'{"entry":[]}'
        original_secret = settings.WHATSAPP_APP_SECRET
        settings.WHATSAPP_APP_SECRET = original_secret or "test-secret"
        signature = "sha256=" + hmac.new(
            settings.WHATSAPP_APP_SECRET.encode(),
            payload,
            hashlib.sha256,
        ).hexdigest()
        try:
            _verify_whatsapp_signature(payload, signature)
            with self.assertRaises(HTTPException):
                _verify_whatsapp_signature(payload, "sha256=bad")
        finally:
            settings.WHATSAPP_APP_SECRET = original_secret


if __name__ == "__main__":
    unittest.main()
