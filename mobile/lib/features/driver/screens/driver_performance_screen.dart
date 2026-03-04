import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../providers/ranking_provider.dart';

class DriverPerformanceScreen extends ConsumerWidget {
  const DriverPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // XP progress
    const xpPerLevel = 100;
    final currentXpInLevel = user.xp % xpPerLevel;
    final progress = currentXpInLevel / xpPerLevel;

    return Scaffold(
      appBar: AppBar(title: const Text('Ma Performance')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Level & XP ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade800, Colors.blue.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.stars, color: Colors.amber, size: 32),
                      const SizedBox(width: 8),
                      Text(
                        'Niveau ${user.level}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white24,
                      color: Colors.amber,
                      minHeight: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${currentXpInLevel} / $xpPerLevel XP pour le prochain niveau',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Badges ──────────────────────────────────────────────
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Mes Badges',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            if (user.badges.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Continuez vos livraisons pour débloquer votre premier badge !',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: user.badges.map((b) => _buildBadgeItem(b)).toList(),
              ),
            const SizedBox(height: 28),

            // ── Stats ───────────────────────────────────────────────
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Statistiques de carrière',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              Icons.local_shipping,
              'Livraisons terminées',
              user.deliveriesCompleted.toString(),
              Colors.blue,
            ),
            _buildStatCard(
              Icons.timer,
              'Livraisons à l\'heure',
              '${user.onTimeDeliveries}',
              Colors.green,
            ),
            _buildStatCard(
              Icons.star,
              'Note moyenne',
              user.averageRating.toStringAsFixed(1),
              Colors.amber,
              subtitle: 'Basé sur ${user.totalRatingsCount} avis',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeItem(String slug) {
    IconData icon = Icons.help_outline;
    String name = 'Badge';
    Color color = Colors.grey;

    switch (slug) {
      case 'first_flight':
        icon = Icons.rocket_launch;
        name = 'Premier Vol';
        color = Colors.orange;
        break;
      case 'road_warrior':
        icon = Icons.directions_bike;
        name = 'Guerrier';
        color = Colors.blue;
        break;
      case 'dakar_legend':
        icon = Icons.emoji_events;
        name = 'Légende';
        color = Colors.amber;
        break;
      case 'five_star_general':
        icon = Icons.military_tech;
        name = 'Général';
        color = Colors.purple;
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 32),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value, Color color, {String? subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyRankingCard(BuildContext context, WidgetRef ref) {
    final rankingAsync = ref.watch(rankingProvider);

    return rankingAsync.when(
      data: (ranking) {
        if (ranking == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events, color: Colors.amber, size: 30),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'CLASSEMENT DU MOIS',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '#${ranking.rank}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _rankingStat('Succès', '${(ranking.successRate * 100).toStringAsFixed(0)}%'),
                  _rankingStat('Volume', '${ranking.deliveriesTotal}'),
                  if (ranking.bonusPaid != null && ranking.bonusPaid! > 0)
                    _rankingStat('Bonus', formatXof(ranking.bonusPaid!), isHighlight: true),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: LinearProgressIndicator()),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _rankingStat(String label, String value, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isHighlight ? Colors.green.shade700 : Colors.black87,
          ),
        ),
      ],
    );
  }
}
