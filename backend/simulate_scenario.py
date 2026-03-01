import asyncio
import os
import sys
from datetime import datetime, timezone
import random
import uuid

# Configuration pour pouvoir importer les modules du backend
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from models.common import ParcelStatus, DeliveryMode
from services.parcel_service import _parcel_id, _event_id

async def simulate_scenario_1_relay_to_relay():
    """
    Scénario 1 : Relais vers Relais (Le classique)
    1. Client crée le colis
    2. Client dépose au relais (Scan IN)
    3. Livreur récupère au relais (Pickup)
    4. Livreur dépose au relais destination (AT_DESTINATION)
    5. Agent relais valide réception (AVAILABLE)
    6. Destinataire retire son colis (DELIVERED)
    """
    await connect_db()
    print("\n--- DÉMARRAGE SCÉNARIO 1 : RELAY TO RELAY ---")
    
    # 1. Forcer l'utilisation des utilisateurs de test habituels
    client = await db.users.find_one({"phone": "+221701234567"}) or await db.users.find_one({"role": "client"})
    driver = await db.users.find_one({"phone": "+221770000003"}) or await db.users.find_one({"role": "driver"})
    
    # Agent de test pour le relais origine
    agent_origin = await db.users.find_one({"phone": "+221770000002"})
    
    if not client or not driver or not agent_origin:
        print("Erreur : Il manque des utilisateurs de test dans la base (+221770000003 ou +221770000002).")
        return
        
    # Le relais origine DOIT être celui assigné à l'agent de test !
    origin_relay = await db.relay_points.find_one({"relay_id": agent_origin.get("relay_point_id")})
    
    # Un relais destination au hasard (différent de l'origine)
    dest_relay = await db.relay_points.find_one({"relay_id": {"$ne": origin_relay["relay_id"]}})
    
    if not origin_relay or not dest_relay:
        print("Erreur : Impossible de trouver le relais d'origine de l'agent ou un relais de destination.")
        return
        
    agent_dest = await db.users.find_one({"user_id": dest_relay["owner_user_id"]})
    
    now = datetime.now(timezone.utc)
    parcel_id = _parcel_id()
    tracking_code = f"TRK-{random.randint(100000, 999999)}"
    delivery_code = f"{random.randint(100000, 999999)}"
    
    print(f"📦 1. Client '{client['phone']}' crée le colis {parcel_id} (Tracking: {tracking_code})")
    parcel_doc = {
        "parcel_id": parcel_id,
        "tracking_code": tracking_code,
        "sender_user_id": client["user_id"],
        "recipient_phone": "+221700000000", # Fake
        "recipient_name": "Destinataire Test",
        "delivery_mode": DeliveryMode.RELAY_TO_RELAY.value,
        "origin_relay_id": origin_relay["relay_id"],
        "destination_relay_id": dest_relay["relay_id"],
        "weight_kg": 2.5,
        "quoted_price": 1500,
        "delivery_code": delivery_code,
        "status": ParcelStatus.CREATED.value,
        "created_at": now,
        "updated_at": now,
    }
    await db.parcels.insert_one(parcel_doc)
    
    # Création de l'événement initial
    await db.parcel_events.insert_one({
        "event_id": _event_id(),
        "parcel_id": parcel_id,
        "event_type": "STATUS_CHANGED",
        "to_status": ParcelStatus.CREATED.value,
        "actor_id": client["user_id"],
        "actor_role": "client",
        "created_at": datetime.now(timezone.utc)
    })

    print(f"\n✅ Colis {parcel_id} créé avec succès !")
    print(f"🔑 Code de suivi : {tracking_code}")
    print(f"📍 Relais Origine : {origin_relay['name']} ({origin_relay['relay_id']})")
    print(f"📍 Relais Destination : {dest_relay['name']} ({dest_relay['relay_id']})")
    print(f"\n👉 PROCHAINE ÉTAPE MANUELLE :")
    print(f"Connectez-vous en tant qu'agent du relais '{origin_relay['name']}'")
    print(f"et utilisez le 'Scanner' pour scanner le colis (Status: DROPPED_AT_ORIGIN).")

    """
    # Les étapes suivantes sont désactivées pour permettre le test manuel
    async def fast_transition(status, role, user):
        ...
    """

async def main():
    print("Démarrage du simulateur de scénarios PickuPoint...")
    print("Ce script crée de fausses données réelles pour tester l'UI sans mocks Frontend.")
    await simulate_scenario_1_relay_to_relay()
    
if __name__ == "__main__":
    asyncio.run(main())
