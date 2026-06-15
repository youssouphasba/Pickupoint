import 'dart:async';

import 'package:geolocator/geolocator.dart';

class FreshPositionHelper {
  static const double strictMaxAccuracyMeters = 60;
  static const double driverSearchMaxAccuracyMeters = 150;

  static Future<void> ensureLocationAccess() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const _LocationError(
        'Activez la localisation pour continuer.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
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
      attempts: 4,
      timeoutPerAttempt: const Duration(seconds: 8),
      desiredAccuracy: LocationAccuracy.high,
      failureMessage:
          'Localisation indisponible ou trop imprécise. Vérifiez le GPS puis réessayez.',
    );
  }

  static Future<Position> _resolveFreshPosition({
    required double maxAccuracyMeters,
    required int attempts,
    required Duration timeoutPerAttempt,
    required LocationAccuracy desiredAccuracy,
    required String failureMessage,
  }) async {
    await ensureLocationAccess();

    Position? bestPosition;
    Object? lastError;
    for (var index = 0; index < attempts; index++) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: desiredAccuracy,
        ).timeout(timeoutPerAttempt);
        if (bestPosition == null ||
            position.accuracy < bestPosition.accuracy) {
          bestPosition = position;
        }
        if (position.accuracy <= maxAccuracyMeters) {
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
