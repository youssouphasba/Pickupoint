import copy
import unittest
from contextlib import ExitStack
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch

from fastapi import HTTPException
from core.exceptions import DeliveryRoundingError
from models.parcel import ParcelCreate, ParcelQuote, QuoteResponse
from routers import deliveries
from services import parcel_service, pricing_service, wallet_service, wallet_activity_service
from services.delivery_rounding import build_financial_rounding, round_down, round_up
from services.wallet_service import compute_delivery_commission_breakdown, default_commission_rules
from tests.fake_database import Database


class DeliveryRoundingTests(unittest.TestCase):
    def test_agreed_client_and_driver_example(self):
        split = build_financial_rounding(2337, "home_to_relay", default_commission_rules())
        self.assertEqual([split[key] for key in (
            "price_xof", "driver_revenue_xof", "relay_commission_xof", "platform_commission_xof",
            "wallet_balance_required_xof",
        )], [2300, 1650, 350, 300, 650])
        self.assertEqual(split["rounding"]["customer_discount_xof"], 37)
        self.assertEqual(split["rounding"]["driver_bonus_xof"], 14.1)
        self.assertEqual(split["rounding"]["denkma_contribution_xof"], 50.55)

    def test_already_round_client_price_and_wallet(self):
        split = build_financial_rounding(3150, "home_to_relay", default_commission_rules())
        self.assertEqual(split["price_xof"], 3150)
        self.assertEqual(split["driver_revenue_xof"], 2250)
        self.assertEqual(split["relay_commission_xof"], 450)
        self.assertEqual(split["platform_commission_xof"], 450)
        self.assertEqual(split["wallet_balance_required_xof"], 900)

    def test_every_mode_balances_without_losing_client_or_driver_money(self):
        rules = default_commission_rules()
        for mode in rules:
            for basis in (700, 1450, 2337, 4579, 10000.37, 125000):
                with self.subTest(mode=mode, basis=basis):
                    split = build_financial_rounding(basis, mode, rules)
                    self.assertLessEqual(split["price_xof"], basis)
                    self.assertGreaterEqual(split["driver_revenue_xof"], round(basis * rules[mode]["driver_rate"], 2))
                    self.assertEqual(split["price_xof"], sum(split[key] for key in (
                        "driver_revenue_xof", "platform_commission_xof",
                        "origin_relay_commission_xof", "destination_relay_commission_xof",
                    )))
                    for key in ("price_xof", "driver_revenue_xof", "platform_commission_xof",
                                "origin_relay_commission_xof", "destination_relay_commission_xof", "wallet_balance_required_xof"):
                        self.assertEqual(split[key] % 50, 0)
                    self.assertGreaterEqual(split["platform_commission_xof"], 0)

    def test_decimal_boundaries_and_free_delivery(self):
        self.assertEqual(round_down(2300.0000000000005), 2300)
        self.assertEqual(round_up(2299.9999999999995), 2300)
        split = build_financial_rounding(0, "home_to_home", default_commission_rules())
        self.assertEqual(split["price_xof"], 0)
        self.assertEqual(split["driver_revenue_xof"], 0)

    def test_subcent_values_do_not_cross_the_cash_rounding_boundary(self):
        self.assertEqual(round_down(2949.999), 2900)
        self.assertEqual(round_up(1000.004), 1050)
        split = build_financial_rounding(1428.577143, "home_to_relay", default_commission_rules())
        self.assertEqual(split["driver_revenue_xof"], 1050)

    def test_custom_admin_rates_drive_the_split(self):
        rules = default_commission_rules()
        rules["home_to_relay"] = {"platform_rate": 0.2, "origin_relay_rate": 0,
                                 "destination_relay_rate": 0.25, "driver_rate": 0.55}
        split = build_financial_rounding(2337, "home_to_relay", rules)
        self.assertEqual(split["price_xof"], 2300)
        self.assertEqual(split["driver_revenue_xof"], 1300)
        self.assertEqual(split["destination_relay_commission_xof"], 550)
        self.assertEqual(split["platform_commission_xof"], 450)
        self.assertEqual(split["wallet_balance_required_xof"], 1000)

    def test_snapshot_preserves_rates_and_rounding_step(self):
        split = build_financial_rounding(2337, "home_to_relay", default_commission_rules())
        parcel = {"delivery_mode": "home_to_relay", "quoted_price": 2300, "financial_rounding": split,
                  "commission_rules_snapshot": {"home_to_relay": {"driver_rate": 0.1}}}
        self.assertEqual(compute_delivery_commission_breakdown(parcel), split)
        with patch("services.delivery_rounding.settings.DELIVERY_ROUNDING_STEP_XOF", 100):
            self.assertEqual(compute_delivery_commission_breakdown(parcel), split)

    def test_tampered_price_or_gift_is_rejected(self):
        split = build_financial_rounding(2337, "home_to_relay", default_commission_rules())
        for key, value in (("price_xof", 2350), ("wallet_balance_required_xof", 600)):
            broken = {**split, key: value}
            with self.subTest(key=key), self.assertRaises(DeliveryRoundingError):
                compute_delivery_commission_breakdown({"delivery_mode": "home_to_relay", "quoted_price": 2300, "financial_rounding": broken})
        broken = copy.deepcopy(split)
        broken["rounding"]["customer_discount_xof"] = 50
        with self.assertRaises(DeliveryRoundingError):
            compute_delivery_commission_breakdown({"delivery_mode": "home_to_relay", "quoted_price": 2300, "financial_rounding": broken})
        with self.assertRaises(DeliveryRoundingError):
            compute_delivery_commission_breakdown({"delivery_mode": "home_to_relay", "quoted_price": 2300.004, "financial_rounding": split})

    def test_legacy_prices_are_not_rewritten(self):
        split = compute_delivery_commission_breakdown({"delivery_mode": "home_to_relay", "paid_price": 2337,
                                                     "commission_rules_snapshot": default_commission_rules()})
        self.assertEqual(split["price_xof"], 2337)
        self.assertEqual(split["driver_revenue_xof"], 1635.9)
        self.assertNotIn("rounding", split)

    def test_insufficient_margin_cannot_charge_client_or_cut_driver_gain(self):
        with self.assertRaises(DeliveryRoundingError) as error:
            build_financial_rounding(2337, "home_to_home", default_commission_rules(), enabled=False)
        self.assertIn("marge", error.exception.detail)
        split = build_financial_rounding(2300, "home_to_home", default_commission_rules(), enabled=False)
        self.assertEqual(split["driver_revenue_xof"], 2300)
        self.assertEqual(split["wallet_balance_required_xof"], 0)

    def test_non_finite_and_negative_values_are_rejected(self):
        for value in (float("nan"), float("inf"), -1, "not money"):
            with self.subTest(value=value), self.assertRaises(DeliveryRoundingError):
                build_financial_rounding(value, "home_to_home", default_commission_rules())


