import asyncio
import copy
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

from fastapi import HTTPException
from pydantic import ValidationError

from services import campaign_targeting as targeting
from routers import in_app_campaigns as router


NOW = datetime(2026, 9, 30, 12, tzinfo=timezone.utc)


class AudienceTests(unittest.TestCase):
    def test_sender_filters_only_support_client_recipients(self):
        self.assertTrue(targeting.valid_audience_for_roles(["client"], "no_send"))
        for roles in ([], ["all"], ["driver"], ["relay_agent"], ["client", "driver"]):
            with self.subTest(roles=roles):
                self.assertFalse(targeting.valid_audience_for_roles(roles, "no_send"))
    def matches(self, audience, activity, **config):
        return targeting.audience_matches(targeting.CampaignTargeting(audience=audience, **config), activity, NOW)

    def test_no_send_is_not_no_successful_delivery(self):
        self.assertTrue(self.matches("no_send", {}))
        self.assertFalse(self.matches("no_send", {"sent": 1, "delivered": 0}))

    def test_first_delivery_and_regular_threshold(self):
        self.assertTrue(self.matches("first_delivery", {"delivered": 1}))
        self.assertFalse(self.matches("first_delivery", {"delivered": 2}))
        self.assertFalse(self.matches("regular", {"delivered": 7}, min_deliveries=8))
        self.assertTrue(self.matches("regular", {"delivered": 8}, min_deliveries=8))

    def test_relay_requires_a_successful_relay_delivery(self):
        self.assertFalse(self.matches("relay_users", {"relay_deliveries": 0}))
        self.assertTrue(self.matches("relay_users", {"relay_deliveries": 1}))

    def test_inactive_excludes_new_users_recent_sends_and_active_parcels(self):
        old = {"sent": 2, "active": 0, "last_send": (NOW - timedelta(days=20)).replace(tzinfo=None)}
        self.assertTrue(self.matches("inactive", old, inactive_days=20))
        self.assertFalse(self.matches("inactive", {**old, "active": 1}, inactive_days=20))
        self.assertFalse(self.matches("inactive", old, inactive_days=21))
        self.assertFalse(self.matches("inactive", {}, inactive_days=20))

    def test_validation_and_legacy_defaults(self):
        self.assertEqual(targeting.targeting_for({}), targeting.CampaignTargeting())
        for invalid in ({"max_exposures": 0}, {"cooldown_hours": -1}, {"frequency_days": 0}, {"audience": "unknown"}):
            with self.subTest(invalid=invalid), self.assertRaises(ValidationError):
                targeting.CampaignTargeting(**invalid)

    def test_window_and_cooldown_boundaries(self):
        policy = targeting.CampaignTargeting(max_exposures=1, frequency_days=7, cooldown_hours=2)
        event = {"exposures": [{"at": NOW - timedelta(days=7), "id": "expired"}]}
        self.assertTrue(targeting.exposure_allowed(event, policy, NOW))
        event["exposures"].append({"at": NOW - timedelta(days=6), "id": "recent"})
        self.assertFalse(targeting.exposure_allowed(event, policy, NOW))
        self.assertFalse(targeting.exposure_allowed({"last_shown_at": NOW - timedelta(hours=1)}, policy, NOW))
        self.assertTrue(targeting.exposure_allowed({"last_shown_at": NOW - timedelta(hours=2)}, policy, NOW))


class AtomicEvents:
    def __init__(self, policy):
        self.policy = policy
        self.docs = {}
        self.lock = asyncio.Lock()

    @staticmethod
    def key(query):
        return tuple(query[field] for field in ("campaign_id", "user_id", "event_type"))

    async def find_one(self, query):
        await asyncio.sleep(0)
        return copy.deepcopy(self.docs.get(self.key(query)))

    async def update_one(self, query, update, upsert=False):
        if upsert and "$expr" in query:
            raise AssertionError("MongoDB forbids $expr in upsert predicates")
        async with self.lock:
            self.docs.setdefault(self.key(query), copy.deepcopy({**query, **update["$setOnInsert"]}))

    async def find_one_and_update(self, query, pipeline, **kwargs):
        if kwargs.get("upsert"):
            raise AssertionError("Exposure claim must not upsert")
        self.last_query = query
        self.last_pipeline = pipeline
        async with self.lock:
            doc = self.docs[self.key(query)]
            token = query["exposures.id"]["$ne"]
            now = pipeline[0]["$set"]["last_shown_at"]
            if any(item["id"] == token for item in doc["exposures"]) or not targeting.exposure_allowed(doc, self.policy, now):
                return None
            previous = copy.deepcopy(doc)
            doc.update(last_shown_at=now, unique_counted=True,
                       exposures=targeting.exposures_in_window(doc, self.policy, now) + [{"at": now, "id": token}])
            return previous


class ExposureTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.policy = targeting.CampaignTargeting(max_exposures=1, cooldown_hours=0)
        self.campaign = {"campaign_id": "campaign", "targeting": self.policy.model_dump(mode="json")}
        self.events = AtomicEvents(self.policy)
        self.db = SimpleNamespace(in_app_campaign_events=self.events, in_app_campaigns=SimpleNamespace(update_one=AsyncMock()))

    async def test_concurrent_claims_share_one_slot_and_one_unique_view(self):
        with patch.object(targeting, "db", self.db):
            results = await asyncio.gather(*(targeting.claim_exposure(self.campaign, "user", "impression", str(i), NOW) for i in range(20)))
        self.assertEqual(sum(results), 1)
        self.assertEqual(self.db.in_app_campaigns.update_one.await_count, 1)
        self.assertIn("$expr", self.events.last_query)
        conditions = self.events.last_query["$expr"]["$and"]
        self.assertEqual(conditions[0]["$lt"][1], 1)
        self.assertEqual(conditions[1]["$lte"][1], NOW)
        self.assertIn("$concatArrays", self.events.last_pipeline[0]["$set"]["exposures"])

    async def test_idempotent_replay_and_channels_are_separate(self):
        with patch.object(targeting, "db", self.db):
            for _ in range(2):
                self.assertTrue(await targeting.claim_exposure(self.campaign, "user", "impression", "same", NOW))
            self.assertTrue(await targeting.claim_exposure(self.campaign, "user", "notification", "push", NOW))
        self.assertEqual(self.db.in_app_campaigns.update_one.await_count, 1)

    async def test_dismissal_blocks_both_channels_and_is_account_scoped(self):
        self.events.docs[("campaign", "user", "dismiss")] = {"created_at": NOW}
        with patch.object(targeting, "db", self.db):
            for channel in ("impression", "notification"):
                self.assertFalse(await targeting.claim_exposure(self.campaign, "user", channel, "new", NOW))
            self.assertTrue(await targeting.claim_exposure(self.campaign, "another-user", "impression", "new", NOW))


