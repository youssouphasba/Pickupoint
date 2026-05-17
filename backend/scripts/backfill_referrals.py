import asyncio
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from database import close_db, connect_db, db
from services.referral_service import ensure_referral_record_for_user, refresh_referral_progress
from services.user_service import get_global_app_settings


async def main():
    dry_run = "--dry-run" in sys.argv
    await connect_db()
    settings_doc = await get_global_app_settings()
    query = {"referred_by": {"$exists": True, "$ne": None}}
    users = await db.users.find(query, {"_id": 0}).to_list(length=None)
    created = 0
    refreshed = 0

    for user in users:
        existing = await db.referrals.find_one({"referred_user_id": user.get("user_id")}, {"_id": 0})
        if not existing:
            created += 1
        if not dry_run:
            referral = await ensure_referral_record_for_user(user, settings_doc, source="legacy_backfill")
            if referral:
                await refresh_referral_progress(user["user_id"], settings_doc)
                refreshed += 1

    mode = "DRY RUN" if dry_run else "BACKFILL"
    print(f"{mode} referred_users={len(users)} missing_referral_records={created} refreshed={refreshed}")
    await close_db()


if __name__ == "__main__":
    asyncio.run(main())
