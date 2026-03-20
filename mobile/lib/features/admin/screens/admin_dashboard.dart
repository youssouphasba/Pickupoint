import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../providers/admin_provider.dart';

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

final _referralSettingsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getReferralAdminStats();
  final data = Map<String, dynamic>.from(
    res.data as Map<String, dynamic>? ?? const {},
  );
  return {
    'referral_enabled': data['referral_enabled'] as bool? ?? true,
    'referral_bonus_xof': data['referral_bonus_xof'] as num? ?? 500,
    'referral_sponsor_bonus_xof':
        data['referral_sponsor_bonus_xof'] as num? ?? 500,
    'referral_referred_bonus_xof':
        data['referral_referred_bonus_xof'] as num? ?? 500,
    'referral_share_base_url':
        data['referral_share_base_url']?.toString() ?? '',
    'effective_referral_share_base_url':
        data['effective_referral_share_base_url']?.toString() ??
            data['referral_share_base_url']?.toString() ??
            '',
    'referral_allowed_roles': List<String>.from(
      data['referral_allowed_roles'] as List? ?? const <String>[],
    ),
    'referral_sponsor_allowed_roles': List<String>.from(
      data['referral_sponsor_allowed_roles'] as List? ??
          data['referral_allowed_roles'] as List? ??
          const <String>[],
    ),
    'referral_referred_allowed_roles': List<String>.from(
      data['referral_referred_allowed_roles'] as List? ??
          data['referral_allowed_roles'] as List? ??
          const <String>[],
    ),
    'referral_apply_metric': data['referral_apply_metric']?.toString() ?? '',
    'referral_apply_max_count': data['referral_apply_max_count'] as num? ?? 0,
    'referral_apply_rule': data['referral_apply_rule']?.toString() ?? '',
    'referral_reward_metric': data['referral_reward_metric']?.toString() ?? '',
    'referral_reward_count': data['referral_reward_count'] as num? ?? 1,
    'referral_reward_rule': data['referral_reward_rule']?.toString() ?? '',
    'referral_metric_options': List<Map<String, dynamic>>.from(
      (data['referral_metric_options'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map)),
    ),
    'sample_referral_url': data['sample_referral_url']?.toString() ?? '',
    'sample_share_message': data['sample_share_message']?.toString() ?? '',
    'users_with_code': data['users_with_code'] as num? ?? 0,
    'effective_enabled_users': data['effective_enabled_users'] as num? ?? 0,
    'override_enabled_users': data['override_enabled_users'] as num? ?? 0,
    'override_disabled_users': data['override_disabled_users'] as num? ?? 0,
    'referred_users': data['referred_users'] as num? ?? 0,
    'rewarded_users': data['rewarded_users'] as num? ?? 0,
    'pending_reward_users': data['pending_reward_users'] as num? ?? 0,
    'stats_by_role': Map<String, dynamic>.from(
      data['stats_by_role'] as Map? ?? const {},
    ),
  };
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
        onRefresh: () => Future.wait([
          ref.refresh(adminDashboardProvider.future),
          ref.refresh(_expressSettingsProvider.future),
          ref.refresh(_referralSettingsProvider.future),
        ]),
        child: statsAsync.when(
          data: (stats) => _DashboardBody(stats: stats),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => Center(child: Text('Erreur: $e')),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final priorities = _buildPriorities();
    final operations = _buildOperations();
    final shortcuts = _buildShortcuts();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(context),
          const SizedBox(height: 24),
          const Text(
            'Vue d\'ensemble',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _MetricGrid(items: [
            _MetricCardData(
              label: 'Colis du jour',
              value: _intValue(stats['parcels_today']).toString(),
              helper: '${_intValue(stats['total_parcels'])} au total',
              color: Colors.blue,
              icon: Icons.today,
            ),
            _MetricCardData(
              label: 'Colis en cours',
              value: _intValue(stats['active_parcels']).toString(),
              helper:
                  '${_intValue(stats['payment_blocked_parcels'])} bloques paiement',
              color: Colors.orange,
              icon: Icons.local_shipping,
            ),
            _MetricCardData(
              label: 'Retraits attente',
              value: _intValue(stats['pending_payouts']).toString(),
              helper: '${_intValue(stats['signal_lost'])} GPS perdus',
              color: Colors.red,
              icon: Icons.payments_outlined,
            ),
            _MetricCardData(
              label: 'Chiffre d\'affaires',
              value: formatXof(_doubleValue(stats['revenue_xof'])),
              helper:
                  'Taux de succes ${_doubleValue(stats['success_rate']).toStringAsFixed(1)} %',
              color: Colors.green,
              icon: Icons.trending_up,
            ),
          ]),
          const SizedBox(height: 32),
          const Text(
            'Priorites',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (priorities.isEmpty)
            const _InfoCard(
              title: 'Rien de critique pour le moment',
              subtitle:
                  'Aucune alerte urgente n\'est remontee par les donnees temps reel.',
              icon: Icons.verified_outlined,
              color: Colors.green,
            )
          else
            Column(
              children: priorities
                  .map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PriorityTile(item: item),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 32),
          const Text(
            'Reseau live',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _MetricGrid(items: operations),
          const SizedBox(height: 32),
          const Text(
            'Parametres',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const _ExpressToggleTile(),
          const SizedBox(height: 12),
          const _ReferralSettingsTile(),
          const SizedBox(height: 32),
          const Text(
            'Acces rapides',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: shortcuts.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.28,
            ),
            itemBuilder: (context, index) {
              final item = shortcuts[index];
              return _ShortcutCard(item: item);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final active = _intValue(stats['active_parcels']);
    final liveFleet = _intValue(stats['live_fleet']);
    final blocked = _intValue(stats['payment_blocked_parcels']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade900,
            Colors.blue.shade600,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cockpit operationnel',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$active colis en cours, $liveFleet positions live et $blocked remises bloquees par paiement.',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroBadge(
                label: '${_intValue(stats['signal_lost'])} GPS perdus',
                icon: Icons.gps_off,
              ),
              _HeroBadge(
                label:
                    '${_intValue(stats['critical_delay'])} retards critiques',
                icon: Icons.warning_amber_rounded,
              ),
              _HeroBadge(
                label: '${_intValue(stats['stale_parcels'])} colis stagnants',
                icon: Icons.inventory_2_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_PriorityItem> _buildPriorities() {
    final items = <_PriorityItem>[
      _PriorityItem(
        title: 'Paiements bloquants',
        subtitle: 'Des remises finales sont actuellement bloquees.',
        count: _intValue(stats['payment_blocked_parcels']),
        color: Colors.red,
        icon: Icons.lock_clock_outlined,
        route: '/admin/parcels',
      ),
      _PriorityItem(
        title: 'Retraits en attente',
        subtitle: 'Demandes de payout a valider par l\'equipe admin.',
        count: _intValue(stats['pending_payouts']),
        color: Colors.deepOrange,
        icon: Icons.account_balance_wallet_outlined,
        route: '/admin/payouts',
      ),
      _PriorityItem(
        title: 'Perte de signal GPS',
        subtitle: 'Livreurs actifs sans position recente.',
        count: _intValue(stats['signal_lost']),
        color: Colors.red.shade700,
        icon: Icons.gps_off_outlined,
        route: '/admin/anomalies',
      ),
      _PriorityItem(
        title: 'Retards critiques',
        subtitle: 'Missions en retard notable a investiguer.',
        count: _intValue(stats['critical_delay']),
        color: Colors.amber.shade800,
        icon: Icons.timer_outlined,
        route: '/admin/anomalies',
      ),
      _PriorityItem(
        title: 'Colis stagnants',
        subtitle: 'Colis en relais depuis plus de 7 jours.',
        count: _intValue(stats['stale_parcels']),
        color: Colors.brown,
        icon: Icons.hourglass_bottom_outlined,
        route: '/admin/stale',
      ),
    ];

    return items.where((item) => item.count > 0).toList();
  }

  List<_MetricCardData> _buildOperations() {
    return [
      _MetricCardData(
        label: 'Flotte live',
        value: _intValue(stats['live_fleet']).toString(),
        helper: 'Positions recues depuis moins d\'1h',
        color: Colors.indigo,
        icon: Icons.map_outlined,
      ),
      _MetricCardData(
        label: 'Livreurs actifs',
        value: _intValue(stats['active_drivers']).toString(),
        helper: 'Comptes actifs cote livreurs',
        color: Colors.teal,
        icon: Icons.two_wheeler_outlined,
      ),
      _MetricCardData(
        label: 'Relais actifs',
        value: _intValue(stats['active_relays']).toString(),
        helper: 'Points relais operationnels',
        color: Colors.green,
        icon: Icons.storefront_outlined,
      ),
      _MetricCardData(
        label: 'Livraisons reussies',
        value: _intValue(stats['delivered']).toString(),
        helper: '${_intValue(stats['failed'])} echecs enregistrés',
        color: Colors.blueGrey,
        icon: Icons.check_circle_outline,
      ),
    ];
  }

  List<_ShortcutItem> _buildShortcuts() {
    return const [
      _ShortcutItem(
        title: 'Colis',
        subtitle: 'Pilotage du flux et blocages',
        route: '/admin/parcels',
        icon: Icons.inventory_2_outlined,
        color: Colors.blue,
      ),
      _ShortcutItem(
        title: 'Utilisateurs',
        subtitle: 'Roles, bannissements, historique',
        route: '/admin/users',
        icon: Icons.people_outline,
        color: Colors.teal,
      ),
      _ShortcutItem(
        title: 'Retraits',
        subtitle: 'Valider ou rejeter les payouts',
        route: '/admin/payouts',
        icon: Icons.payments_outlined,
        color: Colors.red,
      ),
      _ShortcutItem(
        title: 'Relais',
        subtitle: 'Verification et controle reseau',
        route: '/admin/relays',
        icon: Icons.store_mall_directory_outlined,
        color: Colors.green,
      ),
      _ShortcutItem(
        title: 'Flotte live',
        subtitle: 'Carte temps reel des missions',
        route: '/admin/fleet',
        icon: Icons.location_searching_outlined,
        color: Colors.indigo,
      ),
      _ShortcutItem(
        title: 'Anomalies',
        subtitle: 'GPS perdu et retards critiques',
        route: '/admin/anomalies',
        icon: Icons.gpp_maybe_outlined,
        color: Colors.orange,
      ),
      _ShortcutItem(
        title: 'Audit',
        subtitle: 'Evenements et traces systeme',
        route: '/admin/audit-log',
        icon: Icons.history,
        color: Colors.brown,
      ),
      _ShortcutItem(
        title: 'Finance COD',
        subtitle: 'Suivi du cash et exposition',
        route: '/admin/finance',
        icon: Icons.account_balance_wallet_outlined,
        color: Colors.deepPurple,
      ),
      _ShortcutItem(
        title: 'Heatmap',
        subtitle: 'Demande et densite terrain',
        route: '/admin/heatmap',
        icon: Icons.layers_outlined,
        color: Colors.cyan,
      ),
      _ShortcutItem(
        title: 'Promotions',
        subtitle: 'Codes promo et campagnes',
        route: '/admin/promotions',
        icon: Icons.campaign_outlined,
        color: Colors.pink,
      ),
    ];
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});

  final List<_MetricCardData> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.24,
      ),
      itemBuilder: (context, index) => _MetricCard(item: items[index]),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});

  final _MetricCardData item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: item.color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: item.color),
          const Spacer(),
          Text(
            item.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: item.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            item.helper,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _PriorityTile extends StatelessWidget {
  const _PriorityTile({required this.item});

  final _PriorityItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(item.route),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: item.color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: item.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: item.color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.count.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.item});

  final _ShortcutItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(item.route),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: item.color.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: item.color),
              ),
              const Spacer(),
              Text(
                item.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCardData {
  const _MetricCardData({
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String helper;
  final Color color;
  final IconData icon;
}

class _PriorityItem {
  const _PriorityItem({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.color,
    required this.icon,
    required this.route,
  });

  final String title;
  final String subtitle;
  final int count;
  final Color color;
  final IconData icon;
  final String route;
}

class _ShortcutItem {
  const _ShortcutItem({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
  final Color color;
}

int _intValue(dynamic value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _doubleValue(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

class _ExpressToggleTile extends ConsumerStatefulWidget {
  const _ExpressToggleTile();

  @override
  ConsumerState<_ExpressToggleTile> createState() => _ExpressToggleTileState();
}

class _ExpressToggleTileState extends ConsumerState<_ExpressToggleTile> {
  bool? _optimistic;
  bool _loading = false;

  Future<void> _toggle(bool current) async {
    final next = !current;
    setState(() {
      _optimistic = next;
      _loading = true;
    });
    try {
      await ref.read(apiClientProvider).setExpressEnabled(next);
      ref.invalidate(_expressSettingsProvider);
    } catch (e) {
      setState(() => _optimistic = current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
            title: const Text(
              'Livraison Express',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              enabled
                  ? 'Activee et visible par les clients (+30 %).'
                  : 'Desactivee et masquee pour les clients.',
              style: TextStyle(
                color: enabled ? const Color(0xFFFF6B00) : Colors.grey,
                fontSize: 13,
              ),
            ),
            secondary: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.bolt,
                    color: enabled ? const Color(0xFFFF6B00) : Colors.grey,
                  ),
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

class _ReferralSettingsTile extends ConsumerStatefulWidget {
  const _ReferralSettingsTile();

  @override
  ConsumerState<_ReferralSettingsTile> createState() =>
      _ReferralSettingsTileState();
}

class _ReferralSettingsTileState extends ConsumerState<_ReferralSettingsTile> {
  bool _loading = false;

  Future<void> _setEnabled(
    Map<String, dynamic> current,
    bool enabled,
  ) async {
    await _saveSettings(
      enabled: enabled,
      sponsorBonusXof: _intValue(current['referral_sponsor_bonus_xof']),
      referredBonusXof: _intValue(current['referral_referred_bonus_xof']),
      shareBaseUrl: current['referral_share_base_url']?.toString() ?? '',
      sponsorAllowedRoles: List<String>.from(
        current['referral_sponsor_allowed_roles'] as List? ??
            current['referral_allowed_roles'] as List? ??
            const <String>[],
      ),
      referredAllowedRoles: List<String>.from(
        current['referral_referred_allowed_roles'] as List? ??
            current['referral_allowed_roles'] as List? ??
            const <String>[],
      ),
      applyMetric:
          current['referral_apply_metric']?.toString() ?? 'sent_parcels',
      applyMaxCount: _intValue(current['referral_apply_max_count']),
      rewardMetric: current['referral_reward_metric']?.toString() ??
          'delivered_sender_parcels',
      rewardCount: _intValue(current['referral_reward_count'], fallback: 1),
    );
  }

  Future<void> _saveSettings({
    required bool enabled,
    required int sponsorBonusXof,
    required int referredBonusXof,
    required String shareBaseUrl,
    required List<String> sponsorAllowedRoles,
    required List<String> referredAllowedRoles,
    required String applyMetric,
    required int applyMaxCount,
    required String rewardMetric,
    required int rewardCount,
  }) async {
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).setReferralSettings({
        'enabled': enabled,
        'sponsor_bonus_xof': sponsorBonusXof,
        'referred_bonus_xof': referredBonusXof,
        'share_base_url': shareBaseUrl.trim(),
        'sponsor_allowed_roles': sponsorAllowedRoles,
        'referred_allowed_roles': referredAllowedRoles,
        'apply_metric': applyMetric,
        'apply_max_count': applyMaxCount,
        'reward_metric': rewardMetric,
        'reward_count': rewardCount,
      });
      ref.invalidate(_referralSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parrainage mis a jour')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _editConfig(Map<String, dynamic> current) async {
    final sponsorBonusController = TextEditingController(
      text: _intValue(current['referral_sponsor_bonus_xof']).toString(),
    );
    final referredBonusController = TextEditingController(
      text: _intValue(current['referral_referred_bonus_xof']).toString(),
    );
    final urlController = TextEditingController(
      text: current['referral_share_base_url']?.toString() ?? '',
    );
    final enabled = current['referral_enabled'] as bool? ?? true;
    final sponsorRoles = List<String>.from(
      current['referral_sponsor_allowed_roles'] as List? ??
          current['referral_allowed_roles'] as List? ??
          const <String>['client', 'driver', 'relay_agent'],
    );
    final referredRoles = List<String>.from(
      current['referral_referred_allowed_roles'] as List? ??
          current['referral_allowed_roles'] as List? ??
          const <String>['client', 'driver', 'relay_agent'],
    );
    final applyMaxCountController = TextEditingController(
      text: _intValue(current['referral_apply_max_count']).toString(),
    );
    final rewardCountController = TextEditingController(
      text: _intValue(current['referral_reward_count'], fallback: 1).toString(),
    );
    final metricOptions = List<Map<String, dynamic>>.from(
      current['referral_metric_options'] as List? ??
          const <Map<String, dynamic>>[
            {'value': 'sent_parcels', 'label': 'colis envoyes'},
            {
              'value': 'delivered_sender_parcels',
              'label': 'colis livres',
            },
            {
              'value': 'completed_driver_deliveries',
              'label': 'livraisons effectuees',
            },
          ],
    );
    String applyMetric =
        current['referral_apply_metric']?.toString() ?? 'sent_parcels';
    String rewardMetric = current['referral_reward_metric']?.toString() ??
        'delivered_sender_parcels';
    if (!metricOptions.any((option) => option['value'] == applyMetric)) {
      applyMetric = metricOptions.first['value']!.toString();
    }
    if (!metricOptions.any((option) => option['value'] == rewardMetric)) {
      rewardMetric = metricOptions.first['value']!.toString();
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Configurer le parrainage'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: sponsorBonusController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Bonus parrain (XOF)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: referredBonusController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Bonus filleul (XOF)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL de partage',
                    hintText: 'Laisser vide pour l\'URL Denkma automatique',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Optionnel. Si tu laisses vide, Denkma genere une page publique de parrainage automatiquement.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Qui peut parrainer',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _roleSelectorChip(
                      label: 'Clients',
                      role: 'client',
                      selectedRoles: sponsorRoles,
                      onChanged: () => setDialogState(() {
                        _toggleRoleSelection(sponsorRoles, 'client');
                      }),
                    ),
                    _roleSelectorChip(
                      label: 'Livreurs',
                      role: 'driver',
                      selectedRoles: sponsorRoles,
                      onChanged: () => setDialogState(() {
                        _toggleRoleSelection(sponsorRoles, 'driver');
                      }),
                    ),
                    _roleSelectorChip(
                      label: 'Relais',
                      role: 'relay_agent',
                      selectedRoles: sponsorRoles,
                      onChanged: () => setDialogState(() {
                        _toggleRoleSelection(sponsorRoles, 'relay_agent');
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Qui peut etre parraine',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _roleSelectorChip(
                      label: 'Clients',
                      role: 'client',
                      selectedRoles: referredRoles,
                      onChanged: () => setDialogState(() {
                        _toggleRoleSelection(referredRoles, 'client');
                      }),
                    ),
                    _roleSelectorChip(
                      label: 'Livreurs',
                      role: 'driver',
                      selectedRoles: referredRoles,
                      onChanged: () => setDialogState(() {
                        _toggleRoleSelection(referredRoles, 'driver');
                      }),
                    ),
                    _roleSelectorChip(
                      label: 'Relais',
                      role: 'relay_agent',
                      selectedRoles: referredRoles,
                      onChanged: () => setDialogState(() {
                        _toggleRoleSelection(referredRoles, 'relay_agent');
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: applyMetric,
                  decoration: const InputDecoration(
                    labelText: 'Regle pour appliquer le code',
                  ),
                  items: metricOptions
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option['value']!.toString(),
                          child: Text(option['label']!.toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setDialogState(() => applyMetric = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: applyMaxCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nombre max avant saisie du code',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: rewardMetric,
                  decoration: const InputDecoration(
                    labelText: 'Regle pour debloquer la prime',
                  ),
                  items: metricOptions
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option['value']!.toString(),
                          child: Text(option['label']!.toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setDialogState(() => rewardMetric = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rewardCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Seuil de declenchement de la prime',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Les overrides utilisateur peuvent toujours forcer actif ou inactif depuis la fiche utilisateur.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop({
                'enabled': enabled,
                'sponsor_bonus_xof':
                    int.tryParse(sponsorBonusController.text.trim()) ?? 0,
                'referred_bonus_xof':
                    int.tryParse(referredBonusController.text.trim()) ?? 0,
                'share_base_url': urlController.text.trim(),
                'sponsor_allowed_roles': sponsorRoles,
                'referred_allowed_roles': referredRoles,
                'apply_metric': applyMetric,
                'apply_max_count':
                    int.tryParse(applyMaxCountController.text.trim()) ?? 0,
                'reward_metric': rewardMetric,
                'reward_count':
                    int.tryParse(rewardCountController.text.trim()) ?? 1,
              }),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    sponsorBonusController.dispose();
    referredBonusController.dispose();
    urlController.dispose();
    applyMaxCountController.dispose();
    rewardCountController.dispose();
    if (result == null) {
      return;
    }
    await _saveSettings(
      enabled: result['enabled'] as bool? ?? enabled,
      sponsorBonusXof: result['sponsor_bonus_xof'] as int? ?? 0,
      referredBonusXof: result['referred_bonus_xof'] as int? ?? 0,
      shareBaseUrl: result['share_base_url']?.toString() ?? '',
      sponsorAllowedRoles: List<String>.from(
        result['sponsor_allowed_roles'] as List? ?? const <String>['client'],
      ),
      referredAllowedRoles: List<String>.from(
        result['referred_allowed_roles'] as List? ?? const <String>['client'],
      ),
      applyMetric: result['apply_metric']?.toString() ?? 'sent_parcels',
      applyMaxCount: result['apply_max_count'] as int? ?? 0,
      rewardMetric:
          result['reward_metric']?.toString() ?? 'delivered_sender_parcels',
      rewardCount: result['reward_count'] as int? ?? 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(_referralSettingsProvider);
    return asyncVal.when(
      data: (data) {
        final enabled = data['referral_enabled'] as bool? ?? true;
        final sponsorBonusXof = _intValue(data['referral_sponsor_bonus_xof']);
        final referredBonusXof = _intValue(data['referral_referred_bonus_xof']);
        final configuredShareBaseUrl =
            data['referral_share_base_url']?.toString().trim() ?? '';
        final effectiveShareBaseUrl =
            data['effective_referral_share_base_url']?.toString().trim() ?? '';
        final sponsorRoles = List<String>.from(
          data['referral_sponsor_allowed_roles'] as List? ??
              data['referral_allowed_roles'] as List? ??
              const <String>[],
        );
        final referredRoles = List<String>.from(
          data['referral_referred_allowed_roles'] as List? ??
              data['referral_allowed_roles'] as List? ??
              const <String>[],
        );
        final statsByRole = Map<String, dynamic>.from(
          data['stats_by_role'] as Map? ?? const {},
        );
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Parrainage',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            enabled
                                ? 'Programme actif. Parrain: ${formatXof(sponsorBonusXof.toDouble())} / filleul: ${formatXof(referredBonusXof.toDouble())}.'
                                : 'Programme desactive globalement.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.blueGrey,
                            ),
                          ),
                          if (effectiveShareBaseUrl.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              effectiveShareBaseUrl,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: enabled,
                      onChanged:
                          _loading ? null : (value) => _setEnabled(data, value),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _referralMetricChip(
                      'Codes',
                      _intValue(data['users_with_code']).toString(),
                    ),
                    _referralMetricChip(
                      'Eligibles',
                      _intValue(data['effective_enabled_users']).toString(),
                    ),
                    _referralMetricChip(
                      'Filleuls',
                      _intValue(data['referred_users']).toString(),
                    ),
                    _referralMetricChip(
                      'Primes payees',
                      _intValue(data['rewarded_users']).toString(),
                    ),
                    _referralMetricChip(
                      'Primes en attente',
                      _intValue(data['pending_reward_users']).toString(),
                    ),
                    _referralMetricChip(
                      'Overrides +',
                      _intValue(data['override_enabled_users']).toString(),
                    ),
                    _referralMetricChip(
                      'Overrides -',
                      _intValue(data['override_disabled_users']).toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _referralLine(
                        'Portee',
                        enabled
                            ? 'Globale active par defaut'
                            : 'Globale inactive',
                      ),
                      const SizedBox(height: 6),
                      _referralLine(
                        'Parrains',
                        sponsorRoles.isEmpty
                            ? 'Aucun role autorise'
                            : sponsorRoles.join(', '),
                      ),
                      const SizedBox(height: 6),
                      _referralLine(
                        'Filleuls',
                        referredRoles.isEmpty
                            ? 'Aucun role autorise'
                            : referredRoles.join(', '),
                      ),
                      const SizedBox(height: 6),
                      _referralLine(
                        'Application',
                        data['referral_apply_rule']?.toString() ??
                            'Regle non disponible',
                      ),
                      const SizedBox(height: 6),
                      _referralLine(
                        'Prime',
                        data['referral_reward_rule']?.toString() ??
                            'Regle non disponible',
                      ),
                      const SizedBox(height: 6),
                      _referralLine(
                        'URL active',
                        effectiveShareBaseUrl.isEmpty
                            ? 'URL Denkma automatique indisponible'
                            : effectiveShareBaseUrl,
                      ),
                      const SizedBox(height: 6),
                      _referralLine(
                        'Exceptions',
                        'Par utilisateur depuis Admin > Utilisateurs > Fiche > Parrainage',
                      ),
                      if (configuredShareBaseUrl.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _referralLine(
                          'URL configuree',
                          configuredShareBaseUrl,
                        ),
                      ] else ...[
                        const SizedBox(height: 6),
                        _referralLine(
                          'Mode URL',
                          'Automatique via la page publique Denkma',
                        ),
                      ],
                      if ((data['sample_referral_url']?.toString() ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _referralLine(
                          'Exemple',
                          data['sample_referral_url']!.toString(),
                        ),
                      ],
                    ],
                  ),
                ),
                if (statsByRole.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Couverture par role',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: statsByRole.entries.map((entry) {
                      final roleData = Map<String, dynamic>.from(
                        entry.value as Map? ?? const {},
                      );
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _roleLabel(entry.key),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Eligibles: ${_intValue(roleData['effective_enabled'])}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Codes: ${_intValue(roleData['with_code'])}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Overrides +: ${_intValue(roleData['forced_enabled'])}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Overrides -: ${_intValue(roleData['forced_disabled'])}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed:
                          _loading ? null : () => context.push('/admin/users'),
                      icon: const Icon(Icons.group_outlined),
                      label: const Text('Gerer les exceptions'),
                    ),
                    TextButton.icon(
                      onPressed: _loading ? null : () => _editConfig(data),
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.tune),
                      label: const Text('Configurer'),
                    ),
                    TextButton.icon(
                      onPressed: _loading
                          ? null
                          : () => context.push('/admin/audit-log'),
                      icon: const Icon(Icons.history_outlined),
                      label: const Text('Voir audit'),
                    ),
                  ],
                ),
                if ((data['sample_share_message']?.toString() ?? '')
                    .isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      data['sample_share_message']!.toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

Widget _referralLine(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 72,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
      ),
    ],
  );
}

Widget _referralMetricChip(String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.blueGrey.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$label: $value',
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

Widget _roleSelectorChip({
  required String label,
  required String role,
  required List<String> selectedRoles,
  required VoidCallback onChanged,
}) {
  return FilterChip(
    label: Text(label),
    selected: selectedRoles.contains(role),
    onSelected: (_) => onChanged(),
  );
}

void _toggleRoleSelection(List<String> roles, String role) {
  if (roles.contains(role)) {
    if (roles.length > 1) {
      roles.remove(role);
    }
    return;
  }
  roles.add(role);
}

String _roleLabel(String role) {
  switch (role) {
    case 'driver':
      return 'Livreurs';
    case 'relay_agent':
      return 'Relais';
    case 'admin':
      return 'Admins';
    default:
      return 'Clients';
  }
}
