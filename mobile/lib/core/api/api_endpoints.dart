/// Toutes les URLs de l'API PickuPoint.
/// Changer [_base] selon l'environnement.
class ApiEndpoints {
  ApiEndpoints._();

  // Surcharger avec --dart-define=API_BASE_URL=http://192.168.1.X:8001 pour le dev local.
  // Par défaut : URL Railway de production.
  static const String _base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://pickupoint-production.up.railway.app',
  );

  // ─── Auth ────────────────────────────────────────────────────────────────
  static const requestOtp = '$_base/api/auth/request-otp';
  static const checkPhone = '$_base/api/auth/check-phone';
  static const loginPin   = '$_base/api/auth/login-pin';
  static const completeReg= '$_base/api/auth/complete-registration';
  static const resetPin   = '$_base/api/auth/reset-pin';
  static const verifyOtp  = '$_base/api/auth/verify-otp';
  static const refresh    = '$_base/api/auth/refresh';
  static const me         = '$_base/api/auth/me';
  static const profile    = '$_base/api/auth/profile';
  static const updateFcm  = '$_base/api/users/me/fcm-token';
  static const loyaltyStats = '$_base/api/users/me/loyalty';
  static const userStats    = '$_base/api/users/me/stats';
  static const userAvatar   = '$_base/api/users/me/avatar';
  static const userKyc      = '$_base/api/users/me/kyc';
  static const favoriteAddresses = '$_base/api/users/me/favorite-addresses';

  // ─── Parcels ─────────────────────────────────────────────────────────────
  static const parcels    = '$_base/api/parcels';
  static const bulkAction = '$_base/api/parcels/bulk-action';
  static const quote      = '$_base/api/parcels/quote';
  static String parcel(String id)         => '$_base/api/parcels/$id';
  static String parcelEvent(String id, String event) => '$_base/api/parcels/$id/$event';
  static String track(String code)        => '$_base/api/tracking/$code';
  static String trackingView(String code) => '$_base/api/tracking/view/$code';
  static String codes(String id)          => '$_base/api/parcels/$id/codes';
  static String driverLocation(String id)       => '$_base/api/parcels/$id/driver-location';
  static String rateParcel(String id)           => '$_base/api/parcels/$id/rate';
  static String updateDeliveryAddress(String id) => '$_base/api/parcels/$id/delivery-address';

  // ─── Relay points ─────────────────────────────────────────────────────────
  static const relayPoints = '$_base/api/relay-points';
  static const relayNearby = '$_base/api/relay-points/nearby';
  static String relayPoint(String id)     => '$_base/api/relay-points/$id';
  static String relayStock(String id)     => '$_base/api/relay-points/$id/stock';
  static String relayVerify(String id)    => '$_base/api/relay-points/$id/verify';

  // ─── Deliveries ───────────────────────────────────────────────────────────
  static const availableMissions = '$_base/api/deliveries/available';
  static const myMissions        = '$_base/api/deliveries/my';
  static String delivery(String id)       => '$_base/api/deliveries/$id';
  static String deliveryLocation(String id) => '$_base/api/deliveries/$id/location';
  static String acceptMission(String id)  => '$_base/api/deliveries/$id/accept';
  static String confirmPickup(String id)  => '$_base/api/deliveries/$id/confirm-pickup';
  static String releaseMission(String id) => '$_base/api/deliveries/$id/release';
  static const rankings         = '$_base/api/deliveries/rankings';
  static const myRanking        = '$_base/api/deliveries/rankings/me';

  static const adminPromotions = '$_base/api/admin/promotions';
  static String adminPromotion(String id) => '$_base/api/admin/promotions/$id';
  static const checkPromo = '$_base/api/parcels/check-promo';

  // ─── Wallets ──────────────────────────────────────────────────────────────
  static const myWallet     = '$_base/api/wallets/me';
  static const transactions = '$_base/api/wallets/me/transactions';
  static const payout       = '$_base/api/wallets/me/payout';

  // ─── Admin ────────────────────────────────────────────────────────────────
  static const dashboard    = '$_base/api/admin/dashboard';
  static const adminParcels = '$_base/api/admin/parcels';
  static String adminParcelStatus(String id) => '$_base/api/admin/parcels/$id/status';
  static const adminRelays  = '$_base/api/admin/relay-points';
  static const adminPayouts = '$_base/api/admin/wallets/payouts';
  static String adminApprove(String id)   => '$_base/api/admin/wallets/payouts/$id/approve';
  static const adminSettleCod     = '$_base/api/admin/finance/settle';
  static String adminOverride(String id)  => '$_base/api/admin/parcels/$id/override';
  
  // Control Max (Phase 9)
  static const adminFleetLive      = '$_base/api/admin/fleet/live';
  static const adminStaleParcels   = '$_base/api/admin/analytics/stale-parcels';
  static const adminAnomalyAlerts  = '$_base/api/admin/analytics/anomaly-alerts';
  static const adminHeatmap        = '$_base/api/admin/analytics/heatmap';
  static const adminCodMonitoring  = '$_base/api/admin/finance/cod-monitoring';
  static String adminParcelAudit(String id)      => '$_base/api/admin/parcels/$id/audit';
  static String adminReassignMission(String id)  => '$_base/api/admin/missions/$id/reassign';
  static const adminAuditLog       = '$_base/api/admin/audit-log';

  // ─── Utilisateurs ─────────────────────────────────────────────────────────
  static const myAvailability = '$_base/api/users/me/availability';

  // ─── Admin — Utilisateurs ─────────────────────────────────────────────────
  static const adminUsers   = '$_base/api/users';
  static String adminUserRole(String id)  => '$_base/api/users/$id/role';
  static String adminUserRelay(String id) => '$_base/api/users/$id/relay-point';
  static String adminUserHistory(String id) => '$_base/api/admin/users/$id/history';
  static String adminBanUser(String id) => '$_base/api/admin/users/$id/ban';
  static String adminUnbanUser(String id) => '$_base/api/admin/users/$id/unban';

  // ─── Candidatures ─────────────────────────────────────────────────────────
  static const applyDriver      = '$_base/api/applications/driver';
  static const applyRelay       = '$_base/api/applications/relay';
  static const myApplications   = '$_base/api/applications/my';
  static const adminApplications = '$_base/api/applications';
  static String approveApplication(String id) => '$_base/api/applications/$id/approve';
  static String rejectApplication(String id)  => '$_base/api/applications/$id/reject';

  // ─── Legal ────────────────────────────────────────────────────────────────
  static String legal(String docType) => '$_base/api/legal/$docType';
}
