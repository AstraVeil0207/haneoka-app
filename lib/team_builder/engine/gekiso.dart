/// Gekisou (fever mission) lives (`engine/gekiso.ts`): the
/// order-independent part of a team's live (Gekisou combo, Gekisou skills,
/// Gekisou support skills, the luck lottery, Just judgements) comes from
/// one whole-live simulation without live skills; the 120 member orders
/// then add live skills and snap skills note by note, with the solo rank
/// bonus of each completed range.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../chart/runtime_chart.dart' show RuntimeChart;
import 'full/conditions.dart';
import 'full/core.dart';
import 'full/gekisou.dart' show missionLuck, missionPattern, rankingFactors;
import 'full/luck.dart';
import 'full/model.dart';
import 'full/play.dart';
import 'full/score.dart' show noteFactorMill;
import 'live.dart';
import 'master.dart';
import 'num.dart';
import 'skills.dart';

class GekisoChart {
  GekisoChart({
    required this.full,
    required this.setup,
    required this.play,
    required this.accuracy,
    required this.notes,
    required this.times,
    required this.noteFrac,
    required this.judgements,
    required this.rangeOf,
    required this.rangePercent,
    required this.luck,
    required this.difficultyFactor,
    required this.musicLengthMs,
    required this.comboFactor,
    required this.judgeFrac,
    required this.span,
  });
  final FullChart full;
  final GekisouSetup setup;
  final LivePlay play;
  final Accuracy accuracy;

  /// Judged notes in (time, id) order.
  final List<LiveNote> notes;
  final Int32List times;
  final Float32List noteFrac;

  /// Play judgement of each note before conversions (6 Just … 1 Miss).
  final Int8List judgements;

  /// Range of each note's rank bonus (-1 none) and each range's bonus percent.
  final Int8List rangeOf;
  final List<int> rangePercent;
  final bool luck;
  final double difficultyFactor;
  final int musicLengthMs;

  /// Combo factor `min(table, 1) + 1` per note of the play.
  final Float32List comboFactor;
  final Float32List judgeFrac;

  /// Frame indices [first, end) spanning every range from standby to finish.
  final (int, int) span;

  final _luckCurves = <String, _RecordedLuck>{};
  List<PlayFrame>? _simulatedFrames;

  /// Per-isolate caches of the Gekisou search on this chart: contexts by
  /// level tag and lottery seeds, then deck; and its seeding phase.
  final contexts = <String, Map<String, GekisoContext>>{};
  int contextBytes = 0;
  final performerIds = <String, int>{};
  final performerJson = <String>[];
  final seeded = <String, Object>{};
}

