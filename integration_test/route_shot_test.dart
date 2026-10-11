import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// Pictures one route at phone and desktop width:
/// `flutter test integration_test/route_shot_test.dart -d linux
///   --dart-define=HANEOKA_ROUTE=/calendar` with SHOTS set to a folder.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['SHOTS'] ?? '/tmp';
  const route = String.fromEnvironment('HANEOKA_ROUTE', defaultValue: '/');
  const scroll = int.fromEnvironment('HANEOKA_SCROLL');
  final name = route.replaceAll('/', '_');
  for (final (width, size) in [
    ('phone', const Size(412, 915)),
    ('desktop', const Size(1280, 860)),
  ]) {
    testWidgets('$route at $width width', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await app.main();
      for (var i = 0; i < 48; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump();
      }
      if (scroll > 0) {
        // In steps, so a long page scrolls past one viewport.
        for (var left = scroll; left > 0; left -= 500) {
          await tester.dragFrom(
            Offset(size.width * 0.75, size.height - 120),
            Offset(0, -(left < 500 ? left : 500) * 1.0),
          );
          await tester.pump();
        }
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 250)),
          );
          await tester.pump();
        }
      }
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$width$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }
}
