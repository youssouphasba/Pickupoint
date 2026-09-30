import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/api/api_client.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/core/models/user.dart';
import 'package:pickupoint/shared/promotions/campaign_banner.dart';

class TestAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthState(
      status: AuthStatus.authenticated,
      user: User(id: 'user', phone: '', role: 'client'));
}

class CampaignApi extends ApiClient {
  int impressions = 0;
  final dismissed = <String>[];

  Response response(dynamic data) =>
      Response(requestOptions: RequestOptions(path: '/test'), data: data);

  @override
  Future<Response> getActiveCampaigns(
          {required String role, String placement = 'home'}) async =>
      response({
        'campaigns': [
          {
            'campaign_id': 'campaign',
            'title': 'Conseil utile',
            'body': 'Votre conseil',
            'cta_label': 'Voir'
          }
        ]
      });

  @override
  Future<Response> markCampaignImpression(String id,
      {required String role, bool countView = true, String? viewId}) async {
    impressions++;
    return response({'ok': true, 'allowed': true});
  }

  @override
  Future<Response> dismissCampaign(String id) async {
    dismissed.add(id);
    return response({'ok': true});
  }
}

void main() {
  testWidgets('carte sans débordement sur petit écran et texte agrandi',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = CampaignApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(TestAuth.new),
        apiClientProvider.overrideWithValue(api)
      ],
      child: const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CampaignBanner(role: 'client')))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Conseil utile'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('vue comptée seulement après défilement et fermeture mémorisée',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final api = CampaignApi();
    Widget app({bool spacer = true}) => ProviderScope(
          key: UniqueKey(),
          overrides: [
            authProvider.overrideWith(TestAuth.new),
            apiClientProvider.overrideWithValue(api)
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: Column(children: [
            if (spacer) const SizedBox(height: 900),
            const CampaignBanner(role: 'client'),
            const SizedBox(height: 900),
          ])))),
        );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(api.impressions, 0);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(api.impressions, 1);
    await tester.tap(find.byTooltip('Masquer cette campagne'));
    await tester.pumpAndSettle();
    expect(api.dismissed, ['campaign']);
    expect(find.text('Conseil utile'), findsNothing);
    await tester.pumpWidget(app(spacer: false));
    await tester.pumpAndSettle();
    expect(find.text('Conseil utile'), findsNothing);
    expect(api.impressions, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
