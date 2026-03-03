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
    this.totalRatingsCount = 0,
  });

  final String id;
  final String phone;

  /// Rôles : 'client' | 'relay_agent' | 'driver' | 'admin'
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
  final int totalRatingsCount;

  /// Nom d'affichage : fullName ou téléphone comme fallback
  String get name => fullName ?? phone;

  /// Utilisateur a besoin d'être redirigé vers l'onboarding ?
  bool get needsOnboarding => fullName == null || fullName!.isEmpty || fullName == phone || userType == null;

  factory User.fromJson(Map<String, dynamic> json) {
    // Le backend renvoie 'user_id' au lieu de 'id'
    final idStr = json['user_id'] as String? ?? json['id'] as String? ?? '';
    
    return User(
      id: idStr,
      phone: json['phone'] as String? ?? '',
      // Le backend renvoie 1 = admin, 2 = client... mais on s'attend à un string ici
      // On le convertit en string si jamais c'est un enum Backend (UserRole.XXX)
      role: json['role']?.toString() ?? 'client',
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
      totalRatingsCount: (json['total_ratings_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': id,
        'phone': phone,
        'role': role,
        'name': fullName,
        'email': email,
        'avatar_url': avatarUrl,
        'relay_point_id': relayPointId,
        'user_type': userType,
        'is_active': isActive,
      };

  bool get isClient     => role == 'client';
  bool get isRelayAgent => role == 'relay_agent';
  bool get isDriver     => role == 'driver';
  bool get isAdmin      => role == 'admin';

  User copyWith({
    String? id,
    String? phone,
    String? role,
    String? fullName,
    String? email,
    String? avatarUrl,
    String? relayPointId,
    bool? isActive,
    bool? isAvailable,
    String? userType,
  }) =>
      User(
        id: id ?? this.id,
        phone: phone ?? this.phone,
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
        totalRatingsCount: totalRatingsCount ?? this.totalRatingsCount,
      );
}
