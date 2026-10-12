/// The Gekisou controller (`engine/full/gekisou.ts`): range states, the
/// Gekisou combo and Just counts with their bonuses and protections, the
/// luck gauge with its lottery, and the solo rank bonus. Every chart fever
/// is one range with a mission (1 combo, 2 luck, 3 Just). A range moves
/// Wait → Standby → Start → Playing → End → Delay → Complete → Finish.
library;

import 'dart:math' as math;

import '../master.dart' show GekisouTables;
import '../num.dart';
import 'core.dart';
import 'score.dart' show GekisouComboInfo;

const _jWait = 0;
const _jGood = 3;
const _jGreat = 4;
const _jPerfect = 5;
const _jJust = 6;
const _jPass = 7;

const missionCombo = 1;
const missionLuck = 2;
const missionAll = 4;

const sWait = 1;
const sStandby = 2;
const sStart = 3;
const sPlaying = 4;
const sEnd = 5;
const sDelay = 6;
const sComplete = 7;
const sFinish = 8;

const feverWait = 1;
const feverFever = 2;
const feverEnd = 3;

const _invalid = -1;
const _critical = 3;
const _noneLot = 0;
const _chanceLow = 1;
const _lotTypeByRush = [_noneLot, 4, 3, 2];
const _bonusPointByResult = [5, 10, 10];
const _completeDelayMs = 500;
const _standbyMs = 4001;
const maxRanges = 3;
const _nonLuckNoteTypes = {0, 80, 82, 100, 101, 102, 103, 104, 105, 121, 122};

int _u32(int x) => x & 0xffffffff;
int _buffed(double buff, int weight) => floorToI32(f(f(buff + 1) * f(weight)));
bool _isSubNote(int nt) => nt == 21 || nt == 120 || (nt & 0xfffffffc) == 0x3c;

typedef _Item = (int weight, int value);

int? _lotteryTable(List<_Item> items, int r) {
  if (items.isEmpty) return null;
  var total = 0;
  for (final it in items) {
    total = i32(total + it.$1);
  }
  if (total < 1) throw StateError('lottery table with a total weight below 1');
  final m = srem(i32(r.abs()), total);
  var cum = 0;
  for (final it in items) {
    cum = i32(cum + it.$1);
    if (m < cum) return it.$2;
  }
  return null;
}

class _LuckSkillTable {
  _LuckSkillTable(List<_Item> items)
    : items = [...items]..sort((a, b) => b.$2 - a.$2) {
    var total = 0;
    for (final it in this.items) {
      total = i32(total + it.$1);
    }
    if (this.items.isNotEmpty && total < 1) {
      throw StateError('luck bonus table with a total weight below 1');
    }
    this.total = total;
  }
  final List<_Item> items;
  double buff = 0;
  late final int total;

  int? lottery(int r) {
    if (items.isEmpty) return null;
    final m = srem(i32(r.abs()), total);
    var cum = 0;
    for (final it in items) {
      cum = i32(cum + _buffed(buff, it.$1));
      if (m < cum) return it.$2;
    }
    return null;
  }

  int? lotteryWithMinimum(int r, int minimum) {
    if (items.isEmpty) return null;
    var n = 0, inc = 0, exc = 0;
    for (final it in items) {
      final w = _buffed(buff, it.$1);
      if (minimum <= it.$2) {
        n++;
        inc = i32(inc + w);
      } else {
        exc = i32(exc + w);
      }
    }
    if (n == 0) return null;
    final per = sdiv(exc, n);
    final total = i32(inc + imul(per, n));
    final m = srem(i32(r.abs()), total);
    var cum = 0;
    for (final it in items) {
      if (minimum <= it.$2) {
        cum = i32(cum + per + _buffed(buff, it.$1));
        if (m < cum) return it.$2;
      }
    }
    return null;
  }
}

