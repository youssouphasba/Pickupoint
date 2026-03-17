import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/notifications/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('fr_FR', null);

  // Firebase est requis pour Auth + FCM
  await Firebase.initializeApp();

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