/// [rank] is the assumed placement in every range (1 for solo Mission lives).
GekisoChart gekisoChart(
  EngineMaster master,
  RuntimeChart source,
  num level,
  List<int> missions,
  Accuracy accuracy, [
  int rank = 1,
]) {
  final full = fullChart(master, source, level);
  final setup = GekisouSetup(full.fevers, missions);
  final play = judgementStream(master, full, setup, accuracy);
  final judgementOf = <int, int>{};
  for (final frame in play.frames) {
    for (final j in frame.judged) {
      judgementOf[j.noteId] = j.judgement;
    }
  }
  final notes = [
    for (final n in full.notes)
      if (isJudgementNote(n.op) && master.live.notePercent.containsKey(n.op)) n,
  ]..sort((a, b) => a.timeMs != b.timeMs ? a.timeMs - b.timeMs : a.id - b.id);
  final n = notes.length;
  final times = Int32List.fromList([for (final note in notes) note.timeMs]);
  final noteFrac = Float32List.fromList([
    for (final note in notes) f((master.live.notePercent[note.op] ?? 0) / 100),
  ]);
  final judgements = Int8List.fromList([
    for (final note in notes) judgementOf[note.id] ?? 5,
  ]);
  int mission(int i) => i < missions.length ? missions[i] : 0;
  final factors = rankingFactors(
    master.live.gekiso,
    missionPattern(mission(0), mission(1), mission(2)),
  );
  final ranges = full.fevers.take(3).toList();
  final rangePercent = [
    for (var r = 0; r < ranges.length; r++)
      rank - 1 >= 0 && rank - 1 < factors[r].length ? factors[r][rank - 1] : 0,
  ];
  final rangeOf = Int8List(n)..fillRange(0, n, -1);
  for (final (i, note) in notes.indexed) {
    final frame = getFrame(note.timeMs);
    for (final (r, (s, e)) in ranges.indexed) {
      if (getFrame(s) < frame && frame <= getFrame(e) && rangeOf[i] == -1) {
        rangeOf[i] = r;
      }
    }
  }
  final table = master.live.combo[0] ?? const <(int, double)>[];
  final comboFactor = Float32List(n);
  {
    // The combo counter orders judgements by time; Bad and Miss reset it.
    var before = 0, pending = 0, last = -1;
    for (var i = 0; i < n; i++) {
      if (times[i] != last) {
        before = pending;
        last = times[i];
      }
      var value = 0.0;
      for (final (required, cumulative) in table) {
        if (required > before) break;
        value = cumulative;
      }
      comboFactor[i] = f(math.min(value, 1) + 1);
      pending = judgements[i] <= 2 ? 0 : pending + 1;
    }
  }
  final judgeFrac = Float32List(7);
  for (var type = 1; type <= 6; type++) {
    judgeFrac[7 - type] = f((master.live.judgePercent[type] ?? 0) / 100);
  }
  final frameTimes = [for (final frame in play.frames) frame.timeMs];
  var span = (0, 0);
  if (ranges.isNotEmpty) {
    final firstStart = ranges.map((r) => r.$1).reduce(math.min);
    final lastEnd = ranges.map((r) => r.$2).reduce(math.max);
    final at = frameTimes.indexWhere(
      (time) => time >= lastEnd + master.live.afterMs + 1200,
    );
    span = (
      math.max(
        0,
        frameTimes.indexWhere((time) => time >= firstStart - 4500) - 1,
      ),
      at < 0 ? frameTimes.length : at,
    );
  }
  return GekisoChart(
    full: full,
    setup: setup,
    play: play,
    accuracy: accuracy,
    notes: notes,
    times: times,
    noteFrac: noteFrac,
    judgements: judgements,
    rangeOf: rangeOf,
    rangePercent: rangePercent,
    luck: missions.take(ranges.length).contains(missionLuck),
    difficultyFactor: f(f(f(i32(level - 5)) * f(0.005)) + 1),
    musicLengthMs: full.lastTimingMs + 1000,
    comboFactor: comboFactor,
    judgeFrac: judgeFrac,
    span: span,
  );
}

class GekisoContext {
  GekisoContext(
    this.judgement,
    this.gk,
    this.up,
    this.luck,
    this.seeds, {
    this.draws,
    this.nominal,
  });
  final Iterable<GekisoContext> Function()? draws;
  final GekisoNominal? nominal;

  /// Simulate judgement of each note after Gekisou conversions.
  final Int8List judgement;

  /// Gekisou combo factor.
  final Float32List gk;

  /// Expected luck factor × order-independent note score-up.
  final Float64List up;

  /// Expected luck factor.
  final Float64List luck;

  /// Lottery runs averaged: 1 deterministic, 0 the exact nominal expectation.
  final int seeds;
}

class GekisoNominal {
  GekisoNominal(
    this.probabilities,
    this.noteUp,
    this.rushUp,
    this.rushFactor,
    this.rankRemainder,
  );
  final List<Float64List> probabilities;
  final Float32List noteUp;
  final double rushUp;
  final double rushFactor;
  final double Function(
    int range,
    Float64List outcomes,
    Map<String, double> cache,
  )
  rankRemainder;
}

class _RecordedLuck {
  _RecordedLuck(this.curve, this.record, this.frames, this.misses);
  final LuckCurve curve;
  final LuckRecord record;
  final List<PlayFrame> frames;
  final List<MissRule> misses;
}

