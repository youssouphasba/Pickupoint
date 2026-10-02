import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/widgets/support_whatsapp_tile.dart';
import '../providers/relay_provider.dart';

class RelayPaymentsButton extends ConsumerStatefulWidget {
  const RelayPaymentsButton({super.key});

  @override
  ConsumerState<RelayPaymentsButton> createState() =>
      _RelayPaymentsButtonState();
}

class _RelayPaymentsButtonState extends ConsumerState<RelayPaymentsButton>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
  }

  void _refresh() => ref.invalidate(relayFinancialActionsProvider);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(foregroundNotificationRefreshProvider, (_, __) => _refresh());
    final count = ref.watch(relayFinancialActionCountProvider);
    return Badge(
      isLabelVisible: (count.valueOrNull ?? 0) > 0,
      label: Text('${count.valueOrNull ?? 0}'),
      child: IconButton(
        tooltip: count.hasError
            ? 'Paiements · compteur indisponible'
            : 'Actions de paiement : ${count.valueOrNull ?? 0}',
        icon: const Icon(Icons.receipt_long_outlined),
        onPressed: () async {
          await context.push('/relay/payments');
          if (mounted) _refresh();
        },
      ),
    );
  }
}

class RelayPaymentsScreen extends ConsumerStatefulWidget {
  const RelayPaymentsScreen({super.key});

  @override
  ConsumerState<RelayPaymentsScreen> createState() =>
      _RelayPaymentsScreenState();
}

class _RelayPaymentsScreenState extends ConsumerState<RelayPaymentsScreen> {
  int _skip = 0;
  bool _pendingOnly = true;
  String? _working;

  void _refresh() => ref.invalidate(relayFinancialActionsProvider);

  Future<void> _declare(Map<String, dynamic> action) async {
    if (_working != null) return;
    final amount = formatXof((action['amount_xof'] as num).toDouble());
    final driver = action['key'] == 'driver_payment';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(driver
            ? 'Confirmer la remise au livreur'
            : 'Confirmer le règlement à Denkma'),
        content: Text(
            'Colis ${action['tracking_code']}\n\nAvez-vous réellement payé $amount ${driver ? 'au livreur' : 'à Denkma'} hors de l’application ?\n\nCette déclaration sera ensuite vérifiée par Denkma. Aucun paiement n’est effectué par ce bouton.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Pas encore')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Oui, paiement effectué')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final relayId = ref.read(authProvider).valueOrNull?.user?.relayPointId;
    if (relayId == null) return;
    setState(() => _working = '${action['parcel_id']}:${action['key']}');
    try {
      await ref.read(apiClientProvider).declareRelayFinancialAction(
          relayId, action['parcel_id'] as String, action['key'] as String);
      if (!mounted) return;
      setState(() => _skip = 0);
      _refresh();
      ref.invalidate(relayStockProvider);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Paiement déclaré. Validation par Denkma en attente.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(foregroundNotificationRefreshProvider, (_, __) => _refresh());
    final data = ref.watch(relayFinancialActionsProvider(
        (skip: _skip, pendingOnly: _pendingOnly)));
    return Scaffold(
      appBar: AppBar(
          title: const Text('Actions de paiement'),
          actions: const [SupportWhatsAppButton()]),
      body: RefreshIndicator(
        onRefresh: () async {
          _refresh();
          await ref.read(relayFinancialActionsProvider(
              (skip: _skip, pendingOnly: _pendingOnly)).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
                'Payez hors de l’application, puis déclarez le règlement ici. Denkma vérifie ensuite votre déclaration. Ces montants ne sont pas des recharges de votre solde.'),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('À faire')),
                ButtonSegment(value: false, label: Text('Suivi'))
              ],
              selected: {_pendingOnly},
              onSelectionChanged: _working != null
                  ? null
                  : (value) => setState(() {
                        _pendingOnly = value.single;
                        _skip = 0;
                      }),
            ),
            const SizedBox(height: 16),
            ...data.when(
              loading: () => [const Center(child: CircularProgressIndicator())],
              error: (error, _) => [
                Text(friendlyError(error)),
                TextButton(onPressed: _refresh, child: const Text('Réessayer'))
              ],
              data: (page) {
                final items = (page['actions'] as List? ?? [])
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList();
                return [
                  if ((page['unavailable_count'] as num? ?? 0) > 0)
                    const Text(
                        'Certains règlements nécessitent une vérification de leurs montants par le support. Le compteur peut être incomplet.'),
                  Text('${page['pending_count'] ?? 0} action(s) à effectuer',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    Text(_pendingOnly
                        ? 'Aucun paiement à déclarer actuellement.'
                        : 'Aucun règlement à afficher.'),
                  ...items.map((action) {
                    final status = action['status'] as String? ?? 'pending';
                    final actionable = action['actionable'] == true;
                    final driver = action['key'] == 'driver_payment';
                    return Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                      action['label'] as String? ?? 'Règlement',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 6),
                                  Text('Colis ${action['tracking_code']}'),
                                  if (action['beneficiary_name'] != null)
                                    Text(
                                        'Bénéficiaire : ${action['beneficiary_name']}'),
                                  if (action['beneficiary_phone'] != null)
                                    SelectableText(
                                        action['beneficiary_phone'] as String),
                                  Text(
                                      formatXof((action['amount_xof'] as num)
                                          .toDouble()),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall),
                                  Text(switch (status) {
                                    'declared' =>
                                      'Déclaré · validation Denkma en attente',
                                    'validated' => 'Validé par Denkma',
                                    'rejected' =>
                                      'Déclaration refusée · vérifiez le règlement avec le support',
                                    _ => actionable
                                        ? 'Paiement à effectuer et à déclarer'
                                        : 'Commission à recevoir · aucune déclaration nécessaire'
                                  }),
                                  if (actionable) ...[
                                    const SizedBox(height: 10),
                                    Text(driver
                                        ? 'Remettez cette somme au livreur de ce colis. Déclarez uniquement après la remise effective.'
                                        : 'Réglez cette somme à Denkma selon les instructions de règlement. Contactez le support si vous ne les avez pas.'),
                                    const SizedBox(height: 12),
                                    FilledButton(
                                        onPressed: _working != null
                                            ? null
                                            : () => _declare(action),
                                        child: Text(_working ==
                                                '${action['parcel_id']}:${action['key']}'
                                            ? 'Enregistrement…'
                                            : 'J’ai effectué ce paiement')),
                                  ],
                                ])));
                  }),
                  if (_skip > 0 || page['has_more'] == true)
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                              onPressed: _skip == 0
                                  ? null
                                  : () => setState(() =>
                                      _skip = (_skip - 20).clamp(0, _skip)),
                              child: const Text('Précédent')),
                          TextButton(
                              onPressed: page['has_more'] != true
                                  ? null
                                  : () => setState(() => _skip += 20),
                              child: const Text('Suivant')),
                        ]),
                ];
              },
            ),
            const SizedBox(height: 16),
            const SupportWhatsAppTile(),
          ],
        ),
      ),
    );
  }
}
