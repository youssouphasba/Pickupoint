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
    required this.isMe,
  });

  factory DriverRanking.fromJson(Map<String, dynamic> json) {
    return DriverRanking(
      rank: json['rank'] ?? 0,
      displayName: json['display_name'] ?? '',
      badge: json['badge'] ?? 'none',
      deliveriesTotal: json['deliveries_total'] ?? 0,
      deliveriesSuccess: json['deliveries_success'] ?? 0,
      successRate: (json['success_rate'] ?? 0).toDouble(),
      avgRating: (json['avg_rating'] ?? 0).toDouble(),
      totalEarned: json['total_earned_xof']?.toDouble(),
      bonusPaid: json['bonus_paid_xof']?.toDouble(),
      isMe: json['is_me'] ?? false,
    );
  }
}
