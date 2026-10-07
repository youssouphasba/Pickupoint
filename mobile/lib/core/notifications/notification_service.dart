import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import '../../../core/auth/auth_provider.dart';
import '../../features/driver/providers/driver_provider.dart';
import '../router/app_router.dart';
import '../models/delivery_mission.dart';
import 'driver_mission_activity.dart';
import 'notification_alert_profile.dart';
import 'notification_navigation.dart';

final notificationServiceProvider = Provider((ref) {
  final service = NotificationService(ref);
  ref.onDispose(service.dispose);
  return service;
});
final foregroundNotificationRefreshProvider = StateProvider<int>((ref) => 0);

final notificationSettingsProvider =
    FutureProvider<NotificationSettings>((ref) async {
  return FirebaseMessaging.instance.getNotificationSettings();
});

const _driverMissionActivityChannel =
    MethodChannel('com.denkma.app/driver_mission_activity');

class NotificationService with WidgetsBindingObserver {
  NotificationService(
    this._ref, {
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    TargetPlatform? platform,
  })  : _fcm = messaging ?? FirebaseMessaging.instance,
        _localNotifs = localNotifications ?? FlutterLocalNotificationsPlugin(),
        _platform = platform ?? defaultTargetPlatform;

  final Ref _ref;
  final FirebaseMessaging _fcm;
  final FlutterLocalNotificationsPlugin _localNotifs;
  final TargetPlatform _platform;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  ProviderSubscription<AsyncValue<AuthState>>? _authSubscription;
  ProviderSubscription<AsyncValue<List<DeliveryMission>>>? _missionSubscription;
  Future<void> _missionSyncTail = Future.value();
  String? _missionOwner;
  DeliveryMission? _currentMission;
  String? _iosActivitySignature;
  String? _iosFallbackSignature;
  bool _missionMonitoringReady = false;
  bool _missionOwnerObserved = false;
  bool _missionStateKnown = false;
  Future<void>? _initialization;
  Timer? _tokenRetry;
  int _tokenRetryAttempts = 0;
  bool _disposed = false;
  bool _uploadingToken = false;

  bool _initialMessageHandled = false;
  bool _localNotificationsInitialized = false;
  String? _appVersion;
  String? _activeDriverMissionNotificationId;
  DateTime? _activeDriverMissionDeadline;

  bool get _hasAuthenticatedSession {
    final authState = _ref.read(authProvider).valueOrNull;
    return authState?.accessToken != null;
  }

