import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pickupoint/core/location/driver_location_consent.dart';

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
  late ConsentGps gps;
  bool? allowed;

  setUp(() {
    gps = ConsentGps();
    GeolocatorPlatform.instance = gps;
    FlutterSecureStorage.setMockInitialValues({
      'driver_location_consent_v1': 'accepted',
    });
    allowed = null;
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalGps;
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
