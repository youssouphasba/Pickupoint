import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/driver_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../../core/models/wallet.dart';
import '../../../shared/widgets/loading_button.dart';

final driverTransactionsProvider = FutureProvider.family<List<WalletTransaction>, String?>((ref, period) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getTransactions(period: period);
  final data = res.data as Map<String, dynamic>;
  return (data['transactions'] as List? ?? [])
      .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
      .toList();
});

class DriverWalletScreen extends ConsumerStatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  ConsumerState<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends ConsumerState<DriverWalletScreen> {
  String? _period; // null = tout, 'week', 'month'

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(driverWalletProvider);
    final transactionsAsync = ref.watch(driverTransactionsProvider(_period));

    return Scaffold(
      appBar: AppBar(title: const Text('Mes Commissions')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(driverWalletProvider.future),
          ref.refresh(driverTransactionsProvider(_period).future),
        ]),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _buildBalanceCard(context, walletAsync),
              const SizedBox(height: 32),
              Row(
                children: [
                  const Expanded(
                    child: Text('Historique des gains', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  _buildPeriodFilter(),
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
    return SegmentedButton<String?>(
      segments: const [
        ButtonSegment(value: null, label: Text('Tout')),
        ButtonSegment(value: 'week', label: Text('7j')),
        ButtonSegment(value: 'month', label: Text('30j')),
      ],
      selected: {_period},
      onSelectionChanged: (v) => setState(() => _period = v.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: Colors.blue.shade100,
        textStyle: const TextStyle(fontSize: 12),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, AsyncValue walletAsync) {
    return walletAsync.when(
      data: (wallet) => Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.blue.shade800, Colors.blue.shade500]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text('Cagnotte Livreur', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              formatXof(wallet.balance),
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            if (wallet.pendingBalance > 0) ...[
              const SizedBox(height: 4),
              Text('En attente : ${formatXof(wallet.pendingBalance)}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Décaisser mes gains',
              color: Colors.white,
              onPressed: wallet.balance > 0 ? () => _showPayoutDialog(context) : null,
            ),
          ],
        ),
      ),
      loading: () => const CircularProgressIndicator(),
      error: (e, __) => Text('Erreur: $e'),
    );
  }

  void _showPayoutDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    String method = 'wave';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Demande de retrait'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant (XOF)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Méthode', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'wave', child: Text('Wave')),
                  DropdownMenuItem(value: 'orange_money', child: Text('Orange Money')),
                  DropdownMenuItem(value: 'free_money', child: Text('Free Money')),
                ],
                onChanged: (v) => setState(() => method = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demande envoyée, en attente de validation.')));
                      ref.invalidate(driverWalletProvider);
                    }
                  } catch (e) {
                    if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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

  Widget _buildTransactionsList(AsyncValue<List<WalletTransaction>> transactionsAsync) {
    return transactionsAsync.when(
      data: (txs) {
        if (txs.isEmpty) return const Text('Aucun gain enregistré.');
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: txs.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final tx = txs[index];
            return ListTile(
              leading: const Icon(Icons.add_circle, color: Colors.green),
              title: Text(tx.description ?? tx.type),
              subtitle: Text(formatDate(tx.createdAt)),
              trailing: Text('+ ${formatXof(tx.amount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            );
          },
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (e, __) => Text('Erreur: $e'),
    );
  }
}
