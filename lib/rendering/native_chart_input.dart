import 'dart:math' as math;

import '../chart/runtime_chart.dart';
import '../chart_editor/project.dart';

RuntimeChart shiftNativeChart(RuntimeChart chart, double milliseconds) {
  if (milliseconds == 0) return chart;
  final us = (milliseconds * 1000).round();
  int ms(int value) => ((value * 1000 + us) / 1000).floor();
  ChartNote note(ChartNote n) =>
      ChartNote(ms(n.timeMs), n.operateType, n.judgementType, n.judged);
  final visuals = <RuntimeVisualNote, RuntimeVisualNote>{};
  RuntimeVisualNote visual(RuntimeVisualNote n) => visuals.putIfAbsent(
    n,
    () => RuntimeVisualNote(
      visualLane: n.visualLane,
      visualWidth: n.visualWidth,
      id: n.id,
      timeMicroseconds: n.timeMicroseconds + us,
      lane: n.lane,
      width: n.width,
      operateType: n.operateType,
      direction: n.direction,
      critical: n.critical,
      slideAlong: n.slideAlong,
      sourceOrdinal: n.sourceOrdinal,
      bar: n.bar,
      rhythm: n.rhythm,
      unit: n.unit,
      progress: n.progress,
      ease: n.ease,
      easeR: n.easeR,
      nativeLineIds: n.nativeLineIds,
      sourceLineIndices: n.sourceLineIndices,
      visible: n.visible,
      visibilitySource: n.visibilitySource,
      sourceTick: n.sourceTick,
    ),
  );
  RuntimeVisualAuxEvent aux(RuntimeVisualAuxEvent n) => RuntimeVisualAuxEvent(
    id: n.id,
    timeMicroseconds: n.timeMicroseconds + us,
    operateType: n.operateType,
    nativeLineIds: n.nativeLineIds,
    isJudgement: n.isJudgement,
    sourceOrdinal: n.sourceOrdinal,
  );
  return RuntimeChart(
    durationMs: math.max(0, ms(chart.durationMs)),
    sourceDurationMs: chart.sourceDurationMs == null
        ? null
        : math.max(0, ms(chart.sourceDurationMs!)),
    notes: chart.notes.map(note).toList(),
    enumeration: chart.enumeration.map(note).toList(),
    skillTimesMs: chart.skillTimesMs.map(ms).toList(),
    feverMs: [for (final pair in chart.feverMs) (ms(pair.$1), ms(pair.$2))],
    bpmChanges: [
      for (final b in chart.bpmChanges)
        RuntimeBpmChange(b.tick, ms(b.timeMs), b.bpm),
    ],
    visualNotes: chart.visualNotes.map(visual).toList(),
    visualTimeSortedIndices: chart.visualTimeSortedIndices,
    visualLines: [
      for (final l in chart.visualLines)
        RuntimeVisualLine(
          nativeLineId: l.nativeLineId,
          family: l.family,
          beginNativeId: l.beginNativeId,
          endNativeId: l.endNativeId,
          pointNativeIds: l.pointNativeIds,
          points: l.points.map(visual).toList(),
          unresolvedPointIds: l.unresolvedPointIds,
          comboEvents: l.comboEvents.map(aux).toList(),
          endComboEvents: l.endComboEvents.map(aux).toList(),
          closedOrdinal: l.closedOrdinal,
        ),
    ],
    visualUnresolvedLines: chart.visualUnresolvedLines,
  );
}

/// Foreign editor projects use the same unjudged presentation projection as Web.
RuntimeChart authoredPresentationChart(ChartProject project, double duration) {
  final map = project.tempoMap,
      visual = <RuntimeVisualNote>[],
      notes = <ChartNote>[],
      lines = <RuntimeVisualLine>[];
  RuntimeVisualNote add(
    ChartMap note,
    double lane,
    double width, {
    int? line,
    int? index,
  }) {
    final id = visual.length,
        tick = note['tick'] as int,
        time = map.secondsAt(tick) * 1000000;
    final op = note['type'] == 'flick'
        ? 40
        : note['type'] == 'trace'
        ? 60
        : 1;
    int ease(Object? value) => value == 'in'
        ? 2
        : value == 'out'
        ? 1
        : 0;
    final pair = note['ease'] is Map
        ? chartMap(note['ease'])
        : const <String, Object?>{};
    final n = RuntimeVisualNote(
      visualLane: lane * 24 / project.laneBasis,
      visualWidth: width * 24 / project.laneBasis,
      id: id,
      timeMicroseconds: time.round(),
      lane: (lane * 24 / project.laneBasis).round(),
      width: (width * 24 / project.laneBasis).round(),
      operateType: op,
      direction: note['direction'] == 'left'
          ? 1
          : note['direction'] == 'right'
          ? 2
          : 0,
      critical: note['critical'] == true,
      slideAlong: note['lane'] == 'auto',
      sourceOrdinal: id,
      bar: tick ~/ 1920,
      rhythm: tick % 1920,
      unit: 1920,
      progress: (tick % 1920) / 1920,
      ease: ease(pair['left']),
      easeR: ease(pair['right']),
      nativeLineIds: line == null ? const [] : [line],
      sourceLineIndices: line == null ? const [] : [line],
      visible: note['visible'] != false,
      visibilitySource: 'authored',
      sourceTick: tick,
    );
    visual.add(n);
    notes.add(ChartNote((time / 1000).floor(), op, 0, false));
    return n;
  }

  for (final note in project.singles) {
    add(
      note,
      (note['lane'] as num).toDouble(),
      (note['size'] as num).toDouble(),
    );
  }
  for (final (id, line) in project.lines.indexed) {
    final points = chartRows(line['points']),
        shapes = resolveChartPoints(points),
        native = <RuntimeVisualNote>[];
    for (final (index, point) in points.indexed) {
      native.add(
        add(point, shapes[index].$1, shapes[index].$2, line: id, index: index),
      );
    }
    lines.add(
      RuntimeVisualLine(
        nativeLineId: id,
        family: line['kind'] == 'guide'
            ? RuntimeVisualLineFamily.guide
            : RuntimeVisualLineFamily.line,
        beginNativeId: native.first.id,
        endNativeId: native.last.id,
        pointNativeIds: native.map((n) => n.id).toList(),
        points: native,
        unresolvedPointIds: const [],
        comboEvents: const [],
        endComboEvents: const [],
        closedOrdinal: id,
      ),
    );
  }
  final indices = List<int>.generate(visual.length, (i) => i)
    ..sort((a, b) {
      final order = visual[a].timeMicroseconds.compareTo(
        visual[b].timeMicroseconds,
      );
      return order != 0 ? order : visual[a].id.compareTo(visual[b].id);
    });
  return RuntimeChart(
    durationMs: (duration * 1000).round(),
    sourceDurationMs: (duration * 1000).round(),
    notes: [for (final i in indices) notes[i]],
    enumeration: notes,
    skillTimesMs: const [],
    feverMs: const [],
    visualNotes: visual,
    visualTimeSortedIndices: indices,
    visualLines: lines,
    bpmChanges: [
      for (final b in project.tempos)
        RuntimeBpmChange(
          b['tick'] as int,
          (map.secondsAt(b['tick'] as int) * 1000).round(),
          (b['bpm'] as num).toDouble(),
        ),
    ],
  );
}
