import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/loyalty.dart';
import '../../../core/models/wallet.dart';
import '../../../shared/utils/currency_format.dart';
import '../providers/ranking_provider.dart';
import '../../relay/providers/relay_provider.dart';

class DriverPerformanceScreen extends ConsumerWidget {
  const DriverPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final transactionsAsync =
        ref.watch(relayTransactionsProvider(_currentMonthPeriod()));

    // XP progress
    const xpPerLevel = 100;
    final currentXpInLevel = user.xp % xpPerLevel;
    final progress = currentXpInLevel / xpPerLevel;
    final levelTitle = _driverLevelTitle(user.level);
    final nextLevelTitle = _nextDriverLevelTitle(user.level);

    return Scaffold(
      appBar: AppBar(title: const Text('Ma Performance')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Level & XP ──────────────────────────────────────────
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showLevelsOverview(context, user.level, user.xp),
              child: Container(
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
                      color: Colors.blue.withValues(alpha: 0.3),
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
                        Flexible(
                          child: Text(
                            'Niveau ${user.level} - $levelTitle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.expand_more,
                            color: Colors.white70, size: 22),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Prochain rang : $nextLevelTitle',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
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
                      '$currentXpInLevel / $xpPerLevel XP pour le prochain niveau',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Classement mensuel ───────────────────────────────────
            _buildMonthlyRankingCard(context, ref),
            const SizedBox(height: 28),

            // ── Gains Chart ──────────────────────────────────────────
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Mes revenus (7 derniers jours)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            _buildGainsChart(transactionsAsync),
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
            _buildStatCard(
              Icons.payments,
              'Revenus totaux accumulés',
              formatXof(user.totalEarned),
              Colors.orange,
              subtitle: 'Missions, bonus et pourboires',
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
          backgroundColor: color.withValues(alpha: 0.1),
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

  Widget _buildStatCard(IconData icon, String label, String value, Color color,
      {String? subtitle}) {
    return Builder(builder: (context) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            _showDriverKpiInfo(context, label, _driverKpiExplanation(label)),
        child: Container(
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
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 13)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 6),
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildMonthlyRankingCard(BuildContext context, WidgetRef ref) {
    final rankingAsync = ref.watch(rankingProvider);

    return rankingAsync.when(
      data: (ranking) {
        if (ranking == null) return const SizedBox.shrink();
        final rankLabel = ranking.rank > 0
            ? '#${ranking.rank} / ${ranking.totalRankedDrivers}'
            : '- / ${ranking.totalRankedDrivers}';
        final goal = ranking.monthlyGoal;

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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      rankLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (ranking.message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ranking.message,
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: goal.progress,
                  minHeight: 10,
                  backgroundColor: Colors.white,
                  color: Colors.amber.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${goal.current} / ${goal.target} courses',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    goal.remaining == 0
                        ? 'Objectif atteint'
                        : 'Encore ${goal.remaining}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _rankingStat('Succès',
                      '${(ranking.successRate * 100).toStringAsFixed(0)}%'),
                  _rankingStat('Courses', '${ranking.deliveriesSuccess}'),
                  _rankingStat('Revenus', formatXof(ranking.totalEarned ?? 0)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _rankingStat('Jours actifs', '${ranking.activeDays}'),
                  _rankingStat('Série', '${ranking.streakDays} j'),
                  if (ranking.bonusPaid != null && ranking.bonusPaid! > 0)
                    _rankingStat('Bonus', formatXof(ranking.bonusPaid!),
                        isHighlight: true)
                  else
                    _rankingStat(
                      'Top 3',
                      ranking.missingDeliveriesToTop3 > 0
                          ? '+${ranking.missingDeliveriesToTop3}'
                          : '-',
                    ),
                ],
              ),
              if (ranking.podium.isNotEmpty) ...[
                const SizedBox(height: 18),
                _buildPodium(ranking.podium),
              ],
              if (ranking.badgesEarned.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildRankingBadges(ranking.badgesEarned),
              ],
              const SizedBox(height: 16),
              _buildGeneralRanking(ranking),
              if (ranking.monthlyHistory.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildMonthlyHistory(ranking.monthlyHistory),
              ],
              if (ranking.achievements.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildAchievements(ranking.achievements),
              ],
            ],
          ),
        );
      },
      loading: () => const Center(child: LinearProgressIndicator()),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildGeneralRanking(DriverRanking ranking) {
    final general = ranking.generalRanking;
    final rankLabel = general.rank > 0
        ? '#${general.rank} / ${general.totalDrivers}'
        : '- / ${general.totalDrivers}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_outlined, color: Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Classement général',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${general.deliveriesSuccess} courses depuis le début',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          Text(
            rankLabel,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyHistory(List<DriverMonthlyHistoryEntry> history) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Historique des mois',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ...history.map((entry) {
          final rank = entry.rank > 0 ? '#${entry.rank}' : '-';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    _formatPeriodLabel(entry.period),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${entry.deliveriesSuccess} courses',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                Text(
                  '$rank / ${entry.totalDrivers}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPodium(List<RankingPodiumEntry> podium) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Podium du mois',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ...podium.map((entry) {
          final color =
              entry.isMe ? Colors.amber.shade700 : Colors.grey.shade700;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor:
                      entry.isMe ? Colors.amber.shade100 : Colors.white,
                  child: Text(
                    '${entry.rank}',
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight:
                          entry.isMe ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${entry.deliveriesSuccess} courses',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRankingBadges(List<RankingBadge> badges) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: badges
          .map(
            (badge) => Chip(
              avatar: Icon(_rankingBadgeIcon(badge.icon), size: 16),
              label: Text(badge.label),
              backgroundColor: Colors.white,
              side: BorderSide(color: Colors.amber.shade200),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          )
          .toList(),
    );
  }

  Widget _buildAchievements(List<RankingAchievement> achievements) {
    return Column(
      children: achievements
          .map(
            (achievement) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      size: 16, color: Colors.green.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      achievement.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  IconData _rankingBadgeIcon(String icon) {
    switch (icon) {
      case 'rocket':
        return Icons.rocket_launch;
      case 'speed':
        return Icons.speed;
      case 'verified':
        return Icons.verified;
      case 'shield':
        return Icons.shield_outlined;
      case 'calendar':
        return Icons.calendar_month;
      default:
        return Icons.emoji_events;
    }
  }

  Widget _rankingStat(String label, String value, {bool isHighlight = false}) {
    return Builder(
      builder: (context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDriverKpiInfo(
          context,
          label,
          _monthlyRankingExplanation(label),
        ),
        child: Container(
          constraints: const BoxConstraints(minWidth: 92),
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.shade100),
          ),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(width: 3),
                  Icon(Icons.info_outline,
                      size: 11, color: Colors.grey.shade500),
                ],
              ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildGainsChart(AsyncValue<List<WalletTransaction>> txAsync) {
    return txAsync.when(
      loading: () => const SizedBox(
          height: 180, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox.shrink(),
      data: (txs) {
        final now = DateTime.now();
        final data = List<double>.filled(7, 0.0);
        final labels = List.generate(7, (i) {
          final d = now.subtract(Duration(days: 6 - i));
          return ['L', 'M', 'M', 'J', 'V', 'S', 'D'][d.weekday - 1];
        });

        for (final tx in txs) {
          if (!tx.isCredit) continue;
          final diff = now.difference(tx.createdAt).inDays;
          if (diff >= 7) continue;
          data[6 - diff] += tx.amount;
        }

        final maxGain = data.reduce((a, b) => a > b ? a : b);

        return Container(
          height: 180,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(data.length, (index) {
              final h = maxGain == 0 ? 0.0 : (data[index] / maxGain) * 100;
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (data[index] > 0)
                    Text(
                      data[index] >= 1000
                          ? '${(data[index] / 1000).toStringAsFixed(1)}k'
                          : data[index].toStringAsFixed(0),
                      style: const TextStyle(fontSize: 8, color: Colors.grey),
                    ),
                  const SizedBox(height: 4),
                  Container(
                    width: 25,
                    height: h == 0 ? 4 : h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: h == 0
                            ? [Colors.grey.shade200, Colors.grey.shade300]
                            : [Colors.green.shade400, Colors.green.shade600],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    labels[index],
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
  }

  String _driverKpiExplanation(String label) {
    if (label.contains('Livraisons')) {
      return 'Total des missions terminées depuis la création de votre compte livreur.';
    }
    if (label.contains('heure')) {
      return 'Nombre de livraisons terminées dans les délais attendus. Cela aide à mesurer votre fiabilité.';
    }
    if (label.contains('Note')) {
      return 'Moyenne des notes laissées après vos missions. Plus elle est élevée, plus votre profil inspire confiance.';
    }
    if (label.contains('Revenus')) {
      return 'Total cumulé de vos revenus livreur : courses, bonus et pourboires enregistrés.';
    }
    return 'Indicateur de performance utilisé pour suivre votre activité livreur.';
  }

  String _monthlyRankingExplanation(String label) {
    if (label.contains('Succes') || label.contains('Succ')) {
      return 'Pourcentage de missions du mois terminées avec succès. Il influence votre classement et certains bonus.';
    }
    if (label.contains('Courses')) {
      return 'Nombre de courses terminées ce mois. C’est la base principale du classement mensuel.';
    }
    if (label.contains('Revenus')) {
      return 'Revenus générés ce mois sur vos missions et transactions associées.';
    }
    if (label.contains('Jours')) {
      return 'Nombre de jours différents où vous avez été actif sur des missions ce mois.';
    }
    if (label.contains('Serie') || label.contains('S')) {
      return 'Nombre de jours actifs consécutifs. Garder une série encourage la régularité.';
    }
    if (label.contains('Bonus')) {
      return 'Bonus déjà attribué selon les règles de performance configurées par Denkma.';
    }
    if (label.contains('Top 3')) {
      return 'Nombre de courses supplémentaires estimé pour rejoindre le podium mensuel.';
    }
    return 'Indicateur du classement mensuel livreur.';
  }

  void _showLevelsOverview(
      BuildContext context, int currentLevel, int currentXp) {
    final levels = _driverLevels();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: Icon(Icons.stars, color: Colors.blue.shade700),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Tous les niveaux livreur',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Chaque niveau demande 100 XP. Vous avez $currentXp XP au total.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 18),
            ...levels.map((level) {
              final minLevel = level.minLevel;
              final isCurrent = currentLevel >= minLevel &&
                  (level.maxLevel == null || currentLevel <= level.maxLevel!);
              final reached = currentLevel >= minLevel;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isCurrent ? Colors.blue.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        isCurrent ? Colors.blue.shade300 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          reached ? Colors.blue.shade700 : Colors.grey.shade200,
                      child: Icon(
                        reached ? Icons.check : Icons.lock_outline,
                        color: reached ? Colors.white : Colors.grey.shade600,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            level.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            level.rangeLabel,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isCurrent)
                      Chip(
                        label: const Text('Actuel'),
                        backgroundColor: Colors.blue.shade100,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showDriverKpiInfo(
    BuildContext context,
    String title,
    String message,
  ) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(fontSize: 14, height: 1.35)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

String _currentMonthPeriod() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

String _formatPeriodLabel(String period) {
  final parts = period.split('-');
  if (parts.length != 2) return period;
  const months = [
    'Jan',
    'Fév',
    'Mar',
    'Avr',
    'Mai',
    'Juin',
    'Juil',
    'Août',
    'Sep',
    'Oct',
    'Nov',
    'Déc',
  ];
  final month = int.tryParse(parts[1]);
  if (month == null || month < 1 || month > 12) return period;
  return '${months[month - 1]} ${parts[0].substring(2)}';
}

class _DriverLevel {
  const _DriverLevel(this.minLevel, this.maxLevel, this.name);

  final int minLevel;
  final int? maxLevel;
  final String name;

  String get rangeLabel {
    final minXp = (minLevel - 1) * 100;
    if (maxLevel == null) return 'Niveau $minLevel+ · à partir de $minXp XP';
    final maxXp = maxLevel! * 100 - 1;
    return minLevel == maxLevel
        ? 'Niveau $minLevel · $minXp à $maxXp XP'
        : 'Niveaux $minLevel à $maxLevel · $minXp à $maxXp XP';
  }
}

List<_DriverLevel> _driverLevels() => const [
      _DriverLevel(1, 1, 'Débutant'),
      _DriverLevel(2, 2, 'Ndaw'),
      _DriverLevel(3, 3, 'Goorgorlu'),
      _DriverLevel(4, 4, 'Yaatu'),
      _DriverLevel(5, 6, 'Nandité'),
      _DriverLevel(7, 8, 'Borom Route'),
      _DriverLevel(9, 9, 'Jambaar'),
      _DriverLevel(10, 11, 'Kilifa'),
      _DriverLevel(12, 14, 'Gaïndé'),
      _DriverLevel(15, 17, 'Légende Teranga'),
      _DriverLevel(18, 20, 'Maître du Réseau'),
      _DriverLevel(21, null, 'Icône Denkma'),
    ];

String _driverLevelTitle(int level) {
  if (level >= 21) return 'Icône Denkma';
  if (level >= 18) return 'Maître du Réseau';
  if (level >= 15) return 'Légende Teranga';
  if (level >= 12) return 'Gaïndé';
  if (level >= 10) return 'Kilifa';
  if (level >= 9) return 'Jambaar';
  if (level >= 7) return 'Borom Route';
  if (level >= 5) return 'Nandité';
  if (level >= 4) return 'Yaatu';
  if (level >= 3) return 'Goorgorlu';
  if (level >= 2) return 'Ndaw';
  return 'Débutant';
}

String _nextDriverLevelTitle(int level) {
  if (level < 2) return 'Ndaw';
  if (level < 3) return 'Goorgorlu';
  if (level < 4) return 'Yaatu';
  if (level < 5) return 'Nandité';
  if (level < 7) return 'Borom Route';
  if (level < 9) return 'Jambaar';
  if (level < 10) return 'Kilifa';
  if (level < 12) return 'Gaïndé';
  if (level < 15) return 'Légende Teranga';
  if (level < 18) return 'Maître du Réseau';
  if (level < 21) return 'Icône Denkma';
  return 'Sommet atteint';
}
