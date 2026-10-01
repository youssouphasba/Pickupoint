import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:pickupoint/core/api/api_client.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/core/location/driver_presence_service.dart';
import 'package:pickupoint/core/models/delivery_mission.dart';
import 'package:pickupoint/core/models/user.dart';
import 'package:pickupoint/core/notifications/notification_navigation.dart';
import 'package:pickupoint/core/notifications/notification_service.dart';
import 'package:pickupoint/features/driver/providers/driver_provider.dart';
import 'package:pickupoint/features/driver/screens/driver_home.dart';
import 'package:pickupoint/shared/notifications/notifications_inbox_screen.dart';
import 'package:pickupoint/shared/promotions/campaign_banner.dart';
import 'package:pickupoint/shared/widgets/support_whatsapp_tile.dart';

class DriverAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'test',
        user: User(id: 'driver', phone: '', role: 'driver', isAvailable: true),
      );
}

class DriverGps extends GeolocatorPlatform {
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
}

class DriverPresence implements DriverPresenceService {
  final controller = StreamController<Position>.broadcast();
  Completer<Position>? pending;
  @override
  Stream<Position> get positions => controller.stream;
  @override
  Future<Position> requestFreshPosition() async => pending == null
      ? Position(
          latitude: 14.7,
          longitude: -17.4,
          timestamp: DateTime.now(),
          accuracy: 10,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        )
      : await pending!.future;
  @override
  Future<void> reconcile(AuthState? auth, {bool forceUpload = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QuietNotifications implements NotificationService {
  @override
  Future<void> syncDriverMissionNotification({
    required String? missionId,
    required String? trackingCode,
    required DateTime? assignedAt,
    required DateTime? startedAt,
    required DateTime? pickupConfirmationDeadline,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewApi extends ApiClient {
  final previews = <String>[];
  @override
  Future<Response> getMissionPreview(String id,
      {double? lat, double? lng}) async {
    previews.add(id);
    return Response(
        data: {'preview': <String, dynamic>{}},
        requestOptions: RequestOptions(path: '/preview'));
  }
}

class FakeMaps extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) =>
      const SizedBox(height: 220);
}

DeliveryMission mission(String id, {String status = 'pending'}) =>
    DeliveryMission.fromJson({
      'mission_id': id,
      'parcel_id': 'parcel-$id',
      'status': status,
      'tracking_code': id,
      'created_at': '2026-10-01T12:00:00Z',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DriverPresence presence;
  late PreviewApi api;
  late ProviderContainer container;
  late GoRouter router;
  late List<DeliveryMission> available;
  late List<DeliveryMission> mine;
  Completer<List<DeliveryMission>>? pendingAvailable;
  Object? availableError;
  late int availableRequests;
  final originalGps = GeolocatorPlatform.instance;
  final originalMaps = GoogleMapsFlutterPlatform.instance;

  setUp(() {
    GeolocatorPlatform.instance = DriverGps();
    GoogleMapsFlutterPlatform.instance = FakeMaps();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => call.method == 'read' ? 'accepted' : null);
    presence = DriverPresence();
    api = PreviewApi();
    available = [mission('first')];
    mine = [];
    pendingAvailable = null;
    availableError = null;
    availableRequests = 0;
    container = ProviderContainer(overrides: [
      authProvider.overrideWith(DriverAuth.new),
      apiClientProvider.overrideWithValue(api),
      driverPresenceServiceProvider.overrideWithValue(presence),
      notificationServiceProvider.overrideWithValue(QuietNotifications()),
      notificationSettingsProvider
          .overrideWith((ref) => Completer<NotificationSettings>().future),
      activeCampaignsProvider.overrideWith((ref, key) async => []),
      supportWhatsAppProvider.overrideWith((ref) async => {}),
      unreadNotificationsCountProvider.overrideWith((ref) => Stream.value(0)),
      myMissionsProvider.overrideWith((ref) async => List.of(mine)),
      availableMissionsProvider.overrideWith((ref, location) async {
        availableRequests++;
        if (availableError != null) throw availableError!;
        if (pendingAvailable != null) return pendingAvailable!.future;
        return List.of(available);
      }),
    ]);
    router = GoRouter(initialLocation: '/driver', routes: [
      GoRoute(
          path: '/driver',
          builder: (_, state) => DriverHome(
                initialPreviewMissionId: state.uri.queryParameters['preview'],
                unavailableMissionId: state.uri.queryParameters['unavailable'],
                openAvailableMissions:
                    state.uri.queryParameters['available'] == 'true',
                notificationRequest:
                    state.extra as DriverMissionNotificationRequest?,
              )),
      GoRoute(
          path: '/elsewhere',
          builder: (_, __) => const Scaffold(body: Text('Other screen'))),
    ]);
  });

  tearDown(() async {
    router.dispose();
    container.dispose();
    await presence.controller.close();
    GeolocatorPlatform.instance = originalGps;
    GoogleMapsFlutterPlatform.instance = originalMaps;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null);
  });

  Future<void> show(WidgetTester tester, {bool waitForIdle = true}) async {
    await tester.binding.setSurfaceSize(const Size(430, 930));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    if (waitForIdle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> tapNotification(WidgetTester tester,
      {String route = '/driver?preview=old'}) async {
    router.go(route, extra: driverMissionNotificationRequestFor(route));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  TabController tabs(WidgetTester tester) =>
      tester.widget<TabBar>(find.byType(TabBar)).controller!;

  testWidgets('multiple current courses open Disponibles without a preview',
      (tester) async {
    available = [mission('first'), mission('second')];
    await show(tester);
    await tester.tap(find.text('Mes missions'));
    await tester.pumpAndSettle();
    await tapNotification(tester);
    await tester.pumpAndSettle();
    expect(tabs(tester).index, 0);
    expect(find.text('Aperçu de la course'), findsNothing);
    expect(api.previews, isEmpty);
    expect(availableRequests, greaterThan(1));
  });

  testWidgets('old notification opens the actual single remaining course',
      (tester) async {
    available = [mission('remaining')];
    await show(tester);
    await tapNotification(tester);
    await tester.pumpAndSettle();
    expect(find.text('Aperçu de la course'), findsOneWidget);
    expect(api.previews, ['remaining']);
  });

  testWidgets('opening the app from a notification waits for the GPS',
      (tester) async {
    presence.pending = Completer<Position>();
    router.go('/driver?preview=old',
        extra: driverMissionNotificationRequestFor('/driver?preview=old'));
    await show(tester, waitForIdle: false);
    expect(availableRequests, 0);
    expect(api.previews, isEmpty);
    presence.pending!.complete(Position(
      latitude: 14.7,
      longitude: -17.4,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ));
    await tester.pumpAndSettle();
    expect(api.previews, ['first']);
  });

  testWidgets('no current course displays an explicit empty message',
      (tester) async {
    await show(tester);
    available = [];
    await tapNotification(tester);
    await tester.pumpAndSettle();
    expect(tabs(tester).index, 0);
    expect(find.text('Il n’y a plus de course disponible dans votre rayon.'),
        findsOneWidget);
    expect(api.previews, isEmpty);
  });

  testWidgets('cached single course is not used while refreshing',
      (tester) async {
    await show(tester);
    pendingAvailable = Completer<List<DeliveryMission>>();
    await tapNotification(tester);
    expect(find.text('Aperçu de la course'), findsNothing);
    expect(api.previews, isEmpty);
    pendingAvailable!.complete([mission('first'), mission('second')]);
    await tester.pumpAndSettle();
    expect(api.previews, isEmpty);
  });

  testWidgets('same notification can be tapped again and reevaluates the list',
      (tester) async {
    available = [mission('first'), mission('second')];
    await show(tester);
    await tapNotification(tester);
    await tester.pumpAndSettle();
    available = [mission('second')];
    await tapNotification(tester);
    await tester.pumpAndSettle();
    expect(api.previews, ['second']);
  });

  testWidgets('a later tap supersedes a still pending availability check',
      (tester) async {
    await show(tester);
    final firstRequest = Completer<List<DeliveryMission>>();
    pendingAvailable = firstRequest;
    await tapNotification(tester);
    final latestRequest = Completer<List<DeliveryMission>>();
    pendingAvailable = latestRequest;
    await tapNotification(tester);
    firstRequest.complete([mission('first')]);
    await tester.pump();
    expect(api.previews, isEmpty);
    latestRequest.complete([mission('first'), mission('second')]);
    await tester.pumpAndSettle();
    expect(api.previews, isEmpty);
    expect(tabs(tester).index, 0);
  });

  testWidgets('another tap dismisses a previous automatic preview',
      (tester) async {
    await show(tester);
    await tapNotification(tester);
    await tester.pumpAndSettle();
    expect(find.text('Aperçu de la course'), findsOneWidget);
    available = [mission('first'), mission('second')];
    await tapNotification(tester);
    await tester.pumpAndSettle();
    expect(find.text('Aperçu de la course'), findsNothing);
    expect(tabs(tester).index, 0);
  });

  testWidgets('active mission is refreshed and remains the priority',
      (tester) async {
    await show(tester);
    mine = [mission('current', status: 'in_progress')];
    await tapNotification(tester);
    await tester.pumpAndSettle();
    expect(tabs(tester).index, 1);
    expect(api.previews, isEmpty);
    expect(
        find.text(
            'Terminez votre mission en cours avant d’accepter une autre course.'),
        findsOneWidget);
  });

  testWidgets('a server error is not mistaken for no available course',
      (tester) async {
    await show(tester);
    availableError = Exception('Connexion indisponible');
    await tapNotification(tester);
    await tester.pumpAndSettle();
    expect(find.text('Il n’y a plus de course disponible dans votre rayon.'),
        findsNothing);
    expect(find.text('Réessayer'), findsOneWidget);
    availableError = null;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(api.previews, ['first']);
  });

  testWidgets(
      'reminder without a mission reference still opens the single course',
      (tester) async {
    await show(tester);
    await tapNotification(tester, route: '/driver?available=true');
    await tester.pumpAndSettle();
    expect(api.previews, ['first']);
  });

  testWidgets('unavailable alert does not open an unrelated preview',
      (tester) async {
    await show(tester);
    await tapNotification(tester, route: '/driver?unavailable=old');
    await tester.pumpAndSettle();
    expect(api.previews, isEmpty);
    expect(find.text('Cette course a déjà été acceptée par un autre livreur.'),
        findsOneWidget);
  });

  testWidgets('leaving the page while refreshing never opens a late preview',
      (tester) async {
    await show(tester);
    pendingAvailable = Completer<List<DeliveryMission>>();
    await tapNotification(tester);
    router.go('/elsewhere');
    await tester.pumpAndSettle();
    pendingAvailable!.complete([mission('first')]);
    await tester.pumpAndSettle();
    expect(find.text('Other screen'), findsOneWidget);
    expect(api.previews, isEmpty);
  });
}
