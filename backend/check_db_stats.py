import asyncio
import os
import sys

# Configuration pour pouvoir importer les modules du backend
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db

async def check_stats():
    await connect_db()
    print("CHECK_START")
    try:
        users = await db.users.count_documents({})
        clients = await db.users.count_documents({"role": "client"})
        drivers = await db.users.count_documents({"role": "driver"})
        relays = await db.relay_points.count_documents({})
        
        print(f"RES:TOTAL_USERS:{users}")
        print(f"RES:CLIENTS:{clients}")
        print(f"RES:DRIVERS:{drivers}")
        print(f"RES:RELAYS:{relays}")
    except Exception as e:
        print(f"ERROR:{e}")
    print("CHECK_END")

if __name__ == "__main__":
    asyncio.run(check_stats())
