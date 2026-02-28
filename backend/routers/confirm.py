"""
Router confirmation d'adresse — système bidirectionnel GPS.
Liens envoyés par SMS/WhatsApp à l'expéditeur ou au destinataire.
Aucune authentification requise — token signé suffit.
"""
import secrets
from datetime import datetime, timezone

from fastapi import APIRouter
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from typing import Optional

from core.exceptions import not_found_exception, bad_request_exception
from database import db
from services.otp_service import _send_via_twilio

router = APIRouter()


class LocationPayload(BaseModel):
    lat:       float
    lng:       float
    accuracy:  Optional[float] = None
    voice_note: Optional[str]  = None  # base64 ou URL enregistrement vocal


def _html_page(token: str, role: str, recipient_name: str = "") -> str:
    """Page HTML minimaliste — 1 grand bouton, aucun texte obligatoire à lire."""
    role_label = "livraison" if role == "recipient" else "enlèvement"
    greeting   = f"Bonjour {recipient_name} ! " if recipient_name else ""
    return f"""<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <title>PickuPoint — Confirmer ma position</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: sans-serif;
      background: #F5F5F5;
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      min-height: 100vh; padding: 24px;
      text-align: center;
    }}
    .logo {{ font-size: 48px; margin-bottom: 16px; }}
    h1 {{ font-size: 20px; color: #212121; margin-bottom: 8px; }}
    p  {{ font-size: 15px; color: #757575; margin-bottom: 40px; line-height: 1.5; }}
    .btn {{
      width: 100%; max-width: 360px;
      padding: 20px;
      background: #1A73E8; color: white;
      border: none; border-radius: 16px;
      font-size: 20px; font-weight: bold;
      cursor: pointer; margin-bottom: 16px;
      box-shadow: 0 4px 12px rgba(26,115,232,0.4);
    }}
    .btn:active {{ background: #1557B0; transform: scale(0.98); }}
    .btn-voice {{
      background: #FF6B00;
      box-shadow: 0 4px 12px rgba(255,107,0,0.4);
    }}
    .success {{
      display: none;
      background: #E8F5E9; border-radius: 16px;
      padding: 24px; width: 100%; max-width: 360px;
    }}
    .success h2 {{ color: #2E7D32; font-size: 22px; margin-bottom: 8px; }}
    #voice-section {{ display: none; margin-top: 24px; width: 100%; max-width: 360px; }}
    #voice-status  {{ font-size: 14px; color: #757575; margin-top: 8px; }}
  </style>
</head>
<body>
  <div class="logo">📦</div>
  <h1>{greeting}Votre colis PickuPoint</h1>
  <p>Appuyez sur le bouton pour indiquer<br>votre position de <strong>{role_label}</strong></p>

  <button class="btn" id="btn-locate" onclick="getLocation()">
    📍 Confirmer ma position
  </button>

  <div id="voice-section">
    <button class="btn btn-voice" id="btn-voice" onclick="toggleRecording()">
      🎤 Laisser un message vocal au livreur
    </button>
    <div id="voice-status"></div>
  </div>

  <div class="success" id="success">
    <h2>✅ Position confirmée !</h2>
    <p>Votre livreur vous trouvera.<br>Merci !</p>
  </div>

  <script>
    const TOKEN = "{token}";
    let mediaRecorder, audioChunks = [], isRecording = false, voiceBase64 = null;

    async function getLocation() {{
      const btn = document.getElementById('btn-locate');
      btn.textContent = "⏳ Localisation...";
      btn.disabled = true;
      try {{
        const pos = await new Promise((res, rej) =>
          navigator.geolocation.getCurrentPosition(res, rej, {{
            enableHighAccuracy: true, timeout: 10000
          }})
        );
        await sendLocation(pos.coords.latitude, pos.coords.longitude, pos.coords.accuracy);
        btn.style.display = 'none';
        document.getElementById('voice-section').style.display = 'block';
      }} catch(e) {{
        btn.textContent = "📍 Confirmer ma position";
        btn.disabled = false;
        alert("Impossible d'accéder au GPS. Vérifiez les permissions.");
      }}
    }}

    async function sendLocation(lat, lng, accuracy) {{
      await fetch('/confirm/' + TOKEN + '/locate', {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify({{ lat, lng, accuracy, voice_note: voiceBase64 }})
      }});
    }}

    async function toggleRecording() {{
      const btn  = document.getElementById('btn-voice');
      const stat = document.getElementById('voice-status');
      if (!isRecording) {{
        const stream = await navigator.mediaDevices.getUserMedia({{ audio: true }});
        mediaRecorder = new MediaRecorder(stream);
        audioChunks = [];
        mediaRecorder.ondataavailable = e => audioChunks.push(e.data);
        mediaRecorder.onstop = async () => {{
          const blob   = new Blob(audioChunks, {{ type: 'audio/webm' }});
          const reader = new FileReader();
          reader.onloadend = async () => {{
            voiceBase64 = reader.result;
            await fetch('/confirm/' + TOKEN + '/voice', {{
              method: 'POST',
              headers: {{'Content-Type': 'application/json'}},
              body: JSON.stringify({{ voice_note: voiceBase64 }})
            }});
            document.getElementById('success').style.display = 'block';
            btn.style.display = 'none';
            stat.textContent = "✅ Message envoyé au livreur";
          }};
          reader.readAsDataURL(blob);
        }};
        mediaRecorder.start();
        isRecording = true;
        btn.textContent = "⏹️ Arrêter l'enregistrement";
        stat.textContent = "🔴 Enregistrement en cours...";
      }} else {{
        mediaRecorder.stop();
        isRecording = false;
        document.getElementById('success').style.display = 'block';
        btn.style.display = 'none';
      }}
    }}
  </script>
</body>
</html>"""


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.get("/{token}", response_class=HTMLResponse, include_in_schema=False)
async def confirmation_page(token: str):
    """Sert la page HTML de confirmation au destinataire ou à l'expéditeur."""
    parcel = await db.parcels.find_one({
        "$or": [
            {"recipient_confirm_token": token},
            {"sender_confirm_token": token},
        ]
    })
    if not parcel:
        return HTMLResponse("<h2>Lien invalide ou expiré.</h2>", status_code=404)

    role = "recipient" if parcel.get("recipient_confirm_token") == token else "sender"
    name = parcel.get("recipient_name", "") if role == "recipient" else ""
    return HTMLResponse(_html_page(token, role, name))


