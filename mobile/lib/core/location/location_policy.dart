import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_endpoints.dart';

class LocationPolicy {
  const LocationPolicy({
    this.strictAccuracy = 60,
    this.driverAccuracy = 150,
    this.maxAge = const Duration(seconds: 60),
    this.clockTolerance = const Duration(seconds: 30),
    this.uploadInterval = const Duration(seconds: 15),
    this.heartbeatInterval = const Duration(seconds: 30),
    this.offlineRetention = const Duration(hours: 24),
  });

  final double strictAccuracy;
  final double driverAccuracy;
  final Duration maxAge;
  final Duration clockTolerance;
  final Duration uploadInterval;
  final Duration heartbeatInterval;
  final Duration offlineRetention;

  static LocationPolicy current = const LocationPolicy();
  static Future<void>? _loading;
  static DateTime? _loadedAt;

  static Future<void> refresh() async {
    if (_loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(hours: 1)) {
      return;
    }
    if (_loading != null) return _loading;
    final request = _load();
    _loading = request;
    try {
      await request;
    } finally {
      if (identical(_loading, request)) _loading = null;
    }
  }

  static Future<void> _load() async {
    final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5)));
    try {
      final response = await dio.get(ApiEndpoints.locationPolicy);
      final data = Map<String, dynamic>.from(response.data as Map);
      current = LocationPolicy.fromJson(data);
      _loadedAt = DateTime.now();
    } catch (_) {
    } finally {
      dio.close();
    }
  }

  factory LocationPolicy.fromJson(Map<String, dynamic> data) {
    const fallback = LocationPolicy();
    double positive(String key, double value) {
      final raw = data[key];
      return raw is num && raw.isFinite && raw > 0 ? raw.toDouble() : value;
    }

    Duration seconds(String key, Duration value) =>
        Duration(seconds: positive(key, value.inSeconds.toDouble()).ceil());
    return LocationPolicy(
      strictAccuracy:
          positive('strict_accuracy_meters', fallback.strictAccuracy),
      driverAccuracy:
          positive('driver_accuracy_meters', fallback.driverAccuracy),
      maxAge: seconds('max_age_seconds', fallback.maxAge),
      clockTolerance:
          seconds('clock_tolerance_seconds', fallback.clockTolerance),
      uploadInterval:
          seconds('upload_interval_seconds', fallback.uploadInterval),
      heartbeatInterval:
          seconds('heartbeat_interval_seconds', fallback.heartbeatInterval),
      offlineRetention: Duration(
          hours: positive('offline_buffer_hours',
                  fallback.offlineRetention.inHours.toDouble())
              .ceil()),
    );
  }

  bool accepts(Position position, {bool strict = false, DateTime? now}) {
    now ??= DateTime.now();
    final age = now.difference(position.timestamp);
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude.abs() <= 90 &&
        position.longitude.abs() <= 180 &&
        position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        position.accuracy <= (strict ? strictAccuracy : driverAccuracy) &&
        age <= maxAge &&
        age >= -clockTolerance &&
        !position.isMocked;
  }
}
