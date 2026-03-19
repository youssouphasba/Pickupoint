import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/widgets/loading_button.dart';
import '../providers/relay_provider.dart';

class RelayWalletScreen extends ConsumerStatefulWidget {
  const RelayWalletScreen({super.key});

  @override
  ConsumerState<RelayWalletScreen> createState() => _RelayWalletScreenState();
}

class _RelayWalletScreenState extends ConsumerState<RelayWalletScreen> {
  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(relayWalletProvider);
    final transactionsAsync = ref.watch(relayTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes Gains')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(relayWalletProvider.future),
          ref.refresh(relayTransactionsProvider.future),
        ]),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBalanceCard(context, walletAsync),
              const SizedBox(height: 32),
              const Text(
                'Dernieres transactions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildTransactionsList(transactionsAsync),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, AsyncValue walletAsync) {
    return walletAsync.when(
      data: (wallet) => Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text(
              'Solde actuel',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              formatXof(wallet.balance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (wallet.pendingBalance > 0) ...[
              const SizedBox(height: 4),
              Text(
                'En attente : ${formatXof(wallet.pendingBalance)}',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Demander un retrait',
              color: Colors.white,
              onPressed:
                  wallet.balance > 0 ? () => _showPayoutDialog(context) : null,
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => Text('Erreur wallet: $e'),
    );
  }

  Widget _buildTransactionsList(AsyncValue transactionsAsync) {
    return transactionsAsync.when(
      data: (txs) {
        if (txs.isEmpty) {
          return const Text('Aucune transaction.');
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: txs.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final tx = txs[index];
            final isCredit = tx.type == 'credit';
            return ListTile(
              leading: Icon(
                isCredit ? Icons.add_circle : Icons.remove_circle,
                color: isCredit ? Colors.green : Colors.red,
              ),
              title: Text(tx.description ?? tx.type),
              subtitle: Text(formatDate(tx.createdAt)),
              trailing: Text(
                '${isCredit ? '+' : '-'}${formatXof(tx.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isCredit ? Colors.green : Colors.red,
                ),
              ),
            );
          },
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (e, __) => Text('Erreur tx: $e'),
    );
  }

  void _showPayoutDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    String method = 'wave';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Demande de retrait'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Montant (XOF)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(
                  labelText: 'Methode',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'wave', child: Text('Wave')),
                  DropdownMenuItem(
                    value: 'orange_money',
                    child: Text('Orange Money'),
                  ),
                  DropdownMenuItem(
                    value: 'free_money',
                    child: Text('Free Money'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => method = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim());
                if (amount == null || amount <= 0) {
                  return;
                }
                try {
                  final user = ref.read(authProvider).valueOrNull?.user;
                  await ref.read(apiClientProvider).requestPayout({
                    'amount': amount,
                    'method': method,
                    'phone': user?.phone ?? '',
                  });
                  if (!ctx.mounted) {
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Demande envoyee, en attente de validation.',
                      ),
                    ),
                  );
                  ref.invalidate(relayWalletProvider);
                  ref.invalidate(relayTransactionsProvider);
                } catch (e) {
                  if (!ctx.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e')),
                  );
                }
              },
              child: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
  }
}
