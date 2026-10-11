/// The client's chart conversion (SsMusicScoreConverter → MusicScoreNoteCreator),
/// reduced to what scoring reads: every runtime note's operate type, judgement
/// type and time, in enumeration order, plus skill events and fevers. A port
/// of the website's `team-builder/engine/runtime-chart.ts`; binary32 steps and
/// .NET rounding are kept where they decide a note's time or existence.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

final _single = Float32List(1);

/// `Math.fround`: the nearest binary32 value.
double f(num x) {
  _single[0] = x.toDouble();
  return _single[0];
}

const _maxLines = 20;
const _unjudged = {0, 80, 82, 100, 103, 121, 122, 123};
bool isJudgementNote(int op) => !_unjudged.contains(op);
const _slideBegin = {20, 41, 61, 80, 104};
const _slideEnd = {22, 42, 62, 82, 105};
const _mergeable = {
  20,
  22,
  41,
  42,
  61,
  62,
  80,
  82,
  100,
  101,
  102,
  103,
  104,
  105,
};
const _noteTypes = {
  'tap': 0,
  'flick': 1,
  'trace': 2,
  'long': 3,
  'guide': 4,
  'node': 5,
};
const _flickDirs = {'up': 0, 'left': 1, 'right': 2, 'down': 3};
const _eases = {'linear': 0, 'in': 1, 'out': 2};

/// Sorts keeping equal elements in order, as JavaScript's sort does.
void _stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (final (index, value) in list.indexed) (index, value)];
  indexed.sort((a, b) {
    final order = compare(a.$2, b.$2);
    return order != 0 ? order : a.$1 - b.$1;
  });
  for (final (index, entry) in indexed.indexed) {
    list[index] = entry.$2;
  }
}

int _sign(num value) => value < 0
    ? -1
    : value > 0
    ? 1
    : 0;

/// System.Math.Round(double), midpoint to even, as the inlined IL2CPP code does it.
double _netRound(double x) {
  final ip = x.truncateToDouble();
  final frac = x - ip;
  if (x >= 0) {
    if (frac == 0.5) return ip.toInt().isOdd ? ip + 1 : ip;
    return (x + 0.5).floorToDouble();
  }
  if (frac == -0.5) return ip.toInt().isOdd ? ip - 1 : ip;
  return (x - 0.5).truncateToDouble();
}

int _netRoundInt(double x) {
  if (!x.isFinite) return -(1 << 31);
  final rounded = _netRound(x);
  return rounded.isFinite ? rounded.toInt() : -(1 << 31);
}

bool _approximately(double a, double b) {
  a = f(a);
  b = f(b);
  final m = math.max(a.abs(), b.abs());
  final tolerance = math.max(f(m * f(1e-6)), f(f(1.401298e-45) * f(8)));
  return f(b - a).abs() < tolerance;
}

int judgementTypeOf(int op, bool critical) {
  if (op == 0 || op == 21) return op;
  if (op == 1) return critical ? 2 : 1;
  if (op == 20) return critical ? 15 : 10;
  if (op == 22) return 11;
  if (op == 40 || op == 41 || op == 42 || op == 102) return 5;
  if (const {60, 61, 63, 104, 105, 120}.contains(op)) return 21;
  if (op == 62) return 22;
  return 1;
}

class _SsNote {
  int type = 0;
  int t = 0;
  double pos = 0;
  bool posAuto = false;
  double size = f(6);
  bool crit = false;
  int dir = 0;
  int easeL = 0;
  int easeR = 0;
  bool visible = true;
  List<_SsNote>? node;
}

int _toInt(Object? value) {
  if (value is bool) return value ? 1 : 0;
  if (value is int) return value;
  if (value is double) {
    return value == value.truncateToDouble()
        ? value.toInt()
        : _netRoundInt(value);
  }
  return int.parse('$value'.trim());
}

double _toF32(Object? value) =>
    f(value is num ? value : double.tryParse('$value') ?? double.nan);

bool _truthy(Object? value) =>
    !(value == null || value == false || value == 0 || value == '');

