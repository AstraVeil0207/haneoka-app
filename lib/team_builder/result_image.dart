/// A search result as a shareable PNG, drawn as the website draws it
/// (`renderTeamResultImage` in `lit/shared/team-result-image.ts`): a
/// 1280-pixel page with the metrics, the five members and their snaps.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/painting.dart';

import '../core/net.dart';

class ResultImageCard {
  ResultImageCard({
    required this.title,
    required this.character,
    required this.image,
    required this.avatars,
    required this.attribute,
    required this.rarity,
    required this.attributeLabel,
    required this.rarityLabel,
    required this.leader,
  });
  final String title;
  final String character;
  final String image;
  final List<String> avatars;
  final String? attribute;
  final String? rarity;
  final String attributeLabel;
  final String rarityLabel;
  final bool leader;
}

class ResultImageTheme {
  ResultImageTheme({
    required this.surface,
    required this.container,
    required this.text,
    required this.muted,
    required this.primary,
    required this.outline,
  });
  final Color surface, container, text, muted, primary, outline;
}

class TeamResultImage {
  TeamResultImage({
    required this.title,
    required this.subtitle,
    required this.membersLabel,
    required this.snapshotsLabel,
    required this.leaderLabel,
    required this.emptyLabel,
    required this.imageUnavailableLabel,
    required this.members,
    required this.snapshots,
    required this.metrics,
    required this.footer,
    required this.theme,
  });
  final String title;
  final String subtitle;
  final String membersLabel;
  final String snapshotsLabel;
  final String leaderLabel;
  final String emptyLabel;
  final String imageUnavailableLabel;
  final List<ResultImageCard> members;
  final List<ResultImageCard?> snapshots;

  /// (label, value).
  final List<(String, String)> metrics;
  final List<String> footer;
  final ResultImageTheme theme;
}

Future<ui.Image?> _fetch(String source) async {
  try {
    final response = await netClient
        .get(Uri.parse(source))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final codec = await ui.instantiateImageCodec(response.bodyBytes);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    return image;
  } catch (_) {
    return null;
  }
}

