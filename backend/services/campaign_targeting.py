from datetime import datetime, timedelta, timezone
from enum import Enum

from pydantic import BaseModel, Field
from pymongo.errors import DuplicateKeyError

from database import db


class CampaignAudience(str, Enum):
    ALL = "all"
    NO_SEND = "no_send"
    FIRST_DELIVERY = "first_delivery"
    REGULAR = "regular"
    RELAY_USERS = "relay_users"
    INACTIVE = "inactive"


class CampaignTargeting(BaseModel):
    audience: CampaignAudience = CampaignAudience.ALL
    min_deliveries: int = Field(default=5, ge=2, le=10000)
    inactive_days: int = Field(default=30, ge=1, le=3650)
    max_exposures: int = Field(default=3, ge=1, le=100)
    frequency_days: int = Field(default=7, ge=1, le=365)
    cooldown_hours: int = Field(default=24, ge=0, le=8760)


AUDIENCE_LABELS = {
    "all": "Tous les comptes des rôles sélectionnés",
    "no_send": "Aucun envoi effectué",
    "first_delivery": "Premier colis livré",
    "regular": "Expéditeurs réguliers",
    "relay_users": "Utilisateurs des relais",
    "inactive": "Expéditeurs sans envoi récent",
}


def targeting_for(campaign):
    return CampaignTargeting.model_validate(campaign.get("targeting") or {})


def utc(value):
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    if not isinstance(value, datetime):
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


async def sender_activity(user_ids):
    if not user_ids:
        return {}
    rows = await db.parcels.aggregate([
        {"$match": {"sender_user_id": {"$in": user_ids}}},
        {"$group": {
            "_id": "$sender_user_id",
            "sent": {"$sum": 1},
            "delivered": {"$sum": {"$cond": [{"$eq": ["$status", "delivered"]}, 1, 0]}},
            "relay_deliveries": {"$sum": {"$cond": [{"$and": [
                {"$eq": ["$status", "delivered"]},
                {"$in": ["$delivery_mode", ["home_to_relay", "relay_to_home", "relay_to_relay"]]},
            ]}, 1, 0]}},
            "active": {"$sum": {"$cond": [{"$in": ["$status", ["delivered", "cancelled", "expired", "returned"]]}, 0, 1]}},
            "last_send": {"$max": "$created_at"},
        }},
    ]).to_list(length=len(user_ids))
    return {row["_id"]: row for row in rows}


def audience_matches(policy, activity, now):
    sent = activity.get("sent", 0)
    delivered = activity.get("delivered", 0)
    if policy.audience == CampaignAudience.ALL:
        return True
    if policy.audience == CampaignAudience.NO_SEND:
        return sent == 0
    if policy.audience == CampaignAudience.FIRST_DELIVERY:
        return delivered == 1
    if policy.audience == CampaignAudience.REGULAR:
        return delivered >= policy.min_deliveries
    if policy.audience == CampaignAudience.RELAY_USERS:
        return activity.get("relay_deliveries", 0) > 0
    last_send = utc(activity.get("last_send"))
    return bool(sent > 0 and not activity.get("active", 0) and last_send and last_send <= now - timedelta(days=policy.inactive_days))


async def campaign_audience_matches(campaign, user_id, now):
    policy = targeting_for(campaign)
    if policy.audience == CampaignAudience.ALL:
        return True
    activity = await sender_activity([user_id])
    return audience_matches(policy, activity.get(user_id, {}), now)


def exposures_in_window(event, policy, now):
    since = now - timedelta(days=policy.frequency_days)
    return [item for item in (event or {}).get("exposures", []) if utc(item.get("at")) and utc(item["at"]) > since]


def exposure_allowed(event, policy, now):
    exposures = exposures_in_window(event, policy, now)
    if len(exposures) >= policy.max_exposures:
        return False
    last = utc((event or {}).get("last_shown_at"))
    return not last or now >= last + timedelta(hours=policy.cooldown_hours)


async def campaign_state(user_id, campaign_ids):
    if not campaign_ids:
        return {}
    rows = await db.in_app_campaign_events.find({
        "user_id": user_id, "campaign_id": {"$in": campaign_ids},
        "event_type": {"$in": ["dismiss", "impression", "notification"]},
    }, {"_id": 0}).to_list(length=len(campaign_ids) * 3)
    return {(row["campaign_id"], row["event_type"]): row for row in rows}


async def claim_exposure(campaign, user_id, channel, token, now):
    policy = targeting_for(campaign)
    key = {"campaign_id": campaign["campaign_id"], "user_id": user_id, "event_type": channel}
    existing = await db.in_app_campaign_events.find_one(key)
    if any(item.get("id") == token for item in (existing or {}).get("exposures", [])):
        return True
    if not exposure_allowed(existing, policy, now):
        return False
    if await db.in_app_campaign_events.find_one({**key, "event_type": "dismiss"}):
        return False
    recent = {"$filter": {
        "input": {"$ifNull": ["$exposures", []]}, "as": "view",
        "cond": {"$gt": ["$$view.at", now - timedelta(days=policy.frequency_days)]},
    }}
    try:
        await db.in_app_campaign_events.update_one(key, {"$setOnInsert": {
            **key, "created_at": now, "exposures": [], "unique_counted": False,
        }}, upsert=True)
    except DuplicateKeyError:
        pass
    query = {**key, "exposures.id": {"$ne": token}, "$expr": {"$and": [
        {"$lt": [{"$size": recent}, policy.max_exposures]},
        {"$lte": [{"$ifNull": ["$last_shown_at", datetime(1970, 1, 1, tzinfo=timezone.utc)]}, now - timedelta(hours=policy.cooldown_hours)]},
    ]}}
    try:
        previous = await db.in_app_campaign_events.find_one_and_update(query, [{"$set": {
            **key, "created_at": {"$ifNull": ["$created_at", now]}, "last_shown_at": now,
            "unique_counted": True,
            "exposures": {"$concatArrays": [recent, {"$literal": [{"at": now, "id": token}]}]},
        }}])
    except DuplicateKeyError:
        latest = await db.in_app_campaign_events.find_one(key)
        return any(item.get("id") == token for item in (latest or {}).get("exposures", []))
    if previous is None:
        latest = await db.in_app_campaign_events.find_one(key)
        return any(item.get("id") == token for item in (latest or {}).get("exposures", []))
    if previous.get("unique_counted") is False and channel == "impression":
        await db.in_app_campaigns.update_one({"campaign_id": campaign["campaign_id"]}, {"$inc": {"impressions_count": 1}})
    return True


async def release_exposure(campaign_id, user_id, channel, token):
    await db.in_app_campaign_events.update_one({"campaign_id": campaign_id, "user_id": user_id, "event_type": channel}, [
        {"$set": {"exposures": {"$filter": {"input": {"$ifNull": ["$exposures", []]}, "as": "view", "cond": {"$ne": ["$$view.id", token]}}}}},
        {"$set": {"last_shown_at": {"$ifNull": [{"$max": "$exposures.at"}, datetime(1970, 1, 1, tzinfo=timezone.utc)]}}},
    ])