/// Rush-reading score-ups (sum of their factors) and Miss-triggered gauge
/// additions of a deck's support skills.
({double rush, List<MissRule> misses}) _luckReaders(
  EngineMaster master,
  List<Performer> deck,
) {
  final lifeBase = master.live.lifeBase.toInt();
  final factory = ConditionFactory(master, deck, lifeBase, 0);
  final ctx = CheckCtx(
    prevConfirmedRank: null,
    life: LifeController(lifeBase, master.live.damage, 1000),
    random: LiveRandom(0),
    frameTime: 0,
    currentCombo: 0,
    judged: [],
    events: [],
    gk: null,
    record: true,
  );
  bool reads(int group, int type, [double? value]) =>
      (master.conditionSets[group] ?? const <List<int>>[]).any(
        (set) => set.any((id) {
          final c = master.conditions[id];
          return c?.type == type &&
              (value == null || c!.values.firstOrNull == value);
        }),
      );
  var rush = 0.0;
  final misses = <MissRule>[];
  for (final (k, p) in deck.indexed) {
    if (p.gekisouSkill == null && (p.missionOnly ?? 0) == 0) continue;
    for (final (id, level) in p.gekisouSupportSkills) {
      final skill = master.gekisoSupportSkills[id];
      if (skill == null ||
          (skill.missionType != missionLuck && skill.missionType != 4)) {
        continue;
      }
      for (final row in skill.effects) {
        if (row.level != level) continue;
        if (row.type == 2000 && reads(row.triggerGroup, 7021)) {
          if (chanceOf(factory.group(row.conditionGroup, k), ctx) > 0.5) {
            rush = f(
              rush + f(noteFactorMill(f(f(row.value) / 10000)) / 100000),
            );
          }
        } else if (row.type == 11003 && reads(row.triggerGroup, 7000, 0)) {
          final chance = chanceOf(factory.group(row.conditionGroup, k), ctx);
          if (chance > 0) misses.add(MissRule(row.value, chance));
        }
      }
    }
  }
  return (rush: rush, misses: misses);
}

LiveParams _params(GekisoChart chart) => LiveParams(
  skillTargetMusicType: 0,
  power: 1,
  level: chart.full.level,
  convertedCount: chart.full.convertedCount,
  musicLengthMs: chart.musicLengthMs,
);

GekisoContext gekisoContext(
  EngineMaster master,
  GekisoChart chart,
  List<Performer> deck,
  List<int> seeds,
) {
  if (chart.luck && seeds.isEmpty) return _expectedContext(master, chart, deck);
  final n = chart.notes.length;
  final index = {for (final (i, note) in chart.notes.indexed) note.id: i};
  final judgement = Int8List.fromList(chart.judgements);
  final gk = Float32List(n)..fillRange(0, n, 1);
  final up = Float64List(n);
  final luck = Float64List(n);
  final runs = chart.luck ? seeds : [seeds.firstOrNull ?? 0];
  final reduced = [for (final p in deck) p.gekisoOnly];
  for (final seed in runs) {
    final model = LiveModel(
      master,
      reduced,
      chart.full.notes,
      chart.full.events,
      _params(chart),
      chart.setup,
      seed: seed,
    );
    final noteUp = Float32List(n)..fillRange(0, n, 1);
    final noteLuck = Float32List(n)..fillRange(0, n, 1);
    model.score.calc.onNote = (id, scoreType, note, factor, luckFactor, _) {
      final i = index[id];
      if (i == null) return;
      judgement[i] = 7 - scoreType;
      gk[i] = factor;
      noteUp[i] = note;
      noteLuck[i] = luckFactor;
    };
    final frames = chart.play.frames;
    // Outside the ranges no Gekisou state or factor exists: only that span
    // is simulated.
    for (var k = chart.span.$1; k < chart.span.$2; k++) {
      model.frame(frames[k].timeMs, frames[k].judged, chart.play.dt[k]);
    }
    for (var i = 0; i < n; i++) {
      up[i] += noteLuck[i] * noteUp[i];
      luck[i] += noteLuck[i];
    }
  }
  for (var i = 0; i < n; i++) {
    up[i] /= runs.length;
    luck[i] /= runs.length;
  }
  return GekisoContext(
    judgement,
    gk,
    up,
    luck,
    runs.length,
    draws: runs.length > 1
        ? () sync* {
            for (final seed in runs) {
              yield gekisoContext(master, chart, deck, [seed]);
            }
          }
        : null,
  );
}

