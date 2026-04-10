import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/utils/error_utils.dart';

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
      appBar: AppBar(title: const Text('Historique points et bonus')),
      body: historyAsync.when(
        data: (events) {
          if (events.isEmpty) {
            return const Center(
              child: Text('Aucun evenement de fidelite enregistre.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final event = Map<String, dynamic>.from(
                events[i] as Map<dynamic, dynamic>,
              );
              final type = event['type']?.toString() ?? 'unknown';
              final points = _intValue(event['points']);
              final balance = _intValue(event['balance']);
              final isPositive = points >= 0;

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        isPositive ? Colors.green.shade50 : Colors.red.shade50,
                    child: Icon(
                      isPositive ? Icons.add : Icons.remove,
                      color: isPositive ? Colors.green : Colors.red,
                      size: 18,
                    ),
                  ),
                  title: Text(_formatEventType(type)),
                  subtitle: Text(
                    balance > 0
                        ? '${_formatEventDate(event['created_at'])} - Solde: $balance pts'
                        : _formatEventDate(event['created_at']),
                  ),
                  trailing: Text(
                    '${isPositive ? "+" : ""}$points pts',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isPositive
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
          child: Text(friendlyError(e)),
        ),
      ),
    );
  }

  String _formatEventType(String type) {
    switch (type) {
      case 'delivery_completed':
        return 'Livraison effectuee';
      case 'referral_bonus':
        return 'Bonus de parrainage';
      case 'welcome_bonus':
        return 'Bonus de bienvenue';
      case 'level_up':
        return 'Montee de niveau';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  String _formatEventDate(dynamic rawDate) {
    if (rawDate == null) {
      return 'Date inconnue';
    }
    final parsed = DateTime.tryParse(rawDate.toString());
    if (parsed == null) {
      return 'Date inconnue';
    }
    return formatDate(parsed);
  }

  int _intValue(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
