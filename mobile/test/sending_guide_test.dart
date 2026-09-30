import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/shared/widgets/sending_guide.dart';

void main() {
  testWidgets('aucun accès en cas d’échec de configuration', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sendingGuideProvider
            .overrideWith((ref) async => throw Exception('offline'))
      ],
      child: const MaterialApp(home: Scaffold(body: SendingGuideEntry())),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
  });

  test('configuration absente ou incorrecte masquée', () {
    for (final data in [
      null,
      {},
      {'video_url': ''},
      {'video_url': 5},
      {'video_url': 'http://example.com/video.mp4'}
    ]) {
      expect(SendingGuide.fromJson(data), isNull);
    }
    expect(
        SendingGuide.fromJson({'video_url': 'https://example.com/video.mp4'}),
        isNotNull);
  });

  for (final compact in [false, true]) {
    testWidgets('accès masqué sans vidéo, compact=$compact', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [sendingGuideProvider.overrideWith((ref) async => null)],
        child: MaterialApp(
            home: Scaffold(body: SendingGuideEntry(compact: compact))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Comment envoyer un colis ?'), findsNothing);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('accès visible avec vidéo sur écran étroit, compact=$compact',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sendingGuideProvider.overrideWith((ref) async => SendingGuide(
              videoUrl: Uri.parse('https://example.com/video.mp4')))
        ],
        child: MaterialApp(
            home: Scaffold(body: SendingGuideEntry(compact: compact))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Comment envoyer un colis ?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
