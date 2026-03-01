import asyncio
import os
import sys
from datetime import datetime, timezone
import uuid

# Configuration pour pouvoir importer les modules du backend
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from models.common import GeoPin

async def setup_extra_relay():
    await connect_db()
    print("--- AJOUT D'UN DEUXIÈME RELAIS DE TEST ---")
    
    # Trouver le premier relais
    first_relay = await db.relay_points.find_one({})
    if not first_relay:
        print("Erreur: Aucun relais trouvé pour cloner.")
        return

    # Créer un deuxième relais
    relay_id = f"REL-{uuid.uuid4().hex[:8].upper()}"
    new_relay = {
        "relay_id": relay_id,
        "name": "Relais Destination Test",
        "owner_user_id": first_relay["owner_user_id"], # On réutilise le même owner pour simplifier le test
        "phone": "+221779999999",
        "address": {
            "street": "Avenue Cheikh Anta Diop",
            "city": "Dakar",
            "district": "Fann",
            "country": "Sénégal"
        },
        "location": {"lat": 14.6937, "lng": -17.4667},
        "is_active": True,
        "created_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc),
        "description": "Relais de test créé pour la simulation.",
        "opening_hours": {"general": "08:00 - 20:00"}
    }
    
    await db.relay_points.insert_one(new_relay)
    print(f"✅ Nouveau relais créé : {relay_id} ({new_relay['name']})")
    print("Vous pouvez maintenant relancer 'python simulate_scenario.py'.")

if __name__ == "__main__":
    asyncio.run(setup_extra_relay())
