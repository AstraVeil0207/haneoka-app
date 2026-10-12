/// Exact normal-live scores for one team over all 120 member orders
/// (`team-builder/engine/live.ts` and `order-equivalence.ts`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'chart.dart';
import 'master.dart';
import 'num.dart';
import 'skills.dart';

/// Every skill order: `ORDERS[i][event]` is the formation slot firing at that event.
final List<List<int>> orders = () {
  final out = <List<int>>[];
  void visit(List<int> chosen) {
    if (chosen.length == 5) {
      out.add(chosen);
    } else {
      for (var slot = 0; slot < 5; slot++) {
        if (!chosen.contains(slot)) visit([...chosen, slot]);
      }
    }
  }

  visit([]);
  return out;
}();

class SkillOrderPlan {
  SkillOrderPlan(this.representatives, this.sources);

  /// First original order index for each distinct sequence of resolved skills.
  final List<int> representatives;

  /// Each original order's representative.
  final Uint8List sources;
}

final fullSkillOrderPlan = SkillOrderPlan([
  for (var i = 0; i < 120; i++) i,
], Uint8List.fromList([for (var i = 0; i < 120; i++) i]));

bool _equalNumbers(List<num> a, List<num> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _equalEffect(LiveEffect a, LiveEffect b) =>
    identical(a, b) ||
    (a.type == b.type &&
        a.delta == b.delta &&
        a.seconds == b.seconds &&
        a.gate.kind == b.gate.kind &&
        (a.gate.kind != GateKind.lifeAtLeast ||
            (a.gate.value == b.gate.value &&
                a.gate.positive == b.gate.positive)) &&
        _equalNumbers(a.judgements, b.judgements));

bool _equalSkill(SlotSkill? a, SlotSkill? b) {
  if (identical(a, b)) return true;
  if (a == null ||
      b == null ||
      a.extensionMs != b.extensionMs ||
      a.recovery != b.recovery) {
    return false;
  }
  if (!identical(a.convert, b.convert)) {
    if (a.convert == null ||
        b.convert == null ||
        a.convert!.limit != b.convert!.limit ||
        !_equalNumbers(a.convert!.judgements, b.convert!.judgements)) {
      return false;
    }
  }
  if (a.effects.length != b.effects.length) return false;
  for (var i = 0; i < a.effects.length; i++) {
    if (!_equalEffect(a.effects[i], b.effects[i])) return false;
  }
  return true;
}

final _plans = <int, SkillOrderPlan>{};

SkillOrderPlan skillOrderPlan(List<SlotSkill?> slots) {
  final groups = <int>[];
  var classes = 0;
  var key = 0;
  for (var slot = 0; slot < 5; slot++) {
    var previous = 0;
    while (previous < slot &&
        !_equalSkill(
          slots.elementAtOrNull(slot),
          slots.elementAtOrNull(previous),
        )) {
      previous++;
    }
    final group = previous == slot ? classes++ : groups[previous];
    groups.add(group);
    key = key * 5 + group;
  }
  if (classes == 5) return fullSkillOrderPlan;
  final cached = _plans[key];
  if (cached != null) return cached;
  final representatives = <int>[];
  final sources = Uint8List(orders.length);
  final first = <int, int>{};
  for (final (index, order) in orders.indexed) {
    var sequence = 0;
    for (final slot in order) {
      sequence = sequence * 5 + groups[slot];
    }
    var representative = first[sequence];
    if (representative == null) {
      representative = index;
      first[sequence] = index;
      representatives.add(index);
    }
    sources[index] = representative;
  }
  return _plans[key] = SkillOrderPlan(representatives, sources);
}

void restoreOrderScores(Float64List scores, SkillOrderPlan plan) {
  if (identical(plan, fullSkillOrderPlan)) return;
  for (var index = 0; index < scores.length; index++) {
    scores[index] = scores[plan.sources[index]];
  }
}

/// Simulate judgements: 6 Just, 5 Perfect, 4 Great, 3 Good, 2 Bad, 1 Miss.
class PlayModel {
  const PlayModel({
    this.great = 0,
    this.good = 0,
    this.bad = 0,
    this.miss = 0,
    this.missEvery = 0,
  });
  factory PlayModel.fromJson(Map<String, Object?> json) => PlayModel(
    great: numOf(json['great']),
    good: numOf(json['good']),
    bad: numOf(json['bad']),
    miss: numOf(json['miss']),
    missEvery: numOf(json['missEvery']),
  );
  final double great;
  final double good;
  final double bad;
  final double miss;

  /// Every Nth judged note (1-based, chart order) is a Miss. 0: none.
  final double missEvery;

  bool get isAllPerfect =>
      great == 0 && good == 0 && bad == 0 && miss == 0 && !(missEvery > 0);

  Map<String, Object?> toJson() => {
    'great': great,
    'good': good,
    'bad': bad,
    'miss': miss,
    if (missEvery > 0) 'missEvery': missEvery,
  };
  String get signature => '$great,$good,$bad,$miss,$missEvery';
}

const ap = PlayModel();

/// Picks [count] of [n] positions evenly (the native accuracy builder's spread).
void _chooseEvenly(int n, int count, void Function(int i) select) {
  var remainder = 0;
  for (var i = 0; i < n; i++) {
    remainder += count;
    if (remainder >= n) {
      remainder -= n;
      select(i);
    }
  }
}

/// Judgements of a stated play in chart order, built like the native
/// accuracy builder.
Int8List playJudgements(int count, PlayModel play) {
  final out = Int8List(count)..fillRange(0, count, 5);
  double clamp(double x) => math.max(0, math.min(1, x));
  _chooseEvenly(count, jsRound(clamp(play.great) * count), (i) => out[i] = 4);
  for (final (judgement, fraction) in [
    (3, play.good),
    (2, play.bad),
    (1, play.miss),
  ]) {
    final wanted = jsRound(clamp(fraction) * count);
    if (wanted == 0) continue;
    final open = [
      for (var i = 0; i < count; i++)
        if (out[i] == 5) i,
    ];
    _chooseEvenly(
      open.length,
      math.min(wanted, open.length),
      (k) => out[open[k]] = judgement,
    );
  }
  final every = play.missEvery.floor();
  if (every > 0) {
    for (var i = every - 1; i < count; i += every) {
      out[i] = 1;
    }
  }
  return out;
}

const _fpsLife = 60;

class LiveSettings {
  const LiveSettings({this.assist = 1, this.luckPercent = 100});

  /// 1 normally; assist mode multiplies by its percent.
  final double assist;
  final double luckPercent;
  String get signature => '$assist,$luckPercent';
}

const normalSettings = LiveSettings();

class PreparedLive {
  PreparedLive(
    this.chart,
    this.master,
    this.apCombo,
    this.comboTable,
    this.judgeFrac,
  );
  final CompiledChart chart;
  final EngineMaster master;

  /// Combo factor of each note in an unbroken play.
  final Float32List apCombo;
  final List<(int, double)> comboTable;
  final Float32List judgeFrac;

  final _lives = Expando<Map<String, OrderLives>>();
}

double comboFactorAt(List<(int, double)> table, int combo) {
  var value = 0.0;
  for (final (required, cumulative) in table) {
    if (required > combo) break;
    value = cumulative;
  }
  return f(math.min(value, 1) + 1);
}

PreparedLive prepareLive(EngineMaster master, CompiledChart chart) {
  final table = master.live.combo[0] ?? const <(int, double)>[];
  final apCombo = Float32List(chart.count);
  var before = 0;
  for (var i = 0; i < chart.count; i++) {
    if (i > 0 && chart.times[i] != chart.times[i - 1]) before = i;
    apCombo[i] = comboFactorAt(table, before);
  }
  final judgeFrac = Float32List(7);
  for (var type = 1; type <= 6; type++) {
    judgeFrac[7 - type] = f((master.live.judgePercent[type] ?? 0) / 100);
  }
  return PreparedLive(chart, master, apCombo, table, judgeFrac);
}

class OrderScores {
  OrderScores(
    this.power,
    this.scores,
    this.mean,
    this.min,
    this.max,
    this.minOrder,
    this.maxOrder,
  );
  final int power;
  final Float64List scores;
  final double mean;
  final double min;
  final double max;
  final int minOrder;
  final int maxOrder;
}

class _Command {
  _Command(this.time, this.owner, this.channel, this.delta);
  final int time;
  final int owner;

  /// 0 general, 4 Great, 5 Perfect, 6 Just.
  final int channel;
  final int delta;
}

List<_Command> _orderCommands(
  PreparedLive prepared,
  List<SlotSkill> slots,
  List<int> order,
  double lifeBase,
) {
  final chart = prepared.chart;
  final commands = <_Command>[];
  final events = math.min(chart.skillTimes.length, 5);
  for (var event = 0; event < events; event++) {
    final slot = slots.elementAtOrNull(order[event]);
    if (slot == null) continue;
    final start = chart.skillTimes[event];
    for (final effect in slot.effects) {
      if (effect.gate.blocks(lifeBase)) continue;
      final end = start + windowMs(effect.seconds, slot.extensionMs);
      for (final channel
          in effect.type == 2000 ? const [0] : effect.judgements) {
        commands
          ..add(_Command(start, event, channel, effect.delta))
          ..add(_Command(end, event, channel, -effect.delta));
      }
    }
  }
  return _stable(commands, (a, b) {
    final d = a.time - b.time;
    return d != 0 ? d : a.owner - b.owner;
  });
}

/// A stable sort (`Array.prototype.sort` is stable).
List<T> _stable<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (final (i, v) in list.indexed) (i, v)];
  indexed.sort((a, b) {
    final d = compare(a.$2, b.$2);
    return d != 0 ? d : a.$1 - b.$1;
  });
  return [for (final (_, v) in indexed) v];
}

