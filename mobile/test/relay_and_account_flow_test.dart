import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/core/auth/biometric_auth_service.dart';
import 'package:pickupoint/core/models/relay_point.dart';
import 'package:pickupoint/core/models/user.dart';
import 'package:pickupoint/features/relay/providers/relay_provider.dart';
import 'package:pickupoint/features/relay/screens/relay_payments_screen.dart';
import 'package:pickupoint/features/relay/screens/relay_public_profile_editor.dart';
import 'package:pickupoint/shared/profile/account_actions.dart';
import 'package:pickupoint/shared/profile/biometric_settings_tile.dart';
import 'package:pickupoint/shared/utils/error_utils.dart';
import 'package:pickupoint/shared/widgets/relay_opening_hours_editor.dart';
import 'package:pickupoint/shared/widgets/support_whatsapp_tile.dart';

import 'profile_settings_test.dart'
    show ProfileAuth, ProfileApi, ProfileBiometrics;

const account = User(
    id: 'owner',
    phone: '+221771234567',
    fullName: 'Awa',
    role: 'relay_agent',
    relayPointId: 'relay');

class FlowApi extends ProfileApi {
  FlowApi() : super(account);
  String? verifiedPin;
  String? declared;
  bool pinFails = false;

  @override
  Future<Response> verifyPin(String pin) async {
    verifiedPin = pin;
    if (pinFails) throw Exception('Code PIN incorrect');
    return response({'verified': true});
  }

  @override
  Future<Response> getRelayFinancialActions(String id,
      {int skip = 0, bool pendingOnly = true}) async {
    final actions = [
      {
        'key': 'driver_payment',
        'label': 'Remettre la part du livreur',
        'amount_xof': 1400,
        'parcel_id': 'parcel',
        'tracking_code': 'PKP-TEST',
        'status': declared == null ? 'pending' : 'declared',
        'actionable': declared == null
      },
      {
        'key': 'denkma_payment',
        'label': 'Déclarer la part à régler à Denkma',
        'amount_xof': 450,
        'parcel_id': 'parcel',
        'tracking_code': 'PKP-TEST',
        'status': 'pending',
        'actionable': true
      },
    ];
    final items = actions
        .where((item) => !pendingOnly || item['actionable'] == true)
        .toList();
    return response({
      'actions': items,
      'pending_count': declared == null ? 2 : 1,
      'total': items.length,
      'has_more': false
    });
  }

  @override
  Future<Response> declareRelayFinancialAction(
      String relayId, String parcelId, String action) async {
    declared = '$relayId:$parcelId:$action';
    return response({'ok': true});
  }
}

class SetupBiometrics extends ProfileBiometrics {
  SetupBiometrics() {
    enabled = false;
  }
  bool confirmed = true;
  int confirmations = 0;
  String? savedPin;

  @override
  Future<bool> authenticateForSetup() async {
    confirmations++;
    return confirmed;
  }

  @override
  Future<void> saveCredentials(
      {required String phone, required String pin}) async {
    savedPin = pin;
    enabled = true;
  }
}

Future<void> show(
    WidgetTester tester, Widget widget, FlowApi api, SetupBiometrics biometrics,
    {RelayPoint? relay}) async {
  final router =
      GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => widget)]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [
    authProvider.overrideWith(() => ProfileAuth(account)),
    apiClientProvider.overrideWithValue(api),
    biometricAuthServiceProvider.overrideWithValue(biometrics),
    supportWhatsAppProvider.overrideWith((ref) async =>
        {'url': 'https://wa.me/221771234567', 'phone': '+221771234567'}),
    if (relay != null)
      relayPointProfileProvider.overrideWith((ref) async => relay),
  ], child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
}