class LotteryMachine {
  LotteryMachine(GekisouTables t) {
    for (final r in t.luckBasePoints) {
      if (r.weight <= 0) continue;
      final it = (r.weight, r.point);
      if (r.category == 0) {
        if (r.judgement == 3) {
          (_good ??= []).add(it);
        } else if (r.judgement == 4) {
          (_great ??= []).add(it);
        } else if (r.judgement == 5) {
          (_perfect ??= []).add(it);
        }
      } else if (r.category == 1 && r.judgement == _jPerfect) {
        _hold.add(it);
      }
    }
    final bonus = [for (var i = 0; i < 5; i++) <_Item>[]];
    for (final r in t.luckBonusLots) {
      if (r.weight > 0 && r.lotType >= 0 && r.lotType < 5) {
        bonus[r.lotType].add((r.weight, r.result));
      }
    }
    _tables = [for (final items in bonus) _LuckSkillTable(items)];
  }
  List<_Item>? _good, _great, _perfect;
  final _hold = <_Item>[];
  late final List<_LuckSkillTable> _tables;
  var _minimum = <List<int>>[];
  int _minimumCounter = 0;
  final _lastConsumed = <int, int>{};

  void setBuff(int percent) {
    final mul = f(f(percent) / 100);
    for (final t in _tables) {
      t.buff = mul;
    }
  }

  int _maxMinimum() {
    var m = 0;
    for (final e in _minimum) {
      if (m <= e[1]) m = e[1];
    }
    return m;
  }

  void _consumeMinimum(int applied, int t) {
    final kept = <List<int>>[];
    for (final e in _minimum) {
      if (e[1] > applied || e[2] < 0) {
        kept.add(e);
        continue;
      }
      e[2] = i32(e[2] - 1);
      if (e[2] != 0) {
        kept.add(e);
        continue;
      }
      _lastConsumed[e[0]] = t;
    }
    _minimum = kept;
  }

  int enableMinimum(int result, int limit) {
    _minimumCounter = i32(_minimumCounter + 1);
    _minimum.add([_minimumCounter, result, limit >= 1 ? limit : -1]);
    return _minimumCounter;
  }

  void disableMinimum(int id) => _minimum = [
    for (final e in _minimum)
      if (e[0] != id) e,
  ];

  bool isMinimumActive(int id) => _minimum.any((e) => e[0] == id);

  int takeLastConsumed(int id) => _lastConsumed.remove(id) ?? -1;

  int luckBonus(int lotType, int t, LiveRandom random) {
    final r = random.nextInt(streamLuck);
    final applied = _maxMinimum();
    if (lotType < 0 || lotType >= _tables.length) {
      throw RangeError('lot type out of range');
    }
    final table = _tables[lotType];
    if (applied < 1) {
      return table.lottery(r) ?? (throw StateError('no luck lottery item'));
    }
    final v =
        table.lotteryWithMinimum(r, applied) ??
        (throw StateError('no luck lottery item'));
    _consumeMinimum(applied, t);
    return v;
  }

  int basePoint(int nt, int j, LiveRandom random) {
    if (_nonLuckNoteTypes.contains(nt)) return 0;
    final u = _u32(j + 1);
    if (u < 9 && ((0x107 >> (u & 31)) & 1) != 0) return 0;
    final r = random.nextInt(streamLuck);
    List<_Item>? items;
    if (_isSubNote(nt)) {
      items = _hold;
    } else if (_u32(j - 5) < 2) {
      items = _perfect;
    } else if (j == _jGreat) {
      items = _great;
    } else if (j == _jGood) {
      items = _good;
    } else {
      return 0;
    }
    if (items == null) throw StateError('no base point table');
    return _lotteryTable(items, r) ??
        (throw StateError('empty base point table'));
  }
}

class LuckScore {
  int totalBonusPoint = 0;
  int gauge = 0;
  int lotCount = 0;
  int rushCombo = 0;
  final results = [0, 0, 0, 0];
  int next = _invalid;
  int gaugeMax = 100;
  int _gaugeMaxDefault = 100;
  int _gaugeMaxRush = 50;

  void addGauge(int v) {
    final g = i32(gauge + v);
    final m = gaugeMax;
    if (m <= g) {
      if (m <= 0) throw StateError('luck gauge maximum below 1');
      lotCount = i32(lotCount + g ~/ m);
      gauge = g.remainder(m);
    } else {
      gauge = g;
    }
  }

  void _changeMax(int m) {
    if (m < 1 || gaugeMax == m) return;
    gaugeMax = m;
    final g = gauge;
    if (g <= m) return;
    lotCount = i32(lotCount + g ~/ m);
    gauge = g.remainder(m);
  }

