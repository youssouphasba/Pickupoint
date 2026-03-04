class ParcelEvent {
  const ParcelEvent({
    required this.id,
    required this.parcelId,
    required this.eventType,
    required this.status,
    required this.createdAt,
    this.note,
    this.actorId,
  });

  final String id;
  final String parcelId;
  final String eventType;
  final String status; // valeur de to_status
  final DateTime createdAt;
  final String? note;
  final String? actorId;

  factory ParcelEvent.fromJson(Map<String, dynamic> json) => ParcelEvent(
        id: json['event_id'] as String? ?? json['id'] as String? ?? '',
        parcelId: json['parcel_id'] as String? ?? '',
        eventType: json['event_type'] as String? ?? '',
        // to_status contient le nouveau statut
        status: (json['to_status'] ?? json['status'] ?? '') as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        note: json['notes'] as String?,
        actorId: json['actor_id'] as String?,
      );
}

class Parcel {
  const Parcel({
    required this.id,
    required this.trackingCode,
    required this.status,
    required this.deliveryMode,
    required this.senderId,
    required this.createdAt,
    this.originRelayId,
    this.destinationRelayId,
    this.senderName,
    this.recipientName,
    this.recipientPhone,
    this.destinationAddress,
    this.destinationLat,
    this.destinationLng,
    this.weightKg,
    this.declaredValue,
    this.hasInsurance = false,
    this.totalPrice,
    this.paymentStatus,
    this.externalRef,
    this.events = const [],
    this.assignedDriverId,
    this.initiatedBy = 'sender',
    this.deliveryConfirmed = false,
    this.pickupConfirmed = false,
    this.deliveryLocation,
    this.pickupLocation,
    this.deliveryCode,
    this.pinCode,
    this.pickupCode,
    this.deliveryLat,
    this.deliveryLng,
    this.rating,
    this.ratingComment,
    this.driverTip = 0.0,
    this.recipientConfirmUrl,
    this.isRecipientView,
    this.promoId,
  });

  final String id;
  final String trackingCode;
  final String status;
  final String deliveryMode;
  final String senderId;
  final String? originRelayId;
  final String? destinationRelayId;
  final String? senderName;
  final String? recipientName;
  final String? recipientPhone;
  final String? destinationAddress;
  final double? destinationLat;
  final double? destinationLng;
  final double? weightKg;
  final double? declaredValue;
  final bool hasInsurance;
  final double? totalPrice;
  final String? paymentStatus;
  final String? externalRef;
  final List<ParcelEvent> events;
  final String? assignedDriverId;
  final DateTime createdAt;
  // Confirmation GPS bidirectionnelle
  final String initiatedBy;
  final bool deliveryConfirmed;
  final bool pickupConfirmed;
  final Map<String, dynamic>? deliveryLocation;  // {lat, lng, accuracy}
  final Map<String, dynamic>? pickupLocation;
  final String? deliveryCode; // code que le destinataire donne au livreur (domicile)
  final String? pinCode;      // code que le destinataire donne au relais (retrait relais)
  final String? pickupCode;   // code que l'expéditeur donne au livreur (H2R / H2H)
  final double? deliveryLat;
  final double? deliveryLng;
  final int? rating;
  final String? ratingComment;
  final double driverTip;
  final String? recipientConfirmUrl;
  /// Calculé côté backend : true si le viewer est le destinataire
  final bool? isRecipientView;
  final String? promoId;

