import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pickupoint/core/api/api_client.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/core/auth/biometric_auth_service.dart';
import 'package:pickupoint/core/auth/token_storage.dart';
import 'package:pickupoint/core/models/delivery_mission.dart';
import 'package:pickupoint/core/models/relay_point.dart';
import 'package:pickupoint/core/models/user.dart';
import 'package:pickupoint/core/models/wallet.dart';
import 'package:pickupoint/core/theme/app_theme.dart';
import 'package:pickupoint/core/notifications/notification_service.dart';
import 'package:pickupoint/core/providers/user_stats_provider.dart';
import 'package:pickupoint/features/client/screens/client_profile_screen.dart';
import 'package:pickupoint/features/client/screens/notification_settings_screen.dart';
import 'package:pickupoint/features/client/widgets/client_loyalty_card.dart';
import 'package:pickupoint/features/driver/providers/driver_provider.dart';
import 'package:pickupoint/features/driver/screens/driver_profile_screen.dart';
import 'package:pickupoint/features/driver/screens/driver_documents_screen.dart';
import 'package:pickupoint/features/relay/providers/relay_provider.dart';
import 'package:pickupoint/features/relay/screens/relay_profile_screen.dart';
import 'package:pickupoint/features/relay/screens/relay_public_profile_editor.dart';
import 'package:pickupoint/shared/profile/account_actions.dart';
import 'package:pickupoint/shared/profile/profile_widgets.dart';
import 'package:pickupoint/shared/screens/account_details_screen.dart';
import 'package:pickupoint/shared/screens/account_settings_screen.dart';
import 'package:pickupoint/shared/widgets/change_pin_tile.dart';
import 'package:pickupoint/shared/widgets/relay_public_details.dart';
import 'package:pickupoint/shared/widgets/support_whatsapp_tile.dart';

class ProfileAuth extends AuthNotifier {
  ProfileAuth(this.user, {this.activeView});
  final User user;
  final String? activeView;
  @override
  Future<AuthState> build() async => AuthState(
      status: AuthStatus.authenticated,
      user: user,
      accessToken: 'test',
      activeView: activeView);
  @override
  Future<void> fetchMe() async {}
}

class ProfileApi extends ApiClient {
  ProfileApi(this.user);
  final User user;
  Map<String, dynamic>? saved;
  Map<String, dynamic>? relaySaved;
  Map<String, dynamic>? pinSaved;
  Completer<void>? gate;
  bool fail = false;
  Response response(Object? data) =>
      Response(data: data, requestOptions: RequestOptions(path: '/test'));
  @override
  Future<Response> updateProfile(Map<String, dynamic> body) async {
    saved = body;
    if (gate != null) await gate!.future;
    if (fail) throw Exception('Sauvegarde indisponible');
    return response({...user.toJson(), ...body});
  }

  @override
  Future<Response> updateRelayPoint(
      String id, Map<String, dynamic> body) async {
    relaySaved = body;
    return response({
      'relay_id': id,
      'owner_user_id': user.id,
      'address': {
        'label': 'Rue 1',
        'city': 'Dakar',
        'geopin': {'lat': 14.7, 'lng': -17.4}
      },
      ...body
    });
  }

  @override
  Future<Response> updatePin(Map<String, dynamic> body) async {
    pinSaved = body;
    if (fail) throw Exception('PIN actuel incorrect');
    return response({});
  }
}

class ProfileBiometrics extends BiometricAuthService {
  ProfileBiometrics() : super(TokenStorage());
  bool enabled = true;
  String? newPin;
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<bool> canUseForPhone(String phone) async => enabled;
  @override
  Future<void> disable() async {
    enabled = false;
  }

  @override
  Future<void> updatePinIfEnabled(String phone, String pin) async {
    newPin = pin;
  }
}

const testWallet =
    Wallet(id: 'wallet', userId: 'user', balance: 1200, currency: 'XOF');
