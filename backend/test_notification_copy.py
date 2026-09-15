import unittest

from models.common import ParcelStatus
from services.notification_service import (
    _should_send_whatsapp_tracking,
    _status_title,
)


class NotificationCopyTests(unittest.TestCase):
    def test_creation_distinguishes_sender_and_recipient(self):
        self.assertEqual(_status_title(ParcelStatus.CREATED), "Colis créé")
        self.assertEqual(
            _status_title(ParcelStatus.CREATED, recipient=True),
            "Vous avez un colis à recevoir !",
        )

    def test_arrival_does_not_claim_parcel_is_ready(self):
        self.assertNotEqual(
            _status_title(ParcelStatus.AT_DESTINATION_RELAY),
            _status_title(ParcelStatus.AVAILABLE_AT_RELAY),
        )

    def test_registered_device_avoids_duplicate_whatsapp(self):
        user = {"fcm_tokens": [{"token": "device", "is_active": True}]}
        self.assertFalse(_should_send_whatsapp_tracking(user, "parcel_updates"))

    def test_inactive_device_keeps_whatsapp_fallback(self):
        user = {"fcm_tokens": [{"token": "device", "is_active": False}]}
        self.assertTrue(_should_send_whatsapp_tracking(user, "parcel_updates"))

    def test_disabled_push_keeps_whatsapp_fallback(self):
        user = {
            "fcm_tokens": [{"token": "device"}],
            "notification_prefs": {"push": False},
        }
        self.assertTrue(_should_send_whatsapp_tracking(user, "parcel_updates"))

    def test_disabled_whatsapp_is_respected(self):
        user = {"notification_prefs": {"whatsapp": False}}
        self.assertFalse(_should_send_whatsapp_tracking(user, "parcel_updates"))
