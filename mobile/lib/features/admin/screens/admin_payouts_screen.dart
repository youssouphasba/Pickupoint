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
          if (payouts.isEmpty) {
            return const Center(child: Text('Aucune demande en attente.'));
          }
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
                          Text(formatXof(p.amount),
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(p.method.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Vers: ${p.phoneNumber}'),
                      Text('Date: ${formatDate(p.createdAt)}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  _rejectPayout(context, ref, p.id),
                              child: const Text('Rejeter',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  _approvePayout(context, ref, p.id),
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

  Future<void> _rejectPayout(
      BuildContext context, WidgetRef ref, String id) async {
    final reason = await _askReason(
      context: context,
      title: 'Rejeter le retrait',
      helper:
          'Le montant sera recredite sur le solde disponible. Indique le motif de rejet.',
      confirmLabel: 'Rejeter',
      confirmColor: Colors.red,
    );
    if (reason == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.rejectPayout(id, reason: reason);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Retrait rejete.')));
      }
      ref.invalidate(adminPayoutsProvider);
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(adminReconciliationProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  Future<void> _approvePayout(
      BuildContext context, WidgetRef ref, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approuver le retrait ?'),
        content: const Text(
          'Confirme que le virement a bien ete execute avant de valider.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Approuver'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.approvePayout(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Le virement a ete marque comme effectue.')),
      );
      ref.invalidate(adminPayoutsProvider);
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(adminReconciliationProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<String?> _askReason({
    required BuildContext context,
    required String title,
    required String helper,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final controller = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(helper),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Motif',
                  hintText: 'Explique la decision admin',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final value = controller.text.trim();
                if (value.length < 3) {
                  setDialogState(
                    () =>
                        errorText = "Saisis un motif d'au moins 3 caracteres.",
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return result;
  }
}
