import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/theme/app_theme.dart';
import 'package:pickupoint/features/client/widgets/client_referral_entry.dart';

class _PreviewAssets extends CachingAssetBundle {
  _PreviewAssets(this.logo);
  final Uint8List logo;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'assets/logo_header.png') return ByteData.sublistView(logo);
    return rootBundle.load(key);
  }
}

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Roboto');
    fonts.addFont(
      File(
        const String.fromEnvironment('PREVIEW_FONT'),
      ).readAsBytes().then(ByteData.sublistView),
    );
    await fonts.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final active in [true, false]) {
    testWidgets('aperçu en-tête parrainage $active', (tester) async {
      final logo = await tester.runAsync(
        () => File(
          '../release-preparation/denkma-header-logo/logo_header.png',
        ).readAsBytes(),
      );
      tester.view.physicalSize = const Size(412, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _PreviewAssets(logo!),
          child: MaterialApp(
            theme: AppTheme.light.copyWith(
              textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Roboto'),
              primaryTextTheme: AppTheme.light.primaryTextTheme.apply(
                fontFamily: 'Roboto',
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: AppTheme.light.filledButtonTheme.style?.copyWith(
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontFamily: 'Roboto', fontSize: 14),
                  ),
                ),
              ),
            ),
            home: Builder(
              builder: (context) {
                return RepaintBoundary(
                  key: key,
                  child: DefaultTabController(
                    length: 2,
                    child: Scaffold(
                      appBar: AppBar(
                        automaticallyImplyLeading: false,
                        toolbarHeight: ClientReferralToolbar.height(context),
                        title: ClientReferralToolbar(
                          offer: active ? {'sponsor_bonus_xof': 100000} : null,
                          actions: [
                            for (final icon in [
                              Icons.account_circle,
                              Icons.notifications_outlined,
                              Icons.workspace_premium_outlined,
                              Icons.handshake_outlined,
                              Icons.support_agent,
                            ])
                              IconButton(onPressed: () {}, icon: Icon(icon)),
                          ],
                          onPressed: () {},
                        ),
                        bottom: const TabBar(
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white70,
                          indicatorColor: Colors.white,
                          tabs: [
                            Tab(text: 'En cours'),
                            Tab(text: 'Terminés'),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../release-preparation/denkma-header-logo/preview-${active ? "active" : "inactive"}.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
