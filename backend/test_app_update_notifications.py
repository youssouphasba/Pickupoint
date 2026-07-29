import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

from routers.admin import AppUpdateNotificationRequest, notify_app_update
from services.notification_service import _push_tokens_from_user


class AppUpdateNotificationTests(unittest.TestCase):
    def test_filters_push_tokens_by_platform(self):
        user = {
            "fcm_token": "legacy-token",
            "fcm_tokens": [
                {
                    "token": "android-token",
                    "platform": "android",
                    "is_active": True,
                },
                {
                    "token": "ios-token",
                    "platform": "ios",
                    "is_active": True,
                },
                {
                    "token": "inactive-android-token",
                    "platform": "android",
                    "is_active": False,
                },
            ],
        }

        self.assertEqual(
            _push_tokens_from_user(user, "android"),
            ["android-token"],
        )
        self.assertEqual(
            _push_tokens_from_user(user, "ios"),
            ["ios-token"],
        )

    def test_keeps_legacy_token_for_non_platform_notifications(self):
        user = {
            "fcm_token": "legacy-token",
            "fcm_tokens": [],
        }

        self.assertEqual(
            _push_tokens_from_user(user),
            ["legacy-token"],
        )
        self.assertEqual(
            _push_tokens_from_user(user, "android"),
            [],
        )


class AppUpdateNotificationEndpointTests(unittest.IsolatedAsyncioTestCase):
    async def test_targets_only_the_selected_platform(self):
        fake_cursor = SimpleNamespace(
            to_list=AsyncMock(
                return_value=[
                    {"user_id": "user-1"},
                    {"user_id": "user-2"},
                ]
            )
        )
        users_find = Mock(return_value=fake_cursor)
        fake_db = SimpleNamespace(
            app_settings=SimpleNamespace(
                find_one=AsyncMock(
                    return_value={
                        "app_update": {
                            "message": "Une nouvelle version est disponible.",
                            "android_latest_version": "1.2.3",
                            "android_store_url": "https://play.google.com/store/apps/details?id=com.denkma.app",
                        }
                    }
                ),
                update_one=AsyncMock(),
            ),
            users=SimpleNamespace(find=users_find),
            notification_broadcasts=SimpleNamespace(insert_one=AsyncMock()),
        )
        send_notifications = AsyncMock(
            return_value={
                "push_sent": 2,
                "push_failed": 0,
                "push_skipped": 0,
                "push_reasons": {},
            }
        )

        with (
            patch("routers.admin.db", new=fake_db),
            patch(
                "routers.admin.send_targeted_notifications",
                new=send_notifications,
            ),
        ):
            result = await notify_app_update(
                AppUpdateNotificationRequest(platform="android"),
                admin_user={"user_id": "admin-1", "name": "Admin"},
            )

        self.assertEqual(result["push_sent"], 2)
        query = users_find.call_args.args[0]
        token_filter = query["fcm_tokens"]["$elemMatch"]
        self.assertEqual(token_filter["platform"], "android")
        self.assertEqual(token_filter["app_version"], {"$ne": "1.2.3"})
        send_notifications.assert_awaited_once()
        kwargs = send_notifications.await_args.kwargs
        self.assertEqual(kwargs["user_ids"], ["user-1", "user-2"])
        self.assertEqual(kwargs["push_platform"], "android")
        self.assertEqual(kwargs["event_type"], "app_update")
        self.assertEqual(
            kwargs["metadata"]["store_url"],
            "https://play.google.com/store/apps/details?id=com.denkma.app",
        )


if __name__ == "__main__":
    unittest.main()
