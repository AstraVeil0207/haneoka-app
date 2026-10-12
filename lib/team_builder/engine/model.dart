/// Per-chart linear skill model and per-order play bounds
/// (`team-builder/engine/model.ts`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'chart.dart';
import 'live.dart';
import 'num.dart';
import 'skills.dart';

class LinearChart {
  LinearChart(
    this.live,
    this.prefix,
    this.perfectPrefix,
    this.total,
    this.lifeAtEvent,
    this.relativeError,
    this.absoluteError,
  );
  final PreparedLive live;

  /// Note weight per unit power, prefix-summed in chart order.
  final Float64List prefix;

  /// The same over notes whose judgement can take a Perfect raise.
  final Float64List perfectPrefix;
  final double total;

  /// Life when each skill event fires.
  final Map<int, double> lifeAtEvent;
  final double relativeError;
  final double absoluteError;
}

LinearChart linearChart(PreparedLive live) {
  final chart = live.chart;
  final master = live.master;
  final perfect = live.judgeFrac[5];
  final unit = master.live.adjustment * chart.difficultyFactor * perfect;
  final prefix = Float64List(chart.count + 1);
  var sum = 0.0;
  for (var i = 0; i < chart.count; i++) {
    sum += unit * chart.noteFrac[i] * live.apCombo[i];
    prefix[i + 1] = sum;
  }
  return LinearChart(
    live,
    prefix,
    prefix,
    sum,
    {
      for (var e = 0; e < chart.skillTimes.length; e++) e: master.live.lifeBase,
    },
    2e-6,
    chart.count + 1,
  );
}

double _comboValue(List<(int, double)> table, int combo) {
  var value = 0.0;
  for (final (required, cumulative) in table) {
    if (required > combo) break;
    value = cumulative;
  }
  return value;
}

/// Linear model of a fixed judgement pattern. The pessimistic side ignores
/// conversions and recovery; the optimistic side never loses life beyond
/// what [maxRecovery] restores and converts up to [conversions] notes.
LinearChart linearPlayChart(
  PreparedLive live,
  Int8List judgements,
  bool high, [
  int conversions = 0,
  double factorCap = 1,
  int maxRecovery = 0,
]) {
  final chart = live.chart;
  final master = live.master;
  final unit = master.live.adjustment * chart.difficultyFactor;
  final prefix = Float64List(chart.count + 1);
  final perfectPrefix = Float64List(chart.count + 1);
  final gains = <double>[];
  var sum = 0.0, perfectSum = 0.0;
  var life = master.live.lifeBase;
  var combo = 0, pending = 0, last = -1;
  final lifeAt = <int, double>{};
  var cursor = 0;
  for (var i = 0; i < chart.count; i++) {
    final time = chart.times[i];
    while (cursor < chart.skillOrder.length &&
        chart.skillTimes[chart.skillOrder[cursor]] <= time) {
      lifeAt[chart.skillOrder[cursor]] = high ? master.live.lifeBase : life;
      // Recoveries over-heal up to twice the gauge, so the bound may too.
      if (high) {
        life = math.min(2 * master.live.lifeBase, life + maxRecovery);
      }
      cursor++;
    }
    if (time != last) {
      combo = pending;
      last = time;
    }
    final judgement = judgements[i];
    final lifeFactor = life > 0 ? 1.0 : master.live.lifeOnus;
    final base =
        unit *
        chart.noteFrac[i] *
        f(math.min(_comboValue(live.comboTable, combo), 1) + 1) *
        lifeFactor;
    sum += base * live.judgeFrac[judgement];
    final convertible = judgement == 3 || judgement == 4;
    if (judgement == 5) perfectSum += base * live.judgeFrac[5];
    if (high && convertible) {
      gains.add(base * (live.judgeFrac[5] - live.judgeFrac[judgement]));
    }
    prefix[i + 1] = sum;
    perfectPrefix[i + 1] = perfectSum;
    pending = judgement <= 2 ? 0 : pending + 1;
    life = math.max(0, life - master.live.damage[judgement]);
  }
  while (cursor < chart.skillOrder.length) {
    lifeAt[chart.skillOrder[cursor++]] = high ? master.live.lifeBase : life;
  }
  if (high && conversions > 0) {
    gains.sort((a, b) => b.compareTo(a));
    sum +=
        factorCap * gains.take(conversions).fold(0.0, (total, g) => total + g);
  }
  return LinearChart(
    live,
    prefix,
    perfectPrefix,
    sum,
    lifeAt,
    2e-6,
    chart.count + 1,
  );
}

