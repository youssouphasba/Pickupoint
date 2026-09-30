import 'location_policy.dart';

bool supportsClientLiveTracking(String deliveryMode,
        {bool isRecipient = false, bool afterRelayCollection = false}) =>
    deliveryMode == 'home_to_home' ||
    (deliveryMode == 'relay_to_home' && isRecipient && afterRelayCollection);

bool isLiveLocationSnapshot(Map<String, dynamic> data, {DateTime? now}) {
  if (data['available'] != true || data['location'] is! Map) return false;
  final location = data['location'] as Map;
  if (location['lat'] is! num ||
      location['lng'] is! num ||
      !(location['lat'] as num).isFinite ||
      !(location['lng'] as num).isFinite ||
      (location['lat'] as num).abs() > 90 ||
      (location['lng'] as num).abs() > 180) {
    return false;
  }
  final measuredAt =
      DateTime.tryParse(data['location_updated_at']?.toString() ?? '');
  if (measuredAt == null) return false;
  final rawMaxAge = data['max_age_seconds'];
  final maxAge = rawMaxAge is num && rawMaxAge > 0
      ? Duration(seconds: rawMaxAge.toInt())
      : LocationPolicy.current.maxAge;
  final age = (now ?? DateTime.now()).difference(measuredAt);
  return age <= maxAge && age >= -LocationPolicy.current.clockTolerance;
}
