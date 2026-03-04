import 'package:dio/dio.dart';
import 'api_endpoints.dart';

/// Client HTTP Dio avec intercepteur auth.
/// Instancié par le provider [apiClientProvider] — ne pas instancier directement.
class ApiClient {
  ApiClient({String? token}) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            // 401 géré par AuthNotifier (refresh token)
            // Pour l'instant on passe l'erreur
          }
          return handler.next(error);
        },
      ),
    );
  }

  late final Dio _dio;

  // ─── Auth ────────────────────────────────────────────────────────────────
  Future<Response> requestOtp(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.requestOtp, data: body);

  Future<Response> verifyOtp(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.verifyOtp, data: body);

  Future<Response> refreshToken(String refreshToken) =>
      _dio.post(ApiEndpoints.refresh, data: {'refresh_token': refreshToken});

  Future<Response> getMe() => _dio.get(ApiEndpoints.me);

  Future<Response> updateProfile(Map<String, dynamic> body) =>
      _dio.put(ApiEndpoints.profile, data: body);

  Future<Response> updateFcmToken(String token) =>
      _dio.put(ApiEndpoints.updateFcm, data: {'fcm_token': token});

  Future<Response> getLoyalty() => _dio.get(ApiEndpoints.loyaltyStats);

  // ─── Parcels ─────────────────────────────────────────────────────────────
  Future<Response> getParcels({Map<String, dynamic>? params}) =>
      _dio.get(ApiEndpoints.parcels, queryParameters: params);

  Future<Response> getParcel(String id) =>
      _dio.get(ApiEndpoints.parcel(id));

  Future<Response> getQuote(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.quote, data: body);

  Future<Response> createParcel(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.parcels, data: body);

  Future<Response> bulkRelayAction(List<String> codes) =>
      _dio.post(ApiEndpoints.bulkAction, data: codes);

  Future<Response> getDriverLocation(String id) =>
      _dio.get(ApiEndpoints.driverLocation(id));

  Future<Response> cancelParcel(String id) =>
      _dio.post(ApiEndpoints.parcelEvent(id, 'cancel'));

  Future<Response> dropAtRelay(String id, Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.parcelEvent(id, 'drop-at-relay'), data: body);

  /// Réceptionner un colis au relais (transit normal OU redirigé après échec)
  Future<Response> arriveAtRelay(String id) =>
      _dio.post(ApiEndpoints.parcelEvent(id, 'arrive-relay'));

  Future<Response> handout(String id, Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.parcelEvent(id, 'handout'), data: body);

  Future<Response> deliverParcel(String id, Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.parcelEvent(id, 'deliver'), data: body);

  Future<Response> failDelivery(String id, Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.parcelEvent(id, 'fail-delivery'), data: body);

  Future<Response> redirectToRelay(String id, Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.parcelEvent(id, 'redirect-relay'), data: body);

  Future<Response> trackParcel(String code) =>
      _dio.get(ApiEndpoints.track(code));

  Future<Response> getParcelCodes(String id) =>
      _dio.get(ApiEndpoints.codes(id));

  Future<Response> confirmLocation(String id, Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.parcelEvent(id, 'confirm-location'), data: body);

  Future<Response> rateParcel(String id, int rating, {String? comment, double tip = 0}) =>
      _dio.post(ApiEndpoints.rateParcel(id), data: {
        'rating': rating,
        'comment': comment,
        'tip': tip,
      });

  // ─── Relay points ─────────────────────────────────────────────────────────
  Future<Response> getRelayPoints({Map<String, dynamic>? params}) =>
      _dio.get(ApiEndpoints.relayPoints, queryParameters: params);

  Future<Response> getNearbyRelays(double lat, double lng) =>
      _dio.get(ApiEndpoints.relayNearby, queryParameters: {'lat': lat, 'lng': lng});

  Future<Response> getRelayStock(String id) =>
      _dio.get(ApiEndpoints.relayStock(id));

  // ─── Deliveries ───────────────────────────────────────────────────────────
  Future<Response> getAvailableMissions({double? lat, double? lng, double radiusKm = 5.0}) {
    final params = <String, dynamic>{'radius_km': radiusKm};
    if (lat != null) params['lat'] = lat;
    if (lng != null) params['lng'] = lng;
    return _dio.get(ApiEndpoints.availableMissions, queryParameters: params);
  }

  Future<Response> getMyMissions() =>
      _dio.get(ApiEndpoints.myMissions);

  Future<Response> getMission(String id) =>
      _dio.get(ApiEndpoints.delivery(id));

  Future<Response> acceptMission(String id) =>
      _dio.post(ApiEndpoints.acceptMission(id));

  Future<Response> confirmPickup(String id, String code) =>
      _dio.post(ApiEndpoints.confirmPickup(id), data: {'code': code});

  Future<Response> releaseMission(String id) =>
      _dio.post(ApiEndpoints.releaseMission(id));

  Future<Response> toggleAvailability() =>
      _dio.put(ApiEndpoints.myAvailability);

  Future<Response> updateLocation(String id, Map<String, dynamic> body) =>
      _dio.put(ApiEndpoints.deliveryLocation(id), data: body);

  Future<Response> getRankings({String? period}) =>
      _dio.get(ApiEndpoints.rankings, queryParameters: {if (period != null) 'period': period});

  Future<Response> getMyRanking({String? period}) =>
      _dio.get(ApiEndpoints.myRanking, queryParameters: {if (period != null) 'period': period});

  // ─── Wallets ──────────────────────────────────────────────────────────────
  Future<Response> getWallet() => _dio.get(ApiEndpoints.myWallet);

  Future<Response> getTransactions() =>
      _dio.get(ApiEndpoints.transactions);

  Future<Response> requestPayout(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.payout, data: body);

  // ─── Admin ────────────────────────────────────────────────────────────────
  Future<Response> getDashboard() => _dio.get(ApiEndpoints.dashboard);

  Future<Response> getAdminParcels({Map<String, dynamic>? params}) =>
      _dio.get(ApiEndpoints.adminParcels, queryParameters: params);

  Future<Response> getLiveFleet() => _dio.get(ApiEndpoints.adminFleetLive);

  Future<Response> getStaleParcels() => _dio.get(ApiEndpoints.adminStaleParcels);

  Future<Response> getAnomalyAlerts() => _dio.get(ApiEndpoints.adminAnomalyAlerts);
  Future<Response> getHeatmapData() => _dio.get(ApiEndpoints.adminHeatmap);
  Future<Response> getCodMonitoring() => _dio.get(ApiEndpoints.adminCodMonitoring);

  Future<Response> getParcelAudit(String id) => _dio.get(ApiEndpoints.adminParcelAudit(id));

  Future<Response> getAdminAuditLog({int limit = 100}) => 
      _dio.get(ApiEndpoints.adminAuditLog, queryParameters: {'limit': limit});

  Future<Response> reassignMission(String id, String driverId) =>
      _dio.post(ApiEndpoints.adminReassignMission(id), data: {'new_driver_id': driverId});

  Future<Response> forceParcelStatus(String id, String status) =>
      _dio.put(ApiEndpoints.adminParcelStatus(id), data: {'status': status});

  Future<Response> getAdminRelays() => _dio.get(ApiEndpoints.adminRelays);

  Future<Response> verifyRelay(String id) =>
      _dio.put(ApiEndpoints.relayVerify(id));

  Future<Response> getPayouts() => _dio.get(ApiEndpoints.adminPayouts);

  Future<Response> approvePayout(String id) =>
      _dio.put(ApiEndpoints.adminApprove(id));

  Future<Response> settleCod(String driverId, {double? amount}) =>
      _dio.post(ApiEndpoints.adminSettleCod, queryParameters: {
        'driver_id': driverId,
        if (amount != null) 'amount': amount,
      });

  Future<Response> overrideParcelStatus(String parcelId, String status, String notes) =>
      _dio.post(ApiEndpoints.adminOverride(parcelId), queryParameters: {
        'new_status': status,
        'notes': notes,
      });

  // ─── Admin — Utilisateurs ─────────────────────────────────────────────────
  Future<Response> getAdminUsers({int skip = 0, int limit = 50}) =>
      _dio.get(ApiEndpoints.adminUsers, queryParameters: {'skip': skip, 'limit': limit});

  Future<Response> changeUserRole(String userId, String role) =>
      _dio.put(ApiEndpoints.adminUserRole(userId), queryParameters: {'role': role});

  Future<Response> assignRelayPoint(String userId, String relayId) =>
      _dio.put(ApiEndpoints.adminUserRelay(userId), queryParameters: {'relay_id': relayId});

  Future<Response> getUserHistory(String userId) =>
      _dio.get(ApiEndpoints.adminUserHistory(userId));

  Future<Response> banUser(String userId) =>
      _dio.post(ApiEndpoints.adminBanUser(userId));

  Future<Response> unbanUser(String userId) =>
      _dio.post(ApiEndpoints.adminUnbanUser(userId));

  Future<Response> getRelayPoint(String id) =>
      _dio.get(ApiEndpoints.relayPoint(id));

  Future<Response> updateRelayPoint(String id, Map<String, dynamic> data) =>
      _dio.put(ApiEndpoints.relayPoint(id), data: data);

  // ─── Candidatures ─────────────────────────────────────────────────────────
  Future<Response> applyDriver(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.applyDriver, data: body);

  Future<Response> applyRelay(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.applyRelay, data: body);

  Future<Response> getMyApplications() =>
      _dio.get(ApiEndpoints.myApplications);

  Future<Response> getAdminApplications({String status = 'pending', String? type}) =>
      _dio.get(ApiEndpoints.adminApplications,
          queryParameters: {'status': status, if (type != null) 'app_type': type});

  Future<Response> approveApplication(String id, {String? notes}) =>
      _dio.put(ApiEndpoints.approveApplication(id),
          queryParameters: {if (notes != null) 'admin_notes': notes});

  Future<Response> rejectApplication(String id, {String? notes}) =>
      _dio.put(ApiEndpoints.rejectApplication(id),
          queryParameters: {if (notes != null) 'admin_notes': notes});

  // ─── Promotions ──────────────────────────────────────────────────────────
  Future<Response> getAdminPromotions({bool activeOnly = false}) =>
      _dio.get(ApiEndpoints.adminPromotions, queryParameters: {'active_only': activeOnly});

  Future<Response> createPromotion(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.adminPromotions, data: body);

  Future<Response> updatePromotion(String id, Map<String, dynamic> body) =>
      _dio.put(ApiEndpoints.adminPromotion(id), data: body);

  Future<Response> deletePromotion(String id) =>
      _dio.delete(ApiEndpoints.adminPromotion(id));

  Future<Response> checkPromoCode(String code, double price, String mode) =>
      _dio.post(ApiEndpoints.checkPromo, data: {
        'promo_code': code,
        'price': price,
        'delivery_mode': mode,
      });

  // ─── Anomales ─────────────────────────────────────────────────────────────
  Future<Response> getAnomalies() => _dio.get('/admin/anomalies');
}