  void initialize(int max, int rushMax) {
    if (max > 0 && rushMax > 0) {
      _gaugeMaxDefault = max;
      _gaugeMaxRush = rushMax;
      _changeMax(max);
    }
  }

  int currentLotType() {
    final rc = _u32(rushCombo);
    return rc < 4 ? _lotTypeByRush[rc] : _chanceLow;
  }

  void addScore(int r) {
    final i = r - 1;
    if (_u32(i) < 3) {
      totalBonusPoint = i32(totalBonusPoint + _bonusPointByResult[i]);
    }
    if (r >= 0 && r <= _critical) results[r]++;
    if (_u32(r) < 3) {
      rushCombo = 0;
      _changeMax(_gaugeMaxDefault);
    } else if (r == _critical) {
      rushCombo = i32(rushCombo + 1);
      _changeMax(_gaugeMaxRush);
    }
  }
}

class _FactorStorage {
  final lot = <(int, double)>[];
  final gauge = <(int, double)>[];
  final _lotIds = <int, double>{};
  final _gaugeIds = <int, double>{};
  int _current = 0;

  static double at(List<(int, double)> cmds, int t) {
    var s = 0.0;
    for (final (ct, d) in cmds) {
      if (ct <= t) s = f(s + d);
    }
    return s;
  }

  int add(bool isGauge, int t, double value) {
    _current = i32(_current + 1);
    (isGauge ? _gaugeIds : _lotIds)[_current] = value;
    (isGauge ? gauge : lot).add((t, value));
    return _current;
  }

  void subtract(bool isGauge, int t, int id) {
    final ids = isGauge ? _gaugeIds : _lotIds;
    final v = ids.remove(id);
    if (v == null) throw StateError('luck factor id not found');
    (isGauge ? gauge : lot).add((t, -v));
  }
}

class GekisouRange {
  GekisouRange(this.startMs, this.endMs, this.mission, this.targets);
  final int startMs;
  final int endMs;
  final int mission;
  final Set<int> targets;
}

class RangeState {
  int state = sWait;
  int timeTo = 0;
  int combo = 0;
  int maxCombo = 0;
  int just = 0;
  int rawJust = 0;
  int cumBase = 0;
  int startScore = 0;
  int endScore = 0;
  int lastComboMs = -1;
  int lastJustMs = -1;
  final luck = LuckScore();
  double swElapsed = 0;
  bool swStopped = true;
  int get score => i32(endScore - startScore);
}

class _Resume {
  int processed = 0;
  int combo = 0, maxCombo = 0, just = 0, rawJust = 0, cumBase = 0;
  double comboBonus = 0, justBonus = 0;
  int iCb = 0, iJb = 0, iAddJust = 0, iAddCombo = 0;
}

class _Rule {
  _Rule(this.rangeIndex, this.unit, this.effect, this.maxCum, this.maxEff);
  final int rangeIndex;
  final int unit;
  final int effect;
  final int maxCum;
  final int maxEff;
}

int _cumulativeJustBonus(Iterable<_Rule> rules, int rangeIndex, int x) {
  var total = 0;
  for (final r in rules) {
    if (r.rangeIndex != rangeIndex || r.unit <= 0) continue;
    var steps = i32(x ~/ r.unit);
    if (!(steps <= r.maxCum || r.maxCum == 0 || r.maxCum < 0)) steps = r.maxCum;
    var v = (steps * r.effect).toSigned(32);
    if (r.maxEff > 0 && r.maxEff <= v) v = r.maxEff;
    total = i32(total + v);
  }
  return total;
}

int _scoreFrame(int ms) => ms > 0 ? f(f(ms) / 40).ceil() : 0;
int _previousFrameEnd(int t) => i32(imul(_scoreFrame(t), 40) - 40);
int _lastJudgementIndex(List<(int, int, int)> h, int count, int maxMs) {
  var hi = count - 1;
  if (hi < 1) return 0;
  var lo = 0;
  for (;;) {
    final mid = lo + sdiv(hi - lo + 1, 2);
    if (h[mid].$1 <= maxMs) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
    if (lo >= hi) return lo;
  }
}

abstract interface class LuckHandle {
  int add(int t, int percent);
  void disable(int t, int id);
}

