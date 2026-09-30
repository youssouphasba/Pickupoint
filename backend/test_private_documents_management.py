from copy import deepcopy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, Mock, patch

from bson import ObjectId
from cryptography.fernet import Fernet
from fastapi import FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
import httpx
import pyotp
from starlette.requests import Request

from config import settings
from core import dependencies
from core.admin_mfa import admin_mfa_key_id, valid_admin_mfa_session
from core.private_documents import legacy_kyc_path, validate_kyc_reference
from routers import admin, admin_auth, applications, users
from scripts import secure_kyc_documents
from services import data_retention_service


class AdminMfaTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.secret = pyotp.random_base32()
        self.user = {"user_id": "synthetic-admin", "email": "synthetic@example.com", "role": "admin",
                     "admin_password_hash": "synthetic-hash", "is_active": True}
        self.collection = SimpleNamespace(find_one=AsyncMock(side_effect=lambda *a, **kw: deepcopy(self.user)),
            update_one=AsyncMock(return_value=SimpleNamespace(modified_count=1)),
            find_one_and_update=AsyncMock(return_value={"admin_mfa_failed_attempts": 1}))
        for target, name, value in ((settings, "ADMIN_MFA_TOTP_SECRETS", {self.user["email"]: self.secret}),
                (settings, "ADMIN_REQUIRE_MFA", False), (settings, "DEBUG", True),
                (admin_auth, "db", SimpleNamespace(users=self.collection)),
                (admin_auth, "verify_password", Mock(return_value=True))):
            patcher = patch.object(target, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.app = FastAPI()
        self.app.include_router(admin_auth.router, prefix="/api/admin/auth")
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app, client=(self._testMethodName, 1234)),
            base_url="http://synthetic.local")
        self.addAsyncCleanup(self.client.aclose)

    async def login(self, otp=None):
        return await self.client.post("/api/admin/auth/login", json={"email": self.user["email"], "password": "synthetic-password",
            **({"otp": otp} if otp is not None else {})})

    async def test_password_alone_does_not_create_session(self):
        response = await self.login()
        self.assertEqual(response.json(), {"ok": False, "mfa_required": True})
        self.assertNotIn("set-cookie", response.headers)
        self.collection.update_one.assert_not_awaited()

    async def test_valid_code_creates_mfa_session(self):
        response = await self.login(pyotp.TOTP(self.secret).now())
        self.assertEqual(response.status_code, 200, response.text)
        token = self.client.cookies.get(dependencies.ADMIN_COOKIE_NAME)
        payload = dependencies.verify_access_token(token)
        self.assertTrue(payload["admin_mfa"])
        self.assertEqual(payload["admin_mfa_key_id"], admin_mfa_key_id(self.user["email"]))
        self.assertTrue(valid_admin_mfa_session(self.user, payload))

    async def test_replayed_code_is_rejected(self):
        self.user["admin_mfa_key_id"] = admin_mfa_key_id(self.user["email"])
        self.user["admin_mfa_last_counter"] = pyotp.TOTP(self.secret).timecode(datetime.now(timezone.utc)) + 1
        response = await self.login(pyotp.TOTP(self.secret).now())
        self.assertEqual(response.status_code, 403)
        self.assertNotIn("set-cookie", response.headers)

    async def test_wrong_code_counts_toward_account_lock(self):
        self.collection.find_one_and_update.return_value = {"admin_mfa_failed_attempts": settings.ADMIN_MFA_MAX_ATTEMPTS}
        with patch.object(pyotp.utils, "strings_equal", return_value=False):
            response = await self.login("000000")
        self.assertEqual(response.status_code, 403)
        self.collection.find_one_and_update.assert_awaited_once()
        self.assertIn("admin_mfa_locked_until", self.collection.update_one.call_args.args[1]["$set"])

    async def test_account_lock_is_enforced(self):
        self.user["admin_mfa_locked_until"] = datetime.now(timezone.utc) + timedelta(minutes=2)
        response = await self.login(pyotp.TOTP(self.secret).now())
        self.assertEqual(response.status_code, 403)
        self.collection.update_one.assert_not_awaited()

    async def test_expired_lock_resets_failure_counter(self):
        self.user["admin_mfa_locked_until"] = datetime.now(timezone.utc) - timedelta(minutes=1)
        response = await self.login()
        self.assertTrue(response.json()["mfa_required"])
        self.assertEqual(self.collection.update_one.call_args.args[1]["$set"]["admin_mfa_failed_attempts"], 0)

    async def test_concurrent_use_of_code_does_not_create_session(self):
        self.collection.update_one.return_value = SimpleNamespace(modified_count=0)
        response = await self.login(pyotp.TOTP(self.secret).now())
        self.assertEqual(response.status_code, 403)
        self.assertNotIn("set-cookie", response.headers)

    async def test_global_requirement_rejects_unenrolled_account(self):
        with patch.object(settings, "ADMIN_MFA_TOTP_SECRETS", {}), patch.object(settings, "ADMIN_REQUIRE_MFA", True):
            response = await self.login()
        self.assertEqual(response.status_code, 403)

    async def test_accounts_without_mfa_configuration_keep_existing_login(self):
        with patch.object(settings, "ADMIN_MFA_TOTP_SECRETS", {}):
            response = await self.login()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["ok"])

    async def test_password_is_required_before_code_prompt(self):
        with patch.object(admin_auth, "verify_password", return_value=False):
            response = await self.login()
        self.assertEqual(response.status_code, 403)
        self.collection.update_one.assert_not_awaited()

    async def test_cookie_requires_current_mfa_key_for_required_and_optional_auth(self):
        request = Request({"type": "http", "headers": [(b"cookie", b"denkma_admin_session=synthetic-token")]})
        payload = {"sub": self.user["user_id"], "admin_mfa": False}
        with patch.object(dependencies, "db", SimpleNamespace(users=self.collection)), patch.object(dependencies, "verify_access_token", return_value=payload):
            with self.assertRaises(HTTPException):
                await dependencies.get_current_user(request, None)
            self.assertIsNone(await dependencies.get_current_user_optional(request, None))
            payload.update(admin_mfa=True, admin_mfa_key_id=admin_mfa_key_id(self.user["email"]))
            self.assertEqual((await dependencies.get_current_user(request, None))["user_id"], self.user["user_id"])
            with patch.object(settings, "ADMIN_MFA_TOTP_SECRETS", {self.user["email"]: pyotp.random_base32()}):
                self.assertIsNone(await dependencies.get_current_user_optional(request, None))

    async def test_mobile_bearer_auth_remains_separate(self):
        request = Request({"type": "http", "headers": []})
        with patch.object(dependencies, "db", SimpleNamespace(users=self.collection)), patch.object(dependencies, "verify_access_token", return_value={"sub": self.user["user_id"]}):
            result = await dependencies.get_current_user(request, HTTPAuthorizationCredentials(scheme="Bearer", credentials="synthetic-token"))
        self.assertEqual(result["user_id"], self.user["user_id"])

    def test_cookie_is_secure_in_production_even_if_debug_enabled(self):
        with patch.object(settings, "APP_ENV", "production"), patch.object(settings, "DEBUG", True):
            self.assertTrue(admin_auth._cookie_settings()["secure"])

    def test_key_material_is_not_exposed_in_settings_repr(self):
        representation = repr(settings)
        self.assertNotIn(self.secret, representation)
        self.assertNotIn("ADMIN_MFA_TOTP_SECRETS=", representation)
        self.assertNotIn("KYC_ENCRYPTION_KEYS=", representation)


