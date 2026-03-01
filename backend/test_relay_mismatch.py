import asyncio
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db

async def main():
    await connect_db()
    
    print("Checking origin relay logic...")
    # Find the agent you are using logging in as +221770000002
    agent = await db.users.find_one({"phone": "+221770000002"})
    if not agent:
        print("Agent +221770000002 not found")
        return
        
    print(f"Agent ID: {agent['user_id']}")
    print(f"Agent Name: {agent.get('name')}")
    print(f"Agent Relay ID: {agent.get('relay_point_id')}")
    
    # Check what relay the parcel expects
    parcel = await db.parcels.find_one({'status': 'created'})
    if not parcel:
        print("No created parcel to test")
        return
        
    print(f"Parcel ID: {parcel['parcel_id']}")
    print(f"Expected Origin Relay: {parcel.get('origin_relay_id')}")
    print(f"Expected Destination Relay: {parcel.get('destination_relay_id')}")
    
    # Verify the code
    if agent.get('relay_point_id') != parcel.get('origin_relay_id'):
        print("\n❌ MISMATCH! The parcel is expecting a different origin relay than the one logging in!")

if __name__ == "__main__":
    asyncio.run(main())
