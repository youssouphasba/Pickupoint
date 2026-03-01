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
    
    # 1. Sélectionner des utilisateurs et des relais au hasard
    client = await db.users.find_one({"role": "client"})
    driver = await db.users.find_one({"role": "driver"})
    relays = await db.relay_points.find().limit(2).to_list(length=2)
    
    if not client or not driver or len(relays) < 2:
        print("Erreur : Il manque des données (client, livreur ou 2 relais) dans la DB pour simuler.")
        return
        
    origin_relay = relays[0]
    dest_relay = relays[1]
    
    # Trouver les agents de ces relais (le owner pour simplifier)
    agent_origin = await db.users.find_one({"user_id": origin_relay["owner_user_id"]})
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
    
    # Fonction helper pour les transitions rapides
    async def fast_transition(status, role, user):
        await asyncio.sleep(1) # Simuler un petit délai
        await db.parcels.update_one({"parcel_id": parcel_id}, {"$set": {"status": status.value}})
        await db.parcel_events.insert_one({
            "event_id": _event_id(),
            "parcel_id": parcel_id,
            "event_type": "STATUS_CHANGED",
            "to_status": status.value,
            "actor_id": user["user_id"],
            "actor_role": role,
            "created_at": datetime.now(timezone.utc)
        })
        print(f"✅ --> Changement de statut: {status.name} (par {role})")
        
    print(f"🏪 2. Dépôt au relais origine '{origin_relay['name']}'")
    await fast_transition(ParcelStatus.DROPPED_AT_ORIGIN_RELAY, "relay_agent", agent_origin)
    
    print(f"🚚 3. Livreur '{driver['phone']}' récupère le colis")
    await fast_transition(ParcelStatus.IN_TRANSIT, "driver", driver)
    
    print(f"🏪 4. Livreur dépose au relais destination '{dest_relay['name']}'")
    await fast_transition(ParcelStatus.AT_DESTINATION_RELAY, "driver", driver)
    
    print(f"📦 5. Agent du relais '{dest_relay['name']}' réceptionne")
    await fast_transition(ParcelStatus.AVAILABLE_AT_RELAY, "relay_agent", agent_dest)
    
    print(f"🤝 6. Destinataire donne le code {delivery_code} pour retirer")
    await db.parcels.update_one({"parcel_id": parcel_id}, {"$set": {"status": ParcelStatus.DELIVERED.value}})
    await db.parcel_events.insert_one({
        "event_id": _event_id(), "parcel_id": parcel_id, "event_type": "STATUS_CHANGED",
        "to_status": ParcelStatus.DELIVERED.value, "actor_id": agent_dest["user_id"], 
        "actor_role": "relay_agent", "created_at": datetime.now(timezone.utc),
        "notes": f"Livré avec code {delivery_code}"
    })
    print(f"✅ --> Changement de statut: DELIVERED (par relay_agent)")
    print(f"\n🎉 Scénario 1 terminé ! Retrouvez le colis {parcel_id} dans l'application.")

async def main():
    print("Démarrage du simulateur de scénarios PickuPoint...")
    print("Ce script crée de fausses données réelles pour tester l'UI sans mocks Frontend.")
    await simulate_scenario_1_relay_to_relay()
    
if __name__ == "__main__":
    asyncio.run(main())