_SsNote _readNote(Map raw) {
  final note = _SsNote();
  if (raw['type'] case final String type) note.type = _noteTypes[type] ?? 0;
  if (raw['t'] != null) note.t = _toInt(raw['t']);
  if (raw['pos'] != null) {
    if (raw['pos'] == 'auto') {
      note.posAuto = true;
    } else {
      note.pos = _toF32(raw['pos']);
    }
  }
  if (raw['size'] != null) note.size = _toF32(raw['size']);
  if (raw['crit'] != null) note.crit = _truthy(raw['crit']);
  if (raw['dir'] case final String dir) note.dir = _flickDirs[dir] ?? 0;
  if (raw['ease'] != null) {
    if (raw['ease'] case final List ease) {
      note.easeL = _eases[ease.elementAtOrNull(0)] ?? 0;
      note.easeR = _eases[ease.elementAtOrNull(1)] ?? 0;
    } else {
      note.easeL = note.easeR = _eases['${raw['ease']}'] ?? 0;
    }
  }
  if (raw['visible'] != null) note.visible = _truthy(raw['visible']);
  if (raw['node'] case final List nodes) {
    note.node = [for (final child in nodes) _readNote(child as Map)];
  }
  return note;
}

class _BarPos {
  const _BarPos(this.bar, this.rhythm, this.unit, this.progress, [this.ms = 0]);
  final int bar;
  final int rhythm;
  final int unit;
  final double progress;
  final int ms;
}

class _TickConverter {
  _TickConverter(List<(int, int, int)> sigs, List<(int, double)> bpms) {
    final s = [...sigs];
    _stableSort(s, (a, b) => a.$1 - b.$1);
    if (s.isEmpty || s.first.$1 > 0) sig.add((0, 0, 1920));
    var bar = 0, previous = 0, perMeasure = 1920;
    for (final (t, num, den) in s) {
      final q = perMeasure != 0 ? (t - previous) ~/ perMeasure : 0;
      if (t - previous != 0 && previous <= t) bar += q;
      perMeasure = den != 0 ? (num * 1920) ~/ den : 0;
      sig.add((t, bar, perMeasure));
      previous = t;
    }
    final b = [...bpms];
    _stableSort(b, (a, c) => a.$1 - c.$1);
    if (b.isEmpty || b.first.$1 > 0) bpm.add((0, 0, f(120)));
    var acc = 0.0;
    var prevT = 0;
    var prevBpm = f(120);
    for (final (t, value) in b) {
      if (t - prevT != 0 && prevT <= t) {
        acc += ((t - prevT) * 60000) / f(prevBpm * f(480));
      }
      bpm.add((t, _netRoundInt(acc), value));
      prevT = t;
      prevBpm = value;
    }
  }
  final sig = <(int, int, int)>[];
  final bpm = <(int, int, double)>[];

  int timeMs(int tick) {
    var segment = bpm.first;
    for (var i = bpm.length - 1; i >= 0; i--) {
      if (bpm[i].$1 <= tick) {
        segment = bpm[i];
        break;
      }
    }
    final (t0, ms0, value) = segment;
    return (((tick - t0) * 60000) / f(value * f(480)) + ms0).floor();
  }

  _BarPos barPosition(int tick, {bool timed = false}) {
    var segment = sig.first;
    for (var i = sig.length - 1; i >= 0; i--) {
      if (sig[i].$1 <= tick) {
        segment = sig[i];
        break;
      }
    }
    final (t0, bar0, perMeasure) = segment;
    final q = perMeasure != 0 ? (tick - t0) ~/ perMeasure : 0;
    final r = tick - t0 - q * perMeasure;
    return _BarPos(
      bar0 + q,
      r,
      perMeasure,
      f(f(r) / f(perMeasure)),
      timed ? timeMs(tick) : 0,
    );
  }
}

double _keyOf(int bar, double progress) => f(progress + f(bar));

bool _before(_BarPos pos, int bar, double progress) =>
    pos.bar < bar || (pos.bar == bar && pos.progress < progress);

