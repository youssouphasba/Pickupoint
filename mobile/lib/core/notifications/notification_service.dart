import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../router/app_router.dart';
import 'notification_navigation.dart';

final notificationServiceProvider = Provider((ref) => NotificationService(ref));
final foregroundMissionNotificationProvider = StateProvider<int>((ref) => 0);
final foregroundNotificationRefreshProvider = StateProvider<int>((ref) => 0);

final notificationSettingsProvider =
    FutureProvider<NotificationSettings>((ref) async {
  return FirebaseMessaging.instance.getNotificationSettings();
});

class NotificationService {
  NotificationService(this._ref);

  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  bool _initialMessageHandled = false;
  String? _appVersion;

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
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
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

    if (notification != null && android != null) {
      _localNotifs.show(
        notificationPlatformId(message.data),
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'Notifications Importantes',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode(message.data),
      );
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
    if (eventType == 'mission_unavailable') {
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
