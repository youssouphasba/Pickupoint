import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../providers/admin_provider.dart';

class AdminFinanceScreen extends ConsumerWidget {
  const AdminFinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeAsync = ref.watch(adminFinanceProvider);
    final reconciliationAsync = ref.watch(adminReconciliationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Controle Finance & Reconciliation')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(adminFinanceProvider.future),
          ref.refresh(adminReconciliationProvider.future),
        ]),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            reconciliationAsync.when(
              data: _buildReconciliationSection,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: const Text('Erreur de reconciliation'),
                  subtitle: Text(e.toString()),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Cash COD a encaisser',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            financeAsync.when(
              data: (fin) => _buildCodSection(context, ref, fin),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: const Text('Erreur de suivi COD'),
                  subtitle: Text(e.toString()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReconciliationSection(Map<String, dynamic> report) {
    final summary = report['summary'] as Map<String, dynamic>? ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reconciliation systeme',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _SummaryCard(
              title: 'Issues totales',
              value: '${summary['issues_total'] ?? 0}',
              color: Colors.red,
              icon: Icons.warning_amber_rounded,
            ),
            _SummaryCard(
              title: 'Ledger payouts',
              value: '${summary['payout_ledger_gaps'] ?? 0}',
              color: Colors.deepOrange,
              icon: Icons.receipt_long_outlined,
            ),
            _SummaryCard(
              title: 'Wallet pending',
              value: '${summary['wallet_pending_mismatches'] ?? 0}',
              color: Colors.amber.shade800,
              icon: Icons.account_balance_wallet_outlined,
            ),
            _SummaryCard(
              title: 'Mission vs colis',
              value: '${summary['mission_parcel_mismatches'] ?? 0}',
              color: Colors.indigo,
              icon: Icons.sync_problem_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _IssueBlock(
          title: 'Ecarts pending wallet',
          subtitle:
              'Le montant pending du wallet doit egaler la somme des retraits en attente.',
          items: List<Map<String, dynamic>>.from(
            report['wallet_pending_mismatches'] as List? ?? const [],
          ),
          builder: (item) => ListTile(
            dense: true,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text('${item['owner_type']} • ${item['owner_id']}'),
            subtitle: Text(
              'Wallet: ${formatXof((item['wallet_pending'] as num?)?.toDouble() ?? 0)} • Attendu: ${formatXof((item['expected_pending'] as num?)?.toDouble() ?? 0)}',
            ),
          ),
        ),
        _IssueBlock(
          title: 'Payouts sans ecriture ledger',
          subtitle:
              'Chaque payout doit avoir son ecriture pending/debit/credit correspondante.',
          items: List<Map<String, dynamic>>.from(
            report['payout_ledger_gaps'] as List? ?? const [],
          ),
          builder: (item) => ListTile(
            dense: true,
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text('${item['payout_id']} • ${item['status']}'),
            subtitle: Text(
              'Wallet: ${item['wallet_id']} • Ecriture attendue: ${item['expected_tx_type']} • Montant: ${formatXof((item['amount'] as num?)?.toDouble() ?? 0)}',
            ),
          ),
        ),
        _IssueBlock(
          title: 'Wallets negatifs',
          subtitle:
              'Un wallet ne devrait pas avoir de balance ou pending negatif.',
          items: List<Map<String, dynamic>>.from(
            report['negative_wallets'] as List? ?? const [],
          ),
          builder: (item) => ListTile(
            dense: true,
            leading: const Icon(Icons.money_off_csred_outlined),
            title: Text('${item['owner_type']} • ${item['owner_id']}'),
            subtitle: Text(
              'Balance: ${formatXof((item['balance'] as num?)?.toDouble() ?? 0)} • Pending: ${formatXof((item['pending'] as num?)?.toDouble() ?? 0)}',
            ),
          ),
        ),
        _IssueBlock(
          title: 'Missions incoherentes',
          subtitle:
              'Mission active avec colis absent ou dans un statut non compatible.',
          items: List<Map<String, dynamic>>.from(
            report['mission_parcel_mismatches'] as List? ?? const [],
          ),
          builder: (item) => ListTile(
            dense: true,
            leading: const Icon(Icons.sync_problem_outlined),
            title: Text('${item['mission_id']} • colis ${item['parcel_id']}'),
            subtitle: Text(
              'Mission: ${item['mission_status'] ?? '-'} • Colis: ${item['parcel_status'] ?? 'introuvable'}',
            ),
          ),
        ),
        _IssueBlock(
          title: 'Colis livres non payes',
          subtitle: 'A verifier pour eviter qu\'un expediteur soit lese.',
          items: List<Map<String, dynamic>>.from(
            report['delivered_unpaid'] as List? ?? const [],
          ),
          builder: (item) => ListTile(
            dense: true,
            leading: const Icon(Icons.lock_clock_outlined),
            title: Text('${item['tracking_code'] ?? item['parcel_id']}'),
            subtitle: Text(
              'Statut paiement: ${item['payment_status'] ?? '-'} • Qui paie: ${item['who_pays'] ?? '-'}',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodSection(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> fin,
  ) {
    if (fin.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.check_circle_outline, color: Colors.green),
          title: Text('Aucun cash COD a encaisser'),
        ),
      );
    }

    return Column(
      children: fin.map((e) {
        final amount = (e['cod_balance'] as num?)?.toDouble() ?? 0.0;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: CircleAvatar(
              backgroundColor:
                  amount > 0 ? Colors.orange.shade50 : Colors.grey.shade50,
              child: Icon(
                Icons.person,
                color: amount > 0 ? Colors.orange : Colors.grey,
              ),
            ),
            title: Text(
              e['name'] ?? 'Livreur inconnu',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'ID: ${e['user_id']}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatXof(amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: amount > 0
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                  ),
                ),
                if (amount > 0)
                  const Text(
                    'A encaisser',
                    style: TextStyle(fontSize: 10, color: Colors.orange),
                  ),
              ],
            ),
            onTap: amount > 0
                ? () => _showSettleDialog(
                      context,
                      ref,
                      amount,
                      e['user_id']?.toString() ?? '',
                      e['name']?.toString() ?? 'Livreur',
                    )
                : null,
          ),
        );
      }).toList(),
    );
  }

  void _showSettleDialog(
    BuildContext context,
    WidgetRef ref,
    double amount,
    String driverId,
    String name,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmer l\'encaissement'),
        content: Text(
          'Voulez-vous marquer ${formatXof(amount)} collectes par $name comme encaissees ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(apiClientProvider).settleCod(driverId);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  ref.invalidate(adminFinanceProvider);
                  ref.invalidate(adminReconciliationProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tresorerie soldee avec succes.'),
                    ),
                  );
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e')),
                  );
                }
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _IssueBlock extends StatelessWidget {
  const _IssueBlock({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic> item) builder;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        initiallyExpanded: items.isNotEmpty,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          items.isEmpty ? 'Aucun ecart detecte.' : subtitle,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: items.isEmpty
                ? Colors.green.withValues(alpha: 0.12)
                : Colors.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${items.length}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: items.isEmpty ? Colors.green : Colors.red,
            ),
          ),
        ),
        children: items.isEmpty
            ? const [
                ListTile(
                  dense: true,
                  leading:
                      Icon(Icons.check_circle_outline, color: Colors.green),
                  title: Text('Aucun probleme detecte sur ce controle.'),
                ),
              ]
            : items.map(builder).toList(),
      ),
    );
  }
}
