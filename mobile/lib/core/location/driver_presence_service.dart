import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/auth_provider.dart';
import 'driver_location_consent.dart';

final driverPresenceServiceProvider = Provider<DriverPresenceService>((ref) {
  final service = DriverPresenceService(ref);
  ref.listen(authProvider, (_, next) {
    service.reconcile(next.valueOrNull);
  });
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

class DriverPresenceService {
  DriverPresenceService(this._ref);

  final Ref _ref;
  StreamSubscription<Position>? _subscription;
  DateTime? _lastUpload;
  bool _started = false;
  bool _starting = false;

  Future<void> start() async {
    _started = true;
    await reconcile(_ref.read(authProvider).valueOrNull);
  }

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await reconcile(_ref.read(authProvider).valueOrNull, forceUpload: true);
    }
  }

  Future<void> reconcile(
    AuthState? auth, {
    bool forceUpload = false,
  }) async {
    if (!_started) return;
    final user = auth?.user;
    final shouldTrack = auth?.isAuthenticated == true &&
        user?.role == 'driver' &&
        user?.isAvailable == true;
    if (!shouldTrack) {
      await _stop();
      return;
    }

    if (_subscription == null) {
      await _startTracking();
    } else if (forceUpload) {
      await _uploadFreshPosition();
    }
  }

  Future<void> _startTracking() async {
    if (_starting || _subscription != null) return;
    _starting = true;
    try {
      if (!await DriverLocationConsent.hasAccepted()) return;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return;
      }

      final LocationSettings settings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
          intervalDuration: const Duration(seconds: 45),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Denkma livreur disponible',
            notificationText:
                'Votre zone est actualisée pour recevoir les courses proches.',
            notificationIcon: AndroidResource(
              name: 'ic_launcher',
              defType: 'mipmap',
            ),
            enableWakeLock: true,
          ),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        settings = AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 25,
          activityType: ActivityType.otherNavigation,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      } else {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        );
      }

      _subscription = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen(_uploadPosition);
      await _uploadFreshPosition();
    } finally {
      _starting = false;
    }
  }

  Future<void> _uploadFreshPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));
      await _uploadPosition(position, force: true);
    } catch (_) {}
  }

  Future<void> _uploadPosition(
    Position position, {
    bool force = false,
  }) async {
    if (position.accuracy > 500) return;
    final now = DateTime.now();
    if (!force &&
        _lastUpload != null &&
        now.difference(_lastUpload!).inSeconds < 45) {
      return;
    }
    _lastUpload = now;
    try {
      await _ref.read(apiClientProvider).updateMyDriverLocation({
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
      });
    } catch (_) {
      _lastUpload = null;
    }
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _lastUpload = null;
  }

  Future<void> dispose() => _stop();
}
