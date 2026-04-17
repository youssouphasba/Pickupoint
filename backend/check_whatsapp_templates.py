"""Vérifie l'état des templates WhatsApp Cloud API sur Meta.

Usage (depuis backend/) :
    python check_whatsapp_templates.py

Lit WHATSAPP_PHONE_NUMBER_ID + WHATSAPP_ACCESS_TOKEN depuis .env,
récupère le WABA associé, liste les templates et compare avec les
4 templates attendus par le code : parcel_created, parcel_assigned,
parcel_delivered, gps_confirmation.
"""
import os
import sys
from pathlib import Path

from dotenv import load_dotenv
import httpx

load_dotenv(Path(__file__).parent / ".env")

PHONE_NUMBER_ID = os.environ.get("WHATSAPP_PHONE_NUMBER_ID")
ACCESS_TOKEN = os.environ.get("WHATSAPP_ACCESS_TOKEN")
API_VERSION = os.environ.get("WHATSAPP_API_VERSION", "v21.0")

EXPECTED = {
    "parcel_created":    {"vars": 3, "lang": "fr"},
    "parcel_assigned":   {"vars": 3, "lang": "fr"},
    "parcel_delivered":  {"vars": 2, "lang": "fr"},
    "gps_confirmation":  {"vars": 4, "lang": "fr"},
}


def _fail(msg: str) -> None:
    print(f"❌ {msg}")
    sys.exit(1)


def _ok(msg: str) -> None:
    print(f"✅ {msg}")


def _warn(msg: str) -> None:
    print(f"⚠️  {msg}")


def main() -> None:
    if not PHONE_NUMBER_ID or not ACCESS_TOKEN:
        _fail("WHATSAPP_PHONE_NUMBER_ID ou WHATSAPP_ACCESS_TOKEN manquant dans .env")

    headers = {"Authorization": f"Bearer {ACCESS_TOKEN}"}
    base = f"https://graph.facebook.com/{API_VERSION}"

    # 1. Récupérer le WABA associé au numéro
    r = httpx.get(
        f"{base}/{PHONE_NUMBER_ID}",
        params={"fields": "display_phone_number,verified_name,whatsapp_business_account"},
        headers=headers,
        timeout=10,
    )
    if r.status_code == 401:
        _fail("Token invalide ou expiré (401). Regénère un System User access token.")
    if r.status_code != 200:
        _fail(f"Erreur numéro: {r.status_code} {r.text}")

    data = r.json()
    waba_id = (data.get("whatsapp_business_account") or {}).get("id")
    phone_display = data.get("display_phone_number", "?")
    verified_name = data.get("verified_name", "?")

    print(f"📞 Numéro Meta: {phone_display}  ({verified_name})")
    if not waba_id:
        _fail("WABA id introuvable — permissions du token ?")
    print(f"🏢 WABA ID: {waba_id}\n")

    # 2. Lister les templates
    r = httpx.get(
        f"{base}/{waba_id}/message_templates",
        params={"fields": "name,status,language,components", "limit": 200},
        headers=headers,
        timeout=10,
    )
    if r.status_code != 200:
        _fail(f"Erreur templates: {r.status_code} {r.text}")

    templates = r.json().get("data", [])
    by_name: dict[str, list[dict]] = {}
    for t in templates:
        by_name.setdefault(t["name"], []).append(t)

    print(f"Templates trouvés sur Meta: {len(templates)}")
    print("─" * 60)

    all_ok = True
    for name, expected in EXPECTED.items():
        variants = by_name.get(name, [])
        fr_variant = next((v for v in variants if v.get("language") == expected["lang"]), None)

        if not fr_variant:
            _warn(f"{name} — ABSENT (langue {expected['lang']} attendue)")
            all_ok = False
            continue

        status = fr_variant.get("status")
        body = next(
            (c for c in fr_variant.get("components", []) if c.get("type") == "BODY"),
            {},
        )
        body_text = body.get("text", "")
        var_count = body_text.count("{{")

        line = f"{name} [{fr_variant['language']}] status={status} vars={var_count}"
        if status != "APPROVED":
            _warn(f"{line} — pas APPROVED")
            all_ok = False
        elif var_count != expected["vars"]:
            _warn(f"{line} — attendu {expected['vars']} variables")
            all_ok = False
        else:
            _ok(line)

    print("─" * 60)
    extras = set(by_name) - set(EXPECTED)
    if extras:
        print(f"Autres templates (non utilisés par le code): {', '.join(sorted(extras))}")

    if all_ok:
        print("\n🎉 Les 4 templates attendus sont APPROVED et bien paramétrés.")
        sys.exit(0)
    else:
        print("\n❌ Au moins un template n'est pas conforme — voir ci-dessus.")
        sys.exit(2)


if __name__ == "__main__":
    main()
