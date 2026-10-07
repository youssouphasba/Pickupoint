import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/location/external_navigation.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('Google Maps uses the correct native scheme on $platform', () {
      final targets = ExternalNavigation.destinations(
          app: NavigationApp.googleMaps,
          latitude: 14.7,
          longitude: -17.4,
          platform: platform);
      expect(
          targets.first.scheme,
          platform == TargetPlatform.iOS
              ? 'comgooglemaps'
              : 'google.navigation');
      expect(targets.last.queryParameters['destination'], '14.7,-17.4');
    });
    test('native failure falls back to web on $platform', () async {
      final launches = <Uri>[];
      expect(
          await ExternalNavigation.open(
              app: NavigationApp.googleMaps,
              latitude: 14.7,
              longitude: -17.4,
              platform: platform,
              launcher: (uri) async {
                launches.add(uri);
                if (uri.scheme != 'https') {
                  throw PlatformException(code: 'not_installed');
                }
                return true;
              }),
          isTrue);
      expect(launches, hasLength(2));
    });
  }
  test('Waze falls back if not installed', () async {
    final launches = <Uri>[];
    expect(
        await ExternalNavigation.open(
            app: NavigationApp.waze,
            latitude: 14.7,
            longitude: -17.4,
            launcher: (uri) async {
              launches.add(uri);
              return uri.scheme == 'https';
            }),
        isTrue);
    expect(launches.first.scheme, 'waze');
  });
  test('invalid coordinates never launch navigation', () async {
    expect(
        await ExternalNavigation.open(
            app: NavigationApp.googleMaps,
            latitude: double.nan,
            longitude: 0,
            launcher: (_) async => throw StateError('must not launch')),
        isFalse);
  });
  test('all launch failures are reported', () async {
    expect(
        await ExternalNavigation.open(
            app: NavigationApp.googleMaps,
            latitude: 14.7,
            longitude: -17.4,
            launcher: (_) async => false),
        isFalse);
  });
}
