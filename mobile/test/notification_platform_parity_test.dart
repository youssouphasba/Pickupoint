import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pickupoint/core/api/api_client.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/core/models/delivery_mission.dart';
import 'package:pickupoint/core/models/user.dart';
import 'package:pickupoint/core/notifications/notification_service.dart';
import 'package:pickupoint/core/notifications/driver_mission_activity.dart';
import 'package:pickupoint/core/notifications/notification_navigation.dart';
import 'package:pickupoint/features/driver/providers/driver_provider.dart';

class TestAuth extends AuthNotifier {
  static bool available = true;
  static String role = 'driver';
  static String owner = 'driver';
  @override
  Future<AuthState> build() async => AuthState(
      status: AuthStatus.authenticated,
      accessToken: 'test',
      user: User(id: owner, phone: '', role: role, isAvailable: available));

  void signOut() {
    state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
  }
}

class TestMessaging implements FirebaseMessaging {
  final tokens = StreamController<String>.broadcast();
  String? apnsToken = 'apns';
  int tokenRequests = 0;
  bool? foregroundAlerts;
  bool permissionFailure = false;
  @override
  Stream<String> get onTokenRefresh => tokens.stream;
  @override
  Future<String?> getAPNSToken() async => apnsToken;
  @override
  Future<String?> getToken({String? vapidKey}) async {
    tokenRequests++;
    return 'fcm';
  }

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
  @override
  Future<NotificationSettings> requestPermission(
      {bool alert = true,
      bool announcement = false,
      bool badge = true,
      bool carPlay = false,
      bool criticalAlert = false,
      bool provisional = false,
      bool sound = true}) async {
    if (permissionFailure) throw PlatformException(code: 'temporary');
    return const NotificationSettings(
        alert: AppleNotificationSetting.enabled,
        announcement: AppleNotificationSetting.disabled,
        authorizationStatus: AuthorizationStatus.authorized,
        badge: AppleNotificationSetting.enabled,
        carPlay: AppleNotificationSetting.disabled,
        criticalAlert: AppleNotificationSetting.disabled,
        lockScreen: AppleNotificationSetting.enabled,
        notificationCenter: AppleNotificationSetting.enabled,
        showPreviews: AppleShowPreviewSetting.always,
        sound: AppleNotificationSetting.enabled,
        timeSensitive: AppleNotificationSetting.disabled);
  }

