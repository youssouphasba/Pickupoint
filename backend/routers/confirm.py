"""
Router confirmation d'adresse — système bidirectionnel GPS.
Liens envoyés par SMS/WhatsApp à l'expéditeur ou au destinataire.
Aucune authentification requise — token signé suffit.
"""
import base64
import hashlib
import html
import json
import mimetypes
import secrets
import uuid
from datetime import datetime, timezone
from datetime import timedelta

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from typing import Optional

from core.exceptions import not_found_exception, bad_request_exception
from core.limiter import limiter
from config import UPLOADS_DIR
from database import db
from models.parcel import ParcelQuote
from services.parcel_service import _record_event
from services.pricing_service import calculate_price
from services.payment_service import create_payment_link

router = APIRouter()

TERMINAL_PARCEL_STATUSES = {"delivered", "cancelled", "returned", "expired", "disputed"}
RELAY_CHANGE_ALLOWED_STATUSES = {"created", "dropped_at_origin_relay"}
PRIVATE_CONFIRM_VOICE_DIR = UPLOADS_DIR.parent / "private_uploads" / "voice"
MAX_CONFIRM_VOICE_SIZE = 5 * 1024 * 1024


def _is_confirm_token_expired(parcel: dict) -> bool:
    return (parcel.get("status") or "").lower() in TERMINAL_PARCEL_STATUSES


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


async def _save_confirmation_voice_note(
    parcel: dict,
    token: str,
    is_recipient: bool,
    voice_note: Optional[str],
) -> Optional[str]:
    if not voice_note or not voice_note.startswith("data:audio/"):
        return None

    existing = await db.parcel_messages.find_one(
        {
            "parcel_id": parcel["parcel_id"],
            "type": "voice",
            "source": "confirm_link",
            "source_token_hash": _token_hash(token),
        },
        {"_id": 0, "message_id": 1},
    )
    if existing:
        return existing.get("message_id")

    try:
        header, encoded = voice_note.split(",", 1)
    except ValueError:
        raise bad_request_exception("Note vocale invalide")

    if ";base64" not in header:
        raise bad_request_exception("Note vocale invalide")

    mime_type = header.removeprefix("data:").split(";", 1)[0] or "audio/webm"
    if not mime_type.startswith("audio/"):
        raise bad_request_exception("Format audio non supporté")

    try:
        content = base64.b64decode(encoded, validate=True)
    except Exception:
        raise bad_request_exception("Note vocale invalide")

    if not content:
        raise bad_request_exception("Fichier audio vide")
    if len(content) > MAX_CONFIRM_VOICE_SIZE:
        raise bad_request_exception("Fichier audio trop volumineux (max 5 Mo)")

    ext = (mimetypes.guess_extension(mime_type) or ".webm").lstrip(".")
    filename = f"confirm_voice_{uuid.uuid4().hex}.{ext}"
    PRIVATE_CONFIRM_VOICE_DIR.mkdir(parents=True, exist_ok=True)
    filepath = PRIVATE_CONFIRM_VOICE_DIR / filename
    with open(filepath, "wb") as f:
        f.write(content)

    sender_role = "recipient" if is_recipient else "sender"
    sender_id = parcel.get("recipient_user_id") if is_recipient else parcel.get("sender_user_id")
    sender_name = parcel.get("recipient_name") if is_recipient else parcel.get("sender_name")
    msg = {
        "message_id": f"msg_{uuid.uuid4().hex[:12]}",
        "parcel_id": parcel["parcel_id"],
        "sender_id": sender_id or f"confirm_{sender_role}",
        "sender_name": sender_name or ("Destinataire" if is_recipient else "Expéditeur"),
        "sender_role": sender_role,
        "type": "voice",
        "content": None,
        "voice_path": str(filepath),
        "mime_type": mime_type,
        "duration_s": None,
        "source": "confirm_link",
        "source_token_hash": _token_hash(token),
        "created_at": datetime.now(timezone.utc),
    }
    await db.parcel_messages.insert_one(msg)
    return msg["message_id"]