int _timeMsFromBar(
  int bar,
  double progress,
  List<(double, _BarPos)> bpmEvents,
  List<(double, _BarPos)> barEvents,
) {
  progress = f(progress);
  var ref = const _BarPos(0, 0, 0, 0);
  var beats = f(4);
  for (final (value, pos) in barEvents) {
    if (_before(pos, bar, progress)) {
      beats = value;
      if (pos.ms > ref.ms) ref = pos;
    }
  }
  var bpm = f(160);
  for (final (value, pos) in bpmEvents) {
    if (_before(pos, bar, progress)) {
      bpm = value;
      if (pos.ms > ref.ms) ref = pos;
    }
  }
  final spb = f(f(beats * f(60)) / bpm);
  var x = f(f(spb * f(bar - ref.bar)) + f(spb * f(progress - ref.progress)));
  x = f(x * f(1000));
  return ref.ms + x.floor();
}

double _barRhythm(int bar, List<(double, _BarPos)> barEvents) {
  var value = f(4);
  for (final (beats, pos) in barEvents) {
    if (bar < pos.bar) return value;
    value = beats;
  }
  return value;
}

double _bpmAtMs(int ms, List<(double, _BarPos)> bpmEvents) {
  var value = f(160);
  for (final (bpm, pos) in bpmEvents) {
    if (pos.ms <= ms) value = bpm;
  }
  return value;
}

bool _samePosition(_BarPos a, _BarPos b) =>
    a.bar == b.bar && _approximately(a.progress, b.progress);

double _ease(double t, int kind) {
  t = f(t);
  if (kind == 0) return t;
  if (kind == 2) return f(t * t);
  return f(f(f(2) - t) * t);
}

int _convertEase(int e) => e == 1
    ? 2
    : e == 2
    ? 1
    : 0;

String _overlapKey(int t, double pos, double size) =>
    '$t|${_netRoundInt(pos)}|${_netRoundInt(size)}';

class _NoteInfo {
  _NoteInfo({
    required this.position,
    required this.lane,
    required this.width,
    required this.op,
    required this.slideAlong,
    required this.crit,
    required this.direction,
    required this.ease,
    required this.easeR,
    required this.lines,
  });
  final _BarPos position;
  final int lane;
  final int width;
  final int op;
  final bool slideAlong;
  final bool crit;
  final int direction;
  final int ease;
  final int easeR;
  final List<int> lines;
}

int _flickDirection(_SsNote note) => note.dir == 1
    ? 1
    : note.dir == 2
    ? 2
    : 0;

_NoteInfo _singleInfo(_SsNote note, _TickConverter tc) => _NoteInfo(
  position: tc.barPosition(note.t),
  lane: _netRoundInt(f(note.pos)),
  width: math.max(1, _netRoundInt(note.size)),
  op: note.type == 1
      ? 40
      : note.type == 2
      ? 60
      : 1,
  slideAlong: false,
  crit: note.crit,
  direction: note.type == 1 ? _flickDirection(note) : 0,
  ease: 0,
  easeR: 0,
  lines: [],
);

int _longNodeOp(List<_SsNote> nodes, int i) {
  final node = nodes[i];
  if (i == 0) {
    return !node.visible
        ? 80
        : node.type == 1
        ? 41
        : node.type == 2
        ? 61
        : 20;
  }
  if (i == nodes.length - 1) {
    return !node.visible
        ? 82
        : node.type == 1
        ? 42
        : node.type == 2
        ? 62
        : 22;
  }
  if (node.posAuto) return 21;
  if (!node.visible) return 122;
  return node.type == 2 ? 63 : 21;
}

int _guideNodeOp(List<_SsNote> nodes, int i, Map<String, _SsNote>? guideMap) {
  final node = nodes[i];
  if (i == 0) {
    if (guideMap != null && !node.posAuto) {
      final single = guideMap[_overlapKey(node.t, node.pos, node.size)];
      if (single != null && single.type < 3) {
        return const [101, 102, 104][single.type];
      }
    }
    return 100;
  }
  if (i == nodes.length - 1) {
    return !node.visible
        ? 103
        : node.type == 2
        ? 105
        : 103;
  }
  if (node.posAuto) return 63;
  return !node.visible ? 122 : 63;
}

class _LineIndexAssigner {
  final _inUse = <(int, int)>[];

