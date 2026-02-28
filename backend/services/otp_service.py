"""
Service OTP : génération, stockage MongoDB avec TTL, envoi Twilio (WhatsApp + SMS fallback),
et vérification.
"""
import logging
from datetime import datetime, timezone, timedelta

from config import settings
from core.security import generate_otp
from database import db

logger = logging.getLogger(__name__)


async def send_otp(phone: str) -> bool:
    """
    Génère un OTP, le stocke avec TTL, et l'envoie via WhatsApp (ou SMS en fallback).
    Retourne True si envoyé avec succès.
    """
    # En mode debug, on utilise un code fixe pour simplifier
    if settings.DEBUG:
        otp_code = "123456"
    else:
        otp_code = generate_otp(settings.OTP_LENGTH)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRE_MINUTES)

    # Supprimer l'OTP précédent pour ce téléphone
    await db.otps.delete_many({"phone": phone})

    # Stocker le nouvel OTP
    await db.otps.insert_one({
        "phone":      phone,
        "otp":        otp_code,
        "expires_at": expires_at,
        "attempts":   0,
    })

    if settings.DEBUG:
        print("\n" + "!"*60, flush=True)
        print(f"🔑 [DEBUG] CODE OTP POUR {phone} : {otp_code}", flush=True)
        print("!"*60 + "\n", flush=True)

    # Envoi Twilio
    sent = await _send_via_twilio(phone, otp_code)

    return sent


async def verify_otp(phone: str, otp_code: str) -> bool:
    """
    Vérifie l'OTP. Supprime le document si valide, incrémente les tentatives sinon.
    """
    record = await db.otps.find_one({"phone": phone}, {"_id": 0})
    if not record:
        return False

    now = datetime.now(timezone.utc)
    # Vérifier expiration
    expires_at = record.get("expires_at")
    if expires_at and expires_at.replace(tzinfo=timezone.utc) < now:
        await db.otps.delete_one({"phone": phone})
        return False

    # Vérifier le code
    if record.get("otp") != otp_code:
        await db.otps.update_one({"phone": phone}, {"$inc": {"attempts": 1}})
        return False

    # Valide → on supprime
    await db.otps.delete_one({"phone": phone})
    return True


async def _send_via_twilio(phone: str, otp_code: str) -> bool:
    """Envoie l'OTP via WhatsApp (priorité) puis SMS (fallback)."""
    if not settings.TWILIO_ACCOUNT_SID or not settings.TWILIO_AUTH_TOKEN:
        logger.warning("Twilio non configuré — OTP non envoyé")
        return False

    try:
        from twilio.rest import Client
        client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
        message_body = f"Votre code PickuPoint : {otp_code}. Valable {settings.OTP_EXPIRE_MINUTES} minutes."

        # Tentative WhatsApp
        if settings.TWILIO_WHATSAPP_NUMBER:
            try:
                client.messages.create(
                    body=message_body,
                    from_=settings.TWILIO_WHATSAPP_NUMBER,
                    to=f"whatsapp:{phone}",
                )
                logger.info(f"OTP envoyé via WhatsApp à {phone}")
                return True
            except Exception as e:
                logger.warning(f"WhatsApp échoué pour {phone} : {e}, tentative SMS...")

        # Fallback SMS
        if settings.TWILIO_SMS_NUMBER:
            client.messages.create(
                body=message_body,
                from_=settings.TWILIO_SMS_NUMBER,
                to=phone,
            )
            logger.info(f"OTP envoyé via SMS à {phone}")
            return True

    except Exception as e:
        logger.error(f"Erreur Twilio : {e}")

    return False
