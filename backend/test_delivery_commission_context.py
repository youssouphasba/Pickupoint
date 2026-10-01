import copy
import unittest
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from fastapi import FastAPI, HTTPException
import httpx

from core.dependencies import get_current_user
from core.exceptions import DeliveryCommissionDataError
from models.common import DeliveryMode, ParcelStatus
from routers.admin import get_finance_overview
from routers.deliveries import (
    _attach_commission_requirements,
    accept_mission,
    available_missions,
    mission_preview,
    router as deliveries_router,
)
from services.parcel_service import _create_delivery_mission, _default_delivery_dispatch_settings
from services.wallet_service import (
    COMMISSION_MODES,
    commission_rules_for,
    compute_delivery_commission_breakdown,
    resolve_delivery_commission_mode,
)


RULES = {
    "home_to_home": {"platform_rate": 0.1, "origin_relay_rate": 0, "destination_relay_rate": 0, "driver_rate": 0.9},
    "home_to_relay": {"platform_rate": 0.2, "origin_relay_rate": 0, "destination_relay_rate": 0.25, "driver_rate": 0.55},
    "relay_to_home": {"platform_rate": 0.15, "origin_relay_rate": 0.25, "destination_relay_rate": 0, "driver_rate": 0.6},
    "relay_to_relay": {"platform_rate": 0.2, "origin_relay_rate": 0.1, "destination_relay_rate": 0.3, "driver_rate": 0.4},
}
DRIVER = {
    "user_id": "driver-1",
    "role": "driver",
    "is_available": True,
    "profile_picture_url": "https://example.test/photo",
    "profile_picture_status": "approved",
}


class ProjectedCollection:
    def __init__(self, rows):
        self.rows = rows
        self.projections = []

    def find(self, query, projection):
        self.projections.append(projection)
        rows = copy.deepcopy(self.rows)
        for key, expected in query.items():
            if isinstance(expected, dict) and "$in" in expected:
                rows = [row for row in rows if row.get(key) in expected["$in"]]
            elif isinstance(expected, dict) and "$gte" in expected:
                rows = [row for row in rows if row.get(key) is not None and expected["$gte"] <= row[key] <= expected["$lte"]]
            else:
                rows = [row for row in rows if row.get(key) == expected]
        included = {key for key, enabled in projection.items() if enabled}
        if included:
            rows = [{key: value for key, value in row.items() if key in included} for row in rows]
        return SimpleNamespace(to_list=AsyncMock(return_value=rows))


def parcel(mode="home_to_home", parcel_id="parcel-1"):
    return {
        "parcel_id": parcel_id,
        "status": "created",
        "delivery_mode": mode,
        "quoted_price": 2000,
        "created_at": datetime.now(timezone.utc),
        "commission_rules_snapshot": copy.deepcopy(RULES),
        "sender_name": "Expéditeur",
        "recipient_name": "Destinataire",
        "recipient_phone": "+221770000000",
    }


def mission(parcel_id="parcel-1", mission_id="mission-1"):
    return {
        "mission_id": mission_id,
        "parcel_id": parcel_id,
        "status": "pending",
        "is_broadcast": True,
        "pickup_geopin": {"lat": 49.2587, "lng": 2.4297},
        "delivery_geopin": {"lat": 49.2588, "lng": 2.4298},
        "quoted_price": 2000,
        "created_at": datetime.now(timezone.utc),
    }


