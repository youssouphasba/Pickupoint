import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';

final clientLoyaltyProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ref.watch(apiClientProvider).getLoyalty();
  return Map<String, dynamic>.from(response.data as Map);
});

String _percent(dynamic value) {
  final number = value is num ? value.toDouble() : 0.0;
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toString();
}

String _benefit(Map<String, dynamic> data) {
  final discount = (data['discount_percent'] as num?) ?? 0;
  return discount > 0
      ? '${_percent(discount)} % de réduction sur vos envois'
      : 'Cumulez des points à chaque colis livré';
}

String _nextBenefit(Map<String, dynamic> data) {
  final next = data['next_tier'];
  if (next is! Map) return 'Vous avez atteint le niveau le plus élevé.';
  final deliveries = (data['deliveries_remaining'] as num?)?.toInt();
  if (deliveries == null) return 'Consultez votre progression';
  return 'Encore $deliveries colis ${deliveries == 1 ? "livré" : "livrés"} pour le niveau ${next['label']} (${_percent(next['discount_percent'])} %).';
}

class ClientLoyaltyCard extends ConsumerWidget {
  const ClientLoyaltyCard({super.key, this.home = false});

  final bool home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientLoyaltyProvider);
    return state.when(
      loading: () =>
          home ? const SizedBox.shrink() : const LinearProgressIndicator(),
      error: (_, __) => home
          ? const SizedBox.shrink()
          : TextButton(
              onPressed: () => ref.invalidate(clientLoyaltyProvider),
              child: const Text('Réessayer de charger la fidélité'),
            ),
      data: (data) => Padding(
        padding:
            home ? const EdgeInsets.fromLTRB(16, 0, 16, 16) : EdgeInsets.zero,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showClientLoyaltyDialog(context),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.workspace_premium_outlined,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('Votre fidélité',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      const Icon(Icons.chevron_right),
                    ]),
                    const SizedBox(height: 8),
                    Text('${data['tier_label']} · ${data['points']} points'),
                    const SizedBox(height: 4),
                    Text(_benefit(data)),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                        value: ((data['progress'] as num?)?.toDouble() ?? 0)
                            .clamp(0, 1)),
                    const SizedBox(height: 8),
                    Text(_nextBenefit(data),
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showClientLoyaltyDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _LoyaltyDialog(),
    );

class _LoyaltyDialog extends ConsumerWidget {
  const _LoyaltyDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientLoyaltyProvider);
    return AlertDialog(
      title: const Text('Votre fidélité'),
      scrollable: true,
      content: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => TextButton(
            onPressed: () => ref.invalidate(clientLoyaltyProvider),
            child: const Text('Impossible de charger. Réessayer')),
        data: (data) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Niveau ${data['tier_label']} · ${data['points']} points',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(_benefit(data)),
          const SizedBox(height: 12),
          LinearProgressIndicator(
              value: ((data['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1)),
          const SizedBox(height: 8),
          Text(_nextBenefit(data)),
          const Divider(height: 24),
          Text(
              '${data['points_per_delivery']} points par colis envoyé puis livré.'),
          const SizedBox(height: 12),
          for (final tier in data['tiers'] as List? ?? [])
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    '${tier['label']} : dès ${tier['min_points']} points · ${_percent(tier['discount_percent'])} % de réduction')),
          const SizedBox(height: 8),
          Text(data['conditions']?.toString() ?? ''),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer')),
        TextButton(
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.push('/client/loyalty-history');
            },
            child: const Text('Historique')),
      ],
    );
  }
}

class ClientLoyaltyAward extends ConsumerWidget {
  const ClientLoyaltyAward({super.key, required this.award});
  final Map<String, dynamic> award;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(clientLoyaltyProvider).asData?.value;
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('+${award['points']} points crédités pour ce colis',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        if (award['tier_changed'] == true)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'Un nouveau niveau a été atteint grâce à cette livraison !'),
          ),
        if (data != null) ...[
          const SizedBox(height: 8),
          Text(_nextBenefit(data)),
        ],
        TextButton(
            onPressed: () => showClientLoyaltyDialog(context),
            child: const Text('Ma fidélité')),
      ]),
    ));
  }
}
