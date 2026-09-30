import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pickupoint/core/api/api_client.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/core/location/driver_presence_service.dart';
import 'package:pickupoint/core/location/driver_trace_buffer.dart';
import 'package:pickupoint/core/location/location_policy.dart';
import 'package:pickupoint/core/models/delivery_mission.dart';
import 'package:pickupoint/core/models/user.dart';
import 'package:pickupoint/features/driver/providers/driver_provider.dart';

Position position({double accuracy = 20, DateTime? at, bool mocked = false}) =>
    Position(
      latitude: 14.7,
      longitude: -17.4,
      timestamp: at ?? DateTime.now(),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: mocked,
    );

class GpsAuth extends AuthNotifier {
  GpsAuth(this.user);
  final User user;
  @override
  Future<AuthState> build() async => AuthState(
      status: AuthStatus.authenticated, user: user, accessToken: 'test');
  void logoutForTest() =>
      state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
}

class GpsPlatform extends DriverGpsPlatform {
  final statuses = StreamController<ServiceStatus>.broadcast();
  final streams = <StreamController<Position>>[];
  bool enabled = true;
  bool consent = true;
  LocationPermission granted = LocationPermission.always;
  int subscriptions = 0;
  int maxSubscriptions = 0;
  int freshRequests = 0;
  Completer<Position>? pendingFresh;
  LocationSettings? settings;
  @override
  Future<bool> hasConsent() async => consent;
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<LocationPermission> permission() async => granted;
  @override
  Stream<ServiceStatus> get serviceStatus => statuses.stream;
  @override
  Future<void> refreshPolicy() async {}
  @override
  Stream<Position> positions(LocationSettings value) {
    settings = value;
    late final StreamController<Position> controller;
    controller = StreamController<Position>(onListen: () {
      subscriptions++;
      if (subscriptions > maxSubscriptions) maxSubscriptions = subscriptions;
    }, onCancel: () {
      subscriptions--;
    });
    streams.add(controller);
    return controller.stream;
  }

  @override
  Future<Position> freshPosition() async {
    freshRequests++;
    return pendingFresh == null ? position() : await pendingFresh!.future;
  }

  Future<void> close() async {
    for (final stream in streams) {
      await stream.close();
    }
    await statuses.close();
  }
}

class TraceMemory extends DriverTraceBuffer {
  String? owner;
  List<DriverTracePoint> pending = [];
  @override
  Future<List<DriverTracePoint>> load(String userId) async =>
      owner == userId ? List.of(pending) : [];
  @override
  Future<void> save(String? userId, List<DriverTracePoint> points) async {
    owner = userId;
    pending = List.of(points);
  }
}

class GpsApi extends ApiClient {
  final presence = <Map<String, dynamic>>[];
  final live = <(String, Map<String, dynamic>)>[];
  final traces = <(String, List<Map<String, dynamic>>)>[];
  bool offline = false;
  bool traceRecorded = true;
  Response response() => Response(
      requestOptions: RequestOptions(path: '/gps'), data: {'message': 'ok'});
  void checkNetwork() {
    if (offline) {
      throw DioException(
          requestOptions: RequestOptions(path: '/gps'),
          type: DioExceptionType.connectionError);
    }
  }

  @override
  Future<Response> updateMyDriverLocation(Map<String, dynamic> body) async {
    checkNetwork();
    presence.add(body);
    return response();
  }

  @override
  Future<Response> updateLocation(String id, Map<String, dynamic> body) async {
    checkNetwork();
    live.add((id, body));
    return Response(
        requestOptions: RequestOptions(path: '/gps'),
        data: {'message': 'ok', 'trace_recorded': traceRecorded});
  }

  @override
  Future<Response> uploadDriverTrace(
      String id, List<Map<String, dynamic>> points) async {
    checkNetwork();
    traces.add((id, points));
    return response();
  }
}