/// The exact nominal luck expectation: one lottery-free run records the
/// live, the luck DP propagates the lottery.
GekisoContext _expectedContext(
  EngineMaster master,
  GekisoChart chart,
  List<Performer> deck,
) {
  final n = chart.notes.length;
  final index = {for (final (i, note) in chart.notes.indexed) note.id: i};
  final judgement = Int8List.fromList(chart.judgements);
  final gk = Float32List(n)..fillRange(0, n, 1);
  final noteUp = Float32List(n)..fillRange(0, n, 1);
  final reduced = [for (final p in deck) p.gekisoOnly];
  final record = LuckRecord();
  final model = LiveModel(
    master,
    reduced,
    chart.full.notes,
    chart.full.events,
    _params(chart),
    chart.setup,
    record: record,
  );
  model.score.calc.onNote = (id, scoreType, note, factor, _, _) {
    final i = index[id];
    if (i == null) return;
    judgement[i] = 7 - scoreType;
    gk[i] = factor;
    noteUp[i] = note;
  };
  // The record is indexed from the first simulated frame.
  final simulated = chart._simulatedFrames ??= chart.play.frames.sublist(
    chart.span.$1,
    chart.span.$2,
  );
  for (var k = 0; k < simulated.length; k++) {
    model.frame(
      simulated[k].timeMs,
      simulated[k].judged,
      chart.play.dt[chart.span.$1 + k],
    );
  }
  final readers = _luckReaders(master, reduced);
  final luckRanges = [
    for (final (r, m)
        in chart.setup.missions
            .take(math.min(3, chart.full.fevers.length))
            .indexed)
      if (m == missionLuck) r,
  ];
  // Teams with the same actions, gauge speeds and Miss rules share one curve.
  final signature = [
    for (final a in record.actions)
      '${a.frame},${a.range},${a.type},${a.value},${a.limit},${a.chance}',
    '|',
    for (final m in readers.misses) '${m.value},${m.chance}',
    '|',
    for (final note in record.notes)
      '${note.frame},${note.judgement},${note.speed},${note.buff}',
    '|',
    for (final frame in record.frames) '${frame.id}',
  ].join(';');
  var recorded = chart._luckCurves[signature];
  if (recorded == null && chart._luckCurves.length >= 1024) {
    chart._luckCurves.clear();
  }
  recorded ??= chart._luckCurves[signature] = _RecordedLuck(
    luckCurve(
      master.live.gekiso,
      record,
      simulated,
      luckRanges,
      readers.misses,
    ),
    record,
    simulated,
    readers.misses,
  );
  final lottery = recorded;
  final curve = lottery.curve;
  final bonus = math.min(100 + master.live.gekiso.rushPercent, 200) / 100 - 1;
  final up = Float64List(n), luck = Float64List(n);
  final probabilities = List.generate(4, (_) => Float64List(n));
  for (var i = 0; i < n; i++) {
    final id = chart.notes[i].id;
    final pr = curve.rush[id] ?? 0,
        ps = curve.skill[id] ?? 0,
        both = curve.both[id] ?? 0;
    luck[i] = 1 + bonus * pr;
    up[i] = noteUp[i] * luck[i] + readers.rush * (ps + bonus * both);
    probabilities[0][i] = math.max(0, 1 - pr - ps + both);
    probabilities[1][i] = math.max(0, pr - both);
    probabilities[2][i] = math.max(0, ps - both);
    probabilities[3][i] = math.max(0, both);
  }
  double rankRemainder(
    int range,
    Float64List outcomes,
    Map<String, double> cache,
  ) {
    final percent = chart.rangePercent[range];
    var divisor = 100, numerator = percent;
    while (numerator != 0) {
      final next = divisor.remainder(numerator);
      divisor = numerator;
      numerator = next;
    }
    final modulus = 100 ~/ divisor;
    if (modulus == 1) return 0;
    final first = lottery.record.frames.indexWhere(
      (frame) => frame.states[range] == 3,
    );
    var last = -1;
    for (var k = first + 1; k < lottery.record.frames.length; k++) {
      if (lottery.record.frames[k].states[range] == 8) {
        last = k;
        break;
      }
    }
    if (last < 0) last = lottery.record.frames.length - 1;
    final observed = {
      for (final frame in lottery.frames.sublist(first, last + 1))
        for (final note in frame.judged) note.noteId,
    };
    var initial = 0;
    final signature = <num>[range];
    for (var i = 0; i < chart.notes.length; i++) {
      if (chart.rangeOf[i] != range) continue;
      if (!observed.contains(chart.notes[i].id)) {
        initial = (initial + outcomes[4 * i].toInt()).remainder(modulus);
      }
      for (var mask = 0; mask < 4; mask++) {
        signature.add(outcomes[4 * i + mask].remainder(modulus));
      }
    }
    final key = signature.join(',');
    final known = cache[key];
    if (known != null) return known;
    final residues = Float64List(modulus);
    luckCurve(
      master.live.gekiso,
      lottery.record,
      lottery.frames,
      [range],
      lottery.misses,
      LuckSettlement(
        modulus: modulus,
        initial: initial,
        residues: residues,
        noteScore: (id, running, reading) {
          final i = index[id];
          return i != null && chart.rangeOf[i] == range
              ? outcomes[4 * i + (running ? 1 : 0) + (reading ? 2 : 0)].toInt()
              : 0;
        },
      ),
    );
    var value = 0.0;
    for (var residue = 0; residue < residues.length; residue++) {
      value += residues[residue] * (residue * percent).remainder(100) / 100;
    }
    return cache[key] = value;
  }

  return GekisoContext(
    judgement,
    gk,
    up,
    luck,
    0,
    nominal: GekisoNominal(
      probabilities,
      noteUp,
      readers.rush,
      f(1 + bonus),
      rankRemainder,
    ),
  );
}

