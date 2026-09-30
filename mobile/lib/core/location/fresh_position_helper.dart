import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'location_policy.dart';

class FreshPositionHelper {
  static double get strictMaxAccuracyMeters =>
      LocationPolicy.current.strictAccuracy;
  static double get driverSearchMaxAccuracyMeters =>
      LocationPolicy.current.driverAccuracy;

  static Future<void> ensureLocationAccess(
      {bool requestPermission = true}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const _LocationError(
        'Activez la localisation pour continuer.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const _LocationError(
        'Autorisez la localisation pour continuer.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const _LocationError(
        'La localisation est bloquée dans les réglages du téléphone.',
      );
    }
  }

  static Future<Position> getStrictFreshPosition({
    String context = 'cette action',
  }) {
    return _resolveFreshPosition(
      maxAccuracyMeters: strictMaxAccuracyMeters,
      attempts: 3,
      timeoutPerAttempt: const Duration(seconds: 12),
      desiredAccuracy: LocationAccuracy.bestForNavigation,
      failureMessage:
          'Position trop imprécise pour $context. Attendez une meilleure précision puis réessayez.',
    );
  }

  static Future<Position> getDriverSearchPosition() {
    return _resolveFreshPosition(
      maxAccuracyMeters: driverSearchMaxAccuracyMeters,
      attempts: 1,
      timeoutPerAttempt: const Duration(seconds: 10),
      desiredAccuracy: LocationAccuracy.high,
      failureMessage:
          'Localisation indisponible ou trop imprécise. Vérifiez le GPS puis réessayez.',
    );
  }

  static Future<Position> getDriverPresencePosition() {
    return _resolveFreshPosition(
      maxAccuracyMeters: driverSearchMaxAccuracyMeters,
      attempts: 1,
      timeoutPerAttempt: const Duration(seconds: 8),
      desiredAccuracy: LocationAccuracy.high,
      failureMessage:
          'Localisation indisponible. Vérifiez le GPS puis réessayez.',
      requestPermission: false,
    );
  }

  static Future<Position> _resolveFreshPosition({
    required double maxAccuracyMeters,
    required int attempts,
    required Duration timeoutPerAttempt,
    required LocationAccuracy desiredAccuracy,
    required String failureMessage,
    bool requestPermission = true,
  }) async {
    await ensureLocationAccess(requestPermission: requestPermission);
    await LocationPolicy.refresh();
    maxAccuracyMeters = desiredAccuracy == LocationAccuracy.bestForNavigation
        ? LocationPolicy.current.strictAccuracy
        : LocationPolicy.current.driverAccuracy;

    Position? bestPosition;
    Object? lastError;
    for (var index = 0; index < attempts; index++) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: desiredAccuracy,
          timeLimit: timeoutPerAttempt,
        ).timeout(timeoutPerAttempt);
        final age = DateTime.now().difference(position.timestamp);
        if (age > LocationPolicy.current.maxAge ||
            age < -LocationPolicy.current.clockTolerance ||
            position.isMocked ||
            !position.accuracy.isFinite ||
            position.accuracy < 0) {
          lastError = const _LocationError(
              'La mesure GPS n’est pas exploitable ou n’est pas récente. Relancez la localisation.');
          continue;
        }
        if (bestPosition == null || position.accuracy < bestPosition.accuracy) {
          bestPosition = position;
        }
        if (position.accuracy <= maxAccuracyMeters &&
            LocationPolicy.current.accepts(position,
                strict:
                    desiredAccuracy == LocationAccuracy.bestForNavigation)) {
          return position;
        }
      } on TimeoutException catch (error) {
        lastError = error;
      } catch (error) {
        lastError = error;
      }

      if (index < attempts - 1) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }

    final measuredAccuracy = bestPosition?.accuracy;
    if (measuredAccuracy != null) {
      throw _LocationError(
        '$failureMessage (précision actuelle : ${measuredAccuracy.round()} m).',
      );
    }
    if (lastError != null) {
      if (lastError is _LocationError) throw lastError;
      throw _LocationError(failureMessage);
    }
    throw _LocationError(failureMessage);
  }
}

class _LocationError implements Exception {
  const _LocationError(this.message);

  final String message;

  @override
  String toString() => message;
}
