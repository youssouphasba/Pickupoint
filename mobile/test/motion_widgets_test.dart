import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/theme/app_motion.dart';
import 'package:pickupoint/shared/widgets/app_launch_reveal.dart';
import 'package:pickupoint/shared/widgets/parcel_status_badge.dart';

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

    expect(find.byType(Image), findsOneWidget);
    expect(finished, isFalse);

    await tester.pump(AppMotion.launch + AppMotion.fast);
    await tester.pump();

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
    await tester.pumpAndSettle();

    expect(find.text('LIVRÉ'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });
}
