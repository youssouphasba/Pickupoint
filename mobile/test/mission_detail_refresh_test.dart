import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pickupoint/core/models/delivery_mission.dart';
import 'package:pickupoint/core/notifications/notification_service.dart';
import 'package:pickupoint/features/driver/providers/driver_provider.dart';
import 'package:pickupoint/features/driver/screens/mission_detail_screen.dart';

class DisabledGps extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalGps = GeolocatorPlatform.instance;
  late ProviderContainer container;
  late String destination;
  late int requests;
  setUp(() {
    GeolocatorPlatform.instance = DisabledGps();
    destination = 'Ancienne destination';
    requests = 0;
    container = ProviderContainer(overrides: [
      missionProvider.overrideWith((ref, id) async {
        requests++;
        return DeliveryMission.fromJson({
          'mission_id': id,
          'parcel_id': 'parcel',
          'status': 'completed',
          'pickup_type': 'gps',
          'delivery_type': 'gps',
          'delivery_area_label': destination,
          'created_at': '2026-10-01T12:00:00Z'
        });
      })
    ]);
  });
  tearDown(() {
    container.dispose();
    GeolocatorPlatform.instance = originalGps;
  });
  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MissionDetailScreen(id: 'mission'))));
    await tester.pumpAndSettle();
    expect(find.text('Ancienne destination'), findsOneWidget);
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('detail updates when returning from navigation on $platform',
        (tester) async {
      await show(tester);
      destination = 'Nouvelle destination';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('Nouvelle destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(platform));
    testWidgets(
        'detail updates when a delivery notification arrives on $platform',
        (tester) async {
      await show(tester);
      destination = 'Relais de repli';
      container.read(foregroundNotificationRefreshProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(find.text('Relais de repli'), findsOneWidget);
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(platform));
  }
}
