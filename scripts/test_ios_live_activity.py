import io
import plistlib
import re
import unittest
from pathlib import Path
import zipfile

from scripts.verify_ios_live_activity import verify_ipa


class IosLiveActivityTests(unittest.TestCase):
    app_id = "com.example.app"
    extension_id = "com.example.app.LiveActivity"
    app_path = "Payload/Example.app"
    extension_path = app_path + "/PlugIns/LiveActivity.appex"

    def artifact(self, app_changes=None, extension_changes=None, embed=True, executable=True):
        app = {
            "CFBundleIdentifier": self.app_id,
            "NSSupportsLiveActivities": True,
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
        }
        extension = {
            "CFBundleIdentifier": self.extension_id,
            "CFBundleExecutable": "LiveActivity",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "MinimumOSVersion": "16.1",
            "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"},
        }
        app.update(app_changes or {})
        extension.update(extension_changes or {})
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr(self.app_path + "/Info.plist", plistlib.dumps(app, fmt=plistlib.FMT_BINARY))
            if embed:
                archive.writestr(self.extension_path + "/Info.plist", plistlib.dumps(extension, fmt=plistlib.FMT_BINARY))
                if executable:
                    archive.writestr(self.extension_path + "/LiveActivity", b"test executable")
        buffer.seek(0)
        return buffer

    def verify(self, **kwargs):
        return verify_ipa(self.artifact(**kwargs), self.app_id, self.extension_id)

    def test_complete_export_passes(self):
        self.assertEqual(self.verify(), self.extension_path)

    def test_missing_extension_fails(self):
        with self.assertRaisesRegex(ValueError, "missing"):
            self.verify(embed=False)

    def test_missing_executable_fails(self):
        with self.assertRaisesRegex(ValueError, "executable is missing"):
            self.verify(executable=False)

    def test_disabled_application_support_fails(self):
        with self.assertRaisesRegex(ValueError, "NSSupportsLiveActivities"):
            self.verify(app_changes={"NSSupportsLiveActivities": False})

    def test_wrong_bundle_identifier_fails(self):
        with self.assertRaisesRegex(ValueError, "bundle identifier"):
            self.verify(app_changes={"CFBundleIdentifier": "other.app"})
        with self.assertRaisesRegex(ValueError, "missing"):
            self.verify(extension_changes={"CFBundleIdentifier": "other.extension"})

    def test_mismatched_versions_fail(self):
        for key in ("CFBundleVersion", "CFBundleShortVersionString"):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, key):
                self.verify(extension_changes={key: "999"})

    def test_invalid_extension_configuration_fails(self):
        with self.assertRaisesRegex(ValueError, "WidgetKit"):
            self.verify(extension_changes={"NSExtension": {}})
        with self.assertRaisesRegex(ValueError, "minimum iOS"):
            self.verify(extension_changes={"MinimumOSVersion": "invalid"})
        with self.assertRaisesRegex(ValueError, "iOS 16.1"):
            self.verify(extension_changes={"MinimumOSVersion": "15.0"})

    def test_swift_app_and_widget_share_the_same_attributes_contract(self):
        root = Path(__file__).resolve().parents[1] / "mobile" / "ios"
        pattern = r"struct DenkmaMissionAttributes: ActivityAttributes \{.*?\n\}"
        bridge = (root / "Runner" / "DenkmaLiveActivityBridge.swift").read_text(encoding="utf-8")
        widget = (root / "DenkmaLiveActivity" / "DenkmaLiveActivity.swift").read_text(encoding="utf-8")
        self.assertEqual(re.search(pattern, bridge, re.S).group(), re.search(pattern, widget, re.S).group())
        self.assertIn("timerInterval:", widget)
        self.assertIn("countsDown: true", widget)


if __name__ == "__main__":
    unittest.main()
