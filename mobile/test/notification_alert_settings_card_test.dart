import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/shared/widgets/notification_alert_settings_card.dart';

void main() {
  Future<void> showCard(WidgetTester tester,
      {required Future<bool> Function() openSettings}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: NotificationAlertSettingsCard(
                    openSettings: openSettings)))));
  }

  testWidgets('Android explains categories and opens app settings once',
      (tester) async {
    final gate = Completer<bool>();
    var calls = 0;
    await showCard(tester, openSettings: () {
      calls++;
      return gate.future;
    });
    await tester.tap(find.text('Quelles catégories régler ?'));
    await tester.pumpAndSettle();
    expect(find.text('Courses disponibles'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Suivi des colis'), findsOneWidget);
    final button = find.byType(OutlinedButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final throws in [false, true]) {
    testWidgets('settings opening failure is readable: exception=$throws',
        (tester) async {
      await showCard(tester, openSettings: () async {
        if (throws) throw StateError('private platform details');
        return false;
      });
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('Impossible d’ouvrir les réglages.'),
          findsOneWidget);
      expect(find.textContaining('private platform details'), findsNothing);
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNotNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('iOS explains phone-wide vibration settings', (tester) async {
    await showCard(tester, openSettings: () async => true);
    expect(find.textContaining('peut affecter les autres applications'),
        findsOneWidget);
    expect(find.text('Quelles catégories régler ?'), findsNothing);
    expect(find.text('Ouvrir les réglages Denkma'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('unsupported desktop hides mobile-only settings', (tester) async {
    await showCard(tester, openSettings: () async => true);
    expect(find.text('Sons et vibrations'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('small screen and enlarged text have no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await showCard(tester, openSettings: () async => true);
    await tester.ensureVisible(find.text('Quelles catégories régler ?'));
    await tester.tap(find.text('Quelles catégories régler ?'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
