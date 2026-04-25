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
              final rewardKind = event['reward_kind']?.toString() ?? 'points';
              final points = _intValue(event['points']);
              final amountXof = _numValue(event['amount_xof']);
              final balance = _intValue(event['balance']);
              final isCash = rewardKind == 'cash';
              final isPositive = isCash ? amountXof >= 0 : points >= 0;
              final subtitle = _buildSubtitle(
                event: event,
                balance: balance,
                isCash: isCash,
              );

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
                  subtitle: Text(subtitle),
                  trailing: Text(
                    isCash
                        ? '${isPositive ? "+" : ""}${_formatCurrency(amountXof)}'
                        : '${isPositive ? "+" : ""}$points pts',
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
      case 'monthly_bonus':
        return 'Prime mensuelle';
      case 'level_up':
        return 'Montee de niveau';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  String _buildSubtitle({
    required Map<String, dynamic> event,
    required int balance,
    required bool isCash,
  }) {
    final dateText = _formatEventDate(event['created_at']);
    final description = (event['description']?.toString() ?? '').trim();
    if (isCash) {
      if (description.isNotEmpty) {
        return '$dateText - $description';
      }
      return dateText;
    }
    if (balance > 0) {
      return '$dateText - Solde: $balance pts';
    }
    return dateText;
  }

  String _formatCurrency(num value) {
    final rounded = value.round();
    return '${rounded.toString()} XOF';
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

  num _numValue(dynamic value) {
    if (value is num) {
      return value;
    }
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }
}