int lowerIndex(Int32List times, int time) {
  var low = 0, high = times.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (times[middle] < time) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// Weight of notes inside [start, start + length).
double windowWeight(
  Float64List prefix,
  CompiledChart chart,
  int start,
  int length,
) =>
    prefix[lowerIndex(chart.times, start + length)] -
    prefix[lowerIndex(chart.times, start)];

/// Most a slot's conversions can add at each event (per unit power), given a
/// cap on any note's total factor.
Float64List conversionWeights(
  LinearChart model,
  Int8List judgements,
  SlotSkill skill,
  double factorCap,
) {
  final out = Float64List(5);
  final convert = skill.convert;
  if (convert == null) return out;
  final chart = model.live.chart;
  final perfect = model.live.judgeFrac[5];
  final unit = model.live.master.live.adjustment * chart.difficultyFactor;
  for (var event = 0; event < math.min(chart.skillTimes.length, 5); event++) {
    final start = lowerIndex(chart.times, chart.skillTimes[event]);
    final end = lowerIndex(
      chart.times,
      chart.skillTimes[event] +
          windowMs(skill.effects.firstOrNull?.seconds ?? 5, skill.extensionMs),
    );
    final values = <double>[
      for (var i = start; i < end; i++)
        if (convert.judgements.contains(judgements[i]))
          unit * chart.noteFrac[i] * 2 * perfect,
    ]..sort((a, b) => b.compareTo(a));
    var total = 0.0;
    for (var i = 0; i < values.length && i < convert.limit; i++) {
      total += values[i];
    }
    out[event] = total * factorCap;
  }
  return out;
}

class SkillWeights {
  SkillWeights(this.mean, this.best, this.worst, this.perEvent);

  /// Mean over the five event positions.
  double mean;
  double best;
  final double worst;
  final Float64List perEvent;
}

SkillWeights skillWeights(LinearChart model, SlotSkill skill) {
  final chart = model.live.chart;
  final events = math.min(chart.skillTimes.length, 5);
  final perEvent = Float64List(5);
  for (final effect in skill.effects) {
    if (effect.type == 2004 && !effect.judgements.contains(5)) continue;
    final factor = f(effect.delta / 100000);
    final length = windowMs(effect.seconds, skill.extensionMs);
    final prefix = effect.type == 2004 ? model.perfectPrefix : model.prefix;
    for (var event = 0; event < events; event++) {
      if (effect.gate.blocks(model.lifeAtEvent[event]!)) continue;
      perEvent[event] +=
          factor * windowWeight(prefix, chart, chart.skillTimes[event], length);
    }
  }
  var total = 0.0, best = 0.0, worst = inf;
  for (var event = 0; event < 5; event++) {
    final value = perEvent[event];
    total += value;
    best = math.max(best, value);
    worst = math.min(worst, value);
  }
  return SkillWeights(total / 5, best, worst, perEvent);
}

class _Window {
  _Window(this.start, this.end, this.general, this.perfect);
  final int start;
  final int end;
  final double general;
  final double perfect;
}

class _Contribution {
  _Contribution(this.value, this.windows);
  final double value;
  final List<_Window> windows;
}

class _LifeBounds {
  _LifeBounds(this.raw, this.perfect, this.penalty);
  final Float64List raw;
  final Float64List perfect;
  final Float32List penalty;
  final contributions = <int, Expando<_Contribution>>{};
}

/// Per-order bounds of a fixed judgement pattern with the team's real life
/// trajectory; only conversions stay as slack.
class PlayBoundsChart {
  PlayBoundsChart(
    this.live,
    this.raw,
    this.perfectLow,
    this.perfectBase,
    this.judgements,
    this.total,
    this.damage,
    this.eventIndex,
    this.relativeError,
    this.absoluteError,
  );
  final PreparedLive live;
  final Float64List raw;
  final Float64List perfectLow;
  final Float64List perfectBase;
  final Int8List judgements;
  final double total;
  final List<(int, double)> damage;
  final List<int> eventIndex;
  final double relativeError;
  final double absoluteError;
  final _lifeBounds = Expando<_LifeBounds>();
}

PlayBoundsChart playBoundsChart(PreparedLive live, Int8List judgements) {
  final chart = live.chart;
  final master = live.master;
  final unit = master.live.adjustment * chart.difficultyFactor;
  final n = chart.count;
  final raw = Float64List(n + 1),
      perfectLow = Float64List(n + 1),
      perfectBase = Float64List(n);
  final damage = <(int, double)>[];
  var combo = 0, pending = 0, last = -1;
  for (var i = 0; i < n; i++) {
    final time = chart.times[i];
    if (time != last) {
      combo = pending;
      last = time;
    }
    final judgement = judgements[i];
    final base =
        unit *
        chart.noteFrac[i] *
        f(math.min(_comboValue(live.comboTable, combo), 1) + 1);
    raw[i + 1] = raw[i] + base * live.judgeFrac[judgement];
    perfectLow[i + 1] =
        perfectLow[i] + (judgement == 5 ? base * live.judgeFrac[5] : 0);
    perfectBase[i] = base * live.judgeFrac[5];
    final amount = master.live.damage[judgement];
    if (amount != 0) damage.add((i, amount));
    pending = judgement <= 2 ? 0 : pending + 1;
  }
  return PlayBoundsChart(
    live,
    raw,
    perfectLow,
    perfectBase,
    judgements,
    raw[n],
    damage,
    [for (final time in chart.skillTimes) lowerIndex(chart.times, time)],
    2e-6,
    n + 1,
  );
}

/// Lower and upper bounds of one order's score under a non-AP play.
(double, double) playOrderBounds(
  PlayBoundsChart model,
  List<SlotSkill> slots,
  List<int> order,
  int power,
) {
  final live = model.live;
  final chart = live.chart;
  final n = chart.count;
  final onus = live.master.live.lifeOnus;
  final events = math.min(chart.skillTimes.length, 5);
  final lives = orderLives(live, model.judgements, slots, order);
  var bounds = model._lifeBounds[lives];
  if (bounds == null) {
    final raw = Float64List(n + 1),
        perfect = Float64List(n + 1),
        penalty = Float32List(n);
    for (var i = 0; i < n; i++) {
      final factor = lives.note[i] > 0 ? 1.0 : onus;
      penalty[i] = factor;
      raw[i + 1] = raw[i] + factor * (model.raw[i + 1] - model.raw[i]);
      perfect[i + 1] =
          perfect[i] + factor * (model.perfectLow[i + 1] - model.perfectLow[i]);
    }
    bounds = model._lifeBounds[lives] = _LifeBounds(raw, perfect, penalty);
  }
  final b = bounds;
  _Contribution contribution(int event, SlotSkill slot) {
    final bySlot = b.contributions[event] ??= Expando<_Contribution>();
    final known = bySlot[slot];
    if (known != null) return known;
    final start = model.eventIndex[event];
    final windows = <_Window>[];
    var total = 0.0;
    for (final effect in slot.effects) {
      if (effect.gate.blocks(lives.gate[event]!)) continue;
      if (effect.type == 2004 && !effect.judgements.contains(5)) continue;
      final end = lowerIndex(
        chart.times,
        chart.skillTimes[event] + windowMs(effect.seconds, slot.extensionMs),
      );
      final factor = f(effect.delta / 100000);
      final prefix = effect.type == 2000 ? b.raw : b.perfect;
      if (end > start) total += factor * (prefix[end] - prefix[start]);
      windows.add(
        effect.type == 2000
            ? _Window(start, end, factor, 0)
            : _Window(start, end, 0, factor),
      );
    }
    return bySlot[slot] = _Contribution(total, windows);
  }

  var low = b.raw[n];
  var converting = false;
  for (var event = 0; event < events; event++) {
    final slot = slots.elementAtOrNull(order[event]);
    if (slot == null) continue;
    low += contribution(event, slot).value;
    if (slot.convert != null) converting = true;
  }
  var high = low;
  if (converting) {
    final windows = <_Window>[];
    for (var event = 0; event < events; event++) {
      final slot = slots.elementAtOrNull(order[event]);
      if (slot != null) windows.addAll(contribution(event, slot).windows);
    }
    final perfectFrac = live.judgeFrac[5];
    for (var event = 0; event < events; event++) {
      final slot = slots.elementAtOrNull(order[event]);
      final convert = slot?.convert;
      if (slot == null || convert == null) continue;
      final start = model.eventIndex[event];
      final end = lowerIndex(
        chart.times,
        chart.skillTimes[event] +
            windowMs(slot.effects.firstOrNull?.seconds ?? 5, slot.extensionMs) +
            17,
      );
      final gains = <double>[];
      for (var i = start; i < end; i++) {
        final judgement = model.judgements[i];
        if (!convert.judgements.contains(judgement)) continue;
        var general = 1.0, perfectUp = 0.0;
        for (final window in windows) {
          if (window.start <= i && i < window.end) {
            general += window.general;
            perfectUp += window.perfect;
          }
        }
        final base = model.perfectBase[i] / perfectFrac;
        gains.add(
          b.penalty[i] *
              base *
              ((perfectFrac - live.judgeFrac[judgement]) * general +
                  perfectFrac * perfectUp),
        );
      }
      gains.sort((x, y) => y.compareTo(x));
      for (var k = 0; k < gains.length && k < convert.limit; k++) {
        high += gains[k];
      }
    }
  }
  final divisor = chart.convertedCount;
  return (
    math.max(
      0,
      power * low / divisor * (1 - model.relativeError) - model.absoluteError,
    ),
    power * high / divisor * (1 + model.relativeError),
  );
}
