import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/features/client/widgets/client_referral_entry.dart';
import 'package:pickupoint/shared/utils/currency_format.dart';

void main() {
  final client = {'referred_role': 'client', 'sponsor_bonus_xof': 1250};
  final driver = {'referred_role': 'driver', 'sponsor_bonus_xof': 5000};
  Map<String, dynamic> info() => {
        'enabled': true,
        'can_sponsor': true,
        'referral_code': 'INVITE',
        'invitation_offers': [driver, client],
      };

  test('montant client issu de son offre, sans maximum trompeur', () {
    expect(referralRewardOffer(info()), client);
    expect(referralRewardOffer({...info(), 'enabled': false}), isNull);
    expect(referralRewardOffer({...info(), 'can_sponsor': false}), isNull);
    expect(referralRewardOffer({...info(), 'referral_code': ''}), isNull);
    expect(referralRewardOffer({...info(), 'invitation_offers': []}), isNull);
    expect(
        referralRewardOffer({
          ...info(),
          'invitation_offers': [
            {...client, 'sponsor_bonus_xof': 0},
          ]
        }),
        isNull);
    expect(referralRewardOffer(null), isNull);
    expect(
        referralRewardOffer({
          ...info(),
          'invitation_offers': [driver]
        }),
        driver);
  });

  for (final width in [320.0, 390.0, 600.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets(
          'bouton accessible et en-tête sans débordement $width / $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var opened = false;
        await tester.pumpWidget(MaterialApp(
            home: Builder(
          builder: (context) => Scaffold(
              appBar: AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: ClientReferralToolbar.height(context),
            title: ClientReferralToolbar(
              offer: client,
              actions: List.generate(
                  4,
                  (_) => IconButton(
                      onPressed: () {}, icon: const Icon(Icons.person))),
              onPressed: () => opened = true,
            ),
          )),
        )));
        expect(find.text('Gagne ${formatXof(1250)}'), findsOneWidget);
        expect(find.text('Denkma'), findsOneWidget);
        expect(find.byType(IconButton), findsNWidgets(4));
        await tester.tap(find.text('Gagne ${formatXof(1250)}'));
        expect(opened, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
