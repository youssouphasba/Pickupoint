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
    DRIVER_NEW = "driver_new"
    DRIVER_FIRST = "driver_first"
    DRIVER_REGULAR = "driver_regular"
    DRIVER_INACTIVE = "driver_inactive"
    RELAY_NEW = "relay_new"
    RELAY_FIRST = "relay_first"
    RELAY_REGULAR = "relay_regular"
    RELAY_INACTIVE = "relay_inactive"


class CampaignTargeting(BaseModel):
    audience: CampaignAudience = CampaignAudience.ALL
    min_deliveries: int = Field(default=5, ge=2, le=10000)
    min_completed_missions: int = Field(default=5, ge=2, le=10000)
    min_processed_parcels: int = Field(default=5, ge=2, le=10000)
    inactive_days: int = Field(default=30, ge=1, le=3650)
    max_exposures: int = Field(default=3, ge=1, le=100)
    frequency_days: int = Field(default=7, ge=1, le=365)
    cooldown_hours: int = Field(default=24, ge=0, le=8760)


AUDIENCE_LABELS = {
    "all": "Sans filtre d’activité",
    "no_send": "Aucun envoi effectué",
    "first_delivery": "Premier colis livré",
    "regular": "Expéditeurs réguliers",
    "relay_users": "Utilisateurs des relais",
    "inactive": "Expéditeurs sans envoi récent",
}

ROLE_AUDIENCES = {
    "client": ["all", "no_send", "first_delivery", "regular", "relay_users", "inactive"],
    "driver": ["all", "driver_new", "driver_first", "driver_regular", "driver_inactive"],
    "relay_agent": ["all", "relay_new", "relay_first", "relay_regular", "relay_inactive"],
}
AUDIENCE_LABELS.update({
    "driver_new": "Aucune mission terminée", "driver_first": "Première mission terminée",
    "driver_regular": "Livreurs réguliers", "driver_inactive": "Livreurs sans activité récente",
    "relay_new": "Aucun colis traité", "relay_first": "Premier colis traité",
    "relay_regular": "Relais réguliers", "relay_inactive": "Relais sans activité récente",
})
AUDIENCE_DETAILS = {
    "all": {"help": "Tous les destinataires sélectionnés, sans condition d’activité."},
    "no_send": {"help": "Comptes qui n’ont jamais créé d’envoi, même annulé."},
    "first_delivery": {"help": "Comptes ayant exactement un colis envoyé puis livré."},
    "regular": {"help": "Comptes ayant atteint le nombre de colis envoyés puis livrés défini ci-dessous.", "threshold_field": "min_deliveries", "threshold_label": "Nombre minimum de colis livrés"},
    "relay_users": {"help": "Comptes ayant envoyé au moins un colis livré avec un relais."},
    "inactive": {"help": "Comptes ayant déjà envoyé un colis, sans colis en cours ni nouvel envoi depuis le délai défini.", "inactive": True},
    "driver_new": {"help": "Livreurs qui n’ont encore terminé aucune mission. Ils peuvent avoir une mission en cours."},
    "driver_first": {"help": "Livreurs ayant exactement une mission terminée."},
    "driver_regular": {"help": "Livreurs ayant atteint le nombre de missions terminées défini ci-dessous.", "threshold_field": "min_completed_missions", "threshold_label": "Nombre minimum de missions terminées"},
    "driver_inactive": {"help": "Livreurs ayant déjà terminé une mission, sans mission en cours ni activité de mission depuis le délai défini.", "inactive": True},
    "relay_new": {"help": "Relais n’ayant encore aucun colis réceptionné, remis ou envoyé avec une action confirmée."},
    "relay_first": {"help": "Relais ayant traité exactement un colis. Plusieurs actions sur ce colis ne le comptent pas plusieurs fois."},
    "relay_regular": {"help": "Relais ayant atteint le nombre de colis distincts traités défini ci-dessous.", "threshold_field": "min_processed_parcels", "threshold_label": "Nombre minimum de colis traités"},
    "relay_inactive": {"help": "Relais ayant déjà traité un colis, sans colis en stock ni action confirmée depuis le délai défini.", "inactive": True},
}


def audience_options(roles):
    values = ROLE_AUDIENCES.get(roles[0], ["all"]) if len(roles) == 1 else ["all"]
    return [{"value": value, "label": AUDIENCE_LABELS[value], **AUDIENCE_DETAILS[value]} for value in values]


def valid_audience_for_roles(roles, audience):
    return any(option["value"] == audience for option in audience_options(roles or ["all"]))


def activity_kind(policy):
    if policy.audience.value.startswith("driver_"):
        return "driver"
    if policy.audience.value.startswith("relay_") and policy.audience != CampaignAudience.RELAY_USERS:
        return "relay_agent"
    return "client"


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


async def driver_activity(user_ids):
    if not user_ids:
        return {}
    activity_fields = ("updated_at", "completed_at", "started_at", "assigned_at", "created_at")
    rows = await db.delivery_missions.aggregate([
        {"$match": {"driver_id": {"$in": user_ids}}},
        {"$group": {
            "_id": "$driver_id",
            "completed": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
            "active": {"$sum": {"$cond": [{"$in": ["$status", ["pending", "assigned", "in_progress", "incident_reported"]]}, 1, 0]}},
            **{field: {"$max": f"${field}"} for field in activity_fields},
        }},
    ]).to_list(length=len(user_ids))
    for row in rows:
        dates = [value for field in activity_fields if (value := utc(row.pop(field, None))) is not None]
        row["last_activity"] = max(dates, default=None)
    return {row["_id"]: row for row in rows}


