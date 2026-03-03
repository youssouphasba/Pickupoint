import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/driver_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../relay/providers/relay_provider.dart'; // Pour réutiliser transactions
import '../../../shared/widgets/loading_button.dart';

class DriverWalletScreen extends ConsumerWidget {
  const DriverWalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(driverWalletProvider);
    final transactionsAsync = ref.watch(relayTransactionsProvider); // On réutilise le même mécanisme

    return Scaffold(
      appBar: AppBar(title: const Text('Mes Commissions')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.refresh(driverWalletProvider);
          ref.refresh(relayTransactionsProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _buildBalanceCard(context, walletAsync),
              const SizedBox(height: 32),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Historique des gains', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Décaisser mes gains',
              color: Colors.white,
              onPressed: () {},
            ),
          ],
        ),
      ),
      loading: () => const CircularProgressIndicator(),
      error: (e, __) => Text('Erreur: $e'),
    );
  }

  Widget _buildTransactionsList(AsyncValue transactionsAsync) {
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
              title: Text(tx.description),
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
