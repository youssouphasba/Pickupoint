"""
Script de soumission des templates WhatsApp v4 (avec nom + adresse relais).

Usage (depuis backend/) :
    python3 scripts/submit_whatsapp_templates.py

Suit exactement le style des v3 approuvés (body court, "Denkma" mentionné,
pas de boutons URL, "Merci d'utiliser Denkma." en footer textuel) avec en
plus le nom et l'adresse du point relais.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def _load_env(path: str) -> dict[str, str]:
    data: dict[str, str] = {}
    if not os.path.exists(path):
        return data
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            data[key.strip()] = value.strip().strip('"').strip("'")
    return data


HERE = os.path.dirname(os.path.abspath(__file__))
ENV = _load_env(os.path.join(HERE, "..", ".env"))

WABA_ID = os.getenv("WHATSAPP_BUSINESS_ACCOUNT_ID") or ENV.get("WHATSAPP_BUSINESS_ACCOUNT_ID")
ACCESS_TOKEN = os.getenv("WHATSAPP_ACCESS_TOKEN") or ENV.get("WHATSAPP_ACCESS_TOKEN")
API_VERSION = os.getenv("WHATSAPP_API_VERSION") or ENV.get("WHATSAPP_API_VERSION") or "v21.0"

if not WABA_ID or not ACCESS_TOKEN:
    print("ERREUR : credentials manquants dans backend/.env")
    sys.exit(1)

URL = f"https://graph.facebook.com/{API_VERSION}/{WABA_ID}/message_templates"


TEMPLATES = [
    {
        "name": "parcel_relay_ready_v4",
        "language": "fr",
        "category": "UTILITY",
        "components": [
            {
                "type": "BODY",
                "text": (
                    "Bonjour {{1}}, votre colis Denkma {{2}} est disponible au point relais {{3}} ({{4}}).\n\n"
                    "Référence de retrait : {{5}}\n"
                    "Suivi du colis : {{6}}\n\n"
                    "Merci d'utiliser Denkma."
                ),
                "example": {
                    "body_text": [
                        [
                            "Anta",
                            "PKP-LIV-1234",
                            "Boutique Touba Pikine",
                            "Quartier 5, Pikine",
                            "482913",
                            "https://api.denkma.com/api/tracking/view/PKP-LIV-1234",
                        ]
                    ]
                },
            }
        ],
    },
    {
        "name": "parcel_relay_redirected_v4",
        "language": "fr",
        "category": "UTILITY",
        "components": [
            {
                "type": "BODY",
                "text": (
                    "Bonjour {{1}}, votre colis Denkma {{2}} a été redirigé vers le point relais {{3}} ({{4}}).\n\n"
                    "Référence de retrait : {{5}}\n"
                    "Suivi du colis : {{6}}\n\n"
                    "Merci d'utiliser Denkma."
                ),
                "example": {
                    "body_text": [
                        [
                            "Anta",
                            "PKP-LIV-1234",
                            "Boutique Touba Pikine",
                            "Quartier 5, Pikine",
                            "482913",
                            "https://api.denkma.com/api/tracking/view/PKP-LIV-1234",
                        ]
                    ]
                },
            }
        ],
    },
    {
        "name": "parcel_created_recipient_relay_v4",
        "language": "fr",
        "category": "UTILITY",
        "components": [
            {
                "type": "BODY",
                "text": (
                    "Bonjour {{1}}, {{2}} vous a envoyé un colis Denkma à retirer au point relais {{3}} ({{4}}).\n\n"
                    "Référence du colis : {{5}}\n"
                    "Référence de retrait : {{6}}\n"
                    "Suivi du colis : {{7}}\n\n"
                    "Merci d'utiliser Denkma."
                ),
                "example": {
                    "body_text": [
                        [
                            "Anta",
                            "Moussa Diop",
                            "Boutique Touba Pikine",
                            "Quartier 5, Pikine",
                            "PKP-LIV-1234",
                            "482913",
                            "https://api.denkma.com/api/tracking/view/PKP-LIV-1234",
                        ]
                    ]
                },
            }
        ],
    },
]


def submit(template: dict) -> tuple[bool, str]:
    payload = json.dumps(template).encode("utf-8")
    req = urllib.request.Request(
        URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {ACCESS_TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            data = json.loads(body) if body else {}
            tid = data.get("id", "?")
            status = data.get("status", "?")
            return True, f"id={tid} status={status}"
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8")
        try:
            err = json.loads(body).get("error", {})
            msg = err.get("message") or body
            sub = err.get("error_user_msg") or err.get("error_user_title") or ""
            return False, f"{msg} | sub={sub}"
        except Exception:
            return False, body
    except Exception as exc:
        return False, str(exc)


def main() -> int:
    print(f"Soumission templates v4 sur WABA {WABA_ID}\n")
    failed = 0
    for tpl in TEMPLATES:
        ok, info = submit(tpl)
        marker = "OK" if ok else "FAIL"
        print(f"[{marker}] {tpl['name']}: {info}")
        if not ok:
            failed += 1
    print()
    if failed:
        return 1
    print("Templates soumis. Quand approuvés, sur Railway :")
    print("  WHATSAPP_TEMPLATE_RELAY_READY=parcel_relay_ready_v4")
    print("  WHATSAPP_TEMPLATE_RECIPIENT_CREATED_RELAY=parcel_created_recipient_relay_v4")
    print("  WHATSAPP_TEMPLATE_RELAY_REDIRECTED=parcel_relay_redirected_v4")
    return 0


if __name__ == "__main__":
    sys.exit(main())
