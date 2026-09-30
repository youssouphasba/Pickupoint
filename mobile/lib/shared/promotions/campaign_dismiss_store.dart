import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CampaignDismissStore {
  static const _storage = FlutterSecureStorage();
  static Future<void> _pendingWrite = Future.value();

  static Future<Set<String>> read(String userId) async {
    final raw = await _storage.read(key: 'campaign_dismissals:$userId');
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).whereType<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> dismiss(String userId, String campaignId) {
    final operation = _pendingWrite.then((_) async {
      final ids = await read(userId);
      ids.add(campaignId);
      await _storage.write(
          key: 'campaign_dismissals:$userId', value: jsonEncode(ids.toList()));
    });
    _pendingWrite = operation.catchError((_) {});
    return operation;
  }
}
