import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/driver_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../../core/models/wallet.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/utils/error_utils.dart';

final driverTransactionsProvider =
    FutureProvider.family<List<WalletTransaction>, String?>(
        (ref, period) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getTransactions(period: period);
  final data = res.data as Map<String, dynamic>;
  return (data['transactions'] as List? ?? [])
      .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
      .toList();
});

final driverPayoutsProvider = FutureProvider<List<PayoutRequest>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getMyPayouts();
  final data = res.data as Map<String, dynamic>;
  return (data['payouts'] as List? ?? [])
      .map((e) => PayoutRequest.fromJson(e as Map<String, dynamic>))
      .toList();
});

class DriverWalletScreen extends ConsumerStatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  ConsumerState<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends ConsumerState<DriverWalletScreen> {
  String? _period = _monthValue(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(driverWalletProvider);
    final transactionsAsync = ref.watch(driverTransactionsProvider(_period));
    final payoutsAsync = ref.watch(driverPayoutsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Solde et revenus')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(driverWalletProvider.future),
          ref.refresh(driverTransactionsProvider(_period).future),
          ref.refresh(driverPayoutsProvider.future),
        ]),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _buildBalanceCard(context, walletAsync),
              const SizedBox(height: 24),
              _buildPayoutsSection(payoutsAsync),
              const SizedBox(height: 32),
              Row(
                children: [
                  const Expanded(
                    child: Text('Mouvements',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  SizedBox(width: 180, child: _buildPeriodFilter()),
                ],
              ),
              const SizedBox(height: 16),
              _buildTransactionsList(transactionsAsync),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodFilter() {
    final options = <String?>[null, ..._monthOptions()];

    return DropdownButtonFormField<String?>(
      initialValue: _period,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Période',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: options
          .map(
            (value) => DropdownMenuItem<String?>(
              value: value,
              child: Text(value == null ? 'Tout' : _monthLabel(value)),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _period = value),
    );
  }

  Widget _buildBalanceCard(BuildContext context, AsyncValue walletAsync) {
    return walletAsync.when(
      data: (wallet) => Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [Colors.blue.shade800, Colors.blue.shade500]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text('Solde Denkma',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              formatXof(wallet.balance),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold),
            ),
            if (wallet.pendingBalance > 0) ...[
              const SizedBox(height: 4),
              Text('En attente : ${formatXof(wallet.pendingBalance)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Décaisser mon solde',
              color: Colors.white,
              onPressed: wallet.balance > 0 && wallet.payoutAvailable
                  ? () => _showPayoutDialog(context)
                  : null,
            ),
            if (!wallet.payoutAvailable &&
                (wallet.payoutBlockReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                wallet.payoutBlockReason!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showTopupDialog(context),
              icon: const Icon(Icons.add_card),
              label: const Text('Recharger mon solde'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
      loading: () => const CircularProgressIndicator(),
      error: (e, __) => Text(friendlyError(e)),
    );
  }

  void _showTopupDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recharger le solde'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Montant (XOF)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Vous serez redirigé vers Stripe. Le solde sera crédité après confirmation du paiement.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim());
                if (amount == null || amount <= 0) return;
                try {
                  final res = await ref
                      .read(apiClientProvider)
                      .createStripeWalletTopup({'amount': amount});
                  final data = res.data as Map<String, dynamic>;
                  final checkoutUrl = data['checkout_url']?.toString();
                  if (checkoutUrl == null || checkoutUrl.isEmpty) {
                    throw Exception('Lien Stripe indisponible');
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await launchUrl(
                    Uri.parse(checkoutUrl),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e))),
                    );
                  }
                }
              },
              child: const Text('Continuer'),
            ),
          ),
        ],
      ),
    ).whenComplete(amountCtrl.dispose);
  }

  void _showPayoutDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    String method = 'wave';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Demande de décaissement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Montant (XOF)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(
                    labelText: 'Méthode', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'wave', child: Text('Wave')),
                  DropdownMenuItem(
                      value: 'orange_money', child: Text('Orange Money')),
                  DropdownMenuItem(
                      value: 'free_money', child: Text('Free Money')),
                ],
                onChanged: (v) => setState(() => method = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text);
                  if (amount == null || amount <= 0) return;
                  try {
                    final user = ref.read(authProvider).valueOrNull?.user;
                    await ref.read(apiClientProvider).requestPayout({
                      'amount': amount,
                      'method': method,
                      'phone': user?.phone ?? '',
                    });
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Demande envoyée, en attente de validation.')));
                      ref.invalidate(driverWalletProvider);
                      ref.invalidate(driverTransactionsProvider(_period));
                      ref.invalidate(driverPayoutsProvider);
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(friendlyError(e))));
                    }
                  }
                },
                child: const Text('Envoyer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList(
      AsyncValue<List<WalletTransaction>> transactionsAsync) {
    return transactionsAsync.when(
      data: (txs) {
        if (txs.isEmpty) return const Text('Aucun mouvement.');
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: txs.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final tx = txs[index];
            final color = tx.isRevenue
                ? Colors.blue
                : tx.type == 'debit'
                    ? Colors.red
                    : Colors.green;
            return ListTile(
              leading: Icon(
                tx.isRevenue
                    ? Icons.payments_outlined
                    : tx.type == 'debit'
                        ? Icons.remove_circle
                        : Icons.add_circle,
                color: color,
              ),
              title: Text(tx.isRevenue
                  ? 'Revenu hors solde'
                  : tx.description ?? tx.type),
              subtitle: Text(formatDate(tx.createdAt)),
              trailing: Text(
                '${tx.isCredit ? '+' : '-'} ${formatXof(tx.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            );
          },
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (e, __) => Text(friendlyError(e)),
    );
  }

  Widget _buildPayoutsSection(AsyncValue<List<PayoutRequest>> payoutsAsync) {
    return payoutsAsync.when(
      data: (payouts) {
        final recent = payouts.take(3).toList();
        if (recent.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Retraits',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...recent.map(
              (payout) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    _payoutStatusIcon(payout.status),
                    color: _payoutStatusColor(payout.status),
                  ),
                  title: Text(formatXof(payout.amount)),
                  subtitle: Text(
                    '${_payoutMethodLabel(payout.method)} · ${formatDate(payout.updatedAt ?? payout.createdAt)}',
                  ),
                  trailing: _StatusPill(
                    label: _payoutStatusLabel(payout.status),
                    color: _payoutStatusColor(payout.status),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _payoutMethodLabel(String method) {
  switch (method) {
    case 'orange_money':
      return 'Orange Money';
    case 'free_money':
      return 'Free Money';
    case 'wave':
      return 'Wave';
    default:
      return method.isEmpty ? '-' : method;
  }
}

String _payoutStatusLabel(String status) {
  switch (status) {
    case 'approved':
      return 'Validé';
    case 'rejected':
      return 'Rejeté';
    default:
      return 'En attente';
  }
}

Color _payoutStatusColor(String status) {
  switch (status) {
    case 'approved':
      return Colors.green;
    case 'rejected':
      return Colors.red;
    default:
      return Colors.orange;
  }
}

IconData _payoutStatusIcon(String status) {
  switch (status) {
    case 'approved':
      return Icons.check_circle;
    case 'rejected':
      return Icons.cancel;
    default:
      return Icons.hourglass_top;
  }
}

List<String> _monthOptions() {
  final now = DateTime.now();
  return List.generate(18, (index) {
    final date = DateTime(now.year, now.month - index);
    return _monthValue(date);
  });
}

String _monthValue(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}';
}

String _monthLabel(String value) {
  final parts = value.split('-');
  if (parts.length != 2) {
    return value;
  }
  final month = int.tryParse(parts[1]);
  final year = parts[0];
  const names = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];
  if (month == null || month < 1 || month > 12) {
    return value;
  }
  return '${names[month - 1]} $year';
}
