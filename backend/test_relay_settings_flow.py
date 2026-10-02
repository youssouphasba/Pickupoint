from copy import deepcopy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

from fastapi import FastAPI, HTTPException
import httpx

from core.dependencies import get_current_user
from models.relay_point import RelayLocationReview, RelayPointUpdate
from routers import relay_points
from services import pin_verification


def value(doc, key):
    for part in key.split("."):
        doc = doc.get(part) if isinstance(doc, dict) else None
    return doc


def matches(doc, query):
    for key, expected in query.items():
        if key == "$or":
            if not any(matches(doc, clause) for clause in expected):
                return False
        elif isinstance(expected, dict) and "$in" in expected:
            if value(doc, key) not in expected["$in"]:
                return False
        elif value(doc, key) != expected:
            return False
    return True


class Cursor:
    def __init__(self, rows):
        self.rows = deepcopy(rows)

    def sort(self, *args):
        return self

    async def to_list(self, length=None):
        return self.rows if length is None else self.rows[:length]

    def __aiter__(self):
        self.iterator = iter(self.rows)
        return self

    async def __anext__(self):
        try:
            return next(self.iterator)
        except StopIteration:
            raise StopAsyncIteration


class Collection:
    def __init__(self, rows):
        self.rows = deepcopy(rows)

    async def find_one(self, query, projection=None):
        return next((deepcopy(row) for row in self.rows if matches(row, query)), None)

    def find(self, query, projection=None):
        return Cursor([row for row in self.rows if matches(row, query)])

    async def update_one(self, query, update):
        for row in self.rows:
            if matches(row, query):
                for key, val in update.get("$set", {}).items():
                    parent = row
                    parts = key.split(".")
                    for part in parts[:-1]:
                        parent = parent.setdefault(part, {})
                    parent[parts[-1]] = deepcopy(val)
                return SimpleNamespace(matched_count=1)
        return SimpleNamespace(matched_count=0)


class RelayFlowTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.owner = {"user_id": "owner", "role": "relay_agent", "relay_point_id": "relay"}
        self.admin = {"user_id": "admin", "role": "admin"}
        self.address = {"label": "Adresse actuelle", "city": "Dakar", "geopin": {"lat": 14.7, "lng": -17.4}}
        self.proposed = {"label": "Nouvelle adresse", "city": "Dakar", "geopin": {"lat": 14.8, "lng": -17.5}}
        self.relays = Collection([{"relay_id": "relay", "owner_user_id": "owner", "name": "Boutique", "address": self.address, "is_verified": True, "is_active": True}])
        self.parcels = Collection([])
        self.users = Collection([])
        self.database = SimpleNamespace(relay_points=self.relays, parcels=self.parcels, users=self.users)
        patcher = patch.object(relay_points, "db", self.database)
        patcher.start(); self.addCleanup(patcher.stop)
        self.events = AsyncMock()
        patcher = patch.object(relay_points, "record_admin_event", self.events)
        patcher.start(); self.addCleanup(patcher.stop)
        patcher = patch.object(relay_points, "geocode_relay_address", AsyncMock(side_effect=lambda address: address))
        patcher.start(); self.addCleanup(patcher.stop)

    async def request(self):
        return await relay_points.update_relay_point("relay", RelayPointUpdate(address=self.proposed), self.owner)

    def parcel(self, **changes):
        return {"parcel_id": "parcel", "tracking_code": "PKP-TEST", "status": "delivered", "delivery_mode": "relay_to_relay", "quoted_price": 2000,
                "origin_relay_id": "relay", "destination_relay_id": "other", "pickup_code": "secret", **changes}

    async def payments(self, **kwargs):
        return await relay_points.relay_financial_actions("relay", skip=kwargs.get("skip", 0), limit=kwargs.get("limit", 20), pending_only=kwargs.get("pending_only", True), current_user=self.owner)

    async def test_unrelated_changes_do_not_require_new_location(self):
        result = await relay_points.update_relay_point("relay", RelayPointUpdate(name="Nouveau nom"), self.owner)
        self.assertEqual(result["address"], self.address)
        self.assertNotIn("location_change_request", result)

    def test_legacy_coordinates_are_preserved_without_database_mutation(self):
        legacy = {"address": "Adresse existante", "latitude": 14.7, "longitude": -17.4, "city": "Dakar"}
        self.assertEqual(relay_points._relay_address(legacy)["geopin"], self.address["geopin"])
        self.assertIsInstance(legacy["address"], str)

    async def test_request_does_not_change_public_location_or_verification(self):
        result = await self.request()
        self.assertEqual(result["address"], self.address)
        self.assertTrue(result["is_verified"])
        self.assertEqual(result["location_change_request"]["status"], "pending")
        public = await relay_points.get_relay_point("relay", None)
        self.assertNotIn("location_change_request", public)
        self.assertEqual(public["address"], self.address)
        self.events.assert_awaited_once()

    async def test_manager_can_see_pending_proposal(self):
        await self.request()
        result = await relay_points.get_relay_point("relay", self.owner)
        self.assertEqual(result["location_change_request"]["address"]["geopin"]["lat"], 14.8)

    async def test_approval_changes_only_the_requested_location(self):
        proposal = (await self.request())["location_change_request"]
        result = await relay_points.review_relay_location("relay", RelayLocationReview(request_id=proposal["request_id"], decision="approved"), self.admin)
        self.assertEqual(result["address"]["geopin"]["lat"], 14.8)
        self.assertEqual(result["latitude"], 14.8)
        self.assertEqual(result["longitude"], -17.5)
        self.assertEqual(result["location_change_request"]["previous_address"], self.address)
        self.assertEqual(result["location_change_request"]["status"], "approved")

    async def test_rejection_keeps_original_location_and_reason(self):
        proposal = (await self.request())["location_change_request"]
        result = await relay_points.review_relay_location("relay", RelayLocationReview(request_id=proposal["request_id"], decision="rejected", reason="Position incorrecte"), self.admin)
        self.assertEqual(result["address"], self.address)
        self.assertEqual(result["location_change_request"]["reason"], "Position incorrecte")

    async def test_rejection_requires_reason_and_stale_request_cannot_be_approved(self):
        proposal = (await self.request())["location_change_request"]
        for body, status in [(RelayLocationReview(request_id=proposal["request_id"], decision="rejected"), 400), (RelayLocationReview(request_id="old", decision="approved"), 409)]:
            with self.assertRaises(HTTPException) as error:
                await relay_points.review_relay_location("relay", body, self.admin)
            self.assertEqual(error.exception.status_code, status)

    async def test_owner_cannot_approve_own_proposal_through_api(self):
        app = FastAPI(); app.include_router(relay_points.router, prefix="/api/relay-points")
        app.dependency_overrides[get_current_user] = lambda: self.owner
        proposal = (await self.request())["location_change_request"]
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post("/api/relay-points/relay/location-review", json={"request_id": proposal["request_id"], "decision": "approved"})
        self.assertEqual(response.status_code, 403)

    async def test_completed_parcel_still_has_two_actions_not_one_parcel_count(self):
        self.parcels.rows = [self.parcel()]
        result = await self.payments(limit=1)
        self.assertEqual(result["pending_count"], 2)
        self.assertEqual(len(result["actions"]), 1)
        self.assertTrue(result["has_more"])
        self.assertNotIn("pickup_code", result["actions"][0])

    async def test_declared_payments_leave_badge_but_stay_in_follow_up(self):
        self.parcels.rows = [self.parcel(relay_settlement={"driver_payment_status": "declared", "denkma_payment_status": "validated"})]
        self.assertEqual((await self.payments())["pending_count"], 0)
        self.assertEqual(len((await self.payments(pending_only=False))["actions"]), 2)

    async def test_driver_beneficiary_is_identified_without_private_user_data(self):
        self.parcels.rows = [self.parcel(assigned_driver_id="driver")]
        self.users.rows = [{"user_id": "driver", "name": "Livreur Test", "phone": "+221770000000", "pin_hash": "secret"}]
        result = await self.payments()
        action = next(item for item in result["actions"] if item["key"] == "driver_payment")
        self.assertEqual(action["beneficiary_name"], "Livreur Test")
        self.assertEqual(action["beneficiary_phone"], "+221770000000")
        self.assertNotIn("pin_hash", action)

    async def test_commission_beneficiary_is_relay_not_denkma(self):
        self.parcels.rows = [self.parcel(origin_relay_id="other", destination_relay_id="relay")]
        result = await self.payments(pending_only=False)
        action = next(item for item in result["actions"] if item["key"] == "relay_commission")
        self.assertEqual(action["beneficiary_name"], "Boutique")
        self.assertFalse(action["actionable"])

    async def test_rejected_declaration_is_actionable_again(self):
        self.parcels.rows = [self.parcel(relay_settlement={"driver_payment_status": "rejected", "denkma_payment_status": "validated"})]
        result = await self.payments()
        self.assertEqual(result["pending_count"], 1)
        self.assertEqual(result["actions"][0]["status"], "rejected")

    async def test_before_collection_and_unrelated_parcels_are_excluded(self):
        self.parcels.rows = [self.parcel(status="dropped_at_origin_relay"), self.parcel(origin_relay_id="elsewhere")]
        self.assertEqual((await self.payments())["pending_count"], 0)

    async def test_invalid_data_is_flagged_not_a_500(self):
        self.parcels.rows = [self.parcel(delivery_mode="")]
        result = await self.payments()
        self.assertEqual(result["unavailable_count"], 1)

    async def test_another_relay_cannot_read_financial_actions(self):
        with self.assertRaises(HTTPException) as error:
            await relay_points.relay_financial_actions("relay", skip=0, limit=20, pending_only=True, current_user={"user_id": "outsider", "role": "relay_agent"})
        self.assertEqual(error.exception.status_code, 403)


class PinVerificationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.users = SimpleNamespace(update_one=AsyncMock(), find_one_and_update=AsyncMock(return_value={"pin_failed_attempts": 5}))
        patcher = patch.object(pin_verification, "db", SimpleNamespace(users=self.users)); patcher.start(); self.addCleanup(patcher.stop)
        patcher = patch.object(pin_verification, "verify_password", lambda pin, hashed: pin == "1234"); patcher.start(); self.addCleanup(patcher.stop)

    async def test_valid_pin_clears_failures_without_creating_session(self):
        await pin_verification.verify_user_pin({"user_id": "user", "pin_hash": "hash"}, "1234")
        self.assertIn("$unset", self.users.update_one.call_args.args[1])

    async def test_wrong_pin_increments_attempts_and_locks(self):
        with self.assertRaises(HTTPException):
            await pin_verification.verify_user_pin({"user_id": "user", "pin_hash": "hash"}, "9999")
        self.assertEqual(self.users.find_one_and_update.call_args.args[1], {"$inc": {"pin_failed_attempts": 1}})
        self.assertIn("pin_locked_until", self.users.update_one.call_args.args[1]["$set"])

    async def test_active_pin_lock_prevents_verification(self):
        with self.assertRaises(HTTPException):
            await pin_verification.verify_user_pin({"user_id": "user", "pin_hash": "hash", "pin_locked_until": datetime.now(timezone.utc) + timedelta(minutes=5)}, "1234")
        self.users.find_one_and_update.assert_not_awaited()


if __name__ == "__main__":
    unittest.main()
