import unittest

from pydantic import ValidationError
from services.sending_guide import SendingGuideSettings, sending_guide_payload


class SendingGuideTests(unittest.TestCase):
    def test_no_video_by_default(self):
        self.assertEqual(sending_guide_payload({})["sending_guide"]["video_url"], "")

    def test_valid_https_and_removal(self):
        config = SendingGuideSettings(video_url=" https://example.com/video.mp4 ")
        self.assertEqual(config.video_url, "https://example.com/video.mp4")
        self.assertEqual(SendingGuideSettings(video_url=" ").video_url, "")

    def test_invalid_links_rejected(self):
        for url in ["http://example.com/video.mp4", "https://", "https://user:password@example.com/video.mp4", "file:///video.mp4"]:
            with self.subTest(url=url), self.assertRaises(ValidationError):
                SendingGuideSettings(video_url=url)

    def test_same_payload_for_admin_and_client(self):
        config = SendingGuideSettings(video_url="https://example.com/video.mp4").model_dump()
        self.assertEqual(sending_guide_payload({"sending_guide": config}), {"sending_guide": config})
