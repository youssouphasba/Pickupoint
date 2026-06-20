import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    _selectedPeriod = _monthValue(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(adminFinanceOverviewProvider(_selectedPeriod));
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
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Commissions Denkma, recharges livreurs, relais, retraits et éléments à surveiller.',
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
                data: Map<String, dynamic>.from(data),
                reconciliation: reconciliationAsync.valueOrNull == null
                    ? null
                    : Map<String, dynamic>.from(reconciliationAsync.valueOrNull!),
              ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => _ErrorCard(
                title: 'Erreur de chargement finance',
                message: friendlyError(error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({required this.data, required this.reconciliation});

  final Map<String, dynamic> data;
  final Map<String, dynamic>? reconciliation;

  @override
  Widget build(BuildContext context) {
    final alerts = _listOfMaps(data['alerts']);
    final payments = _map(data['payments']);
    final commissions = _map(data['commissions']);
    final relays = _map(data['relays']);
    final payouts = _map(data['payouts']);
    final wallets = _map(data['wallets']);
    final topups = _map(data['topups']);

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
                label: _string(alert['label']),
                value: '${alert['value'] ?? 0}',
                tone: _string(alert['tone'], fallback: 'info'),
                onTap: () => _showFinanceDetails(
                  context,
                  title: _string(alert['label']),
                  description: 'Éléments concernés sur la période choisie',
                  items: _listOfMaps(alert['items']),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        const _SectionTitle('Paiements colis'),
        const SizedBox(height: 6),
        const Text(
          'Le client paie hors application. Cette zone sert à suivre les colis et le payeur choisi.',
          style: TextStyle(color: Colors.black54),
        ),
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
              title: 'Valeur des colis en cours',
              value: formatXof(_number(payments['active_expected_amount_xof']).toDouble()),
              subtitle: '${payments['active_parcels'] ?? 0} colis actifs',
              onTap: () => _showFinanceDetails(
                context,
                title: 'Colis en cours',
                items: _detailList(payments, 'active'),
              ),
            ),
            _MetricCard(
              title: 'Colis livrés',
              value: '${payments['delivered_parcels'] ?? 0}',
              subtitle: '${formatXof(_number(payments['delivered_amount_xof']).toDouble())} à la livraison',
              color: Colors.blue,
              onTap: () => _showFinanceDetails(
                context,
                title: 'Colis livrés',
                items: _detailList(payments, 'delivered'),
              ),
            ),
            _MetricCard(
              title: 'Colis annulés',
              value: '${payments['cancelled_parcels'] ?? 0}',
              subtitle: '${formatXof(_number(payments['cancelled_amount_xof']).toDouble())} sortis du flux',
              color: Colors.redAccent,
              onTap: () => _showFinanceDetails(
                context,
                title: 'Colis annulés',
                items: _detailList(payments, 'cancelled'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Répartition du paiement des colis',
          rows: [
            _RowData(
              'Expéditeur paie',
              '${payments['sender_pays_parcels'] ?? 0} colis',
              onTap: () => _showFinanceDetails(
                context,
                title: 'Colis payés par l’expéditeur',
                items: _detailList(payments, 'sender_pays'),
              ),
            ),
            _RowData(
              'Destinataire paie',
              '${payments['recipient_pays_parcels'] ?? 0} colis',
              onTap: () => _showFinanceDetails(
                context,
                title: 'Colis payés par le destinataire',
                items: _detailList(payments, 'recipient_pays'),
              ),
            ),
            _RowData(
              'Colis livrés',
              '${payments['delivered_parcels'] ?? 0} colis',
              onTap: () => _showFinanceDetails(
                context,
                title: 'Colis livrés',
                items: _detailList(payments, 'delivered'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Commissions Denkma'),
        const SizedBox(height: 6),
        const Text(
          'Denkma encaisse ses commissions depuis les soldes livreurs après leurs recharges.',
          style: TextStyle(color: Colors.black54),
        ),
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
              title: 'Commission totale',
              value: formatXof(_number(commissions['platform_total_xof'] ?? commissions['platform_expected_xof']).toDouble()),
              color: Colors.indigo,
              onTap: () => _showFinanceDetails(
                context,
                title: 'Toutes les commissions Denkma',
                items: [
                  ..._detailList(commissions, 'collectable'),
                  ..._detailList(commissions, 'received'),
                  ..._detailList(commissions, 'debt'),
                  ..._detailList(commissions, 'offered'),
                ],
              ),
            ),
            _MetricCard(
              title: 'Commission à percevoir',
              value: formatXof(_number(commissions['platform_collectable_xof']).toDouble()),
              subtitle: '${_detailList(commissions, 'collectable').length} courses',
              color: Colors.orange,
              onTap: () => _showFinanceDetails(
                context,
                title: 'Commission à percevoir',
                description: 'Commissions encore non prélevées sur le solde des livreurs.',
                items: _detailList(commissions, 'collectable'),
              ),
            ),
            _MetricCard(
              title: 'Commission reçue',
              value: formatXof(_number(commissions['platform_received_xof']).toDouble()),
              color: Colors.green,
              onTap: () => _showFinanceDetails(
                context,
                title: 'Commission déjà reçue',
                items: _detailList(commissions, 'received'),
              ),
            ),
            _MetricCard(
              title: 'Commission offerte',
              value: formatXof(_number(commissions['platform_offered_xof']).toDouble()),
              subtitle: '${commissions['offered_by_denkma_count'] ?? 0} courses',
              color: Colors.purple,
              onTap: () => _showFinanceDetails(
                context,
                title: 'Commission offerte',
                items: _detailList(commissions, 'offered'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Mode de prise en charge',
          rows: [
            _RowData(
              'Prélevée sur le solde du livreur',
              '${commissions['charged_to_balance_count'] ?? 0} courses',
              onTap: () => _showFinanceDetails(
                context,
                title: 'Commissions prélevées sur le solde',
                items: _detailList(commissions, 'charged_to_balance'),
              ),
            ),
            _RowData(
              'Mise en dette du livreur',
              '${commissions['charged_as_debt_count'] ?? 0} courses',
              onTap: () => _showFinanceDetails(
                context,
                title: 'Commissions mises en dette',
                items: _detailList(commissions, 'charged_as_debt'),
              ),
            ),
            _RowData(
              'Montant en dette',
              formatXof(_number(commissions['debt_amount_xof']).toDouble()),
              onTap: () => _showFinanceDetails(
                context,
                title: 'Montants en dette',
                items: _detailList(commissions, 'debt'),
              ),
            ),
            _RowData(
              'En attente de réponse livreur',
              '${commissions['waiting_driver_confirmation_count'] ?? 0} courses',
              onTap: () => _showFinanceDetails(
                context,
                title: 'Courses en attente de réponse livreur',
                items: _detailList(commissions, 'waiting_driver_confirmation'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Relais et retraits'),
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
              title: 'Recharges payées',
              value: formatXof(_number(topups['paid_amount_xof']).toDouble()),
              subtitle: '${topups['paid_count'] ?? 0} recharges',
              color: Colors.teal,
              onTap: () => _showFinanceDetails(
                context,
                title: 'Recharges Stripe payées',
                description: 'Argent encaissé par Denkma avant crédit du solde livreur.',
                items: _detailList(topups, 'paid'),
              ),
            ),
            _MetricCard(
              title: 'Retraits en attente',
              value: '${payouts['waiting_count'] ?? 0}',
              subtitle: formatXof(_number(payouts['waiting_amount_xof']).toDouble()),
              color: Colors.deepOrange,
              onTap: () => _showFinanceDetails(
                context,
                title: 'Retraits en attente',
                items: _detailList(payouts, 'waiting'),
              ),
            ),
            _MetricCard(
              title: 'Relais à payer',
              value: formatXof(_number(relays['amount_due_xof']).toDouble()),
              color: Colors.blueGrey,
              onTap: () => _showFinanceDetails(
                context,
                title: 'Relais à payer',
                items: _detailList(relays, 'due'),
              ),
            ),
            _MetricCard(
              title: 'Relais déjà payés',
              value: formatXof(_number(relays['amount_already_sent_xof']).toDouble()),
              color: Colors.green,
              onTap: () => _showFinanceDetails(
                context,
                title: 'Relais déjà payés',
                items: _detailList(relays, 'sent'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Retraits',
          rows: [
            _RowData(
              'En attente',
              '${payouts['waiting_count'] ?? 0}',
              trailingHint: formatXof(_number(payouts['waiting_amount_xof']).toDouble()),
              onTap: () => _showFinanceDetails(
                context,
                title: 'Retraits en attente',
                items: _detailList(payouts, 'waiting'),
              ),
            ),
            _RowData(
              'Envoyés',
              '${payouts['sent_count'] ?? 0}',
              trailingHint: formatXof(_number(payouts['sent_amount_xof']).toDouble()),
              onTap: () => _showFinanceDetails(
                context,
                title: 'Retraits envoyés',
                items: _detailList(payouts, 'sent'),
              ),
            ),
            _RowData(
              'Refusés',
              '${payouts['refused_count'] ?? 0}',
              trailingHint: formatXof(_number(payouts['refused_amount_xof']).toDouble()),
              onTap: () => _showFinanceDetails(
                context,
                title: 'Retraits refusés',
                items: _detailList(payouts, 'refused'),
              ),
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
              value: formatXof(_number(wallets['total_available_amount_xof']).toDouble()),
            ),
            _MetricCard(
              title: 'Montant en attente',
              value: formatXof(_number(wallets['total_waiting_amount_xof']).toDouble()),
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
              highlight: _number(wallets['negative_wallets']) > 0,
            ),
            _RowData(
              'Comptes avec montant en attente',
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

  List<Widget> _buildIssueCards(BuildContext context, Map<String, dynamic> reconciliation) {
    const labels = {
      'wallet_pending_mismatches': 'Montants en attente à corriger',
      'negative_wallets': 'Soldes négatifs à vérifier',
      'payout_ledger_gaps': 'Retraits à revoir',
      'mission_parcel_mismatches': 'Courses à revoir',
    };

    final widgets = <Widget>[];
    for (final entry in labels.entries) {
      final items = _listOfMaps(reconciliation[entry.key]);
      if (items.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _AlertCard(
            label: entry.value,
            value: '${items.length}',
            tone: 'warning',
            onTap: () => _showFinanceDetails(
              context,
              title: entry.value,
              description: 'Éléments du contrôle de cohérence',
              items: items,
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.value, required this.onChanged});

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
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tone),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.rows});

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
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: row.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(row.label, style: const TextStyle(color: Colors.black54)),
                                if (row.trailingHint != null) ...[
                                  const SizedBox(height: 2),
                                  Text(row.trailingHint!, style: const TextStyle(fontSize: 12, color: Colors.black45)),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: row.highlight
                                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.title, required this.message});

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
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800));
  }
}

class _RowData {
  const _RowData(this.label, this.value, {this.highlight = false, this.trailingHint, this.onTap});

  final String label;
  final String value;
  final bool highlight;
  final String? trailingHint;
  final VoidCallback? onTap;
}

class _MonthItem {
  const _MonthItem(this.value, this.label);

  final String value;
  final String label;
}

class _FinanceDetailTile extends StatelessWidget {
  const _FinanceDetailTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final amount = item['amount_xof'];
    final subtitle = _string(item['subtitle'], fallback: '');
    final meta = _string(item['meta'], fallback: '');
    final status = _string(item['status'], fallback: '');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _string(item['title'], fallback: 'Élément'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(meta, style: const TextStyle(fontSize: 12, color: Colors.black45)),
          ],
          if (amount is num) ...[
            const SizedBox(height: 10),
            Text(formatXof(amount.toDouble()), style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          if (status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue),
              ),
            ),
          ],
        ],
      ),
    );
  }
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

Map<String, dynamic> _map(dynamic value) => Map<String, dynamic>.from(value as Map? ?? const {});

List<Map<String, dynamic>> _listOfMaps(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
}

List<Map<String, dynamic>> _detailList(Map<String, dynamic> root, String key) {
  final details = _map(root['details']);
  return _listOfMaps(details[key]);
}

num _number(dynamic value) => value is num ? value : 0;

String _string(dynamic value, {String fallback = '-'}) {
  if (value is! String) return fallback;
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

void _showFinanceDetails(
  BuildContext context, {
  required String title,
  String? description,
  required List<Map<String, dynamic>> items,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if (description != null) ...[
                  const SizedBox(height: 6),
                  Text(description, style: const TextStyle(color: Colors.black54)),
                ],
                const SizedBox(height: 16),
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Text(
                            'Aucun élément à afficher.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) => _FinanceDetailTile(item: items[index]),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
