import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/notification_navigation.dart';
import 'app.dart';

/// Handler pour les messages FCM reçus en arrière-plan / app fermée.
/// Doit être une fonction top-level (pas dans une classe).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final eventType = message.data['event_type']?.toString();
  final endsParcelTracking = eventType == 'parcel_detail' &&
      const {
        'delivered',
        'delivery_failed',
        'cancelled',
        'expired',
        'returned',
        'suspended',
        'disputed',
      }
          .contains(message.data['parcel_status']);
  if (eventType == 'mission_unavailable' ||
      eventType == 'tracking_progress' ||
      eventType == 'tracking_ended' ||
      endsParcelTracking) {
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      const InitializationSettings(
        android:
            AndroidInitializationSettings('@drawable/ic_notification_logo'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'denkma_tracking_progress_v1',
            'Suivi en cours',
            description: 'Progression des colis suivis et missions actives',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );
    if (eventType == 'tracking_progress') {
      await showBackgroundClientTrackingNotification(
        notifications,
        message.data,
      );
    } else if (eventType == 'tracking_ended' || endsParcelTracking) {
      final parcelId = message.data['ref_id']?.toString() ?? '';
      if (parcelId.isNotEmpty) {
        await notifications.cancel(trackingProgressNotificationId(parcelId));
      }
    } else {
      await notifications.cancel(driverActiveMissionNotificationId);
      await notifications.cancel(notificationPlatformId(message.data));
    }
  }
  debugPrint('FCM background message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('fr_FR', null);

  // Firebase est requis pour Auth + FCM
  await Firebase.initializeApp();

  // Enregistrer le handler background AVANT tout autre code FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final container = ProviderContainer();

  runApp(UncontrolledProviderScope(
    container: container,
    child: const DenkmaApp(),
  ));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await container.read(notificationServiceProvider).init();
    } catch (e) {
      debugPrint('Push notifications init failed: $e');
    }
  });
}
