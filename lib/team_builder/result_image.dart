/// A search result as a shareable PNG, drawn as the website draws it
/// (`renderTeamResultImage` in `lit/shared/team-result-image.ts`): a
/// 1280-pixel page with the metrics, the five members and their snaps.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/painting.dart';

import '../core/net.dart';
import '../ui/card_artwork.dart';

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
    this.growth,
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
  final CardGrowthDisplay? growth;
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
    this.allEmptyLabel,
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
  final String? allEmptyLabel;
  final ResultImageTheme theme;
}

Future<ui.Image?> _fetch(String source) async {
  try {
    final response = await netClient
        .get(Uri.parse(source))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final codec = await ui.instantiateImageCodec(
      response.bodyBytes,
      targetWidth: 512,
      allowUpscaling: false,
    );
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
      if (card.growth case final growth?) ...[
        ?growth.rankIcon,
        ?growth.trainingIcon,
        ?growth.liveSkill?.icon,
        ?growth.gekisoSkill?.icon,
      ],
    ],
  }..remove('');
  final images = <String, ui.Image?>{};
  await Future.wait([
    for (final source in sources)
      _fetch(source).then((image) => images[source] = image),
  ]);
  final rows = math.max(1, (model.metrics.length / 3).ceil());
  final allEmpty =
      model.snapshots.length == 5 &&
      model.snapshots.every((card) => card == null);
  const pageWidth = 1280.0, margin = 48.0, gap = 16.0, width = 224.0;
  final t = model.theme;
  TextPainter layout(
    String text,
    double size,
    double maxWidth, {
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? t.text,
        height: (size + 6) / size,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(1, maxWidth));
  double textHeight(
    String text,
    double size,
    double maxWidth, {
    FontWeight weight = FontWeight.w400,
  }) {
    final painter = layout(text, size, maxWidth, weight: weight);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  final titleHeight = math.max(
    84.0,
    textHeight(model.title, 36, 1184, weight: FontWeight.w700),
  );
  final subtitleY = 81 + titleHeight;
  final metricsY =
      subtitleY + math.max(26.0, textHeight(model.subtitle, 20, 1184)) + 17;
  final columns = math.max(1, math.min(3, model.metrics.length));
  final metricWidth = (1184 - gap * (columns - 1)) / columns;
  final metricHeights = [
    for (var row = 0; row < rows; row++)
      model.metrics
          .skip(row * 3)
          .take(3)
          .fold<double>(
            106,
            (height, cell) => math.max(
              height,
              32 +
                  textHeight(cell.$1, 17, metricWidth - 32) +
                  textHeight(
                    cell.$2,
                    29,
                    metricWidth - 32,
                    weight: FontWeight.w700,
                  ),
            ),
          ),
  ];
  final metricOffsets = <double>[];
  var nextRow = metricsY;
  for (final height in metricHeights) {
    metricOffsets.add(nextRow);
    nextRow += height + gap;
  }
  double avatarWidth(ResultImageCard card) =>
      card.avatars.take(5).where((source) => images[source] != null).length *
      20.0;
  double rowExtra(Iterable<ResultImageCard?> cards) =>
      cards.whereType<ResultImageCard>().fold<double>(
        0,
        (height, card) => math.max(
          height,
          math.max(
                0,
                textHeight(card.title, 20, width, weight: FontWeight.w600) - 52,
              ) +
              math.max(
                0,
                textHeight(card.character, 15, width - avatarWidth(card) - 8) -
                    42,
              ),
        ),
      );
  final membersY = nextRow + 24;
  final snapshotsY = membersY + 605 + rowExtra(model.members);
  final footerY =
      snapshotsY + (allEmpty ? 210 : 350 + rowExtra(model.snapshots));
  final footerHeight = model.footer.fold<double>(
    0,
    (height, line) => height + textHeight(line, 16, 1184) + 4,
  );
  final pageHeight = footerY + 18 + footerHeight + 48;
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.drawRect(
    Rect.fromLTWH(0, 0, pageWidth, pageHeight),
    Paint()..color = t.surface,
  );
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
    final painter = layout(text, size, max, color: color, weight: weight);
    painter.paint(c, Offset(x, y));
    painter.dispose();
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
  lines(model.subtitle, margin, subtitleY, 1184, 20, color: t.muted);
  for (final (index, (label, value)) in model.metrics.indexed) {
    final x = margin + index % 3 * (metricWidth + gap);
    final y = metricOffsets[index ~/ 3];
    panel(x, y, metricWidth, metricHeights[index ~/ 3]);
    lines(label, x + 16, y + 12, metricWidth - 32, 17, color: t.muted);
    lines(
      value,
      x + 16,
      y + 20 + textHeight(label, 17, metricWidth - 32),
      metricWidth - 32,
      29,
      color: t.primary,
      weight: FontWeight.w700,
    );
  }
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
    final markWidth = width * (member ? 50 / 224 : 50 / 326);
    double imageHeight(String? source, double width) {
      final loaded = images[source];
      return loaded == null ? width : width * loaded.height / loaded.width;
    }

    if (!image(
      card.attribute,
      x,
      y,
      markWidth,
      imageHeight(card.attribute, markWidth),
    )) {
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
    if (!image(
      card.rarity,
      x + width - markWidth,
      y,
      markWidth,
      imageHeight(card.rarity, markWidth),
    )) {
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
    if (card.growth case final growth?) {
      String value(int? number) => number?.toString() ?? growth.unknown;
      void overlay(String text, double left, double top, double size) {
        final stroke = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w600,
              height: 1,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2
                ..color = const Color(0xFF000000),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final fill = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w600,
              height: 1,
              color: const Color(0xFFFFFFFF),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        stroke.paint(c, Offset(left, top));
        fill.paint(c, Offset(left, top));
        stroke.dispose();
        fill.dispose();
      }

      overlay(
        'Lv.${value(growth.level)}',
        x + width * .03,
        y + h * .97 - 28,
        28,
      );
      if (member) {
        image(growth.trainingIcon, x + width * .03, y + h * .85 - 24, 22, 22);
        overlay(
          value(growth.training),
          x + width * .03 + 26,
          y + h * .85 - 24,
          24,
        );
      }
      var left = x + width * .03;
      for (final skill in [growth.liveSkill, growth.gekisoSkill]) {
        if (skill == null || skill.icon.isEmpty) continue;
        image(skill.icon, left, y + h * .71 - 24, 24, 24);
        overlay(value(skill.level), left + 27, y + h * .71 - 24, 24);
        left += 58;
      }
      final rankWidth = width * (member ? 64 / 224 : 64 / 326);
      final rankHeight = imageHeight(growth.rankIcon, rankWidth);
      image(
        growth.rankIcon,
        x + width - rankWidth,
        y + h - rankHeight,
        rankWidth,
        rankHeight,
      );
      if (growth.rank == null) {
        overlay(
          growth.unknown,
          x + width - rankWidth * .65,
          y + h - rankHeight * .65,
          22,
        );
      }
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
          Rect.fromLTWH(x + 8, y + h * .56 - 28, w, 28),
          const Radius.circular(14),
        ),
        Paint()..color = t.surface,
      );
      lines(
        model.leaderLabel,
        x + 20,
        y + h * .56 - 23,
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
    final avatarY =
        y +
        h +
        19 +
        math.max(
          52,
          textHeight(card.title, 20, width, weight: FontWeight.w600),
        );
    var avatarX = x;
    for (final avatar in card.avatars.take(5)) {
      final loaded = images[avatar];
      if (loaded != null) {
        final edge = math.min(loaded.width, loaded.height).toDouble();
        c.drawImageRect(
          loaded,
          Rect.fromLTWH(
            (loaded.width - edge) / 2,
            (loaded.height - edge) / 4,
            edge,
            edge,
          ),
          Rect.fromLTWH(avatarX, avatarY, 24, 24),
          Paint()..filterQuality = FilterQuality.high,
        );
        avatarX += 20;
      }
    }
    lines(
      card.character,
      avatarX + (avatarX > x ? 8 : 0),
      avatarY + 4,
      width - (avatarX - x) - 8,
      15,
      limit: 2,
      color: t.muted,
    );
  }

  for (final (index, card) in model.members.indexed) {
    drawCard(card, index, membersY + 40, true);
  }
  lines(
    model.snapshotsLabel,
    margin,
    snapshotsY,
    1184,
    22,
    weight: FontWeight.w700,
  );
  if (allEmpty) {
    panel(margin, snapshotsY + 40, 1184, 90);
    lines(
      model.allEmptyLabel ?? model.emptyLabel,
      margin + 20,
      snapshotsY + 72,
      1144,
      20,
      color: t.muted,
    );
  } else {
    for (final (index, card) in model.snapshots.indexed) {
      drawCard(card, index, snapshotsY + 40, false);
    }
  }
  c.drawLine(
    Offset(margin, footerY),
    Offset(1232, footerY),
    Paint()
      ..color = t.outline
      ..strokeWidth = 1,
  );
  var footerLineY = footerY + 18;
  for (final line in model.footer) {
    lines(line, margin, footerLineY, 1184, 16, color: t.muted);
    footerLineY += textHeight(line, 16, 1184) + 4;
  }
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(pageWidth.toInt(), pageHeight.ceil());
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
  await FilePicker.saveFile(
    fileName: 'team.png',
    type: FileType.image,
    bytes: bytes,
  );
}
