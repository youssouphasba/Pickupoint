import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/notifications/notification_service.dart';

class NotificationPermissionBanner extends ConsumerWidget {
  const NotificationPermissionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(notificationSettingsProvider);

    return settingsAsync.maybeWhen(
      data: (settings) {
        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          color: Colors.amber.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  color: Colors.amber.shade900),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications inactives',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                    const Text(
                      'Activez-les pour suivre vos colis et recevoir vos codes de livraison.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(notificationServiceProvider).requestPermission(),
                child: const Text('Activer'),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