  int acquire(int startTick) {
    _inUse.removeWhere((entry) => entry.$2 < startTick);
    final used = {for (final (index, _) in _inUse) index};
    for (var i = 0; i < _maxLines; i++) {
      if (!used.contains(i)) return i;
    }
    throw StateError('ss lineIndex $_maxLines startTick $startTick');
  }

  void register(int index, int endTick) => _inUse.add((index, endTick));
}

void _lineInfos(
  List<_SsNote> chains,
  bool isLong,
  _TickConverter tc,
  List<_NoteInfo> out,
  Map<String, _SsNote>? guideMap,
  _LineIndexAssigner assigner,
) {
  for (final chain in chains) {
    final nodes = chain.node!;
    final n = nodes.length;
    final lineIndex = assigner.acquire(nodes.first.t);
    final endTick = nodes.last.t;
    for (final (i, node) in nodes.indexed) {
      final op = isLong
          ? _longNodeOp(nodes, i)
          : _guideNodeOp(nodes, i, guideMap);
      double pos, size;
      if (!node.posAuto) {
        pos = node.pos;
        size = node.size;
      } else if (i == 0 || i >= n - 1) {
        pos = nodes.first.pos;
        size = nodes.first.size;
      } else {
        var j = i;
        for (;;) {
          if (j < 2) {
            j = 0;
            break;
          }
          j--;
          if (!nodes[j].posAuto) break;
        }
        var k = i + 1;
        while (k < n - 1 && nodes[k].posAuto) {
          k++;
        }
        final a = nodes[j], b = nodes[k];
        final span = b.t - a.t;
        final progress = span < 1 ? 0.0 : f(f(node.t - a.t) / f(span));
        final el = _ease(progress, _convertEase(a.easeL));
        final er = _ease(progress, _convertEase(a.easeR));
        pos = f(a.pos + f(el * f(b.pos - a.pos)));
        final aRight = f(a.pos + a.size);
        final right = f(aRight + f(er * f(f(b.pos + b.size) - aRight)));
        size = f(right - pos);
      }
      var directionSource = node;
      if (guideMap != null && i == 0 && !isLong && !node.posAuto) {
        directionSource =
            guideMap[_overlapKey(node.t, node.pos, node.size)] ?? node;
      }
      out.add(
        _NoteInfo(
          position: tc.barPosition(node.t),
          lane: _netRoundInt(f(pos)),
          width: math.max(1, _netRoundInt(size)),
          op: op,
          slideAlong: node.posAuto,
          crit: node.crit,
          direction: directionSource.type == 1
              ? _flickDirection(directionSource)
              : 0,
          ease: _convertEase(node.easeL),
          easeR: _convertEase(node.easeR),
          lines: [lineIndex],
        ),
      );
    }
    assigner.register(lineIndex, endTick);
  }
}

List<_NoteInfo> _buildNoteInfos(List<_SsNote> notes, _TickConverter tc) {
  final guideStarts = <String>{};
  for (final note in notes) {
    if (note.type == 4 && (note.node?.isNotEmpty ?? false)) {
      final first = note.node!.first;
      if (!first.posAuto) {
        guideStarts.add(_overlapKey(first.t, first.pos, first.size));
      }
    }
  }
  final guideMap = <String, _SsNote>{};
  final merged = <int>{};
  for (final (i, note) in notes.indexed) {
    if (note.type < 3) {
      final key = _overlapKey(note.t, note.pos, note.size);
      if (guideStarts.contains(key) && !guideMap.containsKey(key)) {
        guideMap[key] = note;
        merged.add(i);
      }
    }
  }
  final out = <_NoteInfo>[
    for (final (i, note) in notes.indexed)
      if (!merged.contains(i) && note.type < 3) _singleInfo(note, tc),
  ];
  List<_SsNote> ordered(int type) {
    final chains = [
      for (final (index, note) in notes.indexed)
        if (note.type == type && (note.node?.length ?? 0) > 1) (note, index),
    ];
    chains.sort((a, b) {
      final order = a.$1.node!.first.t - b.$1.node!.first.t;
      return order != 0 ? order : a.$2 - b.$2;
    });
    return [for (final (note, _) in chains) note];
  }

  final assigner = _LineIndexAssigner();
  _lineInfos(ordered(3), true, tc, out, null, assigner);
  _lineInfos(ordered(4), false, tc, out, guideMap, assigner);
  return out;
}

