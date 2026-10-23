// Source semantics: cassiopeia-plugin-sekai/src/convert.ts and its MIT SUS adapter.

import '../chart/runtime_chart.dart';
import '../chart_editor/project.dart';
import '../chart_editor/sus.dart';
import 'visual_time.dart';

typedef SekaiNativeChart = ({
  RuntimeChart chart,
  List<({double timeMs, double scale})> scales,
});

SekaiNativeChart compileSekaiChart(String source) {
  final parsed = _inspect(source), rows = parsed.$1, metadata = parsed.$2;
  final speedRows = rows
      .where((r) => RegExp(r'^TIL..$').hasMatch(r.$1))
      .toList();
  final selected =
      (metadata['HISPEED'] ?? speedRows.firstOrNull?.$1.substring(3))
          ?.toUpperCase();
  if (selected != null &&
      !speedRows.any((r) => r.$1.substring(3) == selected)) {
    throw const FormatException('sekai_speed');
  }
  final normalized = rows
      .where((r) => !r.$1.startsWith('TIL') || r.$1.substring(3) == selected)
      .map(
        (r) =>
            '#${r.$1}${RegExp(r'^\d|^(BPM|TIL|VOLUME)').hasMatch(r.$1) ? ': ' : ' '}${RegExp(r'^\d{3}(08|[1359])').hasMatch(r.$1) ? r.$2.toUpperCase() : r.$2}',
      )
      .join('\n');
  ChartMap? usc;
  final imported = importSusChart(normalized, onUsc: (value) => usc = value);
  final objects = chartRows(usc!['objects']);
  final tempos = objects.where((o) => o['type'] == 'bpm').toList()
    ..sort((a, b) => (a['beat'] as num).compareTo(b['beat'] as num));
  if (tempos.isEmpty || tempos.first['beat'] != 0) {
    throw const FormatException('sekai_tempo');
  }
  final bpm = <({double beat, double ms, double value})>[];
  for (final row in tempos) {
    final beat = (row['beat'] as num).toDouble(),
        value = (row['bpm'] as num).toDouble(),
        previous = bpm.lastOrNull;
    bpm.add((
      beat: beat,
      ms: previous == null
          ? 0
          : previous.ms + (beat - previous.beat) * 60000 / previous.value,
      value: value,
    ));
  }
  double time(double beat) {
    var low = 0, high = bpm.length;
    while (low < high) {
      final m = (low + high) ~/ 2;
      if (bpm[m].beat <= beat) {
        low = m + 1;
      } else {
        high = m;
      }
    }
    final row = bpm[low == 0 ? 0 : low - 1];
    return row.ms + (beat - row.beat) * 60000 / row.value;
  }

  final scales = [
    for (final row in objects)
      if (row['type'] == 'timeScale')
        (
          timeMs: time((row['beat'] as num).toDouble()),
          scale: (row['timeScale'] as num).toDouble(),
        ),
  ]..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final visualTime = ChartVisualTimeMap(scales),
      visual = <RuntimeVisualNote>[],
      notes = <ChartNote>[],
      lines = <RuntimeVisualLine>[];
  RuntimeVisualNote add(ChartMap value, int op, {int? line, int? point}) {
    final beat = (value['beat'] as num).toDouble(),
        lane = (value['lane'] as num).toDouble(),
        size = (value['size'] as num).toDouble(),
        id = notes.length;
    final critical = value['critical'] == true,
        judged = !const {122, 100, 103}.contains(op),
        visible = !const {122, 100, 103, 120}.contains(op);
    final judgement = !judged ? 0 : judgementTypeOf(op, critical),
        tick = (beat * 480).round(),
        ms = time(beat),
        easing = value['ease'] == 'in'
            ? 2
            : value['ease'] == 'out'
            ? 1
            : 0;
    final row = RuntimeVisualNote(
      visualLane: (lane - size + 6) * 2,
      visualWidth: size * 4,
      id: id,
      timeMicroseconds: (ms * 1000).round(),
      lane: ((lane - size + 6) * 2).round(),
      width: (size * 4).round(),
      operateType: op,
      direction: value['direction'] == 'left'
          ? 1
          : value['direction'] == 'right'
          ? 2
          : 0,
      critical: critical,
      slideAlong: value['type'] == 'attach' || op == 120,
      sourceOrdinal: id,
      bar: tick ~/ 1920,
      rhythm: tick % 1920,
      unit: 1920,
      progress: tick % 1920 / 1920,
      ease: easing,
      easeR: easing,
      nativeLineIds: line == null ? const [] : [line],
      sourceLineIndices: line == null ? const [] : [line],
      visible: visible,
      visibilitySource: 'sekai',
      sourceTick: tick,
    );
    visual.add(row);
    notes.add(ChartNote(ms.floor(), op, judgement, judged));
    return row;
  }

  for (final object in objects) {
    if (object['type'] == 'single') {
      add(
        object,
        object['direction'] != null
            ? 40
            : object['trace'] == true
            ? 60
            : 1,
      );
    }
    if (object['type'] != 'slide') continue;
    final connections = chartRows(object['connections']);
    if (connections.length < 2 ||
        (connections.last['beat'] as num) <=
            (connections.first['beat'] as num)) {
      throw const FormatException('sekai_slide');
    }
    for (var i = 1; i < connections.length; i++) {
      if ((connections[i]['beat'] as num) <=
          (connections[i - 1]['beat'] as num)) {
        throw const FormatException('sekai_slide');
      }
    }
    final active = object['active'] == true,
        id = lines.length,
        path = connections.where((r) => r['lane'] is num).toList(),
        points = <RuntimeVisualNote>[];
    for (final (index, connection) in connections.indexed) {
      final type = connection['type'];
      ChartMap position = connection;
      if (connection['lane'] is! num) {
        final beat = (connection['beat'] as num).toDouble(),
            before = path.lastWhere((p) => (p['beat'] as num) <= beat),
            after = path.firstWhere((p) => (p['beat'] as num) >= beat);
        final a = visualTime.scaled(time((before['beat'] as num).toDouble())),
            b = visualTime.scaled(time((after['beat'] as num).toDouble()));
        final progress = b == a
                ? 0.0
                : (visualTime.scaled(time(beat)) - a) / (b - a),
            p = progress.clamp(0.0, 1.0),
            eased = before['ease'] == 'in'
                ? p * p
                : before['ease'] == 'out'
                ? (2 - p) * p
                : p;
        position = {
          'type': 'ignore',
          'beat': beat,
          'lane':
              (before['lane'] as num) +
              ((after['lane'] as num) - (before['lane'] as num)) * eased,
          'size':
              (before['size'] as num) +
              ((after['size'] as num) - (before['size'] as num)) * eased,
          'ease': 'linear',
          ...connection,
        };
      }
      final op = switch (type) {
        'start' =>
          !active
              ? 100
              : connection['trace'] == true
              ? 61
              : 20,
        'end' =>
          !active
              ? 103
              : connection['direction'] != null
              ? 42
              : connection['trace'] == true
              ? 62
              : 22,
        'tick' || 'attach' =>
          !active
              ? 122
              : connection['trace'] == true
              ? 63
              : 21,
        _ => active && type == 'hidden' ? 120 : 122,
      };
      points.add(add(position, op, line: id, point: index));
    }
    if (active) {
      for (var i = 1; i < path.length; i++) {
        final before = path[i - 1], after = path[i];
        final start = (before['beat'] as num).toDouble(),
            end = (after['beat'] as num).toDouble();
        for (var beat = (start * 2).ceil() / 2; beat < end; beat += .5) {
          if (beat == path.first['beat']) continue;
          final a = visualTime.scaled(time(start)),
              b = visualTime.scaled(time(end));
          final p =
              (b == a ? 0.0 : (visualTime.scaled(time(beat)) - a) / (b - a))
                  .clamp(0.0, 1.0);
          final eased = before['ease'] == 'in'
              ? p * p
              : before['ease'] == 'out'
              ? (2 - p) * p
              : p;
          add(
            {
              'beat': beat,
              'lane':
                  (before['lane'] as num) +
                  ((after['lane'] as num) - (before['lane'] as num)) * eased,
              'size':
                  (before['size'] as num) +
                  ((after['size'] as num) - (before['size'] as num)) * eased,
              'type': 'hidden',
            },
            120,
            line: id,
          );
        }
      }
    }
    lines.add(
      RuntimeVisualLine(
        nativeLineId: id,
        family: active
            ? RuntimeVisualLineFamily.line
            : RuntimeVisualLineFamily.guide,
        beginNativeId: points.first.id,
        endNativeId: points.last.id,
        pointNativeIds: points.map((p) => p.id).toList(),
        points: points,
        unresolvedPointIds: const [],
        comboEvents: const [],
        endComboEvents: const [],
        closedOrdinal: id,
      ),
    );
  }
  final indices = List<int>.generate(notes.length, (i) => i)
    ..sort((a, b) {
      final order = visual[a].timeMicroseconds.compareTo(
        visual[b].timeMicroseconds,
      );
      return order != 0 ? order : a.compareTo(b);
    });
  final duration = indices.isEmpty ? 0 : notes[indices.last].timeMs;
  // Meter geometry remains canonical in the editor; rendering consumes timed BPMs.
  imported.project.requireValid();
  return (
    chart: RuntimeChart(
      durationMs: duration,
      sourceDurationMs: duration,
      notes: [for (final i in indices) notes[i]],
      enumeration: notes,
      skillTimesMs: const [],
      feverMs: const [],
      visualNotes: visual,
      visualTimeSortedIndices: indices,
      visualLines: lines,
      bpmChanges: [
        for (final row in bpm)
          RuntimeBpmChange((row.beat * 480).round(), row.ms.round(), row.value),
      ],
    ),
    scales: scales,
  );
}

