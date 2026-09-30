from copy import deepcopy
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from fastapi import HTTPException

from models.user import ProfileUpdate
from models.relay_point import RelayPointUpdate
from routers import users, relay_points


class Collection:
    def __init__(self, document):
        self.document = deepcopy(document)
        self.writes = []

    async def find_one(self, query, projection=None):
        if "email" in query:
            return None
        return deepcopy(self.document)

    async def update_one(self, query, update):
        self.writes.append(deepcopy(update))
        self.document.update(deepcopy(update["$set"]))


class ProfileSettingsTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.account = {"user_id": "user", "role": "relay_agent", "email": "old@example.com", "bio": "Old bio"}
        self.accounts = Collection(self.account)
        self.relay = {
            "relay_id": "relay", "owner_user_id": "user", "name": "Boutique",
            "description": "Old instructions", "is_active": True, "opening_hours": None,
            "address": {"label": "Rue 1", "city": "Dakar", "notes": "Entrée latérale"},
        }
        self.relays = Collection(self.relay)
        self.database = SimpleNamespace(users=self.accounts, relay_points=self.relays)
        for module in (users, relay_points):
            patcher = patch.object(module, "db", self.database)
            patcher.start()
            self.addCleanup(patcher.stop)

    async def test_explicit_empty_email_and_bio_are_removed(self):
        result = await users.update_my_profile(ProfileUpdate(email="  ", bio=""), self.account)
        self.assertIsNone(result["email"])
        self.assertIsNone(result["bio"])
        self.assertEqual(result["user_id"], "user")

    async def test_omitted_fields_are_preserved(self):
        result = await users.update_my_profile(ProfileUpdate(bio="New bio"), self.account)
        self.assertEqual(result["email"], "old@example.com")
        self.assertEqual(result["bio"], "New bio")

    async def test_empty_body_has_no_write(self):
        result = await users.update_my_profile(ProfileUpdate(), self.account)
        self.assertEqual(result, self.account)
        self.assertEqual(self.accounts.writes, [])

    async def test_notification_update_preserves_identity_and_hidden_email_preference(self):
        result = await users.update_my_profile(ProfileUpdate(notification_prefs={
            "push": False, "email": False, "whatsapp": True, "parcel_updates": True, "promotions": False,
        }), self.account)
        self.assertEqual(result["email"], "old@example.com")
        self.assertEqual(result["bio"], "Old bio")
        self.assertFalse(result["notification_prefs"]["email"])

    async def test_relay_can_clear_public_instructions_without_losing_address(self):
        result = await relay_points.update_relay_point("relay", RelayPointUpdate(description="  "), self.account)
        self.assertIsNone(result["description"])
        self.assertEqual(result["address"], self.relay["address"])
        self.assertEqual(result["name"], "Boutique")

    async def test_omitted_relay_description_is_preserved(self):
        result = await relay_points.update_relay_point("relay", RelayPointUpdate(name="Nouvelle boutique"), self.account)
        self.assertEqual(result["description"], "Old instructions")

    async def test_other_account_cannot_edit_relay(self):
        with self.assertRaises(HTTPException) as error:
            await relay_points.update_relay_point("relay", RelayPointUpdate(description=""), {"user_id": "other", "role": "relay_agent"})
        self.assertEqual(error.exception.status_code, 403)
        self.assertEqual(self.relays.writes, [])


if __name__ == "__main__":
    unittest.main()
