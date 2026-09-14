import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/theme/app_motion.dart';
import 'package:pickupoint/shared/widgets/app_launch_reveal.dart';
import 'package:pickupoint/shared/widgets/parcel_status_badge.dart';
import 'package:pickupoint/shared/widgets/pressable_scale.dart';

void main() {
  testWidgets('launch reveal finishes and exposes the application', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppLaunchReveal(
          onFinished: () => finished = true,
          child: const Text('Application prête'),
        ),
      ),
    );

    expect(find.byType(Image), findsNWidgets(2));
    expect(finished, isFalse);

    await tester.runAsync(() async {
      await Future.wait([
        precacheImage(const AssetImage('assets/logo_base.png'),
            tester.element(find.byType(AppLaunchReveal))),
        precacheImage(const AssetImage('assets/logo_moto.png'),
            tester.element(find.byType(AppLaunchReveal))),
      ]);
    });
    await tester.pumpAndSettle();

    expect(finished, isTrue);
    expect(find.text('Application prête'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('parcel status animates to its new value', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ParcelStatusBadge(
            key: ValueKey('status'),
            status: 'created',
          ),
        ),
      ),
    );

    expect(find.text('CRÉÉ'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ParcelStatusBadge(
            key: ValueKey('status'),
            status: 'delivered',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 180));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    expect(find.text('LIVRÉ'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('disabling a pressed button restores its scale', (tester) async {
    Widget button(bool enabled) => MaterialApp(
      home: Center(child: PressableScale(
        enabled: enabled,
        child: const SizedBox(width: 100, height: 50),
      )),
    );
    await tester.pumpWidget(button(true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressableScale)),
    );
    await tester.pump(AppMotion.fast);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        lessThan(1));
    await tester.pumpWidget(button(false));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
}
