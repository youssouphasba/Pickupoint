import posixpath
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import HTTPException
from starlette.staticfiles import StaticFiles

from config import UPLOADS_DIR, settings
from core.exceptions import bad_request_exception, forbidden_exception
from models.common import UserRole


PRIVATE_UPLOAD_DIRECTORIES = frozenset({"kyc", "profiles", "parcel_photos", "voice"})
PRIVATE_KYC_DIR = UPLOADS_DIR.parent / "private_uploads" / "kyc"
KYC_DOCUMENT_TYPES = ("id_card", "license")
SENSITIVE_USER_FIELDS = frozenset({
    "_id", "pin_hash", "admin_password_hash", "admin_totp_secret",
    "admin_totp_pending_secret", "fcm_token", "refresh_token", "refresh_token_hash", "driver_application",
})


def is_private_upload_path(path: str) -> bool:
    normalized = posixpath.normpath("/" + path.replace("\\", "/").lstrip("/")).casefold()
    parts = normalized.strip("/").split("/")
    return len(parts) >= 2 and parts[0] == "uploads" and parts[1] in PRIVATE_UPLOAD_DIRECTORIES


class PublicUploadFiles(StaticFiles):
    async def get_response(self, path: str, scope):
        if is_private_upload_path(f"/uploads/{path}"):
            raise HTTPException(status_code=404, detail="Not found")
        return await super().get_response(path, scope)


def can_access_kyc_documents(user: dict) -> bool:
    return user.get("role") == UserRole.SUPERADMIN.value or (
        user.get("role") == UserRole.ADMIN.value
        and user.get("kyc_access_enabled") is True
    )


def require_kyc_access(user: dict) -> None:
    if not can_access_kyc_documents(user):
        raise forbidden_exception("Vous n’êtes pas habilité à consulter ou valider les pièces d’identité.")


def kyc_document_url(user_id: str, doc_type: str) -> str:
    if doc_type not in KYC_DOCUMENT_TYPES:
        raise ValueError("Invalid document type")
    return f"{settings.BASE_URL.rstrip('/')}/api/users/{user_id}/kyc/{doc_type}"


def validate_kyc_reference(url: str | None, user_id: str, doc_type: str) -> None:
    if not url:
        return
    try:
        parsed = urlsplit(url)
    except ValueError:
        raise bad_request_exception("Référence du document invalide.") from None
    base = urlsplit(settings.BASE_URL)
    if parsed.scheme or parsed.netloc:
        if (parsed.scheme, parsed.netloc) != (base.scheme, base.netloc):
            raise bad_request_exception("Utilisez les documents téléversés dans Denkma, pas un lien externe.")
    allowed = {f"/api/users/me/kyc/{doc_type}", f"/api/users/{user_id}/kyc/{doc_type}"}
    if parsed.path not in allowed or parsed.query or parsed.fragment:
        raise bad_request_exception("La référence du document ne correspond pas à votre compte.")


def legacy_kyc_path(user: dict, doc_type: str) -> Path | None:
    stored = user.get(f"kyc_{doc_type}_path")
    if not stored:
        return None
    try:
        resolved = Path(stored).resolve()
        for root in (PRIVATE_KYC_DIR, UPLOADS_DIR / "kyc"):
            if resolved.is_relative_to(root.resolve()) and resolved.is_file():
                return resolved
    except (OSError, ValueError, TypeError):
        return None
    return None


def has_kyc_document(user: dict, doc_type: str) -> bool:
    return bool(user.get(f"kyc_{doc_type}_file_id") or legacy_kyc_path(user, doc_type))


def serialize_private_user(user: dict, viewer: dict) -> dict:
    result = {key: value for key, value in user.items() if key not in SENSITIVE_USER_FIELDS}
    allowed = viewer.get("user_id") == user.get("user_id") or can_access_kyc_documents(viewer)
    for doc_type in KYC_DOCUMENT_TYPES:
        prefix = f"kyc_{doc_type}"
        present = bool(user.get(f"{prefix}_url") or user.get(f"{prefix}_file_id") or user.get(f"{prefix}_path"))
        if present or f"{prefix}_url" in result:
            result[f"{prefix}_url"] = kyc_document_url(user["user_id"], doc_type) if allowed and present else None
        for suffix in ("path", "file_id", "storage", "content_type"):
            result.pop(f"{prefix}_{suffix}", None)
    return result
