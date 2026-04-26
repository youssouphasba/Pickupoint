/// Toutes les URLs de l'API Denkma.
/// Changer [_base] selon l'environnement.
class ApiEndpoints {
  ApiEndpoints._();

  // Surcharger avec --dart-define=API_BASE_URL=http://192.168.1.X:8001 pour le dev local.
  // Par défaut : URL Railway de production.
  static const String _base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.denkma.com',
  );

  static String resolve(String url) {
    final value = url.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) {
      return '$_base$value';
    }
    return '$_base/$value';
  }

  // ─── Auth ────────────────────────────────────────────────────────────────
  static const checkPhone = '$_base/api/auth/check-phone';
  static const loginPin = '$_base/api/auth/login-pin';
  static const completeReg = '$_base/api/auth/complete-registration';
  static const resetPinFirebase = '$_base/api/auth/reset-pin-firebase';
  static const firebaseAuth = '$_base/api/auth/firebase';
  static const refresh = '$_base/api/auth/refresh';
  static const me = '$_base/api/auth/me';
  static const profile = '$_base/api/auth/profile';
  static const updateFcm = '$_base/api/users/me/fcm-token';
  static const loyaltyStats = '$_base/api/users/me/loyalty';
  static const userStats = '$_base/api/users/me/stats';
  static const userAvatar = '$_base/api/users/me/avatar';
  static const userKyc = '$_base/api/users/me/kyc';
  static const favoriteAddresses = '$_base/api/users/me/favorite-addresses';
  static const referralInfo = '$_base/api/users/refer';
  static const applyReferral = '$_base/api/users/apply-referral';

  // ─── Parcels ─────────────────────────────────────────────────────────────
  static const parcels = '$_base/api/parcels';
  static const bulkAction = '$_base/api/parcels/bulk-action';
  static const quote = '$_base/api/parcels/quote';
  static String parcel(String id) => '$_base/api/parcels/$id';
  static String parcelLookupByTracking(String code) =>
      '$_base/api/parcels/lookup/tracking/$code';
  static String parcelEvent(String id, String event) =>
      '$_base/api/parcels/$id/$event';
  static String track(String code) => '$_base/api/tracking/$code';
  static String trackingView(String code) => '$_base/api/tracking/view/$code';
  static String codes(String id) => '$_base/api/parcels/$id/codes';
  static String driverLocation(String id) =>
      '$_base/api/parcels/$id/driver-location';
  static String rateParcel(String id) => '$_base/api/parcels/$id/rate';
  static String updateDeliveryAddress(String id) =>
      '$_base/api/parcels/$id/delivery-address';
  static String previewDeliveryAddress(String id) =>
      '$_base/api/parcels/$id/delivery-address/preview';
  static String applyDeliveryAddress(String id) =>
      '$_base/api/parcels/$id/delivery-address/apply';

  // ─── Relay points ─────────────────────────────────────────────────────────
  static const relayPoints = '$_base/api/relay-points';
  static const relayNearby = '$_base/api/relay-points/nearby';
  static String relayPoint(String id) => '$_base/api/relay-points/$id';
  static String relayStock(String id) => '$_base/api/relay-points/$id/stock';
  static String relayHistory(String id) =>
      '$_base/api/relay-points/$id/history';
  static String relayVerify(String id) => '$_base/api/relay-points/$id/verify';

  // ─── Deliveries ───────────────────────────────────────────────────────────
  static const availableMissions = '$_base/api/deliveries/available';
  static const myMissions = '$_base/api/deliveries/my';
  static String delivery(String id) => '$_base/api/deliveries/$id';
  static String deliveryLocation(String id) =>
      '$_base/api/deliveries/$id/location';
  static String acceptMission(String id) => '$_base/api/deliveries/$id/accept';
  static String confirmPickup(String id) =>
      '$_base/api/deliveries/$id/confirm-pickup';
  static String releaseMission(String id) =>
      '$_base/api/deliveries/$id/release';
  static String reportMissionIncident(String id) =>
      '$_base/api/deliveries/$id/report-incident';
  static String confirmMissionReturn(String id) =>
      '$_base/api/deliveries/$id/confirm-return';
  static String contactMissionRecipient(String id) =>
      '$_base/api/deliveries/$id/contact-recipient';
  static String callMissionRecipient(String id) =>
      '$_base/api/deliveries/$id/call-recipient';
  static String missionCallStatus(String missionId, String callId) =>
      '$_base/api/deliveries/$missionId/calls/$callId';
  static String arriveAtDestination(String parcelId) =>
      '$_base/api/parcels/$parcelId/arrive-at-destination';
  static const rankings = '$_base/api/deliveries/rankings';
  static const myRanking = '$_base/api/deliveries/rankings/me';

  static const adminPromotions = '$_base/api/admin/promotions';
  static String adminPromotion(String id) => '$_base/api/admin/promotions/$id';
  static const checkPromo = '$_base/api/parcels/check-promo';
  static const resolvePhones = '$_base/api/admin/resolve-phones';

  // ─── Wallets ──────────────────────────────────────────────────────────────
  static const myWallet = '$_base/api/wallets/me';
  static const transactions = '$_base/api/wallets/me/transactions';
  static const payout = '$_base/api/wallets/me/payout';

  // ─── Admin ────────────────────────────────────────────────────────────────
  static const dashboard = '$_base/api/admin/dashboard';
  static const adminParcels = '$_base/api/admin/parcels';
  static String adminParcelStatus(String id) =>
      '$_base/api/admin/parcels/$id/override';
  static const adminRelays = '$_base/api/admin/relay-points';
  static const adminPayouts = '$_base/api/admin/wallets/payouts';
  static String adminApprove(String id) =>
      '$_base/api/admin/wallets/payouts/$id/approve';
  static String adminReject(String id) =>
      '$_base/api/admin/wallets/payouts/$id/reject';
  static const adminSettleCod = '$_base/api/admin/finance/settle';
  static String adminOverride(String id) =>
      '$_base/api/admin/parcels/$id/override';
  static String adminPaymentOverride(String id) =>
      '$_base/api/admin/parcels/$id/payment-override';
  static const adminWhatsappSupportConversations =
      '$_base/api/admin/support/whatsapp/conversations';
  static String adminWhatsappSupportConversation(String id) =>
      '$_base/api/admin/support/whatsapp/conversations/$id';
  static String adminWhatsappSupportConversationStatus(String id) =>
      '$_base/api/admin/support/whatsapp/conversations/$id/status';
  static String adminWhatsappSupportReply(String id) =>
      '$_base/api/admin/support/whatsapp/conversations/$id/reply';
  static String adminWhatsappSupportVoice(String id) =>
      '$_base/api/admin/support/whatsapp/conversations/$id/voice';

  // Control Max (Phase 9)
  static const adminFleetLive = '$_base/api/admin/fleet/live-rich';
  static const adminFleetLiveLegacy = '$_base/api/admin/fleet/live';
  static const adminStaleParcels = '$_base/api/admin/analytics/stale-parcels';
  static const adminAnomalyAlerts = '$_base/api/admin/analytics/anomaly-alerts';
  static const adminHeatmap = '$_base/api/admin/analytics/heatmap-rich';
  static const adminHeatmapLegacy = '$_base/api/admin/analytics/heatmap';
  static const adminCodMonitoring = '$_base/api/admin/finance/cod-monitoring';
  static const adminFinanceReconciliation =
      '$_base/api/admin/finance/reconciliation';
  static String adminParcelAudit(String id) =>
      '$_base/api/admin/parcels/$id/audit-rich';
  static String adminParcelAuditLegacy(String id) =>
      '$_base/api/admin/parcels/$id/audit';
  static String adminReassignMission(String id) =>
      '$_base/api/admin/missions/$id/reassign';
  static const adminAuditLog = '$_base/api/admin/audit-log';

  // ─── Utilisateurs ─────────────────────────────────────────────────────────
  static const myAvailability = '$_base/api/users/me/availability';

  // ─── Admin — Utilisateurs ─────────────────────────────────────────────────
  static const adminUsers = '$_base/api/users';
  static String adminUserRole(String id) => '$_base/api/users/$id/role';
  static String adminUserRelay(String id) => '$_base/api/users/$id/relay-point';
  static String adminUserHistory(String id) =>
      '$_base/api/admin/users/$id/history';
  static String adminUserDetail(String id) =>
      '$_base/api/admin/users/$id/detail';
  static String adminBanUser(String id) => '$_base/api/admin/users/$id/ban';
  static String adminUnbanUser(String id) => '$_base/api/admin/users/$id/unban';
  static String adminUserKyc(String id, String docType) =>
      '$_base/api/users/$id/kyc/$docType';
  static String adminRelayDetail(String id) =>
      '$_base/api/admin/relay-points/$id/detail';

  // ─── Notifications in-app ────────────────────────────────────────────────
  static const notifications = '$_base/api/notifications';
  static const notificationsUnreadCount = '$_base/api/notifications/unread-count';
  static const notificationsReadAll = '$_base/api/notifications/read-all';
  static String notificationRead(String notifId) =>
      '$_base/api/notifications/$notifId/read';

  // ─── Candidatures ─────────────────────────────────────────────────────────
  static const applyDriver = '$_base/api/applications/driver';
  static const applyRelay = '$_base/api/applications/relay';
  static const myApplications = '$_base/api/applications/my';
  static const adminApplications = '$_base/api/applications';
  static String approveApplication(String id) =>
      '$_base/api/applications/$id/approve';
  static String rejectApplication(String id) =>
      '$_base/api/applications/$id/reject';

  // ─── Legal ────────────────────────────────────────────────────────────────
  static String legal(String docType) => '$_base/api/legal/$docType';

  // ─── Messagerie colis ─────────────────────────────────────────────────────
  static String parcelMessages(String id) => '$_base/api/parcels/$id/messages';
  static String parcelVoiceMessage(String id) =>
      '$_base/api/parcels/$id/messages/voice';
  static String parcelVoiceAsset(String parcelId, String messageId) =>
      '$_base/api/parcels/$parcelId/messages/$messageId/voice';

  // ─── App Settings (public/admin) ─────────────────────────────────────────
  static const publicSettings = '$_base/api/settings';

  // ─── App Settings (admin) ─────────────────────────────────────────────────
  static const adminSettings = '$_base/api/admin/settings';
  static const adminSettingsExpress = '$_base/api/admin/settings/express';
  static const adminSettingsReferral = '$_base/api/admin/settings/referral';
  static const adminSettingsReferralStats =
      '$_base/api/admin/settings/referral/stats';
  static String adminUserReferralAccess(String id) =>
      '$_base/api/admin/users/$id/referral-access';
}
