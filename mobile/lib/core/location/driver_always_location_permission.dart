import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

class DriverAlwaysLocationPermission {
  static const _channel =
      MethodChannel('com.denkma.app/driver_location_permission');
  static Future<LocationPermission>? _pendingRequest;

  static Future<LocationPermission> requestUpgrade() async {
    final permission = await Geolocator.checkPermission();
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        permission != LocationPermission.whileInUse) {
      return permission;
    }
    final pending = _pendingRequest;
    if (pending != null) return pending;
    final request = _request();
    _pendingRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_pendingRequest, request)) _pendingRequest = null;
    }
  }

  static Future<LocationPermission> _request() async {
    try {
      await _channel.invokeMethod<bool>('requestAlwaysAuthorization');
    } on MissingPluginException {
      return Geolocator.checkPermission();
    } on PlatformException {
      return Geolocator.checkPermission();
    }
    return Geolocator.checkPermission();
  }
}
