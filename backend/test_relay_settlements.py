import asyncio
from datetime import datetime, timezone
import unittest
from unittest.mock import AsyncMock, patch

from fastapi import FastAPI, HTTPException
import httpx

from core.dependencies import get_current_user
from routers import admin
from services.relay_settlement_service import settlement_actions, settlement_overview, settlement_action_list
from services.wallet_service import default_commission_rules
from tests.fake_database import Database


def parcel(parcel_id="parcel", **changes):
    return {
        "parcel_id": parcel_id, "tracking_code": f"PKP-{parcel_id}",
        "delivery_mode": "relay_to_relay", "status": "delivered", "quoted_price": 2000,
        "origin_relay_id": "origin", "destination_relay_id": "destination",
        "commission_rules_snapshot": default_commission_rules(),
        "created_at": datetime(2025, 1, 1, tzinfo=timezone.utc), **changes,
    }


class SettlementTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.database = Database()
        await self.database.relay_points.insert_one({"relay_id": "origin", "name": "Relais Alpha", "is_active": False})
        await self.database.relay_points.insert_one({"relay_id": "destination", "name": "Relais Bêta", "is_active": True})
        self.notifier = AsyncMock()
        for name, replacement in [("db", self.database), ("notify_relay_settlement_update", self.notifier)]:
            patcher = patch.object(admin, name, replacement)
            patcher.start()
            self.addCleanup(patcher.stop)

    async def seed(self, **changes):
        doc = parcel(**changes)
        await self.database.parcels.insert_one(doc)
        return doc

    async def review(self, **changes):
        return await admin.update_relay_settlement("parcel", {
            "action": "denkma_payment", "status": "validated", "relay_id": "origin",
            "expected_status": "declared", "note": "Wave : référence de test", **changes,
        }, {"user_id": "admin"})

    async def test_current_totals_include_old_unpaid_parcels_and_inactive_relays(self):
        await self.seed()
        overview = await settlement_overview(self.database)
        self.assertEqual(overview["totals"]["to_denkma_xof"], 450)
        self.assertEqual(overview["totals"]["to_relay_xof"], 150)
        self.assertEqual(overview["totals"]["to_driver_xof"], 1400)
        self.assertEqual(overview["totals"]["outstanding_count"], 3)
        origin = next(row for row in overview["relays"] if row["relay_id"] == "origin")
        self.assertEqual(origin["to_relay_xof"], 0)
        self.assertFalse(origin["is_active"])

    async def test_relays_without_activity_are_listed_with_zero_balances(self):
        overview = await settlement_overview(self.database)
        self.assertEqual(overview["total"], 2)
        self.assertTrue(all(row["to_relay_xof"] == 0 and row["to_denkma_xof"] == 0 for row in overview["relays"]))

    async def test_declared_amount_is_still_due_and_driver_is_counted(self):
        await self.seed(relay_settlement={"denkma_payment_status": "declared", "driver_payment_status": "declared"})
        totals = (await settlement_overview(self.database))["totals"]
        self.assertEqual(totals["to_denkma_xof"], 450)
        self.assertEqual(totals["to_denkma_declared_xof"], 450)
        self.assertEqual(totals["declared_count"], 2)
        self.assertEqual((await settlement_action_list(self.database, status="declared"))["total"], 2)

    async def test_validated_payments_are_not_due(self):
        await self.seed(relay_settlement={"denkma_payment_status": "validated", "destination_relay_payment_status": "validated"})
        totals = (await settlement_overview(self.database))["totals"]
        self.assertEqual(totals["to_denkma_xof"], 0)
        self.assertEqual(totals["to_relay_xof"], 0)
        self.assertEqual(totals["to_denkma_validated_xof"], 450)
        self.assertEqual(totals["to_relay_validated_xof"], 150)

    async def test_wallet_credit_is_not_proof_of_external_payment(self):
        await self.seed()
        await self.database.wallet_transactions.insert_one({"reference": "relay_destination_commission:parcel", "amount": 150})
        self.assertEqual((await settlement_overview(self.database))["totals"]["to_relay_xof"], 150)
        overview = await admin.get_finance_overview(period=None, from_date="2025-01-01", to_date="2025-01-31", _admin={"user_id": "admin"})
        self.assertEqual(overview["relays"]["amount_remaining_xof"], 150)
        self.assertEqual(overview["relays"]["amount_already_sent_xof"], 0)

    async def test_commission_is_upcoming_before_delivery(self):
        await self.seed(status="in_transit")
        totals = (await settlement_overview(self.database))["totals"]
        self.assertEqual(totals["to_relay_xof"], 0)
        self.assertEqual(totals["upcoming_to_relay_xof"], 150)
        self.assertEqual(totals["to_denkma_xof"], 450)
        upcoming = (await settlement_action_list(self.database, status="upcoming"))["actions"]
        self.assertFalse(upcoming[0]["can_validate"])

    async def test_before_collection_no_amount_is_due(self):
        await self.seed(status="created")
        totals = (await settlement_overview(self.database))["totals"]
        self.assertEqual(totals["to_denkma_xof"], 0)
        self.assertEqual(totals["to_driver_xof"], 0)
        self.assertEqual(totals["outstanding_count"], 0)

    async def test_redirect_only_pays_effective_destination(self):
        await self.seed(redirect_relay_id="redirect")
        actions = (await settlement_action_list(self.database))["actions"]
        commissions = [item for item in actions if item["direction"] == "to_relay"]
        self.assertEqual([item["relay_id"] for item in commissions], ["redirect"])
        self.assertEqual((await settlement_action_list(self.database, relay_id="destination"))["total"], 0)

    async def test_legacy_mode_and_snapshots_are_used(self):
        rules = default_commission_rules()
        rules["relay_to_relay"] = {"platform_rate": .10, "origin_relay_rate": .10, "destination_relay_rate": .10, "driver_rate": .70}
        await self.seed(delivery_mode="", mode="relay_to_relay", commission_rules_snapshot=rules)
        self.assertEqual((await settlement_overview(self.database))["totals"]["to_denkma_xof"], 400)

    async def test_disabled_commissions_and_zero_amounts_are_not_payable(self):
        await self.seed(delivery_commissions_enabled=False)
        totals = (await settlement_overview(self.database))["totals"]
        self.assertEqual(totals["to_denkma_xof"], 0)
        self.assertEqual(totals["to_relay_xof"], 0)
        self.assertEqual(totals["to_driver_xof"], 2000)

    async def test_invalid_data_is_reported_with_parcel_link_not_a_fake_zero(self):
        await self.seed(delivery_mode="")
        overview = await settlement_overview(self.database)
        self.assertEqual(overview["totals"]["unavailable_count"], 1)
        self.assertTrue(all(row["unavailable_count"] == 1 for row in overview["relays"]))
        issues = await settlement_action_list(self.database, status="issues")
        self.assertEqual(issues["actions"][0]["parcel_id"], "parcel")
        self.assertTrue(issues["actions"][0]["issue"])

    async def test_unknown_settlement_status_is_reported(self):
        await self.seed(relay_settlement={"denkma_payment_status": "bad"})
        self.assertEqual((await settlement_overview(self.database))["totals"]["unavailable_count"], 1)

    async def test_missing_relays_are_reported_instead_of_hiding_the_parcel(self):
        await self.seed(origin_relay_id=None, destination_relay_id=None)
        self.assertEqual((await settlement_overview(self.database))["totals"]["unavailable_count"], 1)

    async def test_notification_failure_does_not_undo_or_duplicate_validation(self):
        await self.seed(relay_settlement={"denkma_payment_status": "declared"})
        self.notifier.side_effect = RuntimeError("Notification indisponible")
        with self.assertLogs("routers.admin", level="ERROR"):
            self.assertTrue((await self.review())["ok"])
        await self.review()
        self.assertEqual((await settlement_overview(self.database))["totals"]["to_denkma_xof"], 0)

    async def test_pagination_search_and_direction_filters_do_not_change_global_totals(self):
        await self.seed()
        overview = await settlement_overview(self.database, search="alpha", limit=1)
        self.assertEqual(overview["total"], 1)
        self.assertEqual(overview["totals"]["to_relay_xof"], 150)
        actions = await settlement_action_list(self.database, limit=1)
        self.assertEqual(actions["total"], 3)
        self.assertTrue(actions["has_more"])
        self.assertEqual((await settlement_action_list(self.database, skip=2, limit=1))["total"], 3)
        self.assertEqual((await settlement_action_list(self.database, direction="to_driver"))["total"], 1)

    async def test_home_modes_have_correct_commission_recipient(self):
        for mode, recipient in [("home_to_relay", "destination"), ("relay_to_home", "origin")]:
            actions = settlement_actions(parcel(delivery_mode=mode))
            commissions = [item for item in actions if item["direction"] == "to_relay"]
            self.assertEqual(commissions[0]["relay_id"], recipient)
            self.assertEqual(commissions[0]["amount_xof"], 300)
            self.assertFalse(any(item["direction"] == "to_denkma" for item in actions))

    async def test_admin_validation_is_audited_and_notifies_correct_relay(self):
        await self.seed(relay_settlement={"denkma_payment_status": "declared"})
        await self.review()
        stored = await self.database.parcels.find_one({"parcel_id": "parcel"})
        history = stored["relay_settlement"]["history"]
        self.assertEqual(history[0]["previous_status"], "declared")
        self.assertEqual(history[0]["amount_xof"], 450)
        self.assertEqual(history[0]["reviewed_by"], "admin")
        self.notifier.assert_awaited_once()
        self.assertEqual(self.notifier.call_args.args[0], "origin")
        self.assertEqual((await settlement_overview(self.database))["totals"]["to_denkma_xof"], 0)

    async def test_admin_can_record_paid_commission_but_not_undeclared_relay_debt(self):
        await self.seed()
        await self.review(action="destination_relay_payment", relay_id="destination", expected_status="pending")
        with self.assertRaises(HTTPException) as error:
            await self.review(expected_status="pending")
        self.assertEqual(error.exception.status_code, 409)

    async def test_reference_rejection_reason_and_applicability_are_required(self):
        await self.seed(relay_settlement={"denkma_payment_status": "declared"})
        for changes in [{"note": ""}, {"status": "rejected", "note": ""}, {"relay_id": "destination"}, {"action": "origin_relay_payment"}]:
            with self.assertRaises(HTTPException) as error:
                await self.review(**changes)
            self.assertEqual(error.exception.status_code, 400)

    async def test_rejected_amount_stays_due(self):
        await self.seed(relay_settlement={"denkma_payment_status": "declared"})
        await self.review(status="rejected", note="Paiement non reçu")
        totals = (await settlement_overview(self.database))["totals"]
        self.assertEqual(totals["to_denkma_xof"], 450)
        self.assertEqual(totals["rejected_count"], 1)

    async def test_stale_admin_request_cannot_overwrite_payment(self):
        await self.seed(relay_settlement={"denkma_payment_status": "declared"})
        await self.review()
        with self.assertRaises(HTTPException) as error:
            await self.review(status="rejected")
        self.assertEqual(error.exception.status_code, 409)
        stored = await self.database.parcels.find_one({"parcel_id": "parcel"})
        self.assertEqual(stored["relay_settlement"]["denkma_payment_status"], "validated")

    async def test_displayed_amount_and_parcel_version_are_checked(self):
        now = datetime(2026, 10, 2, tzinfo=timezone.utc)
        await self.seed(updated_at=now, relay_settlement={"denkma_payment_status": "declared"})
        for changes in [{"expected_amount_xof": 500}, {"expected_updated_at": "2026-10-01T00:00:00Z"}]:
            with self.assertRaises(HTTPException) as error:
                await self.review(**changes)
            self.assertEqual(error.exception.status_code, 409)
        self.assertTrue((await self.review(expected_amount_xof=450, expected_updated_at=now.isoformat()))["ok"])

    async def test_identical_retry_is_idempotent(self):
        await self.seed(relay_settlement={"denkma_payment_status": "declared"})
        await self.review()
        await self.review()
        stored = await self.database.parcels.find_one({"parcel_id": "parcel"})
        self.assertEqual(len(stored["relay_settlement"]["history"]), 1)
        self.notifier.assert_awaited_once()

    async def test_concurrent_updates_cannot_both_change_the_same_status(self):
        await self.seed(relay_settlement={"denkma_payment_status": "declared"})
        responses = await asyncio.gather(self.review(), self.review(status="rejected"), return_exceptions=True)
        self.assertEqual(sum(isinstance(item, HTTPException) for item in responses), 1)
        stored = await self.database.parcels.find_one({"parcel_id": "parcel"})
        self.assertEqual(len(stored["relay_settlement"]["history"]), 1)

    async def test_relay_accounts_cannot_access_admin_finance(self):
        app = FastAPI()
        app.include_router(admin.router, prefix="/api/admin")
        app.dependency_overrides[get_current_user] = lambda: {"user_id": "relay_owner", "role": "relay_agent"}
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
            for url in ["/api/admin/finance/relay-settlements", "/api/admin/finance/relay-settlements/actions"]:
                self.assertEqual((await client.get(url)).status_code, 403)
            self.assertEqual((await client.post("/api/admin/parcels/parcel/relay-settlement", json={})).status_code, 403)


if __name__ == "__main__":
    unittest.main()
