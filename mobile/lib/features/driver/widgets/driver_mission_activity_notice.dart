import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/notifications/driver_mission_activity.dart';
import '../../../core/notifications/notification_service.dart';

class DriverMissionActivityNotice extends ConsumerWidget {
  const DriverMissionActivityNotice({super.key});

  Future<void> _act(BuildContext context, WidgetRef ref, bool settings) async {
    try {
      if (settings) {
        if (!await Geolocator.openAppSettings()) {
          throw StateError('settings_unavailable');
        }
      } else {
        await ref
            .read(notificationServiceProvider)
            .refreshDriverMissionNotification();
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Action indisponible. Réessayez dans un instant.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issue = ref.watch(driverMissionActivityIssueProvider);
    if (issue == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.timer_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(issue.message,
                  style: Theme.of(context).textTheme.bodySmall)),
          if (issue.openSettings || issue.canRetry)
            IconButton(
              tooltip: issue.openSettings ? 'Ouvrir les réglages' : 'Réessayer',
              icon: Icon(
                  issue.openSettings ? Icons.settings_outlined : Icons.refresh),
              onPressed: () => _act(context, ref, issue.openSettings),
            ),
          if (!issue.openSettings && !issue.canRetry) const SizedBox(width: 12),
        ]),
      ),
    );
  }
}
