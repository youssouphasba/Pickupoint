import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pickupoint/core/notifications/driver_mission_activity.dart';
import 'package:pickupoint/core/notifications/notification_service.dart';
import 'package:pickupoint/features/driver/widgets/driver_mission_activity_notice.dart';

class ActivityGps extends GeolocatorPlatform {
  int settingsOpened = 0;
  bool canOpen = true;

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return canOpen;
  }
}

class ActivityNotifications implements NotificationService {
  int refreshes = 0;

  @override
  Future<void> refreshDriverMissionNotification() async {
    refreshes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final originalGps = GeolocatorPlatform.instance;
  late ActivityGps gps;
  late ActivityNotifications notifications;
  setUp(() {
    gps = ActivityGps();
    GeolocatorPlatform.instance = gps;
    notifications = ActivityNotifications();
  });
  tearDown(() => GeolocatorPlatform.instance = originalGps);

  Future<void> notice(
      WidgetTester tester, DriverMissionActivityIssue? issue) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        driverMissionActivityIssueProvider.overrideWith((ref) => issue),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const MaterialApp(
          home: Scaffold(
              body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: DriverMissionActivityNotice(),
      ))),
    ));
    expect(tester.takeException(), isNull);
  }

  test('pickup timer uses the server deadline without inventing a duration',
      () {
    final assigned = DateTime.utc(2026, 10, 5, 10);
    final deadline = assigned.add(const Duration(minutes: 7));
    final activity = DriverMissionActivity(
      missionId: 'mission',
      trackingCode: 'CODE',
      assignedAt: assigned,
      startedAt: null,
      pickupDeadline: deadline,
    );
    expect(activity.arguments['phase'], 'pickup');
    expect(DateTime.parse(activity.arguments['deadline']! as String), deadline);
    expect(activity.notificationData['ref_id'], 'mission');
  });

  test('collection switches to delivery even if an old deadline remains', () {
    final assigned = DateTime.utc(2026, 10, 5, 10);
    final activity = DriverMissionActivity(
      missionId: 'mission',
      trackingCode: 'CODE',
      assignedAt: assigned,
      startedAt: assigned.add(const Duration(minutes: 1)),
      pickupDeadline: assigned.add(const Duration(minutes: 7)),
    );
    expect(activity.arguments['phase'], 'delivery');
    expect(activity.arguments['deadline'], isNull);
    expect(
        DateTime.parse(activity.arguments['assignedAt']! as String), assigned);
  });

  test('missing deadline keeps an active pickup without a fabricated countdown',
      () {
    final activity = DriverMissionActivity(
      missionId: 'mission',
      trackingCode: null,
      assignedAt: DateTime.utc(2026, 10, 5),
      startedAt: null,
      pickupDeadline: null,
    );
    expect(activity.phase, 'pickup');
    expect(activity.arguments['deadline'], isNull);
  });

  testWidgets('healthy activity adds no banner', (tester) async {
    await notice(tester, null);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
  });

  testWidgets(
      'disabled activity opens app settings and fits small screens with large text',
      (tester) async {
    await notice(
        tester,
        const DriverMissionActivityIssue(
          'Activités en direct désactivées. Activez-les dans les réglages de Denkma.',
          openSettings: true,
        ));
    await tester.tap(find.byTooltip('Ouvrir les réglages'));
    await tester.pumpAndSettle();
    expect(gps.settingsOpened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed activity can retry without opening settings',
      (tester) async {
    await notice(
        tester, const DriverMissionActivityIssue('Réessayez depuis Denkma.'));
    await tester.tap(find.byTooltip('Réessayer'));
    await tester.pumpAndSettle();
    expect(notifications.refreshes, 1);
    expect(gps.settingsOpened, 0);
  });

  testWidgets('unavailable settings shows a readable error', (tester) async {
    gps.canOpen = false;
    await notice(
        tester,
        const DriverMissionActivityIssue('Activez les activités en direct.',
            openSettings: true));
    await tester.tap(find.byTooltip('Ouvrir les réglages'));
    await tester.pump();
    expect(find.textContaining('Action indisponible'), findsOneWidget);
  });

  testWidgets('an unsupported version does not offer a pointless retry',
      (tester) async {
    await notice(
        tester,
        const DriverMissionActivityIssue('Mettez Denkma à jour.',
            canRetry: false));
    expect(find.byType(IconButton), findsNothing);
    expect(find.text('Mettez Denkma à jour.'), findsOneWidget);
  });
}
