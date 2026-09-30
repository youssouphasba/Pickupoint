import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DriverTracePoint {
  const DriverTracePoint(this.missionId, this.body);
  final String missionId;
  final Map<String, dynamic> body;
  DateTime? get capturedAt =>
      DateTime.tryParse(body['captured_at']?.toString() ?? '');
}

class DriverTraceBuffer {
  DriverTraceBuffer({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
                aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final FlutterSecureStorage _storage;
  static const _key = 'driver_pending_gps_trace_v1';
  Future<void> _writes = Future.value();

  Future<List<DriverTracePoint>> load(String userId) async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return [];
      final data = jsonDecode(raw) as Map;
      if (data['user_id'] != userId) return [];
      return (data['points'] as List? ?? [])
          .whereType<Map>()
          .map((p) => DriverTracePoint(p['mission_id'] as String,
              Map<String, dynamic>.from(p['body'] as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(String? userId, List<DriverTracePoint> points) {
    final snapshot = jsonEncode({
      'user_id': userId,
      'points': points
          .map((p) => {'mission_id': p.missionId, 'body': p.body})
          .toList()
    });
    final empty = points.isEmpty;
    final write = _writes.then((_) async {
      if (userId == null || empty) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: snapshot);
      }
    });
    _writes = write.catchError((Object _) {});
    return _writes;
  }
}