  @override
  Future<void> setForegroundNotificationPresentationOptions(
      {bool alert = false, bool badge = false, bool sound = false}) async {
    foregroundAlerts = alert;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestLocalNotifications implements FlutterLocalNotificationsPlugin {
  final shown = <NotificationDetails?>[];
  final missionShown =
      <({String? body, NotificationDetails? details, String? payload})>[];
  final cancelled = <int>[];
  int initializations = 0;
  @override
  Future<bool?> initialize(InitializationSettings settings,
      {DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
      DidReceiveBackgroundNotificationResponseCallback?
          onDidReceiveBackgroundNotificationResponse}) async {
    initializations++;
    return true;
  }

  @override
  T? resolvePlatformSpecificImplementation<
          T extends FlutterLocalNotificationsPlatform>() =>
      null;
  @override
  Future<void> show(
      int id, String? title, String? body, NotificationDetails? details,
      {String? payload}) async {
    if (id == driverActiveMissionNotificationId) {
      missionShown.add((body: body, details: details, payload: payload));
    } else {
      shown.add(details);
    }
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelled.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TokenApi extends ApiClient {
  final uploaded = <String>[];
  @override
  Future<Response> updateFcmToken(String token, {String? appVersion}) async {
    uploaded.add(token);
    return Response(requestOptions: RequestOptions(path: '/token'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late NotificationService service;
  late TestMessaging messaging;
  late TestLocalNotifications local;
  late TokenApi api;
  var active = false;
  var pickedUp = false;
  var missionFetchFailure = false;
  var nativeStatus = 'active';
  var nativeFailure = false;
  var missionReads = 0;
  String? fixtureDriver;
  final activityCalls = <MethodCall>[];
  late DateTime assignedAt;
  late DateTime pickupDeadline;
  const channel = MethodChannel('com.denkma.app/driver_mission_activity');
  Future<void> setup(TargetPlatform platform) async {
    TestAuth.available = true;
    TestAuth.role = 'driver';
    TestAuth.owner = 'driver';
    active = false;
    pickedUp = false;
    missionFetchFailure = false;
    nativeStatus = 'active';
    nativeFailure = false;
    missionReads = 0;
    fixtureDriver = null;
    activityCalls.clear();
    assignedAt = DateTime.now().toUtc();
    pickupDeadline = assignedAt.add(const Duration(minutes: 20));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      activityCalls.add(call);
      if (nativeFailure && call.method == 'start') {
        throw PlatformException(code: 'activity_start_failed');
      }
      return {'status': call.method == 'end' ? 'ended' : nativeStatus};
    });
    messaging = TestMessaging();
    local = TestLocalNotifications();
    api = TokenApi();
    PackageInfo.setMockInitialValues(
        appName: 'Denkma',
        packageName: 'com.denkma.app',
        version: 'test',
        buildNumber: '48',
        buildSignature: '');
    container = ProviderContainer(overrides: [
      authProvider.overrideWith(TestAuth.new),
      apiClientProvider.overrideWithValue(api),
      myMissionsProvider.overrideWith((ref) async {
        missionReads++;
        if (missionFetchFailure) throw StateError('network');
        return active
            ? [
                DeliveryMission.fromJson({
                  'mission_id': 'active',
                  'parcel_id': 'parcel',
                  'driver_id': fixtureDriver,
                  'status': pickedUp ? 'in_progress' : 'assigned',
                  'created_at': assignedAt.toIso8601String(),
                  'assigned_at': assignedAt.toIso8601String(),
                  'started_at': pickedUp ? assignedAt.toIso8601String() : null,
                  'pickup_confirmation_deadline_at':
                      pickedUp ? null : pickupDeadline.toIso8601String(),
                })
              ]
            : [];
      }),
      notificationServiceProvider.overrideWith((ref) {
        final result = NotificationService(ref,
            messaging: messaging,
            localNotifications: local,
            platform: platform);
        ref.onDispose(result.dispose);
        return result;
      }),
    ]);
    await container.read(authProvider.future);
    await container.read(myMissionsProvider.future);
    service = container.read(notificationServiceProvider);
  }

  tearDown(() async {
    container.dispose();
    await messaging.tokens.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> sendAvailable() async {
    FirebaseMessagingPlatform.onMessage.add(const RemoteMessage(
        data: {'event_type': 'mission_available', 'ref_type': 'mission'},
        notification: RemoteNotification(title: 'Course', body: 'Disponible')));
    await Future<void>.delayed(Duration.zero);
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
        'foreground alert is delivered once and suppressed when busy on $platform',
        () async {
      await setup(platform);
      await service.init();
      await service.init();
      await sendAvailable();
      expect(local.shown, hasLength(1));
      active = true;
      await container.refresh(myMissionsProvider.future);
      await sendAvailable();
      expect(local.shown, hasLength(1));
      expect(local.initializations, 1);
      if (platform == TargetPlatform.iOS) {
        expect(messaging.foregroundAlerts, isFalse);
        expect(local.shown.single?.iOS?.presentSound, isTrue);
      }
    });
    test('unavailable driver receives no foreground mission alert on $platform',
        () async {
      await setup(platform);
      TestAuth.available = false;
      await container.refresh(authProvider.future);
      await service.init();
      await sendAvailable();
      expect(local.shown, isEmpty);
    });
  }
  test('iOS waits for APNS and retries on resume', () async {
    await setup(TargetPlatform.iOS);
    messaging.apnsToken = null;
    await service.init();
    expect(messaging.tokenRequests, 0);
    messaging.apnsToken = 'ready';
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(api.uploaded, ['fcm']);
  });
  test('permission failure does not prevent installation of listeners',
      () async {
    await setup(TargetPlatform.iOS);
    messaging.permissionFailure = true;
    await service.init();
    await sendAvailable();
    expect(local.shown, hasLength(1));
    expect(container.read(foregroundNotificationRefreshProvider), 1);
  });
  test('iOS live activity sends a parseable deadline and updates changes',
      () async {
    await setup(TargetPlatform.iOS);
    Future<void> sync(DateTime deadline) =>
        service.syncDriverMissionNotification(
            missionId: 'mission',
            trackingCode: 'CODE',
            assignedAt: assignedAt,
            startedAt: null,
            pickupConfirmationDeadline: deadline);
    final deadline = DateTime.now().toUtc().add(const Duration(minutes: 20));
    await sync(deadline);
    await sync(deadline);
    expect(activityCalls, hasLength(1));
    expect(
        DateTime.parse(activityCalls.single.arguments['deadline']), deadline);
    await sync(deadline.add(const Duration(minutes: 5)));
    expect(activityCalls.map((c) => c.method), ['start', 'start']);
    await sync(DateTime.now().subtract(const Duration(seconds: 1)));
    expect(activityCalls.last.method, 'start');
  });

  test(
      'iOS starts without DriverHome, updates after pickup, ends on completion',
      () async {
    await setup(TargetPlatform.iOS);
    active = true;
    await container.refresh(myMissionsProvider.future);
    await service.init();
    expect(activityCalls.single.method, 'start');
    expect(activityCalls.single.arguments['phase'], 'pickup');
    pickedUp = true;
    await container.refresh(myMissionsProvider.future);
    await service.refreshDriverMissionNotification();
    expect(activityCalls.last.method, 'start');
    expect(activityCalls.last.arguments['phase'], 'delivery');
    expect(activityCalls.last.arguments['deadline'], isNull);
    expect(activityCalls.where((call) => call.method == 'end'), isEmpty);
    active = false;
    await container.refresh(myMissionsProvider.future);
    await service.refreshDriverMissionNotification();
    expect(activityCalls.last.method, 'end');
  });

  test('a failed refresh does not end an ongoing iOS activity', () async {
    await setup(TargetPlatform.iOS);
    active = true;
    await container.refresh(myMissionsProvider.future);
    await service.init();
    missionFetchFailure = true;
    await expectLater(
        container.refresh(myMissionsProvider.future), throwsStateError);
    await service.refreshDriverMissionNotification();
    expect(activityCalls.every((call) => call.method == 'start'), isTrue);
  });

  test(
      'unknown missions on a network failure do not masquerade as an empty list',
      () async {
    await setup(TargetPlatform.iOS);
    missionFetchFailure = true;
    await expectLater(
        container.refresh(myMissionsProvider.future), throwsStateError);
    await service.init();
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await service.refreshDriverMissionNotification();
    expect(activityCalls, isEmpty);
    missionFetchFailure = false;
    active = true;
    await container.refresh(myMissionsProvider.future);
    await service.refreshDriverMissionNotification();
    expect(activityCalls.single.method, 'start');
  });

  test('resuming resynchronizes an activity dismissed by the system', () async {
    await setup(TargetPlatform.iOS);
    active = true;
    await container.refresh(myMissionsProvider.future);
    await service.init();
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await service.refreshDriverMissionNotification();
    expect(activityCalls.where((call) => call.method == 'start').length,
        greaterThan(1));
  });

  for (final status in ['disabled', 'unsupported', 'update_required']) {
    test('iOS reports $status and provides one silent fallback notification',
        () async {
      await setup(TargetPlatform.iOS);
      nativeStatus = status;
      active = true;
      await container.refresh(myMissionsProvider.future);
      await service.init();
      await service.refreshDriverMissionNotification();
      final issue = container.read(driverMissionActivityIssueProvider);
      expect(issue, isNotNull);
      expect(issue!.openSettings, status == 'disabled');
      expect(local.missionShown, hasLength(1));
      expect(local.missionShown.single.details?.iOS?.presentSound, isFalse);
      expect(local.missionShown.single.payload, contains('active'));
      expect(local.missionShown.single.body, contains('avant'));
      nativeStatus = 'active';
      await service.refreshDriverMissionNotification();
      expect(container.read(driverMissionActivityIssueProvider), isNull);
      expect(local.cancelled, contains(driverActiveMissionNotificationId));
    });
  }

  test('iOS start failure is visible and recoverable', () async {
    await setup(TargetPlatform.iOS);
    nativeFailure = true;
    active = true;
    await container.refresh(myMissionsProvider.future);
    await service.init();
    expect(container.read(driverMissionActivityIssueProvider)?.message,
        contains('Réessayez'));
    expect(local.missionShown, hasLength(1));
    nativeFailure = false;
    await service.refreshDriverMissionNotification();
    expect(container.read(driverMissionActivityIssueProvider), isNull);
  });

  test('iOS defers background creation and retries on resume', () async {
    await setup(TargetPlatform.iOS);
    nativeStatus = 'deferred';
    active = true;
    await container.refresh(myMissionsProvider.future);
    await service.init();
    expect(local.missionShown, isEmpty);
    expect(container.read(driverMissionActivityIssueProvider), isNull);
    nativeStatus = 'active';
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await service.refreshDriverMissionNotification();
    expect(activityCalls.where((call) => call.method == 'start').length,
        greaterThan(1));
  });

  test('logout ends the activity and stops observing driver missions',
      () async {
    await setup(TargetPlatform.iOS);
    active = true;
    await container.refresh(myMissionsProvider.future);
    await service.init();
    (container.read(authProvider.notifier) as TestAuth).signOut();
    await service.refreshDriverMissionNotification();
    expect(activityCalls.last.method, 'end');
    final starts = activityCalls.where((call) => call.method == 'start').length;
    await container.refresh(myMissionsProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(
        activityCalls.where((call) => call.method == 'start').length, starts);
  });

  test('client accounts do not create driver activities', () async {
    await setup(TargetPlatform.iOS);
    TestAuth.role = 'client';
    await container.refresh(authProvider.future);
    active = true;
    await container.refresh(myMissionsProvider.future);
    await service.init();
    expect(activityCalls.every((call) => call.method == 'end'), isTrue);
  });

  test(
      'switching accounts reloads missions and rejects another driver’s cached mission',
      () async {
    await setup(TargetPlatform.iOS);
    active = true;
    fixtureDriver = 'driver';
    await container.refresh(myMissionsProvider.future);
    await service.init();
    final reads = missionReads;
    TestAuth.owner = 'other-driver';
    await container.refresh(authProvider.future);
    await container.read(myMissionsProvider.future);
    await service.refreshDriverMissionNotification();
    expect(missionReads, greaterThan(reads));
    expect(activityCalls.last.method, 'end');
    expect(activityCalls.where((call) => call.method == 'start'), hasLength(1));
  });

  test('iOS mission updates run serially without ending the pickup activity',
      () async {
    await setup(TargetPlatform.iOS);
    final gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      activityCalls.add(call);
      if (call.arguments['phase'] == 'pickup') await gate.future;
      return {'status': 'active'};
    });
    final first = service.syncDriverMissionNotification(
      missionId: 'mission',
      trackingCode: 'CODE',
      assignedAt: assignedAt,
      startedAt: null,
      pickupConfirmationDeadline: pickupDeadline,
    );
    final second = service.syncDriverMissionNotification(
      missionId: 'mission',
      trackingCode: 'CODE',
      assignedAt: assignedAt,
      startedAt: assignedAt,
      pickupConfirmationDeadline: null,
    );
    await Future<void>.delayed(Duration.zero);
    expect(activityCalls, hasLength(1));
    gate.complete();
    await Future.wait([first, second]);
    expect(activityCalls.map((call) => call.arguments['phase']),
        ['pickup', 'delivery']);
    expect(activityCalls.every((call) => call.method == 'start'), isTrue);
  });

  test(
      'a legacy native bridge response requests an app update instead of claiming success',
      () async {
    await setup(TargetPlatform.iOS);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    active = true;
    await container.refresh(myMissionsProvider.future);
    await service.init();
    expect(container.read(driverMissionActivityIssueProvider)?.message,
        contains('Mettez Denkma à jour'));
    expect(local.missionShown, hasLength(1));
  });
}
