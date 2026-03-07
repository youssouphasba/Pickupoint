import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/admin_provider.dart';

// Provider express settings (admin)
final _expressSettingsProvider = FutureProvider<bool>((ref) async {
  try {
    final api = ref.watch(apiClientProvider);
    final res = await api.getAppSettings();
    final data = res.data as Map<String, dynamic>;
    return data['express_enabled'] as bool? ?? false;
  } catch (_) {
    return false;
  }
});

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminDashboardProvider.future),
        child: statsAsync.when(
          data: (stats) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Vue d\'ensemble', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                _buildStatsGrid(stats),
                const SizedBox(height: 32),
                const Text('Paramètres', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const _ExpressToggleTile(),
                const SizedBox(height: 24),
                const Text('Actions Rapides', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildActionButtons(context),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => Center(child: Text('Erreur: $e')),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(Map<String, dynamic> stats) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('Colis total', stats['total_parcels']?.toString() ?? '0', Colors.blue),
        _buildStatCard('En cours', stats['active_parcels']?.toString() ?? '0', Colors.orange),
        _buildStatCard('Retraits attente', stats['pending_payouts']?.toString() ?? '0', Colors.red),
        _buildStatCard('Relais actifs', stats['active_relays']?.toString() ?? '0', Colors.green),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        _buildActionButton(context, 'Gérer les Colis', Icons.inventory_2, '/admin/parcels'),
        _buildActionButton(context, 'Gestion Utilisateurs', Icons.people, '/admin/users'),
        _buildActionButton(context, 'Validation Relais', Icons.store, '/admin/relays'),
        _buildActionButton(context, 'Approuver Retraits', Icons.payments, '/admin/payouts'),
        _buildActionButton(context, 'Gestion Promotions', Icons.campaign, '/admin/promotions'),
        const Divider(height: 32),
        const Text('Contrôle Max', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildActionButton(context, 'Suivi Flotte Live', Icons.map, '/admin/fleet'),
        _buildActionButton(context, 'Journal d\'Audit Global', Icons.history, '/admin/audit-log'),
        _buildActionButton(context, 'Carte des Demandes', Icons.layers, '/admin/heatmap'),
        _buildActionButton(context, 'Alertes d\'Anomalies', Icons.gpp_maybe, '/admin/anomalies'),
        _buildActionButton(context, 'Documents Légaux', Icons.gavel, '/admin/legal'),
        _buildActionButton(context, 'Colis Stagnants', Icons.timer_off, '/admin/stale'),
        _buildActionButton(context, 'Suivi Finance COD', Icons.account_balance_wallet, '/admin/finance'),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context, String label, IconData icon, String route) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        tileColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () => context.push(route),
      ),
    );
  }
}

// ── Express toggle isolé (ConsumerStatefulWidget pour état optimiste) ─────

class _ExpressToggleTile extends ConsumerStatefulWidget {
  const _ExpressToggleTile();

  @override
  ConsumerState<_ExpressToggleTile> createState() => _ExpressToggleTileState();
}

class _ExpressToggleTileState extends ConsumerState<_ExpressToggleTile> {
  bool? _optimistic; // surcharge locale pendant la requête
  bool  _loading = false;

  Future<void> _toggle(bool current) async {
    final next = !current;
    setState(() { _optimistic = next; _loading = true; });
    try {
      await ref.read(apiClientProvider).setExpressEnabled(next);
      ref.invalidate(_expressSettingsProvider);
    } catch (e) {
      setState(() => _optimistic = current); // rollback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(_expressSettingsProvider);

    return asyncVal.when(
      data: (serverVal) {
        final enabled = _optimistic ?? serverVal;
        return Card(
          child: SwitchListTile(
            title: const Text('Livraison Express', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(
              enabled
                  ? 'Activée — visible par les clients (+30 %)'
                  : 'Désactivée — masquée pour les clients',
              style: TextStyle(color: enabled ? const Color(0xFFFF6B00) : Colors.grey, fontSize: 13),
            ),
            secondary: _loading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.bolt, color: enabled ? const Color(0xFFFF6B00) : Colors.grey),
            value: enabled,
            onChanged: _loading ? null : (_) => _toggle(enabled),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
