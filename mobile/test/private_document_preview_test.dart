import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pickupoint/shared/widgets/private_document_preview.dart';

void main() {
  testWidgets(
      'Downloads once, hides in background and evicts decoded image on close',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final bytes =
        Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));
    var downloads = 0;
    await tester.pumpWidget(MaterialApp(
        home: PrivateDocumentPreview(
      title: 'Pièce privée',
      loadDocument: () async {
        downloads++;
        return bytes;
      },
    )));
    await tester.pumpAndSettle();
    expect(downloads, 1);
    final provider = tester.widget<Image>(find.byType(Image)).image;
    final key = await provider.obtainKey(ImageConfiguration.empty);
    expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Document masqué'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(downloads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Closing during a download does not retain an image or update a disposed widget',
      (tester) async {
    final completion = Completer<Uint8List>();
    await tester.pumpWidget(MaterialApp(
        home: PrivateDocumentPreview(
      title: 'Pièce privée',
      loadDocument: () => completion.future,
    )));
    await tester.pumpWidget(const SizedBox.shrink());
    completion.complete(Uint8List(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
