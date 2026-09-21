import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../../../core/auth/auth_provider.dart';
import '../../features/driver/providers/driver_provider.dart';
import '../router/app_router.dart';
import 'notification_alert_profile.dart';
import 'notification_navigation.dart';

final notificationServiceProvider = Provider((ref) => NotificationService(ref));
final foregroundNotificationRefreshProvider = StateProvider<int>((ref) => 0);

final notificationSettingsProvider =
    FutureProvider<NotificationSettings>((ref) async {
  return FirebaseMessaging.instance.getNotificationSettings();
});

const _driverMissionActivityChannel =
    MethodChannel('com.denkma.app/driver_mission_activity');

class NotificationService {
  NotificationService(this._ref);

  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  bool _initialMessageHandled = false;
  bool _localNotificationsInitialized = false;
  String? _appVersion;
  String? _activeDriverMissionNotificationId;
  DateTime? _activeDriverMissionDeadline;

  bool get _hasAuthenticatedSession {
    final authState = _ref.read(authProvider).valueOrNull;
    return authState?.accessToken != null;
  }

  Future<void> init() async {
    if (Platform.isAndroid) {
      await _initializeLocalNotifications();

      _fcm.onTokenRefresh.listen((token) {
        _uploadToken(token);
      });

      _ref.listen(authProvider, (_, next) async {
        final authState = next.valueOrNull;
        if (authState?.accessToken == null) {
          return;
        }
        await _tryUploadCurrentToken();
      });

      if (_hasAuthenticatedSession) {
        await _tryUploadCurrentToken();
      }

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp
          .listen(_handleRemoteMessageNavigation);
      await _handleInitialMessage();
      return;
    }

    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (Platform.isIOS) {
      await _fcm.getAPNSToken();
    }

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _tryUploadCurrentToken();
    }

    _fcm.onTokenRefresh.listen((token) {
      _uploadToken(token);
    });

