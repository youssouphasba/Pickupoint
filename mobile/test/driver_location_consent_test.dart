import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pickupoint/core/location/driver_location_consent.dart';
import 'package:pickupoint/core/location/driver_always_location_permission.dart';
import 'package:pickupoint/core/location/fresh_position_helper.dart';

class ConsentGps extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.always;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  int settingsOpened = 0;
  int permissionRequests = 0;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return permission = requestedPermission;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalGps = GeolocatorPlatform.instance;
  const channel = MethodChannel('com.denkma.app/driver_location_permission');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final nativeCalls = <MethodCall>[];
  late ConsentGps gps;
  bool? allowed;

  setUp(() {
    gps = ConsentGps();
    GeolocatorPlatform.instance = gps;
    FlutterSecureStorage.setMockInitialValues({
      'driver_location_consent_v1': 'accepted',
    });
    allowed = null;
    nativeCalls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return false;
    });
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalGps;
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              allowed = await DriverLocationConsent.ensureForWork(context);
            },
            child: const Text('Vérifier'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Vérifier'));
    await tester.pumpAndSettle();
  }

  Future<void> acceptDisclosure(WidgetTester tester) async {
    expect(find.textContaining('autorisation Android'), findsNothing);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
  }

  testWidgets('iOS Always lets the driver work without another prompt',
      (tester) async {
    await start(tester);
    expect(allowed, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(gps.settingsOpened, 0);
    expect(nativeCalls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iOS while-in-use cannot bypass Always by dismissing settings',
      (tester) async {
    gps.permission = LocationPermission.whileInUse;
    await start(tester);
    await acceptDisclosure(tester);
    expect(find.textContaining('Service de localisation > Denkma'),
        findsOneWidget);
    expect(find.textContaining('« Toujours »'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
    expect(gps.settingsOpened, 0);
    expect(nativeCalls.single.method, 'requestAlwaysAuthorization');
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final upgraded in [false, true]) {
    testWidgets('iOS rechecks permission after settings: Always=$upgraded',
        (tester) async {
      gps.permission = LocationPermission.whileInUse;
      await start(tester);
      await acceptDisclosure(tester);
      await tester.tap(find.text('Ouvrir les réglages'));
      await tester.pumpAndSettle();
      expect(gps.settingsOpened, 1);
      expect(allowed, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      gps.permission =
          upgraded ? LocationPermission.always : LocationPermission.whileInUse;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(allowed, upgraded);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  testWidgets('iOS first grant of while-in-use still requires Always',
      (tester) async {
    gps.permission = LocationPermission.denied;
    await start(tester);
    await acceptDisclosure(tester);
    expect(gps.permissionRequests, 1);
    expect(nativeCalls.single.method, 'requestAlwaysAuthorization');
    expect(find.text('Position en arrière-plan'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android still requires Always with Android instructions',
      (tester) async {
    gps.permission = LocationPermission.whileInUse;
    await start(tester);
    await acceptDisclosure(tester);
    expect(find.textContaining('Autorisations de l’application > Position'),
        findsOneWidget);
    expect(find.textContaining('« Toujours autoriser »'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
    expect(nativeCalls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('iOS native Always approval avoids the settings detour',
      (tester) async {
    gps.permission = LocationPermission.whileInUse;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      gps.permission = LocationPermission.always;
      return true;
    });
    await start(tester);
    expect(nativeCalls, isEmpty);
    await acceptDisclosure(tester);
    expect(nativeCalls.single.method, 'requestAlwaysAuthorization');
    expect(allowed, isTrue);
    expect(gps.settingsOpened, 0);
    expect(find.byType(AlertDialog), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iOS first requests when-in-use, then upgrades for the driver',
      (tester) async {
    gps.permission = LocationPermission.denied;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(gps.permissionRequests, 1);
      expect(gps.permission, LocationPermission.whileInUse);
      nativeCalls.add(call);
      gps.permission = LocationPermission.always;
      return true;
    });
    await start(tester);
    await acceptDisclosure(tester);
    expect(allowed, isTrue);
    expect(nativeCalls, hasLength(1));
    expect(gps.settingsOpened, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('declining the driver disclosure never starts the native request',
      (tester) async {
    gps.permission = LocationPermission.whileInUse;
    await start(tester);
    await tester.tap(find.text('Pas maintenant'));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
    expect(nativeCalls, isEmpty);
    expect(gps.permissionRequests, 0);
    expect(gps.settingsOpened, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a native response cannot replace the real iOS permission',
      (tester) async {
    gps.permission = LocationPermission.whileInUse;
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    await start(tester);
    await acceptDisclosure(tester);
    expect(find.text('Position en arrière-plan'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final failure in ['missing_bridge', 'native_error']) {
    testWidgets('iOS $failure keeps the settings fallback available',
        (tester) async {
      gps.permission = LocationPermission.whileInUse;
      messenger.setMockMethodCallHandler(channel, (_) async {
        if (failure == 'missing_bridge') throw MissingPluginException();
        throw PlatformException(code: 'native_unavailable');
      });
      await start(tester);
      await acceptDisclosure(tester);
      expect(find.text('Ouvrir les réglages'), findsOneWidget);
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(allowed, isFalse);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  testWidgets('iOS waits for the native decision before showing settings',
      (tester) async {
    gps.permission = LocationPermission.whileInUse;
    final decision = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) {
      nativeCalls.add(call);
      return decision.future;
    });
    await start(tester);
    await acceptDisclosure(tester);
    expect(nativeCalls, hasLength(1));
    expect(allowed, isNull);
    expect(find.text('Ouvrir les réglages'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    gps.permission = LocationPermission.always;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    decision.complete(true);
    await tester.pumpAndSettle();
    expect(allowed, isTrue);
    expect(gps.settingsOpened, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('closing the driver screen during a request starts no work',
      (tester) async {
    gps.permission = LocationPermission.whileInUse;
    final decision = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (_) => decision.future);
    await start(tester);
    await acceptDisclosure(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    gps.permission = LocationPermission.always;
    decision.complete(true);
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
    expect(gps.settingsOpened, 0);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('concurrent iOS upgrades share one native request',
      (tester) async {
    gps.permission = LocationPermission.whileInUse;
    final decision = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) {
      nativeCalls.add(call);
      return decision.future;
    });
    final first = DriverAlwaysLocationPermission.requestUpgrade();
    final second = DriverAlwaysLocationPermission.requestUpgrade();
    await tester.pump();
    expect(nativeCalls, hasLength(1));
    gps.permission = LocationPermission.always;
    decision.complete(true);
    expect(await first, LocationPermission.always);
    expect(await second, LocationPermission.always);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final permission in [
    LocationPermission.denied,
    LocationPermission.deniedForever,
    LocationPermission.always,
  ]) {
    testWidgets('native upgrade is skipped for iOS permission $permission',
        (tester) async {
      gps.permission = permission;
      expect(await DriverAlwaysLocationPermission.requestUpgrade(), permission);
      expect(nativeCalls, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  for (final permission in [
    LocationPermission.denied,
    LocationPermission.whileInUse,
  ]) {
    testWidgets('client location remains when-in-use from $permission',
        (tester) async {
      gps.permission = permission;
      await FreshPositionHelper.ensureLocationAccess();
      expect(gps.permission, LocationPermission.whileInUse);
      expect(gps.permissionRequests,
          permission == LocationPermission.denied ? 1 : 0);
      expect(nativeCalls, isEmpty);
      expect(gps.settingsOpened, 0);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}
