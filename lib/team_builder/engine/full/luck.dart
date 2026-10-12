/// Expected Gekisou luck under the native lottery with independent nominal
/// draws (`engine/full/luck.ts`): the distribution of each luck range's
/// lottery state is propagated note by note and frame by frame through a
/// lottery-free recording of the live, and each judged note reads the
/// probability that the rush luck bonus, the rush-reading score-up skills,
/// or both are running at its time.
library;

import 'dart:math' as math;
import 'dart:typed_data';

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

class LuckSettlement {
  LuckSettlement({
    required this.modulus,
    required this.initial,
    required this.noteScore,
    required this.residues,
  });
  final int modulus;
  final int initial;
  final int Function(int id, bool bonus, bool skill) noteScore;
  final Float64List residues;
}

const _row = 1 << 18;
const _high = _row - 1;

/// Merged PR #12's insertion-ordered gauge vectors and reusable allocation pool.
class _Rows {
  _Rows(this.width, this.pool, bool wide)
    : table = wide ? null : Int32List(_row),
      map = wide ? <int, int>{} : null;
  final int width;
  final List<Float64List> pool;
  final Int32List? table;
  final Map<int, int>? map;
  final keys = <int>[];
  final vecs = <Float64List>[];
  final lo = <int>[];
  final hi = <int>[];
  int find(int key) => table != null ? table![key] - 1 : map![key] ?? -1;
  int put(int key, Float64List vec, int low, int high) {
    if (table != null) {
      table![key] = keys.length + 1;
    } else {
      map![key] = keys.length;
    }
    keys.add(key);
    vecs.add(vec);
    lo.add(low);
    hi.add(high);
    return keys.length - 1;
  }

  int at(int key) {
    final index = find(key);
    return index >= 0
        ? index
        : put(
            key,
            pool.isNotEmpty ? pool.removeLast() : Float64List(width),
            width,
            0,
          );
  }

  void touch(int index, int low, int high) {
    if (low < lo[index]) lo[index] = low;
    if (high > hi[index]) hi[index] = high;
  }

  void adopt(int key, Float64List vec, int low, int high) {
    final index = find(key);
    if (index < 0) {
      put(key, vec, low, high);
      return;
    }
    for (var gauge = low; gauge < high; gauge++) {
      vecs[index][gauge] += vec[gauge];
    }
    touch(index, low, high);
    free(vec, low, high);
  }

  void free(Float64List vec, int low, int high) {
    if (high > low) vec.fillRange(low, high, 0);
    pool.add(vec);
  }

  void reset() {
    if (table != null) {
      for (final key in keys) {
        table![key] = 0;
      }
    } else {
      map!.clear();
    }
    keys.clear();
    vecs.clear();
    lo.clear();
    hi.clear();
  }
}

