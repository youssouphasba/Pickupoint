import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/shared/widgets/animated_number_text.dart';

void main() {
  testWidgets('number reaches its real value after the reveal animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedNumberText(
          value: 24,
          formatter: (value) => value.round().toString(),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('24'), findsOneWidget);
  });
}
