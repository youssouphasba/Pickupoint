import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/core/models/user.dart';
import 'package:pickupoint/features/client/widgets/client_referral_entry.dart';
import 'package:pickupoint/shared/screens/referral_screen.dart';
import 'package:pickupoint/shared/utils/currency_format.dart';

class ReferralAuth extends AuthNotifier {
  ReferralAuth({this.role = 'client', this.activeView});

  final String role;
  final String? activeView;

  @override
  Future<AuthState> build() async => AuthState(
        status: AuthStatus.authenticated,
        user: User(id: 'referral-user', phone: '+221700000000', role: role),
        activeView: activeView,
      );
}

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
      {String? code, String role = 'client', String? activeView}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(
            () => ReferralAuth(role: role, activeView: activeView)),
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

  testWidgets(
      'montant et objectif visibles, détails accessibles sans répétition',
      (tester) async {
    final data = info();
    final offer = (data['invitation_offers'] as List).first as Map;
    offer['sponsor_bonus_xof'] = 2400;
    offer['apply_rule'] = 'Code applicable jusqu’à trois envois.';
    offer['reward_rule'] = 'Prime débloquée après cinq colis livrés.';
    await show(tester, data);
    await tester.scrollUntilVisible(find.text('Inviter un client'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Pour vous : ${formatXof(2400)}'), findsOneWidget);
    expect(find.textContaining(offer['reward_rule'] as String), findsOneWidget);
    expect(find.textContaining(offer['apply_rule'] as String), findsNothing);
    await tester.ensureVisible(find.text('Conditions de l’invitation'));
    await tester.tap(find.text('Conditions de l’invitation'));
    await tester.pumpAndSettle();
    expect(find.textContaining(offer['apply_rule'] as String), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Comment ça marche ?'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Comment ça marche ?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('séparément de votre solde'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Map<String, dynamic> bothOffers() {
    final data = info();
    final offers = data['invitation_offers'] as List;
    offers.add(<String, Object>{
      ...Map<String, Object>.from(offers.first as Map),
      'label': 'Compte déjà livreur',
      'referred_role': 'driver',
      'reward_rule': 'Prime débloquée après trois livraisons effectuées.',
      'apply_rule': 'Code applicable avant la quatrième livraison effectuée.',
      'share_message': 'Invitation livreur TEST-CODE',
    });
    return data;
  }

  testWidgets(
      'un client ne voit aucune offre livreur même avec une ancienne réponse',
      (tester) async {
    await show(tester, bothOffers());
    expect(find.text('Inviter un client'), findsOneWidget);
    expect(find.text('Inviter un livreur'), findsNothing);
    expect(find.textContaining('livreur'), findsNothing);
    expect(find.textContaining('livraisons effectuées'), findsNothing);
  });

  testWidgets('un livreur peut inviter clients et livreurs, même en vue client',
      (tester) async {
    await show(tester, bothOffers(), role: 'driver', activeView: 'client');
    await tester.scrollUntilVisible(find.text('Inviter un livreur'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Inviter un client'), findsOneWidget);
    expect(find.text('Inviter un livreur'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Comment ça marche ?'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Comment ça marche ?'), findsOneWidget);
    expect(find.text('1. Partagez votre invitation.'), findsNothing);
  });

  testWidgets('aucune prime filleul n’affiche pas une ligne zéro dans l’offre',
      (tester) async {
    final data = info();
    ((data['invitation_offers'] as List).first as Map)['referred_bonus_xof'] =
        0;
    await show(tester, data);
    expect(find.textContaining('Pour votre filleul'), findsNothing);
    await tester.ensureVisible(find.text('Conditions de l’invitation'));
    await tester.tap(find.text('Conditions de l’invitation'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune prime prévue pour le filleul.'), findsOneWidget);
  });

  testWidgets('un compte non éligible ne reçoit aucune offre par défaut',
      (tester) async {
    await show(tester, bothOffers(), role: 'relay_agent');
    expect(find.textContaining('Inviter un'), findsNothing);
    expect(
        find.text('Aucune invitation disponible pour ce compte actuellement.'),
        findsOneWidget);
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
        authProvider.overrideWith(() => ReferralAuth()),
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
