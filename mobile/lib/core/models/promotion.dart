class Promotion {
  const Promotion({
    required this.promoId,
    required this.title,
    required this.description,
    required this.promoType,   // "percentage" | "fixed_amount" | "free_delivery" | "express_upgrade"
    required this.value,
    required this.target,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.usesCount,
    this.promoCode,
    this.deliveryMode,
    this.minAmount,
    this.maxUsesTotal,
    this.maxUsesPerUser = 1,
  });

  final String   promoId;
  final String   title;
  final String   description;
  final String   promoType;
  final double   value;
  final String   target;
  final DateTime startDate;
  final DateTime endDate;
  final bool     isActive;
  final int      usesCount;
  final String?  promoCode;
  final String?  deliveryMode;
  final double?  minAmount;
  final int?     maxUsesTotal;
  final int      maxUsesPerUser;

  factory Promotion.fromJson(Map<String, dynamic> j) => Promotion(
        promoId:        j['promo_id'] as String,
        title:          j['title'] as String,
        description:    j['description'] as String? ?? '',
        promoType:      j['promo_type'] as String,
        value:          (j['value'] as num?)?.toDouble() ?? 0,
        target:         j['target'] as String? ?? 'all',
        startDate:      DateTime.parse(j['start_date'] as String),
        endDate:        DateTime.parse(j['end_date'] as String),
        isActive:       j['is_active'] as bool? ?? true,
        usesCount:      j['uses_count'] as int? ?? 0,
        promoCode:      j['promo_code'] as String?,
        deliveryMode:   j['delivery_mode'] as String?,
        minAmount:      (j['min_amount'] as num?)?.toDouble(),
        maxUsesTotal:   j['max_uses_total'] as int?,
        maxUsesPerUser: j['max_uses_per_user'] as int? ?? 1,
      );

  String get typeLabel => switch (promoType) {
        'percentage'      => '-${value.toStringAsFixed(0)}%',
        'fixed_amount'    => '-${value.toStringAsFixed(0)} XOF',
        'free_delivery'   => 'Livraison gratuite',
        'express_upgrade' => 'Express offert',
        _                 => '',
      };

  bool get isCurrentlyActive {
    final now = DateTime.now();
    return isActive && now.isAfter(startDate) && now.isBefore(endDate);
  }
}
