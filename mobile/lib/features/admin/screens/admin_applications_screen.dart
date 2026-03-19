import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/utils/phone_utils.dart';
import '../../../core/auth/auth_provider.dart';

// Provider local (pas besoin de le déplacer — écran unique)
final _applicationsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, status) async {
    final api = ref.watch(apiClientProvider);
    final res = await api.getAdminApplications(status: status);
    final data = res.data as Map<String, dynamic>;
    return (data['applications'] as List? ?? []).cast<Map<String, dynamic>>();
  },
);

class AdminApplicationsScreen extends ConsumerStatefulWidget {
  const AdminApplicationsScreen({super.key});

  @override
  ConsumerState<AdminApplicationsScreen> createState() =>
      _AdminApplicationsScreenState();
}

class _AdminApplicationsScreenState
    extends ConsumerState<AdminApplicationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Candidatures Partenaires'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'En attente'),
            Tab(text: 'Approuvées'),
            Tab(text: 'Rejetées'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _ApplicationsList(status: 'pending'),
          _ApplicationsList(status: 'approved'),
          _ApplicationsList(status: 'rejected'),
        ],
      ),
    );
  }
}

// ── Liste des candidatures ────────────────────────────────────────────────────
class _ApplicationsList extends ConsumerWidget {
  const _ApplicationsList({required this.status});
  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsAsync = ref.watch(_applicationsProvider(status));

    return appsAsync.when(
      data: (apps) {
        if (apps.isEmpty) {
          return Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                status == 'pending'
                    ? 'Aucune candidature en attente'
                    : status == 'approved'
                        ? 'Aucune candidature approuvée'
                        : 'Aucune candidature rejetée',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ]),
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.refresh(_applicationsProvider(status).future),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: apps.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ApplicationCard(app: apps[i]),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => Center(child: Text('Erreur: $e')),
    );
  }
}

// ── Carte candidature ─────────────────────────────────────────────────────────
class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.app});
  final Map<String, dynamic> app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = app['type'] as String;
    final status = app['status'] as String;
    final data = app['data'] as Map<String, dynamic>? ?? {};
    final phone = app['user_phone'] as String? ?? '—';
    final name = app['user_name'] as String? ?? phone;
    final appId = app['application_id'] as String;

    final isDriver = type == 'driver';
    final color = isDriver ? Colors.blue : Colors.orange;
    final icon = isDriver ? Icons.delivery_dining : Icons.store;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // En-tête type + statut
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              isDriver ? 'Candidature Livreur' : 'Candidature Point Relais',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
            const Spacer(),
            _StatusBadge(status: status),
          ]),
          const Divider(height: 20),
          // Infos candidat
          _row(Icons.person, 'Candidat', name),
          _row(Icons.phone, 'Téléphone', maskPhone(phone)),
          if (isDriver) ...[
            _row(Icons.badge, 'CNI', data['id_card_number'] ?? '—'),
            _row(Icons.credit_card, 'Permis', data['license_number'] ?? '—'),
            _row(Icons.directions_car, 'Véhicule', data['vehicle_type'] ?? '—'),
          ] else ...[
            _row(Icons.storefront, 'Boutique', data['business_name'] ?? '—'),
            _row(Icons.location_on, 'Adresse',
                '${data['address_label'] ?? ''}, ${data['city'] ?? ''}'),
            if (data['geopin'] != null)
              _row(Icons.gps_fixed, 'Position GPS',
                  '${data['geopin']['lat'].toStringAsFixed(5)}, ${data['geopin']['lng'].toStringAsFixed(5)}'),
            _row(Icons.access_time, 'Horaires', data['opening_hours'] ?? '—'),
            if (data['business_reg'] != null)
              _row(Icons.business, 'Registre Commerce', data['business_reg']),
          ],
          if ((data['message'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '"${data['message']}"',
                style:
                    const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ),
          ],
          if (app['admin_notes'] != null) ...[
            const SizedBox(height: 8),
            Text('Note admin : ${app['admin_notes']}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          // Actions (seulement si en attente)
          if (status == 'pending') ...[
            const SizedBox(height: 14),
            Row(children: [
              // Appeler
              OutlinedButton.icon(
                onPressed: () => _call(context, phone),
                icon: const Icon(Icons.phone, size: 16),
                label: const Text('Appeler'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
              ),
              const SizedBox(width: 8),
              // Rejeter
              OutlinedButton.icon(
                onPressed: () => _showRejectDialog(context, ref, appId),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Rejeter'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
              const Spacer(),
              // Approuver
              ElevatedButton.icon(
                onPressed: () => _showApproveDialog(context, ref, appId, type),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Approuver'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ),
      ]),
    );
  }

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Impossible d’ouvrir le composeur téléphonique')),
    );
  }

  void _showApproveDialog(
      BuildContext ctx, WidgetRef ref, String id, String type) {
    final notesCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (context) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          Text(type == 'driver' ? 'Approuver Livreur' : 'Approuver Relais'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            type == 'driver'
                ? 'L\'utilisateur deviendra Livreur. Il aura accès au dashboard livreur.'
                : 'L\'utilisateur deviendra Agent Relais. Un point relais sera créé automatiquement.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Note interne (optionnel)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final api = ref.read(apiClientProvider);
                await api.approveApplication(id,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim());
                ref.invalidate(_applicationsProvider('pending'));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('Candidature approuvée ✅'),
                        backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text('Erreur: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext ctx, WidgetRef ref, String id) {
    final notesCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (context) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.cancel, color: Colors.red),
          SizedBox(width: 8),
          Text('Rejeter la candidature'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Indiquez la raison pour informer le candidat.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Raison du rejet (optionnel)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final api = ref.read(apiClientProvider);
                await api.rejectApplication(id,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim());
                ref.invalidate(_applicationsProvider('pending'));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('Candidature rejetée'),
                        backgroundColor: Colors.orange),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text('Erreur: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'approved' => ('Approuvé', Colors.green),
      'rejected' => ('Rejeté', Colors.red),
      _ => ('En attente', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
