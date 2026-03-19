import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';

// Provider dynamique pour l'audit d'un colis spécifique
final adminParcelAuditProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getParcelAudit(id);
  return res.data as Map<String, dynamic>;
});

class AdminParcelAuditScreen extends ConsumerWidget {
  final String id;
  const AdminParcelAuditScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(adminParcelAuditProvider(id));

    return Scaffold(
      appBar: AppBar(title: const Text('Audit Trail du Colis')),
      body: auditAsync.when(
        data: (data) {
          final parcel = data['parcel'];
          final timeline = data['timeline'] as List;
          final missions = data['missions'] as List;
          final financial =
              data['financial_summary'] as Map<String, dynamic>? ?? const {};

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Infos Colis'),
                Text('Code: ${parcel['tracking_code']}'),
                Text('Statut actuel: ${parcel['status']}'),
                Text(
                    'Expéditeur: ${parcel['sender_name'] ?? parcel['sender_user_id'] ?? "Inconnu"}'),
                if (parcel['origin_relay_name'] != null)
                  Text('Relais Origine: ${parcel['origin_relay_name']}'),
                if (parcel['destination_relay_name'] != null)
                  Text(
                      'Relais Destination: ${parcel['destination_relay_name']}'),
                Text(
                    'Destinataire: ${parcel['recipient_name']} (${parcel['recipient_phone']})'),
                const Divider(height: 32),
                _buildSectionTitle('Paiement & Repricing'),
                Text(
                    'Statut paiement: ${financial['payment_status'] ?? "inconnu"}'),
                if (financial['payment_method'] != null)
                  Text('Méthode: ${financial['payment_method']}'),
                if (financial['who_pays'] != null)
                  Text('Payeur: ${financial['who_pays']}'),
                if (financial['payment_override'] == true)
                  Text(
                      'Override: ${financial['payment_override_reason'] ?? "oui"}'),
                if ((financial['address_change_surcharge_xof'] as num?) !=
                        null &&
                    (financial['address_change_surcharge_xof'] as num) > 0)
                  Text(
                      'Surcoût adresse: ${financial['address_change_surcharge_xof']} XOF'),
                if ((financial['driver_bonus_xof'] as num?) != null &&
                    (financial['driver_bonus_xof'] as num) > 0)
                  Text('Bonus livreur: ${financial['driver_bonus_xof']} XOF'),
                const Divider(height: 32),
                _buildSectionTitle('Timeline des Événements'),
                ...timeline.map((e) => ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(e['event_type']),
                      subtitle: Text('${e['timestamp'] ?? e['created_at']}\n'
                          'Acteur: ${e['actor_name'] ?? e['actor_id'] ?? e['actor_role'] ?? "Système"}\n'
                          'Notes: ${e['notes'] ?? ""}'),
                    )),
                const Divider(height: 32),
                _buildSectionTitle('Missions & GPS (Dispute Center)'),
                if (missions.isEmpty) const Text('Aucune mission trouvée.'),
                ...missions.map((m) {
                  final canReassign = const [
                    'pending',
                    'assigned',
                    'incident_reported'
                  ].contains(m['status']);
                  return Card(
                    child: ExpansionTile(
                      title: Text('Mission: ${m['mission_id']}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Livreur: ${m['driver_name'] ?? m['driver_id']}'),
                          Text('Status: ${m['status']}'),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.swap_horiz, color: Colors.blue),
                        tooltip: 'Réassigner',
                        onPressed: canReassign
                            ? () => _showReassignDialog(
                                context, ref, m['mission_id'])
                            : null,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Traces GPS: ${(m['gps_trail'] as List).length} points enregistrés.'),
                              if (!canReassign)
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Réassignation directe indisponible pour cette mission.',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  void _showReassignDialog(
      BuildContext context, WidgetRef ref, String missionId) {
    final driverController = TextEditingController();
    final reasonController = TextEditingController(
        text: 'Réassignation manuelle depuis l’audit colis');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réassigner la mission'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: driverController,
              decoration:
                  const InputDecoration(labelText: 'ID du nouveau livreur'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Motif'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              if (driverController.text.trim().isEmpty ||
                  reasonController.text.trim().isEmpty) {
                return;
              }
              try {
                await ref.read(apiClientProvider).reassignMission(
                      missionId,
                      driverController.text.trim(),
                      reason: reasonController.text.trim(),
                    );
                if (!context.mounted) return;
                Navigator.pop(context);
                ref.invalidate(adminParcelAuditProvider(id));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mission réassignée.')));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Erreur: $e')));
              }
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}
