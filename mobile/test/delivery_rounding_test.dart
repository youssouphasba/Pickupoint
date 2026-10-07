import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pickupoint/core/api/api_client.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/core/models/delivery_mission.dart';
import 'package:pickupoint/core/models/delivery_rounding.dart';
import 'package:pickupoint/core/models/parcel.dart';
import 'package:pickupoint/core/models/wallet.dart';
import 'package:pickupoint/features/client/screens/quote_screen.dart';
import 'package:pickupoint/shared/widgets/denkma_rounding_offer.dart';
import 'package:pickupoint/shared/widgets/loading_button.dart';

Map<String, dynamic> snapshot({double customer = 37, double driver = 14.1}) => {
      'rounding': {
        'version': 'customer_down_driver_up_v1',
        'customer_discount_xof': customer,
        'driver_bonus_xof': driver,
        'denkma_contribution_xof': 50.55,
      },
    };

Map<String, dynamic> quote({double price = 2300, bool promo = false}) => {
      'price': price,
      'breakdown': {
        'price_available': true,
        'delivery_mode': 'home_to_home',
        'who_pays': 'sender',
        'base': 2237,
        'distance_cost': 100,
        'distance_km': 1,
        'financial_rounding': snapshot(customer: promo ? 36 : 37),
      },
      if (promo) 'promo_applied': {'title': 'Réduction'},
      if (promo) 'discount_xof': 101,
    };

class RoundingApi extends ApiClient {
  final quotes = <Map<String, dynamic>>[];
  final creations = <Map<String, dynamic>>[];
  Completer<Response>? quoteGate;
  bool changedPrice = false;

  Response response(Object data) =>
      Response(data: data, requestOptions: RequestOptions(path: '/synthetic'));

  @override
  Future<Response> getQuote(Map<String, dynamic> data) async {
    quotes.add(Map.of(data));
    if (quoteGate != null) return quoteGate!.future;
    return response(quote(
        price: data['promo_code'] == null ? 2300 : 2200,
        promo: data['promo_code'] != null));
  }

  @override
  Future<Response> createParcel(Map<String, dynamic> data) async {
    creations.add(Map.of(data));
    if (changedPrice) {
      final request = RequestOptions(path: '/synthetic');
      throw DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 409,
          data: {'detail': 'Le tarif a changé. Actualisez le devis.'},
        ),
      );
    }
    return response({'parcel_id': 'parcel'});
  }
}