class GekisouEnv {
  GekisouEnv(this.random, this.handle);
  final LiveRandom random;
  final LuckHandle handle;
}

/// A judged note as the controller reads it: id, type, chart time, converted judgement.
typedef GkNote = (int id, int type, int timeMs, int judgement);

class GekisouController implements GekisouComboInfo {
  GekisouController(
    List<(int, int, int)> ranges,
    List<(int, int)> notes,
    GekisouTables t,
    this._rushPercent,
    this._lastNoteDelayMs,
  ) : ranges = [
        for (final (s, e, mission) in ranges)
          GekisouRange(s, e, mission, {
            for (final (id, time) in notes)
              if (s <= time && time <= e) id,
          }),
      ],
      machine = LotteryMachine(t),
      _luckGaugeMax = t.gaugeMax {
    states = [
      for (final r in this.ranges)
        RangeState()
          ..luck.initialize(
            r.mission == missionLuck ? t.gaugeMax : 0,
            r.mission == missionLuck ? t.gaugeMaxRush : 0,
          ),
    ];
    final n = this.ranges.length;
    _history = [for (var i = 0; i < n; i++) []];
    _snapshot = [for (var i = 0; i < n; i++) []];
    _resume = [for (var i = 0; i < n; i++) _Resume()];
    _pending = [for (var i = 0; i < n; i++) []];
  }
  final List<GekisouRange> ranges;
  late final List<RangeState> states;
  final LotteryMachine machine;
  final int _rushPercent;
  final int _lastNoteDelayMs;
  final int _luckGaugeMax;
  final _storage = _FactorStorage();
  int _rushId = 0;
  final _playing = <int>[];
  final _comboBonusIds = <int, int>{};
  final _justBonusIds = <int, int>{};
  final _rules = <int, _Rule>{};
  int _handleId = 0;
  bool _needsRecalc = false;
  bool _fullRecalc = false;
  int _seq = 0;
  late List<List<(int, int, int)>> _history;
  late List<List<int>> _snapshot;
  late List<_Resume> _resume;
  final _cbStack = <(int, double, int)>[];
  final _jbStack = <(int, double, int)>[];
  final _addJustStack = <(int, double, int)>[];
  final _addComboStack = <(int, double, int)>[];
  final _prStack = <(int, int, int, int)>[];
  var _unlimited = <(int, int)>[];
  var _limited = <(int, int, int)>[];
  final _limitedIds = <int>{};
  late List<List<(int, int, int, int)>> _pending;
  int _lotResult = _invalid;
  final lotResults = <int>[];
  final stateUpdates = <int>[];
  int currentPlayingIndex = -1;

  /// Luck recording: no lottery is drawn (the luck DP propagates it).
  bool weighted = false;

  int _nextId() => _handleId = i32(_handleId + 1);
  void _flag() {
    _needsRecalc = true;
    _fullRecalc = true;
  }

  /// The last range that started and has not finished, or -1.
  int playingRangeIndex() => _playing.isNotEmpty ? _playing.last : -1;

  void addJustCount(int timeMs, num count) {
    _addJustStack.add((timeMs, f(count), playingRangeIndex()));
    _flag();
  }

  void addGekisouCombo(int timeMs, num count) {
    _addComboStack.add((timeMs, f(count), playingRangeIndex()));
    _flag();
  }

  void _applyFixedCount(int idx, double delta, int range, bool just) {
    if (range != -1 && range != idx) return;
    final n = i32(delta.truncate());
    final rs = states[idx];
    if (just) {
      rs.just = i32(rs.just + n);
      rs.cumBase = i32(rs.cumBase + n);
    } else {
      rs.combo = i32(rs.combo + n);
      rs.maxCombo = math.max(rs.maxCombo, rs.combo);
    }
  }

  void addLuckPoint(int p) {
    final i = playingRangeIndex();
    if (i < 0) return;
    final ls = states[i].luck;
    ls.totalBonusPoint = i32(ls.totalBonusPoint + p);
  }

  void addLuckGaugePercent(int g) {
    final i = playingRangeIndex();
    if (i >= 0) states[i].luck.addGauge(g);
  }

  int currentGaugeMax() {
    final i = playingRangeIndex();
    return i >= 0 ? states[i].luck.gaugeMax : _luckGaugeMax;
  }

