import asyncio
from motor.motor_asyncio import AsyncIOMotorClient
from config import settings
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

async def test_pin():
    client = AsyncIOMotorClient(settings.MONGO_URL)
    db = client[settings.DB_NAME]
    
    pin = "1234"
    h1 = pwd_context.hash(pin)
    h2 = pwd_context.hash(pin)
    
    user1 = {
        "user_id": "usr_test100",
        "phone": "+221779998881",
        "name": "Test1",
        "pin_hash": h1,
        "created_at": "now",
        "updated_at": "now"
    }
    user2 = {
        "user_id": "usr_test101",
        "phone": "+221779998882",
        "name": "Test2",
        "pin_hash": h1, 
        "created_at": "now",
        "updated_at": "now"
    }
    
    try:
        await db.users.delete_many({"user_id": {"$in": ["usr_test100", "usr_test101"]}})
        await db.users.delete_many({"phone": {"$in": ["+221779998881", "+221779998882"]}})
        
        await db.users.insert_one(user1)
        print("User 1 inserted with hash:", h1)
        
        await db.users.insert_one(user2)
        print("User 2 inserted successfully with the SAME pin hash:", h1)
        
    except Exception as e:
        print("ERROR:", e)

if __name__ == "__main__":
    asyncio.run(test_pin())
