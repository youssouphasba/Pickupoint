String? notificationRouteFor({
  required String? refType,
  required String? refId,
  required String role,
  String? eventType,
  String? targetView,
  String? messageId,
}) {
  final type = (refType ?? '').trim().toLowerCase();
  final id = (refId ?? '').trim();
  final action = (eventType ?? '').trim().toLowerCase();
  final effectiveRole = (targetView ?? role).trim().toLowerCase();
  final encodedId = Uri.encodeComponent(id);
  final encodedMessageId = Uri.encodeComponent((messageId ?? '').trim());

  switch (action) {
    case 'mission_available':
      return id.isEmpty ? '/driver' : '/driver?preview=$encodedId';
    case 'mission_detail':
      return id.isEmpty ? '/driver' : '/driver/mission/$encodedId';
    case 'mission_unavailable':
      return id.isEmpty ? '/driver' : '/driver?unavailable=$encodedId';
    case 'parcel_detail':
      if (id.isEmpty) return null;
      if (effectiveRole == 'admin' || effectiveRole == 'superadmin') {
        return '/admin/parcels/$encodedId/audit';
      }
      return '/client/parcel/$encodedId';
    case 'parcel_message':
      if (id.isEmpty) return null;
      final query =
          encodedMessageId.isEmpty ? '' : '?message=$encodedMessageId';
      if (effectiveRole == 'driver') {
        return '/driver/mission/$encodedId$query';
      }
      return '/client/parcel/$encodedId$query';
    case 'relay_scan_in':
      return id.isEmpty ? '/relay/scan-in' : '/relay/scan-in?parcel=$encodedId';
    case 'wallet':
      return effectiveRole == 'relay_agent'
          ? '/relay/wallet'
          : '/driver/wallet';
    case 'application_status':
      return '/client/profile?section=application';
  }

  if (id.isEmpty) return null;

  if (type == 'mission' && effectiveRole == 'driver') {
    return '/driver?preview=$encodedId';
  }
  if (type == 'parcel') {
    if (effectiveRole == 'admin' || effectiveRole == 'superadmin') {
      return '/admin/parcels/$encodedId/audit';
    }
    if (effectiveRole == 'client') {
      return '/client/parcel/$encodedId';
    }
  }

  return switch (effectiveRole) {
    'driver' => '/driver/notifications',
    'client' => '/client/notifications',
    'relay_agent' => '/relay/notifications',
    'admin' || 'superadmin' => '/admin',
    _ => null,
  };
}

int notificationPlatformId(Map<String, dynamic> data) {
  final dedupeKey = data['dedupe_key']?.toString().trim() ?? '';
  final key = dedupeKey.isNotEmpty
      ? dedupeKey
      : [
          data['event_type'],
          data['ref_type'],
          data['ref_id'],
        ]
          .map((value) => value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .join(':');

  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