  int addComboBonus(int t, int bonus) {
    final i = _nextId();
    _comboBonusIds[i] = bonus;
    _cbStack.add((t, bonus.toDouble(), i32(_seq - 1)));
    _flag();
    return i;
  }

  void subtractComboBonus(int t, int id) {
    final v = _comboBonusIds.remove(id);
    if (v == null) throw StateError('combo bonus id not found');
    _cbStack.add((t, -v.toDouble(), i32(_seq - 1)));
    _flag();
  }

  int addJustBonus(int t, int bonus) {
    final i = _nextId();
    _justBonusIds[i] = bonus;
    _jbStack.add((t, bonus.toDouble(), i32(_seq - 1)));
    _flag();
    return i;
  }

  void subtractJustBonus(int t, int id) {
    final v = _justBonusIds.remove(id);
    if (v == null) throw StateError('Just bonus id not found');
    _jbStack.add((t, -v.toDouble(), i32(_seq - 1)));
    _flag();
  }

  int addCumulativeRule(int unit, int effect, int maxCum, int maxEff) {
    final i = _nextId();
    _rules[i] = _Rule(playingRangeIndex(), unit, effect, maxCum, maxEff);
    _flag();
    return i;
  }

  void removeCumulativeRule(int id) {
    if (_rules.remove(id) != null) _flag();
  }

  int enableComboProtect(int t, int limit, int mask) {
    final i = _nextId();
    if (limit < 1) {
      _prStack.add((t, 1, i, mask & 0xff));
    } else {
      _limitedIds.add(i);
      _prStack.add((t, i32(limit + 1), i, mask & 0xff));
    }
    _flag();
    return i;
  }

  void disableComboProtect(int t, int id) {
    final d = _limitedIds.remove(id) ? -2 : -1;
    _prStack.add((t, d, id, 0));
    _flag();
  }

  int addLotProbabilityUp(int t, double value) => _storage.add(false, t, value);
  int addGaugeUp(int t, double value) => _storage.add(true, t, value);
  void subtractLotProbabilityUp(int t, int id) =>
      _storage.subtract(false, t, id);
  void subtractGaugeUp(int t, int id) => _storage.subtract(true, t, id);

  void _recalculate() {
    for (var idx = 0; idx < states.length; idx++) {
      if (states[idx].state >= sDelay || _history[idx].isEmpty) continue;
      final rr = _resume[idx];
      final rs = states[idx];
      final h = _history[idx];
      double cb, jb;
      int iCb, iJb, iPr, k, iAddJust, iAddCombo;
      if (!_fullRecalc &&
          _prStack.isEmpty &&
          1 <= rr.processed &&
          rr.processed <= h.length) {
        rs.combo = rr.combo;
        rs.maxCombo = rr.maxCombo;
        rs.just = rr.just;
        rs.rawJust = rr.rawJust;
        rs.cumBase = rr.cumBase;
        cb = rr.comboBonus;
        jb = rr.justBonus;
        iCb = rr.iCb;
        iJb = rr.iJb;
        iPr = 0;
        k = rr.processed;
        iAddJust = rr.iAddJust;
        iAddCombo = rr.iAddCombo;
      } else {
        rs.combo = rs.maxCombo = rs.just = rs.rawJust = rs.cumBase = 0;
        _snapshot[idx] = [];
        _unlimited = [];
        _limited = [];
        cb = 1;
        jb = 1;
        iCb = iJb = iPr = k = iAddJust = iAddCombo = 0;
      }
      while (k < h.length) {
        final (et, j, es) = h[k];
        while (iCb < _cbStack.length) {
          final (ct, d, cs) = _cbStack[iCb];
          if (et <= ct && (et < ct || es < cs)) break;
          cb = f(cb + d);
          iCb++;
        }
        while (iJb < _jbStack.length) {
          final (ct, d, cs) = _jbStack[iJb];
          if (et <= ct && (et < ct || es < cs)) break;
          jb = f(jb + d);
          iJb++;
        }
        while (iPr < _prStack.length && et >= _prStack[iPr].$1) {
          final (_, d, pid, mask) = _prStack[iPr];
          if (d < 2) {
            if (d == 1) {
              _unlimited.add((pid, mask));
            } else if (d < -1) {
              final p = _limited.indexWhere((x) => x.$1 == pid);
              if (p >= 0) _limited.removeAt(p);
            } else {
              final p = _unlimited.indexWhere((x) => x.$1 == pid);
              if (p >= 0) _unlimited.removeAt(p);
            }
          } else {
            _limited.add((pid, i32(d - 1), mask));
          }
          iPr++;
        }
        while (iAddJust < _addJustStack.length &&
            _addJustStack[iAddJust].$1 <= et) {
          final (_, d, range) = _addJustStack[iAddJust];
          _applyFixedCount(idx, d, range, true);
          iAddJust++;
        }
        while (iAddCombo < _addComboStack.length &&
            _addComboStack[iAddCombo].$1 <= et) {
          final (_, d, range) = _addComboStack[iAddCombo];
          _applyFixedCount(idx, d, range, false);
          iAddCombo++;
        }
        _entry(idx, j, floorToI32(cb), floorToI32(jb));
        _snapshot[idx].add(rs.combo);
        k++;
      }
      _resume[idx] = _Resume()
        ..processed = h.length
        ..combo = rs.combo
        ..maxCombo = rs.maxCombo
        ..just = rs.just
        ..rawJust = rs.rawJust
        ..cumBase = rs.cumBase
        ..comboBonus = cb
        ..justBonus = jb
        ..iCb = iCb
        ..iJb = iJb
        ..iAddJust = iAddJust
        ..iAddCombo = iAddCombo;
      for (var i = iAddJust; i < _addJustStack.length; i++) {
        final (_, d, range) = _addJustStack[i];
        _applyFixedCount(idx, d, range, true);
      }
      for (var i = iAddCombo; i < _addComboStack.length; i++) {
        final (_, d, range) = _addComboStack[i];
        _applyFixedCount(idx, d, range, false);
      }
    }
    _fullRecalc = false;
  }