class ManagementTests(unittest.IsolatedAsyncioTestCase):
    async def test_ordinary_admin_cannot_escalate_or_modify_admin_roles(self):
        collection = SimpleNamespace(find_one=AsyncMock(return_value={"role": "client"}), update_one=AsyncMock())
        with patch.object(users, "db", SimpleNamespace(users=collection)):
            for role in (users.UserRole.ADMIN, users.UserRole.SUPERADMIN):
                with self.assertRaises(HTTPException) as error:
                    await users.change_role("synthetic", role, {"role": "admin"})
                self.assertEqual(error.exception.status_code, 403)
            collection.find_one.return_value = {"role": "superadmin"}
            with self.assertRaises(HTTPException):
                await users.change_role("synthetic", users.UserRole.CLIENT, {"role": "admin"})
        collection.update_one.assert_not_awaited()

    async def test_access_delegation_is_audited(self):
        collection = SimpleNamespace(find_one=AsyncMock(return_value={"user_id": "target", "role": "admin"}), update_one=AsyncMock())
        audit = AsyncMock()
        with patch.object(admin, "db", SimpleNamespace(users=collection)), patch.object(admin, "_record_event", audit):
            for enabled in (True, False):
                result = await admin.admin_set_kyc_access("target", admin.UserKycAccessRequest(enabled=enabled), {"user_id": "operator", "role": "superadmin"})
                self.assertEqual(result["enabled"], enabled)
                self.assertEqual(audit.call_args.kwargs["event_type"], "KYC_ACCESS_GRANTED" if enabled else "KYC_ACCESS_REVOKED")

    async def test_photo_moderation_does_not_disclose_kyc_or_passwords(self):
        user = {"user_id": "owner", "profile_picture_url": "synthetic-photo", "pin_hash": "private",
            "admin_password_hash": "private", "kyc_id_card_url": "https://outside.example/private"}
        collection = SimpleNamespace(find_one=AsyncMock(side_effect=lambda *a, **kw: deepcopy(user)), update_one=AsyncMock())
        with patch.object(admin, "db", SimpleNamespace(users=collection)), patch.object(admin, "_record_event", AsyncMock()):
            result = await admin.admin_moderate_profile_photo("owner", admin.ProfilePhotoModerationRequest(status="approved"), {"user_id": "operator", "role": "admin"})
        self.assertIsNone(result["user"]["kyc_id_card_url"])
        self.assertNotIn("pin_hash", result["user"])
        self.assertNotIn("admin_password_hash", result["user"])

    async def test_driver_application_cannot_import_external_document(self):
        body = applications.DriverApplicationCreate(full_name="Synthetic driver", id_card_number="synthetic", license_number="synthetic", id_card_url="https://outside.example/private")
        account = {"user_id": "owner", "phone": "+221700000000", "profile_picture_url": "synthetic-photo",
            "kyc_id_card_file_id": str(ObjectId()), "kyc_license_file_id": str(ObjectId())}
        collection = SimpleNamespace(find_one=AsyncMock(return_value=None), insert_one=AsyncMock())
        with patch.object(applications, "db", SimpleNamespace(applications=collection)):
            with self.assertRaises(HTTPException) as error:
                await applications.apply_driver(body, account)
        self.assertEqual(error.exception.status_code, 400)
        collection.insert_one.assert_not_awaited()

    async def test_approval_uses_current_uploaded_documents_not_application_urls(self):
        account = {"user_id": "owner", "profile_picture_url": "synthetic-photo", "profile_picture_status": "approved",
            "kyc_id_card_file_id": str(ObjectId()), "kyc_license_file_id": str(ObjectId())}
        app = {"application_id": "synthetic", "user_id": "owner", "status": "pending", "type": "driver",
            "data": {"id_card_url": "https://outside.example/private", "license_url": "https://outside.example/private"}}
        collection = SimpleNamespace(find_one=AsyncMock(return_value=app), update_one=AsyncMock())
        accounts = SimpleNamespace(find_one=AsyncMock(return_value=account), update_one=AsyncMock())
        with patch.object(applications, "db", SimpleNamespace(applications=collection, users=accounts)), patch.object(applications, "notify_application_result", AsyncMock()):
            await applications.approve_application("synthetic", None, {"role": "superadmin"})
        updates = accounts.update_one.call_args.args[1]["$set"]
        self.assertEqual(updates["kyc_id_card_url"], f"{settings.BASE_URL.rstrip('/')}/api/users/owner/kyc/id_card")
        self.assertEqual(updates["kyc_license_url"], f"{settings.BASE_URL.rstrip('/')}/api/users/owner/kyc/license")

    def test_invalid_urls_and_legacy_paths_fail_safely(self):
        with self.assertRaises(HTTPException):
            validate_kyc_reference("https://[broken/path", "owner", "id_card")
        self.assertIsNone(legacy_kyc_path({"kyc_id_card_path": {"invalid": "path"}}, "id_card"))


class MigrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.previous_id, self.next_id = ObjectId(), ObjectId()
        self.user = {"user_id": "owner", "kyc_id_card_file_id": str(self.previous_id)}
        self.stream = SimpleNamespace(metadata={"user_id": "owner", "doc_type": "id_card", "content_type": "image/jpeg"},
            filename="synthetic.jpg", read=AsyncMock(return_value=b"synthetic private bytes"))
        self.bucket = SimpleNamespace(open_download_stream=AsyncMock(return_value=self.stream),
            upload_from_stream=AsyncMock(return_value=self.next_id), delete=AsyncMock())
        self.database = SimpleNamespace(users=SimpleNamespace(update_one=AsyncMock(return_value=SimpleNamespace(modified_count=1))))
        patcher = patch.object(settings, "KYC_ENCRYPTION_KEYS", Fernet.generate_key().decode())
        patcher.start()
        self.addCleanup(patcher.stop)

    async def test_dry_run_does_not_read_content_write_or_delete(self):
        result = await secure_kyc_documents.secure_document(self.database, self.bucket, self.user, "id_card", apply=False, rotate=False)
        self.assertEqual(result, "to_secure")
        self.stream.read.assert_not_awaited()
        self.bucket.upload_from_stream.assert_not_awaited()
        self.bucket.delete.assert_not_awaited()
        self.database.users.update_one.assert_not_awaited()

    async def test_apply_encrypts_and_swaps_before_old_file_cleanup(self):
        result = await secure_kyc_documents.secure_document(self.database, self.bucket, self.user, "id_card", apply=True, rotate=False)
        self.assertEqual(result, "secured")
        encrypted = self.bucket.upload_from_stream.call_args.args[1]
        self.assertEqual(Fernet(settings.KYC_ENCRYPTION_KEYS.encode()).decrypt(encrypted), b"synthetic private bytes")
        self.bucket.delete.assert_awaited_once_with(self.previous_id)
        query = self.database.users.update_one.call_args.args[0]
        self.assertEqual(query["kyc_id_card_file_id"], str(self.previous_id))
        self.assertEqual(query["deleted_account"], {"$ne": True})

    async def test_concurrent_change_keeps_old_file(self):
        self.database.users.update_one.return_value = SimpleNamespace(modified_count=0)
        result = await secure_kyc_documents.secure_document(self.database, self.bucket, self.user, "id_card", apply=True, rotate=False)
        self.assertEqual(result, "concurrent_change")
        self.bucket.delete.assert_awaited_once_with(self.next_id)

    async def test_other_owner_reference_is_not_migrated(self):
        self.stream.metadata["user_id"] = "other"
        result = await secure_kyc_documents.secure_document(self.database, self.bucket, self.user, "id_card", apply=True, rotate=False)
        self.assertEqual(result, "invalid_owner")
        self.stream.read.assert_not_awaited()
        self.bucket.delete.assert_not_awaited()

    async def test_already_encrypted_file_is_not_replaced_without_rotation(self):
        self.stream.metadata["encryption"] = "fernet"
        result = await secure_kyc_documents.secure_document(self.database, self.bucket, self.user, "id_card", apply=True, rotate=False)
        self.assertEqual(result, "already_encrypted")
        self.stream.read.assert_not_awaited()

    async def test_orphan_purge_keeps_every_referenced_document(self):
        retained, orphan = ObjectId(), ObjectId()
        async def documents():
            for value in (retained, orphan):
                yield {"_id": value}
        files = SimpleNamespace(find=Mock(return_value=documents()))
        accounts = SimpleNamespace(find_one=AsyncMock(side_effect=[{"_id": "synthetic"}, None]))
        database = Mock()
        database.__getitem__ = Mock(return_value=files)
        database.users = accounts
        bucket = SimpleNamespace(delete=AsyncMock())
        cutoff = datetime.now(timezone.utc) - timedelta(hours=settings.KYC_ORPHAN_GRACE_HOURS)
        with patch.object(data_retention_service, "db", database), patch.object(data_retention_service, "get_db", return_value=database), patch.object(data_retention_service, "AsyncIOMotorGridFSBucket", return_value=bucket):
            count = await data_retention_service._purge_orphaned_kyc(cutoff)
        self.assertEqual(count, 1)
        bucket.delete.assert_awaited_once_with(orphan)
        self.assertEqual(files.find.call_args.args[0], {"uploadDate": {"$lt": cutoff}})


if __name__ == "__main__":
    unittest.main()