/// BuildNoteInfoDictionary + TryMergeSlideEndpoint: position key → lane → infos.
Map<double, Map<int, List<_NoteInfo>>> _infoDictionary(List<_NoteInfo> infos) {
  final dictionary = <double, Map<int, List<_NoteInfo>>>{};
  for (final info in infos) {
    final key = _keyOf(info.position.bar, info.position.progress);
    final list = (dictionary[key] ??= {})[info.lane] ??= [];
    if (_mergeable.contains(info.op) && info.lines.isNotEmpty) {
      final hit = list
          .where(
            (e) =>
                e.op == info.op &&
                e.width == info.width &&
                e.crit == info.crit &&
                e.direction == info.direction &&
                e.ease == info.ease &&
                e.easeR == info.easeR,
          )
          .firstOrNull;
      if (hit != null) {
        hit.lines.addAll(info.lines);
        continue;
      }
    }
    list.add(info);
  }
  return dictionary;
}

int _priority(int op) => const {20, 41, 61, 80, 100, 101, 102, 104}.contains(op)
    ? 8
    : op == 122
    ? 9
    : 10;

class _RuntimeNote {
  _RuntimeNote(this.id, this.pos, this.op, this.crit, this.lineIds);
  final int id;
  final _BarPos pos;
  final int op;
  final bool crit;
  final List<int> lineIds;
  final viewNotes = <_RuntimeNote>[];
  final comboNotes = <_RuntimeNote>[];
  final endCombo = <_RuntimeNote>[];
}

Iterable<_BarPos> _eighths(
  _BarPos segStart,
  _BarPos segEnd,
  List<(double, _BarPos)> bpmEvents,
  List<(double, _BarPos)> barEvents,
) sync* {
  var bar = segStart.bar;
  var progress = segStart.progress;
  var r = _barRhythm(bar, barEvents);
  var step = 1 / (r + r);
  for (;;) {
    progress += step;
    if (progress >= 1) {
      bar += 1;
      progress -= 1;
      r = _barRhythm(bar, barEvents);
      step = 1 / (r + r);
    }
    final fp = f(progress);
    final ms = _timeMsFromBar(bar, fp, bpmEvents, barEvents);
    if (segEnd.ms <= ms) return;
    final r2 = _barRhythm(bar, barEvents);
    final unit = f(r2 + r2).truncate();
    yield _BarPos(bar, _netRoundInt(f(fp * f(unit))), unit, fp, ms);
  }
}

/// One runtime note, as scoring reads it.
class ChartNote {
  const ChartNote(
    this.timeMs,
    this.operateType,
    this.judgementType,
    this.judged,
  );
  final int timeMs;
  final int operateType;
  final int judgementType;
  final bool judged;
}

/// A converted chart (`ChartSource`): notes by time, skill events and fevers,
/// and the notes in the client's own enumeration order.
class RuntimeChart {
  const RuntimeChart({
    required this.durationMs,
    required this.notes,
    required this.skillTimesMs,
    required this.feverMs,
    required this.enumeration,
  });
  final int durationMs;
  final List<ChartNote> notes;
  final List<int> skillTimesMs;
  final List<(int, int)> feverMs;
  final List<ChartNote> enumeration;

  /// Raw `.bytes` chart (gzip or plain JSON) → runtime chart.
  factory RuntimeChart.fromBytes(List<int> bytes) {
    final data = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
        ? gzip.decode(bytes)
        : bytes;
    return RuntimeChart.fromJson(jsonDecode(utf8.decode(data)));
  }

