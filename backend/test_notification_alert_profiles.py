import unittest

from services.notification_service import _push_alert_profile


class PushAlertProfileTests(unittest.TestCase):
    def test_message_profile_takes_priority_for_driver_conversation(self):
        profile = _push_alert_profile(
            "parcel_message",
            "mission",
            "messages",
        )

        self.assertEqual(profile["android_channel_id"], "denkma_messages_v2")
        self.assertEqual(profile["ios_sound"], "denkma_message.wav")

    def test_mission_profile_is_used_for_available_course(self):
        profile = _push_alert_profile(
            "mission_available",
            "mission",
            "parcel_updates",
        )

        self.assertEqual(profile["android_channel_id"], "denkma_missions_v2")
        self.assertEqual(profile["android_sound"], "denkma_mission")

    def test_status_profile_is_the_default(self):
        profile = _push_alert_profile(
            "parcel_detail",
            "parcel",
            "parcel_updates",
        )

        self.assertEqual(profile["android_channel_id"], "denkma_updates_v2")
        self.assertEqual(profile["ios_sound"], "denkma_status.wav")


if __name__ == "__main__":
    unittest.main()
