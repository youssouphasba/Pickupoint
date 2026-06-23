import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../router/app_router.dart';
import 'notification_navigation.dart';

final notificationServiceProvider = Provider((ref) => NotificationService(ref));

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

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showLocalNotification(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessageNavigation);
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

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
    });
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
      await _ref.read(apiClientProvider).updateFcmToken(token);
    } catch (_) {}
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null && android != null) {
      _localNotifs.show(
        notification.hashCode,
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
    final authState = _ref.read(authProvider).valueOrNull;
    final role = authState?.effectiveRole ?? 'client';
    final route = notificationRouteFor(
      refType: data['ref_type']?.toString(),
      refId: data['ref_id']?.toString(),
      role: role,
    );
    if (route == null || route.isEmpty) {
      return;
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