  Future<void> init() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(FirebaseMessaging.onMessage.listen((message) {
      unawaited(_handleForegroundMessage(message));
    }));
    _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(_handleRemoteMessageNavigation(message));
    }));
    _subscriptions.add(_fcm.onTokenRefresh.listen((token) {
      unawaited(_uploadToken(token));
    }));
    _authSubscription = _ref.listen(authProvider, (_, next) {
      if (next.isLoading || next.hasError) return;
      if (next.valueOrNull?.accessToken != null) {
        _tokenRetryAttempts = 0;
        unawaited(_tryUploadCurrentToken());
      } else {
        _tokenRetry?.cancel();
      }
      if (_missionMonitoringReady) _watchDriverMissions();
    });
    try {
      await _initializeLocalNotifications();
    } catch (_) {}
    if (_disposed) return;
    if (_platform == TargetPlatform.iOS) {
      try {
        await _fcm.requestPermission(alert: true, badge: true, sound: true);
      } catch (_) {}
      if (_disposed) return;
      try {
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: !_localNotificationsInitialized,
          badge: !_localNotificationsInitialized,
          sound: !_localNotificationsInitialized,
        );
      } catch (_) {}
    }
    if (_disposed) return;
    _missionMonitoringReady = true;
    _watchDriverMissions();
    await _missionSyncTail;
    await _tryUploadCurrentToken();
    try {
      await _handleInitialMessage();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed) {
      _tokenRetryAttempts = 0;
      unawaited(_tryUploadCurrentToken());
      if (_missionMonitoringReady) {
        _iosActivitySignature = null;
        _watchDriverMissions();
        unawaited(_syncCurrentMission());
        if (_missionOwner != null) _ref.invalidate(myMissionsProvider);
      }
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _tokenRetry?.cancel();
    _authSubscription?.close();
    _missionSubscription?.close();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _watchDriverMissions() {
    if (_disposed) return;
    final auth = _ref.read(authProvider).valueOrNull;
    final user = auth?.user;
    final owner = auth?.isAuthenticated == true &&
            user?.role == 'driver' &&
            user?.isActive != false &&
            user?.isBanned != true
        ? user!.id
        : null;
    if (_missionOwnerObserved && _missionOwner == owner) return;
    final ownerWasObserved = _missionOwnerObserved;
    _missionOwnerObserved = true;
    _missionSubscription?.close();
    _missionSubscription = null;
    _currentMission = null;
    final hadOwner = _missionOwner != null;
    _missionOwner = owner;
    _missionStateKnown = owner == null;
    _iosActivitySignature = null;
    if (hadOwner || owner == null) {
      unawaited(_syncCurrentMission(clear: true));
    }
    if (owner == null) return;
    if (ownerWasObserved) _ref.invalidate(myMissionsProvider);
    _missionSubscription = _ref.listen(myMissionsProvider, (_, next) {
      if (_disposed || next.isLoading || next.hasError || !next.hasValue) {
        return;
      }
      _missionStateKnown = true;
      _currentMission = null;
      for (final mission in next.requireValue) {
        if (activeDriverMissionStatuses.contains(mission.status) &&
            (mission.driverId == null || mission.driverId == owner)) {
          _currentMission = mission;
          break;
        }
      }
      unawaited(_syncCurrentMission());
    }, fireImmediately: true);
  }

  Future<void> _syncCurrentMission({bool clear = false}) {
    if (!clear && _missionOwner != null && !_missionStateKnown) {
      return Future.value();
    }
    final mission = clear ? null : _currentMission;
    return syncDriverMissionNotification(
      missionId: mission?.id,
      trackingCode: mission?.trackingCode,
      assignedAt: mission?.assignedAt ?? mission?.createdAt,
      startedAt: mission?.startedAt ??
          (mission?.status == 'in_progress'
              ? mission?.assignedAt ?? mission?.createdAt
              : null),
      pickupConfirmationDeadline: mission?.pickupConfirmationDeadlineAt,
    );
  }

  Future<void> refreshDriverMissionNotification() {
    _iosActivitySignature = null;
    return _syncCurrentMission();
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;
    const androidInit =
        AndroidInitializationSettings('@drawable/ic_notification_logo');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _localNotifs.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _handleLocalNotificationResponse(response);
      },
    );
    if (_platform == TargetPlatform.android) {
      final androidPlugin = _localNotifs.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'denkma_driver_mission_v3',
          'Mission livreur',
          description: 'Compte à rebours et état de la mission active',
          importance: Importance.high,
          playSound: false,
          enableVibration: false,
          showBadge: true,
        ),
      );
      for (final profile in notificationAlertProfiles) {
        for (final vibrationEnabled in [true, false]) {
          await androidPlugin?.createNotificationChannel(
            profile.toAndroidChannel(vibrationEnabled: vibrationEnabled),
          );
        }
      }
    }
    _localNotificationsInitialized = true;
  }

  Future<void> _tryUploadCurrentToken() async {
    if (_disposed || !_hasAuthenticatedSession || _uploadingToken) return;
    _uploadingToken = true;
    var uploaded = false;
    try {
      final apnsReady =
          _platform != TargetPlatform.iOS || await _fcm.getAPNSToken() != null;
      if (_disposed) return;
      if (apnsReady) {
        final token = await _fcm.getToken();
        if (!_disposed && token != null) uploaded = await _uploadToken(token);
      }
    } catch (_) {
    } finally {
      _uploadingToken = false;
      if (!_disposed) {
        if (uploaded) {
          _tokenRetryAttempts = 0;
          _tokenRetry?.cancel();
        } else if (_hasAuthenticatedSession && _tokenRetryAttempts < 3) {
          _tokenRetry?.cancel();
          _tokenRetryAttempts++;
          _tokenRetry = Timer(const Duration(seconds: 5), () {
            unawaited(_tryUploadCurrentToken());
          });
        }
      }
    }
  }

  Future<bool> _uploadToken(String token) async {
    if (_disposed) return false;
    final authState = _ref.read(authProvider).valueOrNull;
    if (authState?.accessToken == null) {
      return false;
    }

    try {
      _appVersion ??= (await PackageInfo.fromPlatform()).version;
      if (_disposed || !_hasAuthenticatedSession) return false;
      await _ref.read(apiClientProvider).updateFcmToken(
            token,
            appVersion: _appVersion,
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final profile = notificationAlertProfileFor(
      eventType: message.data['event_type']?.toString(),
      refType: message.data['ref_type']?.toString(),
      category: message.data['category']?.toString(),
      targetView: message.data['target_view']?.toString(),
      parcelStatus: message.data['parcel_status']?.toString(),
      alertKind: message.data['alert_kind']?.toString(),
    );

    if (notification != null && _localNotificationsInitialized) {
      await _localNotifs.show(
        notificationPlatformId(message.data),
        notification.title,
        notification.body,
        NotificationDetails(
          android: profile.toAndroidDetails(
            vibrationEnabled: _ref
                    .read(authProvider)
                    .valueOrNull
                    ?.user
                    ?.notificationPrefs
                    .androidVibrationEnabled ??
                true,
          ),
          iOS: profile.toDarwinDetails(),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  Future<void> syncDriverMissionNotification({
    required String? missionId,
    required String? trackingCode,
    required DateTime? assignedAt,
    required DateTime? startedAt,
    required DateTime? pickupConfirmationDeadline,
  }) {
    final owner = _ref.read(authProvider).valueOrNull?.user?.id;
    final next = _missionSyncTail.then((_) async {
      if (_disposed ||
          (missionId != null &&
              owner != _ref.read(authProvider).valueOrNull?.user?.id)) {
        return;
      }
      await _syncDriverMissionNotification(
        missionId: missionId,
        trackingCode: trackingCode,
        assignedAt: assignedAt,
        startedAt: startedAt,
        pickupConfirmationDeadline: pickupConfirmationDeadline,
      );
    });
    _missionSyncTail = next.catchError((Object error) {
      if (!_disposed && _platform == TargetPlatform.iOS) {
        _ref.read(driverMissionActivityIssueProvider.notifier).state =
            const DriverMissionActivityIssue(
                'Le minuteur n’a pas pu s’afficher sur l’écran verrouillé. '
                'Réessayez depuis Denkma.');
      }
    });
    return _missionSyncTail;
  }

  Future<void> _syncDriverMissionNotification({
    required String? missionId,
    required String? trackingCode,
    required DateTime? assignedAt,
    required DateTime? startedAt,
    required DateTime? pickupConfirmationDeadline,
  }) async {
    final effectivePickupDeadline =
        startedAt == null ? pickupConfirmationDeadline : null;
    if (_platform == TargetPlatform.iOS) {
      await _syncIosMissionActivity(missionId == null || assignedAt == null
          ? null
          : DriverMissionActivity(
              missionId: missionId,
              trackingCode: trackingCode,
              assignedAt: assignedAt,
              startedAt: startedAt,
              pickupDeadline: pickupConfirmationDeadline,
            ));
      return;
    }
    if (_platform != TargetPlatform.android) return;
    await _initializeLocalNotifications();
    final notificationId = driverActiveMissionNotificationId;
    if (missionId == null || assignedAt == null) {
      await _localNotifs.cancel(notificationId);
      _activeDriverMissionNotificationId = null;
      _activeDriverMissionDeadline = null;
      return;
    }
    final now = DateTime.now();
    final isPickupCountdown =
        effectivePickupDeadline != null && effectivePickupDeadline.isAfter(now);
    final isPickupExpired = effectivePickupDeadline != null &&
        !effectivePickupDeadline.isAfter(now);
    if (_activeDriverMissionNotificationId == missionId &&
        _activeDriverMissionDeadline == effectivePickupDeadline &&
        !isPickupExpired) {
      return;
    }
    final referenceTime =
        (effectivePickupDeadline ?? assignedAt).millisecondsSinceEpoch;
    final timeoutAfter = isPickupCountdown
        ? effectivePickupDeadline.difference(now).inMilliseconds
        : null;
    final data = <String, dynamic>{
      'event_type': 'mission_detail',
      'ref_type': 'mission',
      'ref_id': missionId,
      'target_view': 'driver',
    };
    try {
      final notificationTitle = isPickupExpired
          ? '⚠️ Délai de récupération dépassé'
          : isPickupCountdown
              ? '⏳ Récupérez le colis avant la fin du délai'
              : '⏱️ Mission en cours${trackingCode == null ? '' : ' · $trackingCode'}';
      final notificationBody = isPickupExpired
          ? 'La mission doit être actualisée dans Denkma.'
          : isPickupCountdown
              ? 'Le compte à rebours est visible à droite. Confirmez la récupération avant son expiration.'
              : 'Le chronomètre est actif depuis l’acceptation de la mission.';
      await _localNotifs.show(
        notificationId,
        notificationTitle,
        notificationBody,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'denkma_driver_mission_v3',
            'Mission livreur',
            channelDescription: 'Compte à rebours et état de la mission active',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.service,
            icon: 'ic_notification_logo',
            ongoing: !isPickupExpired,
            autoCancel: isPickupExpired,
            onlyAlertOnce: true,
            playSound: false,
            enableVibration: false,
            showWhen: !isPickupExpired,
            when: isPickupExpired ? null : referenceTime,
            timeoutAfter: timeoutAfter,
            usesChronometer: !isPickupExpired,
            chronometerCountDown: isPickupCountdown,
            subText: isPickupExpired
                ? 'Mission à actualiser'
                : isPickupCountdown
                    ? 'Collecte à confirmer'
                    : 'Mission active',
            ticker: isPickupExpired
                ? 'Délai de récupération dépassé'
                : isPickupCountdown
                    ? 'Compte à rebours de récupération actif'
                    : 'Mission livreur active',
            styleInformation: BigTextStyleInformation(
              isPickupExpired
                  ? 'Le délai de récupération est dépassé. Ouvrez Denkma pour actualiser la mission.'
                  : isPickupCountdown
                      ? 'Le compte à rebours reste visible à droite pendant la navigation. Confirmez la récupération avant son expiration.'
                      : 'Le chronomètre suit le temps depuis l’acceptation de la mission.',
              contentTitle: isPickupExpired
                  ? '⚠️ Récupération à actualiser'
                  : isPickupCountdown
                      ? '⏳ Récupération à confirmer'
                      : '⏱️ Mission livreur en cours',
              summaryText: 'Denkma',
            ),
          ),
        ),
        payload: jsonEncode(data),
      );
      _activeDriverMissionNotificationId = missionId;
      _activeDriverMissionDeadline = effectivePickupDeadline;
    } catch (_) {
      _activeDriverMissionNotificationId = null;
      _activeDriverMissionDeadline = null;
    }
  }

  Future<void> _syncIosMissionActivity(DriverMissionActivity? mission) async {
    if (mission == null) {
      _iosActivitySignature = null;
      _iosFallbackSignature = null;
      _ref.read(driverMissionActivityIssueProvider.notifier).state = null;
      try {
        await _driverMissionActivityChannel.invokeMethod<Object?>('end');
      } catch (error) {
        debugPrint(
            'Denkma Live Activity: arrêt indisponible (${error.runtimeType})');
      }
      if (_disposed) return;
      if (_localNotificationsInitialized) {
        await _localNotifs.cancel(driverActiveMissionNotificationId);
      }
      return;
    }
    if (_iosActivitySignature == mission.signature) return;
    String status;
    try {
      final result =
          await _driverMissionActivityChannel.invokeMapMethod<String, dynamic>(
        'start',
        mission.arguments,
      );
      status = result?['status']?.toString() ?? 'update_required';
    } on MissingPluginException {
      status = 'update_required';
    } catch (error) {
      debugPrint(
          'Denkma Live Activity: démarrage indisponible (${error.runtimeType})');
      status = 'failed';
    }
    if (_disposed) return;
    if (status == 'active') {
      _iosActivitySignature = mission.signature;
      _iosFallbackSignature = null;
      _ref.read(driverMissionActivityIssueProvider.notifier).state = null;
      if (_localNotificationsInitialized) {
        await _localNotifs.cancel(driverActiveMissionNotificationId);
      }
      return;
    }
    if (status == 'deferred') {
      _ref.read(driverMissionActivityIssueProvider.notifier).state = null;
      return;
    }
    _ref.read(driverMissionActivityIssueProvider.notifier).state =
        switch (status) {
      'disabled' => const DriverMissionActivityIssue(
          'Activités en direct désactivées. Activez-les dans les réglages de Denkma.',
          openSettings: true),
      'unsupported' => const DriverMissionActivityIssue(
          'Le minuteur sur l’écran verrouillé nécessite iOS 16.1 ou ultérieur.',
          canRetry: false),
      'update_required' => const DriverMissionActivityIssue(
          'Mettez Denkma à jour pour afficher le minuteur sur l’écran verrouillé.',
          canRetry: false),
      _ => const DriverMissionActivityIssue(
          'Le minuteur n’a pas pu s’afficher sur l’écran verrouillé. Réessayez depuis Denkma.'),
    };
    if (!_localNotificationsInitialized ||
        _iosFallbackSignature == mission.signature) {
      return;
    }
    final deadline = mission.deadline;
    final body = mission.phase == 'delivery'
        ? 'Livraison en cours. Ouvrez Denkma pour retrouver votre mission.'
        : deadline == null
            ? 'Collecte à confirmer. Consultez votre mission dans Denkma.'
            : deadline.isAfter(DateTime.now())
                ? 'Collecte à confirmer avant ${_missionDeadlineLabel(deadline)}. Ouvrez Denkma pour voir le minuteur.'
                : 'Délai de collecte dépassé. Ouvrez Denkma pour actualiser la mission.';
    await _localNotifs.show(
      driverActiveMissionNotificationId,
      'Mission en cours${mission.trackingCode?.isNotEmpty == true ? ' · ${mission.trackingCode}' : ''}',
      body,
      const NotificationDetails(
          iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: false,
        presentBadge: false,
        threadIdentifier: 'denkma_driver_mission',
      )),
      payload: jsonEncode(mission.notificationData),
    );
    _iosFallbackSignature = mission.signature;
  }

  String _missionDeadlineLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> showClientTrackingNotification(
    Map<String, dynamic> data,
  ) async {
    if (_platform == TargetPlatform.android) {
      await showBackgroundClientTrackingNotification(_localNotifs, data);
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (_disposed) return;
    final eventType = message.data['event_type']?.toString();
    final refreshNotifier =
        _ref.read(foregroundNotificationRefreshProvider.notifier);
    refreshNotifier.state = refreshNotifier.state + 1;
    if (message.data['ref_type']?.toString() == 'mission') {
      final notifier =
          _ref.read(foregroundMissionNotificationProvider.notifier);
      notifier.state = notifier.state + 1;
      if (_missionOwner != null) _ref.invalidate(myMissionsProvider);
    }
    final user = _ref.read(authProvider).valueOrNull?.user;
    if (eventType == 'mission_available' &&
        (user?.role != 'driver' ||
            user?.isAvailable != true ||
            hasActiveDriverMission(
              _ref.read(myMissionsProvider).valueOrNull ?? const [],
            ))) {
      return;
    }
    if (eventType == 'tracking_progress') {
      await showClientTrackingNotification(message.data);
      return;
    }
    if (eventType == 'tracking_ended') {
      final parcelId = message.data['ref_id']?.toString() ?? '';
      if (parcelId.isNotEmpty) {
        await _localNotifs.cancel(trackingProgressNotificationId(parcelId));
      }
      return;
    }
    if (eventType == 'parcel_detail' &&
        const {
          'delivered',
          'delivery_failed',
          'cancelled',
          'expired',
          'returned',
          'suspended',
          'disputed',
        }.contains(message.data['parcel_status'])) {
      final parcelId = message.data['ref_id']?.toString() ?? '';
      if (parcelId.isNotEmpty) {
        await _localNotifs.cancel(trackingProgressNotificationId(parcelId));
      }
    }
    if (eventType == 'mission_unavailable') {
      await _localNotifs.cancel(notificationPlatformId(message.data));
      return;
    }
    await _showLocalNotification(message);
  }

  Future<void> _handleInitialMessage() async {
    if (_initialMessageHandled) {
      return;
    }
    final message = await _fcm.getInitialMessage();
    if (_disposed) return;
    _initialMessageHandled = true;
    if (message != null) {
      await _handleRemoteMessageNavigation(message);
    }
  }

  Future<void> _handleRemoteMessageNavigation(RemoteMessage message) async {
    await _navigateFromData(message.data);
  }

  Future<void> _handleLocalNotificationResponse(
    NotificationResponse response,
  ) async {
    final payload = response.payload;
    if (payload == null || payload.trim().isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        await _navigateFromData(
          decoded.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _navigateFromData(Map<String, dynamic> data) async {
    final eventType = data['event_type']?.toString();
    if (eventType == 'tracking_ended') {
      final parcelId = data['ref_id']?.toString() ?? '';
      if (parcelId.isNotEmpty) {
        await _localNotifs.cancel(trackingProgressNotificationId(parcelId));
      }
    }
    if (eventType == 'tracking_progress') {
      await showClientTrackingNotification(data);
    }
    if (eventType == 'mission_unavailable') {
      await _localNotifs.cancel(notificationPlatformId(data));
    }

    final externalUrl = notificationExternalUrl(
      eventType: eventType,
      storeUrl: data['store_url']?.toString(),
      currentPlatform: Platform.operatingSystem,
      targetPlatform: data['platform']?.toString(),
    );
    if (externalUrl != null) {
      await launchUrl(
        Uri.parse(externalUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    final authState = await _ref.read(authProvider.future);
    if (!authState.isAuthenticated) {
      return;
    }
    final targetView = data['target_view']?.toString().trim();
    if (targetView != null &&
        targetView.isNotEmpty &&
        targetView != authState.effectiveRole) {
      final realRole = authState.user?.role;
      final canOpenTarget = targetView == 'client' ||
          targetView == realRole ||
          (targetView == 'admin' && realRole == 'superadmin');
      if (canOpenTarget) {
        _ref.read(authProvider.notifier).switchView(targetView);
      }
    }

    final currentAuth = _ref.read(authProvider).valueOrNull ?? authState;
    var route = notificationRouteFor(
      refType: data['ref_type']?.toString(),
      refId: data['ref_id']?.toString(),
      role: currentAuth.effectiveRole,
      eventType: eventType,
      targetView: targetView,
      messageId: data['message_id']?.toString(),
    );
    route = await resolveLegacyDriverMissionRoute(route, (id) async {
      final response = await _ref.read(apiClientProvider).getMission(id);
      return Map<String, dynamic>.from(response.data as Map);
    });
    if (route == null || route.isEmpty) {
      return;
    }
    final routeParts = Uri.parse(route).pathSegments;
    if (routeParts.length == 3 &&
        routeParts[0] == 'driver' &&
        routeParts[1] == 'mission') {
      _ref.invalidate(missionProvider(routeParts[2]));
    }

    final notifId = data['notif_id']?.toString().trim();
    if (notifId != null && notifId.isNotEmpty) {
      try {
        await _ref.read(apiClientProvider).markNotificationRead(notifId);
      } catch (_) {}
    }
    final router = _ref.read(appRouterProvider);
    router.go(route, extra: driverMissionNotificationRequestFor(route));
  }

  Future<void> requestPermission() async {
    try {
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await _tryUploadCurrentToken();
    } catch (_) {}
    _ref.invalidate(notificationSettingsProvider);
  }
}

Future<void> showBackgroundClientTrackingNotification(
  FlutterLocalNotificationsPlugin notifications,
  Map<String, dynamic> data,
) async {
  final parcelId = data['ref_id']?.toString() ?? '';
  if (parcelId.isEmpty) return;
  final trackingCode = data['tracking_code']?.toString();
  final phase = data['phase']?.toString() ?? 'Livraison en cours';
  final distanceText = data['distance_text']?.toString();
  final etaText = data['eta_text']?.toString();
  final details = <String>[
    if (distanceText != null && distanceText.isNotEmpty)
      'Distance par la route : $distanceText',
    if (etaText != null && etaText.isNotEmpty) 'Temps estimé : $etaText',
  ];
  await notifications.show(
    trackingProgressNotificationId(parcelId),
    'Suivi${trackingCode == null || trackingCode.isEmpty ? '' : ' · $trackingCode'}',
    [phase, ...details].join(' · '),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'denkma_tracking_progress_v1',
        'Suivi en cours',
        channelDescription: 'Progression des colis suivis et missions actives',
        importance: Importance.low,
        priority: Priority.low,
        category: AndroidNotificationCategory.status,
        icon: 'ic_notification_logo',
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        showWhen: false,
      ),
    ),
    payload: jsonEncode(data),
  );
}
