class User {
  const User({
    required this.id,
    required this.phone,
    required this.role,
    this.fullName,
    this.email,
    this.avatarUrl,
    this.relayPointId,
    this.isActive = true,
    this.isAvailable = false,
    this.userType,
    this.xp = 0,
    this.level = 1,
    this.badges = const [],
    this.deliveriesCompleted = 0,
    this.onTimeDeliveries = 0,
    this.averageRating = 0.0,
    this.totalEarned = 0.0,
    this.totalRatingsCount = 0,
    this.loyaltyPoints = 0,
    this.loyaltyTier = 'bronze',
    this.referralCode = '',
    this.isBanned = false,
    this.acceptedLegal = false,
    this.acceptedLegalAt,
    this.bio,
    this.kycStatus = 'none',
    this.kycIdCardUrl,
    this.kycLicenseUrl,
    this.profilePictureUrl,
    this.favoriteAddresses = const [],
    this.notificationPrefs = const NotificationPrefs(),
  });

  final String id;
  final String phone;

  /// Rôles : 'client' | 'relay_agent' | 'driver' | 'admin'
  final String? profilePictureUrl;
  final String role;
  final String? fullName;
  final String? email;
  final String? avatarUrl;
  final String? relayPointId;
  final bool isActive;
  final bool isAvailable;
  final String? userType;
  final int xp;
  final int level;
  final List<String> badges;
  final int deliveriesCompleted;
  final int onTimeDeliveries;
  final double averageRating;
  final double totalEarned;
  final int totalRatingsCount;
  final int loyaltyPoints;
  final String loyaltyTier;
  final String referralCode;
  final bool isBanned;
  final bool acceptedLegal;
  final DateTime? acceptedLegalAt;
  final String? bio;
  final String kycStatus;
  final String? kycIdCardUrl;
  final String? kycLicenseUrl;
  final List<FavoriteAddress> favoriteAddresses;
  final NotificationPrefs notificationPrefs;

  /// Nom d'affichage : fullName ou téléphone comme fallback
  String get name => fullName ?? phone;

  /// Utilisateur a besoin d'être redirigé vers l'onboarding ?
  bool get needsOnboarding => fullName == null || fullName!.isEmpty || fullName == phone;

