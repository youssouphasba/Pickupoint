class DeliveryMission {
  const DeliveryMission({
    required this.id,
    required this.parcelId,
    required this.status,
    required this.pickupLabel,
    required this.pickupCity,
    required this.deliveryLabel,
    required this.deliveryCity,
    required this.earnAmount,
    required this.createdAt,
    this.distanceKm,
    this.trackingCode,
    this.pickupType, // 'relay' | 'gps'
    this.pickupRelayId,
    this.pickupLat,
    this.pickupLng,
    this.deliveryType, // 'relay' | 'gps'
    this.deliveryRelayId,
    this.deliveryLat,
    this.deliveryLng,
    this.recipientName,
    this.recipientPhone,
    this.driverId,
    this.failureReason,
    this.assignedAt,
    this.completedAt,
    this.etaSeconds,
    this.etaText,
    this.distanceText,
    this.paymentStatus,
    this.paymentMethod,
    this.whoPays,
    this.paymentOverride = false,
    this.deliveryBlockedByPayment = false,
    this.pickupVoiceNote,
    this.deliveryVoiceNote,
    this.driverBonusXof = 0.0,
    this.senderPhotoUrl,
    this.recipientPhotoUrl,
    this.encodedPolyline,
  });

  final String id;
  final String parcelId;
  final String? trackingCode;

  /// pending | assigned | in_progress | completed | failed | cancelled
  final String status;

  // ── Pickup ──────────────────────────────────────────────────────────────
  final String? pickupType; // 'relay' | 'gps'
  final String? pickupRelayId;
  final String pickupLabel; // texte affiché dans la carte
  final String pickupCity;
  final double? pickupLat;
  final double? pickupLng;

  // ── Livraison ────────────────────────────────────────────────────────────
  final String? deliveryType; // 'relay' | 'gps'
  final String? deliveryRelayId;
  final String deliveryLabel;
  final String deliveryCity;
  final double? deliveryLat;
  final double? deliveryLng;

  // ── Destinataire ─────────────────────────────────────────────────────────
  final String? recipientName;
  final String? recipientPhone;

  // ── Business ─────────────────────────────────────────────────────────────
  final double earnAmount;
  final double? distanceKm; // distance livreur → pickup (null si GPS inconnu)
  final String? driverId;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime? assignedAt;
  final DateTime? completedAt;

  // ── Real-time Navigation ──
  final int? etaSeconds;
  final String? etaText;
  final String? distanceText;
  final String? paymentStatus;
  final String? paymentMethod;
  final String? whoPays;
  final bool paymentOverride;
  final bool deliveryBlockedByPayment;
  final String? pickupVoiceNote;
  final String? deliveryVoiceNote;
  final double driverBonusXof;
  final String? senderPhotoUrl;
  final String? recipientPhotoUrl;
  final String? encodedPolyline;

  factory DeliveryMission.fromJson(Map<String, dynamic> json) {
    // Pickup geopin
    final pg = (json['pickup_geopin'] as Map<String, dynamic>?);
    // Delivery geopin
    final dg = (json['delivery_geopin'] as Map<String, dynamic>?);

    return DeliveryMission(
      id: json['mission_id'] as String? ?? json['id'] as String? ?? '',
      parcelId: json['parcel_id'] as String? ?? '',
      trackingCode: json['tracking_code'] as String?,
      status: json['status'] as String? ?? 'pending',
      pickupType: json['pickup_type'] as String?,
      pickupRelayId: json['pickup_relay_id'] as String?,
      pickupLabel: json['pickup_label'] as String? ?? '—',
      pickupCity: json['pickup_city'] as String? ?? 'Dakar',
      pickupLat: pg?['lat'] != null ? (pg!['lat'] as num).toDouble() : null,
      pickupLng: pg?['lng'] != null ? (pg!['lng'] as num).toDouble() : null,
      deliveryType: json['delivery_type'] as String?,
      deliveryRelayId: json['delivery_relay_id'] as String?,
      deliveryLabel: json['delivery_label'] as String? ?? '—',
      deliveryCity: json['delivery_city'] as String? ?? 'Dakar',
      deliveryLat: dg?['lat'] != null ? (dg!['lat'] as num).toDouble() : null,
      deliveryLng: dg?['lng'] != null ? (dg!['lng'] as num).toDouble() : null,
      recipientName: json['recipient_name'] as String?,
      recipientPhone: json['recipient_phone'] as String?,
      earnAmount: (json['earn_amount'] as num? ?? 0).toDouble(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      driverId: json['driver_id'] as String?,
      failureReason: json['failure_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      assignedAt: json['assigned_at'] != null
          ? DateTime.tryParse(json['assigned_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
      etaSeconds: json['eta_seconds'] as int?,
      etaText: json['eta_text'] as String?,
      distanceText: json['distance_text'] as String?,
      paymentStatus: json['payment_status'] as String?,
      paymentMethod: json['payment_method'] as String?,
      whoPays: json['who_pays'] as String?,
      paymentOverride: json['payment_override'] as bool? ?? false,
      deliveryBlockedByPayment:
          json['delivery_blocked_by_payment'] as bool? ?? false,
      pickupVoiceNote: json['pickup_voice_note'] as String?,
      deliveryVoiceNote: json['delivery_voice_note'] as String?,
      driverBonusXof: (json['driver_bonus_xof'] as num?)?.toDouble() ?? 0.0,
      senderPhotoUrl: json['sender_photo_url'] as String?,
      recipientPhotoUrl: json['recipient_photo_url'] as String?,
      encodedPolyline: json['encoded_polyline'] as String?,
    );
  }

  bool get isPending => status == 'pending';
  bool get isAssigned => status == 'assigned';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  bool get isPaid => paymentStatus == 'paid';
  bool get paymentBlocksDelivery =>
      deliveryBlockedByPayment && !paymentOverride;

  bool get pickupIsRelay => pickupType == 'relay';
  bool get deliveryIsRelay => deliveryType == 'relay';
}