async def _refresh_quote_if_ready(parcel: dict) -> tuple[dict, bool]:
    # Verrou atomique : seule la premiere confirmation qui rend le devis calculable
    # recree le lien de paiement, les requetes paralleles trouvent quoted_price deja
    # rempli et repartent sans toucher au lien existant.
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

    previous_price = parcel.get("quoted_price")

    # Cas 1 : devis toujours pas calculable -> on ne touche ni au paiement ni au prix.
    if quote.price is None:
        await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"]},
            {"$set": {
                "quote_breakdown": quote.breakdown,
                "updated_at": datetime.now(timezone.utc),
            }},
        )
        refreshed = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0}) or parcel
        return refreshed, False

    # Cas 2 : devis deja existant (autre confirmation parallele a deja cree le lien).
    # On met juste a jour le breakdown et on sort sans recreer de lien de paiement.
    if previous_price is not None:
        await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"]},
            {"$set": {
                "quoted_price": quote.price,
                "quote_breakdown": quote.breakdown,
                "updated_at": datetime.now(timezone.utc),
            }},
        )
        refreshed = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0}) or parcel
        return refreshed, False

    # Cas 3 : premier calcul. On reserve le slot atomiquement avant d'appeler Flutterwave.
    now = datetime.now(timezone.utc)
    lock_result = await db.parcels.update_one(
        {"parcel_id": parcel["parcel_id"], "quoted_price": None},
        {"$set": {
            "quoted_price": quote.price,
            "quote_breakdown": quote.breakdown,
            "updated_at": now,
        }},
    )
    if lock_result.modified_count == 0:
        # Une autre requete nous a devance entre le find et l'update : on abandonne sans rien refaire.
        refreshed = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0}) or parcel
        return refreshed, False

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
        await db.parcels.update_one(
            {"parcel_id": parcel["parcel_id"], "payment_ref": None},
            {"$set": {
                "payment_url": payment_res.get("payment_link"),
                "payment_ref": payment_res.get("tx_ref"),
                "updated_at": datetime.now(timezone.utc),
            }},
        )

    refreshed = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0}) or parcel
    return refreshed, True


class LocationPayload(BaseModel):
    lat:       float = Field(..., ge=-90, le=90)
    lng:       float = Field(..., ge=-180, le=180)
    accuracy:  Optional[float] = Field(None, ge=0)
    voice_note: Optional[str]  = None  # base64 ou URL enregistrement vocal


class RelayChoicePayload(BaseModel):
    relay_id: str = Field(..., min_length=1)


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
  <title>Denkma — Confirmer ma position</title>
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
  <h1>{greeting}Votre colis Denkma</h1>
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