  void _entry(int idx, int j, int iCombo, int iJust) {
    final rs = states[idx];
    if (_u32(j - 3) < 0xfffffffe) {
      if (_u32(j - 7) > 0xfffffffb) {
        rs.combo = i32(rs.combo + iCombo);
        rs.maxCombo = math.max(rs.maxCombo, rs.combo);
      } else {
        return;
      }
    } else {
      final bit = 1 << (j & 31);
      int eff(int m) => m != 0 ? m : 6;
      var prot = _unlimited.any((e) => (eff(e.$2) & bit) != 0);
      for (var i = _limited.length - 1; i >= 0; i--) {
        final (pid, rem, m) = _limited[i];
        if ((eff(m) & bit) != 0) {
          final left = i32(rem - 1);
          if (left < 1) {
            _limited.removeAt(i);
          } else {
            _limited[i] = (pid, left, m);
          }
          prot = true;
        }
      }
      if (!prot) {
        rs.maxCombo = math.max(rs.maxCombo, rs.combo);
        rs.combo = 0;
      }
    }
    if (j == _jJust) {
      rs.rawJust = i32(rs.rawJust + 1);
      rs.cumBase = i32(rs.cumBase + iJust);
      final c = _cumulativeJustBonus(_rules.values, idx, rs.cumBase);
      rs.just = i32(c + iJust + rs.just);
    }
  }

  int _timingComboInRange(int idx, int t) {
    final h = _history[idx];
    final sn = _snapshot[idx];
    final n = math.min(h.length, sn.length);
    if (n == 0) return 0;
    final prevEnd = _previousFrameEnd(t);
    if (prevEnd < h.first.$1) return 0;
    return sn[_lastJudgementIndex(h, n, prevEnd)];
  }

  /// Gauge speed and lot buff filed at a chart time.
  double gaugeSpeedAt(int t) => _FactorStorage.at(_storage.gauge, t);
  int lotBuffAt(int t) =>
      floorToI32(f(_FactorStorage.at(_storage.lot, t) * 100));

  void _updateLuck(int idx, int nt, int tn, int j, GekisouEnv env) {
    if (weighted) return;
    final buff = floorToI32(f(_FactorStorage.at(_storage.lot, tn) * 100));
    machine.setBuff(buff);
    final gup = _FactorStorage.at(_storage.gauge, tn);
    final base = machine.basePoint(nt, j, env.random);
    final add = floorToI32(f(f(gup + 1) * f(base)));
    states[idx].luck.addGauge(add);
    _consumeLot(idx, tn, env);
  }

