class LoyaltyInfo {
  final int points;
  final String tier;
  final int? nextTierAt;
  final String referralCode;
  final List<LoyaltyEvent> history;

  LoyaltyInfo({
    required this.points,
    required this.tier,
    this.nextTierAt,
    required this.referralCode,
    required this.history,
  });

  factory LoyaltyInfo.fromJson(Map<String, dynamic> json) {
    return LoyaltyInfo(
      points: json['points'] ?? 0,
      tier: json['tier'] ?? 'bronze',
      nextTierAt: json['next_tier_at'],
      referralCode: json['referral_code'] ?? '',
      history: (json['history'] as List? ?? [])
          .map((e) => LoyaltyEvent.fromJson(e))
          .toList(),
    );
  }
}

class LoyaltyEvent {
  final String id;
  final String type;
  final int points;
  final int balance;
  final DateTime createdAt;

  LoyaltyEvent({
    required this.id,
    required this.type,
    required this.points,
    required this.balance,
    required this.createdAt,
  });

  factory LoyaltyEvent.fromJson(Map<String, dynamic> json) {
    return LoyaltyEvent(
      id: json['event_id'] ?? '',
      type: json['type'] ?? '',
      points: json['points'] ?? 0,
      balance: json['balance'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class DriverRanking {
  final int rank;
  final String displayName;
  final String badge;
  final int deliveriesTotal;
  final int deliveriesSuccess;
  final double successRate;
  final double avgRating;
  final double? totalEarned;
  final double? bonusPaid;
  final MonthlyGoal monthlyGoal;
  final int streakDays;
  final int activeDays;
  final List<RankingPodiumEntry> podium;
  final List<RankingBadge> badgesEarned;
  final List<RankingAchievement> achievements;
  final int missingDeliveriesToTop3;
  final int totalRankedDrivers;
  final String message;
  final DateTime? lastUpdatedAt;
  final bool isMe;

  DriverRanking({
    required this.rank,
    required this.displayName,
    required this.badge,
    required this.deliveriesTotal,
    required this.deliveriesSuccess,
    required this.successRate,
    required this.avgRating,
    this.totalEarned,
    this.bonusPaid,
    required this.monthlyGoal,
    required this.streakDays,
    required this.activeDays,
    required this.podium,
    required this.badgesEarned,
    required this.achievements,
    required this.missingDeliveriesToTop3,
    required this.totalRankedDrivers,
    required this.message,
    this.lastUpdatedAt,
    required this.isMe,
  });

  factory DriverRanking.fromJson(Map<String, dynamic> json) {
    final rawSuccessRate = (json['success_rate'] as num? ?? 0).toDouble();
    return DriverRanking(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      displayName: json['display_name'] ?? '',
      badge: json['badge'] ?? 'none',
      deliveriesTotal: (json['deliveries_total'] as num?)?.toInt() ?? 0,
      deliveriesSuccess: (json['deliveries_success'] as num?)?.toInt() ?? 0,
      successRate: rawSuccessRate > 1 ? rawSuccessRate / 100 : rawSuccessRate,
      avgRating: (json['avg_rating'] as num? ?? 0).toDouble(),
      totalEarned: (json['total_earned_xof'] as num?)?.toDouble(),
      bonusPaid: (json['bonus_paid_xof'] as num?)?.toDouble(),
      monthlyGoal: MonthlyGoal.fromJson(
        json['monthly_goal'] as Map<String, dynamic>? ?? const {},
      ),
      streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      activeDays: (json['active_days'] as num?)?.toInt() ?? 0,
      podium: (json['podium'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RankingPodiumEntry.fromJson)
          .toList(),
      badgesEarned: (json['badges_earned'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RankingBadge.fromJson)
          .toList(),
      achievements: (json['achievements'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RankingAchievement.fromJson)
          .toList(),
      missingDeliveriesToTop3:
          (json['missing_deliveries_to_top3'] as num?)?.toInt() ?? 0,
      totalRankedDrivers: (json['total_ranked_drivers'] as num?)?.toInt() ?? 0,
      message: json['message'] as String? ?? '',
      lastUpdatedAt: json['last_updated_at'] != null
          ? DateTime.tryParse(json['last_updated_at'] as String)
          : null,
      isMe: json['is_me'] ?? false,
    );
  }
}

class MonthlyGoal {
  final int target;
  final int current;
  final int remaining;
  final double progress;

  const MonthlyGoal({
    required this.target,
    required this.current,
    required this.remaining,
    required this.progress,
  });

  factory MonthlyGoal.fromJson(Map<String, dynamic> json) {
    return MonthlyGoal(
      target: (json['target'] as num?)?.toInt() ?? 0,
      current: (json['current'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      progress:
          (json['progress'] as num? ?? 0).toDouble().clamp(0.0, 1.0).toDouble(),
    );
  }
}

class RankingPodiumEntry {
  final int rank;
  final String displayName;
  final int deliveriesSuccess;
  final String badge;
  final bool isMe;

  const RankingPodiumEntry({
    required this.rank,
    required this.displayName,
    required this.deliveriesSuccess,
    required this.badge,
    required this.isMe,
  });

  factory RankingPodiumEntry.fromJson(Map<String, dynamic> json) {
    return RankingPodiumEntry(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      displayName: json['display_name'] as String? ?? 'Livreur',
      deliveriesSuccess: (json['deliveries_success'] as num?)?.toInt() ?? 0,
      badge: json['badge'] as String? ?? 'none',
      isMe: json['is_me'] as bool? ?? false,
    );
  }
}

class RankingBadge {
  final String code;
  final String label;
  final String icon;

  const RankingBadge({
    required this.code,
    required this.label,
    required this.icon,
  });

  factory RankingBadge.fromJson(Map<String, dynamic> json) {
    return RankingBadge(
      code: json['code'] as String? ?? '',
      label: json['label'] as String? ?? 'Badge',
      icon: json['icon'] as String? ?? 'trophy',
    );
  }
}

class RankingAchievement {
  final String label;

  const RankingAchievement({required this.label});

  factory RankingAchievement.fromJson(Map<String, dynamic> json) {
    return RankingAchievement(label: json['label'] as String? ?? '');
  }
}
