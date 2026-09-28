import os
import sys
import unittest

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from routers.admin import _mission_reconciliation_detail


class FinanceReconciliationTests(unittest.TestCase):
    def test_pending_orphan_mission_can_be_cancelled_safely(self):
        detail = _mission_reconciliation_detail(
            {
                "mission_id": "msn_1",
                "parcel_id": "prc_1",
                "status": "pending",
                "driver_id": None,
            },
            None,
            None,
        )

        self.assertEqual(detail["reason_code"], "parcel_missing")
        self.assertTrue(detail["can_auto_resolve"])
        self.assertEqual(detail["resolution_type"], "cancel")

    def test_orphan_mission_with_driver_requires_manual_review(self):
        detail = _mission_reconciliation_detail(
            {
                "mission_id": "msn_2",
                "parcel_id": "prc_2",
                "status": "assigned",
                "driver_id": "usr_driver",
            },
            None,
            {"name": "Awa Ndiaye", "phone": "+221770000000"},
        )

        self.assertFalse(detail["can_auto_resolve"])
        self.assertIn("commission", detail["financial_impact"])
        self.assertEqual(detail["driver_name"], "Awa Ndiaye")

    def test_active_mission_for_delivered_parcel_can_be_completed(self):
        detail = _mission_reconciliation_detail(
            {
                "mission_id": "msn_3",
                "parcel_id": "prc_3",
                "status": "in_progress",
                "driver_id": "usr_driver",
            },
            {
                "parcel_id": "prc_3",
                "tracking_code": "PKP-123",
                "status": "delivered",
            },
            {"name": "Moussa Diop"},
        )

        self.assertTrue(detail["can_auto_resolve"])
        self.assertEqual(detail["resolution_type"], "complete")
        self.assertEqual(detail["tracking_code"], "PKP-123")


if __name__ == "__main__":
    unittest.main()
