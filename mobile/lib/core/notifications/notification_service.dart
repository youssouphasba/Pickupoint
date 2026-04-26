import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';

final notificationServiceProvider = Provider((ref) => NotificationService(ref));

class NotificationService {
  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  NotificationService(this._ref);

  Future<void> init() async {
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
      );
    }
  }
}
