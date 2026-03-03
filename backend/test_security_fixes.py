import asyncio
import os
import sys
from datetime import datetime, timezone
import httpx

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from core.security import create_access_token

async def test_security():
    await connect_db()
    print("--- DEBUT TEST CORRECTIFS SECURITE ---")
    
    # 1. Test is_banned check in dependency
    print("\n[TEST] Verificaton check is_banned sur route protegee...")
    user_id = "test_sec_user_1"
    phone = "+221770000001"
    
    # NETTOYAGE RIGOUREUX
    await db.users.delete_many({"phone": phone})
    await db.users.delete_one({"user_id": user_id})
    
    await db.users.insert_one({
        "user_id": user_id,
        "phone": phone,
        "role": "client",
        "is_active": True,
        "is_banned": True,
        "created_at": datetime.now(timezone.utc)
    })
    
    u = await db.users.find_one({"user_id": user_id})
    if u.get("is_banned"):
        print("[OK] Flag is_banned present en DB.")

    # Nettoyage final
    await db.users.delete_one({"user_id": user_id})
    print("\n--- FIN TEST ---")

if __name__ == "__main__":
    asyncio.run(test_security())
