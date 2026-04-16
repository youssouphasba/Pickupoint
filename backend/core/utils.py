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


SUPPORTED_COUNTRY_CODES = ("221", "33")  # Sénégal, France


def normalize_phone(phone: str | None) -> str:
    """Normalise un numero en E.164 quand c'est possible (SN/FR).

    Regles:
      - "+221..." ou "+33..." : conserve l'indicatif.
      - "00221..." / "00 33..." : convertit en "+...".
      - "221..." / "33..." (sans +) : prefixe "+".
      - 9 chiffres commencant par 7 ou 3 (format local senegalais) : prefixe "+221".
      - 9 chiffres commencant par 6 ou 7 (format local francais sans 0) : prefixe "+33"
        uniquement si l'indicatif est explicite ailleurs — sinon on ne devine pas.
      - Sinon, retourne juste les chiffres.
    """
    if not phone:
        return ""

    raw = phone.strip().replace(" ", "").replace("-", "").replace(".", "")
    if raw.startswith("00"):
        raw = f"+{raw[2:]}"

    if raw.startswith("+"):
        return f"+{re.sub(r'\\D', '', raw[1:])}"

    digits = re.sub(r"\D", "", raw)
    if not digits:
        return ""

    for code in SUPPORTED_COUNTRY_CODES:
        if digits.startswith(code):
            return f"+{digits}"

    if len(digits) == 9 and digits[0] in {"7", "3"}:
        return f"+221{digits}"

    return digits


def is_supported_phone(phone: str | None) -> bool:
    normalized = normalize_phone(phone)
    if not normalized.startswith("+"):
        return False
    return any(normalized.startswith(f"+{code}") for code in SUPPORTED_COUNTRY_CODES)


def phones_match(left: str | None, right: str | None) -> bool:
    left_normalized = normalize_phone(left)
    right_normalized = normalize_phone(right)
    return bool(left_normalized and right_normalized and left_normalized == right_normalized)


def phone_suffix(phone: str | None, digits: int = 9) -> str:
    normalized = normalize_phone(phone)
    numeric = re.sub(r"\D", "", normalized)
    return numeric[-digits:] if numeric else ""


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
