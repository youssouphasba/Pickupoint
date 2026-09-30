import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import mongomock
from fastapi import HTTPException
from models.in_app_campaign import InAppCampaignCreate, InAppCampaignUpdate
from routers import in_app_campaigns as router
from services import campaign_targeting as targeting

NOW = datetime(2026, 9, 30, 12, tzinfo=timezone.utc)


class AsyncCursor:
    def __init__(self, rows):
        self.rows = rows

    async def to_list(self, length):
        return list(self.rows)[:length]


class AsyncCollection:
    def __init__(self, collection):
        self.collection = collection

    def find(self, *args, **kwargs):
        return AsyncCursor(self.collection.find(*args, **kwargs))

    def aggregate(self, pipeline):
        return AsyncCursor(self.collection.aggregate(pipeline))


class AudienceRulesTests(unittest.TestCase):
    def test_options_match_selected_recipient_role(self):
        for role in ("client", "driver", "relay_agent"):
            options = targeting.audience_options([role])
            self.assertEqual(options[0]["value"], "all")
            for option in options:
                self.assertTrue(targeting.valid_audience_for_roles([role], option["value"]))
        for roles in (["all"], ["client", "driver"], []):
            self.assertEqual([item["value"] for item in targeting.audience_options(roles)], ["all"])
        self.assertFalse(targeting.valid_audience_for_roles(["driver"], "relay_regular"))
        self.assertFalse(targeting.valid_audience_for_roles(["relay_agent"], "first_delivery"))

    def test_professional_counts_ignore_personal_sends(self):
        for audience in ("driver_new", "relay_new"):
            policy = targeting.CampaignTargeting(audience=audience)
            self.assertTrue(targeting.audience_matches(policy, {"sent": 100, "delivered": 100, "linked_relay": True}, NOW))
        for audience, field in (("driver_first", "completed"), ("relay_first", "processed")):
            policy = targeting.CampaignTargeting(audience=audience)
            self.assertTrue(targeting.audience_matches(policy, {field: 1, "linked_relay": True}, NOW))
            self.assertFalse(targeting.audience_matches(policy, {field: 2, "linked_relay": True}, NOW))

    def test_thresholds_are_role_specific_and_configurable(self):
        for audience, field, threshold in (("driver_regular", "completed", "min_completed_missions"),
                                           ("relay_regular", "processed", "min_processed_parcels")):
            policy = targeting.CampaignTargeting(audience=audience, **{threshold: 8})
            self.assertFalse(targeting.audience_matches(policy, {field: 7, "linked_relay": True}, NOW))
            self.assertTrue(targeting.audience_matches(policy, {field: 8, "linked_relay": True}, NOW))

    def test_inactivity_requires_history_old_activity_and_no_active_work(self):
        for audience, field in (("driver_inactive", "completed"), ("relay_inactive", "processed")):
            policy = targeting.CampaignTargeting(audience=audience, inactive_days=20)
            activity = {field: 2, "linked_relay": True, "last_activity": NOW - timedelta(days=20)}
            self.assertTrue(targeting.audience_matches(policy, activity, NOW))
            for change in ({"active": 1}, {field: 0}, {"last_activity": NOW - timedelta(days=19)}, {"last_activity": None}):
                self.assertFalse(targeting.audience_matches(policy, {**activity, **change}, NOW))

    def test_unlinked_relay_account_is_not_a_new_relay(self):
        self.assertFalse(targeting.audience_matches(targeting.CampaignTargeting(audience="relay_new"), {}, NOW))


class ActivityAggregationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.mongo = mongomock.MongoClient(tz_aware=True).test
        self.db = SimpleNamespace(**{name: AsyncCollection(self.mongo[name]) for name in
                                     ("users", "parcels", "parcel_events", "delivery_missions")})

    async def test_driver_real_missions_and_last_activity(self):
        self.mongo.delivery_missions.insert_many([
            {"driver_id": "driver", "status": "completed", "completed_at": NOW - timedelta(days=30)},
            {"driver_id": "driver", "status": "failed", "updated_at": NOW - timedelta(days=2)},
            {"driver_id": "driver", "status": "assigned", "assigned_at": NOW - timedelta(days=1)},
            {"driver_id": "other", "status": "completed", "completed_at": NOW},
        ])
        with patch.object(targeting, "db", self.db):
            activity = await targeting.driver_activity(["driver"])
        self.assertEqual(activity["driver"]["completed"], 1)
        self.assertEqual(activity["driver"]["active"], 1)
        self.assertEqual(activity["driver"]["last_activity"], NOW - timedelta(days=1))

    async def test_relay_distinct_parcels_shared_point_and_stock(self):
        self.mongo.users.insert_many([
            {"user_id": "agent", "relay_point_id": "r1"},
            {"user_id": "colleague", "relay_point_id": "r1"},
            {"user_id": "unlinked"},
        ])
        self.mongo.parcels.insert_many([
            {"parcel_id": "p1", "origin_relay_id": "r1", "destination_relay_id": "r1", "status": "delivered"},
            {"parcel_id": "p2", "destination_relay_id": "r1", "status": "available_at_relay"},
            {"parcel_id": "planned", "destination_relay_id": "r1", "status": "created"},
            {"parcel_id": "home", "origin_relay_id": "r1", "status": "delivered"},
        ])
        self.mongo.parcel_events.insert_many([
            {"parcel_id": "p1", "event_type": "STATUS_CHANGED", "to_status": "dropped_at_origin_relay", "created_at": NOW - timedelta(days=3)},
            {"parcel_id": "p1", "event_type": "STATUS_CHANGED", "from_status": "dropped_at_origin_relay", "to_status": "in_transit", "created_at": NOW - timedelta(days=2)},
            {"parcel_id": "p1", "event_type": "STATUS_CHANGED", "to_status": "available_at_relay", "created_at": NOW - timedelta(days=1)},
            {"parcel_id": "p2", "event_type": "STATUS_CHANGED", "to_status": "available_at_relay", "created_at": NOW},
            {"parcel_id": "planned", "event_type": "PARCEL_CREATED", "to_status": "created", "created_at": NOW},
            {"parcel_id": "home", "event_type": "STATUS_CHANGED", "from_status": "out_for_delivery", "to_status": "delivered", "created_at": NOW},
        ])
        with patch.object(targeting, "db", self.db):
            activity = await targeting.relay_activity(["agent", "colleague", "unlinked"])
        self.assertEqual(activity["agent"]["processed"], 2)
        self.assertEqual(activity["agent"]["active"], 1)
        self.assertEqual(activity["agent"]["last_activity"], NOW)
        self.assertEqual(activity["agent"], activity["colleague"])
        self.assertFalse(activity["unlinked"]["linked_relay"])

    async def test_no_filter_loads_no_activity(self):
        with patch.object(targeting, "sender_activity", AsyncMock()) as sender, \
             patch.object(targeting, "driver_activity", AsyncMock()) as driver, \
             patch.object(targeting, "relay_activity", AsyncMock()) as relay:
            activities = await targeting.activities_for_campaigns([{"target_roles": ["all"]}], ["user"])
        self.assertEqual(activities, {})
        sender.assert_not_awaited()
        driver.assert_not_awaited()
        relay.assert_not_awaited()


class ProfessionalCampaignEndpointTests(unittest.IsolatedAsyncioTestCase):
    def campaign(self, role="driver", audience="driver_first"):
        return {"campaign_id": "professional", "title": "Conseil", "body": "Message", "cta_label": "Voir",
                "target_roles": [role], "targeting": {"audience": audience}, "action_value": "/client/create",
                "is_active": True, "start_date": NOW - timedelta(days=365), "end_date": NOW + timedelta(days=365)}

    async def test_create_and_update_professional_audiences(self):
        collection = SimpleNamespace(insert_one=AsyncMock(), find_one=AsyncMock(return_value=self.campaign()), update_one=AsyncMock())
        with patch.object(router, "db", SimpleNamespace(in_app_campaigns=collection)):
            for role, audience in (("driver", "driver_regular"), ("relay_agent", "relay_regular")):
                await router.create_campaign(InAppCampaignCreate.model_validate(self.campaign(role, audience)), {"user_id": "admin"})
            await router.update_campaign("professional", InAppCampaignUpdate(target_roles=["relay_agent"], targeting={"audience": "relay_first"}), {"user_id": "admin"})
            with self.assertRaises(HTTPException):
                await router.update_campaign("professional", InAppCampaignUpdate(target_roles=["all"]), {"user_id": "admin"})
        self.assertEqual(collection.insert_one.await_count, 2)
        self.assertEqual(collection.update_one.await_count, 1)

    async def test_professional_filter_matches_list_direct_access_and_notifications(self):
        campaign = self.campaign()
        cursor = MagicMock()
        cursor.sort.return_value = cursor
        cursor.to_list = AsyncMock(return_value=[campaign])
        users = MagicMock()
        users.to_list = AsyncMock(return_value=[{"user_id": "d1", "role": "driver"}, {"user_id": "d2", "role": "driver"}])
        db = SimpleNamespace(in_app_campaigns=SimpleNamespace(find=MagicMock(return_value=cursor), find_one=AsyncMock(return_value=campaign)),
                             users=SimpleNamespace(find=MagicMock(return_value=users)))
        activity = {"d1": {"completed": 1}, "d2": {"completed": 2}}
        with patch.object(router, "db", db), patch.object(targeting, "driver_activity", AsyncMock(return_value=activity)), \
             patch.object(router, "campaign_state", AsyncMock(return_value={})), \
             patch.object(router, "claim_exposure", AsyncMock(return_value=True)), \
             patch.object(router, "send_targeted_notifications", AsyncMock(return_value={"in_app_sent": 1})) as sender:
            visible = await router.active_campaigns(role="driver", placement="home", current_user={"user_id": "d1", "role": "driver"})
            self.assertEqual(len(visible["campaigns"]), 1)
            visible = await router.active_campaigns(role="driver", placement="home", current_user={"user_id": "d2", "role": "driver"})
            self.assertEqual(visible["campaigns"], [])
            await router._check_campaign_access(campaign, {"user_id": "d1", "role": "driver"})
            with self.assertRaises(HTTPException):
                await router._check_campaign_access(campaign, {"user_id": "d2", "role": "driver"})
            result = await router.notify_campaign("professional", {"user_id": "admin"})
        self.assertEqual(result["matched"], 1)
        self.assertEqual(sender.await_args.kwargs["user_ids"], ["d1"])


if __name__ == "__main__":
    unittest.main()