async def relay_activity(user_ids):
    if not user_ids:
        return {}
    users = await db.users.find({"user_id": {"$in": user_ids}},
                               {"_id": 0, "user_id": 1, "relay_point_id": 1}).to_list(length=len(user_ids))
    relay_ids = list({user["relay_point_id"] for user in users if user.get("relay_point_id")})
    if not relay_ids:
        return {uid: {"linked_relay": False} for uid in user_ids}
    relay_fields = ["origin_relay_id", "destination_relay_id", "redirect_relay_id", "transit_relay_id"]
    related = {"$or": [{field: {"$in": relay_ids}} for field in relay_fields]}
    arrival_relay = {"$ifNull": ["$redirect_relay_id", {"$ifNull": ["$transit_relay_id", "$destination_relay_id"]}]}
    processed = await db.parcels.aggregate([
        {"$match": related},
        {"$lookup": {"from": "parcel_events", "localField": "parcel_id", "foreignField": "parcel_id", "as": "event"}},
        {"$unwind": "$event"},
        {"$match": {"event.event_type": "STATUS_CHANGED"}},
        {"$project": {"parcel_id": 1, "at": "$event.created_at", "relay_id": {"$switch": {
            "branches": [
                {"case": {"$eq": ["$event.to_status", "dropped_at_origin_relay"]}, "then": "$origin_relay_id"},
                {"case": {"$in": ["$event.to_status", ["at_destination_relay", "available_at_relay"]]}, "then": arrival_relay},
                {"case": {"$and": [{"$eq": ["$event.to_status", "in_transit"]}, {"$eq": ["$event.from_status", "dropped_at_origin_relay"]}]}, "then": "$origin_relay_id"},
                {"case": {"$and": [{"$eq": ["$event.to_status", "delivered"]}, {"$in": ["$event.from_status", ["at_destination_relay", "available_at_relay"]]}]}, "then": arrival_relay},
            ], "default": None,
        }}}},
        {"$match": {"relay_id": {"$in": relay_ids}}},
        {"$group": {"_id": {"relay_id": "$relay_id", "parcel_id": "$parcel_id"}, "last_activity": {"$max": "$at"}}},
        {"$group": {"_id": "$_id.relay_id", "processed": {"$sum": 1}, "last_activity": {"$max": "$last_activity"}}},
    ]).to_list(length=len(relay_ids))
    stock = await db.parcels.aggregate([
        {"$match": related},
        {"$project": {"relay_id": {"$switch": {"branches": [
            {"case": {"$eq": ["$status", "dropped_at_origin_relay"]}, "then": "$origin_relay_id"},
            {"case": {"$in": ["$status", ["at_destination_relay", "available_at_relay"]]}, "then": arrival_relay},
        ], "default": None}}}},
        {"$match": {"relay_id": {"$in": relay_ids}}},
        {"$group": {"_id": "$relay_id", "active": {"$sum": 1}}},
    ]).to_list(length=len(relay_ids))
    by_relay = {row["_id"]: row for row in processed}
    for row in stock:
        by_relay.setdefault(row["_id"], {}).update(active=row["active"])
    lookup = {user["user_id"]: user.get("relay_point_id") for user in users}
    return {uid: {**by_relay.get(lookup.get(uid), {}), "linked_relay": bool(lookup.get(uid))} for uid in user_ids}


async def activities_for_campaigns(campaigns, user_ids):
    kinds = {activity_kind(targeting_for(campaign)) for campaign in campaigns
             if targeting_for(campaign).audience != CampaignAudience.ALL}
    loaders = {"client": sender_activity, "driver": driver_activity, "relay_agent": relay_activity}
    return {kind: await loaders[kind](user_ids) for kind in kinds}


def campaign_matches_activity(campaign, activities, user_id, now):
    policy = targeting_for(campaign)
    if not valid_audience_for_roles(campaign.get("target_roles") or ["all"], policy.audience):
        return False
    return audience_matches(policy, activities.get(activity_kind(policy), {}).get(user_id, {}), now)


def audience_matches(policy, activity, now):
    sent = activity.get("sent", 0)
    delivered = activity.get("delivered", 0)
    if policy.audience == CampaignAudience.ALL:
        return True
    professional_counts = {
        CampaignAudience.DRIVER_NEW: ("completed", "new"), CampaignAudience.DRIVER_FIRST: ("completed", "first"),
        CampaignAudience.DRIVER_REGULAR: ("completed", "regular"), CampaignAudience.DRIVER_INACTIVE: ("completed", "inactive"),
        CampaignAudience.RELAY_NEW: ("processed", "new"), CampaignAudience.RELAY_FIRST: ("processed", "first"),
        CampaignAudience.RELAY_REGULAR: ("processed", "regular"), CampaignAudience.RELAY_INACTIVE: ("processed", "inactive"),
    }
    if policy.audience in professional_counts:
        field, criterion = professional_counts[policy.audience]
        if activity_kind(policy) == "relay_agent" and not activity.get("linked_relay", False):
            return False
        count = activity.get(field, 0)
        if criterion == "new":
            return count == 0
        if criterion == "first":
            return count == 1
        if criterion == "regular":
            threshold = policy.min_completed_missions if field == "completed" else policy.min_processed_parcels
            return count >= threshold
        last = utc(activity.get("last_activity"))
        return bool(count > 0 and not activity.get("active", 0) and last and last <= now - timedelta(days=policy.inactive_days))
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
    activities = await activities_for_campaigns([campaign], [user_id])
    return campaign_matches_activity(campaign, activities, user_id, now)


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