/// A rush-reading support that leaves the lottery trajectory unchanged.
double? rushOnlyFactor(EngineMaster master, Performer performer) {
  for (final (id, level) in performer.gekisouSupportSkills) {
    final skill = master.gekisoSupportSkills[id];
    if (skill == null ||
        (skill.missionType != missionLuck && skill.missionType != 4)) {
      continue;
    }
    for (final row in skill.effects) {
      if (row.level == level && row.type != 2000) return null;
    }
  }
  final readers = _luckReaders(master, [
    performer.withMissionOnly(
      performer.missionOnly == null || performer.missionOnly == 0
          ? 1
          : performer.missionOnly,
    ),
  ]);
  return readers.misses.isNotEmpty ? null : readers.rush;
}

int settleSlack(GekisoChart chart) => [
  for (var range = 0; range < chart.rangePercent.length; range++)
    if (chart.setup.missions[range] == missionLuck) range,
].length;

class _Active {
  _Active(this.end, this.channel, this.delta);
  final int end;
  final int channel;
  final int delta;
}

/// Per-order scores: live skills and snap skills on top of the shared
/// Gekisou context, plus rank bonuses.
OrderScores scoreOrdersGekiso(
  EngineMaster master,
  GekisoChart chart,
  GekisoContext ctx,
  int power,
  List<SlotSkill> slots, {
  bool settle = true,
  void Function(int order, int note, double score, double live)? debug,
}) {
  if (ctx.draws != null) {
    final scores = Float64List(orders.length);
    for (final draw in ctx.draws!()) {
      final result = scoreOrdersGekiso(
        master,
        chart,
        draw,
        power,
        slots,
        settle: settle,
        debug: debug,
      );
      for (var order = 0; order < scores.length; order++) {
        scores[order] += result.scores[order] / ctx.seeds;
      }
    }
    return _summarizeOrders(power, scores);
  }
  if (ctx.seeds != 1 && ctx.nominal == null) {
    throw StateError(
      'Gekisou expectation requires outcome probabilities or individual draws',
    );
  }
  final n = chart.notes.length;
  final t = f(f(master.live.adjustment * power) * chart.difficultyFactor);
  final count = chart.full.convertedCount;
  final onus = master.live.lifeOnus;
  final damage = master.live.damage;
  final eventTimes = [for (final (_, time) in chart.full.events) time];
  // Events fire in time order; the chart lists them by performer position.
  final firing = [for (var i = 0; i < eventTimes.length && i < 5; i++) i]
    ..sort((a, b) {
      final d = eventTimes[a] - eventTimes[b];
      return d != 0 ? d : a - b;
    });
  final noteA = Float32List(n);
  final comboFactor = Float32List(n);
  for (var i = 0; i < n; i++) {
    noteA[i] = f(chart.noteFrac[i] * t);
    comboFactor[i] = f(ctx.gk[i] * chart.comboFactor[i]);
  }
  final nominal = ctx.nominal;
  final outcomes = nominal == null ? null : Float64List(n * 4);
  final remainders = <String, double>{};
  final ranges = chart.rangePercent.length;
  final scores = Float64List(orders.length);
  final rangeScore = Float64List(ranges);
  final plan = debug != null ? fullSkillOrderPlan : skillOrderPlan(slots);
  for (final orderIndex in plan.representatives) {
    final order = orders[orderIndex];
    var life = master.live.lifeBase;
    final channel = Float32List(7);
    final active = <_Active>[];
    var factor = f(0);
    var cursor = 0;
    int? convertEnd;
    List<int> convertJudgements = const [];
    var convertLeft = 0.0;
    var score = 0.0;
    rangeScore.fillRange(0, ranges, 0);
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
      if (convertEnd != null && convertEnd! <= time) convertEnd = null;
    }

    for (var i = 0; i <= n; i++) {
      final time = i < n ? chart.times[i] : 1 << 53;
      while (cursor < firing.length && eventTimes[firing[cursor]] <= time) {
        final event = firing[cursor];
        final start = eventTimes[event];
        expire(start);
        final slot = order[event] < slots.length ? slots[order[event]] : null;
        if (slot != null) {
          for (final effect in slot.effects) {
            if (effect.gate.blocks(life)) continue;
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
          if (slot.recovery != 0) {
            life = math.min(master.live.lifeBase, life + slot.recovery);
          }
          if (slot.convert case final convert?) {
            convertEnd =
                start +
                windowMs(
                  slot.effects.firstOrNull?.seconds ?? 5,
                  slot.extensionMs,
                );
            convertJudgements = convert.judgements;
            convertLeft = convert.limit;
          }
        }
        cursor++;
      }
      if (i == n) break;
      expire(time);
      var judgement = ctx.judgement[i];
      if (convertEnd != null &&
          convertLeft > 0 &&
          convertJudgements.contains(judgement)) {
        judgement = 5;
        convertLeft--;
      }
      final c = f(f(chart.judgeFrac[judgement] * noteA[i]) * comboFactor[i]);
      final live = f(factor + channel[judgement]);
      var x = 0.0;
      if (nominal != null && outcomes != null) {
        for (var mask = 0; mask < 4; mask++) {
          final up = f(
            f(nominal.noteUp[i] + (mask & 2 != 0 ? nominal.rushUp : 0)) + live,
          );
          var value = f(
            f(f(mask & 1 != 0 ? nominal.rushFactor : 1) * f(c * up)) / count,
          ).floorToDouble();
          if (life <= 0) value = f(onus * value).floorToDouble();
          outcomes[4 * i + mask] = value;
          x += nominal.probabilities[mask][i] * value;
        }
      } else {
        final up = f(f(ctx.up[i] / ctx.luck[i]) + live);
        x = f(f(f(ctx.luck[i]) * f(c * up)) / count).floorToDouble();
        if (life <= 0) x = f(onus * x).floorToDouble();
      }
      debug?.call(orderIndex, i, x, live);
      score += x;
      final r = chart.rangeOf[i];
      if (r >= 0) rangeScore[r] += x;
      if (damage[judgement] != 0) {
        life = math.max(0, life - damage[judgement]);
      }
    }
    for (var r = 0; r < ranges; r++) {
      if (nominal != null &&
          outcomes != null &&
          chart.setup.missions[r] == missionLuck) {
        score +=
            rangeScore[r] * chart.rangePercent[r] / 100 -
            (settle ? nominal.rankRemainder(r, outcomes, remainders) : 0);
      } else {
        score += (rangeScore[r] * chart.rangePercent[r] / 100).floorToDouble();
      }
    }
    scores[orderIndex] = score;
  }
  restoreOrderScores(scores, plan);
  return _summarizeOrders(power, scores);
}

