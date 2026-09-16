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
  final String addressLabel;
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
    final rawAddress = json['address'];
    final addr = rawAddress is Map
        ? Map<String, dynamic>.from(rawAddress)
        : <String, dynamic>{
            if (rawAddress is String && rawAddress.trim().isNotEmpty)
              'label': rawAddress.trim(),
          };
    final rawGeopin = addr['geopin'];
    final geopin = rawGeopin is Map ? Map<String, dynamic>.from(rawGeopin) : null;
    final rawOpeningHours = json['opening_hours'];
    final addressLabel = [
      addr['label'],
      addr['formatted_address'],
      addr['address_line'],
      addr['full_address'],
      addr['display_name'],
      addr['address'],
      addr['street'],
      addr['notes'],
    ].map((value) => value is String ? value.trim() : '').firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );

    return RelayPoint(
      id: json['relay_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Point relais',
      phone: json['phone'] as String? ?? '',
      description: json['description'] as String?,
      openingHours: rawOpeningHours is Map
          ? Map<String, dynamic>.from(rawOpeningHours)
          : null,
      addressLabel: addressLabel,
      city: addr['city'] as String? ?? '',
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

  String get displayName {
    final parts = <String>[
      if (addressLabel.trim().isNotEmpty) addressLabel.trim(),
      if (district != null && district!.trim().isNotEmpty) district!.trim(),
      if (city.trim().isNotEmpty) city.trim(),
    ].fold<List<String>>([], (unique, value) {
      if (!unique.any((entry) => entry.toLowerCase() == value.toLowerCase())) {
        unique.add(value);
      }
      return unique;
    });
    return parts.isEmpty ? name : '$name — ${parts.join(', ')}';
  }
}
