import asyncio
import os
import sys

# Configuration pour pouvoir importer les modules du backend
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db

async def wipe_all_scenarios():
    """
    Supprime TOUS les colis, missions et evenements pour repartir de zero.
    """
    await connect_db()
    print("\n--- PURGE COMPLETE DES SCENARIOS (Colis, Missions, Evenements) ---")
    
    # 1. Supprimer tous les colis
    parcel_res = await db.parcels.delete_many({})
    print(f"DEL: {parcel_res.deleted_count} colis supprimés.")

    # 2. Supprimer tous les evenements de colis
    event_res = await db.parcel_events.delete_many({})
    print(f"DEL: {event_res.deleted_count} evenements supprimés.")

    # 3. Supprimer toutes les missions (deliveries)
    delivery_res = await db.delivery_missions.delete_many({})
    print(f"DEL: {delivery_res.deleted_count} missions de livraison supprimées.")

    # 4. Réinitialiser la charge des relais (current_load)
    await db.relay_points.update_many({}, {"$set": {"current_load": 0}})
    print("RES: Charge des relais réinitialisée à 0.")

    print("\n[OK] Base de données nettoyée. Vous pouvez relancer simulate_4_scenarios_v2.py ou créer de nouveaux colis.")

if __name__ == "__main__":
    asyncio.run(wipe_all_scenarios())