  factory User.fromJson(Map<String, dynamic> json) {
    // Le backend renvoie 'user_id' au lieu de 'id'
    final idStr = json['user_id'] as String? ?? json['id'] as String? ?? '';
    
    return User(
      id: idStr,
      phone: json['phone'] as String? ?? '',
      // Le backend renvoie 1 = admin, 2 = client... mais on s'attend à un string ici
      // On le convertit en string si jamais c'est un enum Backend (UserRole.XXX)
      role: json['role']?.toString() ?? 'client',
      profilePictureUrl: json['profile_picture_url'] as String?, // Added this line
      fullName: json['name'] as String? ?? json['full_name'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      relayPointId: json['relay_point_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isAvailable: json['is_available'] as bool? ?? false,
      userType: json['user_type'] as String?,
      xp: (json['xp'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
      badges: (json['badges'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      deliveriesCompleted: (json['deliveries_completed'] as num?)?.toInt() ?? 0,
      onTimeDeliveries: (json['on_time_deliveries'] as num?)?.toInt() ?? 0,
      averageRating: (json['average_rating'] as num?)?.toDouble() ?? 0.0,
      totalEarned: (json['total_earned'] as num?)?.toDouble() ?? 0.0,
      totalRatingsCount: (json['total_ratings_count'] as num?)?.toInt() ?? 0,
      loyaltyPoints: (json['loyalty_points'] as num?)?.toInt() ?? 0,
      loyaltyTier: json['loyalty_tier'] as String? ?? 'bronze',
      referralCode: json['referral_code'] as String? ?? '',
      isBanned: json['is_banned'] as bool? ?? false,
      acceptedLegal: json['accepted_legal'] as bool? ?? false,
      acceptedLegalAt: json['accepted_legal_at'] != null ? DateTime.parse(json['accepted_legal_at'] as String) : null,
      bio: json['bio'] as String?,
      kycStatus: json['kyc_status'] as String? ?? 'none',
      kycIdCardUrl: json['kyc_id_card_url'] as String?,
      kycLicenseUrl: json['kyc_license_url'] as String?,
      favoriteAddresses: (json['favorite_addresses'] as List<dynamic>?)
              ?.map((e) => FavoriteAddress.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      notificationPrefs: json['notification_prefs'] != null
          ? NotificationPrefs.fromJson(json['notification_prefs'] as Map<String, dynamic>)
          : const NotificationPrefs(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': id,
        'phone': phone,
        'profile_picture_url': profilePictureUrl,
      'role': role,
        'name': fullName,
        'email': email,
        'avatar_url': avatarUrl,
        'relay_point_id': relayPointId,
        'user_type': userType,
        'is_active': isActive,
        'is_banned': isBanned,
        'bio': bio,
        'notification_prefs': notificationPrefs.toJson(),
      };

  bool get isClient     => role == 'client';
  bool get isRelayAgent => role == 'relay_agent';
  bool get isDriver     => role == 'driver';
  bool get isAdmin      => role == 'admin';

  User copyWith({
    String? id,
    String? phone,
    String? profilePictureUrl, // Added this line
    String? role,
    String? fullName,
    String? email,
    String? avatarUrl,
    String? relayPointId,
    bool? isActive,
    bool? isAvailable,
    String? userType,
    int? xp,
    int? level,
    List<String>? badges,
    int? deliveriesCompleted,
    int? onTimeDeliveries,
    double? averageRating,
    double? totalEarned,
    int? totalRatingsCount,
    int? loyaltyPoints,
    String? loyaltyTier,
    String? referralCode,
    bool? isBanned,
    bool? acceptedLegal,
    DateTime? acceptedLegalAt,
    String? bio,
    String? kycStatus,
    String? kycIdCardUrl,
    String? kycLicenseUrl,
    List<FavoriteAddress>? favoriteAddresses,
    NotificationPrefs? notificationPrefs,
  }) =>
      User(
        id: id ?? this.id,
        phone: phone ?? this.phone,
        profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      role: role ?? this.role,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        relayPointId: relayPointId ?? this.relayPointId,
        isActive: isActive ?? this.isActive,
        isAvailable: isAvailable ?? this.isAvailable,
        userType: userType ?? this.userType,
        xp: xp ?? this.xp,
        level: level ?? this.level,
        badges: badges ?? this.badges,
        deliveriesCompleted: deliveriesCompleted ?? this.deliveriesCompleted,
        onTimeDeliveries: onTimeDeliveries ?? this.onTimeDeliveries,
        averageRating: averageRating ?? this.averageRating,
        totalEarned: totalEarned ?? this.totalEarned,
        totalRatingsCount: totalRatingsCount ?? this.totalRatingsCount,
        loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
        loyaltyTier: loyaltyTier ?? this.loyaltyTier,
        referralCode: referralCode ?? this.referralCode,
        isBanned: isBanned ?? this.isBanned,
        acceptedLegal: acceptedLegal ?? this.acceptedLegal,
        acceptedLegalAt: acceptedLegalAt ?? this.acceptedLegalAt,
        bio: bio ?? this.bio,
        kycStatus: kycStatus ?? this.kycStatus,
        kycIdCardUrl: kycIdCardUrl ?? this.kycIdCardUrl,
        kycLicenseUrl: kycLicenseUrl ?? this.kycLicenseUrl,
        favoriteAddresses: favoriteAddresses ?? this.favoriteAddresses,
        notificationPrefs: notificationPrefs ?? this.notificationPrefs,
      );
}

class FavoriteAddress {
  final String name;
  final String address;
  final double lat;
  final double lng;

  const FavoriteAddress({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  factory FavoriteAddress.fromJson(Map<String, dynamic> json) => FavoriteAddress(
        name: json['name'] as String? ?? '',
        address: json['address'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
      };
}

class NotificationPrefs {
  final bool pushEnabled;
  final bool emailEnabled;
  final bool whatsappEnabled;

  const NotificationPrefs({
    this.pushEnabled = true,
    this.emailEnabled = true,
    this.whatsappEnabled = true,
  });

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) => NotificationPrefs(
        pushEnabled: json['push'] as bool? ?? true,
        emailEnabled: json['email'] as bool? ?? true,
        whatsappEnabled: json['whatsapp'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'push': pushEnabled,
        'email': emailEnabled,
        'whatsapp': whatsappEnabled,
      };
}
