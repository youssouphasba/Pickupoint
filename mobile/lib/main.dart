import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/notifications/notification_service.dart';
import 'app.dart';

const bool _pushNotificationsEnabled = bool.fromEnvironment(
  'ENABLE_PUSH_NOTIFICATIONS',
  defaultValue: false,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('fr_FR', null);
  
  final container = ProviderContainer();

  if (_pushNotificationsEnabled) {
    try {
      await Firebase.initializeApp();
      await container.read(notificationServiceProvider).init();
    } catch (e) {
      debugPrint('Push notifications init failed: $e');
    }
  } else {
    debugPrint('Push notifications disabled via --dart-define');
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const PickuPointApp(),
  ));
}
