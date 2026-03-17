"""
Service OTP : génération, stockage MongoDB avec TTL et envoi via provider explicite.
"""
import logging
from datetime import datetime, timedelta, timezone

from config import settings
from core.security import generate_otp
from database import db

logger = logging.getLogger(__name__)


def _build_mock_code() -> str:
    code = settings.OTP_MOCK_CODE.strip() or "123456"
    if len(code) < settings.OTP_LENGTH:
        code = code.ljust(settings.OTP_LENGTH, "0")
    return code[: settings.OTP_LENGTH]


async def _store_otp(phone: str, otp_code: str) -> None:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRE_MINUTES)
    await db.otps.delete_many({"phone": phone})
    await db.otps.insert_one(
        {
            "phone": phone,
            "otp": otp_code,
            "expires_at": expires_at,
            "attempts": 0,
        }
    )


async def send_otp(phone: str) -> dict:
    """
    Génère un OTP et l'envoie selon le provider configuré.
    Retourne un objet sérialisable pour l'API.
    """
    provider = settings.OTP_PROVIDER.lower()

    if provider == "mock":
        otp_code = _build_mock_code()
        await _store_otp(phone, otp_code)
        logger.info("OTP mock generated for %s", phone)
        if settings.DEBUG:
            print("\n" + "!" * 60, flush=True)
            print(f"[DEBUG OTP] {phone} -> {otp_code}", flush=True)
            print("!" * 60 + "\n", flush=True)
        return {
            "sent": True,
            "channel": "mock",
            "test_code": otp_code if settings.DEBUG else None,
        }

    otp_code = generate_otp(settings.OTP_LENGTH)
    sent = await _send_via_twilio(phone, otp_code)
    if not sent:
        logger.warning("OTP delivery failed for %s via provider=%s", phone, provider)
        return {"sent": False, "channel": provider}

    await _store_otp(phone, otp_code)
    return {"sent": True, "channel": provider}


async def verify_otp(phone: str, otp_code: str) -> bool:
    """
    Vérifie l'OTP. Expire le code après trop d'essais ou après expiration.
    """
    record = await db.otps.find_one({"phone": phone}, {"_id": 0})
    if not record:
        return False

    now = datetime.now(timezone.utc)
    expires_at = record.get("expires_at")
    if expires_at and expires_at.replace(tzinfo=timezone.utc) < now:
        await db.otps.delete_one({"phone": phone})
        return False

    attempts = int(record.get("attempts", 0))
    if attempts >= settings.OTP_MAX_ATTEMPTS:
        await db.otps.delete_one({"phone": phone})
        return False

    if record.get("otp") != otp_code.strip():
        attempts += 1
        if attempts >= settings.OTP_MAX_ATTEMPTS:
            await db.otps.delete_one({"phone": phone})
        else:
            await db.otps.update_one({"phone": phone}, {"$set": {"attempts": attempts}})
        return False

    await db.otps.delete_one({"phone": phone})
    return True


async def _send_via_twilio(phone: str, otp_code: str) -> bool:
    """Envoie l'OTP via WhatsApp (priorité) puis SMS (fallback)."""
    try:
        from twilio.rest import Client
        client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
        message_body = f"Votre code Denkma : {otp_code}. Valable {settings.OTP_EXPIRE_MINUTES} minutes."

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