(List<(String, String)>, Map<String, String>) _inspect(String source) {
  if (source.length > 8 * 1024 * 1024) {
    throw const FormatException('sekai_size');
  }
  final rows = <(String, String)>[],
      metadata = <String, String>{},
      streams = <String, List<(double, int)>>{};
  var base = 0;
  final bpms = <String>{}, references = <String>[];
  for (final raw in source.split(RegExp(r'\r\n|\r|\n'))) {
    final text = raw.trim();
    if (!text.startsWith('#')) continue;
    final match = RegExp(
      r'^#([a-z0-9]+)(?::\s*(.*)|\s+(.*))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) throw const FormatException('sekai_directive');
    final header = match[1]!.toUpperCase(),
        data = (match[2] ?? match[3] ?? '').trim();
    rows.add((header, data));
    if (match[2] == null) {
      metadata[header] = data.replaceAll(RegExp(r'^"|"$'), '');
      if (header == 'MEASUREBS') {
        final n = int.tryParse(data);
        if (n == null || n < 0) throw const FormatException('sekai_measure');
        base = n;
      }
      if (header == 'WAVEOFFSET' && (double.tryParse(data)?.isFinite != true)) {
        throw const FormatException('sekai_offset');
      }
      if (header == 'REQUEST' &&
              !RegExp(r'^"ticks_per_beat [1-9]\d*"$').hasMatch(data) ||
          header == 'NOSPEED') {
        throw const FormatException('sekai_request');
      }
      continue;
    }
    if (RegExp(r'^BPM[0-9A-Z]{2}$|^\d{3}02$').hasMatch(header)) {
      final value = double.tryParse(data);
      if (value == null || !value.isFinite || value <= 0) {
        throw const FormatException('sekai_timing');
      }
      if (header.startsWith('BPM')) bpms.add(header.substring(3));
      continue;
    }
    if (RegExp(r'^TIL[0-9A-Z]{2}$').hasMatch(header)) {
      if (!data.startsWith('"') || !data.endsWith('"')) {
        throw const FormatException('sekai_speed');
      }
      for (final part in data.substring(1, data.length - 1).split(',')) {
        if (part.trim().isEmpty) continue;
        final m = RegExp(r"^(\d+)'(\d+):(.+)$").firstMatch(part.trim()),
            value = m == null ? null : double.tryParse(m[3]!);
        if (value == null || !value.isFinite || value <= 0) {
          throw const FormatException('sekai_speed');
        }
      }
      continue;
    }
    if (header == 'VOLUME' && data.replaceAll('"', '').isEmpty) continue;
    final channel = RegExp(r'^(\d{3})(08|1[0-9A-Z]|5[0-9A-Z]|[39][0-9A-Z]{2})$')
        .firstMatch(header);
    if (channel == null ||
        data.length.isOdd ||
        !RegExp(r'^[0-9A-Z]*$', caseSensitive: false).hasMatch(data)) {
      throw const FormatException('sekai_channel');
    }
    for (var i = 0; i < data.length; i += 2) {
      final pair = data.substring(i, i + 2).toUpperCase();
      if (pair == '00') continue;
      if (channel[2] == '08') {
        references.add(pair);
        continue;
      }
      final type = int.parse(pair[0], radix: 36),
          lane = int.parse(header[4], radix: 36),
          width = int.parse(pair[1], radix: 36),
          family = header[3];
      if (family == '1' &&
          (lane <= 1 || lane >= 14) &&
          const {1, 2, 4}.contains(type)) {
        continue;
      }
      final supported = family == '1'
          ? const {1, 2, 3, 5, 6, 7, 8}
          : family == '5'
          ? const {1, 2, 3, 4, 5, 6}
          : const {1, 2, 3, 5};
      if (!supported.contains(type) ||
          lane < 2 ||
          lane >= 14 ||
          width <= 0 ||
          lane + width > 14) {
        throw const FormatException('sekai_note');
      }
      if (family == '3' || family == '9') {
        (streams['$family-${header[5]}'] ??= []).add((
          int.parse(header.substring(0, 3)) + base + i / data.length,
          type,
        ));
      }
    }
  }
  if (metadata['REQUEST'] == null ||
      references.any((id) => !bpms.contains(id))) {
    throw const FormatException('sekai_tempo');
  }
  for (final stream in streams.values) {
    stream.sort((a, b) => a.$1.compareTo(b.$1));
    var open = false;
    for (final point in stream) {
      if (point.$2 == 1) {
        if (open) throw const FormatException('sekai_slide');
        open = true;
      } else if (!open) {
        throw const FormatException('sekai_slide');
      }
      if (point.$2 == 2) open = false;
    }
    if (open) throw const FormatException('sekai_slide');
  }
  return (rows, metadata);
}
