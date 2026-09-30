import asyncio
from copy import deepcopy
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

from services.loyalty_rules import compute_tier, loyalty_summary, tier_discount_coeff
from services.performance_rewards_service import normalize_performance_rewards, set_performance_rewards_settings
from services.loyalty_service import credit_loyalty_points
from services.pricing_service import calculate_price
from models.parcel import ParcelQuote


class LoyaltyRulesTests(unittest.TestCase):
    def setUp(self):
        self.rules = normalize_performance_rewards({})["client"]

    def test_existing_defaults_preserved(self):
        self.assertEqual(compute_tier(199), "bronze")
        self.assertEqual(compute_tier(200), "silver")
        self.assertEqual(compute_tier(500), "gold")
        self.assertAlmostEqual(tier_discount_coeff("gold"), .8)

    def test_configured_rules_drive_benefits(self):
        self.rules["loyalty_tiers"][1].update(min_points=100, discount_percent=15)
        summary = loyalty_summary(80, self.rules)
        self.assertEqual(summary["deliveries_remaining"], 2)
        self.assertEqual(summary["next_tier"]["discount_percent"], 15)
        self.assertEqual(loyalty_summary(100, self.rules)["discount_percent"], 15)

    def test_progress_relative_to_current_level(self):
        summary = loyalty_summary(350, self.rules)
        self.assertEqual(summary["progress"], .5)
        self.assertEqual(summary["points_remaining"], 150)

    def test_highest_level_has_no_false_target(self):
        summary = loyalty_summary(600, self.rules)
        self.assertIsNone(summary["next_tier"])
        self.assertEqual(summary["progress"], 1)
        self.assertEqual(summary["deliveries_remaining"], 0)

    def test_remaining_deliveries_rounded_up(self):
        self.assertEqual(loyalty_summary(191, self.rules)["deliveries_remaining"], 1)


class LoyaltyAwardTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.user = {"user_id": "u1", "loyalty_points": 190}
        self.parcel = {"parcel_id": "p1", "tracking_code": "PKP-TEST", "sender_user_id": "u1", "status": "delivered"}
        self.events = []
        self.lock = asyncio.Lock()
        self.fake_db = SimpleNamespace(
            users=SimpleNamespace(find_one=AsyncMock(side_effect=lambda *a, **k: deepcopy(self.user)), update_one=AsyncMock(side_effect=self.update_user)),
            parcels=SimpleNamespace(find_one=AsyncMock(side_effect=lambda *a, **k: deepcopy(self.parcel)), update_one=AsyncMock(side_effect=self.update_parcel)),
            loyalty_events=SimpleNamespace(insert_one=AsyncMock(side_effect=lambda event, **k: self.events.append(deepcopy(event)))),
        )
        owner = self
        class Session:
            async def __aenter__(self): return self
            async def __aexit__(self, *args): return False
            async def with_transaction(self, operation):
                async with owner.lock:
                    before = deepcopy((owner.user, owner.parcel, owner.events))
                    try:
                        return await operation(self)
                    except Exception:
                        owner.user, owner.parcel, owner.events = before
                        raise
        self.client = SimpleNamespace(start_session=AsyncMock(side_effect=Session))

    async def update_user(self, query, update, **kwargs): self.user.update(update["$set"])
    async def update_parcel(self, query, update, **kwargs): self.parcel.update(update["$set"])

    async def award(self):
        with patch("services.loyalty_service.db", self.fake_db), patch("services.loyalty_service.get_client", return_value=self.client), patch("services.loyalty_service.get_performance_rewards_settings", AsyncMock(return_value=normalize_performance_rewards({}))), patch("services.loyalty_service._check_referral_bonus", AsyncMock()):
            return await credit_loyalty_points("u1", "p1")

    async def test_delivery_credit_is_unique_even_with_concurrent_requests(self):
        first, second = await asyncio.gather(self.award(), self.award())
        self.assertEqual(first, second)
        self.assertEqual(self.user["loyalty_points"], 200)
        self.assertEqual(len(self.events), 1)
        self.assertTrue(first["tier_changed"])
        self.assertEqual(first["tracking_code"], "PKP-TEST")

    async def test_only_delivered_sender_earns_points(self):
        self.parcel["status"] = "cancelled"
        self.assertIsNone(await self.award())
        self.parcel.update(status="delivered", sender_user_id="other")
        self.assertIsNone(await self.award())
        self.assertEqual(self.user["loyalty_points"], 190)

    async def test_failed_transaction_leaves_no_partial_credit(self):
        self.fake_db.parcels.update_one.side_effect = RuntimeError("write failed")
        with self.assertRaises(RuntimeError):
            await self.award()
        self.assertEqual(self.user["loyalty_points"], 190)
        self.assertEqual(self.events, [])
        self.assertNotIn("loyalty_award", self.parcel)

    async def test_invalid_configuration_rejected(self):
        body = normalize_performance_rewards({})
        body["client"]["loyalty_tiers"][2]["min_points"] = 100
        with self.assertRaises(Exception) as caught:
            await set_performance_rewards_settings(body)
        self.assertEqual(caught.exception.status_code, 400)


class LoyaltyPriceTests(unittest.IsolatedAsyncioTestCase):
    async def price(self, minimum=100, express=False):
        rules = normalize_performance_rewards({})
        rules["client"]["loyalty_tiers"][1]["discount_percent"] = 15
        quote = ParcelQuote(delivery_mode="relay_to_relay", origin_relay_id="r1", destination_relay_id="r2", is_express=express)
        pricing = {"price_per_km": 0, "price_per_kg": 0, "free_weight_kg": 1, "min_price": minimum, "express_enabled": True, "express_multiplier": 1.3}
        fake_db = SimpleNamespace(users=SimpleNamespace(find_one=AsyncMock(return_value={"loyalty_points": 200})))
        with patch("services.pricing_service.get_pricing_settings", AsyncMock(return_value=pricing)), patch("services.pricing_service._base_price", return_value=1000), patch("services.pricing_service.estimate_distance_km", AsyncMock(return_value=1)), patch("services.performance_rewards_service.get_performance_rewards_settings", AsyncMock(return_value=rules)), patch("services.pricing_service.db", fake_db), patch("services.promotion_service.find_best_promo", AsyncMock(return_value=None)):
            return await calculate_price(quote, sender_tier="bronze", user_id="u1")

    async def test_configured_discount_and_fresh_level_are_used(self):
        quote = await self.price()
        self.assertEqual(quote.price, 850)
        self.assertEqual(quote.breakdown["loyalty_tier"], "silver")
        self.assertEqual(quote.breakdown["loyalty_discount_xof"], 150)
        self.assertEqual(quote.breakdown["price_before_loyalty"], 1000)

    async def test_minimum_does_not_display_a_fictitious_discount(self):
        quote = await self.price(minimum=1000)
        self.assertEqual(quote.price, 1000)
        self.assertEqual(quote.breakdown["loyalty_discount_xof"], 0)

    async def test_discount_display_matches_express_and_rounding(self):
        quote = await self.price(express=True)
        self.assertEqual(quote.breakdown["price_before_loyalty"], 1300)
        self.assertEqual(quote.price + quote.breakdown["loyalty_discount_xof"], 1300)
