/// Expected Gekisou luck under the native lottery with independent nominal
/// draws (`engine/full/luck.ts`): the distribution of each luck range's
/// lottery state is propagated note by note and frame by frame through a
/// lottery-free recording of the live, and each judged note reads the
/// probability that the rush luck bonus, the rush-reading score-up skills,
/// or both are running at its time.
library;

import 'dart:math' as math;

import '../master.dart' show GekisouTables;
import '../num.dart';
import 'core.dart';
import 'model.dart';

const _nonLuck = {0, 80, 82, 100, 101, 102, 103, 104, 105, 121, 122};
bool _isSubNote(int nt) => nt == 21 || nt == 120 || (nt & 0xfffffffc) == 0x3c;
const _critical = 3;
const _invalid = -1;
const _lotTypeByRush = [0, 4, 3, 2];
const _sStart = 3;
const _sPlaying = 4;
const _sEnd = 5;
const _sComplete = 7;
const _sFinish = 8;

typedef _Item = (int weight, int value);
int _buffed(double buff, int weight) => floorToI32(f(f(buff + 1) * f(weight)));
int _u32(int x) => x & 0xffffffff;

/// Nominal probabilities of one draw: (probability, value) with values merged.
List<(double, int)> _merge(List<(double, int)> pairs) {
  final out = <(double, int)>[];
  for (final (p, v) in pairs) {
    final at = out.indexWhere((item) => item.$2 == v);
    if (at >= 0) {
      out[at] = (out[at].$1 + p, v);
    } else if (p > 0) {
      out.add((p, v));
    }
  }
  return out;
}

class MissRule {
  MissRule(this.value, this.chance);
  final int value;
  final double chance;
}

/// Per judged note (by note id): probabilities that the rush luck bonus
/// runs, that the rush score-ups run, both.
class LuckCurve {
  final rush = <int, double>{};
  final skill = <int, double>{};
  final both = <int, double>{};
}

// A lottery state packed into an integer: gauge (8 bits), lots (3),
// next + 1 (3), rush (3), minimum (2), then flags.
const _g = 1,
    _l = 1 << 8,
    _n = 1 << 11,
    _r = 1 << 14,
    _min = 1 << 17,
    _missUsed = 1 << 19,
    _prevMiss = 1 << 20,
    _frameLot = 1 << 21,
    _frameMiss = 1 << 22,
    _bonus = 1 << 23,
    _skill = 1 << 24,
    _skillPrev = 1 << 25;
int _gaugeOf(int s) => s & 0xff;
int _lotsOf(int s) => (s >> 8) & 7;
int _nextOf(int s) => ((s >> 11) & 7) - 1;
int _rushOf(int s) => (s >> 14) & 7;
int _minimumOf(int s) => (s >> 17) & 3;
int _pack(int gauge, int lots, int next, int rush, int minimum, int flags) =>
    gauge * _g +
    math.min(lots, 7) * _l +
    (next + 1) * _n +
    rush * _r +
    minimum * _min +
    flags;
const _flags =
    _missUsed |
    _prevMiss |
    _frameLot |
    _frameMiss |
    _bonus |
    _skill |
    _skillPrev;
int _flagsOf(int s) => s & _flags;