  void _disableRush(int t, GekisouEnv env) {
    if (_rushId != 0) {
      env.handle.disable(t, _rushId);
      _rushId = 0;
    }
  }

  void _consumeLot(int idx, int t, GekisouEnv env) {
    final st = states[idx];
    if (st.state > sEnd || st.luck.lotCount < 1) return;
    st.luck.lotCount--;
    if (st.luck.next == _invalid) {
      st.luck.next = machine.luckBonus(_noneLot, t, env.random);
    }
    final next = st.luck.next;
    final rush = st.luck.rushCombo;
    if (rush == 0) {
      if (next == _critical) {
        _rushId = env.handle.add(t, _rushPercent);
      } else {
        _disableRush(t, env);
      }
    } else if (next != _critical) {
      _disableRush(t, env);
    }
    st.luck.addScore(next);
    if (next != _invalid) {
      _lotResult = next;
      lotResults.add(next);
    }
    st.luck.next = machine.luckBonus(st.luck.currentLotType(), t, env.random);
  }

  void _pendingLots(int t, GekisouEnv env) {
    if (weighted) return;
    for (final idx in [..._playing]) {
      final rs = states[idx];
      if (ranges[idx].mission == missionLuck &&
          rs.state == sPlaying &&
          rs.luck.lotCount != 0 &&
          _lotResult == _invalid) {
        machine.setBuff(
          floorToI32(f(_FactorStorage.at(_storage.lot, t) * 100)),
        );
        _consumeLot(idx, t, env);
      }
    }
  }

  void _judge(int idx, int nt, int tn, int j, GekisouEnv env) {
    if (j == _jPass || j == _jWait) return;
    _history[idx].add((tn, j, _seq));
    _seq = i32(_seq + 1);
    _needsRecalc = true;
    if (_u32(j - 3) < 4) states[idx].lastComboMs = tn;
    if (j == _jJust) states[idx].lastJustMs = tn;
    if (ranges[idx].mission == missionLuck) {
      if (states[idx].state < sStart) {
        _pending[idx].add((nt, tn, 0, j));
      } else {
        _updateLuck(idx, nt, tn, j, env);
      }
    }
  }

  /// After the frame's skills and score: judged notes of the ranges, the
  /// recount, fever-end scores and pending lots.
  void update(
    int t,
    List<GkNote> judged,
    List<(int, int)> feverUpdates,
    int currentScore,
    GekisouEnv env,
  ) {
    for (var idx = 0; idx < states.length; idx++) {
      if (states[idx].state > sStandby && _pending[idx].isNotEmpty) {
        final pending = _pending[idx];
        _pending[idx] = [];
        for (final (nt, tn, _, j) in pending) {
          _updateLuck(idx, nt, tn, j, env);
        }
      }
    }
    for (var idx = 0; idx < states.length; idx++) {
      for (final (nid, nt, tn, j) in judged) {
        if (ranges[idx].targets.contains(nid)) _judge(idx, nt, tn, j, env);
      }
    }
    if (_needsRecalc) {
      _recalculate();
      _needsRecalc = false;
    }
    for (final (idx, fs) in feverUpdates) {
      if (idx >= states.length) {
        throw RangeError(
          'IndexOutOfRangeException: fever without a Gekisou range',
        );
      }
      if (fs == feverEnd) states[idx].endScore = currentScore;
    }
    _pendingLots(t, env);
  }

  void _stateUpdate(int idx) {
    if (!stateUpdates.contains(idx)) stateUpdates.add(idx);
  }

  static int _elapsedMs(RangeState rs) {
    final v = f(rs.swElapsed * 1000);
    return v == double.infinity ? -9007199254740991 : v.truncate();
  }

