import asyncio
import mimetypes
import sys
from pathlib import Path
from urllib.parse import urlparse

from motor.motor_asyncio import AsyncIOMotorGridFSBucket

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from config import UPLOADS_DIR
from database import close_db, connect_db, get_db


PRIVATE_UPLOADS_DIR = UPLOADS_DIR.parent / "private_uploads"
PRIVATE_KYC_DIR = PRIVATE_UPLOADS_DIR / "kyc"


def _bucket(name: str) -> AsyncIOMotorGridFSBucket:
    database = get_db()
    if database is None:
        raise RuntimeError("Database not connected")
    return AsyncIOMotorGridFSBucket(database, bucket_name=name)


def _filename_from_url(url: str | None) -> str | None:
    if not url:
        return None
    filename = Path(urlparse(url).path).name
    return filename or None


async def _upload_file(bucket: AsyncIOMotorGridFSBucket, path: Path, metadata: dict) -> str:
    content = path.read_bytes()
    file_id = await bucket.upload_from_stream(path.name, content, metadata=metadata)
    return str(file_id)


async def migrate_profile_photo(user: dict, dry_run: bool) -> bool:
    if user.get("profile_picture_file_id"):
        return False
    filename = _filename_from_url(user.get("profile_picture_url"))
    if not filename:
        return False
    path = UPLOADS_DIR / "profiles" / filename
    if not path.is_file():
        return False
    if dry_run:
        return True
    media_type = mimetypes.guess_type(str(path))[0] or "application/octet-stream"
    file_id = await _upload_file(
        _bucket("profile_photos"),
        path,
        {
            "content_type": media_type,
            "user_id": user["user_id"],
            "source": "local_migration",
        },
    )
    await get_db().users.update_one(
        {"user_id": user["user_id"]},
        {
            "$set": {
                "profile_picture_file_id": file_id,
                "profile_picture_storage": "gridfs",
            }
        },
    )
    return True


async def migrate_kyc_document(user: dict, doc_type: str, dry_run: bool) -> bool:
    path_field = "kyc_id_card_path" if doc_type == "id_card" else "kyc_license_path"
    file_id_field = "kyc_id_card_file_id" if doc_type == "id_card" else "kyc_license_file_id"
    storage_field = "kyc_id_card_storage" if doc_type == "id_card" else "kyc_license_storage"
    content_type_field = (
        "kyc_id_card_content_type" if doc_type == "id_card" else "kyc_license_content_type"
    )
    if user.get(file_id_field):
        return False
    stored_path = user.get(path_field)
    if not stored_path:
        return False
    path = Path(stored_path)
    if not path.is_file():
        fallback = PRIVATE_KYC_DIR / path.name
        if fallback.is_file():
            path = fallback
        else:
            return False
    if dry_run:
        return True
    media_type = user.get(content_type_field) or mimetypes.guess_type(str(path))[0] or "application/octet-stream"
    file_id = await _upload_file(
        _bucket("kyc_documents"),
        path,
        {
            "content_type": media_type,
            "user_id": user["user_id"],
            "doc_type": doc_type,
            "source": "local_migration",
        },
    )
    await get_db().users.update_one(
        {"user_id": user["user_id"]},
        {"$set": {file_id_field: file_id, storage_field: "gridfs"}},
    )
    return True


async def main() -> None:
    dry_run = "--dry-run" in sys.argv
    await connect_db()
    try:
        users = await get_db().users.find(
            {
                "$or": [
                    {"profile_picture_url": {"$ne": None}},
                    {"kyc_id_card_path": {"$ne": None}},
                    {"kyc_license_path": {"$ne": None}},
                ]
            },
            {"_id": 0},
        ).to_list(length=None)
        migrated_profiles = 0
        migrated_kyc = 0
        missing_profiles = 0
        missing_kyc = 0
        for user in users:
            if await migrate_profile_photo(user, dry_run):
                migrated_profiles += 1
            elif user.get("profile_picture_url") and not user.get("profile_picture_file_id"):
                missing_profiles += 1
            for doc_type in ("id_card", "license"):
                if await migrate_kyc_document(user, doc_type, dry_run):
                    migrated_kyc += 1
                else:
                    path_field = "kyc_id_card_path" if doc_type == "id_card" else "kyc_license_path"
                    file_id_field = "kyc_id_card_file_id" if doc_type == "id_card" else "kyc_license_file_id"
                    if user.get(path_field) and not user.get(file_id_field):
                        missing_kyc += 1
        mode = "DRY RUN" if dry_run else "MIGRATION"
        print(f"{mode} profile_photos={migrated_profiles} kyc_documents={migrated_kyc}")
        print(f"missing_local_files profiles={missing_profiles} kyc_documents={missing_kyc}")
    finally:
        await close_db()


if __name__ == "__main__":
    asyncio.run(main())