DeliveryMission mission(String status) => DeliveryMission.fromJson({
      'mission_id': 'm1',
      'parcel_id': 'p1',
      'status': status,
      'driver_id': 'driver',
      'created_at': DateTime.now().toIso8601String(),
      if (status != 'assigned')
        'started_at':
            DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late GpsPlatform gps;
  late GpsApi api;
  late TraceMemory buffer;
  final missionState = StateProvider<AsyncValue<List<DeliveryMission>>>(
      (ref) => const AsyncData([]));

  Future<void> drain() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<DriverPresenceService> setup(
      {bool available = true,
      List<DeliveryMission> missions = const [],
      String role = 'driver'}) async {
    gps = GpsPlatform();
    api = GpsApi();
    buffer = TraceMemory();
    container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => GpsAuth(
          User(id: 'driver', phone: '', role: role, isAvailable: available))),
      apiClientProvider.overrideWithValue(api),
      driverGpsPlatformProvider.overrideWithValue(gps),
      driverTraceBufferProvider.overrideWithValue(buffer),
      myMissionsProvider.overrideWith((ref) => ref.watch(missionState).when(
          data: (value) async => value,
          error: (error, stack) => Future.error(error, stack),
          loading: () => Completer<List<DeliveryMission>>().future)),
    ]);
    container.read(missionState.notifier).state = AsyncData(missions);
    await container.read(authProvider.future);
    final service = container.read(driverPresenceServiceProvider);
    await service.start();
    await drain();
    return service;
  }

  setUp(() => LocationPolicy.current = const LocationPolicy());
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await container.read(driverPresenceServiceProvider).dispose();
    container.dispose();
    await gps.close();
    LocationPolicy.current = const LocationPolicy();
  });

  test('Only one stream and one endpoint upload per measured position',
      () async {
    final service = await setup(missions: [mission('in_progress')]);
    await service.reconcile(container.read(authProvider).valueOrNull,
        forceUpload: true);
    await drain();
    expect(gps.maxSubscriptions, 1);
    expect(api.live, hasLength(1));
    expect(api.presence, isEmpty);
    expect(api.traces, isEmpty);
    expect(api.live.first.$2['captured_at'], isNotNull);
  });

  test('Driver who is unavailable and has no mission is not tracked', () async {
    await setup(available: false);
    expect(gps.subscriptions, 0);
    expect(api.presence, isEmpty);
  });

  test('Client account never starts professional GPS', () async {
    await setup(role: 'client');
    expect(gps.subscriptions, 0);
    expect(api.presence, isEmpty);
  });

  test('An active relay mission is tracked even if driver unavailable',
      () async {
    await setup(available: false, missions: [mission('in_progress')]);
    expect(gps.subscriptions, 1);
    expect(api.live.first.$1, 'm1');
  });

  test('iOS accepts while-in-use for an already active location session',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final service = await setup(available: false);
    gps.granted = LocationPermission.whileInUse;
    container.read(missionState.notifier).state =
        AsyncData([mission('in_progress')]);
    await drain();
    await service.reconcile(container.read(authProvider).valueOrNull);
    await drain();
    expect(gps.settings, isA<AppleSettings>());
    expect((gps.settings as AppleSettings).pauseLocationUpdatesAutomatically,
        false);
    expect(gps.subscriptions, 1);
  });

  test('Android does not start without background permission', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = await setup(available: false);
    gps.granted = LocationPermission.whileInUse;
    container.read(authProvider.notifier).updateUserAvailability(true);
    await service.reconcile(container.read(authProvider).valueOrNull);
    await drain();
    expect(gps.subscriptions, 0);
  });

  test('Stream error releases subscription and foreground resume restarts',
      () async {
    final service = await setup();
    gps.streams.last.addError(StateError('GPS error'));
    await drain();
    expect(gps.subscriptions, 0);
    expect(container.read(driverLocationHealthProvider).tracking, false);
    await service.handleLifecycleState(AppLifecycleState.resumed);
    await drain();
    expect(gps.subscriptions, 1);
    expect(gps.maxSubscriptions, 1);
  });

  test('Stream completion is not mistaken for a still-active subscription',
      () async {
    final service = await setup();
    await gps.streams.last.close();
    await drain();
    expect(gps.subscriptions, 0);
    await service.reconcile(container.read(authProvider).valueOrNull);
    await drain();
    expect(gps.subscriptions, 1);
  });

  test('GPS switch off then on recovers via service status', () async {
    await setup();
    gps.enabled = false;
    gps.statuses.add(ServiceStatus.disabled);
    await drain();
    expect(gps.subscriptions, 0);
    gps.enabled = true;
    gps.statuses.add(ServiceStatus.enabled);
    await drain();
    expect(gps.subscriptions, 1);
  });

  test('Mission loading or API error does not stop active capture', () async {
    await setup(available: false, missions: [mission('in_progress')]);
    container.read(missionState.notifier).state = const AsyncLoading();
    await drain();
    expect(gps.subscriptions, 1);
    container.read(missionState.notifier).state =
        AsyncError(StateError('Network'), StackTrace.current);
    await drain();
    expect(gps.subscriptions, 1);
  });

  test('Buffered points are replayed without replacing the live position',
      () async {
    final service = await setup(available: false);
    api.offline = true;
    container.read(missionState.notifier).state =
        AsyncData([mission('in_progress')]);
    await drain();
    expect(buffer.pending, isNotEmpty);
    final recordedAt = buffer.pending.first.body['captured_at'];
    api.offline = false;
    LocationPolicy.current =
        const LocationPolicy(uploadInterval: Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    gps.streams.last
        .add(position(at: DateTime.now().add(const Duration(seconds: 1))));
    await drain();
    await service.reconcile(container.read(authProvider).valueOrNull,
        forceUpload: true);
    await drain();
    expect(api.live, isNotEmpty);
    expect(
        api.traces
            .expand((batch) => batch.$2)
            .any((point) => point['captured_at'] == recordedAt),
        true);
    expect(buffer.pending, isEmpty);
  });

  test('Logout cancels capture and a late GPS reply is never uploaded',
      () async {
    final service = await setup();
    gps.pendingFresh = Completer<Position>();
    final future = service.requestFreshPosition();
    final rejection = expectLater(future, throwsStateError);
    final sent = api.presence.length;
    (container.read(authProvider.notifier) as GpsAuth).logoutForTest();
    await drain();
    gps.pendingFresh!.complete(position());
    await rejection;
    await drain();
    expect(gps.subscriptions, 0);
    expect(api.presence.length, sent);
    expect(buffer.pending, isEmpty);
  });

  test('A concurrent live update rejection keeps the point for archive replay',
      () async {
    await setup(available: false);
    api.traceRecorded = false;
    container.read(missionState.notifier).state =
        AsyncData([mission('in_progress')]);
    await drain();
    expect(api.live, hasLength(1));
    expect(api.traces, hasLength(1));
    expect(api.traces.single.$2.single['captured_at'],
        api.live.single.$2['captured_at']);
    expect(buffer.pending, isEmpty);
  });

  test('An interrupted Android service is only restarted in the foreground',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = await setup();
    await service.handleLifecycleState(AppLifecycleState.paused);
    gps.streams.last.addError(StateError('Interrupted'));
    await drain();
    await service.reconcile(container.read(authProvider).valueOrNull);
    await drain();
    expect(gps.subscriptions, 0);
    await service.handleLifecycleState(AppLifecycleState.resumed);
    await drain();
    expect(gps.subscriptions, 1);
    expect(gps.maxSubscriptions, 1);
  });

  test(
      'Confirmed collection immediately buffers GPS even if mission refresh then fails',
      () async {
    final service = await setup(missions: [mission('assigned')]);
    api.offline = true;
    service.registerCollection(
        'm1', DateTime.now().subtract(const Duration(seconds: 30)));
    container.read(missionState.notifier).state =
        AsyncError(StateError('Offline'), StackTrace.current);
    await drain();
    gps.streams.last
        .add(position(at: DateTime.now().add(const Duration(seconds: 1))));
    await drain();
    expect(buffer.pending.single.missionId, 'm1');
  });
}
