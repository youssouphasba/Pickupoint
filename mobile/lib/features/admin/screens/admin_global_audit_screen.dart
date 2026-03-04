import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/utils/date_format.dart';
import '../../../core/auth/auth_provider.dart';

final adminAuditLogProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminAuditLog();
  final data = res.data as Map<String, dynamic>;
  return data['events'] as List? ?? [];
});

class AdminGlobalAuditScreen extends ConsumerWidget {
  const AdminGlobalAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(adminAuditLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal d\'Audit Global'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminAuditLogProvider),
          ),
        ],
      ),
      body: auditAsync.when(
        data: (events) {
          if (events.isEmpty) {
            return const Center(child: Text('Aucun événement enregistré.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final ev = events[i] as Map<String, dynamic>;
              final date = ev['created_at'] != null ? formatDate(ev['created_at']) : "---";
              final type = ev['event_type'] ?? "UNKNOWN";
              final actor = ev['actor_name'] ?? ev['actor_role'] ?? "Système";
              final tracking = ev['tracking_code'] ?? "---";
              
              return ListTile(
                leading: _getEventIcon(type),
                title: Text(type.replaceAll('_', ' ')),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Acteur: $actor'),
                    Text('Colis: $tracking'),
                    Text('Date: $date', style: const TextStyle(fontSize: 11)),
                  ],
                ),
                isThreeLine: true,
                trailing: ev['notes'] != null ? IconButton(
                  icon: const Icon(Icons.notes, size: 18),
                  onPressed: () => _showNotes(context, ev['notes']),
                ) : null,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  void _showNotes(BuildContext context, String notes) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notes d\'événement'),
        content: Text(notes),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Widget _getEventIcon(String type) {
    if (type.contains('CREATED')) return const Icon(Icons.add_box, color: Colors.blue);
    if (type.contains('SCAN')) return const Icon(Icons.qr_code_scanner, color: Colors.purple);
    if (type.contains('ARRIVE')) return const Icon(Icons.store, color: Colors.orange);
    if (type.contains('DELIVERED')) return const Icon(Icons.check_circle, color: Colors.green);
    if (type.contains('FAIL')) return const Icon(Icons.error_outline, color: Colors.red);
    return const Icon(Icons.history, color: Colors.grey);
  }
}
