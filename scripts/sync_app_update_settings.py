#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any
from urllib import error, request


FALSE_VALUES = {"0", "false", "no", "off", ""}


def _env_flag(name: str, default: bool = True) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() not in FALSE_VALUES


def _warn_only_on_failure() -> bool:
    return not _env_flag("APP_UPDATE_SYNC_REQUIRED", default=False)


def _normalize_base_url(raw_base_url: str) -> str:
    base_url = raw_base_url.strip().rstrip("/")
    if not base_url:
        raise ValueError("APP_UPDATE_ADMIN_BASE_URL est vide")
    if base_url.endswith("/api"):
        return base_url
    return f"{base_url}/api"


def _read_version_from_pubspec(pubspec_path: Path) -> str:
    content = pubspec_path.read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([^\s]+)\s*$", content, flags=re.MULTILINE)
    if not match:
        raise ValueError(f"Impossible de lire la version dans {pubspec_path}")
    return match.group(1).strip()


def _normalize_version(version: str) -> str:
    return version.split("+", 1)[0].strip()


def _json_request(method: str, url: str, payload: dict[str, Any] | None = None, token: str | None = None) -> dict[str, Any]:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = request.Request(url, data=data, headers=headers, method=method)
    try:
        with request.urlopen(req, timeout=30) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {url} a échoué ({exc.code}): {body}") from exc
    except error.URLError as exc:
        raise RuntimeError(f"Impossible de joindre {url}: {exc}") from exc


def _get_admin_token(api_base_url: str) -> str:
    explicit_token = (os.getenv("APP_UPDATE_ADMIN_TOKEN") or "").strip()
    if explicit_token:
        return explicit_token

    email = (os.getenv("APP_UPDATE_ADMIN_EMAIL") or "").strip()
    password = os.getenv("APP_UPDATE_ADMIN_PASSWORD") or ""
    if not email or not password:
        raise RuntimeError(
            "APP_UPDATE_ADMIN_TOKEN ou le couple APP_UPDATE_ADMIN_EMAIL / APP_UPDATE_ADMIN_PASSWORD est requis"
        )

    response = _json_request(
        "POST",
        f"{api_base_url}/admin/auth/login",
        payload={"email": email, "password": password},
    )
    token = str(response.get("token") or "").strip()
    if not token:
        raise RuntimeError("Le login admin a réussi sans retourner de token")
    return token


def main() -> int:
    parser = argparse.ArgumentParser(description="Synchronise la version mobile publiée vers les réglages d'app update.")
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    parser.add_argument("--pubspec", default="mobile/pubspec.yaml")
    parser.add_argument("--version", default="")
    args = parser.parse_args()

    if not _env_flag("APP_UPDATE_SYNC_ENABLED", default=True):
        print("App update sync désactivée via APP_UPDATE_SYNC_ENABLED.")
        return 0

    base_url = (os.getenv("APP_UPDATE_ADMIN_BASE_URL") or "").strip()
    if not base_url:
        print("APP_UPDATE_ADMIN_BASE_URL absent, synchro ignorée.")
        return 0

    resolved_version = args.version.strip() or _read_version_from_pubspec(Path(args.pubspec))
    normalized_version = _normalize_version(resolved_version)
    if not normalized_version:
        raise RuntimeError("Version cible vide après normalisation")

    api_base_url = _normalize_base_url(base_url)
    token = _get_admin_token(api_base_url)
    settings_response = _json_request("GET", f"{api_base_url}/admin/settings", token=token)
    app_update = dict(settings_response.get("app_update") or {})

    payload = {
        "enabled": bool(app_update.get("enabled", True)),
        "message": str(app_update.get("message") or "Une nouvelle version de Denkma est disponible.").strip(),
        "android_latest_version": str(app_update.get("android_latest_version") or "").strip(),
        "android_min_version": str(app_update.get("android_min_version") or "").strip(),
        "android_store_url": str(app_update.get("android_store_url") or "").strip(),
        "ios_latest_version": str(app_update.get("ios_latest_version") or "").strip(),
        "ios_min_version": str(app_update.get("ios_min_version") or "").strip(),
        "ios_store_url": str(app_update.get("ios_store_url") or "").strip(),
    }

    latest_key = f"{args.platform}_latest_version"
    payload[latest_key] = normalized_version

    store_url_env = f"APP_UPDATE_{args.platform.upper()}_STORE_URL"
    store_url = (os.getenv(store_url_env) or "").strip()
    if store_url:
        payload[f"{args.platform}_store_url"] = store_url

    if payload == {
        "enabled": bool(app_update.get("enabled", True)),
        "message": str(app_update.get("message") or "Une nouvelle version de Denkma est disponible.").strip(),
        "android_latest_version": str(app_update.get("android_latest_version") or "").strip(),
        "android_min_version": str(app_update.get("android_min_version") or "").strip(),
        "android_store_url": str(app_update.get("android_store_url") or "").strip(),
        "ios_latest_version": str(app_update.get("ios_latest_version") or "").strip(),
        "ios_min_version": str(app_update.get("ios_min_version") or "").strip(),
        "ios_store_url": str(app_update.get("ios_store_url") or "").strip(),
    }:
        print(f"Aucune mise à jour nécessaire pour {args.platform}: {normalized_version}")
        return 0

    _json_request(
        "PUT",
        f"{api_base_url}/admin/settings/app-update",
        payload=payload,
        token=token,
    )
    print(f"Version {args.platform} synchronisée: {normalized_version}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        if _warn_only_on_failure():
            print(f"AVERTISSEMENT: synchro app update ignorée: {exc}", file=sys.stderr)
            raise SystemExit(0)
        print(f"ERREUR: {exc}", file=sys.stderr)
        raise
