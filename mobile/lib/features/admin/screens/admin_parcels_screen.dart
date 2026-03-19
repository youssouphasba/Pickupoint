import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/admin_provider.dart';
import '../../../shared/widgets/parcel_status_badge.dart';

class AdminParcelsScreen extends ConsumerWidget {
  const AdminParcelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parcelsAsync = ref.watch(adminParcelsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gestion des Colis')),
      body: parcelsAsync.when(
        data: (parcels) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: parcels.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final p = parcels[index];
            return ListTile(
              title: Text('Code: ${p.trackingCode}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('De: ${p.senderId} -> Dest: ${p.recipientName}'),
              trailing: ParcelStatusBadge(status: p.status),
              onTap: () => _showStatusActionSheet(context, ref, p.id),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  void _showStatusActionSheet(BuildContext context, WidgetRef ref, String id) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Actions sur le colis',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.blue),
              title: const Text('Voir l\'audit complet (Dispute Center)'),
              onTap: () {
                Navigator.pop(context);
                context.push('/admin/parcels/$id/audit');
              },
            ),
            const Divider(),
            const Text('Forcer le statut',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _buildStatusChip(context, ref, id, 'cancelled', Colors.red),
                _buildStatusChip(context, ref, id, 'returned', Colors.grey),
                _buildStatusChip(context, ref, id, 'disputed', Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, WidgetRef ref, String id,
      String status, Color color) {
    return ActionChip(
      label: Text(status.toUpperCase(),
          style: const TextStyle(color: Colors.white, fontSize: 10)),
      backgroundColor: color,
      onPressed: () => _showForceStatusDialog(context, ref, id, status),
    );
  }

  void _showForceStatusDialog(
      BuildContext context, WidgetRef ref, String id, String status) {
    final notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Forcer le statut ${status.toUpperCase()}'),
        content: TextField(
          controller: notesController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motif obligatoire',
            hintText: 'Explique la raison de cette intervention admin',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final notes = notesController.text.trim();
              if (notes.isEmpty) return;
              try {
                await ref
                    .read(apiClientProvider)
                    .forceParcelStatus(id, status, notes: notes);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                Navigator.pop(context);
                ref.invalidate(adminParcelsProvider);
                ref.invalidate(adminDashboardProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Statut $status forcé.')),
                );
              } catch (e) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Erreur: $e')),
                );
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }
}