def _relay_picker_page(
    token: str,
    recipient_name: str,
    tracking_code: str,
    relays: list,
    current_relay_id: str,
    is_locked: bool,
    current_relay_name: str,
) -> str:
    """Page HTML de choix / modification du point relais de retrait."""
    safe_name = html.escape(recipient_name or "")
    safe_tracking = html.escape(tracking_code or "")
    safe_current_name = html.escape(current_relay_name or "")
    greeting = f"Bonjour {safe_name} ! " if safe_name else ""
    token_json = json.dumps(token)

    if is_locked:
        body_html = f"""
      <div class=\"locked\">
        Votre colis est déjà en route vers <strong>{safe_current_name or 'votre point relais'}</strong>.
        Le choix du relais ne peut plus être modifié.
      </div>
    """
    else:
        options_html = ""
        for r in relays:
            rid = r.get("relay_id") or ""
            rname = r.get("name") or "Point relais"
            addr = r.get("address") or {}
            district = addr.get("district") or ""
            city = addr.get("city") or ""
            sub = ", ".join(p for p in (district, city) if p)
            checked = " checked" if rid == current_relay_id else ""
            options_html += (
                f'<label class="relay-option">'
                f'<input type="radio" name="relay" value="{html.escape(rid)}"{checked}>'
                f'<div><strong>{html.escape(rname)}</strong>'
                f'<small>{html.escape(sub)}</small></div>'
                f'</label>'
            )
        current_banner = (
            f'<div class="current">Point relais actuel : <strong>{safe_current_name}</strong>. '
            f'Vous pouvez le conserver ou en choisir un autre.</div>'
            if safe_current_name else ""
        )
        body_html = f"""
      {current_banner}
      <form id=\"picker\">
        <div class=\"relay-list\">{options_html}</div>
        <button type=\"submit\" class=\"btn\" id=\"submit\">Confirmer ce point relais</button>
      </form>
      <div class=\"success\" id=\"success\">✅ Point relais enregistré. Vous recevrez un code PIN pour le retrait.</div>
    """

    return f"""<!DOCTYPE html>
<html lang=\"fr\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1\">
  <title>Denkma — Choisir mon point relais</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif;
      background: #F5F5F5; padding: 24px; min-height: 100vh; color: #1a1a1a;
    }}
    .wrap {{ max-width: 480px; margin: 0 auto; }}
    h1 {{ font-size: 22px; margin-bottom: 6px; color: #0b8a5f; }}
    .tracking {{ color: #757575; font-size: 14px; margin-bottom: 20px; }}
    .current {{
      background: #e6f5ef; border-radius: 12px; padding: 14px; margin-bottom: 20px;
      font-size: 14px; color: #0b4a33;
    }}
    .locked {{
      background: #fff3cd; border-radius: 12px; padding: 18px; color: #7a5d00; font-size: 15px;
    }}
    .relay-list {{ display: flex; flex-direction: column; gap: 10px; margin-bottom: 20px; }}
    .relay-option {{
      display: flex; align-items: center; gap: 12px;
      background: #fff; border: 2px solid #e5e5e5; border-radius: 14px;
      padding: 14px; cursor: pointer;
    }}
    .relay-option input {{ transform: scale(1.3); margin: 0; }}
    .relay-option strong {{ display: block; font-size: 15px; margin-bottom: 2px; }}
    .relay-option small {{ color: #757575; font-size: 13px; }}
    .btn {{
      width: 100%; padding: 18px; background: #0b8a5f; color: #fff;
      border: none; border-radius: 14px; font-size: 17px; font-weight: 700;
      cursor: pointer;
    }}
    .btn:disabled {{ opacity: 0.6; cursor: wait; }}
    .success {{
      display: none; background: #e8f5e9; border-radius: 14px;
      padding: 18px; color: #2e7d32; text-align: center; margin-top: 16px; font-weight: 600;
    }}
  </style>
</head>
<body>
  <div class=\"wrap\">
    <h1>{greeting}Choisissez votre point relais</h1>
    <div class=\"tracking\">Colis {safe_tracking}</div>
    {body_html}
  </div>
  <script>
    const TOKEN = {token_json};
    const form = document.getElementById('picker');
    const btn = document.getElementById('submit');
    const success = document.getElementById('success');
    if (form) {{
      form.addEventListener('submit', async (ev) => {{
        ev.preventDefault();
        const data = new FormData(form);
        const relay_id = data.get('relay');
        if (!relay_id) {{ alert('Sélectionnez un point relais.'); return; }}
        btn.disabled = true;
        btn.textContent = 'Enregistrement...';
        try {{
          const res = await fetch('/confirm/' + TOKEN + '/relay', {{
            method: 'POST',
            headers: {{'Content-Type': 'application/json'}},
            body: JSON.stringify({{ relay_id }}),
          }});
          if (!res.ok) {{
            const msg = await res.text();
            throw new Error(msg || 'Erreur');
          }}
          form.style.display = 'none';
          success.style.display = 'block';
        }} catch (e) {{
          btn.disabled = false;
          btn.textContent = 'Confirmer ce point relais';
          alert('Impossible d\\'enregistrer votre choix. Réessayez.');
        }}
      }});
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

    if _is_confirm_token_expired(parcel):
        return HTMLResponse(
            "<h2>Lien expiré — la livraison est déjà terminée.</h2>",
            status_code=410,
        )

    role = "recipient" if parcel.get("recipient_confirm_token") == token else "sender"
    mode = parcel.get("delivery_mode", "") or ""
    status = (parcel.get("status") or "").lower()

    # Destinataire + livraison vers relais → page choix / modification de relais
    if role == "recipient" and mode.endswith("_to_relay"):
        relays_cursor = db.relay_points.find({"is_active": True}, {"_id": 0}).sort([("address.city", 1), ("name", 1)]).limit(100)
        relays = await relays_cursor.to_list(length=100)
        current_relay_id = parcel.get("destination_relay_id") or ""
        current_relay_name = ""
        if current_relay_id:
            cur = next((r for r in relays if r.get("relay_id") == current_relay_id), None)
            if not cur:
                cur = await db.relay_points.find_one({"relay_id": current_relay_id}, {"_id": 0})
            current_relay_name = (cur or {}).get("name", "")
        is_locked = status not in RELAY_CHANGE_ALLOWED_STATUSES
        return HTMLResponse(
            _relay_picker_page(
                token=token,
                recipient_name=parcel.get("recipient_name", ""),
                tracking_code=parcel.get("tracking_code", ""),
                relays=relays,
                current_relay_id=current_relay_id,
                is_locked=is_locked,
                current_relay_name=current_relay_name,
            )
        )

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

    if _is_confirm_token_expired(parcel):
        raise bad_request_exception("Lien expiré — la livraison est déjà terminée")

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
    voice_message_id = await _save_confirmation_voice_note(
        parcel,
        token,
        is_recipient,
        payload.voice_note,
    )
    if voice_message_id:
        updates[f"{field_prefix}_voice_note"] = "Note vocale reçue via le lien de confirmation."
        updates[f"{field_prefix}_voice_message_id"] = voice_message_id
    elif payload.voice_note:
        updates[f"{field_prefix}_voice_note"] = payload.voice_note

    await db.parcels.update_one({"parcel_id": parcel["parcel_id"]}, {"$set": updates})
    await _record_event(
        parcel_id=parcel["parcel_id"],
        event_type="RECIPIENT_LOCATION_CONFIRMED" if is_recipient else "SENDER_LOCATION_CONFIRMED",
        actor_role="recipient" if is_recipient else "sender",
        notes=(
            "Position de livraison confirmée par le destinataire via le lien sécurisé."
            if is_recipient
            else "Position de collecte confirmée par l'expéditeur via le lien sécurisé."
        ),
        metadata={
            "source": "confirm_link",
            "has_voice_note": bool(voice_message_id or payload.voice_note),
            "voice_message_id": voice_message_id,
        },
    )

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


@router.post("/{token}/relay")
@limiter.limit("10/minute")
async def choose_destination_relay(token: str, payload: RelayChoicePayload, request: Request):
    """Laisse le destinataire choisir ou modifier son point relais de retrait."""
    parcel = await db.parcels.find_one({"recipient_confirm_token": token})
    if not parcel:
        raise not_found_exception("Token de confirmation")

    if _is_confirm_token_expired(parcel):
        raise bad_request_exception("Lien expiré — la livraison est déjà terminée")

    mode = (parcel.get("delivery_mode") or "")
    if not mode.endswith("_to_relay"):
        raise bad_request_exception("Ce colis n'est pas en livraison vers un point relais")

    status = (parcel.get("status") or "").lower()
    if status not in RELAY_CHANGE_ALLOWED_STATUSES:
        raise bad_request_exception("Le point relais ne peut plus être modifié — le colis est en route")

    relay = await db.relay_points.find_one(
        {"relay_id": payload.relay_id, "is_active": True},
        {"_id": 0},
    )
    if not relay:
        raise not_found_exception("Point relais")

    if relay.get("current_load", 0) >= relay.get("max_capacity", 50):
        raise bad_request_exception("Ce relais est plein, choisissez un autre point relais")

    if relay.get("relay_id") == parcel.get("origin_relay_id"):
        raise bad_request_exception("Le relais de retrait doit être différent du relais de dépôt")

    now = datetime.now(timezone.utc)
    await db.parcels.update_one(
        {"parcel_id": parcel["parcel_id"]},
        {"$set": {
            "destination_relay_id": payload.relay_id,
            "redirect_relay_id": None,
            "updated_at": now,
        }},
    )

    refreshed = await db.parcels.find_one({"parcel_id": parcel["parcel_id"]}, {"_id": 0})
    if refreshed:
        try:
            await _refresh_quote_if_ready(refreshed)
        except Exception:
            pass

    return {"ok": True, "relay_id": payload.relay_id}


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

    if _is_confirm_token_expired(parcel):
        raise bad_request_exception("Lien expiré — la livraison est déjà terminée")

    is_recipient = parcel.get("recipient_confirm_token") == token
    field = "delivery_voice_note" if is_recipient else "pickup_voice_note"
    message_field = "delivery_voice_message_id" if is_recipient else "pickup_voice_message_id"
    voice_message_id = await _save_confirmation_voice_note(
        parcel,
        token,
        is_recipient,
        payload.get("voice_note"),
    )
    voice_value = (
        "Note vocale reçue via le lien de confirmation."
        if voice_message_id
        else payload.get("voice_note")
    )
    await db.parcels.update_one(
        {"parcel_id": parcel["parcel_id"]},
        {"$set": {
            field: voice_value,
            message_field: voice_message_id,
            "updated_at": datetime.now(timezone.utc),
        }}
    )
    if voice_message_id:
        await _record_event(
            parcel_id=parcel["parcel_id"],
            event_type="VOICE_INSTRUCTION_ADDED",
            actor_role="recipient" if is_recipient else "sender",
            notes=(
                "Note vocale de livraison ajoutée par le destinataire."
                if is_recipient
                else "Note vocale de collecte ajoutée par l'expéditeur."
            ),
            metadata={
                "source": "confirm_link",
                "voice_message_id": voice_message_id,
            },
        )
    return {"ok": True}


def generate_confirm_tokens() -> tuple[str, str]:
    """Génère 2 tokens uniques (destinataire, expéditeur)."""
    return secrets.token_urlsafe(32), secrets.token_urlsafe(32)