class DeliveryCommissionModeTests(unittest.TestCase):
    def test_old_mission_uses_the_actual_parcel_mode_for_every_flow(self):
        for mode in COMMISSION_MODES:
            with self.subTest(mode=mode):
                result = compute_delivery_commission_breakdown(parcel(mode), mission())
                rules = RULES[mode]
                self.assertEqual(result["platform_commission_xof"], 2000 * rules["platform_rate"])
                self.assertEqual(result["origin_relay_commission_xof"], 2000 * rules["origin_relay_rate"])
                self.assertEqual(result["destination_relay_commission_xof"], 2000 * rules["destination_relay_rate"])
                self.assertEqual(result["driver_revenue_xof"], 2000 * rules["driver_rate"])
                self.assertAlmostEqual(result["wallet_balance_required_xof"], 2000 * (1 - rules["driver_rate"]))

    def test_blank_mission_mode_does_not_erase_parcel_mode(self):
        result = compute_delivery_commission_breakdown(parcel(), {**mission(), "delivery_mode": " "})
        self.assertEqual(result["total_commission_xof"], 200)

    def test_enum_mode_and_legacy_mode_field_are_supported(self):
        self.assertEqual(resolve_delivery_commission_mode({"delivery_mode": DeliveryMode.HOME_TO_HOME}), "home_to_home")
        self.assertEqual(resolve_delivery_commission_mode({"mode": "relay_to_home"}), "relay_to_home")

    def test_null_mission_snapshot_preserves_the_parcel_rules(self):
        for snapshot in (None, {}):
            with self.subTest(snapshot=snapshot):
                result = compute_delivery_commission_breakdown(
                    parcel(), {**mission(), "commission_rules_snapshot": snapshot},
                )
                self.assertEqual(result["platform_commission_xof"], 200)

    def test_mission_snapshot_remains_authoritative(self):
        snapshot = copy.deepcopy(RULES)
        snapshot["home_to_home"]["platform_rate"] = 0.3
        snapshot["home_to_home"]["driver_rate"] = 0.7
        result = compute_delivery_commission_breakdown(parcel(), {"commission_rules_snapshot": snapshot})
        self.assertEqual(result["platform_commission_xof"], 600)

    def test_null_mission_preference_preserves_disabled_commissions(self):
        result = compute_delivery_commission_breakdown(
            {**parcel(), "delivery_commissions_enabled": False},
            {"delivery_commissions_enabled": None},
        )
        self.assertEqual(result["total_commission_xof"], 0)
        self.assertEqual(result["driver_revenue_xof"], 2000)

    def test_unknown_modes_never_fall_back_to_an_arbitrary_flow(self):
        for mode in (None, "", " ", "unknown"):
            with self.subTest(mode=mode):
                with self.assertRaises(DeliveryCommissionDataError) as caught:
                    compute_delivery_commission_breakdown({**parcel(), "delivery_mode": mode})
                self.assertEqual(caught.exception.status_code, 409)

    def test_direct_rules_lookup_rejects_invalid_modes_with_or_without_snapshot(self):
        for source in ({}, {"commission_rules_snapshot": RULES}):
            with self.subTest(source=source):
                with self.assertRaises(DeliveryCommissionDataError):
                    commission_rules_for(source, "")


