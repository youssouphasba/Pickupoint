import asyncio
import os
import sys

# Ajouter le chemin du backend
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from database import connect_db, db, close_db

async def update_role(phone, new_role):
    print(f"Connexion à la base de données...")
    await connect_db()
    
    print(f"Recherche de l'utilisateur {phone}...")
    user = await db.users.find_one({"phone": phone})
    
    if not user:
        print(f"Utilisateur {phone} non trouvé !")
    else:
        print(f"Utilisateur trouvé. Rôle actuel: {user.get('role')}")
        result = await db.users.update_one(
            {"phone": phone},
            {"$set": {"role": new_role}}
        )
        print(f"Mise à jour effectuée. Documents modifiés: {result.modified_count}")
        
    await close_db()

if __name__ == "__main__":
    phone = "+221770000002"
    role = "relay_agent"
    print(f"Démarrage de la mise à jour pour {phone} -> {role}")
    asyncio.run(update_role(phone, role))