  /// Before the frame: range state machine and stopwatches.
  void beforeUpdate(
    double dt,
    int t,
    List<(int, int)> feverUpdates,
    int currentScore,
    GekisouEnv env,
  ) {
    stateUpdates.clear();
    _lotResult = _invalid;
    lotResults.clear();
    currentPlayingIndex = -1;
    for (var i = 0; i < states.length; i++) {
      states[i].timeTo = i32(ranges[i].startMs - t);
    }
    List<int>? remove;
    for (final idx in _playing) {
      final rs = states[idx];
      final st = rs.state;
      if (st < sEnd) {
        if (st == sStart) {
          rs.state = sPlaying;
          _stateUpdate(idx);
          currentPlayingIndex = idx;
        } else if (st == sPlaying) {
          currentPlayingIndex = idx;
        }
      } else if (st == sEnd) {
        currentPlayingIndex = idx;
        if (!rs.swStopped) rs.swElapsed = f(rs.swElapsed + dt);
        if (_lastNoteDelayMs <= _elapsedMs(rs)) {
          rs.swElapsed = 0;
          rs.swStopped = false;
          rs.state = sDelay;
          _stateUpdate(idx);
        }
      } else if (st == sDelay) {
        if (!rs.swStopped) rs.swElapsed = f(rs.swElapsed + dt);
        if (_completeDelayMs <= _elapsedMs(rs)) {
          rs.state = sComplete;
          rs.swStopped = true;
          _stateUpdate(idx);
        }
      } else if (st == sComplete) {
        rs.state = sFinish;
        _stateUpdate(idx);
        (remove ??= []).add(idx);
        _disableRush(t, env);
      }
    }
    if (remove != null) {
      for (final idx in remove) {
        _playing.remove(idx);
      }
    }
    for (final (idx, fs) in feverUpdates) {
      if (idx >= states.length) {
        throw RangeError(
          'IndexOutOfRangeException: fever without a Gekisou range',
        );
      }
      final rs = states[idx];
      if (fs == feverEnd) {
        rs.state = sEnd;
        rs.swElapsed = 0;
        rs.swStopped = false;
        _stateUpdate(idx);
      } else if (fs == feverFever) {
        rs.state = sStart;
        rs.startScore = currentScore;
        _playing.add(idx);
        _stateUpdate(idx);
        currentPlayingIndex = idx;
      }
    }
    for (var idx = 0; idx < states.length; idx++) {
      if (states[idx].state == sWait && states[idx].timeTo < _standbyMs) {
        states[idx].state = sStandby;
        _stateUpdate(idx);
      }
    }
  }

  @override
  int? gekisouCombo(int timeMs) {
    final i = ranges.indexWhere(
      (r) =>
          r.mission == missionCombo && r.startMs <= timeMs && timeMs <= r.endMs,
    );
    return i < 0 ? null : _timingComboInRange(i, timeMs);
  }
}

/// The chart's fevers: Wait → Fever at the start and Fever → End at the
/// end, at most one step per frame.
class FeverUpdater {
  FeverUpdater(this._fevers) : _state = List.filled(_fevers.length, feverWait);
  final List<(int, int)> _fevers;
  final List<int> _state;
  final _out = <(int, int)>[];

  List<(int, int)> update(int t) {
    _out.clear();
    for (var i = 0; i < _fevers.length; i++) {
      final (s, e) = _fevers[i];
      final st = _state[i];
      final next = st == feverWait && t >= s
          ? feverFever
          : st == feverFever && t >= e
          ? feverEnd
          : 0;
      if (next == 0) continue;
      _state[i] = next;
      _out.add((i, next));
    }
    return _out;
  }
}

/// The song's mission pattern: 0 when a mission is missing, 1 all the
/// same, 2 all different, 3 otherwise.
int missionPattern(int t0, int t1, int t2) {
  if (t0 == 0 || t1 == 0 || t2 == 0) return 0;
  if (t0 == t1) return t0 == t2 ? 1 : 3;
  if (t1 != t2 && t0 != t2) return 2;
  return 3;
}

/// Rank bonus percentages `[range][rank - 1]` of a mission pattern.
List<List<int>> rankingFactors(GekisouTables t, int pattern) {
  final out = [for (var i = 0; i < 3; i++) List.filled(5, 0)];
  for (final r in t.rankingBonuses) {
    final c = r.count - 1;
    final k = r.rank - 1;
    if (r.pattern == pattern && _u32(c) < 3 && _u32(k) <= 4) {
      out[c][k] = r.percent;
    }
  }
  return out;
}
