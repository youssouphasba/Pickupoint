"""
Router confirmation d'adresse — système bidirectionnel GPS.
Liens envoyés par SMS/WhatsApp à l'expéditeur ou au destinataire.
Aucune authentification requise — token signé suffit.
"""
import html
import json
import secrets
from datetime import datetime, timezone
from datetime import timedelta

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from typing import Optional

from core.exceptions import not_found_exception, bad_request_exception
from core.limiter import limiter
from database import db
from services.otp_service import _send_via_twilio
from models.parcel import ParcelQuote
from services.pricing_service import calculate_price
from services.payment_service import create_payment_link

router = APIRouter()


async def _refresh_quote_if_ready(parcel: dict) -> tuple[dict, bool]:
    sender_user_id = parcel.get("sender_user_id")
    user = await db.users.find_one({"user_id": sender_user_id}) if sender_user_id else None
    sender_tier = user.get("loyalty_tier", "bronze") if user else "bronze"

    month_ago = datetime.now(timezone.utc) - timedelta(days=30)
    delivered_count = await db.parcels.count_documents({
        "sender_user_id": sender_user_id,
        "status": "delivered",
        "created_at": {"$gte": month_ago},
    })
    total_delivered = await db.parcels.count_documents({
        "sender_user_id": sender_user_id,
        "status": "delivered",
    })

    quote_req = ParcelQuote(
        delivery_mode=parcel["delivery_mode"],
        origin_relay_id=parcel.get("origin_relay_id"),
        destination_relay_id=parcel.get("destination_relay_id"),
        origin_location=parcel.get("origin_location"),
        delivery_address=parcel.get("delivery_address"),
        weight_kg=float(parcel.get("weight_kg") or 0.5),
        declared_value=parcel.get("declared_value"),
        is_express=bool(parcel.get("is_express")),
        who_pays=parcel.get("who_pays") or "sender",
        promo_code=None,
    )

    quote = await calculate_price(
        quote_req,
        sender_tier=sender_tier,
        is_frequent=delivered_count >= 10,
        user_id=sender_user_id,
        is_first_delivery=(total_delivered == 0),
    )

    payment_url = None
    payment_ref = None
    if quote.price is not None:
        payer_phone = parcel.get("sender_phone") if parcel.get("who_pays") == "sender" else parcel.get("recipient_phone")
        payer_name = parcel.get("sender_name") if parcel.get("who_pays") == "sender" else parcel.get("recipient_name")
        payment_res = await create_payment_link(
            parcel_id=parcel["parcel_id"],
            tracking_code=parcel["tracking_code"],
            amount=quote.price,
            customer_phone=payer_phone or "",
            customer_name=payer_name or "Client Denkma",
        )
        if payment_res.get("success"):
            payment_url = payment_res.get("payment_link")
            payment_ref = payment_res.get("tx_ref")

    previous_price = parcel.get("quoted_price")
    updates = {
        "quoted_price": quote.price,
        "quote_breakdown": quote.breakdown,
        "updated_at": datetime.now(timezone.utc),
    }
    if payment_url:
        updates["payment_url"] = payment_url
    if payment_ref:
        updates["payment_ref"] = payment_ref
    if quote.price is None:
        updates["payment_url"] = None
        updates["payment_ref"] = None

    await db.parcels.update_one({"parcel_id": parcel["parcel_id"]}, {"$set": updates})

    refreshed = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0}) or parcel
    quote_became_available = previous_price is None and quote.price is not None
    return refreshed, quote_became_available


class LocationPayload(BaseModel):
    lat:       float = Field(..., ge=-90, le=90)
    lng:       float = Field(..., ge=-180, le=180)
    accuracy:  Optional[float] = Field(None, ge=0)
    voice_note: Optional[str]  = None  # base64 ou URL enregistrement vocal


def _html_page(token: str, role: str, recipient_name: str = "") -> str:
    """Page HTML minimaliste — 1 grand bouton, aucun texte obligatoire à lire."""
    role_label = "livraison" if role == "recipient" else "enlèvement"
    safe_name = html.escape(recipient_name)
    safe_role_label = html.escape(role_label)
    greeting   = f"Bonjour {safe_name} ! " if safe_name else ""
    token_json = json.dumps(token)
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
  <p>Appuyez sur le bouton pour indiquer<br>votre position de <strong>{safe_role_label}</strong></p>

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
    const TOKEN = {token_json};
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
@limiter.limit("10/minute")
async def confirmation_page(token: str, request: Request):
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
@limiter.limit("10/minute")
async def confirm_location(token: str, payload: LocationPayload, request: Request):
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
    reminder_role = "recipient" if is_recipient else "sender"

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
        f"gps_reminders.{reminder_role}.confirmed_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc),
    }

    if is_recipient:
        updates["delivery_address"] = location
    else:
        updates["origin_location"] = location
    if payload.voice_note:
        updates[f"{field_prefix}_voice_note"] = payload.voice_note

    await db.parcels.update_one({"parcel_id": parcel["parcel_id"]}, {"$set": updates})

    # ── Si le destinataire ou l'expéditeur confirme, on vérifie la création de mission ──
    updated_parcel = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0})
    if updated_parcel:
        mode = updated_parcel.get("delivery_mode", "")
        status = updated_parcel.get("status", "")

        from services.parcel_service import _create_delivery_mission
        from models.common import ParcelStatus

        if mode.startswith("home_to_") or mode.endswith("_to_home"):
            updated_parcel, quote_became_available = await _refresh_quote_if_ready(updated_parcel)
            quoted_price = updated_parcel.get("quoted_price")
            estimated_hours = ((updated_parcel.get("quote_breakdown") or {}).get("estimated_hours"))
            payer_user_id = (
                updated_parcel.get("recipient_user_id")
                if updated_parcel.get("who_pays") == "recipient"
                else updated_parcel.get("sender_user_id")
            )
            if quote_became_available and payer_user_id and quoted_price is not None and estimated_hours:
                from services.notification_service import notify_quote_finalized

                await notify_quote_finalized(
                    user_id=payer_user_id,
                    parcel_id=updated_parcel["parcel_id"],
                    tracking_code=updated_parcel.get("tracking_code", ""),
                    amount=float(quoted_price),
                    estimated_hours=str(estimated_hours),
                )

        if is_recipient and mode.endswith("_to_home"):
            if status == ParcelStatus.CREATED.value and mode == "home_to_home":
                await _create_delivery_mission(updated_parcel, ParcelStatus.CREATED)
            elif status == ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value and mode == "relay_to_home":
                await _create_delivery_mission(updated_parcel, ParcelStatus.DROPPED_AT_ORIGIN_RELAY)
            elif status == ParcelStatus.AT_DESTINATION_RELAY.value:
                await _create_delivery_mission(updated_parcel, ParcelStatus.AT_DESTINATION_RELAY)

        if (not is_recipient) and mode.startswith("home_to_") and status == ParcelStatus.CREATED.value:
            await _create_delivery_mission(updated_parcel, ParcelStatus.CREATED)

    return {"ok": True, "confirmed": field_prefix}


@router.post("/{token}/voice")
@limiter.limit("10/minute")
async def save_voice_note(token: str, payload: dict, request: Request):
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