class PricingRoundingTests(unittest.IsolatedAsyncioTestCase):
    async def test_admin_settings_are_loaded_without_fixed_rate_override(self):
        database = Database()
        rules = default_commission_rules()
        rules["home_to_home"] = {"platform_rate": 0.25, "origin_relay_rate": 0,
                                 "destination_relay_rate": 0, "driver_rate": 0.75}
        await database.app_settings.insert_one({"key": "global", "commission_rules": rules,
                                               "delivery_commissions_enabled": False, "price_per_km": 175})
        with patch.object(pricing_service, "db", database):
            config = await pricing_service.get_pricing_settings()
        self.assertEqual(config["commission_rules"], rules)
        self.assertFalse(config["delivery_commissions_enabled"])
        self.assertEqual(config["price_per_km"], 175)

    async def test_quote_respects_custom_rates_for_both_payers_and_keeps_frozen_rates(self):
        rules = default_commission_rules()
        rules["home_to_home"] = {"platform_rate": 0.25, "origin_relay_rate": 0,
                                 "destination_relay_rate": 0, "driver_rate": 0.75}
        pricing = {"base_home_to_home": 2237, "base_home_to_relay": 900, "base_relay_to_home": 1100,
                   "base_relay_to_relay": 700, "price_per_km": 100, "free_weight_kg": 2,
                   "price_per_kg": 100, "min_price": 700, "express_enabled": False,
                   "commission_rules": rules, "delivery_commissions_enabled": True}
        with patch.object(pricing_service, "get_pricing_settings", AsyncMock(return_value=pricing)), \
                patch.object(pricing_service, "estimate_distance_km", AsyncMock(return_value=1)), \
                patch("services.promotion_service.find_best_promo", AsyncMock(return_value=None)), \
                patch("services.performance_rewards_service.get_performance_rewards_settings", AsyncMock(return_value={"client": {"loyalty_tiers": []}})):
            for who_pays in ("sender", "recipient"):
                quote = ParcelQuote(delivery_mode="home_to_home", who_pays=who_pays,
                                    origin_location={"geopin": {"lat": 14.7, "lng": -17.4}},
                                    delivery_address={"geopin": {"lat": 14.8, "lng": -17.4}})
                result = await pricing_service.calculate_price(quote)
                self.assertEqual(result.price, 2300)
                self.assertEqual(result.breakdown["financial_rounding"]["driver_revenue_xof"], 1800)
                self.assertEqual(result.breakdown["financial_rounding"]["wallet_balance_required_xof"], 500)
                frozen = await pricing_service.calculate_price(quote, financial_context={"commission_rules_snapshot": default_commission_rules()})
                self.assertEqual(frozen.breakdown["financial_rounding"]["driver_revenue_xof"], 2000)

    async def test_promotions_apply_before_customer_rounding_and_driver_share(self):
        quote = ParcelQuote(delivery_mode="home_to_home", origin_location={"geopin": {"lat": 14.7, "lng": -17.4}},
                            delivery_address={"geopin": {"lat": 14.8, "lng": -17.4}})
        pricing = {"base_home_to_home": 2237, "base_home_to_relay": 900, "base_relay_to_home": 1100,
                   "base_relay_to_relay": 700, "price_per_km": 100, "free_weight_kg": 2,
                   "price_per_kg": 100, "min_price": 700, "express_enabled": False,
                   "commission_rules": default_commission_rules()}
        promo = {"promo_id": "promo", "title": "Réduction", "promo_type": "fixed_amount", "value": 101}
        with patch.object(pricing_service, "get_pricing_settings", AsyncMock(return_value=pricing)), \
                patch.object(pricing_service, "estimate_distance_km", AsyncMock(return_value=1)), \
                patch("services.performance_rewards_service.get_performance_rewards_settings", AsyncMock(return_value={"client": {"loyalty_tiers": []}})):
            result = await pricing_service.calculate_price(quote, reserved_promo=promo)
        split = result.breakdown["financial_rounding"]
        self.assertEqual(result.price, 2200)
        self.assertEqual(split["rounding"]["basis_price_xof"], 2236)
        self.assertEqual(split["rounding"]["customer_discount_xof"], 36)
        self.assertEqual(split["driver_revenue_xof"], 1950)


class RoundingFlowTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.database = Database()
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        for module in (parcel_service, wallet_service, deliveries):
            self.stack.enter_context(patch.object(module, "db", self.database))
        self.stack.enter_context(patch.object(wallet_service, "get_client", return_value=self.database))
        self.split = build_financial_rounding(2337, "home_to_home", default_commission_rules())
        self.quote = self.stack.enter_context(patch.object(parcel_service, "calculate_price", AsyncMock(
            return_value=QuoteResponse(price=2300, breakdown={"financial_rounding": self.split}))))
        self.stack.enter_context(patch.object(parcel_service, "_enrich_location_from_geopin", AsyncMock(side_effect=lambda address: address)))
        self.stack.enter_context(patch.object(parcel_service, "_create_delivery_mission", AsyncMock()))
        self.stack.enter_context(patch.object(parcel_service, "_record_event", AsyncMock()))
        self.stack.enter_context(patch.object(parcel_service, "notify_parcel_status_change", AsyncMock()))
        self.stack.enter_context(patch("services.loyalty_service._check_referral_bonus", AsyncMock()))
        self.stack.enter_context(patch("services.notification_service.notify_location_confirmation_request", AsyncMock()))
        self.payment = self.stack.enter_context(patch.object(parcel_service, "create_payment_link", AsyncMock(return_value={"success": False})))
        self.data = ParcelCreate(recipient_name="Destinataire", recipient_phone="+221770000001",
                                 delivery_mode="home_to_home", expected_price_xof=2300,
                                 origin_location={"geopin": {"lat": 14.7, "lng": -17.4, "accuracy": 10}},
                                 delivery_address={"geopin": {"lat": 14.8, "lng": -17.4, "accuracy": 10}})

    async def test_creation_persists_server_split_and_charges_displayed_price(self):
        await parcel_service.create_parcel(self.data, "sender", "+221770000002")
        parcel = await self.database.parcels.find_one({})
        self.assertEqual(parcel["financial_rounding"], self.split)
        self.assertEqual(compute_delivery_commission_breakdown(parcel), self.split)
        self.assertEqual(self.payment.await_args.kwargs["amount"], 2300)

    async def test_changed_quote_never_creates_or_charges_without_new_confirmation(self):
        self.quote.return_value.price = 2350
        with self.assertRaises(HTTPException) as error:
            await parcel_service.create_parcel(self.data, "sender", "+221770000002")
        self.assertEqual(error.exception.status_code, 409)
        self.assertEqual(await self.database.parcels.count_documents({}), 0)
        self.payment.assert_not_awaited()

    async def test_available_mission_uses_parcel_split_instead_of_stale_commission(self):
        await self.database.parcels.insert_one({"parcel_id": "parcel", "delivery_mode": "home_to_home",
                                               "quoted_price": 2300, "financial_rounding": self.split})
        mission = {"mission_id": "mission", "parcel_id": "parcel", "wallet_balance_required_xof": 999}
        await deliveries._attach_commission_requirements([mission])
        self.assertEqual(mission["wallet_balance_required_xof"], self.split["wallet_balance_required_xof"])
        self.assertEqual(mission["financial_rounding"], self.split)

    async def test_rounding_gain_is_recorded_once_and_never_credited_twice(self):
        now = datetime.now(timezone.utc)
        await self.database.wallets.insert_one({"wallet_id": "wallet", "owner_id": "driver", "balance": 650, "currency": "XOF"})
        parcel = {"parcel_id": "parcel", "assigned_driver_id": "driver", "delivery_mode": "home_to_home",
                  "quoted_price": 2300, "financial_rounding": self.split, "tracking_code": "SYNTHETIC"}
        await wallet_service.distribute_delivery_revenue(parcel)
        await wallet_service.distribute_delivery_revenue(parcel)
        revenues = await self.database.wallet_transactions.find({"tx_type": "revenue"}).to_list(length=None)
        self.assertEqual(len(revenues), 1)
        self.assertEqual(revenues[0]["amount"], self.split["driver_revenue_xof"])
        self.assertEqual((await self.database.wallets.find_one({"wallet_id": "wallet"}))["balance"], 650)
        await self.database.delivery_missions.insert_one({"mission_id": "mission", "parcel_id": "parcel", "driver_id": "driver",
                                                        "status": "completed", "financial_rounding": self.split})
        await self.database.wallet_transactions.insert_one({"tx_id": "extra", "wallet_id": "wallet", "parcel_id": "parcel",
                                                           "tx_type": "revenue", "amount": 50, "created_at": now,
                                                           "reference": "driver_bonus:parcel"})
        with patch.object(wallet_activity_service, "get_or_create_wallet", AsyncMock(return_value={"wallet_id": "wallet"})):
            history = await wallet_activity_service.wallet_activity(self.database, {"user_id": "driver"}, {}, category="revenues")
        self.assertEqual(len([row for row in history["items"] if row.get("financial_rounding")]), 1)


if __name__ == "__main__":
    unittest.main()
