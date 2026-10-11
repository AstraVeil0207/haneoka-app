import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/main.dart' as app;
import 'package:haneoka/ui/tile.dart';
import 'package:integration_test/integration_test.dart';

/// Walks the main screens against the live API and saves a picture of each.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['SHOTS'] ?? '/tmp';

  Future<void> wait(WidgetTester tester, double seconds) async {
    for (var i = 0; i < seconds * 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await wait(tester, 1.5);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  Future<void> untilTiles(WidgetTester tester) async {
    final tiles = find.descendant(
      of: find.byWidgetPredicate((w) => w is Tile || w is Card),
      matching: find.byType(InkWell),
    );
    for (var i = 0; i < 160 && tiles.evaluate().isEmpty; i++) {
      await wait(tester, 0.25);
    }
  }

  for (final (name, size) in [
    ('desktop', const Size(1280, 860)),
    ('phone', const Size(412, 915)),
  ]) {
    testWidgets('screens at $name width', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await app.main();
      await untilTiles(tester);
      await wait(tester, 4);
      await shot(tester, '$name-home');
      if (name == 'phone') {
        await tester.tap(find.byIcon(Symbols.menu_rounded).first);
        await wait(tester, 1);
      }
      await tester.tap(find.text('Library').first);
      await wait(tester, 1);
      await tester.tap(find.text('Songs').last);
      await untilTiles(tester);
      await wait(tester, 4);
      await shot(tester, '$name-songs');
      await tester.tap(
        find
            .descendant(of: find.byWidgetPredicate((w) => w is Tile || w is Card), matching: find.byType(InkWell))
            .first,
      );
      await wait(tester, 6);
      await shot(tester, '$name-song');
      await tester.tap(find.byType(BackButton).first);
      await wait(tester, 1);
      if (name == 'phone') {
        await tester.tap(find.byIcon(Symbols.menu_rounded).first);
        await wait(tester, 1);
        await shot(tester, '$name-drawer');
      }
      await tester.tap(find.text('Characters').last);
      await untilTiles(tester);
      await wait(tester, 3);
      await shot(tester, '$name-characters');
      await tester.tap(
        find
            .descendant(of: find.byWidgetPredicate((w) => w is Tile || w is Card), matching: find.byType(InkWell))
            .first,
      );
      await wait(tester, 6);
      await shot(tester, '$name-character');
      await tester.tap(find.byType(BackButton).first);
      await wait(tester, 1);
      if (name == 'phone') {
        await tester.tap(find.byIcon(Symbols.menu_rounded).first);
        await wait(tester, 1);
      }
      await tester.tap(find.text('Members').last);
      await untilTiles(tester);
      await wait(tester, 3);
      await shot(tester, '$name-cards');
      await tester.tap(
        find
            .descendant(of: find.byWidgetPredicate((w) => w is Tile || w is Card), matching: find.byType(InkWell))
            .first,
      );
      await wait(tester, 6);
      await shot(tester, '$name-card');
    });
  }
}