Future<void> pumpQuote(WidgetTester tester, RoundingApi api) async {
  final router = GoRouter(initialLocation: '/quote', routes: [
    GoRoute(
      path: '/quote',
      builder: (_, __) => QuoteScreen(data: {
        'quote': quote(),
        'recipient_name': 'Destinataire',
        'recipient_phone': '+221770000001',
        'formData': const {
          'delivery_mode': 'home_to_home',
          'weight_kg': 0.5,
          'origin_location': {
            'geopin': {'lat': 14.7, 'lng': -17.4}
          },
          'delivery_address': {
            'geopin': {'lat': 14.8, 'lng': -17.4}
          },
        },
      }),
    ),
    GoRoute(
      path: '/client/parcel/:id',
      builder: (_, __) => const Scaffold(body: Text('Colis créé')),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('quote, parcel, mission and income retain the authoritative benefits',
      () {
    final data = {
      'financial_rounding': snapshot(),
      'created_at': '2026-10-07T09:00:00Z',
    };
    expect(DeliveryRounding.fromJson({'breakdown': data}).customerDiscount, 37);
    expect(Parcel.fromJson(data).rounding.customerDiscount, 37);
    expect(DeliveryMission.fromJson(data).rounding.driverBonus, 14.1);
    final income = WalletActivityItem.fromJson({
      ...data,
      'tx_id': 'revenue',
      'kind': 'revenue',
      'status': 'recorded',
      'amount': 1650,
      'effect': 0,
      'created_at': '2026-10-07T09:00:00Z',
    });
    expect(income.amount, 1650);
    expect(income.rounding.driverBonus, 14.1);
  });

  test('locked contract takes precedence, legacy data invents no offer', () {
    expect(
        DeliveryRounding.fromJson({
          'financial_contract': {'breakdown': snapshot(customer: 12)},
          'financial_rounding': snapshot(),
        }).customerDiscount,
        12);
    expect(DeliveryRounding.fromJson({}).customerDiscount, 0);
    expect(
        DeliveryRounding.fromJson({
          'financial_rounding': {
            'rounding': {'customer_discount_xof': 37}
          }
        }).customerDiscount,
        0);
  });

  test('invalid benefits never surface as real financial rewards', () {
    final offer = DeliveryRounding.fromJson({
      'financial_rounding': {
        'rounding': {
          'version': 'customer_down_driver_up_v1',
          'customer_discount_xof': double.nan,
          'driver_bonus_xof': -50,
          'denkma_contribution_xof': double.infinity,
        }
      }
    });
    expect(offer.customerDiscount, 0);
    expect(offer.driverBonus, 0);
    expect(offer.denkmaContribution, 0);
  });

  testWidgets(
      'green offer keeps fractional information and includes driver gain',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DenkmaRoundingOffer(amount: 14.1, includedInGain: true),
      ),
    ));
    final text = tester.widget<Text>(find.textContaining('offerts par Denkma'));
    expect(text.data, contains('14,1 FCFA'));
    expect(text.data, contains('inclus dans votre gain'));
    expect(text.style?.color, Colors.green.shade800);
  });

  testWidgets('offer fits a small screen with large accessibility text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: DenkmaRoundingOffer(
              amount: 14.1, includedInGain: true, onColoredBackground: true),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('offerts par Denkma'), findsOneWidget);
  });

  testWidgets('zero or invalid amounts add no visual claim', (tester) async {
    for (final amount in [0.0, -5.0, double.nan, double.infinity]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: DenkmaRoundingOffer(amount: amount))));
      expect(find.textContaining('offerts par Denkma'), findsNothing);
    }
  });

  testWidgets('promo uses the full server quote, not a second local rounding',
      (tester) async {
    final api = RoundingApi();
    await pumpQuote(tester, api);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'promo');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(api.quotes.single['promo_code'], 'PROMO');
    expect(api.quotes.single['delivery_address'], isNotNull);
    expect(
        tester
            .widgetList<DenkmaRoundingOffer>(find.byType(DenkmaRoundingOffer))
            .every((offer) => offer.amount == 36),
        isTrue);
    await tester.ensureVisible(find.byType(LoadingButton));
    await tester.tap(find.text('Confirmer la demande'));
    await tester.pumpAndSettle();
    expect(api.creations.single['expected_price_xof'], 2200);
    expect(api.creations.single['promo_id'], 'PROMO');
    expect(find.text('Colis créé'), findsOneWidget);
  });

  testWidgets('confirmation is disabled while server quote is being refreshed',
      (tester) async {
    final api = RoundingApi()..quoteGate = Completer<Response>();
    await pumpQuote(tester, api);
    await tester.tap(find.byTooltip('Actualiser le devis'));
    await tester.pump();
    final button = tester.widget<LoadingButton>(find.byType(LoadingButton));
    expect(button.onPressed, isNull);
    expect(api.creations, isEmpty);
    api.quoteGate!.complete(api.response(quote(price: 2250)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(LoadingButton));
    await tester.tap(find.text('Confirmer la demande'));
    await tester.pumpAndSettle();
    expect(api.creations.single['expected_price_xof'], 2250);
  });

  testWidgets(
      'changed admin price remains unconfirmed and offers quote refresh',
      (tester) async {
    final api = RoundingApi()..changedPrice = true;
    await pumpQuote(tester, api);
    await tester.ensureVisible(find.byType(LoadingButton));
    await tester.tap(find.text('Confirmer la demande'));
    await tester.pumpAndSettle();
    expect(api.creations.single['expected_price_xof'], 2300);
    expect(find.text('Colis créé'), findsNothing);
    expect(
        find.text('Le tarif a changé. Actualisez le devis.'), findsOneWidget);
    expect(find.byTooltip('Actualiser le devis'), findsOneWidget);
  });
}
