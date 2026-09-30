from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

from services import performance_rewards_service as rewards


class PerformanceRewardsTests(unittest.TestCase):
    def test_no_bonus_by_default(self):
        for raw in (None, {}, {"driver": {}, "relay": {}}):
            with self.subTest(raw=raw):
                config = rewards.normalize_performance_rewards(raw)
                self.assertEqual(config["driver"]["volume_bonuses"], [])
                self.assertEqual(config["relay"]["volume_bonuses"], [])
                self.assertFalse(config["driver"]["success_bonus"]["enabled"])

    def test_empty_lists_are_preserved(self):
        config = rewards.normalize_performance_rewards({
            "driver": {"volume_bonuses": []},
            "relay": {"volume_bonuses": []},
        })
        self.assertEqual(config["driver"]["volume_bonuses"], [])
        self.assertEqual(config["relay"]["volume_bonuses"], [])

    def test_explicit_configured_bonuses_are_preserved(self):
        config = rewards.normalize_performance_rewards({
            "driver": {
                "success_bonus": {"enabled": True, "amount_xof": 800},
                "volume_bonuses": [{"min_deliveries": 12, "amount_xof": 350}],
            },
            "relay": {"volume_bonuses": [{"min_parcels": 7, "amount_xof": 125}]},
        })
        self.assertTrue(config["driver"]["success_bonus"]["enabled"])
        self.assertEqual(config["driver"]["success_bonus"]["amount_xof"], 800)
        self.assertEqual(config["driver"]["volume_bonuses"],
                         [{"min_deliveries": 12, "amount_xof": 350}])
        self.assertEqual(config["relay"]["volume_bonuses"],
                         [{"min_parcels": 7, "amount_xof": 125}])

    def test_removed_row_not_reintroduced(self):
        config = rewards.normalize_performance_rewards({
            "driver": {"volume_bonuses": [{"min_deliveries": 100, "amount_xof": 900}]},
        })
        self.assertEqual(len(config["driver"]["volume_bonuses"]), 1)
        self.assertEqual(config["relay"]["volume_bonuses"], [])


class PerformanceRewardsSaveTests(unittest.IsolatedAsyncioTestCase):
    async def test_save_and_reload_keep_all_bonuses_disabled(self):
        config = await rewards.set_performance_rewards_settings({
            "driver": {"success_bonus": {"enabled": False}, "volume_bonuses": []},
            "relay": {"volume_bonuses": []},
        })
        fake_db = SimpleNamespace(app_settings=SimpleNamespace(
            find_one=AsyncMock(return_value={"key": "global", "performance_rewards": config}),
        ))
        with patch.object(rewards, "db", fake_db):
            reloaded = await rewards.get_performance_rewards_settings()
        self.assertEqual(reloaded["driver"]["volume_bonuses"], [])
        self.assertEqual(reloaded["relay"]["volume_bonuses"], [])
        self.assertFalse(reloaded["driver"]["success_bonus"]["enabled"])


if __name__ == "__main__":
    unittest.main()