class MissionCommissionContextTests(unittest.IsolatedAsyncioTestCase):
    async def test_http_old_notification_and_second_course_return_200(self):
        app = FastAPI()
        app.include_router(deliveries_router, prefix="/api/deliveries")
        app.dependency_overrides[get_current_user] = lambda: DRIVER
        collection = ProjectedCollection([mission(), mission("parcel-2", "mission-2")])
        collection.find_one = AsyncMock(return_value=mission())
        fake_db = SimpleNamespace(
            parcels=ProjectedCollection([parcel(), parcel("relay_to_relay", "parcel-2")]),
            delivery_missions=collection,
        )
        with (
            patch("routers.deliveries.db", fake_db),
            patch("routers.deliveries._hydrate_mission_area_labels", AsyncMock()),
            patch("routers.deliveries.get_directions_eta", AsyncMock(return_value=None)),
        ):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
                response = await client.get("/api/deliveries/available", params={"lat": 49.2587, "lng": 2.4297, "radius_km": 5})
                self.assertEqual(response.status_code, 200)
                self.assertEqual(len(response.json()["missions"]), 2)
                preview = await client.get("/api/deliveries/mission-1/preview", params={"lat": 49.2587, "lng": 2.4297})
                self.assertEqual(preview.status_code, 200)
                self.assertEqual(preview.json()["mission"]["wallet_balance_required_xof"], 200)

    async def test_http_unrecoverable_course_returns_409_before_acceptance(self):
        app = FastAPI()
        app.include_router(deliveries_router, prefix="/api/deliveries")
        app.dependency_overrides[get_current_user] = lambda: DRIVER
        update = AsyncMock()
        fake_db = SimpleNamespace(
            delivery_missions=SimpleNamespace(find_one=AsyncMock(side_effect=[mission(), None]), update_one=update),
            parcels=SimpleNamespace(find_one=AsyncMock(return_value=parcel(None))),
        )
        with patch("routers.deliveries.db", fake_db):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
                response = await client.post("/api/deliveries/mission-1/accept")
        self.assertEqual(response.status_code, 409)
        self.assertIn("mode de livraison", response.json()["detail"])
        update.assert_not_awaited()

    async def test_list_projection_restores_old_missions_for_every_flow(self):
        rows = [parcel(mode, f"parcel-{mode}") for mode in COMMISSION_MODES]
        missions = [mission(row["parcel_id"]) for row in rows]
        collection = ProjectedCollection(rows)
        with patch("routers.deliveries.db", SimpleNamespace(parcels=collection)):
            await _attach_commission_requirements(missions)
        self.assertEqual(collection.projections[0]["delivery_mode"], 1)
        self.assertEqual(collection.projections[0]["commission_rules_snapshot"], 1)
        for row in missions:
            mode = row["delivery_mode"]
            self.assertAlmostEqual(row["total_commission_xof"], 2000 * (1 - RULES[mode]["driver_rate"]))
            self.assertNotIn("commission_data_unavailable", row)

    async def test_existing_commission_amounts_are_preserved(self):
        row = {**mission(), "total_commission_xof": 175, "wallet_balance_required_xof": 175}
        with patch("routers.deliveries.db", SimpleNamespace(parcels=ProjectedCollection([parcel()]))):
            await _attach_commission_requirements([row])
        self.assertEqual(row["total_commission_xof"], 175)
        self.assertEqual(row["wallet_balance_required_xof"], 175)

    async def test_missing_mode_is_flagged_without_fabricating_amounts_or_erasing_history(self):
        rows = [mission(), {**mission("missing-parcel", "historical"), "status": "completed", "total_commission_xof": 125}]
        with patch("routers.deliveries.db", SimpleNamespace(parcels=ProjectedCollection([parcel()]))):
            await _attach_commission_requirements(rows)
        self.assertEqual(len(rows), 2)
        self.assertTrue(rows[1]["commission_data_unavailable"])
        self.assertEqual(rows[1]["total_commission_xof"], 125)
        self.assertNotIn("wallet_balance_required_xof", rows[1])

    async def test_available_endpoint_keeps_both_old_and_new_valid_courses(self):
        rows = [mission(), mission("parcel-2", "mission-2")]
        rows[1]["commission_rules_snapshot"] = RULES
        fake_db = SimpleNamespace(
            parcels=ProjectedCollection([parcel(), parcel("home_to_relay", "parcel-2")]),
            delivery_missions=ProjectedCollection(rows),
        )
        with patch("routers.deliveries.db", fake_db):
            result = await available_missions(lat=49.2587, lng=2.4297, radius_km=5, current_user=DRIVER)
        self.assertEqual(len(result["missions"]), 2)
        self.assertEqual(result["missions"][0]["wallet_balance_required_xof"], 200)
        self.assertEqual(result["missions"][1]["wallet_balance_required_xof"], 900)
        self.assertTrue(all(row["recipient_phone"] is None for row in result["missions"]))

    async def test_one_unrecoverable_course_does_not_break_the_available_list(self):
        fake_db = SimpleNamespace(
            parcels=ProjectedCollection([parcel(), parcel(None, "parcel-2")]),
            delivery_missions=ProjectedCollection([mission(), mission("parcel-2", "mission-2")]),
        )
        with patch("routers.deliveries.db", fake_db):
            result = await available_missions(lat=49.2587, lng=2.4297, radius_km=5, current_user=DRIVER)
        self.assertEqual([row["mission_id"] for row in result["missions"]], ["mission-1"])

    async def test_preview_of_old_valid_notification_uses_actual_commissions(self):
        fake_db = SimpleNamespace(
            parcels=ProjectedCollection([parcel()]),
            delivery_missions=SimpleNamespace(find_one=AsyncMock(return_value=mission())),
        )
        with (
            patch("routers.deliveries.db", fake_db),
            patch("routers.deliveries._hydrate_mission_area_labels", AsyncMock()),
            patch("routers.deliveries.get_directions_eta", AsyncMock(return_value=None)),
        ):
            result = await mission_preview("mission-1", lat=49.2587, lng=2.4297, current_user=DRIVER)
        self.assertEqual(result["mission"]["wallet_balance_required_xof"], 200)

    async def test_preview_of_invalid_course_returns_a_clear_conflict_not_500(self):
        fake_db = SimpleNamespace(
            parcels=ProjectedCollection([parcel(None)]),
            delivery_missions=SimpleNamespace(find_one=AsyncMock(return_value=mission())),
        )
        with patch("routers.deliveries.db", fake_db):
            with self.assertRaises(DeliveryCommissionDataError) as caught:
                await mission_preview("mission-1", lat=49.2587, lng=2.4297, current_user=DRIVER)
        self.assertEqual(caught.exception.status_code, 409)

    async def test_notification_for_taken_course_does_not_reopen_it(self):
        fake_db = SimpleNamespace(
            delivery_missions=SimpleNamespace(find_one=AsyncMock(return_value={**mission(), "status": "assigned"})),
        )
        with patch("routers.deliveries.db", fake_db):
            with self.assertRaises(HTTPException) as caught:
                await mission_preview("mission-1", lat=49.2587, lng=2.4297, current_user=DRIVER)
        self.assertEqual(caught.exception.status_code, 403)

    async def test_invalid_mode_cannot_be_accepted_or_change_wallet_or_mission(self):
        update = AsyncMock()
        wallet_lookup = AsyncMock()
        debit = AsyncMock()
        fake_db = SimpleNamespace(
            delivery_missions=SimpleNamespace(find_one=AsyncMock(side_effect=[mission(), None]), update_one=update),
            parcels=SimpleNamespace(find_one=AsyncMock(return_value=parcel(None))),
            wallets=SimpleNamespace(find_one=wallet_lookup),
        )
        with patch("routers.deliveries.db", fake_db), patch("routers.deliveries.debit_wallet", debit):
            with self.assertRaises(DeliveryCommissionDataError):
                await accept_mission("mission-1", body=None, current_user=DRIVER)
        wallet_lookup.assert_not_awaited()
        debit.assert_not_awaited()
        update.assert_not_awaited()

    async def test_new_missions_persist_the_original_mode_for_every_flow(self):
        relay = {"name": "Relais", "address": {"city": "Ville", "geopin": {"lat": 49.2587, "lng": 2.4297}}}
        for mode in COMMISSION_MODES:
            with self.subTest(mode=mode):
                row = {
                    **parcel(mode),
                    "pickup_confirmed": True,
                    "delivery_confirmed": True,
                    "origin_relay_id": "origin" if mode.startswith("relay_") else None,
                    "destination_relay_id": "destination" if mode.endswith("_relay") else None,
                    "origin_location": relay["address"],
                    "delivery_address": relay["address"],
                }
                insert = AsyncMock()
                fake_db = SimpleNamespace(
                    delivery_missions=SimpleNamespace(find_one=AsyncMock(return_value=None), insert_one=insert),
                    relay_points=SimpleNamespace(find_one=AsyncMock(return_value=relay)),
                )
                with (
                    patch("services.parcel_service.db", fake_db),
                    patch("services.parcel_service.get_delivery_dispatch_settings", AsyncMock(return_value=_default_delivery_dispatch_settings())),
                    patch("services.parcel_service._find_candidate_drivers_within_radius", AsyncMock(return_value=[])),
                ):
                    status = ParcelStatus.CREATED if mode.startswith("home_") else ParcelStatus.DROPPED_AT_ORIGIN_RELAY
                    await _create_delivery_mission(row, status)
                created = insert.await_args.args[0]
                self.assertEqual(created["delivery_mode"], mode)
                self.assertEqual(created["commission_rules_snapshot"], RULES)
                self.assertAlmostEqual(created["wallet_balance_required_xof"], 2000 * (1 - RULES[mode]["driver_rate"]))


