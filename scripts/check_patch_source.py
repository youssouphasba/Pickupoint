import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


PROTECTED_PATHS = (
    "mobile/android", "mobile/ios", "mobile/macos", "mobile/windows", "mobile/linux",
    "mobile/pubspec.lock", "mobile/shorebird.yaml", "mobile/assets",
)


def version_of(text):
    match = re.search(r"^version:\s*(\S+)\s*$", text, re.MULTILINE)
    return match.group(1) if match else None


def configuration_without_version(text):
    return re.sub(r"^version:.*\n?", "", text.replace("\r\n", "\n"), flags=re.MULTILINE)


def compatibility_errors(current, baseline, target, changed_paths):
    errors = []
    if not re.fullmatch(r"\d+\.\d+\.\d+\+\d+", target):
        errors.append("Use an explicit Shorebird release version, never latest.")
    if version_of(current) != target or version_of(baseline) != target:
        errors.append("The pubspec and baseline versions must match the targeted release.")
    if configuration_without_version(current) != configuration_without_version(baseline):
        errors.append("The pubspec configuration, dependencies and declared assets differ from the baseline.")
    if changed_paths:
        errors.append("Native files, dependencies or packaged assets changed: " + ", ".join(changed_paths))
    return errors


def git(root, *args):
    return subprocess.run(["git", *args], cwd=root, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8").stdout


def locked_packages(text):
    packages = {}
    for match in re.finditer(r"^  ([a-zA-Z0-9_]+):\r?\n((?:[ ]{4}[^\n]*\n?)*)", text, re.MULTILINE):
        version = re.search(r'^    version: "([^"\r\n]+)"', match[2], re.MULTILINE)
        checksum = re.search(r'^      sha256: ([^\r\n]+)', match[2], re.MULTILINE)
        packages[match[1]] = (version[1] if version else None, checksum[1] if checksum else None)
    return packages


def changed_native_plugins(baseline, current, metadata):
    before, after = locked_packages(baseline), locked_packages(current)
    names = {plugin["name"] for platform in ("android", "ios")
        for plugin in metadata.get("plugins", {}).get(platform, [])}
    return sorted(name for name in names if name not in before or before[name] != after.get(name))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-version", required=True)
    parser.add_argument("--base-ref", required=True)
    parser.add_argument("--fetch-base", action="store_true")
    parser.add_argument("--resolved-plugins", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-fA-F0-9]{40}", args.base_ref):
        parser.error("The baseline must be an exact Git commit SHA.")
    root = Path(__file__).resolve().parents[1]
    try:
        try:
            git(root, "cat-file", "-e", f"{args.base_ref}^{{commit}}")
        except subprocess.CalledProcessError:
            if not args.fetch_base:
                raise
            git(root, "fetch", "--depth=1", "origin", args.base_ref)
        baseline = git(root, "show", f"{args.base_ref}:mobile/pubspec.yaml")
        current = (root / "mobile/pubspec.yaml").read_text(encoding="utf-8")
        if args.resolved_plugins:
            metadata = json.loads((root / "mobile/.flutter-plugins-dependencies").read_text(encoding="utf-8"))
            if not isinstance(metadata.get("plugins"), dict):
                raise ValueError("Missing resolved plugin metadata. Run flutter pub get first.")
            changed = changed_native_plugins(
                git(root, "show", f"{args.base_ref}:mobile/pubspec.lock"),
                (root / "mobile/pubspec.lock").read_text(encoding="utf-8"), metadata,
            )
        else:
            changed = git(root, "diff", "--name-only", args.base_ref, "--", *PROTECTED_PATHS).splitlines()
            changed += git(root, "ls-files", "--others", "--exclude-standard", "--", *PROTECTED_PATHS).splitlines()
        errors = compatibility_errors(current, baseline, args.release_version, changed)
        if errors:
            raise ValueError("\n".join(errors))
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f"Patch source check failed: {error}", file=sys.stderr)
        return 1
    scope = "resolved native plugins unchanged" if args.resolved_plugins else "no native, dependency or asset changes"
    print(f"Patch source verified for {args.release_version}: {scope}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
