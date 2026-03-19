import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/notifications/notification_service.dart';
import 'app.dart';

/// Handler pour les messages FCM reçus en arrière-plan / app fermée.
/// Doit être une fonction top-level (pas dans une classe).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
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

  // Init push notifications (FCM)
  try {
    await container.read(notificationServiceProvider).init();
  } catch (e) {
    debugPrint('Push notifications init failed: $e');
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const PickuPointApp(),
  ));
}
