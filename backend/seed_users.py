import asyncio
import os
import uuid
from datetime import datetime, timezone

from motor.motor_asyncio import AsyncIOMotorClient

MONGO_URL = os.environ.get("MONGO_URL", "mongodb://localhost:27017")
DB_NAME = os.environ.get("DB_NAME", "Pickupoint")

# Numéros de tests officiels (OTP sera toujours 123456 pour ces numéros grace au DEBUG)
TEST_USERS = [
    {
        "phone": "+221770000000",
        "name": "Jane Doe (Admin)",
        "role": "admin",
        "email": "admin@pickupoint.sn"
    },
    {
        "phone": "+221770000001",
        "name": "Moussa (Livreur)",
        "role": "driver",
        "email": "livreur@pickupoint.sn"
    },
    {
        "phone": "+221770000002",
        "name": "Boutique Relais 1",
        "role": "relay_agent",
        "email": "relais@pickupoint.sn"
    },
    {
        "phone": "+221770000003",
        "name": "Fatou (Client)",
        "role": "client",
        "email": "client@pickupoint.sn"
    }
]

async def seed_test_accounts():
    print(f"🔌 Connexion à MongoDB : {DB_NAME}")
    client = AsyncIOMotorClient(MONGO_URL)
    db = client[DB_NAME]
    
    now = datetime.now(timezone.utc)
    
    # 1. Créer le point relais pour la boutique (+221770000002)
    relay_id = f"rly_{uuid.uuid4().hex[:12]}"
    
    print("\n---------- CRÉATION DES COMPTES ------------")
    for u in TEST_USERS:
        # Vérifier si existe déjà
        existing = await db.users.find_one({"phone": u["phone"]})
        if existing:
            print(f"⏩ {u['role'].upper()} ({u['phone']}) existe déjà.")
            
            # On force la mise à jour des infos pour être sûr
            update_data = {
                "role": u["role"],
                "name": u["name"]
            }
            if u["role"] == "relay_agent":
               update_data["relay_point_id"] = relay_id
               
            await db.users.update_one({"_id": existing["_id"]}, {"$set": update_data})
            continue

        user_id = f"usr_{uuid.uuid4().hex[:12]}"
        
        user_doc = {
            "user_id":           user_id,
            "phone":             u["phone"],
            "name":              u["name"],
            "email":             u["email"],
            "role":              u["role"],
            "is_active":         True,
            "is_phone_verified": True,
            "relay_point_id":    relay_id if u["role"] == "relay_agent" else None,
            "store_id":          None,
            "external_ref":      None,
            "language":          "fr",
            "currency":          "XOF",
            "country_code":      "SN",
            "created_at":        now,
            "updated_at":        now,
        }
        await db.users.insert_one(user_doc)
        print(f"✅ Créé : {u['role'].upper():<12} -> {u['phone']} ({u['name']})")
        
        # 1.1 Si c'est le relais, on insère la boutique dans la DB 'relay_points'
        if u["role"] == "relay_agent":
            await db.relay_points.update_one(
                {"relay_id": relay_id},
                {"$setOnInsert": {
                    "relay_id": relay_id,
                    "owner_user_id": user_id,
                    "name": "Point Relais Médina",
                    "address": "Médina Rue 11x12",
                    "city": "Dakar",
                    "location": {"type": "Point", "coordinates": [-17.456, 14.678]}, # lng, lat
                    "is_active": True,
                    "created_at": now
                }},
                upsert=True
            )

    print("\n-------------------------------------------")
    print("🚀 TERMINÉ ! COMPTES DE TEST CRÉÉS OU MIS À JOUR.")
    client.close()

if __name__ == "__main__":
    asyncio.run(seed_test_accounts())
