import argparse
import plistlib
from pathlib import Path, PurePosixPath
import zipfile


def verify_ipa(path, bundle_id, extension_bundle_id):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        app_plists = [
            name for name in names
            if name.startswith("Payload/") and name.endswith(".app/Info.plist")
            and len(PurePosixPath(name).parts) == 3
        ]
        if len(app_plists) != 1:
            raise ValueError("The IPA must contain exactly one application.")
        app_path = PurePosixPath(app_plists[0]).parent
        app = plistlib.loads(archive.read(app_plists[0]))
        if app.get("CFBundleIdentifier") != bundle_id:
            raise ValueError("Unexpected application bundle identifier.")
        if app.get("NSSupportsLiveActivities") is not True:
            raise ValueError("NSSupportsLiveActivities is missing from the application.")
        extensions = []
        for name in names:
            path_in_zip = PurePosixPath(name)
            if (
                path_in_zip.name == "Info.plist"
                and path_in_zip.parent.suffix == ".appex"
                and path_in_zip.parent.parent == app_path / "PlugIns"
            ):
                info = plistlib.loads(archive.read(name))
                if info.get("CFBundleIdentifier") == extension_bundle_id:
                    extensions.append((path_in_zip.parent, info))
        if len(extensions) != 1:
            raise ValueError("The signed Live Activity extension is missing or duplicated.")
        extension_path, extension = extensions[0]
        if extension.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
            raise ValueError("The Live Activity extension is not a WidgetKit extension.")
        executable = extension.get("CFBundleExecutable", "")
        if not isinstance(executable, str) or not executable or PurePosixPath(executable).name != executable:
            raise ValueError("The Live Activity executable name is invalid.")
        executable_path = str(extension_path / executable)
        if executable_path not in names or archive.getinfo(executable_path).file_size == 0:
            raise ValueError("The Live Activity executable is missing or empty.")
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            if not app.get(key) or extension.get(key) != app[key]:
                raise ValueError(f"The application and Live Activity extension disagree on {key}.")
        try:
            minimum = tuple(int(part) for part in extension["MinimumOSVersion"].split("."))
        except (KeyError, AttributeError, ValueError):
            raise ValueError("The Live Activity minimum iOS version is invalid.") from None
        if minimum < (16, 1):
            raise ValueError("The Live Activity extension must target iOS 16.1 or later.")
        return str(extension_path)


def main():
    parser = argparse.ArgumentParser(description="Verify the Live Activity embedded in the exported iOS IPA.")
    parser.add_argument("--ipa-dir", type=Path, required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--extension-bundle-id", required=True)
    args = parser.parse_args()
    artifacts = sorted(args.ipa_dir.glob("*.ipa"))
    if not artifacts:
        parser.error(f"No IPA found in {args.ipa_dir}")
    for artifact in artifacts:
        try:
            extension = verify_ipa(artifact, args.bundle_id, args.extension_bundle_id)
        except (ValueError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
            parser.exit(1, f"Live Activity verification failed: {error}\n")
        print(f"Live Activity verified: {artifact.name} -> {extension}")


if __name__ == "__main__":
    main()
