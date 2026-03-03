import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_client.dart';

class AdminFinanceScreen extends ConsumerWidget {
  const AdminFinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeAsync = ref.watch(adminFinanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi de la Trésorerie (COD)'),
      ),
      body: financeAsync.when(
        data: (fin) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: fin.length,
          itemBuilder: (context, index) {
            final e = fin[index];
            final amount = (e['cod_balance'] as num).toDouble();
            
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: amount > 0 ? Colors.orange.shade50 : Colors.grey.shade50,
                  child: Icon(Icons.person, color: amount > 0 ? Colors.orange : Colors.grey),
                ),
                title: Text(e['name'] ?? 'Livreur inconnu', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('ID: ${e['user_id']}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${amount.toInt()} XOF',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 16,
                        color: amount > 0 ? Colors.red.shade700 : Colors.green.shade700
                      ),
                    ),
                    if (amount > 0)
                      const Text('À encaisser', style: TextStyle(fontSize: 10, color: Colors.orange)),
                  ],
                ),
                onTap: amount > 0 ? () => _showSettleDialog(context, ref, e['user_id'], e['name'] ?? 'Livreur', amount) : null,
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  void _showSettleDialog(BuildContext context, WidgetRef ref, String driverId, String name, double amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer l\'encaissement'),
        content: Text('Voulez-vous marquer les $amount XOF collectés par $name comme encaissés ?\n\nCela remettra son solde COD à zéro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(apiClientProvider).settleCod(driverId);
                if (context.mounted) {
                  Navigator.pop(context);
                  ref.invalidate(adminFinanceProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Trésorerie soldée avec succès !')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