Future<List<int>> renderTeamResultImage(TeamResultImage model) async {
  final cards = [...model.members, for (final card in model.snapshots) ?card];
  final sources = {
    for (final card in cards) ...[
      card.image,
      ?card.attribute,
      ?card.rarity,
      ...card.avatars,
    ],
  }..remove('');
  final images = <String, ui.Image?>{};
  await Future.wait([
    for (final source in sources)
      _fetch(source).then((image) => images[source] = image),
  ]);
  final rows = math.max(1, (model.metrics.length / 3).ceil());
  final hasSnapshots = model.snapshots.any((card) => card != null);
  const pageWidth = 1280.0;
  final pageHeight = 1480.0 + (rows - 1) * 122 - (hasSnapshots ? 0 : 140);
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  final t = model.theme;
  const margin = 48.0, gap = 16.0, width = 224.0;
  c.drawRect(
    const Rect.fromLTWH(0, 0, pageWidth, 16384),
    Paint()..color = t.surface,
  );

  /// `lines`: wraps by character, ellipsizing the last allowed line.
  void lines(
    String text,
    double x,
    double y,
    double max,
    double size, {
    int limit = 1,
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) {
    final style = TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color ?? t.text,
      height: 1,
    );
    double measure(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    void fill(String value, int line) => (TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout()).paint(c, Offset(x, y + line * (size + 6)));
    var used = 0;
    for (final paragraph in text.split(RegExp(r'\r?\n'))) {
      final chars = paragraph.runes.map(String.fromCharCode).toList();
      var line = '';
      for (final char in chars) {
        if (measure(line + char) <= max) {
          line += char;
          continue;
        }
        if (used == limit - 1) {
          while (line.isNotEmpty && measure('$line…') > max) {
            final runes = line.runes.toList()..removeLast();
            line = String.fromCharCodes(runes);
          }
          fill('$line…', used);
          return;
        }
        fill(line, used++);
        line = char;
      }
      if (used >= limit) return;
      fill(line, used++);
    }
  }

  void panel(double x, double y, double w, double h) => c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      const Radius.circular(16),
    ),
    Paint()..color = t.container,
  );

  bool image(String? source, double x, double y, double w, double h) {
    final loaded = source == null ? null : images[source];
    if (loaded == null) return false;
    final scale = math.min(w / loaded.width, h / loaded.height);
    final dw = loaded.width * scale, dh = loaded.height * scale;
    c.drawImageRect(
      loaded,
      Rect.fromLTWH(0, 0, loaded.width.toDouble(), loaded.height.toDouble()),
      Rect.fromLTWH(x + (w - dw) / 2, y + (h - dh) / 2, dw, dh),
      Paint()..filterQuality = FilterQuality.high,
    );
    return true;
  }

  lines(
    'haneoka',
    margin,
    32,
    1184,
    20,
    color: t.primary,
    weight: FontWeight.w700,
  );
  lines(model.title, margin, 76, 1184, 36, limit: 2, weight: FontWeight.w700);
  lines(model.subtitle, margin, 165, 1184, 20, color: t.muted);
  final columns = math.max(1, math.min(3, model.metrics.length));
  final metricWidth = (1184 - gap * (columns - 1)) / columns;
  for (final (index, (label, value)) in model.metrics.indexed) {
    final x = margin + index % 3 * (metricWidth + gap);
    final y = 208.0 + (index ~/ 3) * 122;
    panel(x, y, metricWidth, 106);
    lines(label, x + 16, y + 12, metricWidth - 32, 17, color: t.muted);
    lines(
      value,
      x + 16,
      y + 36,
      metricWidth - 32,
      29,
      color: t.primary,
      weight: FontWeight.w700,
    );
  }
  final membersY = 232.0 + rows * 122;
  lines(
    model.membersLabel,
    margin,
    membersY,
    1184,
    22,
    weight: FontWeight.w700,
  );
  void drawCard(ResultImageCard? card, int index, double y, bool member) {
    final x = margin + index * (width + gap), h = member ? 299.0 : 126.0;
    panel(x, y, width, h);
    if (card == null) {
      lines(
        model.emptyLabel,
        x + 16,
        y + h / 2 - 12,
        width - 32,
        20,
        limit: 2,
        color: t.muted,
      );
      return;
    }
    if (!image(card.image, x, y, width, h)) {
      lines(
        model.imageUnavailableLabel,
        x + 16,
        y + h / 2 - 12,
        width - 32,
        18,
        limit: 2,
        color: t.muted,
      );
    }
    if (!image(card.attribute, x + 8, y + 8, 32, 32)) {
      lines(
        card.attributeLabel,
        x + 8,
        y + 8,
        128,
        16,
        color: t.primary,
        weight: FontWeight.w600,
      );
    }
    if (!image(card.rarity, x + width - 40, y + 8, 32, 32)) {
      lines(
        card.rarityLabel,
        x + width - 48,
        y + 8,
        40,
        18,
        color: t.primary,
        weight: FontWeight.w600,
      );
    }
    if (card.leader) {
      final painter = TextPainter(
        text: TextSpan(
          text: model.leaderLabel,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = math.min(width - 16, painter.width + 24);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + width - w - 8, y + h - 36, w, 28),
          const Radius.circular(14),
        ),
        Paint()..color = t.surface,
      );
      lines(
        model.leaderLabel,
        x + width - w + 4,
        y + h - 31,
        w - 24,
        15,
        color: t.primary,
        weight: FontWeight.w700,
      );
    }
    lines(
      card.title,
      x,
      y + h + 14,
      width,
      20,
      limit: 2,
      weight: FontWeight.w600,
    );
    var avatarX = x;
    for (final avatar in card.avatars.take(5)) {
      if (image(avatar, avatarX, y + h + 71, 24, 24)) avatarX += 20;
    }
    lines(
      card.character,
      avatarX + (avatarX > x ? 8 : 0),
      y + h + 75,
      width - (avatarX - x) - 8,
      15,
      limit: 2,
      color: t.muted,
    );
  }

  for (final (index, card) in model.members.indexed) {
    drawCard(card, index, membersY + 40, true);
  }
  final snapshotsY = membersY + 605;
  lines(
    model.snapshotsLabel,
    margin,
    snapshotsY,
    1184,
    22,
    weight: FontWeight.w700,
  );
  for (final (index, card) in model.snapshots.indexed) {
    drawCard(card, index, snapshotsY + 40, false);
  }
  final footerY = snapshotsY + (hasSnapshots ? 350 : 210);
  c.drawLine(
    Offset(margin, footerY),
    Offset(1232, footerY),
    Paint()
      ..color = t.outline
      ..strokeWidth = 1,
  );
  for (final (index, line) in model.footer.take(4).indexed) {
    lines(line, margin, footerY + 18 + index * 25, 1184, 16, color: t.muted);
  }
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(pageWidth.toInt(), pageHeight.toInt());
  final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
  rendered.dispose();
  for (final loaded in images.values) {
    loaded?.dispose();
  }
  return data!.buffer.asUint8List();
}

/// Saves the PNG where the reader chooses, as `team.png`.
Future<void> saveResultImage(List<int> png) async {
  final bytes = png is Uint8List ? png : Uint8List.fromList(png);
  final path = await FilePicker.platform.saveFile(
    fileName: 'team.png',
    type: FileType.image,
    bytes: bytes,
  );
  if (path != null && !(Platform.isAndroid || Platform.isIOS)) {
    await File(path).writeAsBytes(bytes);
  }
}
