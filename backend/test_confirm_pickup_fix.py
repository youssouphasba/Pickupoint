import asyncio
import os
import sys
from datetime import datetime, timezone

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from models.common import ParcelStatus, UserRole
from services.parcel_service import transition_status

async def test_fix():
    await connect_db()
    
    # Mock data
    p_id = "test_prc_fix_500"
    m_id = "test_msn_fix_500"
    u_id = "test_usr_fix_500"
    
    # Cleanup
    await db.parcels.delete_one({"parcel_id": p_id})
    await db.delivery_missions.delete_one({"mission_id": m_id})
    await db.users.delete_one({"user_id": u_id})
    
    # Setup
    await db.users.insert_one({
        "user_id": u_id,
        "name": "Test Driver",
        "role": "driver",
        "is_active": True
    })
    
    await db.parcels.insert_one({
        "parcel_id": p_id,
        "status": ParcelStatus.CREATED.value,
        "tracking_code": "FIX-500",
        "delivery_mode": "home_to_home",
        "assigned_driver_id": u_id,
        "created_at": datetime.now(timezone.utc)
    })
    
    print(f"Testing transition_status for {p_id}...")
    try:
        actor = {"actor_id": u_id, "actor_role": "driver"}
        await transition_status(
            p_id, 
            ParcelStatus.OUT_FOR_DELIVERY, 
            notes="Test pick-up fix", 
            **actor
        )
        print("[SUCCESS] Transition completed without 500 error.")
        
        # Verify event
        event = await db.parcel_events.find_one({"parcel_id": p_id})
        if event and event.get("actor_role") == "driver":
            print("[SUCCESS] Event recorded with actor_role.")
        else:
            print("[FAILURE] Event missing actor_role or not recorded.")
            
    except Exception as e:
        print(f"[FAILURE] Error during transition: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_fix())
