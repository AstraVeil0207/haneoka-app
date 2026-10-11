import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/main.dart' as app;
import 'package:haneoka/ui/tile.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_symbols_icons/symbols.dart';

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

  final tiles = find.descendant(
    of: find.byType(Tile),
    matching: find.byType(InkWell),
  );

  Future<void> untilTiles(WidgetTester tester) async {
    for (var i = 0; i < 160 && tiles.evaluate().isEmpty; i++) {
      await wait(tester, 0.25);
    }
    await wait(tester, 3);
  }

  for (final (name, size) in [
    ('desktop', const Size(1280, 860)),
    ('phone', const Size(412, 915)),
  ]) {
    final phone = name == 'phone';

    /// Opens the drawer on phones, unfolds [destination] by its chevron when
    /// [page] is not showing, and opens [page].
    Future<void> go(
      WidgetTester tester,
      String page, {
      String? destination,
    }) async {
      if (phone) {
        await tester.tap(find.byIcon(Symbols.menu_rounded).first);
        await wait(tester, 1);
      }
      if (destination != null && find.text(page).evaluate().isEmpty) {
        await tester.tap(
          find
              .descendant(
                of: find
                    .ancestor(
                      of: find.text(destination).first,
                      matching: find.byType(Row),
                    )
                    .first,
                matching: find.byType(InkResponse),
              )
              .last,
        );
        await wait(tester, 1);
      }
      await tester.tap(find.text(page).last);
      await wait(tester, 1);
    }

    Future<void> openFirstTile(WidgetTester tester) async {
      await tester.tap(tiles.first);
      await wait(tester, 6);
    }

    testWidgets('screens at $name width', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await app.main();
      await untilTiles(tester);
      await shot(tester, '$name-home');
      await go(tester, 'Songs', destination: 'Catalog');
      await untilTiles(tester);
      await shot(tester, '$name-songs');
      await openFirstTile(tester);
      await shot(tester, '$name-song');
      await tester.tap(find.byType(BackButton).first);
      await wait(tester, 1);
      if (phone) {
        await tester.tap(find.byIcon(Symbols.menu_rounded).first);
        await wait(tester, 1);
        await shot(tester, '$name-drawer');
        await tester.tap(find.text('Characters').last);
      } else {
        await go(tester, 'Characters');
      }
      await untilTiles(tester);
      await shot(tester, '$name-characters');
      await openFirstTile(tester);
      await shot(tester, '$name-character');
      await tester.tap(find.byType(BackButton).first);
      await wait(tester, 1);
      await go(tester, 'Members');
      await untilTiles(tester);
      await shot(tester, '$name-cards');
      await openFirstTile(tester);
      await shot(tester, '$name-card');
      await tester.tap(find.byType(BackButton).first);
      await wait(tester, 1);
      await go(tester, 'Settings');
      await wait(tester, 2);
      await shot(tester, '$name-settings');
    });
  }
}