LuckCurve luckCurve(
  GekisouTables tables,
  LuckRecord record,
  List<PlayFrame> frames,
  List<int> luckRanges,
  List<MissRule> missRules, [
  LuckSettlement? settlement,
]) {
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
  final width = math.max(tables.gaugeMax, tables.gaugeMaxRush);
  final pool = <Float64List>[];
  var dist = _Rows(width, pool, settlement != null);
  var spare = _Rows(width, pool, settlement != null);
  var steadyAt = -1;
  int Function(int)? pending;
  int keyAt(int index) {
    final key = dist.keys[index];
    if (pending == null) return key;
    final high = key & _high;
    return key - high + (pending!(high << 8) >> 8);
  }

  void pass(
    bool? Function(int key, Float64List vec, int low, int high, _Rows out) step,
  ) {
    final from = dist, out = spare;
    for (var index = 0; index < from.keys.length; index++) {
      if (step(
            keyAt(index),
            from.vecs[index],
            from.lo[index],
            from.hi[index],
            out,
          ) !=
          true) {
        out.free(from.vecs[index], from.lo[index], from.hi[index]);
      }
    }
    pending = null;
    from.reset();
    spare = from;
    dist = out;
    steadyAt = -1;
  }

  void axpy(
    _Rows out,
    int key,
    Float64List vec,
    double scale,
    int low,
    int high,
  ) {
    if (!(scale > 0)) return;
    final index = out.at(key), into = out.vecs[index];
    for (var gauge = low; gauge < high; gauge++) {
      into[gauge] += vec[gauge] * scale;
    }
    out.touch(index, low, high);
  }

  void shift(
    _Rows out,
    int key,
    Float64List vec,
    double scale,
    int add,
    int low,
    int high,
  ) {
    if (!(scale > 0)) return;
    final highState = key & _high,
        maximum = gaugeMaxOf(_rushOf(highState << 8)),
        lots = highState & 7;
    for (var overflow = (low + add) ~/ maximum; ; overflow++) {
      final a = math.max(low, overflow * maximum - add),
          b = math.min(high, (overflow + 1) * maximum - add);
      if (a >= high) break;
      if (b <= a) continue;
      final index = out.at(
        overflow == 0 ? key : key - lots + math.min(lots + overflow, 7),
      );
      final into = out.vecs[index], offset = add - overflow * maximum;
      for (var gauge = a; gauge < b; gauge++) {
        into[gauge + offset] += vec[gauge] * scale;
      }
      out.touch(index, a + offset, b + offset);
    }
  }

  void unary(int Function(int) fn) {
    final before = pending;
    pending = before != null ? (state) => fn(before(state)) : fn;
    steadyAt = -1;
  }

  final lotCache = <int, Map<int, List<(int, double, int)>>>{};
  List<(int, double, int)> lotRows(int high, int buff) {
    final byRow = lotCache.putIfAbsent(buff, () => {});
    return byRow.putIfAbsent(high, () {
      final state = high << 8, lots = _lotsOf(state) - 1;
      var minimum = _minimumOf(state);
      List<(double, int)> first;
      if (_nextOf(state) == _invalid) {
        first = draw(0, buff, minimum);
        minimum = 0;
      } else {
        first = [(1.0, _nextOf(state))];
      }
      final out = <(int, double, int)>[];
      for (final (pn, result) in first) {
        var flags = _flagsOf(state), rush = _rushOf(state);
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
        flags |= _frameLot;
        if (result == 0) flags |= _frameMiss;
        final type = rush < 4 ? _lotTypeByRush[rush] : 1;
        for (final (pr, value) in draw(type, buff, minimum)) {
          out.add((
            _pack(0, lots, value, rush, 0, flags) >> 8,
            pn * pr,
            before != after && after >= 1 ? after : 0,
          ));
        }
      }
      return out;
    });
  }

  void consume(
    _Rows out,
    int key,
    Float64List vec,
    int low,
    int high,
    int buff,
  ) {
    final highState = key & _high, residuePart = key - (key & _high);
    for (final (next, chance, after) in lotRows(highState, buff)) {
      final to = residuePart + next;
      if (after == 0 || high <= after + 1) {
        axpy(out, to, vec, chance, low, high);
        continue;
      }
      final lots = to & 7;
      if (low <= after) axpy(out, to, vec, chance, low, after + 1);
      for (var gauge = math.max(low, after + 1); gauge < high; gauge++) {
        final value = vec[gauge];
        if (value == 0) continue;
        final index = out.at(to - lots + math.min(lots + gauge ~/ after, 7));
        final remainder = gauge.remainder(after);
        out.vecs[index][remainder] += value * chance;
        out.touch(index, remainder, remainder + 1);
      }
    }
  }

  double total(Float64List vec, int low, int high) {
    var sum = 0.0;
    for (var gauge = low; gauge < high; gauge++) {
      sum += vec[gauge];
    }
    return sum;
  }

  bool missHit(int high) =>
      ((high << 8) & (_prevMiss | _missUsed)) == _prevMiss;
  bool anyRow(bool Function(int high) fn) {
    for (var index = 0; index < dist.keys.length; index++) {
      if (fn(keyAt(index) & _high)) return true;
    }
    return false;
  }

  void missPass() {
    if (!anyRow(missHit)) return;
    for (final rule in missRules) {
      pass((key, vec, low, high, out) {
        final highState = key & _high;
        if (!missHit(highState)) {
          out.adopt(key, vec, low, high);
          return true;
        }
        final gauge = i32(gaugeMaxOf(_rushOf(highState << 8)) * rule.value);
        shift(
          out,
          key,
          vec,
          rule.chance,
          floorToI32(f(f(gauge) / 10000)),
          low,
          high,
        );
        axpy(out, key, vec, 1 - rule.chance, low, high);
        return null;
      });
    }
    unary(
      (state) => (state & (_prevMiss | _missUsed)) == _prevMiss
          ? state | _missUsed
          : state,
    );
  }

  bool pendingLots(int high) {
    final state = high << 8;
    return _lotsOf(state) > 0 && state & _frameLot == 0;
  }

  void consumePending(int buff) {
    if (!anyRow(pendingLots)) return;
    pass((key, vec, low, high, out) {
      if (!pendingLots(key & _high)) {
        out.adopt(key, vec, low, high);
        return true;
      }
      consume(out, key, vec, low, high, buff);
      return null;
    });
  }

  final basePointCache = <int, List<(double, int)>>{};
  final notesByFrame = <int, List<LuckNote>>{};
  for (final note in record.notes) {
    (notesByFrame[note.frame] ??= []).add(note);
  }
  for (final range in luckRanges) {
    final first = record.frames.indexWhere(
      (frame) => frame.states[range] == _sStart,
    );
    if (first < 0) continue;
    var last = -1;
    for (var index = first + 1; index < record.frames.length; index++) {
      if (record.frames[index].states[range] == _sFinish) {
        last = index;
        break;
      }
    }
    if (last < 0) last = record.frames.length - 1;
    for (var index = 0; index < dist.vecs.length; index++) {
      dist.free(dist.vecs[index], dist.lo[index], dist.hi[index]);
    }
    dist.reset();
    pending = null;
    final start = dist.at(
      (settlement?.initial ?? 0) * _row + (_pack(0, 0, _invalid, 0, 0, 0) >> 8),
    );
    dist.vecs[start][0] = 1;
    dist.touch(start, 0, 1);
    steadyAt = -1;
    for (var k = first; k <= last; k++) {
      final frame = record.frames[k],
          time = frames[k].timeMs,
          state = frame.states[range];
      final changed = frame.updates.contains(range),
          finishing = frame.updates.contains(range) && state == _sFinish,
          playing = frame.playing == range;
      for (final action in record.actions) {
        if (action.frame != k || action.range != range) continue;
        pass((key, vec, low, high, out) {
          final highState = key & _high, packed = highState << 8;
          if (action.type == 11005) {
            final result = action.value - 2 >= 0 && action.value - 2 <= 2
                ? action.value - 1
                : 0;
            axpy(
              out,
              key -
                  highState +
                  (_pack(
                        0,
                        _lotsOf(packed),
                        _nextOf(packed),
                        _rushOf(packed),
                        math.max(_minimumOf(packed), result),
                        _flagsOf(packed),
                      ) >>
                      8),
              vec,
              action.chance,
              low,
              high,
            );
          } else {
            final gauge = i32(gaugeMaxOf(_rushOf(packed)) * action.value);
            shift(
              out,
              key,
              vec,
              action.chance,
              floorToI32(f(f(gauge) / 10000)),
              low,
              high,
            );
          }
          axpy(out, key, vec, 1 - action.chance, low, high);
          return null;
        });
      }
      final gateOpen = changed || playing;
      final luckNotes = (notesByFrame[k] ?? const <LuckNote>[])
          .where((note) => note.range == range)
          .toList();
      final judged = frames[k].judged;
      int skillStep(int packed) {
        var skill = packed & _skill != 0;
        if (playing) skill = _rushOf(packed) != 0;
        if (changed && (state == _sComplete || state == _sFinish)) {
          skill = false;
        }
        var next = packed & ~(_skill | _skillPrev);
        if (packed & _skill != 0) next |= _skillPrev;
        if (skill) next |= _skill;
        return next;
      }

      int end(int packed) {
        var next = packed & ~(_prevMiss | _frameMiss | _frameLot);
        if (packed & _frameMiss != 0) next |= _prevMiss;
        if (changed && state == _sComplete) next &= ~_missUsed;
        return next;
      }

      if (luckNotes.isEmpty && judged.isEmpty) {
        if (!changed) {
          final at = state * 2 + (playing ? 1 : 0);
          if (steadyAt == at) continue;
          final missGate = missRules.isNotEmpty && playing;
          var steady = true;
          for (var index = 0; index < dist.keys.length; index++) {
            final packed = (keyAt(index) & _high) << 8,
                skill = ((keyAt(index) & _high) << 8) & _skill != 0;
            if (!(packed & (_prevMiss | _frameMiss | _frameLot) == 0 &&
                skill == (packed & _skillPrev != 0) &&
                (!playing || skill == (_rushOf(packed) != 0)) &&
                !(missGate &&
                    packed & _missUsed == 0 &&
                    packed & _prevMiss != 0) &&
                !(state == _sPlaying && _lotsOf(packed) > 0))) {
              steady = false;
              break;
            }
          }
          if (steady) {
            steadyAt = at;
            continue;
          }
        }
        if (missRules.isNotEmpty && gateOpen) missPass();
        unary(skillStep);
        if (state == _sPlaying) consumePending(0);
        unary(finishing ? (packed) => end(packed & ~_bonus) : end);
        continue;
      }
      if (missRules.isNotEmpty && gateOpen) missPass();
      unary(skillStep);
      void observe(int id, bool atFrameTime) {
        final skillBit = atFrameTime ? _skill : _skillPrev;
        if (settlement != null) {
          pass((key, vec, low, high, out) {
            final highState = key & _high, packed = highState << 8;
            final residue =
                ((key >> 18) +
                        settlement.noteScore(
                          id,
                          packed & _bonus != 0,
                          packed & skillBit != 0,
                        ))
                    .remainder(settlement.modulus);
            out.adopt(residue * _row + highState, vec, low, high);
            return true;
          });
          return;
        }
        var rush = 0.0, skill = 0.0, both = 0.0;
        for (var index = 0; index < dist.keys.length; index++) {
          final packed = (keyAt(index) & _high) << 8;
          final bonus = packed & _bonus != 0, reading = packed & skillBit != 0;
          if (!bonus && !reading) continue;
          final probability = total(
            dist.vecs[index],
            dist.lo[index],
            dist.hi[index],
          );
          if (bonus) rush += probability;
          if (reading) skill += probability;
          if (bonus && reading) both += probability;
        }
        curve.rush[id] = (curve.rush[id] ?? 0) + rush;
        curve.skill[id] = (curve.skill[id] ?? 0) + skill;
        curve.both[id] = (curve.both[id] ?? 0) + both;
      }

      void luckNote(LuckNote note) {
        final key =
            note.op * 1000 + note.judgement * 100 + jsRound(note.speed * 10);
        final points = basePointCache.putIfAbsent(
          key,
          () => [
            for (final (probability, value) in basePoints(
              note.op,
              note.judgement,
            ))
              (probability, floorToI32(f(f(note.speed + 1) * f(value)))),
          ],
        );
        pass((key, vec, low, high, out) {
          for (final (probability, add) in points) {
            shift(out, key, vec, probability, add, low, high);
          }
          return null;
        });
        if (state <= _sEnd) {
          pass((key, vec, low, high, out) {
            if (key & 7 == 0) {
              out.adopt(key, vec, low, high);
              return true;
            }
            consume(out, key, vec, low, high, note.buff);
            return null;
          });
        }
      }

      final times = {
        for (final note in luckNotes) note.timeMs,
        for (final note in judged) note.timeMs,
      }.toList()..sort();
      for (final at in times) {
        if (at >= time) continue;
        for (final note in luckNotes) {
          if (note.timeMs == at) luckNote(note);
        }
        for (final note in judged) {
          if (note.timeMs == at) observe(note.noteId, false);
        }
      }
      for (final note in luckNotes) {
        if (note.timeMs >= time) luckNote(note);
      }
      if (state == _sPlaying) {
        consumePending(
          luckNotes.where((note) => note.timeMs >= time).firstOrNull?.buff ??
              luckNotes.lastOrNull?.buff ??
              0,
        );
      }
      if (finishing) unary((packed) => packed & ~_bonus);
      for (final note in judged) {
        if (note.timeMs >= time) observe(note.noteId, true);
      }
      unary(end);
    }
    if (settlement != null) {
      for (var index = 0; index < dist.keys.length; index++) {
        settlement.residues[dist.keys[index] >> 18] += total(
          dist.vecs[index],
          dist.lo[index],
          dist.hi[index],
        );
      }
    }
  }
  return curve;
}
