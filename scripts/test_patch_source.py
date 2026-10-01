import unittest

from scripts.check_patch_source import compatibility_errors, changed_native_plugins


class PatchSourceTests(unittest.TestCase):
    def setUp(self):
        self.pubspec = "name: synthetic\nversion: 1.0.27+47\ndependencies:\n  flutter:\n    sdk: flutter\n"

    def check(self, current=None, target="1.0.27+47", paths=()):
        return compatibility_errors(current or self.pubspec, self.pubspec, target, paths)

    def test_matching_source_is_allowed(self):
        self.assertEqual(self.check(), [])
        self.assertEqual(self.check(current=self.pubspec.replace("\n", "\r\n")), [])

    def test_latest_checks_current_pubspec_against_baseline(self):
        self.assertEqual(self.check(target="latest"), [])
        self.assertTrue(self.check(target="latest",
            current=self.pubspec.replace("1.0.27+47", "1.0.28+48")))

    def test_wrong_release_is_rejected(self):
        self.assertTrue(self.check(target="1.0.28+48"))

    def test_native_code_is_rejected(self):
        for path in ("mobile/android/app/src/main/MainActivity.kt", "mobile/ios/Runner/AppDelegate.swift"):
            self.assertTrue(self.check(paths=[path]))

    def test_lockfile_and_assets_are_rejected(self):
        for path in ("mobile/pubspec.lock", "mobile/assets/logo.png", "mobile/shorebird.yaml"):
            self.assertTrue(self.check(paths=[path]))

    def test_dependency_and_asset_declarations_are_rejected(self):
        for suffix in ("  pdf: ^3.0.0\n", "flutter:\n  assets:\n    - new.png\n"):
            self.assertTrue(self.check(current=self.pubspec + suffix))

    def test_version_bump_is_rejected(self):
        self.assertTrue(self.check(current=self.pubspec.replace("1.0.27+47", "1.0.28+48")))

    def test_sdk_test_package_update_does_not_change_native_plugins(self):
        lock = 'packages:\n  native_plugin:\n    description:\n      sha256: checksum\n    version: "1.0.0"\n  test_api:\n    version: "0.7.7"\n'
        metadata = {"plugins": {"android": [{"name": "native_plugin"}], "ios": []}}
        self.assertEqual(changed_native_plugins(lock, lock.replace("0.7.7", "0.7.12"), metadata), [])
        self.assertEqual(changed_native_plugins(lock, lock.replace("1.0.0", "2.0.0"), metadata), ["native_plugin"])
        self.assertEqual(changed_native_plugins(lock, lock.replace("checksum", "different"), metadata), ["native_plugin"])

    def test_new_resolved_native_plugin_is_rejected(self):
        metadata = {"plugins": {"android": [], "ios": [{"name": "new_plugin"}]}}
        self.assertEqual(changed_native_plugins("packages:\n", "packages:\n", metadata), ["new_plugin"])


if __name__ == "__main__":
    unittest.main()
