import argparse
import asyncio
from datetime import datetime, timezone
import mimetypes
from pathlib import Path
import sys

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorGridFSBucket

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from config import settings
from core.private_documents import KYC_DOCUMENT_TYPES, kyc_document_url, legacy_kyc_path
from services.kyc_security import decrypt_kyc_content, encrypt_kyc_content


async def secure_document(database, bucket, user: dict, doc_type: str, *, apply: bool, rotate: bool) -> str:
    field = f"kyc_{doc_type}_file_id"
    previous_id = user.get(field)
    old_path = legacy_kyc_path(user, doc_type)
    stream = await bucket.open_download_stream(ObjectId(previous_id)) if previous_id else None
    metadata = dict(stream.metadata or {}) if stream else {}
    if metadata.get("user_id") not in (None, user["user_id"]) or metadata.get("doc_type") not in (None, doc_type):
        return "invalid_owner"
    if stream and metadata.get("encryption") == "fernet" and not rotate and not old_path:
        return "already_encrypted"
    if not stream and not old_path:
        return "unavailable"
    if not apply:
        return "to_secure"
    content = await stream.read() if stream else old_path.read_bytes()
    encrypted, encryption = encrypt_kyc_content(decrypt_kyc_content(content, metadata.get("encryption")))
    if encryption is None:
        raise ValueError("Configure encryption before applying migration")
    metadata.update(user_id=user["user_id"], doc_type=doc_type, encryption=encryption,
                    secured_at=datetime.now(timezone.utc))
    filename = stream.filename if stream else old_path.name
    media_type = metadata.get("content_type") or user.get(f"kyc_{doc_type}_content_type") or mimetypes.guess_type(filename)[0] or "application/octet-stream"
    metadata["content_type"] = media_type
    new_id = await bucket.upload_from_stream(filename, encrypted, metadata=metadata)
    try:
        result = await database.users.update_one({"user_id": user["user_id"], field: previous_id,
            "deleted_account": {"$ne": True}, "is_active": {"$ne": False}}, {
            "$set": {field: str(new_id), f"kyc_{doc_type}_storage": "gridfs",
                f"kyc_{doc_type}_url": kyc_document_url(user["user_id"], doc_type),
                f"kyc_{doc_type}_path": None, f"kyc_{doc_type}_content_type": media_type},
        })
    except Exception:
        await bucket.delete(new_id)
        raise
    if result.modified_count != 1:
        await bucket.delete(new_id)
        return "concurrent_change"
    if previous_id:
        await bucket.delete(ObjectId(previous_id))
    if old_path:
        old_path.unlink(missing_ok=True)
    return "secured"


async def main():
    parser = argparse.ArgumentParser(description="Sécuriser les pièces KYC existantes. Simulation par défaut.")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--rotate", action="store_true")
    args = parser.parse_args()
    if args.apply and not settings.KYC_ENCRYPTION_KEYS.strip():
        parser.error("Configurez KYC_ENCRYPTION_KEYS avant --apply.")
    client = AsyncIOMotorClient(settings.MONGO_URL, serverSelectionTimeoutMS=5000)
    database = client[settings.DB_NAME]
    bucket = AsyncIOMotorGridFSBucket(database, bucket_name="kyc_documents")
    totals = {}
    try:
        query = {"$or": [{f"kyc_{doc_type}_{suffix}": {"$ne": None}}
            for doc_type in KYC_DOCUMENT_TYPES for suffix in ("file_id", "path")]}
        async for user in database.users.find(query):
            for doc_type in KYC_DOCUMENT_TYPES:
                try:
                    outcome = await secure_document(database, bucket, user, doc_type, apply=args.apply, rotate=args.rotate)
                except Exception:
                    outcome = "failed"
                totals[outcome] = totals.get(outcome, 0) + 1
        print({"mode": "apply" if args.apply else "dry_run", "totals": totals})
    finally:
        client.close()


if __name__ == "__main__":
    asyncio.run(main())
