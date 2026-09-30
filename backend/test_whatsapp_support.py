import asyncio
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

import mongomock
from fastapi import HTTPException
from services import whatsapp_support_service as support
from services import data_retention_service as retention
from routers import admin
from routers import admin_action_center, webhooks
from starlette.requests import Request
import hashlib
import hmac
import json
import io
import wave
import shutil


class Cursor:
    def __init__(self, cursor): self.cursor = cursor
    def sort(self, *args): self.cursor = self.cursor.sort(*args); return self
    def skip(self, value): self.cursor = self.cursor.skip(value); return self
    def limit(self, value): self.cursor = self.cursor.limit(value); return self
    async def to_list(self, length=None): return list(self.cursor)[:length]
    def __aiter__(self):
        self.iterator = iter(self.cursor)
        return self
    async def __anext__(self):
        try: return next(self.iterator)
        except StopIteration: raise StopAsyncIteration


class Collection:
    def __init__(self, collection): self.collection = collection
    def find(self, *args, **kwargs):
        kwargs.pop('session', None)
        return Cursor(self.collection.find(*args, **kwargs))
    def __getattr__(self, name):
        async def operation(*args, **kwargs):
            kwargs.pop('session', None)
            await asyncio.sleep(0)
            return getattr(self.collection, name)(*args, **kwargs)
        return operation


class SupportTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.raw = mongomock.MongoClient(tz_aware=True).support_tests
        self.db = SimpleNamespace(**{name: Collection(self.raw[name]) for name in (
            'whatsapp_support_conversations', 'whatsapp_support_messages', 'whatsapp_support_delivery_statuses',
            'whatsapp_support_notes', 'users', 'parcels', 'app_settings')})
        self.raw.whatsapp_support_messages.create_index('message_id', unique=True)
        self.raw.whatsapp_support_messages.create_index('whatsapp_message_id', unique=True, sparse=True)
        self.raw.whatsapp_support_conversations.create_index('conversation_id', unique=True)
        self.now = datetime.now(timezone.utc).replace(microsecond=0)
        self.admin = {'user_id': 'admin1', 'name': 'Support'}
        self.lock = asyncio.Lock()
        owner = self
        class Session:
            async def __aenter__(self): return self
            async def __aexit__(self, *args): return False
            async def with_transaction(self, operation):
                async with owner.lock:
                    snapshot = {name: list(owner.raw[name].find()) for name in owner.raw.list_collection_names()}
                    try: return await operation(self)
                    except Exception:
                        for name in owner.raw.list_collection_names(): owner.raw[name].delete_many({})
                        for name, rows in snapshot.items():
                            if rows: owner.raw[name].insert_many(rows)
                        raise
        client = SimpleNamespace(start_session=AsyncMock(side_effect=Session))
        self.db.list_collection_names = AsyncMock(side_effect=self.raw.list_collection_names)
        for module in (support, retention, admin, admin_action_center):
            patcher = patch.object(module, 'db', self.db); patcher.start(); self.addCleanup(patcher.stop)
        patcher = patch.object(support, 'get_client', return_value=client); patcher.start(); self.addCleanup(patcher.stop)
        self.post = AsyncMock(return_value={'messages': [{'id': 'meta-out'}]})
        patcher = patch.object(support, '_post_whatsapp_message', self.post); patcher.start(); self.addCleanup(patcher.stop)
        patcher = patch.object(support, '_download_whatsapp_media', AsyncMock(return_value=None)); patcher.start(); self.addCleanup(patcher.stop)

    def inbound(self, id='meta-in', at=None, text='Bonjour'):
        return {'id': id, 'from': '221771234567', 'timestamp': str(int((at or self.now).timestamp())),
                'type': 'text', 'text': {'body': text}}

    async def receive(self, **kwargs):
        return await support.record_whatsapp_inbound_message({}, self.inbound(**kwargs))

    def conversation(self):
        return self.raw.whatsapp_support_conversations.find_one({}, {'_id': 0})

    async def reply(self, text='Bonjour aussi', key='request_12345678'):
        return await support.send_support_text_reply(self.conversation(), text, self.admin, key)

    async def test_normalized_id_and_legacy_alias(self):
        self.assertEqual(support._conversation_id('+221 77-1234567'), 'wa_221771234567')
        self.raw.whatsapp_support_conversations.insert_one({'conversation_id': 'wa_+221771234567', 'phone': '+221771234567'})
        await self.receive()
        self.assertEqual(self.conversation()['conversation_id'], 'wa_+221771234567')
        self.assertIsNotNone(await support.find_support_conversation('wa_ 221771234567'))
        self.assertIsNotNone(await support.find_support_conversation('wa_221771234567'))

    async def test_duplicate_never_reopens_resolved_or_extends_window(self):
        await self.receive(at=self.now - timedelta(hours=25))
        await admin.update_whatsapp_support_conversation_status(self.conversation()['conversation_id'],
            admin.SupportConversationStatusRequest(status='resolved'), self.admin)
        before = deepcopy(self.conversation())
        await self.receive(at=self.now - timedelta(hours=25))
        self.assertEqual(self.conversation(), before)
        self.assertFalse(admin._with_whatsapp_reply_window(before)['can_reply_freeform'])

    async def test_delayed_message_uses_provider_date(self):
        await self.receive(at=self.now - timedelta(hours=26))
        self.assertEqual(self.conversation()['last_inbound_at'], self.now - timedelta(hours=26))
        with self.assertRaises(HTTPException): admin._ensure_whatsapp_reply_window_open(self.conversation())

    async def test_new_message_reopens_resolved(self):
        await self.receive(at=self.now - timedelta(hours=1))
        self.raw.whatsapp_support_conversations.update_one({}, {'$set': {'status': 'resolved', 'resolved_at': self.now - timedelta(minutes=30)}})
        await self.receive(id='meta-new')
        self.assertEqual(self.conversation()['status'], 'open')

    async def test_old_message_does_not_replace_latest_or_reopen(self):
        await self.receive()
        self.raw.whatsapp_support_conversations.update_one({}, {'$set': {'status': 'resolved', 'resolved_at': self.now}})
        await self.receive(id='old', at=self.now - timedelta(hours=2), text='Ancien')
        self.assertEqual(self.conversation()['status'], 'resolved')
        self.assertEqual(self.conversation()['last_message_text'], 'Bonjour')

    async def test_delayed_unseen_message_before_reply_keeps_awaiting_client(self):
        await self.receive(at=self.now - timedelta(hours=1))
        await self.reply()
        await self.receive(id='late', at=self.now - timedelta(minutes=5))
        self.assertEqual(self.conversation()['status'], 'pending')

    async def test_incomplete_send_is_not_presented_as_success(self):
        for status in ('sending', 'uncertain'):
            with self.assertRaises(HTTPException): admin._support_send_result({'delivery_status': status})

    async def test_audio_retry_does_not_upload_or_convert_again(self):
        await self.receive()
        import hashlib
        self.raw.whatsapp_support_messages.insert_one({'message_id': 'wmsg_audio-request',
            'conversation_id': self.conversation()['conversation_id'], 'message_type': 'audio',
            'media': {'content_hash': hashlib.sha256(b'audio').hexdigest()}, 'delivery_status': 'accepted'})
        with patch.object(support, '_upload_whatsapp_media', AsyncMock()) as upload:
            result = await support.send_support_audio_reply(self.conversation(), content=b'audio', filename='vocal.ogg',
                mime_type='audio/ogg', admin_user=self.admin, request_id='audio-request')
            self.assertEqual(result['delivery_status'], 'accepted')
            upload.assert_not_awaited()

    async def test_concurrent_duplicates_stored_once(self):
        await asyncio.gather(self.receive(), self.receive())
        self.assertEqual(self.raw.whatsapp_support_messages.count_documents({}), 1)
        self.assertEqual(self.raw.whatsapp_support_conversations.count_documents({}), 1)

    async def test_transaction_failure_rolls_back_message(self):
        with patch.object(self.db.whatsapp_support_conversations, 'update_one', AsyncMock(side_effect=RuntimeError('db offline'))):
            with self.assertRaises(RuntimeError): await self.receive()
        self.assertEqual(self.raw.whatsapp_support_messages.count_documents({}), 0)
        await self.receive()
        self.assertEqual(self.raw.whatsapp_support_messages.count_documents({}), 1)

    async def test_reply_idempotency_and_pending_client(self):
        await self.receive()
        first = await self.reply()
        second = await self.reply()
        self.assertEqual(first['message_id'], second['message_id'])
        self.post.assert_awaited_once()
        self.assertEqual(self.conversation()['status'], 'pending')
        self.assertEqual(first['delivery_status'], 'accepted')

    async def test_concurrent_same_send_is_one_meta_call(self):
        await self.receive()
        await asyncio.gather(self.reply(), self.reply())
        self.post.assert_awaited_once()

    async def test_changed_payload_cannot_reuse_key(self):
        await self.receive(); await self.reply()
        with self.assertRaises(ValueError): await self.reply('Différent')
        self.post.assert_awaited_once()

    async def test_uncertain_send_is_not_automatically_resent(self):
        await self.receive()
        self.post.side_effect = support.WhatsAppSendUncertain('Timeout')
        with self.assertRaises(support.WhatsAppSendUncertain): await self.reply()
        result = await self.reply()
        self.assertEqual(result['delivery_status'], 'uncertain')
        self.assertEqual(self.conversation()['status'], 'open')
        self.post.assert_awaited_once()

    async def test_explicit_failed_send_can_retry(self):
        await self.receive()
        self.post.side_effect = RuntimeError('Refus explicite')
        with self.assertRaises(RuntimeError): await self.reply()
        self.post.side_effect = None
        self.assertEqual((await self.reply())['delivery_status'], 'accepted')
        self.assertEqual(self.post.await_count, 2)

    async def test_reply_does_not_hide_new_inbound_even_same_second(self):
        await self.receive()
        async def racing(*args, **kwargs):
            await self.receive(id='new-during-send')
            return {'messages': [{'id': 'meta-out'}]}
        self.post.side_effect = racing
        await self.reply()
        self.assertEqual(self.conversation()['status'], 'open')

    async def test_reply_does_not_override_manual_resolution(self):
        await self.receive()
        async def racing(*args, **kwargs):
            await admin.update_whatsapp_support_conversation_status(self.conversation()['conversation_id'],
                admin.SupportConversationStatusRequest(status='resolved'), self.admin)
            return {'messages': [{'id': 'meta-out'}]}
        self.post.side_effect = racing
        await self.reply()
        self.assertEqual(self.conversation()['status'], 'resolved')

    async def test_delivery_events_out_of_order_do_not_regress(self):
        await self.receive(); message = await self.reply()
        for state in ('read', 'sent', 'delivered', 'failed'):
            await support.record_whatsapp_delivery_status({'id': 'meta-out', 'status': state, 'timestamp': str(int(self.now.timestamp()))})
        self.assertEqual((await support.enrich_delivery_statuses([message]))[0]['delivery_status'], 'read')

    async def test_delivery_event_before_message_is_joined(self):
        await support.record_whatsapp_delivery_status({'id': 'meta-out', 'status': 'delivered'})
        await self.receive(); message = await self.reply()
        self.assertEqual((await support.enrich_delivery_statuses([message]))[0]['delivery_status'], 'delivered')

    async def test_latest_messages_and_keyset_pagination(self):
        await self.receive()
        id = self.conversation()['conversation_id']
        self.raw.whatsapp_support_messages.delete_many({})
        self.raw.whatsapp_support_messages.insert_many([{'message_id': f'm{i:03}', 'conversation_id': id,
            'created_at': self.now, 'text': str(i), 'raw_message': {'private': True}} for i in range(215)])
        newest = await admin.get_whatsapp_support_conversation(id, before=None, limit=50, _admin=self.admin)
        self.assertEqual(newest['messages'][-1]['message_id'], 'm214')
        self.assertEqual(newest['messages'][0]['message_id'], 'm165')
        self.assertNotIn('raw_message', newest['messages'][0])
        older = await admin.get_whatsapp_support_conversation(id, before=newest['next_before'], limit=50, _admin=self.admin)
        self.assertEqual(older['messages'][-1]['message_id'], 'm164')

    async def test_search_phone_plus_and_regex_characters_are_literal(self):
        await self.receive()
        result = await admin.list_whatsapp_support_conversations(status=None, q='+221', limit=50, skip=0, _admin=self.admin)
        self.assertEqual(result['total'], 1)
        result = await admin.list_whatsapp_support_conversations(status=None, q='[.*', limit=50, skip=0, _admin=self.admin)
        self.assertEqual(result['total'], 0)

    async def test_notes_are_internal_and_quick_replies_are_configured(self):
        await self.receive()
        await admin.add_whatsapp_support_note(self.conversation()['conversation_id'], admin.SupportNoteRequest(text=' Vérifier le colis '), self.admin)
        self.assertEqual(self.raw.whatsapp_support_notes.find_one()['text'], 'Vérifier le colis')
        self.post.assert_not_awaited()
        self.raw.app_settings.insert_one({'key': 'global', 'pricing': {'unchanged': True}})
        await admin.set_whatsapp_support_settings(admin.SupportSettingsRequest(quick_replies=[{'label': 'Suivi', 'text': 'Votre code de suivi ?'}]), self.admin)
        self.assertTrue(self.raw.app_settings.find_one()['pricing']['unchanged'])
        self.assertEqual((await admin.get_whatsapp_support_settings(self.admin))['quick_replies'][0]['label'], 'Suivi')

    async def test_action_center_excludes_awaiting_client_and_encodes_legacy_link(self):
        for id, status in [('wa_+221771111111', 'open'), ('wa_+221772222222', 'pending'), ('wa_+221773333333', 'pending_internal')]:
            self.raw.whatsapp_support_conversations.insert_one({'conversation_id': id, 'phone': '+221',
                'status': status, 'last_inbound_at': self.now - timedelta(days=10), 'last_message_at': self.now,
                'status_changed_at': self.now, 'matched_user': {'name': 'Awa'}, 'last_message_text': 'Le colis ?'})
        items = await admin_action_center._fetch_support(self.now)
        self.assertEqual(len(items), 2)
        self.assertTrue(all(item['full_name'] == 'Awa' for item in items))
        self.assertTrue(all('%2B' in item['href'] for item in items))
        internal = next(item for item in items if item['status'] == 'pending_internal')
        self.assertEqual(internal['age_hours'], 0)

    async def test_webhook_requests_retry_when_database_fails(self):
        body = json.dumps({'entry': [{'changes': [{'value': {'messages': [self.inbound()]}}]}]}).encode()
        secret = 'test-secret-only'
        signature = 'sha256=' + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        async def receive(): return {'type': 'http.request', 'body': body, 'more_body': False}
        request = Request({'type': 'http', 'method': 'POST', 'path': '/whatsapp', 'headers': []}, receive)
        with patch.object(webhooks.settings, 'WHATSAPP_APP_SECRET', secret), patch.object(webhooks, 'record_whatsapp_inbound_message', AsyncMock(side_effect=RuntimeError('offline'))):
            with self.assertRaises(HTTPException) as raised: await webhooks.whatsapp_webhook(request, signature)
        self.assertEqual(raised.exception.status_code, 503)

    async def test_webhook_refuses_unsigned_messages(self):
        with patch.object(webhooks.settings, 'WHATSAPP_APP_SECRET', 'test-secret-only'):
            with self.assertRaises(HTTPException) as raised: webhooks._verify_whatsapp_signature(b'{}', None)
        self.assertEqual(raised.exception.status_code, 401)

    async def test_media_is_durable_before_download_and_stable_url(self):
        message = self.inbound(); message.update(type='document', document={'id': 'media1', 'mime_type': 'application/pdf', 'filename': 'preuve.pdf'})
        saved = await support.record_whatsapp_inbound_message({}, message)
        support._download_whatsapp_media.assert_not_awaited()
        url = saved['media']['download_url']
        support._download_whatsapp_media.return_value = {'media_id': 'media1', 'storage_path': '/private/new.pdf', 'download_url': 'new-url', 'mime_type': 'application/pdf'}
        await support.hydrate_pending_support_media()
        hydrated = self.raw.whatsapp_support_messages.find_one()
        self.assertFalse(hydrated['media']['pending_download'])
        self.assertEqual(hydrated['media']['download_url'], url)
        self.assertEqual(hydrated['media']['filename'], 'preuve.pdf')

    async def test_media_failure_remains_queued_with_backoff(self):
        message = self.inbound(); message.update(type='audio', audio={'id': 'media1', 'mime_type': 'audio/ogg'})
        await support.record_whatsapp_inbound_message({}, message)
        await support.hydrate_pending_support_media()
        media = self.raw.whatsapp_support_messages.find_one()['media']
        self.assertTrue(media['pending_download'])
        self.assertEqual(media['attempts'], 1)
        self.assertGreater(media['retry_at'], self.now)

    async def test_anonymization_removes_embedded_personal_data_and_phone_id(self):
        self.raw.whatsapp_support_conversations.insert_one({'conversation_id': 'wa_+221771234567', 'phone': '+221771234567',
            'status': 'resolved', 'updated_at': self.now - timedelta(days=40), 'matched_user': {'name': 'Contact', 'phone': '+221'},
            'related_parcels': [{'recipient_phone': '+221'}], 'last_message_text': 'Adresse privée', 'last_media': {'file_id': 'x'}})
        self.assertEqual(await retention._anonymize_resolved_support(self.now - timedelta(days=30)), 1)
        result = self.conversation()
        self.assertTrue(result['conversation_id'].startswith('wa_archived_'))
        self.assertNotIn('matched_user', result)
        self.assertNotIn('last_message_text', result)
        self.assertNotIn('related_parcels', result)
        self.assertEqual(await retention._anonymize_resolved_support(self.now - timedelta(days=30)), 0)

    async def test_new_message_same_second_as_resolution_is_visible(self):
        await self.receive()
        self.raw.whatsapp_support_conversations.update_one({}, {'$set': {'status': 'resolved', 'resolved_at': self.now}})
        await self.receive(id='another-message')
        self.assertEqual(self.conversation()['status'], 'open')


class AudioConversionTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('ffmpeg'), 'FFmpeg non installé localement')
    def test_browser_audio_is_converted_to_whatsapp_ogg(self):
        stream = io.BytesIO()
        with wave.open(stream, 'wb') as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(16000)
            audio.writeframes(b'\x00\x00' * 1600)
        content, filename, mime = support._prepare_outbound_audio(stream.getvalue(), 'vocal.wav', 'audio/wav')
        self.assertTrue(content.startswith(b'OggS'))
        self.assertEqual(filename, 'note-vocale.ogg')
        self.assertEqual(mime, 'audio/ogg')


if __name__ == '__main__': unittest.main()
