"""
simulate_4_scenarios_v2.py -- Cree 4 scenarios de test complets :
1. R2R Inter-Villes (Dakar -> Thies)
2. H2R (Collecte Domicile -> Relais)
3. R2H (Relais -> Domicile avec confirmation GPS)
4. H2H (Domicile -> Domicile complet)

Usage :
    cd pickupoint/backend
    python simulate_4_scenarios_v2.py
"""
import asyncio
import os
import sys
import random
import uuid
from datetime import datetime, timezone

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from models.common import ParcelStatus, DeliveryMode
from services.parcel_service import _parcel_id, _event_id

# -- Configuration des Acteurs --
ACCOUNTS = {
    "moussa":    {"phone": "+221770000001", "name": "Moussa (Livreur)",            "role": "driver"},
    "agent_med": {"phone": "+221770000002", "name": "Relais Medina (Dakar Agent)", "role": "relay_agent"},
    "fatou":     {"phone": "+221770000003", "name": "Fatou Diallo (Expeditrice)",   "role": "client"},
    "ibrahima":  {"phone": "+221770000004", "name": "Ibrahima Sow (Destinataire)",  "role": "client"},
    "agent_plat":{"phone": "+221770000005", "name": "Relais Plateau (Dakar Agent)", "role": "relay_agent"},
    "agent_thes":{"phone": "+221770000006", "name": "Relais Escale (Thies Agent)",  "role": "relay_agent"},
}

RELAYS = {
    "medina": {
        "name": "Relais Medina (Dakar)",
        "address": {"label": "Medina, Rue 11", "city": "Dakar", "geopin": {"lat": 14.6789, "lng": -17.4456}}
    },
    "plateau": {
        "name": "Relais Plateau (Dakar)",
        "address": {"label": "Plateau, Av. Pompidou", "city": "Dakar", "geopin": {"lat": 14.693, "lng": -17.438}}
    },
    "escale": {
        "name": "Relais Escale (Thies)",
        "address": {"label": "Escale, Rue de France", "city": "Thies", "geopin": {"lat": 14.791, "lng": -16.935}}
    }
}

async def _ensure_user(phone: str, name: str, role: str) -> dict:
    user = await db.users.find_one({"phone": phone})
    if user: return user
    doc = {
        "user_id": f"usr_{uuid.uuid4().hex[:12]}",
        "phone": phone, "name": name, "role": role,
        "is_active": True, "created_at": datetime.now(timezone.utc)
    }
    await db.users.insert_one(doc)
    return doc

async def _ensure_relay(owner_id: str, info: dict) -> dict:
    relay = await db.relay_points.find_one({"owner_user_id": owner_id})
    if relay: return relay
    doc = {
        "relay_id": f"rly_{uuid.uuid4().hex[:12]}",
        "owner_user_id": owner_id, "name": info["name"], "address": info["address"],
        "is_active": True, "created_at": datetime.now(timezone.utc)
    }
    await db.relay_points.insert_one(doc)
    return doc

async def create_scenario(name: str, mode: DeliveryMode, origin_relay=None, dest_relay=None, origin_loc=None, dest_addr=None):
    now = datetime.now(timezone.utc)
    p_id = _parcel_id()
    t_code = f"PKP-{random.randint(100,999)}-{random.randint(1000,9999)}"
    pickup_code = str(random.randint(100000, 999999))
    pin_code = str(random.randint(1000, 9999))

    doc = {
        "parcel_id": p_id, "tracking_code": t_code, "status": ParcelStatus.CREATED.value,
        "delivery_mode": mode.value, "sender_user_id": "usr_fatou", "recipient_name": "Ibrahima Sow",
        "recipient_phone": "+221770000004", "origin_relay_id": origin_relay, "destination_relay_id": dest_relay,
        "origin_location": origin_loc, "delivery_address": dest_addr, "quoted_price": 2000, "payment_status": "paid",
        "pickup_code": pickup_code, "pin_code": pin_code, "created_at": now, "updated_at": now
    }
    await db.parcels.insert_one(doc)
    print(f"[OK] Scenario '{name}' cree : {t_code}")
    return doc

async def main():
    await connect_db()
    print("--- INITIALISATION DES COMPTES ET RELAIS ---")
    u = {}
    for k, v in ACCOUNTS.items(): u[k] = await _ensure_user(**v)
    
    r = {}
    r["medina"] = await _ensure_relay(u["agent_med"]["user_id"], RELAYS["medina"])
    r["plateau"] = await _ensure_relay(u["agent_plat"]["user_id"], RELAYS["plateau"])
    r["escale"] = await _ensure_relay(u["agent_thes"]["user_id"], RELAYS["escale"])

    print("\n--- CREATION DES SCENARIOS ---")
    
    # 1. R2R Inter-Villes (Dakar Medina -> Thies Escale)
    await create_scenario("1. R2R Inter-Villes", DeliveryMode.RELAY_TO_RELAY, 
                        origin_relay=r["medina"]["relay_id"], dest_relay=r["escale"]["relay_id"])

    # 2. H2R (Collecte Medina -> Relais Plateau)
    await create_scenario("2. H2R Auto-Collecte", DeliveryMode.HOME_TO_RELAY,
                        origin_loc={"label": "Chez Fatou", "city": "Dakar", "geopin": {"lat": 14.68, "lng": -17.44}},
                        dest_relay=r["plateau"]["relay_id"])

    # 3. R2H (Relais Medina -> Domicile Ibrahima)
    await create_scenario("3. R2H GPS-Confirm", DeliveryMode.RELAY_TO_HOME,
                        origin_relay=r["medina"]["relay_id"],
                        dest_addr={"label": "Appart. Ibrahima", "city": "Dakar", "geopin": {"lat": 14.7, "lng": -17.42}})

    # 4. H2H (Domicile -> Domicile)
    await create_scenario("4. H2H Full Flow", DeliveryMode.HOME_TO_HOME,
                        origin_loc={"label": "Boutique Fatou", "city": "Dakar", "geopin": {"lat": 14.675, "lng": -17.435}},
                        dest_addr={"label": "Bureau Ibrahima", "city": "Dakar", "geopin": {"lat": 14.71, "lng": -17.43}})

    print("\n[OK] Tous les scenarios sont prets en base de donnees.")

if __name__ == "__main__":
    asyncio.run(main())