int _lower(Int32List times, int n, int time) {
  var low = 0, high = n;
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

/// Exact all-Perfect scores: note scores at a constant factor are cached as prefix sums.
OrderScores scoreOrdersAP(
  PreparedLive prepared,
  int power,
  List<SlotSkill> slots, [
  LiveSettings settings = normalSettings,
]) {
  final chart = prepared.chart;
  final master = prepared.master;
  final n = chart.count;
  final t = f(f(master.live.adjustment * power) * chart.difficultyFactor);
  final perfect = prepared.judgeFrac[5];
  final base = Float32List(n);
  for (var i = 0; i < n; i++) {
    base[i] = f(f(perfect * f(chart.noteFrac[i] * t)) * prepared.apCombo[i]);
  }
  final count = chart.convertedCount;
  final luck = f(math.min(settings.luckPercent, 200) / 100);
  final assist = f(settings.assist);
  final prefixes = <double, Float64List>{};
  Float64List prefix(double factor) => prefixes[factor] ??= () {
    final sums = Float64List(n + 1);
    var total = 0.0;
    for (var i = 0; i < n; i++) {
      var x = f(f(luck * f(base[i] * factor)) / count).floorToDouble();
      if (assist != 1) x = f(assist * x).floorToDouble();
      total += x;
      sums[i + 1] = total;
    }
    return sums;
  }();
  final scores = Float64List(orders.length);
  final times = chart.times;
  final plan = skillOrderPlan(slots);
  for (final orderIndex in plan.representatives) {
    final commands = _orderCommands(
      prepared,
      slots,
      orders[orderIndex],
      master.live.lifeBase,
    );
    var general = f(1), perfectUp = f(0);
    var index = 0;
    var score = 0.0;
    for (final command in commands) {
      final end = _lower(times, n, command.time);
      if (end > index) {
        final sums = prefix(f(general + perfectUp));
        score += sums[end] - sums[index];
        index = end;
      }
      final diff = f(command.delta / 100000);
      if (command.channel == 0) {
        general = f(general + diff);
      } else if (command.channel == 5) {
        perfectUp = f(perfectUp + diff);
      }
    }
    if (index < n) {
      final sums = prefix(f(general + perfectUp));
      score += sums[n] - sums[index];
    }
    scores[orderIndex] = score;
  }
  restoreOrderScores(scores, plan);
  return _summarize(power, scores);
}

OrderScores _summarize(int power, Float64List scores) {
  var min = inf, max = -inf;
  var minOrder = 0, maxOrder = 0;
  // Canonical summation keeps permuted equal teams exactly tied.
  final sorted = Float64List.fromList(scores)..sort();
  var total = 0.0;
  for (final value in sorted) {
    total += value;
  }
  for (var index = 0; index < scores.length; index++) {
    final value = scores[index];
    if (value < min) {
      min = value;
      minOrder = index;
    }
    if (value > max) {
      max = value;
      maxOrder = index;
    }
  }
  return OrderScores(
    power,
    scores,
    total / scores.length,
    min,
    max,
    minOrder,
    maxOrder,
  );
}

class OrderLives {
  OrderLives(this.note, this.gate);

  /// The life note i is scored with (after its own damage).
  final Float64List note;

  /// The life a life condition of each skill event reads.
  final Map<int, double> gate;
}

/// The gauge of one order under a play, exactly as the live simulation sees it.
OrderLives orderLives(
  PreparedLive prepared,
  Int8List judgements,
  List<SlotSkill?> slots,
  List<int> order,
) {
  final recoveries = [
    for (var event = 0; event < 5; event++)
      slots.elementAtOrNull(order[event])?.recovery ?? 0,
  ];
  final byPlay = prepared._lives[judgements] ??= {};
  return byPlay[recoveries.join(',')] ??= _computeLives(
    prepared,
    judgements,
    recoveries,
  );
}

class _Pending {
  _Pending(this.time, this.frame, this.amount);
  final int time;
  final int frame;
  final int amount;
}

OrderLives _computeLives(
  PreparedLive prepared,
  Int8List judgements,
  List<int> recoveries,
) {
  final chart = prepared.chart;
  final master = prepared.master;
  final n = chart.count;
  final damage = master.live.damage;
  final firing = [
    for (final event in chart.skillOrder)
      if (event < 5) event,
  ];
  final overHealCap = master.live.lifeBase * 2;
  final note = Float64List(n);
  final gate = <int, double>{};
  var life = master.live.lifeBase;
  // Recoveries are filed at their skill's time after that frame's notes were
  // scored: later frames read the gauge replayed in time order.
  final pending = <_Pending>[];
  var processed = 0;
  void settle(int noteTime) {
    for (var r = 0; r < pending.length;) {
      final rec = pending[r];
      if (rec.frame >= noteTime) {
        r++;
        continue;
      }
      pending.removeAt(r);
      var from = processed;
      while (from > 0 && chart.times[from - 1] > rec.time) {
        from--;
      }
      var value = from > 0 ? note[from - 1] : master.live.lifeBase;
      if (value > 0) value = math.min(overHealCap, value + rec.amount);
      for (var j = from; j < processed; j++) {
        final d = damage[judgements[j]];
        if (d != 0) value = math.max(0, value - d);
        note[j] = value;
      }
      life = value;
    }
  }

  var cursor = 0;
  for (var i = 0; i <= n; i++) {
    final time = i < n ? chart.times[i] : 1 << 53;
    while (cursor < firing.length && chart.skillTimes[firing[cursor]] <= time) {
      final event = firing[cursor];
      final start = chart.skillTimes[event];
      final recovery = recoveries.elementAtOrNull(event) ?? 0;
      // Phase 1 files the recovery before the phase-2 score-ups check their
      // life condition in the same frame.
      if (recovery != 0) {
        pending.add(_Pending(start, frameTime(start), recovery));
      }
      final frame = frameTime(start);
      settle(frame);
      final due = _stable([
        for (final rec in pending)
          if (rec.frame <= frame) rec,
      ], (a, b) => a.time - b.time);
      var gateLife = life;
      var r = 0;
      for (var j = i; j < n && chart.times[j] <= frame; j++) {
        for (; r < due.length && due[r].time < chart.times[j]; r++) {
          if (gateLife > 0) {
            gateLife = math.min(overHealCap, gateLife + due[r].amount);
          }
        }
        final d = damage[judgements[j]];
        if (d != 0) gateLife = math.max(0, gateLife - d);
      }
      for (; r < due.length; r++) {
        if (gateLife > 0) {
          gateLife = math.min(overHealCap, gateLife + due[r].amount);
        }
      }
      gate[event] = gateLife;
      cursor++;
    }
    if (i == n) break;
    settle(time);
    // The note's own damage lands before its score reads the gauge.
    final d = damage[judgements[i]];
    if (d != 0) life = math.max(0, life - d);
    note[i] = life;
    processed = i + 1;
  }
  return OrderLives(note, gate);
}

/// The 60 fps frame a time is processed in: the first frame time at or after it.
int frameTime(int time) {
  var k = math.max(0, (time * _fpsLife / 1000).ceil() - 1);
  while ((k * 1000 / _fpsLife).floor() < time) {
    k++;
  }
  return (k * 1000 / _fpsLife).floor();
}

class _Active {
  _Active(this.end, this.channel, this.delta);
  final int end;
  final int channel;
  final int delta;
}

class _Conversion {
  _Conversion(this.from, this.until, this.judgements, this.left);
  final int from;
  final int until;
  final List<int> judgements;
  double left;
}

/// General play: combo breaks, life, Great→Perfect conversion and
/// life-gated skills, per order.
OrderScores scoreOrdersPlay(
  PreparedLive prepared,
  int power,
  List<SlotSkill> slots,
  Int8List judgements, [
  LiveSettings settings = normalSettings,
]) {
  final chart = prepared.chart;
  final master = prepared.master;
  final n = chart.count;
  final t = f(f(master.live.adjustment * power) * chart.difficultyFactor);
  final count = chart.convertedCount;
  final luck = f(math.min(settings.luckPercent, 200) / 100);
  final assist = f(settings.assist);
  final onus = master.live.lifeOnus;
  final damage = master.live.damage;
  final firing = [
    for (final event in chart.skillOrder)
      if (event < 5) event,
  ];
  final scores = Float64List(orders.length);
  final noteA = Float32List(n);
  for (var i = 0; i < n; i++) {
    noteA[i] = f(chart.noteFrac[i] * t);
  }
  // Bad and Miss alone break combos, so the combo of each note is fixed by the pattern.
  final comboFactors = Float32List(n);
  {
    var pending = 0, combo = 0, last = -1;
    for (var i = 0; i < n; i++) {
      if (chart.times[i] != last) {
        combo = pending;
        last = chart.times[i];
      }
      comboFactors[i] = comboFactorAt(prepared.comboTable, combo);
      pending = judgements[i] <= 2 ? 0 : pending + 1;
    }
  }
  final convertsBreaks = slots.any(
    (slot) => slot.convert?.judgements.any((j) => j <= 2) ?? false,
  );
  if (convertsBreaks || damage[3] != 0 || damage[4] != 0) {
    throw StateError('conversions that change damage need the full simulation');
  }
  final plan = skillOrderPlan(slots);
  for (final orderIndex in plan.representatives) {
    final order = orders[orderIndex];
    final lives = orderLives(prepared, judgements, slots, order);
    var pendingCombo = 0;
    final channel = Float32List(7);
    final active = <_Active>[];
    var factor = f(1);
    var cursor = 0;
    // Registered conversions, most recent first.
    final converts = <_Conversion>[];
    var score = 0.0;
    void expire(int time) {
      for (var i = active.length - 1; i >= 0; i--) {
        if (active[i].end <= time) {
          final diff = f(active[i].delta / 100000);
          final which = active[i].channel;
          if (which == 0) {
            factor = f(factor - diff);
          } else {
            channel[which] = f(channel[which] - diff);
          }
          active.removeAt(i);
        }
      }
    }

    for (var i = 0; i <= n; i++) {
      final time = i < n ? chart.times[i] : 1 << 53;
      while (cursor < firing.length &&
          chart.skillTimes[firing[cursor]] <= time) {
        final event = firing[cursor];
        final start = chart.skillTimes[event];
        expire(start);
        final slot = slots.elementAtOrNull(order[event]);
        if (slot != null) {
          final gateLife = lives.gate[event]!;
          for (final effect in slot.effects) {
            if (effect.gate.blocks(gateLife)) continue;
            final end = start + windowMs(effect.seconds, slot.extensionMs);
            final diff = f(effect.delta / 100000);
            for (final which
                in effect.type == 2000 ? const [0] : effect.judgements) {
              if (which == 0) {
                factor = f(factor + diff);
              } else {
                channel[which] = f(channel[which] + diff);
              }
              active.add(_Active(end, which, effect.delta));
            }
          }
          final convert = slot.convert;
          if (convert != null) {
            converts.insert(
              0,
              _Conversion(
                frameTime(start),
                frameTime(
                  start +
                      windowMs(
                        slot.effects.firstOrNull?.seconds ?? 5,
                        slot.extensionMs,
                      ),
                ),
                convert.judgements,
                convert.limit,
              ),
            );
          }
        }
        cursor++;
      }
      if (i == n) break;
      expire(time);
      var judgement = judgements[i];
      for (var c = 0; c < converts.length; c++) {
        final conv = converts[c];
        if (conv.until < time) {
          converts.removeAt(c--);
          continue;
        }
        if (time <= conv.from || !conv.judgements.contains(judgement)) continue;
        judgement = 5;
        if (--conv.left <= 0) converts.removeAt(c);
        break;
      }
      final judge = prepared.judgeFrac[judgement];
      final comboFactor = comboFactors[i];
      final up = f(factor + channel[judgement]);
      final life = lives.note[i];
      var x = f(f(luck * f(f(f(judge * noteA[i]) * comboFactor) * up)) / count)
          .floorToDouble();
      if (life <= 0) x = f(onus * x).floorToDouble();
      if (assist != 1) x = f(assist * x).floorToDouble();
      score += x;
      pendingCombo = judgement <= 2 ? 0 : pendingCombo + 1;
    }
    scores[orderIndex] = score;
  }
  restoreOrderScores(scores, plan);
  return _summarize(power, scores);
}

/// Skip score: valid notes as Great, combo 0, full life, no skills.
int skipScore(EngineMaster master, CompiledChart chart, int power) {
  final t = f(f(master.live.adjustment * power) * chart.difficultyFactor);
  final great = f((master.live.judgePercent[3] ?? 80) / 100);
  final combo = comboFactorAt(master.live.combo[0] ?? const [], 0);
  var total = 0;
  for (final frac in chart.skipNoteFrac) {
    total += f(f(f(great * f(frac * t)) * combo) / chart.convertedCount)
        .floor();
  }
  return total;
}
