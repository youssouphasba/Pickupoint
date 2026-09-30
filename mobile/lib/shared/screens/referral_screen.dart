import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../features/client/widgets/client_referral_entry.dart';
import '../utils/currency_format.dart';
import '../utils/error_utils.dart';

final referralPageProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, skip) async {
  final response =
      await ref.watch(apiClientProvider).getMyReferrals(skip: skip, limit: 10);
  return Map<String, dynamic>.from(response.data as Map);
});

class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key, this.initialCode});
  final String? initialCode;

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  int _skip = 0;
  bool _codeOffered = false;

  @override
  void didUpdateWidget(covariant ReferralScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCode != widget.initialCode) _codeOffered = false;
  }

  Future<void> _refresh() async {
    ref.invalidate(clientReferralProvider);
    ref.invalidate(referralPageProvider);
    setState(() => _skip = 0);
    try {
      await ref.read(clientReferralProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientReferralProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon parrainage'), actions: [
        IconButton(
            tooltip: 'Actualiser',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh)),
      ]),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: info.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(children: [
            Padding(
                padding: const EdgeInsets.all(20),
                child: Text(friendlyError(error))),
            TextButton(onPressed: _refresh, child: const Text('Réessayer')),
          ]),
          data: (data) {
            if (!_codeOffered && (widget.initialCode ?? '').isNotEmpty) {
              _codeOffered = true;
              if (data['can_apply_now'] == true &&
                  data['can_be_referred'] == true) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    showReferralCodeDialog(context,
                        initialCode: widget.initialCode);
                  }
                });
              }
            }
            final received = data['received_referral'] is Map
                ? Map<String, dynamic>.from(data['received_referral'] as Map)
                : null;
            final summary = Map<String, dynamic>.from(
                data['sponsored_referrals'] as Map? ?? {});
            final offers = (data['invitation_offers'] as List? ?? [])
                .whereType<Map>()
                .map((offer) => Map<String, dynamic>.from(offer))
                .toList();
            final page =
                _skip == 0 ? null : ref.watch(referralPageProvider(_skip));
            final pageData = _skip == 0 ? summary : page?.asData?.value;
            final items = (pageData?['items'] as List? ?? [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
            final total = (summary['total'] as num?)?.toInt() ?? 0;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                    'Les primes sont payées par Denkma hors de l’application. Elles ne créditent pas votre wallet.'),
                const SizedBox(height: 16),
                if (received != null)
                  _referralCard(received, 'Votre prime de filleul', 'referred'),
                if (received == null &&
                    data['can_apply_now'] == true &&
                    data['can_be_referred'] == true)
                  FilledButton.icon(
                    onPressed: () => showReferralCodeDialog(context,
                        initialCode: widget.initialCode),
                    icon: const Icon(Icons.card_giftcard_outlined),
                    label: const Text('Ajouter un code parrainage'),
                  ),
                if ((widget.initialCode ?? '').isNotEmpty &&
                    data['can_apply_now'] != true)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          'Ce compte ne peut plus ajouter un parrain. Les parrainages déjà acceptés restent visibles ci-dessous.')),
                if (data['can_sponsor'] == true && offers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SelectableText('Votre code : ${data['referral_code']}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final offer in offers)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(offer['label']?.toString() ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text(
                                      'Pour vous : ${formatXof((offer['sponsor_bonus_xof'] as num).toDouble())}'),
                                  Text(
                                      'Pour votre filleul : ${formatXof((offer['referred_bonus_xof'] as num).toDouble())}'),
                                  const SizedBox(height: 8),
                                  const Text('Comment obtenir votre prime ?',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  const Text(
                                      '1. Partagez votre code ou votre invitation.'),
                                  Text(
                                      '2. Votre proche ajoute votre code à son compte. ${offer['apply_rule'] ?? ''}'),
                                  Text(
                                      '3. Votre proche atteint l’objectif : ${offer['reward_rule'] ?? ''}'),
                                  const Text(
                                      '4. Une fois le parrainage validé, Denkma vous paie hors de l’application. Le suivi du paiement apparaît ici.'),
                                  if (offer['referred_role'] == 'driver')
                                    const Text(
                                        'Cette offre concerne un compte déjà livreur. Une nouvelle inscription démarre comme compte client.'),
                                  TextButton.icon(
                                      onPressed: () => showReferralShareDialog(
                                              context, {
                                            ...data,
                                            'share_message':
                                                offer['share_message']
                                          }),
                                      icon: const Icon(Icons.share_outlined),
                                      label: const Text(
                                          'Partager cette invitation')),
                                ]))),
                ],
                if (data['can_sponsor'] != true)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(data['message']?.toString() ??
                          'Vous ne pouvez pas inviter de filleul actuellement.')),
                const SizedBox(height: 20),
                Text('Mes filleuls ($total)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  Text(
                      'Payé hors plateforme : ${formatXof((summary['total_sponsor_bonus_xof'] as num? ?? 0).toDouble())}'),
                  Text(
                      'À payer : ${formatXof((summary['sponsor_due_xof'] as num? ?? 0).toDouble())}'),
                ]),
                const SizedBox(height: 12),
                if (page?.isLoading == true)
                  const Center(child: CircularProgressIndicator())
                else if (page?.hasError == true) ...[
                  Text(friendlyError(page!.error!)),
                  TextButton(
                      onPressed: () =>
                          ref.invalidate(referralPageProvider(_skip)),
                      child: const Text('Réessayer')),
                ] else if (items.isEmpty)
                  const Text('Aucun filleul sur cette page.')
                else
                  for (final item in items)
                    _referralCard(
                        item,
                        item['referred_name']?.toString() ?? 'Filleul',
                        'sponsor'),
                if (total > 10 || _skip > 0)
                  Wrap(spacing: 12, children: [
                    OutlinedButton(
                        onPressed: _skip == 0
                            ? null
                            : () => setState(
                                () => _skip = (_skip - 10).clamp(0, total)),
                        child: const Text('Précédent')),
                    OutlinedButton(
                        onPressed: _skip + 10 >= total
                            ? null
                            : () => setState(() => _skip += 10),
                        child: const Text('Voir plus')),
                  ]),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _referralCard(
      Map<String, dynamic> item, String title, String beneficiary) {
    final payment = Map<String, dynamic>.from(
        (item['payments'] as Map?)?[beneficiary] as Map? ?? {});
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                  "${item['reward_metric_count'] ?? 0} / ${item['reward_count']} ${item['reward_metric_label'] ?? ''}"),
              const SizedBox(height: 8),
              ReferralPaymentSummary(
                  payment: payment,
                  qualified: [
                    'qualified',
                    'partially_paid',
                    'rewarded',
                    'qualified_no_bonus'
                  ].contains(item['status'])),
            ])));
  }
}

class ReferralPaymentSummary extends StatelessWidget {
  const ReferralPaymentSummary(
      {super.key, required this.payment, required this.qualified});
  final Map<String, dynamic> payment;
  final bool qualified;

  @override
  Widget build(BuildContext context) {
    final status = payment['status']?.toString();
    final label = switch (status) {
      'confirmed' || 'legacy_confirmed' => 'Payé hors plateforme',
      'legacy_wallet' => 'Ancien crédit wallet',
      'needs_review' => 'Historique en cours de vérification',
      'not_due' => 'Aucune prime prévue',
      _ => qualified ? 'À payer par Denkma' : 'En attente de l’objectif',
    };
    final paidAt = DateTime.tryParse(payment['paid_at']?.toString() ?? '');
    final amount =
        (payment['paid_amount_xof'] ?? payment['amount_xof']) as num? ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${formatXof(amount.toDouble())} · $label'),
      if (paidAt != null)
        Text('Le ${DateFormat('dd/MM/yyyy à HH:mm').format(paidAt.toLocal())}'),
      if (status == 'legacy_wallet')
        const Text(
            'Ce crédit historique n’est pas un nouveau paiement hors plateforme.'),
    ]);
  }
}
