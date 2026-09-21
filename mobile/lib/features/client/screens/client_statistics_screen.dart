import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/user_stats_provider.dart';
import '../../../shared/utils/currency_format.dart';

class ClientStatisticsScreen extends ConsumerWidget {
  const ClientStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes statistiques')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(userStatsProvider.future),
        child: statsAsync.when(
          data: (stats) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildOverview(stats),
              const SizedBox(height: 20),
              _buildMonthlySection(stats),
              const SizedBox(height: 20),
              _buildDeliveryTimeSection(stats),
              const SizedBox(height: 20),
              _buildModesSection(stats),
              const SizedBox(height: 20),
              _buildLoyaltySection(stats),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Statistiques indisponibles.')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverview(Map<String, dynamic> stats) {
    return _section(
      title: 'Vue d’ensemble',
      icon: Icons.insights_outlined,
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.55,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: [
          _metric('Envoyés', stats['parcels_sent'], Icons.outbox_outlined,
              Colors.blue),
          _metric('Reçus', stats['parcels_received'],
              Icons.move_to_inbox_outlined, Colors.teal),
          _metric('En cours', stats['parcels_active'],
              Icons.local_shipping_outlined, Colors.orange),
          _metric('Livrés', stats['parcels_delivered'], Icons.verified_outlined,
              Colors.green),
          _metric('Annulés', stats['parcels_cancelled'], Icons.cancel_outlined,
              Colors.red),
          _metric('Parrainages', stats['referrals_count'], Icons.group_outlined,
              Colors.purple),
        ],
      ),
    );
  }

  Widget _buildMonthlySection(Map<String, dynamic> stats) {
    final successRate = _number(stats['client_monthly_success_rate']);
    final progress =
        (_number(stats['client_goal_progress']) / 1).clamp(0.0, 1.0);
    return _section(
      title: 'Ce mois-ci',
      icon: Icons.calendar_month_outlined,
      child: Column(
        children: [
          _line('Colis envoyés', '${stats['client_monthly_sent'] ?? 0}'),
          _line('Colis livrés', '${stats['client_monthly_delivered'] ?? 0}'),
          _line('Taux de réussite', '${successRate.toStringAsFixed(1)} %'),
          _line('Dépenses',
              formatXof(_number(stats['client_monthly_spent_xof']))),
          _line('Dépense moyenne par colis',
              formatXof(_number(stats['client_average_spent_xof']))),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Objectif mensuel'),
              Text(
                  '${stats['client_monthly_sent'] ?? 0} / ${stats['client_monthly_goal'] ?? 0}'),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress, minHeight: 8),
        ],
      ),
    );
  }

  Widget _buildDeliveryTimeSection(Map<String, dynamic> stats) {
    final average = stats['client_average_delivery_seconds'];
    final fastest = stats['client_fastest_delivery_seconds'];
    final slowest = stats['client_slowest_delivery_seconds'];
    return _section(
      title: 'Délais de livraison',
      icon: Icons.timer_outlined,
      child: Column(
        children: [
          _line('Durée moyenne', _formatDuration(average)),
          _line('Livraison la plus rapide', _formatDuration(fastest)),
          _line('Livraison la plus lente', _formatDuration(slowest)),
          const SizedBox(height: 8),
          Text(
            'Calculé entre la création du colis et sa confirmation de livraison.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildModesSection(Map<String, dynamic> stats) {
    final modeCounts = Map<String, dynamic>.from(
        stats['client_mode_counts'] as Map? ?? const {});
    final durationStats = Map<String, dynamic>.from(
      stats['client_delivery_duration_stats'] as Map? ?? const {},
    );
    const modes = <String, String>{
      'home_to_home': 'Domicile → domicile',
      'home_to_relay': 'Domicile → relais',
      'relay_to_home': 'Relais → domicile',
      'relay_to_relay': 'Relais → relais',
    };
    return _section(
      title: 'Répartition par mode',
      icon: Icons.route_outlined,
      child: Column(
        children: modes.entries.map((entry) {
          final duration = Map<String, dynamic>.from(
            durationStats[entry.key] as Map? ?? const {},
          );
          final count = modeCounts[entry.key] ?? 0;
          return Column(
            children: [
              _line(entry.value, '$count colis'),
              if (duration.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Durée moyenne : ${_formatDuration(duration['average_seconds'])}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              const Divider(height: 18),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLoyaltySection(Map<String, dynamic> stats) {
    return _section(
      title: 'Fidélité',
      icon: Icons.stars_outlined,
      child: Column(
        children: [
          _line('Points', '${stats['loyalty_points'] ?? 0}'),
          _line('Niveau', '${stats['loyalty_tier'] ?? 'bronze'}'),
          _line('Points par livraison',
              '${stats['loyalty_points_per_delivery'] ?? 0}'),
        ],
      ),
    );
  }

  Widget _section(
      {required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blue.shade700),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _metric(String label, dynamic value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          Text('$value',
              style:
                  const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child:
                  Text(label, style: TextStyle(color: Colors.grey.shade700))),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  double _number(dynamic value) => (value as num?)?.toDouble() ?? 0;

  String _formatDuration(dynamic value) {
    final seconds = (value as num?)?.toInt();
    if (seconds == null || seconds <= 0) return 'Pas encore de données';
    final duration = Duration(seconds: seconds);
    if (duration.inHours > 0) {
      return '${duration.inHours} h ${duration.inMinutes.remainder(60)} min';
    }
    return '${duration.inMinutes} min';
  }
}
