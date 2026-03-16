import re
from datetime import datetime, timedelta, timezone

from pymongo import ReturnDocument

from core.exceptions import bad_request_exception

MAX_CODE_ATTEMPTS = 5
CODE_LOCKOUT_MINUTES = 15


async def check_code_lockout(db, parcel_id: str, code_type: str):
    """Vérifie si le colis est verrouillé suite à trop de tentatives erronées."""
    key = f"{parcel_id}:{code_type}"
    record = await db.code_attempts.find_one({"_id": key})
    if not record:
        return
    if record.get("locked_until"):
        now = datetime.now(timezone.utc)
        if now < record["locked_until"]:
            remaining = int((record["locked_until"] - now).total_seconds() // 60) + 1
            raise bad_request_exception(
                f"Trop de tentatives échouées. Réessayez dans {remaining} min."
            )
        await db.code_attempts.delete_one({"_id": key})


async def record_failed_attempt(db, parcel_id: str, code_type: str):
    """Enregistre une tentative échouée. Verrouille après MAX_CODE_ATTEMPTS."""
    key = f"{parcel_id}:{code_type}"
    now = datetime.now(timezone.utc)
    result = await db.code_attempts.find_one_and_update(
        {"_id": key},
        {"$inc": {"attempts": 1}, "$set": {"last_attempt": now}},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    if result and result.get("attempts", 0) >= MAX_CODE_ATTEMPTS:
        await db.code_attempts.update_one(
            {"_id": key},
            {"$set": {"locked_until": now + timedelta(minutes=CODE_LOCKOUT_MINUTES)}},
        )
        raise bad_request_exception(
            f"Trop de tentatives échouées ({MAX_CODE_ATTEMPTS}). Code verrouillé pendant {CODE_LOCKOUT_MINUTES} min."
        )


async def clear_code_attempts(db, parcel_id: str, code_type: str):
    """Supprime le compteur après une vérification réussie."""
    await db.code_attempts.delete_one({"_id": f"{parcel_id}:{code_type}"})


def mask_phone(phone: str) -> str:
    """
    Masque un numéro de téléphone en ne laissant que l'indicatif (si présent) 
    et les 2 derniers chiffres.
    Format type: +221 77 123 45 67 -> +221 ••• •• 67
    """
    if not phone:
        return ""
    
    # On nettoie les espaces pour le traitement
    clean_phone = phone.replace(" ", "")
    
    # Si le numéro est très court, on ne fait rien ou on masque tout
    if len(clean_phone) <= 4:
        return "••••"

    # On essaie de garder l'indicatif (+ suivi de 1-3 chiffres)
    match = re.match(r"^(\+\d{1,3})", clean_phone)
    prefix = match.group(1) if match else ""
    
    # Les 2 derniers chiffres
    suffix = clean_phone[-2:]
    
    # Le milieu à masquer
    return f"{prefix} ••• •• {suffix}" if prefix else f"••• •• {suffix}"
