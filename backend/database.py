import logging
from motor.motor_asyncio import AsyncIOMotorClient
from pymongo import IndexModel, ASCENDING
from pymongo.errors import OperationFailure
from config import settings

logger = logging.getLogger(__name__)

client: AsyncIOMotorClient = None
_db_instance = None


class _DbProxy:
    """
    Proxy transparent vers l'instance Motor.
    Permet aux services de faire `from database import db` AVANT connect_db().
    db.collection → délégué à _db_instance.collection au moment de l'appel.
    """
    def __getattr__(self, name):
        if _db_instance is None:
            raise RuntimeError("Database not connected. Call connect_db() first.")
        return getattr(_db_instance, name)

    def __getitem__(self, name):
        if _db_instance is None:
            raise RuntimeError("Database not connected. Call connect_db() first.")
        return _db_instance[name]


db = _DbProxy()


def get_db():
    return _db_instance


def get_client():
    """Retourne le client Motor sous-jacent (pour les sessions / transactions)."""
    return client


async def connect_db():
    global client, _db_instance
    client = AsyncIOMotorClient(
        settings.MONGO_URL,
        serverSelectionTimeoutMS=5000,
        connectTimeoutMS=10000,
    )
    _db_instance = client[settings.DB_NAME]
    logger.info(f"Connected to MongoDB: {settings.DB_NAME}")
    try:
        await create_indexes()
    except Exception as e:
        logger.warning(f"Could not create indexes (non-blocking): {e}")


async def close_db():
    global client
    if client:
        client.close()
        logger.info("MongoDB connection closed")


async def create_indexes():
    collections_to_index = {
        "users": [
            IndexModel([("user_id", 1)], unique=True),
            IndexModel([("phone", 1)], unique=True),
            IndexModel([("email", 1)], sparse=True),
            IndexModel([("role", 1)]),
        ],
        "otps": [
            IndexModel([("phone", 1)]),
            IndexModel([("expires_at", 1)], expireAfterSeconds=0),
        ],
        "user_sessions": [
            IndexModel([("refresh_token", 1)], unique=True),
            IndexModel([("user_id", 1)]),
            IndexModel([("expires_at", 1)], expireAfterSeconds=0),
        ],
        "relay_points": [
            IndexModel([("relay_id", 1)], unique=True),
            IndexModel([("owner_user_id", 1)]),
            IndexModel([("is_active", 1)]),
        ],
        "parcels": [
            IndexModel([("parcel_id", 1)], unique=True),
            IndexModel([("tracking_code", 1)], unique=True),
            IndexModel([("sender_user_id", 1)]),
            IndexModel([("recipient_phone", 1)]),
            IndexModel([("origin_relay_id", 1)]),
            IndexModel([("destination_relay_id", 1)]),
            IndexModel([("status", 1)]),
            IndexModel([("assigned_driver_id", 1)]),
            IndexModel([("created_at", 1)]),
        ],
        "parcel_events": [
            IndexModel([("parcel_id", 1)]),
            IndexModel([("created_at", 1)]),
        ],
        "delivery_missions": [
            IndexModel([("mission_id", 1)], unique=True),
            IndexModel([("driver_id", 1)]),
            IndexModel([("parcel_id", 1)]),
            IndexModel([("status", 1)]),
        ],
        "pricing_zones": [
            IndexModel([("zone_id", 1)], unique=True),
        ],
        "pricing_rules": [
            IndexModel([("rule_id", 1)], unique=True),
            IndexModel([("delivery_mode", 1)]),
        ],
        "wallets": [
            IndexModel([("wallet_id", 1)], unique=True),
            IndexModel([("owner_id", 1)], unique=True),
        ],
        "wallet_transactions": [
            IndexModel([("tx_id", 1)], unique=True),
            IndexModel([("wallet_id", 1)]),
            IndexModel([("parcel_id", 1)]),
            IndexModel([("reference", 1)]),
            IndexModel([("created_at", 1)]),
        ],
        "wallet_topups": [
            IndexModel([("topup_id", 1)], unique=True),
            IndexModel([("owner_id", 1)]),
            IndexModel([("provider_session_id", 1)]),
        ],
        "payout_requests": [
            IndexModel([("payout_id", 1)], unique=True),
            IndexModel([("wallet_id", 1)]),
            IndexModel([("status", 1)]),
        ],
        "notifications": [
            IndexModel([("user_id", 1)]),
            IndexModel([("created_at", 1)]),
        ],
        "notification_broadcasts": [
            IndexModel([("broadcast_id", 1)], unique=True),
            IndexModel([("created_at", -1)]),
            IndexModel([("created_by", 1)]),
        ],
        "referrals": [
            IndexModel([("referral_id", 1)], unique=True),
            IndexModel([("sponsor_user_id", 1)]),
            IndexModel([("referred_user_id", 1)], unique=True),
            IndexModel([("referral_code", 1)]),
            IndexModel([("status", 1)]),
            IndexModel([("created_at", -1)]),
        ],
        "whatsapp_support_conversations": [
            IndexModel([("conversation_id", 1)], unique=True),
            IndexModel([("phone", 1)]),
            IndexModel([("matched_user_id", 1)]),
            IndexModel([("matched_parcel_id", 1)]),
            IndexModel([("status", 1)]),
            IndexModel([("last_message_at", -1)]),
        ],
        "whatsapp_support_messages": [
            IndexModel([("message_id", 1)], unique=True),
            IndexModel([("whatsapp_message_id", 1)], unique=True, sparse=True),
            IndexModel([("conversation_id", 1), ("created_at", 1)]),
            IndexModel([("matched_user_id", 1)]),
            IndexModel([("matched_parcel_id", 1)]),
        ],
        "legal_contents": [
            IndexModel([("document_type", 1)], unique=True),
        ],
    }

    await _repair_ttl_index("otps", "expires_at_1", "expires_at", 0)
    await _repair_ttl_index("user_sessions", "expires_at_1", "expires_at", 0)

    for collection_name, index_models in collections_to_index.items():
        try:
            await _db_instance[collection_name].create_indexes(index_models)
            logger.info(f"Indexes created for collection: {collection_name}")
        except Exception as e:
            logger.error(f"Failed to create indexes for collection {collection_name}: {e}")

    logger.info("All MongoDB indexes creation attempts completed.")


async def _repair_ttl_index(collection_name: str, index_name: str, field_name: str, expire_after_seconds: int):
    collection = _db_instance[collection_name]
    try:
        indexes = await collection.index_information()
        existing = indexes.get(index_name)
        if not existing:
            return
        key = existing.get("key")
        has_same_key = key == [(field_name, 1)] or key == [(field_name, ASCENDING)]
        has_ttl = existing.get("expireAfterSeconds") == expire_after_seconds
        if has_same_key and not has_ttl:
            await collection.drop_index(index_name)
            logger.warning(
                "Dropped incompatible TTL index %s.%s before recreation",
                collection_name,
                index_name,
            )
    except OperationFailure as e:
        logger.error("Failed to inspect TTL index %s.%s: %s", collection_name, index_name, e)
