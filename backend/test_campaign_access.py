import unittest

from routers.in_app_campaigns import _campaign_targets_user


class CampaignAccessTests(unittest.TestCase):
    def test_all_campaign_targets_every_authenticated_role(self):
        self.assertTrue(
            _campaign_targets_user(
                {"target_roles": ["all"]},
                {"role": "driver"},
            )
        )

    def test_driver_can_view_client_campaign(self):
        self.assertTrue(
            _campaign_targets_user(
                {"target_roles": ["client"]},
                {"role": "driver"},
            )
        )

    def test_client_cannot_view_driver_campaign(self):
        self.assertFalse(
            _campaign_targets_user(
                {"target_roles": ["driver"]},
                {"role": "client"},
            )
        )


if __name__ == "__main__":
    unittest.main()