@router.post("/{token}/locate")
async def confirm_location(token: str, payload: LocationPayload):
    """Enregistre les coordonnées GPS sur le colis."""
    parcel = await db.parcels.find_one({
        "$or": [
            {"recipient_confirm_token": token},
            {"sender_confirm_token": token},
        ]
    })
    if not parcel:
        raise not_found_exception("Token de confirmation")

    is_recipient = parcel.get("recipient_confirm_token") == token
    field_prefix = "delivery" if is_recipient else "pickup"

    location = {
        "label":    None,
        "district": None,
        "city":     "Dakar",
        "notes":    None,
        "geopin": {
            "lat":      payload.lat,
            "lng":      payload.lng,
            "accuracy": payload.accuracy,
        },
        "source":    "gps_recipient" if is_recipient else "gps_sender",
        "confirmed": True,
    }

    updates = {
        f"{field_prefix}_location":  location,
        f"{field_prefix}_confirmed": True,
        "updated_at": datetime.now(timezone.utc),
    }
    if payload.voice_note:
        updates[f"{field_prefix}_voice_note"] = payload.voice_note

    await db.parcels.update_one({"parcel_id": parcel["parcel_id"]}, {"$set": updates})
    return {"ok": True, "confirmed": field_prefix}


@router.post("/{token}/voice")
async def save_voice_note(token: str, payload: dict):
    """Sauvegarde la note vocale après confirmation GPS."""
    parcel = await db.parcels.find_one({
        "$or": [
            {"recipient_confirm_token": token},
            {"sender_confirm_token": token},
        ]
    })
    if not parcel:
        raise not_found_exception("Token")

    is_recipient = parcel.get("recipient_confirm_token") == token
    field = "delivery_voice_note" if is_recipient else "pickup_voice_note"
    await db.parcels.update_one(
        {"parcel_id": parcel["parcel_id"]},
        {"$set": {field: payload.get("voice_note"), "updated_at": datetime.now(timezone.utc)}}
    )
    return {"ok": True}


def generate_confirm_tokens() -> tuple[str, str]:
    """Génère 2 tokens uniques (destinataire, expéditeur)."""
    return secrets.token_urlsafe(12), secrets.token_urlsafe(12)
