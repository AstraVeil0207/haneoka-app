import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show
        haneokaProfileAssetRoot,
        loadHaneokaProfileAsset,
        loadHaneokaProfileString;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cassiopeia_plugin_our_notes/render_profile.dart';
import 'package:cassiopeia_renderer_flutter/overview.dart';

import '../chart/runtime_chart.dart';
import 'native_chart_document.dart';
import 'native_chart_input.dart';

/// App-owned I/O/format adaptation. The independent renderer receives normalized
/// coordinates, ready sprite meshes and color curves, never RuntimeChart.
final class ChartOverviewSource {
  const ChartOverviewSource(this.data, this.atlas);
  final ChartOverviewData data;
  final ui.Image atlas;
  void dispose() => atlas.dispose();
}

Future<ChartOverviewSource> loadChartOverviewSource(
  NativeChartDocument document,
  Future<Uint8List> Function(Uri) fetch, {
  RuntimeChart? chart,
}) async {
  final runtime =
      chart ??
      shiftNativeChart(
        document.chart ?? RuntimeChart.fromBytes(
          await fetch(document.scoreUri),
          includeVisualSource: true,
        ),
        document.audioOffsetMs,
      );
  final prefix = haneokaProfileAssetRoot;
  final archive = Map<String, Object?>.from(
    jsonDecode(
      await loadHaneokaProfileString('$prefix${document.noteSkin}.json'),
    ) as Map,
  );
  final styleRoot = jsonDecode(
    await loadHaneokaProfileString('${prefix}hold-styles.json'),
  ) as Map;
  final style = styleRoot[document.noteSkin] as Map;
  final imageBytes = await loadHaneokaProfileAsset(
    '$prefix${document.noteSkin}.png',
  );
  final codec = await ui.instantiateImageCodec(
    imageBytes.buffer.asUint8List(
      imageBytes.offsetInBytes,
      imageBytes.lengthInBytes,
    ),
  );
  final atlas = (await codec.getNextFrame()).image;
  codec.dispose();
  try {
    final geometry = ChartNoteGeometry(archive, atlas.width, atlas.height);
    const judgementWidth = 15.416889634999361;
    final glyphs = <String, List<ChartOverviewSpritePart>>{};
    final visual =
        runtime.visualNotes
            .where((n) => n.visible == true && isJudgementNote(n.operateType))
            .toList()
          ..sort(
            (a, b) => a.timeMicroseconds != b.timeMicroseconds
                ? a.timeMicroseconds.compareTo(b.timeMicroseconds)
                : a.id.compareTo(b.id),
          );
    String kind(RuntimeVisualNote n) => switch (n.operateType) {
      40 || 41 || 42 || 102 => 'flick',
      20 || 61 || 80 => 'slide-start',
      22 || 62 || 82 => 'slide-end',
      21 || 63 || 120 => 'slide-node',
      60 || 104 || 105 => 'trace',
      100 || 103 => 'guide',
      _ => 'tap',
    };
    final notes = <ChartOverviewNote>[];
    for (final n in visual) {
      final name = kind(n), key = '$name:${n.direction}:${n.visualWidth}';
      glyphs.putIfAbsent(
        key,
        () => [
          for (final part
              in geometry
                  .note(
                    kind: name,
                    direction: n.direction,
                    lane: n.visualLane,
                    laneWidth: n.visualWidth,
                    timeSeconds: 0,
                    flat: true,
                  )
                  .values)
            ChartOverviewSpritePart(
              GeometryShape(
                positions: Float32List.fromList([
                  for (final value in part.geometry.positions)
                    value / judgementWidth,
                ]),
                uv: part.geometry.uv,
                indices: part.geometry.indices,
              ),
              alpha: part.alpha,
            ),
        ],
      );
      notes.add(
        ChartOverviewNote(
          timeMs: n.timeMicroseconds / 1000,
          center: (n.visualLane + n.visualWidth / 2) / 24,
          glyph: key,
        ),
      );
    }
    int rgba(List values, [double alphaScale = 1]) {
      int byte(num value) => (value.toDouble().clamp(0.0, 1.0) * 255).round();
      return (byte((values[3] as num) * alphaScale) << 24) |
          (byte(values[0] as num) << 16) |
          (byte(values[1] as num) << 8) |
          byte(values[2] as num);
    }

    final normal = style['normal'] as Map,
        alpha = normal['alpha'] as List,
        glow = style['glow'] as Map;
    final colors = <ChartOverviewColorStop>[];
    for (final row in (normal['colors'] as List).cast<List>()) {
      final t = (row[0] as num).toDouble();
      final p =
          ((t - (alpha[0] as num)) / ((alpha[2] as num) - (alpha[0] as num)))
              .clamp(0.0, 1.0);
      final actualAlpha =
          (alpha[1] as num) + ((alpha[3] as num) - (alpha[1] as num)) * p;
      colors.add(
        ChartOverviewColorStop(t, rgba([row[1], row[2], row[3], actualAlpha])),
      );
    }
    final normalStroke = rgba(
      glow['color'] as List,
      (glow['intensity'] as num).toDouble() *
          (glow['enabledScale'] as num).toDouble(),
    );
    ChartOverviewCurve ease(int value) => switch (value) {
      1 => const ChartOverviewCurve(0, -1, 2, 0),
      2 => const ChartOverviewCurve(0, 1, 0, 0),
      _ => ChartOverviewCurve.identity,
    };
    final ribbons = <ChartOverviewRibbon>[];
    for (final line in runtime.visualLines) {
      if (!line.completeGeometry || line.points.length < 2) continue;
      final points = [...line.points]
        ..sort(
          (a, b) => a.timeMicroseconds != b.timeMicroseconds
              ? a.timeMicroseconds.compareTo(b.timeMicroseconds)
              : a.id.compareTo(b.id),
        );
      final segments = <ChartOverviewRibbonSegment>[];
      for (var i = 0; i < points.length - 1; i++) {
        final a = points[i], b = points[i + 1];
        if (b.timeMicroseconds <= a.timeMicroseconds) continue;
        segments.add(
          ChartOverviewRibbonSegment(
            startMs: a.timeMicroseconds / 1000,
            endMs: b.timeMicroseconds / 1000,
            leftStart: a.visualLane / 24,
            rightStart: (a.visualLane + a.visualWidth) / 24,
            leftEnd: b.visualLane / 24,
            rightEnd: (b.visualLane + b.visualWidth) / 24,
            leftCurve: ease(a.ease),
            rightCurve: ease(a.easeR),
          ),
        );
      }
      if (segments.isEmpty) continue;
      final guide = line.family == RuntimeVisualLineFamily.guide;
      ribbons.add(
        ChartOverviewRibbon(
          segments: segments,
          colors: guide
              ? [ChartOverviewColorStop(0, rgba(style['guide'] as List))]
              : colors,
          strokeArgb: guide ? 0 : normalStroke,
          strokeWidth: guide ? 0 : 1,
        ),
      );
    }
    final pairs = <int, List<RuntimeVisualNote>>{};
    for (final n in visual) {
      if (const {1, 20, 22, 40, 41, 42}.contains(n.operateType) &&
          n.sourceTick != null) {
        (pairs[n.sourceTick!] ??= []).add(n);
      }
    }
    final simultaneous = <ChartOverviewSimultaneous>[];
    for (final pair in pairs.values) {
      pair.sort((a, b) => a.id.compareTo(b.id));
      for (var i = 1; i < pair.length; i++) {
        final a = pair[i - 1],
            b = pair[i],
            x = (a.visualLane + a.visualWidth / 2) / 24,
            y = (b.visualLane + b.visualWidth / 2) / 24;
        simultaneous.add(
          ChartOverviewSimultaneous(
            b.timeMicroseconds / 1000,
            x < y ? x : y,
            x < y ? y : x,
          ),
        );
      }
    }
    final judged = [...runtime.notes.where((n) => n.judged)]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return ChartOverviewSource(
      ChartOverviewData(
        durationMs: (runtime.sourceDurationMs ?? runtime.durationMs).toDouble(),
        notes: notes,
        glyphs: glyphs,
        ribbons: ribbons,
        tempos: [
          for (final bpm in runtime.bpmChanges)
            ChartOverviewTempo(bpm.timeMs.toDouble(), bpm.tick / 480, bpm.bpm),
        ],
        skills: [
          for (final (i, time) in runtime.skillTimesMs.indexed)
            ChartOverviewLabel(time.toDouble(), '#${i + 1}'),
        ],
        combos: [
          for (var i = 50; i < judged.length; i += 50)
            ChartOverviewLabel(judged[i].timeMs.toDouble(), '$i'),
        ],
        intervals: [
          for (final pair in runtime.feverMs)
            ChartOverviewInterval(pair.$1.toDouble(), pair.$2.toDouble()),
        ],
        simultaneous: simultaneous,
        visualBands: 6,
        simultaneousThickness: .025 / 19.12000084,
        judgedCount: judged.length,
      ),
      atlas,
    );
  } catch (_) {
    atlas.dispose();
    rethrow;
  }
}
