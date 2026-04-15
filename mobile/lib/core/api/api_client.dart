import 'dart:io';
import 'dart:typed_data';
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

  Future<Response> getUserStats() async {
    return _dio.get(ApiEndpoints.userStats);
  }

  Future<Response> uploadAvatar(File file) async {
    final fileName = file.path.split('/').last;
    final formData = FormData.fromMap({
      "file": await MultipartFile.fromFile(file.path, filename: fileName),
    });
    return _dio.post(ApiEndpoints.userAvatar, data: formData);
  }

  Future<Response> uploadKyc(File file, String docType) async {
    final fileName = file.path.split('/').last;
    final formData = FormData.fromMap({
      "file": await MultipartFile.fromFile(file.path, filename: fileName),
    });
    // doc_type est passé en query param ou multipart ?
    // Mon backend le prend en query param par défaut si non spécifié comme Form (...)
    return _dio.post(ApiEndpoints.userKyc,
        queryParameters: {"doc_type": docType}, data: formData);
  }

  // --- Auth & Profile ---
  Future<Response> requestOtp(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.requestOtp, data: body);

  Future<Response> verifyOtp(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.verifyOtp, data: body);

  Future<Response> firebaseLogin(String idToken) =>
      _dio.post(ApiEndpoints.firebaseAuth, data: {'id_token': idToken});

  Future<Response> checkPhone(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.checkPhone, data: body);

  Future<Response> loginPin(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.loginPin, data: body);

  Future<Response> completeRegistration(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.completeReg, data: body);

  Future<Response> resetPin(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.resetPin, data: body);

  Future<Response> resetPinWithFirebase(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.resetPinFirebase, data: body);

  Future<Response> refreshToken(String refreshToken) =>
      _dio.post(ApiEndpoints.refresh, data: {'refresh_token': refreshToken});

  Future<Response> getMe() => _dio.get(ApiEndpoints.me);

  Future<Response> updateProfile(Map<String, dynamic> body) =>
      _dio.put(ApiEndpoints.profile, data: body);

  Future<Response> updateFcmToken(String token) =>
      _dio.put(ApiEndpoints.updateFcm, data: {'fcm_token': token});

  Future<Response> getLoyalty() => _dio.get(ApiEndpoints.loyaltyStats);

  Future<Response> getFavoriteAddresses() =>
      _dio.get(ApiEndpoints.favoriteAddresses);

  Future<Response> addFavoriteAddress(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.favoriteAddresses, data: body);

  Future<Response> updateFavoriteAddress(
          String name, Map<String, dynamic> body) =>
      _dio.put('${ApiEndpoints.favoriteAddresses}/$name', data: body);

  Future<Response> deleteFavoriteAddress(String name) =>
      _dio.delete('${ApiEndpoints.favoriteAddresses}/$name');

  Future<Response> getReferralInfo() => _dio.post(ApiEndpoints.referralInfo);

  Future<Response> applyReferralCode(String code) =>
      _dio.post(ApiEndpoints.applyReferral, data: {'referral_code': code});

  // ─── Parcels ─────────────────────────────────────────────────────────────
  Future<Response> getParcels({Map<String, dynamic>? params}) =>
      _dio.get(ApiEndpoints.parcels, queryParameters: params);

  Future<Response> getParcel(String id) => _dio.get(ApiEndpoints.parcel(id));

  Future<Response> lookupParcelByTracking(String code) =>
      _dio.get(ApiEndpoints.parcelLookupByTracking(code));

  Future<Response> getQuote(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.quote, data: body);

  Future<Response> createParcel(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.parcels, data: body);

  Future<Response> bulkRelayAction(List<String> codes) =>
      _dio.post(ApiEndpoints.bulkAction, data: codes);

  Future<Response> getDriverLocation(String id) =>
      _dio.get(ApiEndpoints.driverLocation(id));

  Future<Response> cancelParcel(String id) =>
      _dio.put(ApiEndpoints.parcelEvent(id, 'cancel'));

  Future<Response> changeDeliveryMode(String id, Map<String, dynamic> body) =>
      _dio.put('${ApiEndpoints.parcels}/$id/change-delivery-mode', data: body);

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

  Future<Response> updateDeliveryAddress(
          String id, Map<String, dynamic> body) =>
      _dio.put(ApiEndpoints.updateDeliveryAddress(id), data: body);

  Future<Response> previewDeliveryAddressChange(
          String id, Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.previewDeliveryAddress(id), data: body);

  Future<Response> applyDeliveryAddressChange(
          String id, Map<String, dynamic> body) =>
      _dio.put(ApiEndpoints.applyDeliveryAddress(id), data: body);

  Future<Response> rateParcel(String id, int rating,
          {String? comment, double tip = 0}) =>
      _dio.post(ApiEndpoints.rateParcel(id), data: {
        'rating': rating,
        'comment': comment,
        'tip': tip,
      });

  // ─── Relay points ─────────────────────────────────────────────────────────
  Future<Response> getRelayPoints({Map<String, dynamic>? params}) =>
      _dio.get(ApiEndpoints.relayPoints, queryParameters: params);

  Future<Response> getNearbyRelays(double lat, double lng) => _dio
      .get(ApiEndpoints.relayNearby, queryParameters: {'lat': lat, 'lng': lng});

  Future<Response> getRelayStock(String id) =>
      _dio.get(ApiEndpoints.relayStock(id));

  Future<Response> getRelayHistory(String id) =>
      _dio.get(ApiEndpoints.relayHistory(id));

  // ─── Deliveries ───────────────────────────────────────────────────────────
  Future<Response> getAvailableMissions(
      {double? lat, double? lng, double radiusKm = 5.0}) {
    final params = <String, dynamic>{'radius_km': radiusKm};
    if (lat != null) params['lat'] = lat;
    if (lng != null) params['lng'] = lng;
    return _dio.get(ApiEndpoints.availableMissions, queryParameters: params);
  }

  Future<Response> getMyMissions() => _dio.get(ApiEndpoints.myMissions);

  Future<Response> getMission(String id) => _dio.get(ApiEndpoints.delivery(id));

  Future<Response> acceptMission(String id) =>
      _dio.post(ApiEndpoints.acceptMission(id));

  Future<Response> confirmPickup(String id, String code,
          {double? lat, double? lng}) =>
      _dio.post(ApiEndpoints.confirmPickup(id), data: {
        'code': code,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });

  Future<Response> arriveAtDestination(String parcelId,
          {required double lat, required double lng}) =>
      _dio.post(ApiEndpoints.arriveAtDestination(parcelId),
          data: {'lat': lat, 'lng': lng});

  Future<Response> releaseMission(String id) =>
      _dio.post(ApiEndpoints.releaseMission(id));

  Future<Response> toggleAvailability() =>
      _dio.put(ApiEndpoints.myAvailability);

  Future<Response> updateLocation(String id, Map<String, dynamic> body) =>
      _dio.put(ApiEndpoints.deliveryLocation(id), data: body);

  Future<Response> getRankings({String? period}) =>
      _dio.get(ApiEndpoints.rankings,
          queryParameters: {if (period != null) 'period': period});

  Future<Response> getMyRanking({String? period}) =>
      _dio.get(ApiEndpoints.myRanking,
          queryParameters: {if (period != null) 'period': period});

  // ─── Wallets ──────────────────────────────────────────────────────────────
  Future<Response> getWallet() => _dio.get(ApiEndpoints.myWallet);

  Future<Response> getTransactions({String? period}) =>
      _dio.get(ApiEndpoints.transactions, queryParameters: {
        if (period != null) 'period': period,
      });

  Future<Response> requestPayout(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.payout, data: body);

  // ─── Admin ────────────────────────────────────────────────────────────────
  Future<Response> getDashboard() => _dio.get(ApiEndpoints.dashboard);

  Future<Response> getAdminParcels({Map<String, dynamic>? params}) =>
      _dio.get(ApiEndpoints.adminParcels, queryParameters: params);

  Future<Response> getLiveFleet() async {
    try {
      return await _dio.get(ApiEndpoints.adminFleetLive);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return _dio.get(ApiEndpoints.adminFleetLiveLegacy);
      }
      rethrow;
    }
  }

  Future<Response> getStaleParcels() =>
      _dio.get(ApiEndpoints.adminStaleParcels);

  Future<Response> getAnomalyAlerts() =>
      _dio.get(ApiEndpoints.adminAnomalyAlerts);
  Future<Response> getHeatmapData() async {
    try {
      return await _dio.get(ApiEndpoints.adminHeatmap);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return _dio.get(ApiEndpoints.adminHeatmapLegacy);
      }
      rethrow;
    }
  }

  Future<Response> getCodMonitoring() =>
      _dio.get(ApiEndpoints.adminCodMonitoring);
  Future<Response> getFinanceReconciliation() =>
      _dio.get(ApiEndpoints.adminFinanceReconciliation);

  Future<Response> getParcelAudit(String id) async {
    try {
      return await _dio.get(ApiEndpoints.adminParcelAudit(id));
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return _dio.get(ApiEndpoints.adminParcelAuditLegacy(id));
      }
      rethrow;
    }
  }

  Future<Response> getAdminAuditLog({int limit = 100}) =>
      _dio.get(ApiEndpoints.adminAuditLog, queryParameters: {'limit': limit});

  Future<Response> reassignMission(String id, String driverId,
          {String reason = 'Reassignation admin'}) =>
      _dio.post(ApiEndpoints.adminReassignMission(id),
          data: {'new_driver_id': driverId, 'reason': reason});

  Future<Response> forceParcelStatus(String id, String status,
          {required String notes}) =>
      _dio.post(ApiEndpoints.adminParcelStatus(id),
          queryParameters: {'new_status': status, 'notes': notes});

  Future<Response> getAdminRelays() => _dio.get(ApiEndpoints.adminRelays);

  Future<Response> verifyRelay(String id) =>
      _dio.put(ApiEndpoints.relayVerify(id));

  Future<Response> getPayouts() => _dio.get(ApiEndpoints.adminPayouts);

  Future<Response> approvePayout(String id) =>
      _dio.put(ApiEndpoints.adminApprove(id));

  Future<Response> rejectPayout(String id, {required String reason}) =>
      _dio.put(ApiEndpoints.adminReject(id), data: {'reason': reason});

  Future<Response> settleCod(String driverId, {double? amount}) =>
      _dio.post(ApiEndpoints.adminSettleCod, queryParameters: {
        'driver_id': driverId,
        if (amount != null) 'amount': amount,
      });

  Future<Response> overrideParcelStatus(
          String parcelId, String status, String notes) =>
      _dio.post(ApiEndpoints.adminOverride(parcelId), queryParameters: {
        'new_status': status,
        'notes': notes,
      });

  Future<Response> overrideParcelPayment(String parcelId, String reason) =>
      _dio.post(ApiEndpoints.adminPaymentOverride(parcelId),
          data: {'reason': reason});

  // ─── Admin — Utilisateurs ─────────────────────────────────────────────────
  Future<Response> getAdminUsers({int skip = 0, int limit = 50}) =>
      _dio.get(ApiEndpoints.adminUsers,
          queryParameters: {'skip': skip, 'limit': limit});

  Future<Response> changeUserRole(String userId, String role) => _dio
      .put(ApiEndpoints.adminUserRole(userId), queryParameters: {'role': role});

  Future<Response> assignRelayPoint(String userId, String relayId) =>
      _dio.put(ApiEndpoints.adminUserRelay(userId),
          queryParameters: {'relay_id': relayId});

  Future<Response> getUserHistory(String userId) =>
      _dio.get(ApiEndpoints.adminUserHistory(userId));

  Future<Response> getAdminUserDetail(String userId) =>
      _dio.get(ApiEndpoints.adminUserDetail(userId));

  Future<Response> getAdminRelayDetail(String relayId) =>
      _dio.get(ApiEndpoints.adminRelayDetail(relayId));

  Future<Response> banUser(String userId, {required String reason}) =>
      _dio.post(ApiEndpoints.adminBanUser(userId), data: {'reason': reason});

  Future<Response> unbanUser(String userId, {required String reason}) =>
      _dio.post(ApiEndpoints.adminUnbanUser(userId), data: {'reason': reason});

  Future<Response> getRelayPoint(String id) =>
      _dio.get(ApiEndpoints.relayPoint(id));

  Future<Response> updateRelayPoint(String id, Map<String, dynamic> data) =>
      _dio.put(ApiEndpoints.relayPoint(id), data: data);

  // ─── Candidatures ─────────────────────────────────────────────────────────
  Future<Response> applyDriver(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.applyDriver, data: body);

  Future<Response> applyRelay(Map<String, dynamic> body) =>
      _dio.post(ApiEndpoints.applyRelay, data: body);

  Future<Response> getMyApplications() => _dio.get(ApiEndpoints.myApplications);

  Future<Response> getAdminApplications(
          {String status = 'pending', String? type}) =>
      _dio.get(ApiEndpoints.adminApplications, queryParameters: {
        'status': status,
        if (type != null) 'app_type': type
      });

  Future<Response> approveApplication(String id, {String? notes}) =>
      _dio.put(ApiEndpoints.approveApplication(id),
          queryParameters: {if (notes != null) 'admin_notes': notes});

  Future<Response> rejectApplication(String id, {String? notes}) =>
      _dio.put(ApiEndpoints.rejectApplication(id),
          queryParameters: {if (notes != null) 'admin_notes': notes});

  // ─── Promotions ──────────────────────────────────────────────────────────
  Future<Response> getAdminPromotions({bool activeOnly = false}) =>
      _dio.get(ApiEndpoints.adminPromotions,
          queryParameters: {'active_only': activeOnly});

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

  Future<Response> resolvePhonesToIds(List<String> phones) =>
      _dio.post(ApiEndpoints.resolvePhones, data: {'phones': phones});

  // ─── Anomales ─────────────────────────────────────────────────────────────
  Future<Response> getAnomalies() => _dio.get(ApiEndpoints.adminAnomalyAlerts);

  // ─── Legal ────────────────────────────────────────────────────────────────
  Future<Response> getLegal(String docType) =>
      _dio.get(ApiEndpoints.legal(docType));

  Future<Response> updateLegal(String docType, Map<String, dynamic> body) =>
      _dio.put(ApiEndpoints.legal(docType), data: body);

  // ─── Messagerie colis ────────────────────────────────────────────────────
  Future<Response> getParcelMessages(String parcelId) =>
      _dio.get(ApiEndpoints.parcelMessages(parcelId));

  Future<Response> sendParcelMessage(String parcelId, String text) =>
      _dio.post(ApiEndpoints.parcelMessages(parcelId), data: {'text': text});

  Future<Response> sendParcelVoice(String parcelId, String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        contentType: DioMediaType('audio', 'm4a'),
      ),
    });
    return _dio.post(ApiEndpoints.parcelVoiceMessage(parcelId), data: formData);
  }

  Future<Uint8List> downloadParcelVoice(
      String parcelId, String messageId) async {
    final response = await _dio.get(
      ApiEndpoints.parcelVoiceAsset(parcelId, messageId),
      options: Options(responseType: ResponseType.bytes),
    );
    final raw = response.data;
    if (raw == null) {
      throw Exception('Audio introuvable');
    }
    if (raw is Uint8List) {
      if (raw.isEmpty) {
        throw Exception('Audio introuvable');
      }
      return raw;
    }
    if (raw is List<int>) {
      if (raw.isEmpty) {
        throw Exception('Audio introuvable');
      }
      return Uint8List.fromList(raw);
    }
    if (raw is List) {
      if (raw.isEmpty) {
        throw Exception('Audio introuvable');
      }
      return Uint8List.fromList(raw.cast<int>());
    }
    throw Exception('Format audio invalide');
  }

  // ─── App Settings (public/admin) ─────────────────────────────────────────
  Future<Response> getPublicAppSettings() =>
      _dio.get(ApiEndpoints.publicSettings);

  // ─── App Settings (admin) ────────────────────────────────────────────────
  Future<Response> getAppSettings() => _dio.get(ApiEndpoints.adminSettings);

  Future<Response> setExpressEnabled(bool enabled) =>
      _dio.put(ApiEndpoints.adminSettingsExpress, data: {'enabled': enabled});

  Future<Response> getReferralAdminStats() =>
      _dio.get(ApiEndpoints.adminSettingsReferralStats);

  Future<Response> setReferralSettings(Map<String, dynamic> body) =>
      _dio.put(ApiEndpoints.adminSettingsReferral, data: body);

  Future<Response> setUserReferralAccess(
          String userId, bool? enabledOverride) =>
      _dio.put(ApiEndpoints.adminUserReferralAccess(userId),
          data: {'enabled_override': enabledOverride});
}
