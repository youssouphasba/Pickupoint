import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pickupoint/core/location/location_policy.dart';
import 'package:pickupoint/core/location/location_snapshot.dart';
import 'package:pickupoint/core/location/gps_trace.dart';
import 'package:pickupoint/core/location/driver_trace_buffer.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pickupoint/core/models/parcel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 9, 30, 12);
  Position position(
          {double accuracy = 20, DateTime? at, bool mocked = false}) =>
      Position(
          latitude: 14.7,
          longitude: -17.4,
          timestamp: at ?? now,
          accuracy: accuracy,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
          isMocked: mocked);
  const policy = LocationPolicy();

  test('Reject stale, inaccurate, invalid precision, mock and future GPS fixes',
      () {
    for (final fix in [
      position(accuracy: 5000),
      position(accuracy: -1),
      position(accuracy: double.nan),
      position(at: now.subtract(const Duration(hours: 2))),
      position(at: now.add(const Duration(hours: 2))),
      position(mocked: true)
    ]) {
      expect(policy.accepts(fix, now: now), false);
    }
  });
  test('Strict collection checks are stricter than general presence', () {
    expect(policy.accepts(position(accuracy: 100), now: now), true);
    expect(
        policy.accepts(position(accuracy: 100), now: now, strict: true), false);
    expect(policy.accepts(position(), now: now, strict: true), true);
  });
  test('Policy uses configured server limits and ignores invalid values', () {
    final configured = LocationPolicy.fromJson({
      'strict_accuracy_meters': 30,
      'driver_accuracy_meters': 80,
      'max_age_seconds': 40,
      'upload_interval_seconds': 0
    });
    expect(configured.strictAccuracy, 30);
    expect(configured.driverAccuracy, 80);
    expect(configured.maxAge.inSeconds, 40);
    expect(
        configured.uploadInterval.inSeconds, policy.uploadInterval.inSeconds);
  });
  test(
      'Client does not display an old snapshot as live even if available is true',
      () {
    expect(
        isLiveLocationSnapshot({
          'available': true,
          'location': {'lat': 14, 'lng': -17},
          'location_updated_at':
              now.subtract(const Duration(hours: 2)).toIso8601String()
        }, now: now),
        false);
    expect(
        isLiveLocationSnapshot({
          'available': true,
          'location': {'lat': 14, 'lng': -17},
          'location_updated_at': now.toIso8601String()
        }, now: now),
        true);
    expect(
        isLiveLocationSnapshot({
          'available': true,
          'location': {'lat': 14, 'lng': -17}
        }, now: now),
        false);
  });
  test('Trace segments remain separated and invalid coordinates are excluded',
      () {
    final segments = recordedTraceSegments({
      'trace_summary': {
        'segments': [
          [
            {'lat': 14, 'lng': -17},
            {'lat': 14.1, 'lng': -17.1}
          ],
          [
            {'lat': 15, 'lng': -16},
            {'lat': 500, 'lng': -16}
          ],
        ]
      }
    });
    expect(segments, hasLength(2));
    expect(segments.first, hasLength(2));
    expect(segments.last, hasLength(1));
  });
  test('Missing archived trace is not replaced with a straight line', () {
    expect(
        recordedTraceSegments({
          'gps_trail': [
            {'lat': 14, 'lng': -17},
            {'lat': 15, 'lng': -16}
          ]
        }),
        isEmpty);
  });

  test('Relay-to-home live map is only available to recipient after collection',
      () {
    expect(supportsClientLiveTracking('home_to_home'), true);
    expect(
        supportsClientLiveTracking('relay_to_home', isRecipient: true), false);
    expect(
        supportsClientLiveTracking('relay_to_home', afterRelayCollection: true),
        false);
    expect(
        supportsClientLiveTracking('relay_to_home',
            isRecipient: true, afterRelayCollection: true),
        true);
    for (final mode in ['home_to_relay', 'relay_to_relay']) {
      expect(
          supportsClientLiveTracking(mode,
              isRecipient: true, afterRelayCollection: true),
          false);
    }
  });

  test(
      'Parcel preserves server collection authorization and recipient identity',
      () {
    final parcel = Parcel.fromJson({
      'parcel_id': 'p1',
      'delivery_mode': 'relay_to_home',
      'status': 'in_transit',
      'is_recipient': true,
      'live_tracking_allowed': true,
    });
    expect(parcel.liveTrackingAllowed, true);
    expect(
        supportsClientLiveTracking(parcel.deliveryMode,
            isRecipient: parcel.isRecipientView == true,
            afterRelayCollection: parcel.liveTrackingAllowed == true),
        true);
    expect(
        Parcel.fromJson({'live_tracking_allowed': false}).liveTrackingAllowed,
        false);
    expect(Parcel.fromJson({}).liveTrackingAllowed, isNull);
  });

  test(
      'Offline trace persists encrypted-storage serialization and stays account-bound',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final buffer = DriverTraceBuffer();
    await buffer.save('driver', [
      DriverTracePoint('m1', {
        'lat': 14,
        'lng': -17,
        'accuracy': 20,
        'captured_at': now.toIso8601String()
      })
    ]);
    final restored = await DriverTraceBuffer().load('driver');
    expect(restored.single.missionId, 'm1');
    expect(restored.single.capturedAt, now);
    expect(await DriverTraceBuffer().load('other-driver'), isEmpty);
    await buffer.save(null, []);
    expect(await DriverTraceBuffer().load('driver'), isEmpty);
  });
}
