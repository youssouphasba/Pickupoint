import asyncio
import httpx
import sys
import os

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from core.security import create_access_token

async def test_api():
    base_url = "https://pickupoint-production.up.railway.app"
    try:
        await connect_db()
        print("Getting token for Relay Agent from DB...")
        user = await db.users.find_one({"phone": "+221770000002"})
        if not user:
            print("User not found in DB")
            return
            
        token = create_access_token({"sub": user["user_id"], "role": user["role"]})
        headers = {"Authorization": f"Bearer {token}"}
        print(f"Token generated: {token[:20]}...")
        
        # Test finding a parcel that works with drop_at_relay
        # A parcel in CREATED state
        parcel = await db.parcels.find_one({'status': 'created'})
        if not parcel:
            print("No parcel in CREATED status to test.")
            return
            
        parcel_id = parcel['parcel_id']
        print(f"\nTesting dropAtRelay on {parcel_id}")
        
        async with httpx.AsyncClient() as client:
            drop_res = await client.post(f"{base_url}/api/parcels/{parcel_id}/drop-at-relay", headers=headers)
            print(f"DropAtRelay Status: {drop_res.status_code}")
            print(f"DropAtRelay Body: {drop_res.text}")
            
            # test also with an empty JSON
            drop_res2 = await client.post(f"{base_url}/api/parcels/{parcel_id}/drop-at-relay", headers=headers, json={})
            print(f"DropAtRelay (json={{}}) Status: {drop_res2.status_code}")
            print(f"DropAtRelay (json={{}}) Body: {drop_res2.text}")

    except Exception as e:
        print(f"Fatal Error: {e}")

if __name__ == "__main__":
    asyncio.run(test_api())
