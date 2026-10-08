import plistlib
from pathlib import Path
import re
import unittest


class IosDriverLocationIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parents[1]
        cls.ios = cls.root / "mobile" / "ios"
        cls.bridge = (cls.ios / "Runner" / "DriverLocationPermissionBridge.swift").read_text(encoding="utf-8")
        cls.delegate = (cls.ios / "Runner" / "AppDelegate.swift").read_text(encoding="utf-8")
        cls.project = (cls.ios / "Runner.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        cls.dart = (cls.root / "mobile" / "lib" / "core" / "location" / "driver_always_location_permission.dart").read_text(encoding="utf-8")

    def test_flutter_and_native_use_the_same_channel_and_method(self):
        native_channel = re.search(r'channelName = "([^"]+)"', self.bridge).group(1)
        dart_channel = re.search(r"MethodChannel\('([^']+)'\)", self.dart).group(1)
        self.assertEqual(native_channel, dart_channel)
        self.assertIn('call.method == "requestAlwaysAuthorization"', self.bridge)
        self.assertIn("invokeMethod<bool>('requestAlwaysAuthorization')", self.dart)

    def test_bridge_is_registered_independently_of_the_root_controller(self):
        self.assertIn('registrar(forPlugin: "DenkmaDriverLocationPermission")', self.delegate)
        self.assertIn("DriverLocationPermissionBridge.register(with: registrar.messenger())", self.delegate)

    def test_bridge_is_compiled_into_the_runner_target(self):
        reference = re.search(
            r"([A-F0-9]{24}) /\* DriverLocationPermissionBridge.swift \*/ = \{isa = PBXFileReference;",
            self.project,
        ).group(1)
        build = re.search(
            rf"([A-F0-9]{{24}}) /\* DriverLocationPermissionBridge.swift in Sources \*/ = "
            rf"\{{isa = PBXBuildFile; fileRef = {reference}", self.project,
        ).group(1)
        source_phase = re.search(
            r"97C146EA1CF9000F007C117D /\* Sources \*/ = \{.*?\n\t\t\};",
            self.project, re.S,
        ).group()
        self.assertIn(build, source_phase)
        runner_group = re.search(
            r"97C146F01CF9000F007C117D /\* Runner \*/ = \{.*?\n\t\t\};",
            self.project, re.S,
        ).group()
        self.assertIn(reference, runner_group)

    def test_iphone_has_both_descriptions_and_the_background_capability(self):
        with (self.ios / "Runner" / "Info.plist").open("rb") as source:
            info = plistlib.load(source)
        for key in ("NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"):
            self.assertTrue(info.get(key, "").strip())
        self.assertIn("location", info.get("UIBackgroundModes", []))
        description = info["NSLocationAlwaysAndWhenInUseUsageDescription"]
        self.assertIn("livreurs disponibles ou en livraison", description)
        self.assertNotIn("application est fermée", description)

    def test_only_driver_consent_calls_the_upgrade(self):
        callers = [
            path.relative_to(self.root / "mobile" / "lib").as_posix()
            for path in (self.root / "mobile" / "lib").rglob("*.dart")
            if "DriverAlwaysLocationPermission.requestUpgrade()" in path.read_text(encoding="utf-8")
        ]
        self.assertEqual(callers, ["core/location/driver_location_consent.dart"])
        self.assertIn("defaultTargetPlatform != TargetPlatform.iOS", self.dart)
        self.assertIn("permission != LocationPermission.whileInUse", self.dart)
        self.assertNotIn("requestWhenInUseAuthorization()", self.bridge)

    def test_local_prompt_preference_has_its_required_privacy_reason(self):
        with (self.ios / "Runner" / "PrivacyInfo.xcprivacy").open("rb") as source:
            manifest = plistlib.load(source)
        defaults = [
            entry for entry in manifest["NSPrivacyAccessedAPITypes"]
            if entry["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryUserDefaults"
        ]
        self.assertEqual(len(defaults), 1)
        self.assertEqual(defaults[0]["NSPrivacyAccessedAPITypeReasons"], ["CA92.1"])
        self.assertNotIn("NSPrivacyCollectedDataTypes", manifest)
        resource_phase = re.search(
            r"97C146EC1CF9000F007C117D /\* Resources \*/ = \{.*?\n\t\t\};",
            self.project, re.S,
        ).group()
        self.assertIn("PrivacyInfo.xcprivacy in Resources", resource_phase)


if __name__ == "__main__":
    unittest.main()
