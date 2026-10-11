import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// Walks the main screens against the live API and saves a picture of each.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['SHOTS'] ?? '/tmp';

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 300));
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  Future<void> settle(WidgetTester tester, [int seconds = 6]) async {
    for (var i = 0; i < seconds * 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump();
    }
  }

  testWidgets('catalogue screens', (tester) async {
    await app.main();
    await settle(tester, 2);
    await shot(tester, 'catalog-index');
    for (final (label, name) in [('Songs', 'songs'), ('Characters', 'characters'), ('Members', 'cards'), ('Events', 'events')]) {
      final entry = find.text(label);
      if (entry.evaluate().isEmpty) continue;
      await tester.tap(entry.first);
      final tiles = find.descendant(of: find.byType(Card), matching: find.byType(InkWell));
      for (var i = 0; i < 160 && tiles.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump();
      }
      await settle(tester, 3);
      await shot(tester, 'list-$name');
      if (tiles.evaluate().isNotEmpty) {
        await tester.tap(tiles.first);
        await settle(tester, 8);
        await shot(tester, 'detail-$name');
        await tester.tap(find.byType(BackButton).last);
        await settle(tester, 1);
      }
      await tester.tap(find.byType(BackButton).last);
      await settle(tester, 1);
    }
  });
}
