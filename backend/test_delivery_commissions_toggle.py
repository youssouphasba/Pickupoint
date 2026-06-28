import os
import sys
import unittest

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from services.wallet_service import compute_delivery_commission_breakdown


class DeliveryCommissionsToggleTests(unittest.TestCase):
    def test_commissions_enabled_keeps_platform_and_relay_shares(self):
        breakdown = compute_delivery_commission_breakdown(
            {
                "quoted_price": 2000,
                "delivery_mode": "relay_to_home",
                "delivery_commissions_enabled": True,
            }
        )

        self.assertGreater(breakdown["platform_commission_xof"], 0)
        self.assertGreater(breakdown["relay_commission_xof"], 0)
        self.assertLess(breakdown["driver_revenue_xof"], 2000)

    def test_commissions_disabled_gives_driver_full_amount(self):
        breakdown = compute_delivery_commission_breakdown(
            {
                "quoted_price": 2000,
                "delivery_mode": "relay_to_home",
                "delivery_commissions_enabled": False,
            }
        )

        self.assertEqual(breakdown["platform_commission_xof"], 0.0)
        self.assertEqual(breakdown["relay_commission_xof"], 0.0)
        self.assertEqual(breakdown["total_commission_xof"], 0.0)
        self.assertEqual(breakdown["wallet_balance_required_xof"], 0.0)
        self.assertEqual(breakdown["driver_revenue_xof"], 2000.0)


if __name__ == "__main__":
    unittest.main()
