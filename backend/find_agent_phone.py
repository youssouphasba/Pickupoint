import asyncio
import os
import sys

# Configuration pour pouvoir importer les modules du backend
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db

async def get_relay_agent_phone(relay_id):
    await connect_db()
    print(f"\n--- RECHERCHE AGENT POUR LE RELAIS {relay_id} ---")
    
    relay = await db.relay_points.find_one({"relay_id": relay_id})
    if not relay:
        print(f"❌ Relais {relay_id} non trouvé.")
        return
        
    owner_id = relay.get("owner_user_id")
    print(f"Propriétaire ID: {owner_id}")
    
    user = await db.users.find_one({"user_id": owner_id})
    if not user:
        print(f"❌ Utilisateur {owner_id} non trouvé.")
        return
        
    print(f"✅ Téléphone de l'agent : {user.get('phone')}")

if __name__ == "__main__":
    # On récupère l'ID du relais depuis l'output de l'utilisateur
    target_relay_id = "rly_2058327bdcc7"
    asyncio.run(get_relay_agent_phone(target_relay_id))
