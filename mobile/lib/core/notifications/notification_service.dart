import 'dart:io';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../router/app_router.dart';
import 'notification_navigation.dart';

final notificationServiceProvider = Provider((ref) => NotificationService(ref));

final notificationSettingsProvider =
    FutureProvider<NotificationSettings>((ref) {
  return FirebaseMessaging.instance.getNotificationSettings();
});

class NotificationService {
  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  NotificationService(this._ref);

  bool _initialMessageHandled = false;

  Future<void> init() async {
    if (Platform.isAndroid) {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
      await _tryUploadCurrentToken();

      _fcm.onTokenRefresh.listen((token) {
        _uploadToken(token);
      });

      _ref.listen(authProvider, (_, next) async {
        final authState = next.valueOrNull;
        if (authState?.accessToken == null) {
          return;
        }
        final token = await _fcm.getToken();
        if (token != null) {
          await _uploadToken(token);
        }
      });

      await _initializeLocalNotifications();

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showLocalNotification(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessageNavigation);
      await _handleInitialMessage();
      return;
    }

    // 1. Demander les permissions
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // 2. Sur iOS, on peut essayer de forcer la récupération du token APNs
    if (Platform.isIOS) {
      await _fcm.getAPNSToken();
    }

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // 3. Récupérer le token et l'envoyer au backend si l'utilisateur est connecté
      String? token = await _fcm.getToken();
      if (token != null) {
        await _uploadToken(token);
      }
    }

    // 4. Écouter le rafraîchissement du token
    _fcm.onTokenRefresh.listen((token) {
      _uploadToken(token);
    });

    // 5. Réessayer dès qu'un utilisateur se connecte.
    _ref.listen(authProvider, (_, next) async {
      final authState = next.valueOrNull;
      if (authState?.accessToken == null) {
        return;
      }

      final token = await _fcm.getToken();
      if (token != null) {
        await _uploadToken(token);
      }
    });

    // 6. Configurer l'affichage natif au premier plan pour iOS
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    await _tryUploadCurrentToken();

    // 7. Configurer les notifications locales
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
    await _localNotifs.initialize(initSettings);

    // 8. Gérer les messages en premier plan
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
    } catch (_) {
      // L'utilisateur n'est peut-être pas encore connecté
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

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
    if (_initialMessageHandled) return;
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
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    // On peut invalider le provider pour rafraîchir l'UI
    await _tryUploadCurrentToken();
    _ref.invalidate(notificationSettingsProvider);
  }
}
