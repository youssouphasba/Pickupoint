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
    final rawAddress = json['address'];
    final addr = rawAddress is Map<String, dynamic>
        ? rawAddress
        : <String, dynamic>{
            if (rawAddress is String && rawAddress.trim().isNotEmpty)
              'label': rawAddress.trim(),
          };
    final rawGeopin = addr['geopin'];
    final geopin = rawGeopin is Map<String, dynamic> ? rawGeopin : null;
    final rawOpeningHours = json['opening_hours'];

    return RelayPoint(
      id: json['relay_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Point relais',
      phone: json['phone'] as String? ?? '',
      description: json['description'] as String?,
      openingHours:
          rawOpeningHours is Map<String, dynamic> ? rawOpeningHours : null,
      addressLabel: addr['label'] as String? ??
          addr['district'] as String? ??
          addr['city'] as String? ??
          '',
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
  String get displayName =>
      district != null ? '$name — $district, $city' : '$name — $city';
}
