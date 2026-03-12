import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/relay_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/widgets/loading_button.dart';

class RelayWalletScreen extends ConsumerWidget {
  const RelayWalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              const Text('Dernières transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            const Text('Solde actuel', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              formatXof(wallet.balance),
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Demander un retrait',
              color: Colors.white,
              onPressed: () => _showPayoutSheet(context),
              // Texte noir sur blanc pour white color
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
        if (txs.isEmpty) return const Text('Aucune transaction.');
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
              title: Text(tx.description),
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

  void _showPayoutSheet(BuildContext context) {
    // Liste des méthodes de retrait
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Demander un retrait', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Choisissez votre méthode de paiement préférée.'),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.wallet, color: Colors.blue),
                title: const Text('Wave / Orange Money'),
                subtitle: const Text('Traitement en 24h'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fonctionnalité de retrait bientôt disponible !')));
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
