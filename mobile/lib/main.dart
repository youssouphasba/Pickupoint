import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/notifications/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialiser Firebase (nécessite google-services.json)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization failed (check google-services.json): $e');
  }

  await initializeDateFormatting('fr_FR', null);
  
  final container = ProviderContainer();
  // Init notification service (best-effort, ne bloque pas le démarrage)
  try {
    await container.read(notificationServiceProvider).init();
  } catch (e) {
    debugPrint('Notification service init failed: $e');
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const PickuPointApp(),
  ));
}
