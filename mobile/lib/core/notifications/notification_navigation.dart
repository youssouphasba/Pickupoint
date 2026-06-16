String? notificationRouteFor({
  required String? refType,
  required String? refId,
  required String role,
}) {
  final normalizedRefType = (refType ?? '').trim().toLowerCase();
  final normalizedRefId = (refId ?? '').trim();
  final normalizedRole = role.trim().toLowerCase();

  if (normalizedRefId.isEmpty) {
    return null;
  }

  if (normalizedRefType == 'mission' && normalizedRole == 'driver') {
    return '/driver/mission/$normalizedRefId';
  }

  if (normalizedRefType == 'parcel') {
    if (normalizedRole == 'client') {
      return '/client/parcel/$normalizedRefId';
    }
    if (normalizedRole == 'admin' || normalizedRole == 'superadmin') {
      return '/admin/parcels/$normalizedRefId/audit';
    }
  }

  if (normalizedRole == 'driver') {
    return '/driver/notifications';
  }
  if (normalizedRole == 'client') {
    return '/client/notifications';
  }
  if (normalizedRole == 'relay_agent') {
    return '/relay/notifications';
  }
  if (normalizedRole == 'admin' || normalizedRole == 'superadmin') {
    return '/admin/notifications';
  }

  return null;
}
