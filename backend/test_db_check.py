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
        
    print(f"Parcel ID: {parcel['parcel_id']}")
    print(f"Status: {parcel['status']}")
    print(f"Tracking Code: {parcel.get('tracking_code')}")

if __name__ == "__main__":
    asyncio.run(main())
