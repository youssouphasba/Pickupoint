import asyncio
import os
import sys

# Configuration pour pouvoir importer les modules du backend
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db

async def list_test_users():
    await connect_db()
    print("\n--- UTILISATEURS DE TEST DISPONIBLES ---")
    
    roles = ["client", "driver", "relay_agent", "admin"]
    
    for role in roles:
        print(f"\nRole: {role.upper()}")
        users = await db.users.find({"role": role}).limit(3).to_list(length=3)
        if not users:
            print("  (Aucun utilisateur trouvé)")
        for u in users:
            phone = u.get("phone", "N/A")
            user_id = u.get("user_id", "N/A")
            print(f"  - {phone} (ID: {user_id})")

if __name__ == "__main__":
    asyncio.run(list_test_users())
