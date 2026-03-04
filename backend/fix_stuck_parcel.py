import asyncio
import os
import sys
from datetime import datetime, timezone

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from models.common import ParcelStatus

async def fix_stuck_parcel():
    await connect_db()
    
    m_id = 'msn_92b45102ab66'
    mission = await db.delivery_missions.find_one({'mission_id': m_id})
    
    if not mission:
        print(f"Mission {m_id} not found.")
        return

    p_id = mission['parcel_id']
    parcel = await db.parcels.find_one({'parcel_id': p_id})
    
    print(f"Current Mission Status: {mission.get('status')}")
    print(f"Current Parcel Status: {parcel.get('status')}")

    # If the mission is IN_PROGRESS but parcel is still CREATED, it's out of sync
    if mission.get('status') == 'in_progress' and parcel.get('status') == 'created':
        print(f"Parcel {p_id} is stuck in CREATED despite mission being IN_PROGRESS. Fixing...")
        
        # Manually transition parcel to OUT_FOR_DELIVERY (H2H assumption)
        await db.parcels.update_one(
            {'parcel_id': p_id},
            {'$set': {
                'status': ParcelStatus.OUT_FOR_DELIVERY.value,
                'updated_at': datetime.now(timezone.utc)
            }}
        )
        # Record event manually since transition_status would have failed
        from services.parcel_service import _record_event
        await _record_event(
            parcel_id=p_id,
            event_type="STATUS_CHANGED",
            from_status=ParcelStatus.CREATED,
            to_status=ParcelStatus.OUT_FOR_DELIVERY,
            actor_id=mission.get('driver_id'),
            actor_role='driver',
            notes="Correction manuelle après erreur 500 sur pickup"
        )
        print("Fixed! Tracking should now work.")
    else:
        print("Statuses are in sync or don't match the 'stuck' pattern.")

if __name__ == "__main__":
    asyncio.run(fix_stuck_parcel())
