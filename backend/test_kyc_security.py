from copy import deepcopy
from datetime import datetime, timedelta, timezone
from io import BytesIO
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, Mock, patch

from bson import ObjectId
from cryptography.fernet import Fernet
from fastapi import FastAPI, HTTPException
from fastapi.responses import PlainTextResponse
import httpx
from PIL import Image

from config import settings
from core.private_documents import PublicUploadFiles, can_access_kyc_documents, serialize_private_user, validate_kyc_reference
from routers import users, applications, admin
from services import kyc_security, data_retention_service


def image_bytes():
    output = BytesIO()
    image = Image.new("RGB", (40, 30), "white")
    exif = Image.Exif()
    exif[270] = "synthetic private metadata"
    image.save(output, format="JPEG", exif=exif)
    return output.getvalue()


class SyntheticPublicFiles(PublicUploadFiles):
    def __init__(self):
        super().__init__(directory=None, check_dir=False)
        self.config_checked = True

    def lookup_path(self, path):
        return "/synthetic-no-file", SimpleNamespace(st_mode=stat.S_IFREG, st_size=1, st_mtime=1)

    def file_response(self, *args, **kwargs):
        return PlainTextResponse("synthetic public file")


class DocumentSecurityTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.identity = {"user_id": "owner", "role": "driver"}
        self.old_id = ObjectId()
        self.new_id = ObjectId()
        self.account = {
            **self.identity, "phone": "+221700000000", "name": "Synthetic user",
            "profile_picture_url": "https://synthetic.local/photo", "profile_picture_status": "approved",
            "kyc_id_card_file_id": str(self.old_id), "kyc_license_file_id": str(ObjectId()),
        }
        self.database = SimpleNamespace(users=SimpleNamespace(
            find_one=AsyncMock(side_effect=lambda *args, **kwargs: deepcopy(self.account)),
            update_one=AsyncMock(return_value=SimpleNamespace(modified_count=1)),
        ))
        self.stream = SimpleNamespace(read=AsyncMock(return_value=image_bytes()), filename="synthetic.jpg",
            metadata={"user_id": "owner", "doc_type": "id_card", "content_type": "image/jpeg"})
        self.bucket = SimpleNamespace(open_download_stream=AsyncMock(return_value=self.stream),
            upload_from_stream=AsyncMock(return_value=self.new_id), delete=AsyncMock())
        self.audit = AsyncMock()
        for target, value in (("db", self.database), ("_kyc_documents_bucket", lambda: self.bucket), ("_record_event", self.audit)):
            patcher = patch.object(users, target, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        for key, value in (("KYC_ENCRYPTION_KEYS", ""), ("KYC_REQUIRE_ENCRYPTION", False),
                           ("KYC_CLAMAV_HOST", None), ("KYC_REQUIRE_ANTIVIRUS", False)):
            patcher = patch.object(settings, key, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.app = FastAPI()
        self.app.include_router(users.router, prefix="/api/users")
        async def identity():
            return self.identity
        self.app.dependency_overrides[users.get_current_user] = identity
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app, client=(self._testMethodName, 1234)), base_url="http://synthetic.local")
        self.addAsyncCleanup(self.client.aclose)

    async def test_anonymous_denied(self):
        self.app.dependency_overrides.clear()
        response = await self.client.get("/api/users/owner/kyc/id_card")
        self.assertEqual(response.status_code, 401)
        self.bucket.open_download_stream.assert_not_awaited()

    async def test_other_roles_and_unprivileged_admin_denied_and_audited(self):
        for role in ("client", "driver", "relay_agent", "admin"):
            self.identity.update(user_id="other", role=role)
            response = await self.client.get("/api/users/owner/kyc/id_card")
            self.assertEqual(response.status_code, 403, role)
        self.bucket.open_download_stream.assert_not_awaited()
        self.assertEqual(self.audit.await_count, 4)
        self.assertEqual(self.audit.call_args.kwargs["event_type"], "KYC_DOCUMENT_ACCESS_DENIED")

    async def test_owner_habilitated_admin_and_superadmin_have_no_cache_and_audit(self):
        for identity in ({"user_id": "owner", "role": "driver"},
                         {"user_id": "admin", "role": "admin", "kyc_access_enabled": True},
                         {"user_id": "superadmin", "role": "superadmin"}):
            self.identity.clear()
            self.identity.update(identity)
            response = await self.client.get("/api/users/owner/kyc/id_card")
            self.assertEqual(response.status_code, 200)
            self.assertIn("no-store", response.headers["cache-control"])
            self.assertEqual(response.headers["x-content-type-options"], "nosniff")
        self.assertEqual(self.audit.await_count, 3)
        self.assertEqual(self.audit.call_args.kwargs["metadata"], {"target_user_id": "owner", "document_type": "id_card"})

    async def test_revoked_permission_denies_next_request(self):
        self.identity.update(user_id="admin", role="admin", kyc_access_enabled=True)
        self.assertEqual((await self.client.get("/api/users/owner/kyc/id_card")).status_code, 200)
        self.identity["kyc_access_enabled"] = False
        self.assertEqual((await self.client.get("/api/users/owner/kyc/id_card")).status_code, 403)

    async def test_cross_owner_storage_reference_rejected(self):
        self.stream.metadata["user_id"] = "other"
        self.assertEqual((await self.client.get("/api/users/owner/kyc/id_card")).status_code, 404)

    async def test_cross_document_storage_reference_rejected(self):
        self.stream.metadata["doc_type"] = "license"
        self.assertEqual((await self.client.get("/api/users/owner/kyc/id_card")).status_code, 404)

    async def test_replacement_sanitizes_content_then_deletes_previous_file(self):
        response = await self.client.post("/api/users/me/kyc?doc_type=id_card", files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")})
        self.assertEqual(response.status_code, 200, response.text)
        content = self.bucket.upload_from_stream.call_args.args[1]
        self.assertNotIn(b"synthetic private metadata", content)
        self.bucket.delete.assert_awaited_once_with(self.old_id)
        query = self.database.users.update_one.call_args.args[0]
        self.assertEqual(query["kyc_id_card_file_id"], str(self.old_id))
        self.assertEqual(query["deleted_account"], {"$ne": True})

    async def test_deleted_account_cannot_receive_a_new_document(self):
        self.account["deleted_account"] = True
        response = await self.client.post("/api/users/me/kyc", files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")})
        self.assertEqual(response.status_code, 403)
        self.bucket.upload_from_stream.assert_not_awaited()

    async def test_concurrent_replacement_keeps_old_file_and_removes_uncommitted_new_file(self):
        self.database.users.update_one.return_value = SimpleNamespace(modified_count=0)
        response = await self.client.post("/api/users/me/kyc?doc_type=id_card", files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")})
        self.assertEqual(response.status_code, 409)
        self.bucket.delete.assert_awaited_once_with(self.new_id)

    async def test_failed_profile_write_cleans_new_upload(self):
        self.database.users.update_one.side_effect = RuntimeError("synthetic failure")
        with self.assertRaises(RuntimeError):
            await self.client.post("/api/users/me/kyc?doc_type=id_card", files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")})
        self.bucket.delete.assert_awaited_once_with(self.new_id)

    async def test_corrupt_photo_is_rejected_before_storage(self):
        response = await self.client.post("/api/users/me/kyc", files={"file": ("synthetic.jpg", b"\xff\xd8\xffnot-an-image", "image/jpeg")})
        self.assertEqual(response.status_code, 400)
        self.bucket.upload_from_stream.assert_not_awaited()

    async def test_pdf_needs_real_antivirus(self):
        response = await self.client.post("/api/users/me/kyc", files={"file": ("synthetic.pdf", b"%PDF-1.4\nsynthetic", "application/pdf")})
        self.assertEqual(response.status_code, 503)
        self.bucket.upload_from_stream.assert_not_awaited()

    async def test_encryption_is_applied_before_storage(self):
        with patch.object(settings, "KYC_ENCRYPTION_KEYS", Fernet.generate_key().decode()):
            response = await self.client.post("/api/users/me/kyc", files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")})
            self.assertEqual(response.status_code, 200)
            args = self.bucket.upload_from_stream.call_args
            self.assertEqual(args.kwargs["metadata"]["encryption"], "fernet")
            self.assertFalse(args.args[1].startswith(b"\xff\xd8"))
            plaintext = kyc_security.decrypt_kyc_content(args.args[1], "fernet")
            self.assertTrue(plaintext.startswith(b"\xff\xd8"))

    async def test_encrypted_document_is_decrypted_only_for_authorized_download(self):
        key = Fernet.generate_key()
        content = image_bytes()
        self.stream.read.return_value = Fernet(key).encrypt(content)
        self.stream.metadata["encryption"] = "fernet"
        with patch.object(settings, "KYC_ENCRYPTION_KEYS", key.decode()):
            response = await self.client.get("/api/users/owner/kyc/id_card")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, content)

    async def test_missing_decryption_key_never_returns_ciphertext_or_plaintext_fallback(self):
        self.stream.metadata["encryption"] = "fernet"
        self.stream.read.return_value = Fernet(Fernet.generate_key()).encrypt(image_bytes())
        response = await self.client.get("/api/users/owner/kyc/id_card")
        self.assertEqual(response.status_code, 503)
        self.assertNotIn(self.stream.read.return_value, response.content)

    async def test_required_encryption_fails_closed_without_key(self):
        with patch.object(settings, "KYC_REQUIRE_ENCRYPTION", True):
            response = await self.client.post("/api/users/me/kyc", files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")})
        self.assertEqual(response.status_code, 503)
        self.bucket.upload_from_stream.assert_not_awaited()

    async def test_public_private_paths_blocked_without_blocking_campaigns(self):
        app = FastAPI()
        app.mount("/uploads", SyntheticPublicFiles())
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://synthetic.local") as client:
            for directory in ("kyc", "profiles", "voice", "parcel_photos"):
                for variant in (directory, f"%2e/{directory}", f"public/%2e%2e/{directory}", directory.upper(), f"%2e%5c{directory}"):
                    response = await client.get(f"/uploads/{variant}/synthetic.jpg")
                    self.assertEqual(response.status_code, 404, variant)
            self.assertEqual((await client.get("/uploads/campaigns/synthetic.jpg")).status_code, 200)

    async def test_no_document_released_if_audit_fails(self):
        self.audit.side_effect = RuntimeError("synthetic audit failure")
        with self.assertRaises(RuntimeError):
            await self.client.get("/api/users/owner/kyc/id_card")


class SecurityHelpersTests(unittest.TestCase):
    def test_candidature_cannot_reference_external_or_other_user_documents(self):
        for url in ("https://outside.example/id.jpg", f"{settings.BASE_URL}/api/users/other/kyc/id_card",
                    f"{settings.BASE_URL}/api/users/me/kyc/id_card?token=secret", "/uploads/kyc/synthetic.jpg"):
            with self.assertRaises(HTTPException):
                validate_kyc_reference(url, "owner", "id_card")
        validate_kyc_reference(f"{settings.BASE_URL}/api/users/me/kyc/id_card", "owner", "id_card")
        validate_kyc_reference("/api/users/owner/kyc/id_card", "owner", "id_card")

    def test_permissions_are_dedicated_and_boolean(self):
        self.assertFalse(can_access_kyc_documents({"role": "admin"}))
        self.assertFalse(can_access_kyc_documents({"role": "admin", "kyc_access_enabled": "true"}))
        self.assertFalse(can_access_kyc_documents({"role": "client", "kyc_access_enabled": True}))
        self.assertTrue(can_access_kyc_documents({"role": "admin", "kyc_access_enabled": True}))
        self.assertTrue(can_access_kyc_documents({"role": "superadmin"}))

    def test_user_serialization_removes_secrets_and_external_links(self):
        account = {"user_id": "owner", "kyc_id_card_url": "https://outside.example/private.jpg",
                   "kyc_id_card_file_id": "private-id", "kyc_id_card_path": "/private/path",
                   "admin_password_hash": "private-hash", "pin_hash": "private-pin"}
        result = serialize_private_user(account, {"user_id": "admin", "role": "admin"})
        self.assertIsNone(result["kyc_id_card_url"])
        for key in ("admin_password_hash", "pin_hash", "kyc_id_card_file_id", "kyc_id_card_path"):
            self.assertNotIn(key, result)
        result = serialize_private_user(account, {"user_id": "superadmin", "role": "superadmin"})
        self.assertEqual(result["kyc_id_card_url"], f"{settings.BASE_URL}/api/users/owner/kyc/id_card")

    def test_application_snapshot_does_not_restore_redacted_legacy_link(self):
        result = admin._application_snapshot({"user_id": "owner", "type": "driver", "data": {"id_card_number": "private"}},
            {"user_id": "owner", "kyc_id_card_path": "/legacy/path"}, {"role": "admin"})
        self.assertNotIn("id_card_url", result["data"])
        self.assertNotIn("id_card_number", result["data"])

    def test_image_resolution_limit(self):
        with patch.object(settings, "KYC_MAX_IMAGE_PIXELS", 10):
            with self.assertRaises(HTTPException):
                kyc_security.sanitize_kyc_image(image_bytes())

    def test_key_rotation_reads_existing_document(self):
        old_key, new_key = Fernet.generate_key(), Fernet.generate_key()
        with patch.object(settings, "KYC_ENCRYPTION_KEYS", old_key.decode()):
            encrypted, mode = kyc_security.encrypt_kyc_content(b"synthetic content")
        with patch.object(settings, "KYC_ENCRYPTION_KEYS", f"{new_key.decode()},{old_key.decode()}"):
            self.assertEqual(kyc_security.decrypt_kyc_content(encrypted, mode), b"synthetic content")


class ManagementSecurityTests(unittest.IsolatedAsyncioTestCase):
    async def test_only_superadmin_can_delegate_access(self):
        with self.assertRaises(HTTPException) as error:
            await admin.admin_set_kyc_access("target", admin.UserKycAccessRequest(enabled=True), {"user_id": "admin", "role": "admin"})
        self.assertEqual(error.exception.status_code, 403)

    async def test_regular_admin_cannot_moderate_documents(self):
        with self.assertRaises(HTTPException) as error:
            await admin.admin_moderate_user_kyc("owner", admin.UserKycModerationRequest(status="verified"), {"user_id": "admin", "role": "admin"})
        self.assertEqual(error.exception.status_code, 403)

    async def test_clamav_clean_and_infected_responses(self):
        for verdict, refused in ((b"stream: OK\0", False), (b"stream: Synthetic FOUND\0", True)):
            reader = SimpleNamespace(readuntil=AsyncMock(return_value=verdict))
            writer = SimpleNamespace(write=Mock(), drain=AsyncMock(), close=Mock())
            with patch.object(settings, "KYC_CLAMAV_HOST", "synthetic.local"), patch.object(kyc_security.asyncio, "open_connection", AsyncMock(return_value=(reader, writer))):
                if refused:
                    with self.assertRaises(HTTPException) as error:
                        await kyc_security.scan_kyc_upload(b"synthetic")
                    self.assertEqual(error.exception.status_code, 400)
                else:
                    self.assertEqual(await kyc_security.scan_kyc_upload(b"synthetic"), "clamav_clean")
                writer.close.assert_called_once()

    async def test_antivirus_outage_fails_closed(self):
        with patch.object(settings, "KYC_CLAMAV_HOST", "synthetic.local"), patch.object(kyc_security.asyncio, "open_connection", AsyncMock(side_effect=OSError())):
            with self.assertRaises(HTTPException) as error:
                await kyc_security.scan_kyc_upload(b"synthetic")
            self.assertEqual(error.exception.status_code, 503)


if __name__ == "__main__":
    unittest.main()
