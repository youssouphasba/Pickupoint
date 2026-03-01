import asyncio
import httpx
import sys

async def test_api():
    base_url = "https://pickupoint-production.up.railway.app"
    try:
        print("Logging in as Relay Agent...")
        async with httpx.AsyncClient() as client:
            login_res = await client.post(
                f"{base_url}/api/auth/verify-otp",
                data={"username": "+221770000002", "password": "123"}, # wait... the swagger for verify-otp might expect OAuth2 password form!
                # Wait, our `auth.py` says `body: OTPVerify`, which means it expects JSON!
                json={"phone": "+221770000002", "code": "123456"}
            )
            
            if login_res.status_code != 200:
                print(f"Login failed: {login_res.text}")
                return
                
            token = login_res.json()["access_token"]
            headers = {"Authorization": f"Bearer {token}"}
            print("Login successful. Got token.")
            
            parcel_id = "prc_c68a8e77a425"
            
            print("\n--- Test 3: POST with explicit Content-Length 0 ---")
            headers["Content-Length"] = "0"
            res3 = await client.post(f"{base_url}/api/parcels/{parcel_id}/drop-at-relay", headers=headers)
            print(f"Status: {res3.status_code}")
            print(f"Body: {res3.text}")

    except Exception as e:
        print(f"Fatal Error: {e}")

if __name__ == "__main__":
    asyncio.run(test_api())