void main() {
  test('biometric system errors use understandable messages', () {
    final message = friendlyError(const LocalAuthException(
        code: LocalAuthExceptionCode.noBiometricsEnrolled));
    expect(message, contains('réglages du téléphone'));
    expect(message, isNot(contains('LocalAuthException')));
  });

  testWidgets('relay day names remain readable with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: RelayOpeningHoursEditor(
                        value: normalizeRelayOpeningHours('08:00–20:00'),
                        onChanged: (_) {}))))));
    expect(tester.takeException(), isNull);
    expect(find.text('Dimanche'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Dimanche')).softWrap, false);
  });

  testWidgets(
      'biométrie activable ici après PIN validé et confirmation système',
      (tester) async {
    final api = FlowApi(), biometrics = SetupBiometrics();
    await show(
        tester, const Scaffold(body: BiometricSettingsTile()), api, biometrics);
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Activer'));
    await tester.pumpAndSettle();
    expect(api.verifiedPin, '1234');
    expect(biometrics.confirmations, 1);
    expect(biometrics.savedPin, '1234');
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(biometrics.enabled, false);
  });

  testWidgets('PIN incorrect : aucune activation biométrique', (tester) async {
    final api = FlowApi()..pinFails = true, biometrics = SetupBiometrics();
    await show(
        tester, const Scaffold(body: BiometricSettingsTile()), api, biometrics);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('Activer'));
    await tester.pumpAndSettle();
    expect(biometrics.confirmations, 0);
    expect(biometrics.savedPin, isNull);
    expect(find.textContaining('Code PIN incorrect'), findsOneWidget);
  });

  testWidgets('annulation système : rien n’est enregistré', (tester) async {
    final api = FlowApi(), biometrics = SetupBiometrics()..confirmed = false;
    await show(
        tester, const Scaffold(body: BiometricSettingsTile()), api, biometrics);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Activer'));
    await tester.pumpAndSettle();
    expect(biometrics.savedPin, isNull);
    expect(biometrics.enabled, false);
  });

  testWidgets(
      'suppression séparée de la déconnexion et double confirmation conservée',
      (tester) async {
    await show(
        tester,
        const Scaffold(
            body: Padding(
                padding: EdgeInsets.all(16),
                child: AccountManagementSection())),
        FlowApi(),
        SetupBiometrics());
    final logout = find.text('Se déconnecter'),
        deletion = find.widgetWithText(OutlinedButton, 'Supprimer mon compte');
    expect(tester.getTopLeft(deletion).dy - tester.getBottomRight(logout).dy,
        greaterThan(64));
    await tester.tap(deletion);
    await tester.pumpAndSettle();
    expect(find.text('Supprimer mon compte ?'), findsOneWidget);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Supprimer définitivement'));
    expect(button.onPressed, isNull);
  });

  testWidgets('emplacement ancien réutilisé sans resélection pour les horaires',
      (tester) async {
    final relay = RelayPoint.fromJson({
      'relay_id': 'relay',
      'name': 'Boutique',
      'phone': account.phone,
      'address': {'label': 'Rue actuelle', 'city': 'Dakar'},
      'latitude': '14.7',
      'longitude': '-17.4',
      'opening_hours': {
        'monday': {'enabled': true, 'open': '08:00', 'close': '20:00'}
      }
    });
    expect(relay.lat, 14.7);
    expect(relay.lng, -17.4);
    final api = FlowApi();
    await show(tester, const RelayPublicProfileEditor(), api, SetupBiometrics(),
        relay: relay);
    await tester.enterText(
        find.byType(TextFormField).first, 'Boutique renommée');
    await tester.pump();
    final save =
        find.widgetWithText(FilledButton, 'Enregistrer ma fiche publique');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.relaySaved, isNotNull);
    expect(api.relaySaved!.containsKey('address'), false);
    expect(find.textContaining('Confirmez l’emplacement'), findsNothing);
  });

  testWidgets(
      'actions dédiées : confirmation hors plateforme, statut et compteur actualisés',
      (tester) async {
    final api = FlowApi();
    await show(tester, const RelayPaymentsScreen(), api, SetupBiometrics());
    expect(find.text('2 action(s) à effectuer'), findsOneWidget);
    final declare =
        find.widgetWithText(FilledButton, 'J’ai effectué ce paiement').first;
    await tester.ensureVisible(declare);
    await tester.tap(declare);
    await tester.pumpAndSettle();
    expect(api.declared, isNull);
    expect(find.textContaining('Aucun paiement n’est effectué par ce bouton.'),
        findsOneWidget);
    await tester.tap(find.text('Oui, paiement effectué'));
    await tester.pumpAndSettle();
    expect(api.declared, 'relay:parcel:driver_payment');
    expect(find.text('1 action(s) à effectuer'), findsOneWidget);
    await tester.tap(find.text('Suivi'));
    await tester.pumpAndSettle();
    expect(find.text('Déclaré · validation Denkma en attente'), findsOneWidget);
  });
}
