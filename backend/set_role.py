import asyncio
import os
import sys

from motor.motor_asyncio import AsyncIOMotorClient

# Utiliser la même URL que le backend, ou celle de la production
MONGO_URL = os.environ.get("MONGO_URL", "mongodb://localhost:27017")
DB_NAME = os.environ.get("DB_NAME", "Pickupoint")

async def force_role(phone: str, role: str):
    client = AsyncIOMotorClient(MONGO_URL)
    db = client[DB_NAME]
    
    user = await db.users.find_one({"phone": phone})
    if not user:
        print(f"❌ Utilisateur avec le numéro {phone} introuvable.")
        print("Veuillez d'abord vous connecter une première fois sur l'application avec ce numéro.")
        client.close()
        return

    result = await db.users.update_one(
        {"phone": phone},
        {"$set": {"role": role}}
    )
    
    if result.modified_count > 0 or result.matched_count > 0:
        print(f"✅ Rôle mis à jour : {phone} est maintenant '{role}' !")
    else:
        print("⚠️ Aucune modification apportée.")
    
    client.close()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage : python set_role.py <numero_telephone> <role>")
        print("Roles possibles : admin, client, relay_agent, driver")
        print("Exemple : python set_role.py +22177xxxxxxxx relay_agent")
        sys.exit(1)
    
    phone_arg = sys.argv[1]
    role_arg = sys.argv[2]
    
    # Assurer le + devant
    if not phone_arg.startswith('+'):
        phone_arg = "+" + phone_arg
        
    asyncio.run(force_role(phone_arg, role_arg))
