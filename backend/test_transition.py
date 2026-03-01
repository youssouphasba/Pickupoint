import asyncio
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from services.parcel_service import transition_status
from models.common import ParcelStatus

async def main():
    await connect_db()
    # Find a parcel in CREATED state
    parcel = await db.parcels.find_one({'status': 'created'})
    if not parcel:
        print("No parcel in CREATED state found.")
        return
        
    print(f"Testing transition for parcel {parcel['parcel_id']}")
    try:
        updated = await transition_status(
            parcel_id=parcel['parcel_id'],
            new_status=ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
            actor_id='usr_6356c7aa889e', # Using the relay agent test user ID
            actor_role='relay_agent'
        )
        print("✅ Transition SUCCESSFUL")
    except Exception as e:
        print(f"❌ Transition FAILED with error: {str(e)}")
        print(f"Exception type: {type(e)}")

if __name__ == "__main__":
    asyncio.run(main())