  factory Parcel.fromJson(Map<String, dynamic> json) {
    // delivery_address est un objet Address { label, city, geopin:{lat,lng} }
    final deliveryAddr = json['delivery_address'] as Map<String, dynamic>?;
    final geopin = deliveryAddr?['geopin'] as Map<String, dynamic>?;

    return Parcel(
      id: json['parcel_id'] as String? ?? json['id'] as String? ?? '',
      trackingCode: json['tracking_code'] as String? ?? '',
      status: (json['status'] is String
              ? json['status']
              : (json['status'] as Map?)?['value'] ?? 'created')
          as String,
      deliveryMode: (json['delivery_mode'] is String
              ? json['delivery_mode']
              : (json['delivery_mode'] as Map?)?['value'] ?? 'relay_to_relay')
          as String,
      senderId: json['sender_user_id'] as String? ?? '',
      senderName: json['sender_name'] as String?,
      originRelayId: json['origin_relay_id'] as String?,
      destinationRelayId: json['destination_relay_id'] as String?,
      recipientName: json['recipient_name'] as String?,
      recipientPhone: json['recipient_phone'] as String?,
      destinationAddress: deliveryAddr?['label'] as String?
          ?? deliveryAddr?['district'] as String?,
      destinationLat: (geopin?['lat'] as num?)?.toDouble(),
      destinationLng: (geopin?['lng'] as num?)?.toDouble(),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      declaredValue: (json['declared_value'] as num?)?.toDouble(),
      hasInsurance: json['is_insured'] as bool? ?? false,
      totalPrice: (json['quoted_price'] as num?)?.toDouble()
          ?? (json['paid_price'] as num?)?.toDouble(),
      paymentStatus: json['payment_status'] as String?,
      externalRef: json['external_ref'] as String?,
      events: (json['events'] as List<dynamic>?)
              ?.map((e) => ParcelEvent.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      assignedDriverId: json['assigned_driver_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      initiatedBy: json['initiated_by'] as String? ?? 'sender',
      deliveryConfirmed: json['delivery_confirmed'] as bool? ?? false,
      pickupConfirmed: json['pickup_confirmed'] as bool? ?? false,
      deliveryLocation: json['delivery_location'] as Map<String, dynamic>?,
      pickupLocation: json['pickup_location'] as Map<String, dynamic>?,
      deliveryCode: json['delivery_code'] as String?,
      pinCode:      json['relay_pin'] as String? ?? json['pin_code'] as String?,
      pickupCode:   json['pickup_code'] as String?,
      deliveryLat: (json['delivery_address'] as Map<String,dynamic>?)?['geopin'] != null
          ? ((json['delivery_address']['geopin']['lat']) as num?)?.toDouble()
          : null,
      deliveryLng: (json['delivery_address'] as Map<String,dynamic>?)?['geopin'] != null
          ? ((json['delivery_address']['geopin']['lng']) as num?)?.toDouble()
          : null,
      rating: json['rating'] as int?,
      ratingComment: json['rating_comment'] as String?,
      driverTip: (json['driver_tip'] as num?)?.toDouble() ?? 0.0,
      recipientConfirmUrl: json['recipient_confirm_url'] as String?,
      isRecipientView: json['is_recipient'] as bool?,
      promoId: json['promo_id'] as String?,
    );
  }

  bool get canBeCancelled => status == 'created';
  bool get isDelivered     => status == 'delivered';
  bool get isRelayToHome   => deliveryMode == 'relay_to_home';
}

class QuoteResponse {
  const QuoteResponse({
    required this.price,
    required this.currency,
    this.breakdown = const {},
  });

  final double price;
  final String currency;
  final Map<String, dynamic> breakdown;
  final double? originalPrice;
  final double discountXof;
  final Map<String, dynamic>? promoApplied;

  factory QuoteResponse.fromJson(Map<String, dynamic> json) => QuoteResponse(
        // Backend retourne { price, currency, breakdown }
        price: (json['price'] as num).toDouble(),
        currency: json['currency'] as String? ?? 'XOF',
        breakdown: json['breakdown'] as Map<String, dynamic>? ?? {},
        originalPrice: (json['original_price'] as num?)?.toDouble(),
        discountXof: (json['discount_xof'] as num?)?.toDouble() ?? 0.0,
        promoApplied: json['promo_applied'] as Map<String, dynamic>?,
      );

  double get base      => (breakdown['base'] as num?)?.toDouble() ?? price;
  double get weight    => (breakdown['weight'] as num?)?.toDouble() ?? 0;
  double get insurance => (breakdown['insurance'] as num?)?.toDouble() ?? 0;
}
