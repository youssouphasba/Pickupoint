import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/features/client/widgets/client_referral_entry.dart';

void main() {
  final data = <String, dynamic>{
    'can_apply_now': true,
    'can_be_referred': true,
    'can_sponsor': true,
    'enabled': true,
    'referral_code': 'TEST123',
    'referral_sponsor_bonus_xof': 750,
    'referral_referred_bonus_xof': 450,
    'apply_rule': 'Avant votre premier envoi.',
    'reward_rule': 'Après deux colis livrés par votre proche.',
    'share_message': 'Mon invitation avec le code TEST123.',
  };

  Future<void> show(WidgetTester tester, Map<String, dynamic> values) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [clientReferralProvider.overrideWith((ref) async => values)],
      child: const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Column(children: [
          ReferralCodeEntry(),
          ReferralInviteCard(),
        ]))),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('code proposé uniquement si le serveur autorise son application',
      (tester) async {
    await show(tester, {...data, 'can_apply_now': false, 'can_sponsor': false});
    expect(find.text('Vous avez un code parrainage ?'), findsNothing);
    expect(find.text('Inviter un proche'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('programme désactivé ne propose aucune invitation',
      (tester) async {
    await show(tester, {...data, 'enabled': false, 'can_be_referred': false});
    expect(find.text('Vous avez un code parrainage ?'), findsNothing);
    expect(find.text('Inviter un proche'), findsNothing);
  });

  testWidgets('conditions réelles et saisie sur petit écran avec texte agrandi',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(tester, data);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Vous avez un code parrainage ?'));
    await tester.pumpAndSettle();
    expect(find.text(data['apply_rule'] as String), findsOneWidget);
    expect(find.text(data['reward_rule'] as String), findsNWidgets(2));
    final apply = find.widgetWithText(FilledButton, 'Appliquer');
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'TEST123');
    await tester.pump();
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invitation utilise les montants et le texte configurés',
      (tester) async {
    await show(tester, data);
    expect(find.textContaining('750'), findsOneWidget);
    expect(find.textContaining('450'), findsOneWidget);
    await tester.tap(find.text('Inviter un proche'));
    await tester.pumpAndSettle();
    expect(find.text('Votre code : TEST123'), findsOneWidget);
    expect(find.text(data['share_message'] as String), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
