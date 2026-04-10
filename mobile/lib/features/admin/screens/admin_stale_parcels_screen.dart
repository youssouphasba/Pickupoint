import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/admin_provider.dart';
import '../../../shared/utils/error_utils.dart';

class AdminStaleParcelsScreen extends ConsumerWidget {
  const AdminStaleParcelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staleAsync = ref.watch(adminStaleParcelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Colis Stagnants (> 7j)'),
      ),
      body: staleAsync.when(
        data: (stale) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: stale.length,
          itemBuilder: (context, index) {
            final p = stale[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.timer_off, color: Colors.orange),
                      title: Text('Colis: ${p['tracking_code']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Dernière MAJ: ${p['updated_at']}\nStatut: ${p['status']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.history_edu, color: Colors.blue),
                        onPressed: () => context.push('/admin/parcels/${p['parcel_id']}/audit'),
                        tooltip: 'Voir Audit',
                      ),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _showOverrideDialog(context, ref, p['parcel_id']),
                          icon: const Icon(Icons.edit_note, size: 18),
                          label: const Text('Forcer Statut'),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text(friendlyError(e))),
      ),
    );
  }

  void _showOverrideDialog(BuildContext context, WidgetRef ref, String parcelId) {
    String? selectedStatus;
    final notesController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Forcer le statut'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedStatus,
                decoration: const InputDecoration(labelText: 'Nouveau statut'),
                items: const [
                  DropdownMenuItem(value: 'delivered', child: Text('Livré (Force)')),
                  DropdownMenuItem(value: 'returned', child: Text('Retourné')),
                  DropdownMenuItem(value: 'cancelled', child: Text('Annulé')),
                ],
                onChanged: (v) => setState(() => selectedStatus = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Motif (obligatoire)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (selectedStatus == null || notesController.text.isEmpty) return;
                try {
                  await ref.read(apiClientProvider).overrideParcelStatus(
                    parcelId, 
                    selectedStatus!, 
                    notesController.text
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ref.invalidate(adminStaleParcelsProvider);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Statut forcé avec succès !')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                  }
                }
              },
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
  }
}