LuckCurve luckCurve(
  GekisouTables tables,
  LuckRecord record,
  List<PlayFrame> frames,
  List<int> luckRanges,
  List<MissRule> missRules,
) {
  final good = <_Item>[],
      great = <_Item>[],
      perfect = <_Item>[],
      hold = <_Item>[];
  for (final r in tables.luckBasePoints) {
    if (r.weight <= 0) continue;
    if (r.category == 0) {
      if (r.judgement == 3) {
        good.add((r.weight, r.point));
      } else if (r.judgement == 4) {
        great.add((r.weight, r.point));
      } else if (r.judgement == 5) {
        perfect.add((r.weight, r.point));
      }
    } else if (r.category == 1 && r.judgement == 5) {
      hold.add((r.weight, r.point));
    }
  }
  final lots = [for (var i = 0; i < 5; i++) <_Item>[]];
  for (final r in tables.luckBonusLots) {
    if (r.weight > 0 && r.lotType >= 0 && r.lotType < 5) {
      lots[r.lotType].add((r.weight, r.result));
    }
  }
  for (final table in lots) {
    // Stable: equal results keep their table order.
    final indexed = [for (final (i, item) in table.indexed) (i, item)]
      ..sort((a, b) {
        final d = b.$2.$2 - a.$2.$2;
        return d != 0 ? d : a.$1 - b.$1;
      });
    table
      ..clear()
      ..addAll([for (final (_, item) in indexed) item]);
  }
  List<(double, int)> basePoints(int op, int j) {
    if (_nonLuck.contains(op)) return const [(1.0, 0)];
    final u = _u32(j + 1);
    if (u < 9 && ((0x107 >> (u & 31)) & 1) != 0) return const [(1.0, 0)];
    final items = _isSubNote(op)
        ? hold
        : _u32(j - 5) < 2
        ? perfect
        : j == 4
        ? great
        : j == 3
        ? good
        : null;
    if (items == null || items.isEmpty) return const [(1.0, 0)];
    final total = items.fold(0, (sum, it) => sum + it.$1);
    return _merge([for (final (w, v) in items) (w / total, v)]);
  }

  final drawCache = <String, List<(double, int)>>{};

  /// One bonus draw of a lot type at a lot buff (percent) with a guaranteed
  /// minimum result.
  List<(double, int)> draw(int type, int buffPercent, int minimum) =>
      drawCache['$type,$buffPercent,$minimum'] ??= () {
        final items = type >= 0 && type < lots.length
            ? lots[type]
            : const <_Item>[];
        final buff = f(f(buffPercent) / 100);
        var total = items.fold(0, (sum, it) => i32(sum + it.$1));
        var per = 0;
        if (minimum >= 1) {
          var included = 0, excluded = 0, n = 0;
          for (final (w, r) in items) {
            final weight = _buffed(buff, w);
            if (r >= minimum) {
              included += weight;
              n++;
            } else {
              excluded += weight;
            }
          }
          per = sdiv(excluded, n);
          total = included + per * n;
        }
        final out = <(double, int)>[];
        var lo = 0;
        for (final (w, r) in items) {
          if (minimum >= 1 && r < minimum) continue;
          final weight = per + _buffed(buff, w);
          final hi = lo + weight;
          final a = math.min(math.max(lo, 0), total),
              b = math.min(math.max(hi, 0), total);
          if (b > a) out.add(((b - a) / total, r));
          lo = hi;
        }
        return _merge(out);
      }();

  final curve = LuckCurve();
  int gaugeMaxOf(int rush) => rush > 0 ? tables.gaugeMaxRush : tables.gaugeMax;

  /// Gauge addition with overflow into lots at the state's gauge maximum.
  int addGauge(int s, int v) {
    final max = gaugeMaxOf(_rushOf(s));
    final g = i32(_gaugeOf(s) + v);
    if (max > g) {
      return _pack(
        g,
        _lotsOf(s),
        _nextOf(s),
        _rushOf(s),
        _minimumOf(s),
        _flagsOf(s),
      );
    }
    return _pack(
      g.remainder(max),
      _lotsOf(s) + g ~/ max,
      _nextOf(s),
      _rushOf(s),
      _minimumOf(s),
      _flagsOf(s),
    );
  }

  var dist = <int, double>{};
  var spare = <int, double>{};
  void push(Map<int, double> out, int s, double p) {
    if (p > 0) out[s] = (out[s] ?? 0) + p;
  }

  void map(void Function(int s, double p, Map<int, double> out) fn) {
    final out = spare..clear();
    dist.forEach((s, p) => fn(s, p, out));
    spare = dist;
    dist = out;
  }

  /// Consumes one lot: the drawn result, the rush bonus, the next draw.
  void consume(int s, double p, int buff, Map<int, double> out) {
    final lotCountBase = _lotsOf(s) - 1;
    var minimum = _minimumOf(s);
    List<(double, int)> first;
    if (_nextOf(s) == _invalid) {
      first = draw(0, buff, minimum);
      minimum = 0;
    } else {
      first = [(1.0, _nextOf(s))];
    }
    for (final (pn, result) in first) {
      var flags = _flagsOf(s);
      var rush = _rushOf(s);
      if (rush == 0 || result != _critical) {
        flags = result == _critical ? flags | _bonus : flags & ~_bonus;
      }
      final before = gaugeMaxOf(rush);
      rush = result >= 0 && result < _critical
          ? 0
          : result == _critical
          ? math.min(rush + 1, 4)
          : rush;
      final after = gaugeMaxOf(rush);
      var gauge = _gaugeOf(s), lotCount = lotCountBase;
      if (before != after && after >= 1 && gauge > after) {
        lotCount += gauge ~/ after;
        gauge = gauge.remainder(after);
      }
      flags |= _frameLot;
      if (result == 0) flags |= _frameMiss;
      final type = rush < 4 ? _lotTypeByRush[rush] : 1;
      for (final (pr, value) in draw(type, buff, minimum)) {
        push(out, _pack(gauge, lotCount, value, rush, 0, flags), p * pn * pr);
      }
    }
  }

  final basePointCache = <int, List<(double, int)>>{};
  final notesByFrame = <int, List<LuckNote>>{};
  for (final n in record.notes) {
    (notesByFrame[n.frame] ??= []).add(n);
  }
  for (final range in luckRanges) {
    final first = record.frames.indexWhere(
      (frame) => frame.states[range] == _sStart,
    );
    if (first < 0) continue;
    var last = -1;
    for (var k = first + 1; k < record.frames.length; k++) {
      if (record.frames[k].states[range] == _sFinish) {
        last = k;
        break;
      }
    }
    if (last < 0) last = record.frames.length - 1;
    dist = {_pack(0, 0, _invalid, 0, 0, 0): 1.0};
    spare = {};
    for (var k = first; k <= last; k++) {
      final frame = record.frames[k];
      final t = frames[k].timeMs;
      final state = frame.states[range];
      final changed = frame.updates.contains(range);
      final finishing = changed && state == _sFinish;
      for (final action in record.actions) {
        if (action.frame != k || action.range != range) continue;
        map((s, p, out) {
          if (action.type == 11005) {
            final result = action.value - 2 >= 0 && action.value - 2 <= 2
                ? action.value - 1
                : 0;
            push(
              out,
              _pack(
                _gaugeOf(s),
                _lotsOf(s),
                _nextOf(s),
                _rushOf(s),
                math.max(_minimumOf(s), result),
                _flagsOf(s),
              ),
              p * action.chance,
            );
          } else {
            final g = i32(gaugeMaxOf(_rushOf(s)) * action.value);
            push(
              out,
              addGauge(s, floorToI32(f(f(g) / 10000))),
              p * action.chance,
            );
          }
          push(out, s, p * (1 - action.chance));
        });
      }
      final gateOpen = changed || frame.playing == range;
      final luckNotes = [
        for (final n in notesByFrame[k] ?? const <LuckNote>[])
          if (n.range == range) n,
      ];
      final judged = frames[k].judged;
      List<(int, double)> missBranches(List<(int, double)> branches) {
        for (final rule in missRules) {
          branches = [
            for (final (b, q) in branches) ...[
              (
                addGauge(
                  b,
                  floorToI32(
                    f(f(i32(gaugeMaxOf(_rushOf(b)) * rule.value)) / 10000),
                  ),
                ),
                q * rule.chance,
              ),
              (b, q * (1 - rule.chance)),
            ],
          ];
        }
        return branches;
      }

      if (luckNotes.isEmpty && judged.isEmpty) {
        // A frame without notes: Miss gauge, rush checker, pending lot,
        // finish and frame end in one pass.
        map((s0, p0, out) {
          var branches = <(int, double)>[(s0, p0)];
          if (missRules.isNotEmpty &&
              gateOpen &&
              s0 & _prevMiss != 0 &&
              s0 & _missUsed == 0) {
            branches = [
              for (final (b, q) in missBranches(branches)) (b | _missUsed, q),
            ];
          }
          void tail(int s, double p) {
            if (finishing) s &= ~_bonus;
            var next = s & ~(_prevMiss | _frameMiss | _frameLot);
            if (s & _frameMiss != 0) next |= _prevMiss;
            if (changed && state == _sComplete) next &= ~_missUsed;
            push(out, next, p);
          }

          for (final (b, q) in branches) {
            var skill = b & _skill != 0;
            if (frame.playing == range) skill = _rushOf(b) != 0;
            if (changed && (state == _sComplete || state == _sFinish)) {
              skill = false;
            }
            var s = b & ~(_skill | _skillPrev);
            if (b & _skill != 0) s |= _skillPrev;
            if (skill) s |= _skill;
            if (state == _sPlaying && _lotsOf(s) > 0 && s & _frameLot == 0) {
              final tmp = <int, double>{};
              consume(s, q, 0, tmp);
              tmp.forEach(tail);
            } else {
              tail(s, q);
            }
          }
        });
        continue;
      }
      if (missRules.isNotEmpty && gateOpen) {
        map((s, p, out) {
          if (s & _prevMiss == 0 || s & _missUsed != 0) {
            push(out, s, p);
            return;
          }
          for (final (b, q) in missBranches([(s, p)])) {
            push(out, b | _missUsed, q);
          }
        });
      }
      // The rush checker is asked in the skill phase; a score-up it starts
      // or ends files at the frame time.
      map((s, p, out) {
        var skill = s & _skill != 0;
        if (frame.playing == range) skill = _rushOf(s) != 0;
        if (changed && (state == _sComplete || state == _sFinish)) {
          skill = false;
        }
        var next = s & ~(_skill | _skillPrev);
        if (s & _skill != 0) next |= _skillPrev;
        if (skill) next |= _skill;
        push(out, next, p);
      });
      void observe(int id, bool atFrameTime) {
        var r = 0.0, sk = 0.0, both = 0.0;
        final skillBit = atFrameTime ? _skill : _skillPrev;
        dist.forEach((s, p) {
          final bonus = s & _bonus != 0, skill = s & skillBit != 0;
          if (bonus) r += p;
          if (skill) sk += p;
          if (bonus && skill) both += p;
        });
        curve.rush[id] = (curve.rush[id] ?? 0) + r;
        curve.skill[id] = (curve.skill[id] ?? 0) + sk;
        curve.both[id] = (curve.both[id] ?? 0) + both;
      }

      void luckNote(LuckNote n) {
        final key = n.op * 1000 + n.judgement * 100 + jsRound(n.speed * 10);
        final points = basePointCache[key] ??= [
          for (final (p, v) in basePoints(n.op, n.judgement))
            (p, floorToI32(f(f(n.speed + 1) * f(v)))),
        ];
        final consumes = state <= _sEnd;
        map((s, p, out) {
          for (final (pb, add) in points) {
            final next = addGauge(s, add);
            if (consumes && _lotsOf(next) > 0) {
              consume(next, p * pb, n.buff, out);
            } else {
              push(out, next, p * pb);
            }
          }
        });
      }

      final times = {
        for (final n in luckNotes) n.timeMs,
        for (final n in judged) n.timeMs,
      }.toList()..sort();
      for (final time in times) {
        if (time >= t) continue;
        for (final n in luckNotes) {
          if (n.timeMs == time) luckNote(n);
        }
        for (final n in judged) {
          if (n.timeMs == time) observe(n.noteId, false);
        }
      }
      for (final n in luckNotes) {
        if (n.timeMs >= t) luckNote(n);
      }
      if (state == _sPlaying) {
        final buff =
            luckNotes.where((n) => n.timeMs >= t).firstOrNull?.buff ??
            luckNotes.lastOrNull?.buff ??
            0;
        map(
          (s, p, out) => _lotsOf(s) > 0 && s & _frameLot == 0
              ? consume(s, p, buff, out)
              : push(out, s, p),
        );
      }
      if (finishing) map((s, p, out) => push(out, s & ~_bonus, p));
      for (final n in judged) {
        if (n.timeMs >= t) observe(n.noteId, true);
      }
      // Frame end: this frame's Miss feeds the next frame's skills.
      map((s, p, out) {
        var next = s & ~(_prevMiss | _frameMiss | _frameLot);
        if (s & _frameMiss != 0) next |= _prevMiss;
        if (changed && state == _sComplete) next &= ~_missUsed;
        push(out, next, p);
      });
    }
  }
  return curve;
}