class CampaignEndpointTests(unittest.IsolatedAsyncioTestCase):
    async def test_create_rejects_sender_filters_for_professionals_and_mixed_roles(self):
        from models.in_app_campaign import InAppCampaignCreate
        for roles in (["all"], ["driver"], ["relay_agent"], ["client", "driver"]):
            campaign = self.campaign(target_roles=roles)
            campaign["action_value"] = "/client/create"
            body = InAppCampaignCreate.model_validate(campaign)
            with self.subTest(roles=roles), self.assertRaises(HTTPException) as error:
                await router.create_campaign(body, {"user_id": "admin"})
            self.assertEqual(error.exception.status_code, 400)

    async def test_create_allows_unfiltered_professionals_and_filtered_clients(self):
        from models.in_app_campaign import InAppCampaignCreate
        collection = SimpleNamespace(insert_one=AsyncMock())
        with patch.object(router, "db", SimpleNamespace(in_app_campaigns=collection)):
            for roles, audience in ((["driver"], "all"), (["relay_agent"], "all"),
                                    (["all"], "all"), (["client"], "no_send")):
                body = InAppCampaignCreate.model_validate({
                    **self.campaign(target_roles=roles, targeting={"audience": audience}),
                    "action_value": "/client/create",
                })
                await router.create_campaign(body, {"user_id": "admin"})
        self.assertEqual(collection.insert_one.await_count, 4)

    async def test_role_change_requires_clearing_existing_sender_filter(self):
        from models.in_app_campaign import InAppCampaignUpdate
        collection = SimpleNamespace(find_one=AsyncMock(return_value=self.campaign()),
                                     update_one=AsyncMock())
        with patch.object(router, "db", SimpleNamespace(in_app_campaigns=collection)):
            with self.assertRaises(HTTPException) as error:
                await router.update_campaign("campaign", InAppCampaignUpdate(target_roles=["driver"]), {"user_id": "admin"})
            self.assertEqual(error.exception.status_code, 400)
            collection.update_one.assert_not_awaited()
            await router.update_campaign("campaign", InAppCampaignUpdate(
                target_roles=["driver"], targeting={"audience": "all", "max_exposures": 4}), {"user_id": "admin"})
        stored = collection.update_one.await_args.args[1]["$set"]
        self.assertEqual(stored["targeting"]["audience"], "all")
        self.assertEqual(stored["targeting"]["max_exposures"], 4)

    async def test_options_publish_supported_filter_roles(self):
        options = await router.campaign_options({"user_id": "admin"})
        self.assertEqual(set(options["audiences_by_role"]), {"client", "driver", "relay_agent"})
        self.assertEqual(options["audiences"][0]["label"], "Sans filtre d’activité")

    def campaign(self, **overrides):
        return {"campaign_id": "campaign", "title": "Conseil", "body": "Votre message", "is_active": True,
                "start_date": datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=1),
                "end_date": datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(days=1),
                "target_roles": ["client"], "targeting": {"audience": "first_delivery"}, **overrides}

    async def test_optout_role_and_audience_protect_direct_access(self):
        campaign = self.campaign()
        user = {"user_id": "user", "role": "client"}
        with patch.object(router, "campaign_audience_matches", AsyncMock(return_value=False)):
            for subject in ({**user, "notification_prefs": {"promotions": False}}, user):
                with self.assertRaises(HTTPException) as error:
                    await router._check_campaign_access(campaign, subject)
                self.assertEqual(error.exception.status_code, 403)
        with patch.object(router, "campaign_audience_matches", AsyncMock(return_value=True)):
            await router._check_campaign_access(campaign, {**user, "role": "driver"})
            with self.assertRaises(HTTPException) as error:
                await router._check_campaign_access(self.campaign(is_active=False), user)
            self.assertEqual(error.exception.status_code, 410)
            with self.assertRaises(HTTPException) as error:
                await router._check_campaign_access(self.campaign(target_roles=["driver"]), user)
            self.assertEqual(error.exception.status_code, 403)

    async def test_active_list_filters_audience_dismissals_and_frequency(self):
        campaigns = [self.campaign(campaign_id=uid) for uid in ("eligible", "dismissed", "capped")]
        campaigns.append(self.campaign(campaign_id="regular-only", targeting={"audience": "regular"}))
        cursor = MagicMock()
        cursor.sort.return_value = cursor
        cursor.to_list = AsyncMock(return_value=campaigns)
        states = {("dismissed", "dismiss"): {}, ("capped", "impression"): {"last_shown_at": datetime.now(timezone.utc)}}
        db = SimpleNamespace(in_app_campaigns=SimpleNamespace(find=MagicMock(return_value=cursor)))
        with patch.object(router, "db", db), patch.object(router, "campaign_state", AsyncMock(return_value=states)), \
             patch.object(targeting, "sender_activity", AsyncMock(return_value={"user": {"delivered": 1}})):
            result = await router.active_campaigns(role="client", placement="home", current_user={"user_id": "user", "role": "driver"})
            self.assertEqual([item["campaign_id"] for item in result["campaigns"]], ["eligible"])
            result = await router.active_campaigns(role="client", placement="home", current_user={"user_id": "user", "notification_prefs": {"promotions": False}})
            self.assertEqual(result, {"campaigns": []})

    async def test_dismissal_saved_for_authenticated_user_only(self):
        events = SimpleNamespace(update_one=AsyncMock())
        db = SimpleNamespace(in_app_campaigns=SimpleNamespace(find_one=AsyncMock(return_value=self.campaign())), in_app_campaign_events=events)
        with patch.object(router, "db", db):
            self.assertEqual(await router.dismiss_campaign("campaign", {"user_id": "user", "role": "driver"}), {"ok": True})
        self.assertEqual(events.update_one.await_args.args[0], {"user_id": "user", "campaign_id": "campaign", "event_type": "dismiss"})
        self.assertTrue(events.update_one.await_args.kwargs["upsert"])

    async def test_notification_uses_same_audience_and_releases_failed_sends(self):
        users = [{"user_id": uid, "role": "client"} for uid in ("first", "regular", "dismissed", "failed")]
        cursor = MagicMock()
        cursor.to_list = AsyncMock(return_value=users)
        db = SimpleNamespace(in_app_campaigns=SimpleNamespace(find_one=AsyncMock(return_value=self.campaign())),
                             users=SimpleNamespace(find=MagicMock(return_value=cursor)))
        activity = {"first": {"delivered": 1}, "regular": {"delivered": 2},
                    "dismissed": {"delivered": 1}, "failed": {"delivered": 1}}
        async def claim(campaign, uid, *args):
            return uid != "dismissed"
        async def send(**kwargs):
            if kwargs["user_ids"] == ["failed"]:
                raise RuntimeError("simulated send failure")
            self.assertEqual(kwargs["category"], "promotions")
            self.assertEqual(kwargs["ref_id"], "campaign")
            return {"in_app_sent": 1, "sent": 1, "push_sent": 1}
        with patch.object(router, "db", db), patch.object(targeting, "sender_activity", AsyncMock(return_value=activity)), \
             patch.object(router, "claim_exposure", AsyncMock(side_effect=claim)), \
             patch.object(router, "send_targeted_notifications", AsyncMock(side_effect=send)) as sender, \
             patch.object(router, "release_exposure", AsyncMock()) as release, \
             patch.object(router.logger, "exception"):
            result = await router.notify_campaign("campaign", {"user_id": "admin"})
        self.assertEqual(result["matched"], 3)
        self.assertEqual(result["in_app_sent"], 1)
        self.assertEqual(result["frequency_skipped"], 1)
        self.assertEqual(result["failed"], 1)
        self.assertEqual(sender.await_count, 2)
        self.assertEqual(release.await_args.args[1], "failed")
        self.assertEqual(db.users.find.call_args.args[0]["notification_prefs.promotions"], {"$ne": False})


if __name__ == "__main__":
    unittest.main()