    _ref.listen(authProvider, (_, next) async {
      final authState = next.valueOrNull;
      if (authState?.accessToken == null) {
        return;
      }
      await _tryUploadCurrentToken();
    });

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _initializeLocalNotifications();

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessageNavigation);
    await _handleInitialMessage();
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
    if (Platform.isAndroid) {
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
        await androidPlugin?.createNotificationChannel(
          profile.toAndroidChannel(),
        );
      }
    }
    _localNotificationsInitialized = true;
  }

  Future<void> _tryUploadCurrentToken() async {
    if (!_hasAuthenticatedSession) {
      return;
    }
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _uploadToken(token);
      }
    } catch (_) {}
  }

  Future<void> _uploadToken(String token) async {
    final authState = _ref.read(authProvider).valueOrNull;
    if (authState?.accessToken == null) {
      return;
    }

    try {
      _appVersion ??= (await PackageInfo.fromPlatform()).version;
      await _ref.read(apiClientProvider).updateFcmToken(
            token,
            appVersion: _appVersion,
          );
    } catch (_) {}
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    final android = message.notification?.android;
    final profile = notificationAlertProfileFor(
      eventType: message.data['event_type']?.toString(),
      refType: message.data['ref_type']?.toString(),
      category: message.data['category']?.toString(),
    );

    if (notification != null && android != null) {
      _localNotifs.show(
        notificationPlatformId(message.data),
        notification.title,
        notification.body,
        NotificationDetails(
          android: profile.toAndroidDetails(),
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
    required DateTime? pickupConfirmationDeadline,
  }) async {
    if (Platform.isIOS) {
      try {
        if (missionId == null || pickupConfirmationDeadline == null) {
          await _driverMissionActivityChannel.invokeMethod<void>('end');
        } else {
          await _driverMissionActivityChannel.invokeMethod<void>('start', {
            'missionId': missionId,
            'trackingCode': trackingCode ?? '',
            'deadline': pickupConfirmationDeadline.toUtc().toIso8601String(),
          });
        }
      } catch (_) {}
      return;
    }
    if (!Platform.isAndroid) return;
    await _initializeLocalNotifications();
    final notificationId = driverActiveMissionNotificationId;
    if (missionId == null || assignedAt == null) {
      await _localNotifs.cancel(notificationId);
      _activeDriverMissionNotificationId = null;
      _activeDriverMissionDeadline = null;
      return;
    }
    if (_activeDriverMissionNotificationId == missionId &&
        _activeDriverMissionDeadline == pickupConfirmationDeadline) {
      return;
    }
    final isPickupCountdown = pickupConfirmationDeadline != null;
    final referenceTime =
        (pickupConfirmationDeadline ?? assignedAt).millisecondsSinceEpoch;
    final data = <String, dynamic>{
      'event_type': 'mission_detail',
      'ref_type': 'mission',
      'ref_id': missionId,
      'target_view': 'driver',
    };
    try {
      final notificationTitle = isPickupCountdown
          ? '⏳ 30 min pour récupérer le colis'
          : '⏱️ Mission en cours${trackingCode == null ? '' : ' · $trackingCode'}';
      final notificationBody = isPickupCountdown
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
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            playSound: false,
            enableVibration: false,
            showWhen: true,
            when: referenceTime,
            usesChronometer: true,
            chronometerCountDown: isPickupCountdown,
            subText:
                isPickupCountdown ? 'Délai de 30 minutes' : 'Mission active',
            ticker: isPickupCountdown
                ? 'Compte à rebours de récupération actif'
                : 'Mission livreur active',
            styleInformation: BigTextStyleInformation(
              isPickupCountdown
                  ? 'Le compte à rebours reste visible à droite pendant la navigation. Confirmez la récupération avant son expiration.'
                  : 'Le chronomètre suit le temps depuis l’acceptation de la mission.',
              contentTitle: isPickupCountdown
                  ? '⏳ Récupération à confirmer'
                  : '⏱️ Mission livreur en cours',
              summaryText: 'Denkma',
            ),
          ),
        ),
        payload: jsonEncode(data),
      );
      _activeDriverMissionNotificationId = missionId;
      _activeDriverMissionDeadline = pickupConfirmationDeadline;
    } catch (_) {
      _activeDriverMissionNotificationId = null;
      _activeDriverMissionDeadline = null;
    }
  }

  Future<void> showClientTrackingNotification(
    Map<String, dynamic> data,
  ) async {
    if (Platform.isAndroid) {
      await showBackgroundClientTrackingNotification(_localNotifs, data);
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final eventType = message.data['event_type']?.toString();
    final refreshNotifier =
        _ref.read(foregroundNotificationRefreshProvider.notifier);
    refreshNotifier.state = refreshNotifier.state + 1;
    if (message.data['ref_type']?.toString() == 'mission') {
      final notifier =
          _ref.read(foregroundMissionNotificationProvider.notifier);
      notifier.state = notifier.state + 1;
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
      await _localNotifs.cancel(driverActiveMissionNotificationId);
      await _localNotifs.cancel(notificationPlatformId(message.data));
      return;
    }
    _showLocalNotification(message);
  }

  Future<void> _handleInitialMessage() async {
    if (_initialMessageHandled) {
      return;
    }
    _initialMessageHandled = true;
    final message = await _fcm.getInitialMessage();
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
    final route = notificationRouteFor(
      refType: data['ref_type']?.toString(),
      refId: data['ref_id']?.toString(),
      role: currentAuth.effectiveRole,
      eventType: eventType,
      targetView: targetView,
      messageId: data['message_id']?.toString(),
    );
    if (route == null || route.isEmpty) {
      return;
    }

    final notifId = data['notif_id']?.toString().trim();
    if (notifId != null && notifId.isNotEmpty) {
      try {
        await _ref.read(apiClientProvider).markNotificationRead(notifId);
      } catch (_) {}
    }
    final router = _ref.read(appRouterProvider);
    router.go(route);
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
