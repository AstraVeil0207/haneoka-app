// SUS semantics adapted from Next-SEKAI, copyright 2025 Kyle Chang (MIT).
// License: third_party/chart_editor/LICENSE.next-sekai.txt.
import 'dart:math' as math;

import 'formats.dart';
import 'project.dart';
import 'usc.dart';

typedef _SusLine = ({String header, String data, int line, double base});
typedef _SusNote = ({double tick, int lane, int width, int type, int line});

String _unquote(String value) {
  final text = value.trim();
  return text.length >= 2 && text.startsWith('"') && text.endsWith('"')
      ? text.substring(1, text.length - 1)
      : text;
}

ChartImport importSusChart(String input, {void Function(ChartMap usc)? onUsc}) {
  final lines = <_SusLine>[],
      meta = <String, String>{},
      requests = <String>[],
      warnings = <ChartIssue>[];
  var measureBase = 0.0;
  void warning(String code, String path) =>
      warnings.add(ChartIssue(code, path, true));
  for (final (index, source)
      in input.replaceFirst('\ufeff', '').split(RegExp(r'\r?\n')).indexed) {
    final text = source.trim();
    if (!text.startsWith('#')) continue;
    final colon = text.indexOf(':'), space = text.indexOf(RegExp(r'\s'));
    final data = colon >= 0 && (space < 0 || colon < space),
        separator = data ? colon : space;
    if (separator < 0) continue;
    final left = text.substring(1, separator).trim().toUpperCase(),
        right = text.substring(separator + 1).trim();
    if (left.isEmpty) continue;
    if (data) {
      lines.add((
        header: left,
        data: right,
        line: index + 1,
        base: measureBase,
      ));
      continue;
    }
    if (left == 'MEASUREBS') {
      final n = double.tryParse(right);
      if (n == null || !n.isFinite) {
        warning('sus.measureBase.invalid', 'line:${index + 1}');
      } else {
        measureBase = n;
      }
      continue;
    }
    if (left == 'REQUEST') requests.add(_unquote(right));
    meta[left] = right;
  }
  final request = requests
      .where(
        (v) =>
            RegExp(r'^\s*ticks_per_beat\b', caseSensitive: false).hasMatch(v),
      )
      .firstOrNull;
  final match = request == null
      ? null
      : RegExp(
          r'^\s*ticks_per_beat\s+([0-9]+(?:\.[0-9]+)?)\s*$',
          caseSensitive: false,
        ).firstMatch(request);
  var ticksPerBeat = double.tryParse(match?.group(1) ?? '') ?? 480;
  if (match == null || ticksPerBeat <= 0) {
    ticksPerBeat = 480;
    warning('sus.ticksPerBeat.defaulted', '#REQUEST');
  }
  final rawLanes = meta['LANECOUNT'];
  var laneCount = rawLanes == null ? 24 : int.tryParse(_unquote(rawLanes)) ?? 0;
  if (laneCount <= 0) {
    laneCount = 24;
    warning('sus.laneCount.defaulted', '#LANECOUNT');
  }
  final lengths = <int, ({double length, int line})>{0: (length: 4, line: 0)};
  for (final line in lines) {
    if (line.header.length != 5 || !line.header.endsWith('02')) continue;
    final local = int.tryParse(line.header.substring(0, 3)),
        length = double.tryParse(line.data),
        measure = local == null ? double.nan : local + line.base;
    if (!measure.isFinite ||
        measure < 0 ||
        measure != measure.truncateToDouble() ||
        length == null ||
        !length.isFinite ||
        length <= 0) {
      warning('sus.barLength.invalid', 'line:${line.line}');
      continue;
    }
    lengths[measure.toInt()] = (length: length, line: line.line);
  }
  final bars = lengths.keys.toList()..sort();
  final segments = <({int measure, double ticks, double perMeasure})>[];
  var accumulated = 0.0;
  for (final (i, bar) in bars.indexed) {
    if (i > 0) {
      accumulated +=
          (bar - bars[i - 1]) * lengths[bars[i - 1]]!.length * ticksPerBeat;
    }
    segments.add((
      measure: bar,
      ticks: accumulated,
      perMeasure: lengths[bar]!.length * ticksPerBeat,
    ));
  }
  double toTick(num measure, num numerator, num denominator) {
    final segment =
        segments.where((v) => v.measure <= measure).lastOrNull ??
        segments.first;
    return segment.ticks +
        (measure - segment.measure) * segment.perMeasure +
        numerator * segment.perMeasure / denominator;
  }

  List<(double, String)> pairs(_SusLine line) {
    final measure = int.tryParse(line.header.substring(0, 3));
    if (measure == null) return [];
    if (line.data.length.isOdd) {
      warning('sus.channel.oddLength', 'line:${line.line}');
    }
    final values = RegExp(r'.{2}')
        .allMatches(line.data)
        .map((m) => m.group(0)!)
        .toList();
    return [
      for (final (index, value) in values.indexed)
        if (value != '00')
          (
            toTick(measure + line.base, index, values.length),
            value.toUpperCase(),
          ),
    ];
  }

  List<_SusNote> notes(_SusLine line) {
    final lane = int.tryParse(line.header[4], radix: 36);
    if (lane == null) return [];
    final result = <_SusNote>[];
    for (final (tick, value) in pairs(line)) {
      final type = int.tryParse(value[0], radix: 36),
          width = int.tryParse(value[1], radix: 36);
      if (type == null || width == null) {
        warning('sus.note.invalid', 'line:${line.line}');
        continue;
      }
      result.add((
        tick: tick,
        lane: lane,
        width: width,
        type: type,
        line: line.line,
      ));
    }
    return result;
  }

  final definitions = <String, double>{},
      bpms = <(double, double)>[],
      scales = <(double, double)>[],
      taps = <_SusNote>[],
      directions = <_SusNote>[];
  final streams = <String, ({int type, List<_SusNote> notes})>{};
  for (final line in lines) {
    if (line.header.length == 5 && line.header.startsWith('BPM')) {
      final n = double.tryParse(line.data);
      if (n != null && n.isFinite && n > 0) {
        definitions[line.header.substring(3)] = n;
      } else {
        warning('sus.bpm.invalid', 'line:${line.line}');
      }
    }
  }
  for (final line in lines) {
    final header = line.header;
    if (header.length == 5 &&
        (header.startsWith('TIL') || header.startsWith('HIS'))) {
      for (final part in _unquote(line.data).split(',')) {
        final segment = part.trim();
        if (segment.isEmpty) continue;
        final m = RegExp(r"^(-?\d+)'(-?\d+(?:\.\d+)?):(-?\d+(?:\.\d+)?)$")
            .firstMatch(segment);
        if (m == null) {
          warning('sus.timeScale.invalid', 'line:${line.line}');
          continue;
        }
        final scale = double.parse(m[3]!);
        if (scale <= 0) {
          warning('sus.timeScale.invalid', 'line:${line.line}');
          continue;
        }
        scales.add((
          toTick(int.parse(m[1]!), 0, 1) + double.parse(m[2]!),
          scale,
        ));
      }
    } else if (header.length == 5 && header.endsWith('08')) {
      for (final (tick, value) in pairs(line)) {
        final bpm = definitions[value];
        if (bpm == null) {
          warning('sus.bpm.undefined', 'line:${line.line}');
        } else {
          bpms.add((tick, bpm));
        }
      }
    } else if (header.length == 5 && header.endsWith('03')) {
      for (final (tick, value) in pairs(line)) {
        final bpm = int.tryParse(value, radix: 16);
        if (bpm != null && bpm > 0) bpms.add((tick, bpm.toDouble()));
      }
    } else if (header.length == 5 && header[3] == '1') {
      taps.addAll(notes(line));
    } else if (header.length == 5 && header[3] == '5') {
      directions.addAll(notes(line));
    } else if (header.length == 6 && (header[3] == '3' || header[3] == '9')) {
      final key = '${header[5]}-${header[3]}';
      final stream = streams.putIfAbsent(
        key,
        () => (type: int.parse(header[3]), notes: <_SusNote>[]),
      );
      stream.notes.addAll(notes(line));
    }
  }
  final slides = <({int type, List<_SusNote> notes})>[];
  for (final stream in streams.values) {
    List<_SusNote>? active;
    final sorted = stableChartSort(stream.notes, (a, b) {
      final t = a.tick.compareTo(b.tick);
      return t != 0 ? t : a.line.compareTo(b.line);
    });
    for (final note in sorted) {
      if (active == null) {
        active = [];
        slides.add((type: stream.type, notes: active));
      }
      active.add(note);
      if (note.type == 2) active = null;
    }
  }
  String key(_SusNote note) => '${note.lane}-${note.tick}';
  final flick = <String, String>{},
      ease = <String, String>{},
      trace = <String>{},
      critical = <String>{},
      removeTick = <String>{},
      removeEnds = <String>{},
      prevent = <String>{},
      seenSingles = <String>{},
      duplicateSlides = <String, ChartMap>{};
  for (final slide in slides) {
    if (slide.type == 3) {
      for (final note in slide.notes) {
        if (const {1, 2, 3, 5}.contains(note.type)) prevent.add(key(note));
      }
    }
  }
  for (final note in directions) {
    switch (note.type) {
      case 1:
        flick[key(note)] = 'up';
      case 3:
        flick[key(note)] = 'left';
      case 4:
        flick[key(note)] = 'right';
      case 2:
        ease[key(note)] = 'in';
      case 5 || 6:
        ease[key(note)] = 'out';
    }
  }
  for (final note in taps) {
    switch (note.type) {
      case 2:
        critical.add(key(note));
      case 5:
        trace.add(key(note));
      case 6:
        trace.add(key(note));
        critical.add(key(note));
      case 3:
        removeTick.add(key(note));
      case 7:
        removeEnds.add(key(note));
      case 8:
        critical.add(key(note));
        removeEnds.add(key(note));
    }
  }
  scales.sort((a, b) => a.$1.compareTo(b.$1));
  bpms.sort((a, b) => a.$1.compareTo(b.$1));
  final objects = <ChartMap>[
    for (final (tick, scale) in scales)
      {'type': 'timeScale', 'beat': tick / ticksPerBeat, 'timeScale': scale},
    for (final (tick, bpm) in bpms)
      {'type': 'bpm', 'beat': tick / ticksPerBeat, 'bpm': bpm},
  ];
  for (final note in taps) {
    final k = key(note);
    if (note.lane <= 1 ||
        note.lane >= 14 ||
        !const {1, 2, 5, 6}.contains(note.type) ||
        prevent.contains(k) ||
        !seenSingles.add(k)) {
      continue;
    }
    objects.add({
      'type': 'single',
      'beat': note.tick / ticksPerBeat,
      'lane': note.lane - 8 + note.width / 2,
      'size': note.width / 2,
      'trace': note.type == 5 || note.type == 6,
      'critical': note.type == 2 || note.type == 6,
      if (flick.containsKey(k)) 'direction': flick[k],
    });
  }
  for (final slide in slides) {
    final start = slide.notes
        .where((n) => n.type == 1 || n.type == 2)
        .firstOrNull;
    if (start == null) continue;
    final active = slide.type == 3,
        lineCritical = critical.contains(key(start)),
        connections = <ChartMap>[];
    for (final note in slide.notes) {
      final k = key(note),
          isCritical = lineCritical || critical.contains(k),
          easing = ease[k] ?? 'linear';
      final common = {
        'beat': note.tick / ticksPerBeat,
        'lane': note.lane - 8 + note.width / 2,
        'size': note.width / 2,
      };
      if (note.type == 1) {
        connections.add(
          !active || removeEnds.contains(k)
              ? {'type': 'ignore', ...common, 'ease': easing}
              : {
                  'type': 'start',
                  ...common,
                  'trace': trace.contains(k),
                  'critical': isCritical,
                  'ease': easing,
                },
        );
      } else if (note.type == 2) {
        connections.add(
          !active || removeEnds.contains(k)
              ? {'type': 'ignore', ...common, 'ease': easing}
              : {
                  'type': 'end',
                  ...common,
                  'trace': trace.contains(k),
                  'critical': isCritical,
                  if (flick.containsKey(k)) 'direction': flick[k],
                },
        );
      } else if (note.type == 3) {
        connections.add(
          removeTick.contains(k)
              ? {
                  'type': 'attach',
                  'beat': common['beat'],
                  'critical': isCritical,
                }
              : {
                  'type': 'tick',
                  ...common,
                  'trace': trace.contains(k),
                  'critical': isCritical,
                  'ease': easing,
                },
        );
      } else if (note.type == 5 && !removeTick.contains(k)) {
        connections.add({'type': 'ignore', ...common, 'ease': easing});
      }
    }
    if (connections.length < 2) continue;
    final object = <String, Object?>{
      'type': 'slide',
      'active': active,
      'critical': lineCritical,
      'connections': connections,
    };
    objects.add(object);
    if (active) {
      final k = key(start), old = duplicateSlides[k];
      if (old != null) objects.remove(old);
      duplicateSlides[k] = object;
    }
  }
  var offset = -(double.tryParse(meta['WAVEOFFSET'] ?? '0') ?? double.nan);
  if (!offset.isFinite) {
    offset = 0;
    warning('sus.offset.invalid', '#WAVEOFFSET');
  }
  onUsc?.call({'offset': offset, 'objects': objects});
  final imported = importUscChart({
        'offset': offset,
        'objects': objects,
      }, laneBasis: laneCount.toDouble()),
      project = imported.project;
  (int, int) signature(double length) {
    for (final den in [4, 8, 16, 32, 64, 2, 1]) {
      final n = length * den / 4;
      if (n > 0 && n == n.truncateToDouble()) return (n.toInt(), den);
    }
    return (math.max(1, (length * 16 + .5).floor()), 64);
  }

  project.data['meters'] = [
    for (final (i, bar) in bars.indexed)
      {
        'id': 'sus-meter-$i',
        'tick': (toTick(bar, 0, 1) * 480 / ticksPerBeat + .5).floor(),
        'numerator': signature(lengths[bar]!.length).$1,
        'denominator': signature(lengths[bar]!.length).$2,
      },
  ];
  final difficulty = _unquote(meta['DIFFICULTY'] ?? ''),
      level = _unquote(meta['PLAYLEVEL'] ?? '');
  project.data['meta'] = {
    'title': _unquote(meta['TITLE'] ?? ''),
    'artist': _unquote(meta['ARTIST'] ?? ''),
    'charter': _unquote(meta['DESIGNER'] ?? ''),
    'difficulty': difficulty,
    'level': level,
    'source': 'sus',
    'extra': {'susDifficulty': difficulty, 'susPlayLevel': level},
  };
  project.data['extensions'] = {
    'sus': {'ticksPerBeat': ticksPerBeat, 'laneCount': laneCount, 'meta': meta},
  };
  return finishChartImport('sus', project, [...warnings, ...imported.warnings]);
}