  factory RuntimeChart.fromJson(Object? root) {
    final score = root is Map ? root['score'] : null;
    if (score is! Map) throw const FormatException('ss score');
    final events = score['events'] is Map ? score['events'] as Map : const {};
    List list(Object? value) => value is List ? value : const [];
    final bpm = [
      for (final b in list(events['bpm']))
        (_toInt((b as Map)['t']), _toF32(b['bpm'])),
    ];
    final sig = [
      for (final s in list(events['sig']))
        (
          _toInt((s as Map)['t']),
          _toInt((s['sig'] as List)[0]),
          _toInt((s['sig'] as List)[1]),
        ),
    ];
    final skill = [for (final tick in list(events['skill'])) _toInt(tick)];
    final fever = [
      for (final pair in list(events['fever']))
        (_toInt((pair as List)[0]), _toInt(pair[1])),
    ];
    final notes = [
      for (final note in list(score['notes'])) _readNote(note as Map),
    ];
    final tc = _TickConverter(sig, bpm);
    final infos = _buildNoteInfos(notes, tc);
    final sortedBpm = [...bpm];
    _stableSort(sortedBpm, (a, b) => a.$1 - b.$1);
    final bpmEvents = [
      for (final (t, value) in sortedBpm)
        (value, tc.barPosition(t, timed: true)),
    ];
    final sortedSig = [...sig];
    _stableSort(sortedSig, (a, b) => a.$1 - b.$1);
    final barEvents = [
      for (final (t, num, den) in sortedSig)
        (f(f(f(num) * f(4)) / f(den)), tc.barPosition(t, timed: true)),
    ];
    final sortedFever = [...fever];
    _stableSort(sortedFever, (a, b) => a.$1 - b.$1);
    final fevers = [
      for (final (a, b) in sortedFever) (tc.timeMs(a), tc.timeMs(b)),
    ];

    // MusicScoreNoteCreator.
    var currentId = 0, currentLine = 0, currentGuideLine = 0;
    final beginByLine = <int, _RuntimeNote>{};
    final lineArr = List<int>.filled(_maxLines, -1);
    final guideArr = List<int>.filled(_maxLines, -1);
    _RuntimeNote make(_NoteInfo info, _BarPos pos, int op, List<int> lineIds) =>
        _RuntimeNote(currentId, pos, op, info.crit, lineIds);

    void endLine(_RuntimeNote end) {
      final begins = <_RuntimeNote>[];
      var ok = true;
      for (final lineId in end.lineIds) {
        final begin = beginByLine[lineId];
        if (begin == null) {
          ok = false;
          break;
        }
        begins.add(begin);
        final lineNotes = [
          for (final note in begin.viewNotes)
            if (note.lineIds.contains(lineId)) note,
        ];
        _stableSort(lineNotes, (a, b) {
          final bar = a.pos.bar - b.pos.bar;
          return bar != 0 ? bar : _sign(a.pos.progress - b.pos.progress);
        });
        lineNotes.add(end);
        final mids = [
          for (final note in lineNotes)
            if (!identical(note, end) && isJudgementNote(note.op)) note.pos,
        ];
        final bounds = [begin.pos, ...mids, end.pos];
        final beats = <_BarPos>[
          for (var s = 0; s < bounds.length - 1; s++)
            ..._eighths(bounds[s], bounds[s + 1], bpmEvents, barEvents),
        ];
        for (final (k, beat) in beats.indexed) {
          if (lineNotes.any(
            (note) => isJudgementNote(note.op) && _samePosition(note.pos, beat),
          )) {
            continue;
          }
          final window = 15000 / _bpmAtMs(beat.ms, bpmEvents);
          var skip = mids.any(
            (mid) => mid.ms - window <= beat.ms && beat.ms < mid.ms,
          );
          if (k == 0 && window > beat.ms - begin.pos.ms) skip = true;
          if (k == beats.length - 1 && window > end.pos.ms - beat.ms) {
            skip = true;
          }
          final combo = _RuntimeNote(
            lineId + k * 10000 + 10000,
            beat,
            skip ? 121 : 120,
            false,
            [lineId],
          );
          if (_slideBegin.contains(begin.op)) begin.comboNotes.add(combo);
        }
        beginByLine.remove(lineId);
      }
      if (ok) {
        for (final begin in begins) {
          if (_slideEnd.contains(end.op) && _slideBegin.contains(begin.op)) {
            end.endCombo.addAll(begin.comboNotes);
          }
        }
      }
    }

    _RuntimeNote? create(_NoteInfo info) {
      final position = info.position;
      final ms = _timeMsFromBar(
        position.bar,
        position.progress,
        bpmEvents,
        barEvents,
      );
      final pos = _BarPos(
        position.bar,
        position.rhythm,
        position.unit,
        position.progress,
        ms,
      );
      currentId++;
      final op = info.op;
      final _RuntimeNote note;
      if (op == 1 || op == 40 || op == 60) {
        note = make(info, pos, op, []);
      } else if (op == 20 || op == 41 || op == 61 || op == 80) {
        final ids = [
          for (final index in info.lines) lineArr[index] = ++currentLine,
        ];
        note = make(info, pos, op, ids);
        for (final id in ids) {
          beginByLine[id] = note;
        }
      } else if (op == 21 || op == 63) {
        final index = info.lines.firstOrNull;
        final id = index == null ? -1 : (op == 21 ? lineArr : guideArr)[index];
        note = make(info, pos, op, [id]);
        beginByLine[id]?.viewNotes.add(note);
      } else if (op == 22 || op == 42 || op == 62 || op == 82) {
        final ids = [
          for (final index in info.lines)
            () {
              final id = lineArr[index];
              lineArr[index] = -1;
              return id;
            }(),
        ];
        note = make(info, pos, op, ids);
        endLine(note);
      } else if (op == 100 || op == 101 || op == 102 || op == 104) {
        final ids = [
          for (final index in info.lines)
            guideArr[index] = (currentGuideLine++) + 10001,
        ];
        note = make(info, pos, op, ids);
        for (final id in ids) {
          beginByLine[id] = note;
        }
      } else if (op == 103 || op == 105) {
        final ids = [
          for (final index in info.lines)
            () {
              final id = guideArr[index];
              guideArr[index] = -1;
              return id;
            }(),
        ];
        note = make(info, pos, op, ids);
        endLine(note);
      } else if (op == 122) {
        final index = info.lines.firstOrNull;
        if (index == null) return null;
        var id = lineArr[index];
        if (id < 1) {
          id = guideArr[index];
          if (id < 1) return null;
        }
        note = make(info, pos, op, [id]);
        beginByLine[id]?.viewNotes.add(note);
      } else {
        return null;
      }
      return note;
    }

    final dictionary = _infoDictionary(infos);
    final byKey = <double, List<_RuntimeNote>>{};
    for (final key in dictionary.keys.toList()..sort()) {
      final flat = [for (final lane in dictionary[key]!.values) ...lane];
      _stableSort(flat, (a, b) => _priority(a.op) - _priority(b.op));
      for (final info in flat) {
        final note = create(info);
        if (note == null) continue;
        (byKey[_keyOf(note.pos.bar, note.pos.progress)] ??= []).add(note);
        if (_slideEnd.contains(note.op) && note.endCombo.isNotEmpty) {
          for (final combo in note.endCombo) {
            final comboList =
                byKey[_keyOf(combo.pos.bar, combo.pos.progress)] ??= [];
            if (!comboList.any((other) => identical(other, combo))) {
              comboList.add(combo);
            }
          }
        }
      }
    }
    ChartNote runtime(_RuntimeNote note) => ChartNote(
      note.pos.ms,
      note.op,
      note.op == 123 ? 0 : judgementTypeOf(note.op, note.crit),
      isJudgementNote(note.op),
    );
    final enumeration = [
      for (final list in byKey.values)
        for (final note in list) runtime(note),
    ];
    final positional = [
      for (final key in byKey.keys.toList()..sort())
        for (final note in byKey[key]!) runtime(note),
    ];
    final lastMs = positional.fold(
      0,
      (max, note) => math.max(max, note.timeMs),
    );
    final ordered = [...positional];
    _stableSort(ordered, (a, b) => a.timeMs - b.timeMs);
    return RuntimeChart(
      durationMs: lastMs + 1000,
      notes: ordered,
      skillTimesMs: [for (final tick in skill) tc.timeMs(tick)],
      feverMs: fevers,
      enumeration: enumeration,
    );
  }
}
