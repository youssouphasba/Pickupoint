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
    this.addressNotes,
    this.capacity = 20,
    this.currentStock = 0,
    this.isVerified = false,
    this.isActive = true,
    this.isOpen = true,
    this.openingStatusKnown = false,
    this.openingStatusLabel,
    this.locationChangeRequest,
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
  final String? addressNotes;
  final int capacity;
  final int currentStock;
  final bool isVerified;
  final bool isActive;
  final bool isOpen;
  final bool openingStatusKnown;
  final String? openingStatusLabel;
  final Map<String, dynamic>? locationChangeRequest;

  factory RelayPoint.fromJson(Map<String, dynamic> json) {
    final rawAddress = json['address'];
    final addr = rawAddress is Map
        ? Map<String, dynamic>.from(rawAddress)
        : <String, dynamic>{
            if (rawAddress is String && rawAddress.trim().isNotEmpty)
              'label': rawAddress.trim(),
          };
    final rawGeopin = addr['geopin'];
    final geopin =
        rawGeopin is Map ? Map<String, dynamic>.from(rawGeopin) : null;
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
          : rawOpeningHours is String && rawOpeningHours.trim().isNotEmpty
              ? {'general': rawOpeningHours.trim()}
              : null,
      addressLabel: addressLabel,
      city: addr['city'] as String? ?? json['city'] as String? ?? '',
      district: addr['district'] as String?,
      addressNotes: addr['notes'] as String?,
      agentId: json['owner_user_id'] as String? ?? '',
      lat: _coordinate(
          geopin?['lat'] ?? addr['latitude'] ?? json['latitude'] ?? json['lat'],
          90),
      lng: _coordinate(
          geopin?['lng'] ??
              addr['longitude'] ??
              json['longitude'] ??
              json['lng'],
          180),
      capacity: json['max_capacity'] as int? ?? 20,
      currentStock: json['current_load'] as int? ?? 0,
      isVerified: json['is_verified'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      isOpen: json['is_open'] as bool? ??
          (json['opening_status'] is Map
              ? json['opening_status']['is_open'] as bool? ?? true
              : true),
      openingStatusKnown: json['opening_status'] is Map
          ? json['opening_status']['known'] as bool? ?? false
          : false,
      openingStatusLabel: json['opening_status'] is Map
          ? json['opening_status']['label']?.toString()
          : null,
      locationChangeRequest: json['location_change_request'] is Map
          ? Map<String, dynamic>.from(json['location_change_request'] as Map)
          : null,
    );
  }

  static double? _coordinate(dynamic value, double bound) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    return number != null && number.isFinite && number.abs() <= bound
        ? number
        : null;
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
