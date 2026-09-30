import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/features/client/widgets/client_loyalty_card.dart';

void main() {
  final data = <String, dynamic>{
    'points': 80,
    'tier_label': 'Bronze',
    'discount_percent': 0,
    'progress': .8,
    'deliveries_remaining': 2,
    'points_per_delivery': 10,
    'next_tier': {'label': 'Argent', 'min_points': 100, 'discount_percent': 15},
    'tiers': [
      {'label': 'Bronze', 'min_points': 0, 'discount_percent': 0},
      {'label': 'Argent', 'min_points': 100, 'discount_percent': 15}
    ],
    'conditions': 'Les points sont crédités à l’expéditeur après livraison.',
  };

  testWidgets('carte et fenêtre suivent les règles serveur sur petit écran',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [clientLoyaltyProvider.overrideWith((ref) async => data)],
      child: const MaterialApp(
          home: Scaffold(
              body:
                  SingleChildScrollView(child: ClientLoyaltyCard(home: true)))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Encore 2 colis livrés'), findsOneWidget);
    await tester.tap(find.text('Votre fidélité'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Argent : dès 100 points · 15 % de réduction'),
        findsOneWidget);
    expect(find.text('Historique'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('niveau maximal n’affiche pas de faux objectif', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clientLoyaltyProvider.overrideWith((ref) async => {
              ...data,
              'tier_label': 'Or',
              'next_tier': null,
              'progress': 1.0,
              'discount_percent': 20
            })
      ],
      child: const MaterialApp(home: Scaffold(body: ClientLoyaltyCard())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Vous avez atteint le niveau le plus élevé.'),
        findsOneWidget);
    expect(find.text('20 % de réduction sur vos envois'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
