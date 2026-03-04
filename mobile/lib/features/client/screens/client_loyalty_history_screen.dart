import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/date_format.dart';

final clientLoyaltyHistoryProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getLoyalty();
  final data = res.data as Map<String, dynamic>;
  return data['history'] as List? ?? [];
});

class ClientLoyaltyHistoryScreen extends ConsumerWidget {
  const ClientLoyaltyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(clientLoyaltyHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Historique Points & Bonus')),
      body: historyAsync.when(
        data: (events) {
          if (events.isEmpty) {
            return const Center(child: Text('Aucun événement fidélité enregistré.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final ev = events[i] as Map<String, dynamic>;
              final date = ev['created_at'] != null ? formatDate(DateTime.parse(ev['created_at'])) : "---";
              final type = ev['event_type'] ?? "UNKNOWN";
              final points = ev['points_delta'] ?? 0;
              final isPositive = points >= 0;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isPositive ? Colors.green.shade50 : Colors.red.shade50,
                  child: Icon(
                    isPositive ? Icons.add : Icons.remove,
                    color: isPositive ? Colors.green : Colors.red,
                    size: 18,
                  ),
                ),
                title: Text(_formatEventType(type)),
                subtitle: Text(date),
                trailing: Text(
                  '${isPositive ? "+" : ""}$points pts',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  String _formatEventType(String type) {
    switch (type) {
      case 'PARCEL_CREATED': return 'Envoi de colis';
      case 'PARCEL_DELIVERED': return 'Colis livré';
      case 'REFERRAL_SUCCESS': return 'Parrainage réussi';
      case 'WELCOME_BONUS': return 'Bonus de bienvenue';
      case 'LEVEL_UP': return 'Montée de niveau';
      default: return type.replaceAll('_', ' ');
    }
  }
}
