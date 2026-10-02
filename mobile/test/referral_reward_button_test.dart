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

  for (final width in [320.0, 390.0, 412.0, 600.0]) {
    testWidgets('parrainage inactif : icônes réparties sur $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return Scaffold(
            appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: ClientReferralToolbar.height(context,
              hasReferral: false, actionCount: 5),
          title: ClientReferralToolbar(
            offer: null,
            actions: List.generate(
                5,
                (_) => IconButton(
                    onPressed: () {}, icon: const Icon(Icons.person))),
            onPressed: () {},
          ),
        ));
      })));
      expect(find.byType(ReferralRewardButton), findsNothing);
      final icons = find.byType(IconButton);
      final centers = List.generate(5, (i) => tester.getCenter(icons.at(i)));
      for (var i = 1; i < centers.length; i++) {
        expect(centers[i].dy, closeTo(centers.first.dy, .1));
        expect(centers[i].dx - centers[i - 1].dx,
            closeTo(centers[1].dx - centers[0].dx, .1));
      }
      expect(tester.getTopLeft(icons.first).dx, greaterThanOrEqualTo(16));
      expect(
          tester.getBottomRight(icons.last).dx, lessThanOrEqualTo(width - 16));
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
    });
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
            toolbarHeight: ClientReferralToolbar.height(context,
                hasReferral: true, actionCount: 5),
            title: ClientReferralToolbar(
              offer: {...client, 'sponsor_bonus_xof': 100000},
              actions: List.generate(
                  5,
                  (_) => IconButton(
                      onPressed: () {}, icon: const Icon(Icons.person))),
              onPressed: () => opened = true,
            ),
          )),
        )));
        final reward = find.text(formatXof(100000));
        expect(reward, findsOneWidget);
        expect(find.text('Denkma'), findsNothing);
        expect(find.byType(ClientHeaderLogo), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        expect(find.byType(IconButton), findsNWidgets(5));
        final iconCenter = tester.getCenter(find.byType(IconButton).first).dy;
        for (final icon in find.byType(IconButton).evaluate()) {
          expect(tester.getCenter(find.byWidget(icon.widget)).dy,
              closeTo(iconCenter, 0.1));
          expect(tester.getTopLeft(find.byWidget(icon.widget)).dx,
              greaterThanOrEqualTo(0));
          expect(tester.getBottomRight(find.byWidget(icon.widget)).dx,
              lessThanOrEqualTo(width));
        }
        expect(find.byType(SingleChildScrollView), findsNothing);
        await tester.tap(reward);
        expect(opened, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
