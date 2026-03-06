import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';

class AdminPayoutsScreen extends ConsumerWidget {
  const AdminPayoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payoutsAsync = ref.watch(adminPayoutsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Validation Retraits')),
      body: payoutsAsync.when(
        data: (payouts) {
          if (payouts.isEmpty) return const Center(child: Text('Aucune demande en attente.'));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: payouts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final p = payouts[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(formatXof(p.amount), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                            child: Text(p.method.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Vers: ${p.phoneNumber}'),
                      Text('Date: ${formatDate(p.createdAt)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _rejectPayout(context, ref, p.id),
                              child: const Text('Rejeter', style: TextStyle(color: Colors.red)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _approvePayout(context, ref, p.id),
                              child: const Text('Approuver'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  Future<void> _rejectPayout(BuildContext context, WidgetRef ref, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rejeter le retrait ?'),
        content: const Text('Le montant sera recrédité sur le solde disponible de l\'utilisateur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rejeter', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.rejectPayout(id);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retrait rejeté.')));
      ref.invalidate(adminPayoutsProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _approvePayout(BuildContext context, WidgetRef ref, String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.approvePayout(id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le virement a été marqué comme effectué.')));
      ref.invalidate(adminPayoutsProvider);
      ref.refresh(adminDashboardProvider);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }
}
