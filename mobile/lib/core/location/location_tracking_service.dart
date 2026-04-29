import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../auth/auth_provider.dart';
import '../../features/driver/providers/driver_provider.dart';

final locationTrackingServiceProvider =
    Provider((ref) => LocationTrackingService(ref));

class LocationTrackingService {
  final Ref _ref;
  StreamSubscription<Position>? _subscription;
  String? _currentMissionId;
  DateTime? _lastUpdate;

  LocationTrackingService(this._ref) {
    // Observer les missions du livreur pour démarrer/arrêter le tracking automatiquement
    _ref.listen(myMissionsProvider, (previous, next) {
      final missions = next.valueOrNull ?? [];
      final activeMission = missions.firstWhere(
        (m) =>
            m.status == 'assigned' ||
            m.status == 'in_progress' ||
            m.status == 'incident_reported',
        orElse: () => missions.firstWhere(
          (m) => false, // dummy orElse
          orElse: () => null as dynamic,
        ),
      );

      if (activeMission != null) {
        startTracking(activeMission.id);
      } else {
        stopTracking();
      }
    });
  }

  Future<void> startTracking(String missionId) async {
    if (_currentMissionId == missionId && _subscription != null) return;

    await stopTracking();
    _currentMissionId = missionId;

    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "Livraison en cours",
          notificationText: "Votre position est partagee avec le client.",
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
        ),
      );
    } else {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: true,
      );
    }

    _subscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((pos) async {
      final now = DateTime.now();
      if (_lastUpdate == null ||
          now.difference(_lastUpdate!).inSeconds >= 10) {
        _lastUpdate = now;
        try {
          await _ref.read(apiClientProvider).updateLocation(missionId, {
            'lat': pos.latitude,
            'lng': pos.longitude,
            'accuracy': pos.accuracy,
          });
          // On peut invalider la mission pour rafraîchir l'ETA si on est sur l'écran
          _ref.invalidate(missionProvider(missionId));
        } catch (_) {}
      }
    });
  }

  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;
    _currentMissionId = null;
  }
}
