import unittest
import sys
from types import ModuleType, SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

from services import notification_service
from services.notification_service import _push_alert_profile, _android_alert_channel_id
from models.user import NotificationPrefs


class PushAlertProfileTests(unittest.TestCase):
    def test_old_accounts_keep_vibration_enabled_by_default(self):
        self.assertTrue(NotificationPrefs().android_vibration)
        profile = _push_alert_profile("mission_available", "mission", "parcel_updates")
        for user in ({}, {"notification_prefs": {"android_vibration": True}}):
            self.assertEqual(_android_alert_channel_id(profile, user), profile["android_channel_id"])

    def test_no_vibration_channels_preserve_sounds_and_profile_definitions(self):
        user = {"notification_prefs": {"android_vibration": False}}
        for profile in notification_service._PUSH_ALERT_PROFILES.values():
            original = dict(profile)
            self.assertEqual(_android_alert_channel_id(profile, user), f'{profile["android_channel_id"]}_no_vibration')
            self.assertEqual(profile, original)

    def test_message_profile_takes_priority_for_driver_conversation(self):
        profile = _push_alert_profile(
            "parcel_message",
            "mission",
            "messages",
        )

        self.assertEqual(profile["android_channel_id"], "denkma_messages_v4")
        self.assertEqual(profile["ios_sound"], "denkma_message.wav")

    def test_mission_profile_is_used_for_available_course(self):
        profile = _push_alert_profile(
            "mission_available",
            "mission",
            "parcel_updates",
        )

        self.assertEqual(profile["android_channel_id"], "denkma_missions_v3")
        self.assertEqual(profile["android_sound"], "denkma_mission")

    def test_client_delivery_steps_use_status_profile(self):
        profile = _push_alert_profile(
            "parcel_detail",
            "parcel",
            "parcel_updates",
            target_view="client", parcel_status="delivered",
        )

        self.assertEqual(profile["android_channel_id"], "denkma_updates_v3")
        self.assertEqual(profile["ios_sound"], "denkma_status.wav")

    def test_long_alerts_are_not_used_for_driver_updates_or_other_roles(self):
        for event in ("mission_detail", "mission_unavailable"):
            profile = _push_alert_profile(event, "mission", "parcel_updates", target_view="driver")
            self.assertEqual(profile["android_channel_id"], "denkma_mission_updates_v1")
        for view in ("driver", "relay_agent", "admin"):
            profile = _push_alert_profile("parcel_detail", "parcel", "parcel_updates", target_view=view, parcel_status="delivered")
            self.assertEqual(profile["android_channel_id"], "denkma_other_alerts_v1")
        profile = _push_alert_profile("wallet", "payout", "parcel_updates", target_view="client")
        self.assertEqual(profile["android_channel_id"], "denkma_other_alerts_v1")
        profile = _push_alert_profile("parcel_detail", "parcel", "parcel_updates", target_view="client")
        self.assertEqual(profile["android_channel_id"], "denkma_other_alerts_v1")
        profile = _push_alert_profile("parcel_detail", "parcel", "parcel_updates", target_view="client", alert_kind="delivery_step")
        self.assertEqual(profile["android_channel_id"], "denkma_updates_v3")


class BackgroundPushVibrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_background_push_uses_preference_without_changing_ios_sound(self):
        for vibration in (False, True):
            with self.subTest(vibration=vibration):
                user = {"fcm_token": "test-token", "notification_prefs": {"android_vibration": vibration}}
                database = SimpleNamespace(
                    users=SimpleNamespace(find_one=AsyncMock(return_value=user), update_one=AsyncMock()),
                    delivery_missions=SimpleNamespace(find_one=AsyncMock(return_value=None)),
                )
                messaging = ModuleType("firebase_admin.messaging")
                for name in ("Message", "Notification", "AndroidConfig", "AndroidNotification", "APNSConfig", "APNSPayload", "Aps"):
                    setattr(messaging, name, lambda **values: SimpleNamespace(**values))
                send = Mock(return_value="test-message")
                messaging.send = send
                firebase = ModuleType("firebase_admin")
                firebase.messaging = messaging
                with patch.object(notification_service, "db", database), \
                     patch.object(notification_service, "_ensure_firebase"), \
                     patch.object(notification_service, "_firebase_initialized", True), \
                     patch.dict(sys.modules, {"firebase_admin": firebase, "firebase_admin.messaging": messaging}):
                    result = await notification_service._send_push(
                        "user", "Nouvelle mission", "Mission disponible", ref_type="mission", event_type="mission_available",
                    )
                self.assertEqual(result["push_status"], "sent")
                message = send.call_args.args[0]
                expected = "denkma_missions_v3" + ("" if vibration else "_no_vibration")
                self.assertEqual(message.android.notification.channel_id, expected)
                self.assertEqual(message.android.notification.sound, "denkma_mission")
                self.assertEqual(message.apns.payload.aps.sound, "denkma_mission.wav")
                self.assertGreater(message.android.ttl.total_seconds(), 0)
                self.assertIn("apns-expiration", message.apns.headers)


if __name__ == "__main__":
    unittest.main()
