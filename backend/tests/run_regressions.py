"""Run the isolated suites; legacy scripts that contact live services are excluded."""

import unittest

MODULES = (
    "test_audit_regressions",
    "test_busy_driver_notifications",
    "test_delivery_commission_context",
    "test_delivery_commissions_toggle",
    "test_mission_notification_reminders",
    "test_notification_alert_profiles",
    "test_notification_copy",
    "test_delivery_mission_preview",
    "test_delivery_dispatch_visibility",
    "test_driver_presence_route",
    "test_mission_area_labels",
    "test_mission_trace",
    "test_mission_completion_summary",
    "test_gps_reliability",
    "test_security_regressions",
    "test_kyc_security",
    "test_private_documents_management",
    "test_stripe_wallet_flow",
    "test_profile_settings",
    "test_relay_settings_flow",
    "test_finance_reconciliation",
    "test_loyalty_rules",
    "test_referral_payments",
    "test_performance_rewards",
    "test_campaign_access",
    "test_campaign_targeting",
    "test_campaign_professional_audiences",
    "test_privacy_export",
    "test_app_update_notifications",
    "test_confirm_location_geocode",
    "test_whatsapp_support",
    "tests.test_sending_guide",
)

if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromNames(MODULES)
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    raise SystemExit(not result.wasSuccessful())
