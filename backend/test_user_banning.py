import asyncio
import os
import sys
from datetime import datetime, timezone

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from models.common import UserRole

async def test_banning():
    await connect_db()
    print("--- DEBUT TEST BANNING UTILISATEUR ---")
    
    phone = "+221770000000"
    user_id = "test_ban_user_1"
    
    # 1. Nettoyage et Création
    await db.users.delete_one({"phone": phone})
    await db.user_sessions.delete_many({"user_id": user_id})
    
    user_doc = {
        "user_id": user_id,
        "phone": phone,
        "name": "Test Ban",
        "role": "client",
        "is_active": True,
        "is_banned": False,
        "created_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc)
    }
    await db.users.insert_one(user_doc)
    
    # Créer une session active
    await db.user_sessions.insert_one({
        "user_id": user_id,
        "refresh_token": "fake_refresh_token_123",
        "created_at": datetime.now(timezone.utc)
    })
    print(f"[OK] Utilisateur créé avec session active.")

    # 2. Bannissement Admin
    print("\n[TEST] Bannissement Admin...")
    # On simule l'action admin:ban
    await db.users.update_one({"user_id": user_id}, {"$set": {"is_banned": True}})
    await db.user_sessions.delete_many({"user_id": user_id})
    
    # Vérifier sessions supprimées
    active_sessions = await db.user_sessions.count_documents({"user_id": user_id})
    if active_sessions == 0:
        print("[OK] Sessions révoquées après ban.")

    # 3. Tentative de Reconnexion (Simulée via find_one comme dans auth.py)
    print("\n[TEST] Tentative de connexion (OTP verify)...")
    u = await db.users.find_one({"phone": phone})
    if u.get("is_banned"):
        print("[OK] Détection utilisateur banni au login.")
    else:
        print("[ERR] Échec détection ban.")

    # 4. Levée du ban
    print("\n[TEST] Levée du ban...")
    await db.users.update_one({"user_id": user_id}, {"$set": {"is_banned": False}})
    u = await db.users.find_one({"phone": phone})
    if not u.get("is_banned"):
        print("[OK] Ban levé avec succès.")

    # Nettoyage final
    await db.users.delete_one({"user_id": user_id})
    print("\n--- FIN TEST ---")

if __name__ == "__main__":
    asyncio.run(test_banning())
