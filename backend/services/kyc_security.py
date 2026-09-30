import asyncio
from io import BytesIO
import struct
import warnings

from cryptography.fernet import Fernet, InvalidToken, MultiFernet
from fastapi import HTTPException
from PIL import Image, ImageOps, UnidentifiedImageError

from config import settings
from core.exceptions import bad_request_exception


def sanitize_kyc_image(content: bytes) -> tuple[bytes, str, str]:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(content)) as image:
                if image.format not in {"JPEG", "PNG", "WEBP"} or getattr(image, "n_frames", 1) != 1:
                    raise bad_request_exception("Utilisez une photo JPEG, PNG ou WebP non animée.")
                if image.width * image.height > settings.KYC_MAX_IMAGE_PIXELS:
                    raise bad_request_exception("La résolution de cette photo est trop élevée.")
                image.load()
                oriented = ImageOps.exif_transpose(image)
                clean = Image.new("RGB", oriented.size, "white")
                if "A" in oriented.getbands():
                    rgba = oriented.convert("RGBA")
                    clean.paste(rgba, mask=rgba.getchannel("A"))
                else:
                    clean.paste(oriented.convert("RGB"))
                output = BytesIO()
                clean.save(output, format="JPEG", quality=settings.KYC_JPEG_QUALITY)
                sanitized = output.getvalue()
                if len(sanitized) > settings.KYC_MAX_UPLOAD_BYTES:
                    raise bad_request_exception("La photo reste trop volumineuse après traitement.")
                return sanitized, ".jpg", "image/jpeg"
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise bad_request_exception("Photo invalide ou corrompue.") from None


async def scan_kyc_upload(content: bytes, *, required: bool = False) -> str:
    if not settings.KYC_CLAMAV_HOST:
        if required or settings.KYC_REQUIRE_ANTIVIRUS:
            raise HTTPException(status_code=503, detail="La vérification antivirus est indisponible. Réessayez ou utilisez une photo.")
        return "image_reconstructed"
    writer = None
    try:
        async with asyncio.timeout(settings.KYC_CLAMAV_TIMEOUT_SECONDS):
            reader, writer = await asyncio.open_connection(settings.KYC_CLAMAV_HOST, settings.KYC_CLAMAV_PORT)
            writer.write(b"zINSTREAM\0")
            for offset in range(0, len(content), 65536):
                chunk = content[offset:offset + 65536]
                writer.write(struct.pack("!I", len(chunk)) + chunk)
                await writer.drain()
            writer.write(struct.pack("!I", 0))
            await writer.drain()
            response = await reader.readuntil(b"\0")
        if response.rstrip(b"\0\r\n") != b"stream: OK":
            raise bad_request_exception("Le contrôle de sécurité a refusé ce document.")
        return "clamav_clean"
    except (OSError, TimeoutError, asyncio.IncompleteReadError, asyncio.LimitOverrunError):
        raise HTTPException(status_code=503, detail="La vérification antivirus est indisponible. Réessayez plus tard.") from None
    finally:
        if writer:
            writer.close()


def _document_cipher() -> MultiFernet | None:
    keys = [key.strip() for key in settings.KYC_ENCRYPTION_KEYS.split(",") if key.strip()]
    return MultiFernet([Fernet(key.encode("ascii")) for key in keys]) if keys else None


def encrypt_kyc_content(content: bytes) -> tuple[bytes, str | None]:
    cipher = _document_cipher()
    if cipher is None:
        if settings.KYC_REQUIRE_ENCRYPTION:
            raise HTTPException(status_code=503, detail="Le stockage sécurisé des documents est indisponible.")
        return content, None
    return cipher.encrypt(content), "fernet"


def decrypt_kyc_content(content: bytes, encryption: str | None) -> bytes:
    if not encryption:
        return content
    cipher = _document_cipher()
    if encryption != "fernet" or cipher is None:
        raise HTTPException(status_code=503, detail="La lecture sécurisée du document est indisponible.")
    try:
        return cipher.decrypt(content)
    except InvalidToken:
        raise HTTPException(status_code=503, detail="La lecture sécurisée du document est indisponible.") from None
