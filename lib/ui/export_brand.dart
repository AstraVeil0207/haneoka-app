import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<ui.Image>? _logo;
Future<ui.Image> loadExportBrandLogo() => _logo ??= () async {
  final bytes = await rootBundle.load(
    'assets/brand/android-chrome-512x512.png',
  );
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  return image;
}();

void paintExportBrand(
  Canvas canvas,
  ThemeData theme,
  Rect bounds,
  ui.Image logo,
) {
  canvas.save();
  canvas.translate(bounds.left, bounds.top);
  canvas.scale(bounds.width / 184);
  final scheme = theme.colorScheme;
  final name = TextPainter(
    text: TextSpan(
      text: 'haneoka',
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final url = TextPainter(
    text: TextSpan(
      text: 'haneoka.org',
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  name.paint(canvas, Offset(184 - name.width, 2));
  url.paint(canvas, Offset(184 - url.width, 30));
  canvas.drawImageRect(
    logo,
    Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
    const Rect.fromLTWH(0, 0, 48, 48),
    Paint(),
  );
  name.dispose();
  url.dispose();
  canvas.restore();
}

class ExportBrand extends StatelessWidget {
  const ExportBrand({super.key, this.width = 184});
  final double width;
  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image>(
    future: loadExportBrandLogo(),
    builder: (context, snapshot) => SizedBox(
      width: width,
      height: width / 184 * 52,
      child: snapshot.data == null
          ? null
          : CustomPaint(
              painter: _BrandPainter(Theme.of(context), snapshot.data!),
            ),
    ),
  );
}

class _BrandPainter extends CustomPainter {
  _BrandPainter(this.theme, this.logo);
  final ThemeData theme;
  final ui.Image logo;
  @override
  void paint(Canvas canvas, Size size) =>
      paintExportBrand(canvas, theme, Offset.zero & size, logo);
  @override
  bool shouldRepaint(_BrandPainter oldDelegate) =>
      oldDelegate.theme != theme || oldDelegate.logo != logo;
}
