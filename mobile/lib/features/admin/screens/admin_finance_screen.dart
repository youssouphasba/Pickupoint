import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/error_utils.dart';
import '../providers/admin_provider.dart';

class AdminFinanceScreen extends ConsumerStatefulWidget {
  const AdminFinanceScreen({super.key});

  @override
  ConsumerState<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends ConsumerState<AdminFinanceScreen> {
  late String _selectedPeriod;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedPeriod = _monthValue(now);
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync =
        ref.watch(adminFinanceOverviewProvider(_selectedPeriod));
    final reconciliationAsync = ref.watch(adminReconciliationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(adminFinanceOverviewProvider(_selectedPeriod).future),
          ref.refresh(adminReconciliationProvider.future),
        ]),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vue d’ensemble finance',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Paiements, commissions, relais, retraits et points à surveiller.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _PeriodPicker(
                  value: _selectedPeriod,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedPeriod = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            overviewAsync.when(
              data: (data) => _OverviewBody(
                data: data,
                reconciliation: reconciliationAsync.valueOrNull,
                period: _selectedPeriod,
              ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, __) => _ErrorCard(
                title: 'Erreur de chargement finance',
                message: friendlyError(e),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({
    required this.data,
    required this.reconciliation,
    required this.period,
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic>? reconciliation;
  final String period;

  String _parcelRoute(String filter) => '/admin/parcels?filter=$filter&period=$period';

  @override
  Widget build(BuildContext context) {
    final alerts = List<Map<String, dynamic>>.from(
      data['alerts'] as List? ?? const [],
    );
    final payments =
        Map<String, dynamic>.from(data['payments'] as Map? ?? const {});
    final commissions =
        Map<String, dynamic>.from(data['commissions'] as Map? ?? const {});
    final relays =
        Map<String, dynamic>.from(data['relays'] as Map? ?? const {});
    final payouts =
        Map<String, dynamic>.from(data['payouts'] as Map? ?? const {});
    final wallets =
        Map<String, dynamic>.from(data['wallets'] as Map? ?? const {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (alerts.isNotEmpty) ...[
          const _SectionTitle('À surveiller'),
          const SizedBox(height: 10),
          ...alerts.map(
            (alert) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AlertCard(
                label: alert['label']?.toString() ?? '-',
                value: '${alert['value'] ?? 0}',
                tone: alert['tone']?.toString() ?? 'info',
                onTap: () {
                  final label = (alert['label']?.toString() ?? '').toLowerCase();
                  if (label.contains('retrait')) {
                    context.push('/admin/payouts');
                    return;
                  }
                  if (label.contains('paiement')) {
                    context.push(_parcelRoute('blocked_payment'));
                    return;
                  }
                  context.push(_parcelRoute('all'));
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        const _SectionTitle('Paiements colis'),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.22,
          children: [
            _MetricCard(
              title: 'Montant sur colis en cours',
              value: formatXof(
                (payments['active_expected_amount_xof'] as num?)?.toDouble() ?? 0,
              ),
              subtitle: '${payments['active_parcels'] ?? 0} colis actifs',
              onTap: () => context.push(_parcelRoute('active')),
            ),
            _MetricCard(
              title: 'Colis livrés',
              value: '${payments['delivered_parcels'] ?? 0}',
              subtitle: formatXof(
                (payments['delivered_amount_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.blue,
              onTap: () => context.push(_parcelRoute('delivered')),
            ),
            _MetricCard(
              title: 'Colis annulés',
              value: '${payments['cancelled_parcels'] ?? 0}',
              subtitle: formatXof(
                (payments['cancelled_amount_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.redAccent,
              onTap: () => context.push(_parcelRoute('cancelled')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Répartition des paiements',
          rows: [
            _RowData(
              'Expéditeur paie',
              '${payments['sender_pays_parcels'] ?? 0} colis',
            ),
            _RowData(
              'Destinataire paie',
              '${payments['recipient_pays_parcels'] ?? 0} colis',
            ),
            _RowData(
              'Colis livrés',
              '${payments['delivered_parcels'] ?? 0} colis',
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Commissions'),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.22,
          children: [
            _MetricCard(
              title: 'Commission Denkma attendue',
              value: formatXof(
                (commissions['platform_expected_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.indigo,
              onTap: () => context.push(_parcelRoute('active')),
            ),
            _MetricCard(
              title: 'Commission Denkma reçue',
              value: formatXof(
                (commissions['platform_received_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.green,
              onTap: () => context.push(_parcelRoute('commission_received')),
            ),
            _MetricCard(
              title: 'Commission en dette',
              value: formatXof(
                (commissions['platform_debt_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.orange,
              onTap: () => context.push(_parcelRoute('commission_debt')),
            ),
            _MetricCard(
              title: 'Commission offerte',
              value: formatXof(
                (commissions['platform_offered_xof'] as num?)?.toDouble() ?? 0,
              ),
              subtitle:
                  '${commissions['offered_by_denkma_count'] ?? 0} courses',
              color: Colors.purple,
              onTap: () => context.push(_parcelRoute('commission_offered')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Mode de prise en charge',
          rows: [
            _RowData(
              'Prélevée sur le solde',
              '${commissions['charged_to_balance_count'] ?? 0} courses',
            ),
            _RowData(
              'À la charge du livreur',
              '${commissions['charged_as_debt_count'] ?? 0} courses',
            ),
            _RowData(
              'Offerte par Denkma',
              '${commissions['offered_by_denkma_count'] ?? 0} courses',
            ),
            _RowData(
              'Montant à récupérer',
              formatXof(
                (commissions['debt_amount_xof'] as num?)?.toDouble() ?? 0,
              ),
            ),
            _RowData(
              'En attente de réponse livreur',
              '${commissions['waiting_driver_confirmation_count'] ?? 0} courses',
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Relais'),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.22,
          children: [
            _MetricCard(
              title: 'Montant à verser',
              value: formatXof(
                (relays['amount_due_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.blueGrey,
              onTap: () => context.push(_parcelRoute('delivered')),
            ),
            _MetricCard(
              title: 'Déjà envoyé',
              value: formatXof(
                (relays['amount_already_sent_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.green,
              onTap: () => context.push('/admin/payouts'),
            ),
            _MetricCard(
              title: 'Reste à verser',
              value: formatXof(
                (relays['amount_remaining_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.orange,
              onTap: () => context.push('/admin/payouts'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Détail relais',
          rows: [
            _RowData(
              'Part relais départ',
              formatXof(
                (relays['origin_amount_due_xof'] as num?)?.toDouble() ?? 0,
              ),
            ),
            _RowData(
              'Part relais arrivée',
              formatXof(
                (relays['destination_amount_due_xof'] as num?)?.toDouble() ?? 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Retraits'),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.22,
          children: [
            _MetricCard(
              title: 'En attente',
              value: '${payouts['waiting_count'] ?? 0}',
              subtitle: formatXof(
                (payouts['waiting_amount_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.orange,
              onTap: () => context.push('/admin/payouts'),
            ),
            _MetricCard(
              title: 'Envoyés',
              value: '${payouts['sent_count'] ?? 0}',
              subtitle: formatXof(
                (payouts['sent_amount_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.green,
              onTap: () => context.push('/admin/payouts'),
            ),
            _MetricCard(
              title: 'Refusés',
              value: '${payouts['refused_count'] ?? 0}',
              subtitle: formatXof(
                (payouts['refused_amount_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.redAccent,
              onTap: () => context.push('/admin/payouts'),
            ),
            _MetricCard(
              title: 'Comptes bloqués',
              value: '${payouts['blocked_wallets'] ?? 0}',
              color: Colors.blueGrey,
              onTap: () => context.push('/admin/payouts'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Soldes'),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.22,
          children: [
            _MetricCard(
              title: 'Solde disponible',
              value: formatXof(
                (wallets['total_available_amount_xof'] as num?)?.toDouble() ??
                    0,
              ),
            ),
            _MetricCard(
              title: 'Montant en attente',
              value: formatXof(
                (wallets['total_waiting_amount_xof'] as num?)?.toDouble() ?? 0,
              ),
              color: Colors.orange,
            ),
            _MetricCard(
              title: 'Comptes livreurs',
              value: '${wallets['driver_wallets'] ?? 0}',
            ),
            _MetricCard(
              title: 'Comptes relais',
              value: '${wallets['relay_wallets'] ?? 0}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'À surveiller sur les soldes',
          rows: [
            _RowData(
              'Soldes négatifs',
              '${wallets['negative_wallets'] ?? 0}',
              highlight: ((wallets['negative_wallets'] ?? 0) as num) > 0,
            ),
            _RowData(
              'Comptes avec attente',
              '${wallets['wallets_with_waiting_money'] ?? 0} comptes',
            ),
          ],
        ),
        if (reconciliation != null) ...[
          const SizedBox(height: 20),
          const _SectionTitle('Points à vérifier'),
          const SizedBox(height: 10),
          ..._buildIssueCards(context, reconciliation!),
        ],
      ],
    );
  }

  List<Widget> _buildIssueCards(
    BuildContext context,
    Map<String, dynamic> reconciliation,
  ) {
    const labels = {
      'wallet_pending_mismatches': 'Montants en attente à corriger',
      'negative_wallets': 'Soldes négatifs à vérifier',
      'payout_ledger_gaps': 'Retraits à revoir',
      'mission_parcel_mismatches': 'Courses à revoir',
    };
    final widgets = <Widget>[];
    for (final entry in labels.entries) {
      final count = (reconciliation[entry.key] as List?)?.length ?? 0;
      if (count == 0) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _AlertCard(
            label: entry.value,
            value: '$count',
            tone: 'warning',
            onTap: () => context.push(_parcelRoute('all')),
          ),
        ),
      );
    }
    return widgets;
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = _monthOptions();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            items: items
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item.value,
                    child: Text(item.label),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    this.subtitle,
    this.color,
    this.onTap,
  });

  final String title;
  final String value;
  final String? subtitle;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Colors.black87;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tone.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<_RowData> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                    Container(
                      padding: row.highlight
                          ? const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            )
                          : EdgeInsets.zero,
                      decoration: row.highlight
                          ? BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            )
                          : null,
                      child: Text(
                        row.value,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: row.highlight ? Colors.orange.shade900 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.label,
    required this.value,
    required this.tone,
    this.onTap,
  });

  final String label;
  final String value;
  final String tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      'danger' => Colors.red,
      'warning' => Colors.orange,
      _ => Colors.blue,
    };
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          title: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.red),
        title: Text(title),
        subtitle: Text(message),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    );
  }
}

class _RowData {
  const _RowData(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;
}

class _MonthItem {
  const _MonthItem(this.value, this.label);

  final String value;
  final String label;
}

String _monthValue(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}-$month';
}

String _monthLabel(String value) {
  final parts = value.split('-');
  if (parts.length != 2) return value;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  const labels = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  if (year == null || month == null || month < 1 || month > 12) return value;
  return '${labels[month - 1]} $year';
}

List<_MonthItem> _monthOptions() {
  final now = DateTime.now();
  return List.generate(18, (index) {
    final date = DateTime(now.year, now.month - index, 1);
    final value = _monthValue(date);
    return _MonthItem(value, _monthLabel(value));
  });
}
