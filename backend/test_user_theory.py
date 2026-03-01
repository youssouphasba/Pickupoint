import asyncio
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db

async def verify_theory():
    await connect_db()
    print("--- VÉRIFICATION DE LA THÉORIE DU USER ---")
    
    # Check the user we are testing with (+221770000002)
    agent_user = await db.users.find_one({"phone": "+221770000002"})
    if not agent_user:
        print("Test agent not found!")
        return
        
    actual_relay_id = agent_user.get("relay_point_id")
    print(f"L'agent +221770000002 est assigné au relais : {actual_relay_id}")
    
    # Check the latest CREATED parcel
    parcel = await db.parcels.find_one({"status": "created"}, sort=[("created_at", -1)])
    if not parcel:
        print("Aucun colis avec statut CREATED trouvé.")
        return
        
    print(f"\nColis test généré : {parcel['parcel_id']}")
    print(f"Relais Origine ATTENDU par le colis : {parcel['origin_relay_id']}")
    
    if actual_relay_id != parcel['origin_relay_id']:
        print("\n❌ THÉORIE CONFIRMÉE !")
        print(f"L'agent essaie de scanner un colis qui doit être déposé au relais {parcel['origin_relay_id']},")
        print(f"MAIS il travaille pour le relais {actual_relay_id}.")
        print("C'est pourquoi le backend retourne une erreur 400 (Logique métier : 'Ceci n'est pas votre colis').")
    else:
        print("\n⚠️ Théorie invalide (ou alors c'est tombé par hasard sur le bon relais).")

if __name__ == "__main__":
    asyncio.run(verify_theory())
