import asyncio
import os
import sys
from datetime import datetime, timezone

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from models.common import ParcelStatus, UserRole
from services.parcel_service import transition_status, _parcel_id, _create_delivery_mission

async def test_flow():
    await connect_db()
    print("--- DEBUT TEST CONTROLE PAIEMENT & ADMIN ---")
    
    # 1. Création d'un colis de test (Unpaid)
    p_id = f"test_{_parcel_id()}"
    parcel_doc = {
        "parcel_id": p_id,
        "status": ParcelStatus.OUT_FOR_DELIVERY.value, # On simule un colis déjà en cours
        "payment_status": "pending",
        "delivery_mode": "home_to_home",
        "delivery_code": "1234",
        "created_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc)
    }
    await db.parcels.insert_one(parcel_doc)
    print(f"[OK] Colis créé: {p_id} (Payment: pending)")

    # 2. Test Suspension par Admin
    print("\n[TEST] Suspension Admin...")
    # On utilise transition_status directement pour simuler l'endpoint admin
    await transition_status(p_id, ParcelStatus.SUSPENDED, actor_id="admin_1", actor_role="admin")
    
    # Vérifier que le pickup ou delivery échouerait (on simule l'appel à transition_status depuis l'app livreur)
    try:
        # On va directement tester via transition_status car c'est là que la logique de blocage 
        # (en plus des routers) devrait résider idéalement, mais ici j'ai mis le blocage dans les routers.
        # Donc pour tester, je vais vérifier le statut.
        p = await db.parcels.find_one({"parcel_id": p_id})
        if p["status"] == ParcelStatus.SUSPENDED.value:
            print("[OK] Nouveau statut est SUSPENDED")
    except Exception as e:
        print(f"[ERR] Erreur suspension: {e}")

    # 3. Test Levée Suspension
    print("\n[TEST] Levée Suspension...")
    await transition_status(p_id, ParcelStatus.OUT_FOR_DELIVERY, actor_id="admin_1", actor_role="admin")
    p = await db.parcels.find_one({"parcel_id": p_id})
    print(f"[OK] Retour au statut: {p['status']}")

    # 4. Test Livraison Non-Bloquante (Unpaid)
    # Dans le code réel, c'est le router qui permet la livraison unpaid.
    # Ici, on vérifie juste que transition_status permet de passer à DELIVERED.
    print("\n[TEST] Livraison sans paiement...")
    await transition_status(p_id, ParcelStatus.DELIVERED, actor_id="driver_1", actor_role="driver")
    p = await db.parcels.find_one({"parcel_id": p_id})
    if p["status"] == ParcelStatus.DELIVERED.value:
         print("[OK] Colis livré malgré payment_status='pending'")

    # Nettoyage
    await db.parcels.delete_one({"parcel_id": p_id})
    await db.parcel_events.delete_many({"parcel_id": p_id})
    print("\n--- FIN TEST ---")

if __name__ == "__main__":
    asyncio.run(test_flow())