final testRelay = RelayPoint.fromJson({
  'relay_id': 'relay',
  'owner_user_id': 'user',
  'name': 'Boutique du quartier',
  'phone': '+221771234567',
  'address': {
    'label': 'Rue 1',
    'city': 'Dakar',
    'geopin': {'lat': 14.7, 'lng': -17.4},
    'notes': 'Entrée latérale'
  },
  'is_verified': true,
  'is_active': true,
  'max_capacity': 20,
  'current_load': 3,
  'opening_hours': {
    'monday': {'enabled': true, 'open': '08:00', 'close': '18:00'}
  },
  'opening_status': {
    'known': true,
    'is_open': true,
    'label': 'Ouvert · ferme à 18:00'
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['DENKMA_PROFILE_SCREENSHOTS'] != null) {
      final fontPath = Platform.environment['DENKMA_PROFILE_FONT'];
      if (fontPath != null) {
        final loader = FontLoader('Roboto')
          ..addFont(File(fontPath)
              .readAsBytes()
              .then((bytes) => bytes.buffer.asByteData()));
        await loader.load();
      }
      final iconsPath = Platform.environment['DENKMA_PROFILE_ICONS'];
      if (iconsPath != null) {
        final icons = FontLoader('MaterialIcons')
          ..addFont(File(iconsPath)
              .readAsBytes()
              .then((bytes) => bytes.buffer.asByteData()));
        await icons.load();
      }
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => switch (call.method) {
        'isLocationServiceEnabled' => true,
        'checkPermission' => 3,
        'getLocationAccuracy' => 1,
        _ => null,
      },
    );
  });

  User account(String role) => User(
        id: 'user',
        phone: '+221771111111',
        fullName: 'Awa Ndiaye',
        role: role,
        relayPointId: role == 'relay_agent' ? 'relay' : null,
        email: 'awa@example.com',
        isAvailable: true,
        profilePictureStatus: 'pending',
        notificationPrefs: const NotificationPrefs(emailEnabled: false),
      );

  Future<void> show(WidgetTester tester, Widget screen,
      {String role = 'client',
      String? activeView,
      ProfileApi? api,
      Future<RelayPoint?> Function()? relay,
      List<DeliveryMission> missions = const []}) async {
    final user = account(role);
    final boundary = GlobalKey();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider
              .overrideWith(() => ProfileAuth(user, activeView: activeView)),
          apiClientProvider.overrideWithValue(api ?? ProfileApi(user)),
          biometricAuthServiceProvider.overrideWithValue(ProfileBiometrics()),
          supportWhatsAppProvider.overrideWith((ref) async =>
              {'url': 'https://wa.me/221771234567', 'phone': '+221771234567'}),
          applicationInfoProvider.overrideWith((ref) async => PackageInfo(
              appName: 'Denkma',
              packageName: 'com.denkma.app',
              version: '1.2.3',
              buildNumber: '99')),
          userStatsProvider.overrideWith((ref) async => {
                'parcels_sent': 4,
                'parcels_received': 2,
                'parcels_delivered': 3
              }),
          clientLoyaltyProvider.overrideWith((ref) async => {
                'points': 40,
                'tier_label': 'Bronze',
                'progress': .4,
                'discount_percent': 0,
                'next_tier': null,
                'tiers': []
              }),
          driverWalletProvider.overrideWith((ref) async => testWallet),
          relayWalletProvider.overrideWith((ref) async => testWallet),
          myMissionsProvider.overrideWith((ref) async => missions),
          relayPointProfileProvider.overrideWith(
              (ref) async => relay == null ? testRelay : await relay()),
        ],
        child: MaterialApp(
            theme: AppTheme.light.copyWith(
              platform: TargetPlatform.android,
              appBarTheme: AppTheme.light.appBarTheme.copyWith(
                  titleTextStyle: AppTheme.light.appBarTheme.titleTextStyle
                      ?.copyWith(fontFamily: 'Roboto')),
            ),
            initialRoute: '/screen',
            routes: {
              '/': (_) => const Scaffold(),
              '/screen': (_) => RepaintBoundary(key: boundary, child: screen),
            })));
    await tester.pumpAndSettle();
    final output = Platform.environment['DENKMA_PROFILE_SCREENSHOTS'];
    if (output != null) {
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/${screen.runtimeType}-$role.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  }

  test('validation de photo conservée dans le modèle et le cache', () {
    final user = User.fromJson({
      'user_id': 'user',
      'role': 'driver',
      'phone': '+22177',
      'profile_picture_url': '/photo',
      'profile_picture_status': 'rejected',
      'profile_picture_rejected_reason': 'Photo floue'
    });
    final cached = User.fromJson(user.toJson()).copyWith(isAvailable: false);
    expect(cached.profilePictureStatus, 'rejected');
    expect(cached.profilePictureRejectedReason, 'Photo floue');
    expect(profilePhotoLabel(cached), 'Photo à remplacer');
  });

  test('support utilise le contact configuré et conserve le contexte du colis',
      () {
    final uri = supportWhatsAppUri('https://wa.me/221771234567?source=app',
        trackingCode: ' PKP-TEST ');
    expect(uri!.queryParameters['source'], 'app');
    expect(uri.queryParameters['text'], contains('PKP-TEST'));
    expect(supportWhatsAppUri('javascript:alert(1)'), isNull);
  });

  for (final role in ['client', 'driver', 'relay_agent']) {
    testWidgets('profil $role lisible sur écran étroit avec support direct',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final screen = switch (role) {
        'driver' => const DriverProfileScreen(),
        'relay_agent' => const RelayProfileScreen(),
        _ => const ClientProfileScreen()
      };
      await show(tester, screen, role: role);
      expect(find.byTooltip('Support WhatsApp'), findsOneWidget);
      expect(find.byTooltip('Paramètres'), findsOneWidget);
      expect(find.text('Changer de rôle'), findsNothing);
      expect(find.byTooltip('Numéro de téléphone vérifié'), findsNothing);
      expect(find.text('Hors ligne'), findsNothing);
      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Mes données'), 250,
          scrollable: scroll);
      expect(find.text('Mes données'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  for (final entry in [
    (const AccountSettingsScreen(), 'client'),
    (const AccountDetailsScreen(), 'client'),
    (const DriverDocumentsScreen(), 'driver'),
    (const RelayPublicProfileEditor(), 'relay_agent'),
  ]) {
    testWidgets('${entry.$1.runtimeType} sans débordement sur écran téléphone',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester, entry.$1, role: entry.$2);
      expect(find.byTooltip('Support WhatsApp'), findsOneWidget);
      final scroll = find.byType(Scrollable).first;
      for (var i = 0; i < 12; i++) {
        await tester.drag(scroll, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('erreur de fiche relais ne masque pas le compte ni le support',
      (tester) async {
    await show(tester, const RelayProfileScreen(),
        role: 'relay_agent',
        relay: () async => throw Exception('Erreur réseau'));
    expect(
        find.textContaining('Impossible de charger la fiche'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mon compte personnel'), 240,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Mes données'), findsOneWidget);
    expect(find.byTooltip('Support WhatsApp'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compte relais non rattaché conserve ses paramètres',
      (tester) async {
    await show(tester, const RelayProfileScreen(),
        role: 'relay_agent', relay: () async => null);
    expect(find.textContaining('Aucun point relais n’est encore rattaché'),
        findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mon compte personnel'), 240,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Paramètres'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'aperçu relais et fiche client partagent les mêmes horaires et état',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: RelayPublicDetails(
                    relay: testRelay, distance: '1,2 km')))));
    expect(find.text('Ouvert · ferme à 18:00'), findsOneWidget);
    expect(find.text('Depuis ma position : 1,2 km'), findsOneWidget);
    expect(find.text('Mardi: Fermé'), findsOneWidget);
    expect(find.text('Lundi: 08:00–18:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'paramètres communs ouvrent directement les préférences et mes données',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const AccountSettingsScreen()),
      GoRoute(
          path: '/settings/notifications',
          builder: (_, __) =>
              const Scaffold(body: Text('Préférences ouvertes'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      authProvider.overrideWith(() => ProfileAuth(account('relay_agent'))),
      biometricAuthServiceProvider.overrideWithValue(ProfileBiometrics()),
      supportWhatsAppProvider
          .overrideWith((ref) async => {'url': 'https://wa.me/221771234567'}),
      applicationInfoProvider.overrideWith((ref) async => PackageInfo(
          appName: 'Denkma',
          packageName: 'com.denkma.app',
          version: '1.2.3',
          buildNumber: '99')),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Préférences de notification'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Préférences de notification'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Préférences de notification'));
    await tester.pumpAndSettle();
    expect(find.text('Préférences ouvertes'), findsOneWidget);
  });

  testWidgets(
      'sauvegarde notification sérialisée sans perdre session ni préférence e-mail',
      (tester) async {
    final user = account('driver');
    final api = ProfileApi(user)..gate = Completer<void>();
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => ProfileAuth(user)),
      apiClientProvider.overrideWithValue(api),
      supportWhatsAppProvider.overrideWith((ref) async => {'url': ''}),
      notificationSettingsProvider.overrideWith(
          (ref) => throw Exception('Non disponible dans le test')),
    ]);
    addTearDown(container.dispose);
    await container.read(authProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NotificationSettingsScreen())));
    await tester.pumpAndSettle();
    final push =
        find.widgetWithText(SwitchListTile, 'Alertes sur mon téléphone');
    await tester.scrollUntilVisible(push, 250);
    await tester.tap(push);
    await tester.pump();
    expect(api.saved!['notification_prefs']['push'], false);
    expect(api.saved!['notification_prefs']['email'], false);
    expect(container.read(authProvider).valueOrNull!.isAuthenticated, true);
    expect(tester.widget<SwitchListTile>(push).onChanged, isNull);
    container.read(authProvider.notifier).switchView('client');
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(container.read(authProvider).valueOrNull!.effectiveRole, 'client');
    expect(
        container
            .read(authProvider)
            .valueOrNull!
            .user!
            .notificationPrefs
            .pushEnabled,
        false);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('interrupteur vibration réservé à Android: $platform',
        (tester) async {
      final user = account('driver');
      final api = ProfileApi(user);
      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => ProfileAuth(user)),
        apiClientProvider.overrideWithValue(api),
        supportWhatsAppProvider.overrideWith((ref) async => {'url': ''}),
        notificationSettingsProvider.overrideWith(
            (ref) => throw Exception('Non disponible dans le test')),
      ]);
      addTearDown(container.dispose);
      await container.read(authProvider.future);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NotificationSettingsScreen())));
      await tester.pumpAndSettle();
      final vibration =
          find.widgetWithText(SwitchListTile, 'Vibrations des notifications');
      if (platform == TargetPlatform.iOS) {
        expect(vibration, findsNothing);
        return;
      }
      await tester.scrollUntilVisible(vibration, 250);
      await tester.tap(vibration);
      await tester.pumpAndSettle();
      expect(api.saved!['notification_prefs']['android_vibration'], false);
      expect(api.saved!['notification_prefs']['push'], true);
      expect(api.saved!['notification_prefs']['email'], false);
      expect(tester.widget<SwitchListTile>(vibration).value, false);
      api.fail = true;
      await tester.tap(vibration);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(vibration).value, false);
      expect(tester.widget<SwitchListTile>(vibration).onChanged, isNotNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('modification du PIN actualise la connexion biométrique',
      (tester) async {
    final api = ProfileApi(account('driver'));
    final biometric = ProfileBiometrics();
    await tester.pumpWidget(ProviderScope(overrides: [
      authProvider.overrideWith(() => ProfileAuth(account('driver'))),
      apiClientProvider.overrideWithValue(api),
      biometricAuthServiceProvider.overrideWithValue(biometric)
    ], child: const MaterialApp(home: Scaffold(body: ChangePinTile()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier mon PIN'));
    await tester.pumpAndSettle();
    final inputs = find.byType(TextField);
    await tester.enterText(inputs.at(0), '1234');
    await tester.enterText(inputs.at(1), '4567');
    await tester.enterText(inputs.at(2), '4567');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(api.pinSaved!['new_pin'], '4567');
    expect(biometric.newPin, '4567');
    expect(find.text('PIN modifié.'), findsOneWidget);
  });

  testWidgets('course active protège la déconnexion même en mode client',
      (tester) async {
    final mission = DeliveryMission.fromJson({
      'mission_id': 'mission',
      'parcel_id': 'parcel',
      'status': 'in_progress',
      'created_at': DateTime.now().toIso8601String()
    });
    await show(tester, const Scaffold(body: AccountManagementSection()),
        role: 'driver', activeView: 'client', missions: [mission]);
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Terminez ou libérez'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'formulaire compte valide e-mail et ne sauvegarde pas une saisie invalide',
      (tester) async {
    final api = ProfileApi(account('client'));
    await show(tester, const AccountDetailsScreen(), api: api);
    final email = find.widgetWithText(TextFormField, 'E-mail (facultatif)');
    await tester.ensureVisible(email);
    await tester.enterText(email, 'invalid');
    await tester.ensureVisible(find.text('Enregistrer mes informations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer mes informations'));
    await tester.pumpAndSettle();
    expect(find.text('Saisissez une adresse e-mail valide.'), findsOneWidget);
    expect(api.saved, isNull);
  });

  testWidgets(
      'ancien relais peut sauvegarder ses jours et horaires sans modifier sa position',
      (tester) async {
    final api = ProfileApi(account('relay_agent'));
    final legacy = RelayPoint.fromJson({
      'relay_id': testRelay.id,
      'owner_user_id': 'user',
      'name': testRelay.name,
      'phone': testRelay.phone,
      'opening_hours': 'Lun-Sam 8h-20h',
      'address': {
        'label': testRelay.addressLabel,
        'city': testRelay.city,
        'notes': testRelay.addressNotes,
        'geopin': {'lat': testRelay.lat, 'lng': testRelay.lng},
      },
    });
    await show(tester, const RelayPublicProfileEditor(),
        role: 'relay_agent', api: api, relay: () async => legacy);
    final name = find.widgetWithText(TextFormField, 'Nom du relais');
    await tester.enterText(name, 'Boutique renommée');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Enregistrer ma fiche publique'), 350,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Enregistrer ma fiche publique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer ma fiche publique'));
    await tester.pumpAndSettle();
    expect(api.relaySaved!['name'], 'Boutique renommée');
    expect(api.relaySaved!['opening_hours'], isA<Map>());
    expect(api.relaySaved!['opening_hours']['monday'],
        {'enabled': true, 'open': '08:00', 'close': '20:00'});
    expect(api.relaySaved!['opening_hours']['sunday']['enabled'], false);
    expect(api.relaySaved!.containsKey('address'), false);
    expect(find.textContaining('Fiche publique enregistrée.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('cache du compte conserve les favoris et états métier', () {
    final user = User.fromJson({
      'user_id': 'user',
      'phone': '+221771111111',
      'role': 'driver',
      'is_available': true,
      'accepted_legal': true,
      'kyc_status': 'verified',
      'kyc_id_card_url': '/document',
      'deliveries_completed': 8,
      'average_rating': 4.5,
      'total_ratings_count': 3,
      'loyalty_points': 42,
      'referral_code': 'DENKMA-TEST',
      'favorite_addresses': [
        {'name': 'Maison', 'address': 'Rue 1', 'lat': 14.7, 'lng': -17.4}
      ],
    });
    final cached = User.fromJson(user.toJson());
    expect(cached.isAvailable, true);
    expect(cached.acceptedLegal, true);
    expect(cached.kycStatus, 'verified');
    expect(cached.kycIdCardUrl, '/document');
    expect(cached.favoriteAddresses.single.name, 'Maison');
    expect(cached.deliveriesCompleted, 8);
    expect(cached.averageRating, 4.5);
    expect(cached.loyaltyPoints, 42);
    expect(cached.referralCode, 'DENKMA-TEST');
  });

  testWidgets('échec réseau conserve les préférences et permet de réessayer',
      (tester) async {
    final api = ProfileApi(account('client'))..fail = true;
    await show(tester, const NotificationSettingsScreen(), api: api);
    final push =
        find.widgetWithText(SwitchListTile, 'Alertes sur mon téléphone');
    await tester.scrollUntilVisible(push, 250);
    await tester.pumpAndSettle();
    await tester.tap(push);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(push).value, true);
    expect(tester.widget<SwitchListTile>(push).onChanged, isNotNull);
    expect(find.textContaining('Sauvegarde indisponible'), findsOneWidget);
    api.fail = false;
    await tester.tap(push);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(push).value, false);
  });

  testWidgets(
      'vider l’e-mail est enregistré sans supprimer la bio masquée du client',
      (tester) async {
    final api = ProfileApi(account('client'));
    await show(tester, const AccountDetailsScreen(), api: api);
    final email = find.widgetWithText(TextFormField, 'E-mail (facultatif)');
    await tester.ensureVisible(email);
    await tester.enterText(email, '');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enregistrer mes informations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer mes informations'));
    await tester.pumpAndSettle();
    expect(api.saved!['email'], '');
    expect(api.saved!.containsKey('bio'), false);
    expect(find.text('Vos informations ont été enregistrées.'), findsOneWidget);
  });

  testWidgets('PIN refusé garde la fenêtre ouverte sans modifier la biométrie',
      (tester) async {
    final api = ProfileApi(account('client'))..fail = true;
    await show(tester, const Scaffold(body: ChangePinTile()), api: api);
    await tester.tap(find.text('Modifier mon PIN'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '1234');
    await tester.enterText(fields.at(1), '5678');
    await tester.enterText(fields.at(2), '5678');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PIN actuel incorrect'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation de suppression annulée ne détruit pas le compte',
      (tester) async {
    await show(tester, const Scaffold(body: AccountManagementSection()));
    await tester.tap(find.text('Supprimer mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    final confirmation =
        find.widgetWithText(FilledButton, 'Supprimer définitivement');
    expect(tester.widget<FilledButton>(confirmation).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'SUPPRIMER');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirmation).onPressed, isNotNull);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Supprimer mon compte'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disponibilité verrouillée pendant une mission active',
      (tester) async {
    final mission = DeliveryMission.fromJson({
      'mission_id': 'mission',
      'parcel_id': 'parcel',
      'status': 'assigned',
      'created_at': DateTime.now().toIso8601String()
    });
    await show(tester, const DriverProfileScreen(),
        role: 'driver', missions: [mission]);
    final toggle = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    expect(find.textContaining('Une course est en cours.'), findsOneWidget);
  });

  testWidgets(
      'retour demande confirmation quand des informations ne sont pas enregistrées',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
              body: TextButton(
                  onPressed: () => context.push('/settings/account'),
                  child: const Text('Ouvrir mon compte')))),
      GoRoute(
          path: '/settings/account',
          builder: (_, __) => const AccountDetailsScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      authProvider.overrideWith(() => ProfileAuth(account('client'))),
      supportWhatsAppProvider.overrideWith((ref) async => {'url': ''}),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.tap(find.text('Ouvrir mon compte'));
    await tester.pumpAndSettle();
    final email = find.widgetWithText(TextFormField, 'E-mail (facultatif)');
    await tester.ensureVisible(email);
    await tester.enterText(email, 'nouveau@example.com');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Continuer à modifier'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(email).controller!.text,
        'nouveau@example.com');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitter sans enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir mon compte'), findsOneWidget);
  });
}
