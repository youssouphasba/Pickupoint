class InAppCampaign {
  const InAppCampaign({
    required this.id,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.targetRoles,
    required this.placements,
    required this.actionType,
    required this.actionValue,
    required this.startDate,
    required this.endDate,
    required this.priority,
    required this.isActive,
    required this.impressionsCount,
    required this.clicksCount,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String body;
  final String ctaLabel;
  final String? imageUrl;
  final List<String> targetRoles;
  final List<String> placements;
  final String actionType;
  final String actionValue;
  final DateTime startDate;
  final DateTime endDate;
  final int priority;
  final bool isActive;
  final int impressionsCount;
  final int clicksCount;

  factory InAppCampaign.fromJson(Map<String, dynamic> json) {
    return InAppCampaign(
      id: json['campaign_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      ctaLabel: json['cta_label']?.toString() ?? 'Voir',
      imageUrl: json['image_url']?.toString(),
      targetRoles: (json['target_roles'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
      placements: (json['placements'] as List? ?? const ['home'])
          .map((value) => value.toString())
          .toList(),
      actionType: json['action_type']?.toString() ?? 'internal_route',
      actionValue: json['action_value']?.toString() ?? '/',
      startDate: DateTime.tryParse(json['start_date']?.toString() ?? '') ??
          DateTime.now(),
      endDate: DateTime.tryParse(json['end_date']?.toString() ?? '') ??
          DateTime.now(),
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      impressionsCount: (json['impressions_count'] as num?)?.toInt() ?? 0,
      clicksCount: (json['clicks_count'] as num?)?.toInt() ?? 0,
    );
  }
}
