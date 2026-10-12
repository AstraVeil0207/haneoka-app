/// The whole-live simulation's primitives (`engine/full/num.ts`,
/// `random.ts`, `combo.ts`, `life.ts`): native numeric conversions, the
/// live's .NET random streams, the combo counter and the life gauge.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../num.dart';

const i32Min = -2147483648;
const i32Max = 2147483647;

/// `x as i32`: truncation with saturation, NaN → 0.
int satI32(double x) {
  if (x.isNaN) return 0;
  if (x >= i32Max) return i32Max;
  if (x <= i32Min) return i32Min;
  return x.truncate();
}

/// Floor to i32; +∞ gives `i32::MIN`.
int floorToI32(double x) {
  if (x == double.infinity) return i32Min;
  final t = satI32(x);
  return t != i32Min && f(t) > x ? t - 1 : t;
}

int floorToI32F64(double x) {
  if (x == double.infinity) return i32Min;
  final t = satI32(x);
  return t != i32Min && t > x ? t - 1 : t;
}

/// Ceil to i32; ±∞ gives `i32::MIN`.
int ceilToI32(double x) {
  if (x == double.infinity || x == double.negativeInfinity) return i32Min;
  final t = satI32(x);
  return t != i32Max && f(t) < x ? t + 1 : t;
}

/// `Math.round` then ties to even.
double roundTiesEven(double x) {
  final r = (x + 0.5).floorToDouble();
  return (x % 1).abs() == 0.5 && r % 2 != 0 ? r - 1 : r;
}

double minIgnoringNaN(double a, double b) {
  if (a.isNaN) return b;
  if (b.isNaN) return a;
  if (a == b) return a.isNegative && a == 0 ? a : b;
  return a < b ? a : b;
}

/// Signed division and remainder that treat a zero divisor as 0.
int sdiv(int a, int b) => b == 0 ? 0 : i32(a / b);
int srem(int a, int b) => i32(a - imul(sdiv(a, b), b));

/// Frame of a music time for the score and life logs.
int getFrame(num ms) => ms < 0 ? 0 : ceilToI32(f(f(ms) / 40));

const _mbig = 2147483647;
const _mseed = 161803398;
const streamSkill = 0;
const streamLuck = 1;

class _NetRandom {
  _NetRandom(int seed) {
    final sa = _seeds;
    final subtraction = seed == -2147483648 ? _mbig : seed.abs();
    var mj = i32(_mseed - subtraction);
    sa[55] = mj;
    var mk = 1;
    var ii = 0;
    for (var i = 1; i < 55; i++) {
      ii += 21;
      if (ii >= 55) ii -= 55;
      sa[ii] = mk;
      mk = i32(mj - mk);
      if (mk < 0) mk = i32(mk + _mbig);
      mj = sa[ii];
    }
    for (var k = 1; k < 5; k++) {
      for (var i = 1; i < 56; i++) {
        var n = i + 30;
        if (n >= 55) n -= 55;
        sa[i] = i32(sa[i] - sa[1 + n]);
        if (sa[i] < 0) sa[i] = i32(sa[i] + _mbig);
      }
    }
  }
  final _seeds = Int32List(56);
  var _inext = 0;
  var _inextp = 21;

  int _internal() {
    var a = _inext + 1, b = _inextp + 1;
    if (a >= 56) a = 1;
    if (b >= 56) b = 1;
    var r = i32(_seeds[a] - _seeds[b]);
    if (r == _mbig) r--;
    if (r < 0) r = i32(r + _mbig);
    _seeds[a] = r;
    _inext = a;
    _inextp = b;
    return r;
  }

  double nextDouble() => _internal() * (1 / _mbig);

  /// `Next(int.MinValue, int.MaxValue)`: the large-range sample.
  int nextInt() {
    var result = _internal();
    if (_internal() % 2 == 0) result = -result;
    var d = (result + (_mbig - 1)).toDouble();
    d /= 2 * _mbig - 1;
    return i32((d * 4294967295).truncate() - 2147483648);
  }
}

