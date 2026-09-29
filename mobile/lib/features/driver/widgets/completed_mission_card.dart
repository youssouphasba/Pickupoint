import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/delivery_mission.dart';
import '../../../shared/utils/currency_format.dart';

class CompletedMissionCard extends StatelessWidget {
  const CompletedMissionCard({super.key, required this.mission});

  final DeliveryMission mission;

  @override
  Widget build(BuildContext context) {
    final isFailed = mission.isFailed;
    final color = isFailed ? Colors.red : Colors.green;
    final icon = isFailed ? Icons.cancel_outlined : Icons.check_circle_outline;
    final fallbackId =
        mission.id.length > 10 ? mission.id.substring(0, 10) : mission.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.grey.shade50,
      child: ListTile(
        onTap: () => context.push('/driver/mission/${mission.id}'),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          mission.trackingCode ?? fallbackId,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        ),
        subtitle: Text(
          '${mission.pickupLabel} → ${mission.deliveryLabel}',
          style: const TextStyle(fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatXof(mission.earnAmount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isFailed ? Colors.grey : Colors.green.shade700,
                fontSize: 14,
              ),
            ),
            Text(
              isFailed ? 'Échouée' : 'Encaissé',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
