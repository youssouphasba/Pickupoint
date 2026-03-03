class RelayPoint {
  const RelayPoint({
    required this.id,
    required this.name,
    required this.phone,
    required this.addressLabel,
    required this.city,
    required this.agentId,
    this.description,
    this.openingHours,
    this.lat,
    this.lng,
    this.district,
    this.capacity = 20,
    this.currentStock = 0,
    this.isVerified = false,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String phone;
  final String? description;
  final Map<String, dynamic>? openingHours;
  final String addressLabel; // address.label ou address.district
  final String city;
  final String agentId;
  final double? lat;
  final double? lng;
  final String? district;
  final int capacity;
  final int currentStock;
  final bool isVerified;
  final bool isActive;

  factory RelayPoint.fromJson(Map<String, dynamic> json) {
    // address est un objet { label, city, district, geopin: {lat, lng} }
    final addr = json['address'] as Map<String, dynamic>? ?? {};
    final geopin = addr['geopin'] as Map<String, dynamic>?;

    return RelayPoint(
      id: json['relay_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String? ?? '',
      description: json['description'] as String?,
      openingHours: json['opening_hours'] as Map<String, dynamic>?,
      addressLabel: addr['label'] as String?
          ?? addr['district'] as String?
          ?? addr['city'] as String?
          ?? '',
      city: addr['city'] as String? ?? 'Dakar',
      district: addr['district'] as String?,
      agentId: json['owner_user_id'] as String? ?? '',
      lat: (geopin?['lat'] as num?)?.toDouble(),
      lng: (geopin?['lng'] as num?)?.toDouble(),
      capacity: json['max_capacity'] as int? ?? 20,
      currentStock: json['current_load'] as int? ?? 0,
      isVerified: json['is_verified'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  int get availableSlots => capacity - currentStock;
  bool get isFull => currentStock >= capacity;

  /// Affichage dans les dropdowns
  String get displayName => district != null
      ? '$name — $district, $city'
      : '$name — $city';
}