/// The live's random streams: four .NET `System.Random` instances seeded
/// from one base seed.
class LiveRandom {
  LiveRandom([this.baseSeed = 0])
    : _streams = [
        for (var index = 0; index < 4; index++)
          _NetRandom(imul(index, -0x61c88647) ^ baseSeed),
      ];
  final int baseSeed;
  final List<_NetRandom> _streams;
  int draws = 0;

  double value(int stream) {
    draws++;
    return f(_streams[stream].nextDouble());
  }

  int nextInt(int stream) {
    draws++;
    return _streams[stream].nextInt();
  }
}

/// The live's combo counter: judgements in chart-time order; a note reads
/// the combo strictly before its time.
class ComboCounter {
  final _times = <int>[];
  final _orders = <int>[];
  final _judgements = <int>[];
  final _combos = <int>[];
  int _addOrder = 0;

  void addJudgement(int timeMs, int judgement) {
    if (judgement == 0 || judgement == 7) return;
    final order = _addOrder++;
    var i = _times.length;
    while (i >= 1 &&
        (timeMs < _times[i - 1] ||
            (timeMs == _times[i - 1] && order < _orders[i - 1]))) {
      i--;
    }
    _times.insert(i, timeMs);
    _orders.insert(i, order);
    _judgements.insert(i, judgement);
    _combos.insert(i, 0);
    var combo = i == 0 ? 0 : _combos[i - 1];
    for (var k = i; k < _times.length; k++) {
      final j = _judgements[k];
      combo = j == 1 || j == 2 ? 0 : combo + 1;
      _combos[k] = combo;
    }
  }

  /// Combo after the last judgement strictly before [t].
  int timingCombo(int t) {
    final n = _times.length;
    if (n == 0 || _times.first >= t) return 0;
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = lo + ((hi - lo) / 2).ceil();
      if (_times[mid] < t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return _combos[lo];
  }
}

const _noteDamage = 0;
const _skillDamage = 1;
const _recovery = 2;
const _guardStart = 3;
const _guardEnd = 4;
const _reductionStart = 5;
const _reductionEnd = 6;

class _LifeCommand {
  _LifeCommand(this.timeMs, this.kind, this.value, this.overHeal, this.safety);
  final int timeMs;
  final int kind;
  final int value;
  final bool overHeal;
  final bool safety;
}

int _nonNegative(int x) => x < 0 ? 0 : x;
int _reduce(int damage, int bp) {
  if (bp < 1) return damage;
  if ((bp & 0xffffffff) >> 4 > 0x270) return 0;
  return _nonNegative(i32(imul(i32(10000 - bp), damage) / 10000));
}

/// The live's life: commands filed in 40 ms frames and replayed with a
/// cache of the completed frames.
class LifeController {
  LifeController(this._initialLife, this._damage, int musicLengthMs)
    : _maxLife = _initialLife,
      currentLife = _initialLife,
      _maxFrame = i32(getFrame(musicLengthMs) + 2) {
    _commands = List.filled(_maxFrame, null);
  }
  final int _initialLife;
  final List<double> _damage;
  int _maxLife;
  int currentLife;
  final _guards = <int>[];
  int _guardCounter = 0;
  final _reductions = <int, int>{};
  int _reductionCounter = 0;
  final _limits = <int, int>{};
  int _limitCounter = 0;
  final int _maxFrame;
  late final List<List<_LifeCommand>?> _commands;
  int _cachedFrame = -1;
  int _cachedLife = 0, _cachedGuard = 0, _cachedReduction = 0;

  int get maximum => _maxLife;

  int _frameOf(int ms) {
    final frame = getFrame(ms);
    return _maxFrame <= frame ? _maxFrame - 1 : frame;
  }

  void _add(_LifeCommand cmd) {
    final frame = _frameOf(cmd.timeMs);
    final list = _commands[frame] ??= [];
    var i = list.length;
    while (i >= 1 && cmd.timeMs < list[i - 1].timeMs) {
      i--;
    }
    list.insert(i, cmd);
    if (frame <= _cachedFrame) {
      _cachedFrame = -1;
      _cachedLife = _cachedGuard = _cachedReduction = 0;
    }
  }

