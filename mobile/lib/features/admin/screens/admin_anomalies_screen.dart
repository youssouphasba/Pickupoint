import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/admin_provider.dart';

class AdminAnomaliesScreen extends ConsumerWidget {
  const AdminAnomaliesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anomaliesAsync = ref.watch(adminAnomalyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Alertes d\'Anomalies')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminAnomalyProvider.future),
        child: anomaliesAsync.when(
          data: (anomalies) {
            if (anomalies.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                    SizedBox(height: 16),
                    Text('Aucune anomalie détectée.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: anomalies.length,
              itemBuilder: (context, index) {
                final a = anomalies[index];
                final isHigh = a['severity'] == 'high';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: isHigh ? Colors.red.shade200 : Colors.orange.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (isHigh ? Colors.red : Colors.orange).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isHigh ? Icons.gpp_maybe : Icons.warning_amber,
                                color: isHigh ? Colors.red : Colors.orange,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a['type'] == 'signal_lost' ? 'Signal Perdu' : 'Retard Critique',
                                    style: TextStyle(
                                      color: isHigh ? Colors.red : Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    a['driver_name'] ?? 'Livreur inconnu',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _showReassignDialog(context, ref, a['mission_id']),
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              label: const Text('Réassigner'),
                              style: TextButton.styleFrom(foregroundColor: Colors.blue),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Text(
                          a['description'],
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Mission: ${a['mission_id']}',
                              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey.shade500),
                            ),
                            TextButton(
                              onPressed: () => context.push('/admin/parcels/${a['mission_id']}/audit'),
                              child: const Text('Voir Audit', style: TextStyle(fontSize: 12)),
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
      ),
    );
  }

  void _showReassignDialog(BuildContext context, WidgetRef ref, String missionId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réassigner la mission'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'ID du nouveau livreur',
            hintText: 'drv_...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isEmpty) return;
              try {
                await ref.read(apiClientProvider).reassignMission(missionId, controller.text);
                if (context.mounted) {
                  Navigator.pop(context);
                  ref.invalidate(adminAnomalyProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mission réassignée !')),
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