OrderScores _summarizeOrders(int power, Float64List scores) {
  var min = inf, max = -inf;
  var minOrder = 0, maxOrder = 0;
  var total = 0.0;
  for (final value in Float64List.fromList(scores)..sort()) {
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

/// The full native live decides close, lottery-free finalists' ranking.
OrderScores fullOrdersGekiso(
  EngineMaster master,
  GekisoChart chart,
  List<Performer> deck,
  int power,
  int skillTargetMusicType,
) {
  if (chart.luck) {
    throw StateError('full Gekisou scores need a lottery-free chart');
  }
  final scores = Float64List(orders.length);
  final params = LiveParams(
    power: power,
    skillTargetMusicType: skillTargetMusicType,
    level: chart.full.level,
    convertedCount: chart.full.convertedCount,
    musicLengthMs: chart.musicLengthMs,
  );
  for (final (index, order) in orders.indexed) {
    final model = LiveModel(
      master,
      [for (final slot in order) deck[slot]],
      chart.full.notes,
      chart.full.events,
      params,
      chart.setup,
    );
    for (final (k, frame) in chart.play.frames.indexed) {
      model.frame(frame.timeMs, frame.judged, chart.play.dt[k]);
    }
    scores[index] = model.score.score.toDouble();
  }
  return _summarizeOrders(power, scores);
}