  void noteDamage(int timeMs, int judgement) {
    if (judgement == 0 || judgement == 7) return;
    final d = judgement < _damage.length ? _damage[judgement].toInt() : 0;
    if (d > 0) _add(_LifeCommand(timeMs, _noteDamage, d, false, false));
  }

  void recovery(int timeMs, num amount, bool overHeal) {
    if (amount > 0) {
      _add(_LifeCommand(timeMs, _recovery, i32(amount), overHeal, false));
    }
  }

  void skillDamage(int timeMs, num amount, bool safety) {
    if (amount > 0) {
      _add(_LifeCommand(timeMs, _skillDamage, i32(amount), false, safety));
    }
  }

  int enableReduction(int timeMs, num bp) {
    final id = ++_reductionCounter;
    _reductions[id] = i32(bp);
    _add(_LifeCommand(timeMs, _reductionStart, i32(bp), false, false));
    return id;
  }

  void disableReduction(int timeMs, int id) {
    final bp = _reductions.remove(id);
    if (bp == null) return;
    _add(_LifeCommand(timeMs, _reductionEnd, bp, false, false));
  }

  int addLimit(num amount) {
    final id = ++_limitCounter;
    _limits[id] = i32(amount);
    _updateMax();
    return id;
  }

  void subtractLimit(int id) {
    if (_limits.remove(id) != null) _updateMax();
  }

  void _updateMax() {
    var sum = 0;
    for (final v in _limits.values) {
      sum = i32(sum + v);
    }
    _maxLife = i32(_maxLife + sum);
  }

  int enableGuard(int timeMs) {
    final id = ++_guardCounter;
    _guards.add(id);
    _add(_LifeCommand(timeMs, _guardStart, 0, false, false));
    return id;
  }

  void disableGuard(int timeMs, int id) {
    if (!_guards.remove(id)) return;
    _add(_LifeCommand(timeMs, _guardEnd, 0, false, false));
  }

  void _step(List<int> state, _LifeCommand cmd) {
    var life = state[0], guard = state[1], reduction = state[2];
    switch (cmd.kind) {
      case _noteDamage:
        if (guard < 1) {
          life = _nonNegative(i32(life - _reduce(cmd.value, reduction)));
        }
      case _skillDamage:
        if (guard < 1 && (life > 0 || !cmd.safety)) {
          life = i32(life - _reduce(cmd.value, reduction));
          life = math.max(life, cmd.safety ? 1 : 0);
        }
      case _recovery:
        if (life > 0) {
          final cap = cmd.overHeal ? i32(_maxLife << 1) : _maxLife;
          final s = i32(cmd.value + life);
          life = s < cap ? s : cap;
        }
      case _guardStart:
        guard = i32(guard + 1);
      case _guardEnd:
        guard = _nonNegative(i32(guard - 1));
      case _reductionStart:
        reduction = i32(reduction + cmd.value);
      case _reductionEnd:
        reduction = _nonNegative(i32(reduction - cmd.value));
    }
    state[0] = life;
    state[1] = guard;
    state[2] = reduction;
  }

  int lifeAt(int ms) {
    final frame = _frameOf(ms);
    final c = _cachedFrame;
    bool full;
    int start;
    final state = [_initialLife, 0, 0];
    if (c < 0 || frame <= c) {
      full = c >= 0 && frame <= c;
      start = 0;
    } else {
      full = false;
      state[0] = _cachedLife;
      state[1] = _cachedGuard;
      state[2] = _cachedReduction;
      start = c + 1;
    }
    for (var k = start; k < math.max(frame, start); k++) {
      final cmds = _commands[k];
      if (cmds != null) {
        for (final cmd in cmds) {
          _step(state, cmd);
        }
      }
    }
    if (frame < 0) return state[0];
    if (!full) {
      _cachedFrame = frame - 1;
      _cachedLife = state[0];
      _cachedGuard = state[1];
      _cachedReduction = state[2];
    }
    if (frame >= _maxFrame) return state[0];
    final cmds = _commands[frame];
    if (cmds != null) {
      for (final cmd in cmds) {
        if (cmd.timeMs > ms) break;
        _step(state, cmd);
      }
    }
    return state[0];
  }

  void syncCurrent(int t) => currentLife = lifeAt(t);
}
