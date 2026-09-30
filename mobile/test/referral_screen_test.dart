import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/features/client/widgets/client_referral_entry.dart';
import 'package:pickupoint/shared/screens/referral_screen.dart';
import 'package:pickupoint/shared/utils/currency_format.dart';

void main() {
  Map<String, dynamic> record(String name, {String status = 'qualified'}) => {
        'referred_name': name,
        'status': status,
        'reward_metric_count': 2,
        'reward_count': 2,
        'reward_metric_label': 'colis livrés',
        'payments': {
          'sponsor': {'status': 'pending', 'amount_xof': 750},
          'referred': {
            'status': 'confirmed',
            'amount_xof': 450,
            'paid_at': '2026-09-30T10:00:00Z'
          },
        },
      };

  Map<String, dynamic> info(
          {List<Map<String, dynamic>> items = const [], int total = 0}) =>
      {
        'can_apply_now': true,
        'can_be_referred': true,
        'can_sponsor': true,
        'referral_code': 'TEST-CODE',
        'apply_rule': 'Avant le premier envoi.',
        'reward_rule': 'Après deux colis livrés.',
        'invitation_offers': [
          {
            'label': 'Nouveau client',
            'referred_role': 'client',
            'sponsor_bonus_xof': 750,
            'referred_bonus_xof': 450,
            'apply_rule': 'Avant le premier envoi.',
            'reward_rule': 'Après deux colis livrés.',
            'share_message': 'Invitation TEST-CODE'
          },
        ],
        'sponsored_referrals': {
          'total': total,
          'items': items,
          'total_sponsor_bonus_xof': 8250,
          'sponsor_due_xof': 750
        },
      };

  Future<void> show(WidgetTester tester, Map<String, dynamic> data,
      {String? code}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clientReferralProvider.overrideWith((ref) async => data),
        referralPageProvider.overrideWith((ref, skip) async => {
              'items': [record('Filleul page $skip')],
              'total': 12
            }),
      ],
      child: MaterialApp(home: ReferralScreen(initialCode: code)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'progression et primes propres au bénéficiaire sans infos internes',
      (tester) async {
    final data = info(items: [record('Awa')], total: 1);
    data['received_referral'] = {
      ...record('Moi', status: 'partially_paid'),
      'payment_history': [
        {'note': 'PRIVATE'}
      ],
    };
    await show(tester, data);
    expect(find.text('Mon parrainage'), findsOneWidget);
    expect(find.textContaining('Payé hors plateforme'), findsWidgets);
    expect(find.textContaining('30/09/2026'), findsOneWidget);
    expect(find.text('PRIVATE'), findsNothing);
    await tester.scrollUntilVisible(find.text('Awa'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('À payer par Denkma'), findsOneWidget);
    expect(find.text('Awa'), findsOneWidget);
  });

  testWidgets('lien de parrainage préremplit sans appliquer automatiquement',
      (tester) async {
    await show(tester, info(), code: 'ami-code');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'AMI-CODE');
    expect(find.text('Appliquer'), findsOneWidget);
    expect(find.text('Mon parrainage'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('étapes reprennent les conditions et montants de l’offre',
      (tester) async {
    final data = info();
    final offer = (data['invitation_offers'] as List).first as Map;
    offer['sponsor_bonus_xof'] = 2400;
    offer['apply_rule'] = 'Code applicable jusqu’à trois envois.';
    offer['reward_rule'] = 'Prime débloquée après cinq colis livrés.';
    await show(tester, data);
    await tester.scrollUntilVisible(
        find.text('Comment obtenir votre prime ?'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Pour vous : ${formatXof(2400)}'), findsOneWidget);
    expect(find.textContaining(offer['apply_rule'] as String), findsOneWidget);
    expect(find.textContaining(offer['reward_rule'] as String), findsOneWidget);
    expect(find.textContaining('4. Une fois le parrainage validé'),
        findsOneWidget);
    expect(find.textContaining('créditent pas votre wallet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lien ne propose pas la saisie si compte déjà parrainé',
      (tester) async {
    await show(tester, {...info(), 'can_apply_now': false}, code: 'AUTRE');
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.textContaining('ne peut plus ajouter un parrain'), findsOneWidget);
  });

  testWidgets('totaux globaux et voir plus accèdent à la page suivante',
      (tester) async {
    await show(tester, info(items: [record('Premier')], total: 12));
    expect(find.text('Mes filleuls (12)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Voir plus'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(
        find.text('Payé hors plateforme : ${formatXof(8250)}'), findsOneWidget);
    await tester.tap(find.text('Voir plus'));
    await tester.pumpAndSettle();
    expect(find.text('Filleul page 10'), findsOneWidget);
    expect(find.text('Premier'), findsNothing);
    await tester.ensureVisible(find.text('Précédent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Précédent'));
    await tester.pumpAndSettle();
    expect(find.text('Premier'), findsOneWidget);
  });

  testWidgets('écran étroit et texte agrandi restent lisibles sans débordement',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(
        tester,
        info(
            items: [record('Un nom de filleul particulièrement long')],
            total: 12));
    await tester.scrollUntilVisible(find.text('Voir plus'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ancien crédit wallet jamais annoncé comme un nouveau paiement externe',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ReferralPaymentSummary(
      payment: {
        'status': 'legacy_wallet',
        'amount_xof': 800,
        'paid_amount_xof': 800
      },
      qualified: true,
    ))));
    expect(find.textContaining('Ancien crédit wallet'), findsOneWidget);
    expect(find.textContaining('Payé hors plateforme'), findsNothing);
    expect(find.textContaining('800'), findsOneWidget);
  });

  testWidgets('échec de chargement propose une nouvelle tentative',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clientReferralProvider.overrideWith((ref) async {
          if (calls++ == 0) throw Exception('network');
          return info();
        })
      ],
      child: const MaterialApp(home: ReferralScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Réessayer'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Réessayer'), findsNothing);
    expect(find.text('Votre code : TEST-CODE'), findsOneWidget);
  });
}