class FinanceCommissionContextTests(unittest.IsolatedAsyncioTestCase):
    async def overview(self, parcels, missions):
        fake_db = SimpleNamespace(
            parcels=ProjectedCollection(parcels),
            delivery_missions=ProjectedCollection(missions),
            payout_requests=ProjectedCollection([]),
            wallet_topups=ProjectedCollection([]),
            wallets=ProjectedCollection([]),
            wallet_transactions=ProjectedCollection([]),
            users=ProjectedCollection([]),
        )
        with patch("routers.admin.db", fake_db):
            return await get_finance_overview(
                period=datetime.now(timezone.utc).strftime("%Y-%m"),
                from_date=None, to_date=None, _admin={"role": "admin"},
            )

    async def test_overview_keeps_valid_totals_and_exposes_unrecoverable_courses(self):
        result = await self.overview([parcel()], [mission(), mission("missing", "invalid-mission")])
        self.assertEqual(result["commissions"]["platform_amount_xof"], 200)
        self.assertTrue(result["commissions"]["totals_incomplete"])
        self.assertEqual(result["commissions"]["unavailable_count"], 1)
        issue = result["alerts"][0]["items"][0]
        self.assertEqual(issue["id"], "invalid-mission")
        self.assertNotIn("amount_xof", issue)
        self.assertIn("exclues des totaux", issue["meta"])

    async def test_delivered_parcel_without_mode_does_not_break_finance(self):
        result = await self.overview([{**parcel(None), "status": "delivered"}], [mission()])
        self.assertEqual(result["commissions"]["platform_amount_xof"], 0)
        self.assertEqual(result["commissions"]["unavailable_count"], 1)
        self.assertEqual(result["payments"]["delivered_parcels"], 1)

    async def test_disabled_commissions_are_respected_in_overview(self):
        result = await self.overview([{**parcel(), "delivery_commissions_enabled": False}], [mission()])
        self.assertEqual(result["commissions"]["total_amount_xof"], 0)
        self.assertFalse(result["commissions"]["totals_incomplete"])

    async def test_mission_outside_parcel_creation_month_still_has_real_commissions(self):
        old_parcel = parcel()
        old_parcel["created_at"] = datetime(2000, 1, 1, tzinfo=timezone.utc)
        result = await self.overview([old_parcel], [mission()])
        self.assertEqual(result["payments"]["total_parcels"], 0)
        self.assertEqual(result["commissions"]["platform_amount_xof"], 200)
        self.assertFalse(result["commissions"]["totals_incomplete"])


if __name__ == "__main__":
    unittest.main()
