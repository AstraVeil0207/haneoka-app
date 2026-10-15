/// Reward-first Gekisou search (`engine/gekiso-rewards.ts`,
/// `gekiso-reward-objective.ts`, `gekiso-score-bound.ts`,
/// `gekiso-just.ts`): every sampled lottery outcome and skill order is
/// settled before the reward mean is taken, and a reward-table ceiling
/// that is safe even where luck score bounds are not proven prunes the
/// search.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'chart.dart';
import 'full/play.dart' show performer;
import 'full/score.dart' show noteFactorMill;
import 'gekiso.dart';
import 'live.dart';
import 'master.dart';
import 'num.dart';
import 'objectives.dart';
import 'power.dart';
import 'search.dart';
import 'skills.dart';

class GekisoSettlement {
  GekisoSettlement({
    required this.rewardSum,
    required this.comparisonSum,
    required this.cpSum,
    required this.observations,
    required this.directMin,
    required this.directMax,
    required this.ranks,
  });
  final double rewardSum;
  final double comparisonSum;
  final double cpSum;
  final int observations;
  final double directMin;
  final double directMax;
  final Map<int, int> ranks;
  double get mean => comparisonSum / observations;
}

typedef RewardCutoff = ({double key, bool pruneEqual});

const _maxSafe = 9007199254740991.0;
bool _safeInteger(double x) =>
    x.isFinite && x == x.roundToDouble() && x.abs() <= _maxSafe;

/// Settles the samples; null once the remaining outcomes cannot reach
/// the cutoff even at the highest reachable table reward.
GekisoSettlement? settleGekisoRewards(
  CompiledChart chart,
  EventRoute route,
  bool points,
  int bonus,
  Iterable<Float64List> scoreSamples, {
  CpExchange? exchange,
  ({int observations, double ceiling, RewardCutoff cutoff})? progress,
}) {
  if (route.kind != RouteKind.live) throw StateError('gekiso-reward-route');
  if (progress != null &&
      (progress.observations < 1 ||
          !_safeInteger(progress.ceiling) ||
          progress.ceiling < 0 ||
          !_safeInteger(progress.observations * progress.ceiling))) {
    throw StateError('gekiso-reward-precision');
  }
  var rewardSum = 0.0, comparisonSum = 0.0, cpSum = 0.0;
  var observations = 0;
  var directMin = inf, directMax = -inf;
  final ranks = <int, int>{};
  for (final scores in scoreSamples) {
    if (scores.isEmpty) throw StateError('gekiso-reward-empty-sample');
    for (final score in scores) {
      if (!score.isFinite || score < 0) throw StateError('gekiso-reward-score');
      final rank = battleRank(chart, score);
      if (points
          ? !route.points.containsKey(rank)
          : !route.rewards.any(
              (r) => r.scoreRank == rank && r.resourceId == route.itemId,
            )) {
        throw StateError('gekiso-reward-rank:$rank');
      }
      if (exchange != null && !route.challengePoints.containsKey(rank)) {
        throw StateError('gekiso-reward-cp:$rank');
      }
      final cp = (route.challengePoints[rank] ?? 0) * route.rate;
      final reward = points
          ? eventPoints(route, bonus, rank).toDouble()
          : eventItems(route, bonus, rank);
      rewardSum += reward;
      cpSum += cp;
      comparisonSum += exchange != null
          ? reward * exchange.denominator + cp * exchange.numerator
          : reward;
      observations++;
      if (!_safeInteger(rewardSum) ||
          !_safeInteger(cpSum) ||
          !_safeInteger(comparisonSum) ||
          comparisonSum > _maxSafe / 2) {
        throw StateError('gekiso-reward-precision');
      }
      directMin = math.min(directMin, reward);
      directMax = math.max(directMax, reward);
      ranks[rank] = (ranks[rank] ?? 0) + 1;
    }
    if (progress != null) {
      if (observations > progress.observations) {
        throw StateError('gekiso-reward-sample-count');
      }
      if (observations < progress.observations) {
        // Every remaining outcome receives the highest reachable table
        // reward: an overestimate of the fixed-sample mean, never less.
        final numerator =
            comparisonSum +
            (progress.observations - observations) * progress.ceiling;
        if (!_safeInteger(numerator)) {
          throw StateError('gekiso-reward-precision');
        }
        final upperBound = numerator / progress.observations;
        if (upperBound < progress.cutoff.key ||
            (progress.cutoff.pruneEqual && upperBound == progress.cutoff.key)) {
          return null;
        }
      }
    }
  }
  if (observations == 0) throw StateError('gekiso-reward-empty-sample');
  if (progress != null && observations != progress.observations) {
    throw StateError('gekiso-reward-sample-count');
  }
  return GekisoSettlement(
    rewardSum: rewardSum,
    comparisonSum: comparisonSum,
    cpSum: cpSum,
    observations: observations,
    directMin: directMin,
    directMax: directMax,
    ranks: ranks,
  );
}

/// Player accuracy and skill conversion are different quantities.
class GekisoJustSummary {
  GekisoJustSummary(
    this.eligible,
    this.baselineHits,
    this.effectiveHits,
    this.convertedHits,
  );
  final int eligible;
  final int baselineHits;
  double effectiveHits;
  double convertedHits;

  /// Null when this chart has no eligible JUST notes. Fractions.
  double? get baselineRate => eligible > 0 ? baselineHits / eligible : null;
  double? get effectiveRate => eligible > 0 ? effectiveHits / eligible : null;
}

GekisoJustSummary gekisoJustSummary(GekisoChart chart, GekisoContext context) {
  if (context.judgement.length != chart.notes.length ||
      chart.judgements.length != chart.notes.length) {
    throw StateError('gekiso-just-note-mismatch');
  }
  final eligible = chart.play.justEligibleIds.toSet();
  var baselineHits = 0, effectiveHits = 0, convertedHits = 0, count = 0;
  for (final (index, note) in chart.notes.indexed) {
    if (!eligible.contains(note.id)) continue;
    count++;
    final before = chart.judgements[index] == 6;
    final after = context.judgement[index] == 6;
    if (before) baselineHits++;
    if (after) effectiveHits++;
    if (after && !before) convertedHits++;
  }
  return GekisoJustSummary(
    count,
    baselineHits,
    effectiveHits.toDouble(),
    convertedHits.toDouble(),
  );
}

// These cases only change mission state or the judgement conversion.
const _counterOnly = {
  11000, 11001, 11002, 11003, 11004, 11005, 12000, 12002, 12003, 12004, //
  12006, 13000, 13002, 13003, 13004, 13005,
};
final _bits = ByteData(8);

/// Outward rounding of positive binary64 arithmetic.
double _up(double x) {
  if (!x.isFinite) return inf;
  if (x < 0) throw StateError('negative-score-bound');
  _bits.setFloat64(0, x);
  _bits.setUint64(0, _bits.getUint64(0) + 1);
  return _bits.getFloat64(0);
}

double _add(double a, double b) => _up(a + b);
double _mul(double a, double b) => _up(a * b);

/// A score ceiling of a power, or infinity where the proof does not apply.
typedef GekisoScoreBound = double Function(int power);
double _unsupported(int power) => inf;

/// The only admitted note effects have at most one activation at each of
/// the three range starts (`rangeStartNoteDelta`).
double? _rangeStartNoteDelta(EngineMaster master, SkillEffectRow row) {
  if (row.type != 2000 && row.type != 2001) return null;
  if (row.triggerType != 1 || row.resetGroup != 0) return null;
  final sets = master.conditionSets[row.triggerGroup];
  if (sets == null || sets.length != 1 || sets[0].length != 1) return null;
  final trigger = master.conditions[sets[0][0]];
  if (trigger?.type != 7010 || !trigger!.positive) return null;
  var value = row.value;
  if (row.type == 2001) {
    if (row.cumulativeId == 0) {
      value = 0;
    } else {
      final cumulative = master.cumulative[row.cumulativeId];
      if (cumulative == null ||
          cumulative.type < 3000 ||
          cumulative.type > 3005 ||
          cumulative.cap < 0) {
        return null;
      }
      // Every admitted fixed count counts performers or distinct performer
      // attributes: at most five.
      final count = math.min(5, cumulative.cap < 1 ? 5 : cumulative.cap);
      // Admit only values for which all possible fixed counts reconstruct
      // exactly, so the six-command proof still holds.
      for (var n = 0; n <= count; n++) {
        var current = row.value * n;
        if (row.maxValue > 0) current = math.min(current, row.maxValue);
        final factor = f(f(current) / 10000);
        if (f(f(noteFactorMill(factor)) / 100000) != factor) return null;
      }
      value *= count;
      if (value >= 2147483648) return null;
      if (row.maxValue > 0) value = math.min(value, row.maxValue);
    }
  }
  final mill = noteFactorMill(f(f(value) / 10000));
  if (mill < 0 || mill >= 2147483647) return null;
  return f(f(mill) / 100000);
}

class _Budget {
  double positive = 0;
  int commands = 0;
}

/// A score ceiling for counter/lottery/judgement effects and a restricted,
/// bounded note-score effect family. Unsupported effect families return
/// infinity: this is a pruning proof, not a score approximation.
GekisoScoreBound gekisoScoreBound(
  EngineMaster master,
  GekisoChart chart,
  List<MemberState> members,
  List<SnapState> snaps, [
  List<SnapState?>? bindings,
]) {
  if (bindings != null &&
      (bindings.length != members.length || members.length > 5)) {
    return _unsupported;
  }
  final activeSnaps = bindings != null
      ? bindings.whereType<SnapState>().toList()
      : snaps;
  _Budget? admitted(List<SkillEffectRow>? rows, int level) {
    final active = [
      for (final row in rows ?? const <SkillEffectRow>[])
        if (row.level == level) row,
    ];
    if (active.isEmpty) return null;
    final budget = _Budget();
    for (final row in active) {
      if (row.value < 0 ||
          row.value > 1e6 ||
          !row.seconds.isFinite ||
          row.seconds < 0 ||
          row.maxValue < 0 ||
          row.maxValue > 1e6) {
        return null;
      }
      if (_counterOnly.contains(row.type)) continue;
      final delta = _rangeStartNoteDelta(master, row);
      if (delta == null) return null;
      budget.positive = _add(budget.positive, _mul(3, delta));
      budget.commands += 6;
    }
    return budget;
  }

  final memberBudgets = <_Budget>[], snapBudgets = <_Budget>[];
  for (final member in members) {
    if (member.card.gekisoSkillId == 0) continue;
    final budget = admitted(
      master.gekisoSkills[member.card.gekisoSkillId]?.effects,
      member.growth.gekisoSkillLevel,
    );
    if (budget == null) return _unsupported;
    memberBudgets.add(budget);
  }
  for (final snap in activeSnaps) {
    final total = _Budget();
    for (final (i, id) in snap.card.gekisoSupportSkillIds.indexed) {
      if (id == 0) continue;
      final budget = admitted(
        master.gekisoSupportSkills[id]?.effects,
        snap.gekisoSkillLevels[i],
      );
      if (budget == null) return _unsupported;
      total.positive = _add(total.positive, budget.positive);
      total.commands += budget.commands;
    }
    snapBudgets.add(total);
  }
  double largestFive(List<_Budget> budgets) => ([
    for (final b in budgets) b.positive,
  ]..sort((a, b) => b.compareTo(a))).take(5).fold(0.0, _add);
  int commandCount(List<_Budget> budgets) => ([
    for (final b in budgets) b.commands,
  ]..sort((a, b) => b - a)).take(5).fold(0, (a, b) => a + b);
  final notePositive = _add(
    largestFive(memberBudgets),
    largestFive(snapBudgets),
  );
  final noteCommands = commandCount(memberBudgets) + commandCount(snapBudgets);
  final live = master.live;
  if (!(live.lifeOnus >= 0 && live.lifeOnus <= 1) ||
      chart.full.convertedCount < 1 ||
      chart.full.convertedCount > 1e9 ||
      chart.rangePercent.any((x) => x < 0)) {
    return _unsupported;
  }
  if (chart.judgeFrac.any((x) => x < 0 || !x.isFinite) ||
      (live.combo[1] ?? const <(int, double)>[]).any(
        (row) => row.$2 < 0 || !row.$2.isFinite,
      ) ||
      !(live.gekiso.rushPercent >= 0 && live.gekiso.rushPercent <= 100)) {
    return _unsupported;
  }

  // Each real trigger may choose only one unused member; letting every
  // trigger choose the best member/photo pair can only raise the bound.
  final shapes = <List<({int duration, double value})>>[];
  final seen = <String>{};
  var maxAbsolute = 0.0;
  var maxActions = 0;
  for (final (memberIndex, member) in members.indexed) {
    for (final snap
        in bindings != null
            ? [bindings[memberIndex]]
            : <SnapState?>[null, ...snaps]) {
      final slot = resolveSlotSkill(master, member, snap);
      final shape = <({int duration, double value})>[];
      var absolute = 0.0;
      var actions = 0;
      for (final effect in slot.effects) {
        final multiplicity = effect.type == 2000 ? 1 : effect.judgements.length;
        final diff = f(effect.delta / 100000);
        final duration = windowMs(effect.seconds, slot.extensionMs);
        if (!diff.isFinite) return _unsupported;
        actions += multiplicity;
        absolute = _add(absolute, _mul(diff.abs(), multiplicity.toDouble()));
        if (duration > 0 && diff > 0) {
          shape.add((
            duration: duration,
            value: _mul(diff, multiplicity.toDouble()),
          ));
        }
      }
      maxActions = math.max(maxActions, actions);
      maxAbsolute = math.max(maxAbsolute, absolute);
      final key = jsonEncode([
        for (final e in shape) [e.duration, e.value],
      ]);
      if (seen.add(key)) shapes.add(shape);
    }
  }
  final durations = {
    for (final shape in shapes)
      for (final e in shape) e.duration,
  }.toList()..sort();
  final envelope = [
    for (final duration in durations)
      shapes.fold(
        0.0,
        (maximum, shape) => math.max(
          maximum,
          shape
              .where((e) => e.duration >= duration)
              .fold(0.0, (sum, e) => _add(sum, e.value)),
        ),
      ),
  ];
  final events = [for (final (_, time) in chart.full.events.take(5)) time];
  final u = math.pow(2, -24).toDouble();
  final eta = math.pow(2, -149).toDouble();
  // N = 3 * (2F + 6) * Q bounds every relevant float32 operation of the
  // frame score log, including arbitrary backwards rewinds.
  final noteOperations = 3 * (2 * chart.play.frames.length + 6) * noteCommands;
  if (noteOperations * u >= 0.25) return _unsupported;
  final noteError = noteCommands != 0
      ? _mul(
          _add(
            _mul(noteOperations * u, _add(1, _mul(2, notePositive))),
            _mul(noteOperations.toDouble(), eta),
          ),
          _up(1 / (1 - noteOperations * u)),
        )
      : 0.0;
  final noteMultiplier = _add(_add(1, notePositive), noteError);
  final operations = 10 * maxActions + 1;
  if (operations * u > 0.25) return _unsupported;
  final residual = _add(
    _mul(8 * operations * u, _mul(5, maxAbsolute)),
    4 * operations * eta,
  );
  final rho = _up(1 / (1 - u));
  var roundFactor = 1.0;
  for (var i = 0; i < 12; i++) {
    roundFactor = _mul(roundFactor, rho);
  }
  final fraction = chart.judgeFrac.reduce(math.max);
  final low = math.pow(2, -10).toDouble();
  for (final v in [live.adjustment, chart.difficultyFactor, fraction]) {
    if (v < low || v > 1e4 || !v.isFinite) return _unsupported;
  }
  var coefficient = 0.0;
  for (var i = 0; i < chart.notes.length; i++) {
    final note = chart.notes[i];
    final noteFrac = chart.noteFrac[i];
    final combo = chart.comboFactor[i];
    if (noteFrac == 0) continue;
    if (noteFrac < low || noteFrac > 100 || combo < low || combo > 4) {
      return _unsupported;
    }
    var liveFactor = residual;
    for (final start in events) {
      final delta = chart.times[i] - start;
      if (delta < 0) continue;
      final at = durations.indexWhere((duration) => duration > delta);
      if (at >= 0) liveFactor = _add(liveFactor, envelope[at]);
    }
    if (liveFactor > 1e5) return _unsupported;
    // The Gekisou combo factor reads these inclusive Combo ranges, capped at 1.
    var gk = 1.0;
    for (final (r, (start, end)) in chart.setup.fevers.indexed) {
      if (r < chart.setup.missions.length &&
          chart.setup.missions[r] == 1 &&
          start <= note.timeMs &&
          note.timeMs <= end) {
        gk = 2;
      }
    }
    // Native luckPercent is capped at 200.
    final luck = chart.luck ? 2.0 : 1.0;
    var c = _mul(live.adjustment, chart.difficultyFactor);
    for (final term in [
      noteFrac,
      fraction,
      combo,
      gk,
      luck,
      _add(noteMultiplier, liveFactor),
      roundFactor,
    ]) {
      c = _mul(c, term);
    }
    c = _up(c / chart.full.convertedCount);
    final range = chart.rangeOf[i];
    if (range >= 0) c = _mul(c, _add(1, _up(chart.rangePercent[range] / 100)));
    coefficient = _add(coefficient, c);
  }
  return (power) {
    if (power < 1 || power > 2147483648) return inf;
    final bound = _mul(coefficient, power.toDouble());
    return bound <= _maxSafe ? bound : inf;
  };
}

class GekisoRewardDetail {
  GekisoRewardDetail({
    required this.settlement,
    required this.bonus,
    required this.scores,
    required this.just,
    required this.luckSamples,
    required this.sampled,
  });
  final GekisoSettlement settlement;
  final int bonus;
  final OrderScores scores;
  final GekisoJustSummary just;
  final int luckSamples;
  final bool sampled;
}

ObjectiveAdapter<GekisoRewardDetail> gekisoRewardObjective({
  required EngineMaster master,
  required List<MemberState> members,
  required List<SnapState> snaps,
  required CompiledChart chart,
  required GekisoChart gekiso,
  required EventRoute route,
  required bool points,
  required int luckSamples,
  CpExchange? exchange,
  double? rewardTarget,
}) {
  final bonusType = points ? 0 : 1;
  int memberBonus(int i) =>
      memberEventPercent(route.effects, members[i], bonusType);
  int snapBonus(int j) => snapEventPercent(route.effects, snaps[j], bonusType);
  final ranks = {
    2,
    for (final r in chart.ranks)
      if (r.battleRequired > 0) r.rank,
  }.toList();
  double value(num bonus, int rank) {
    final reward = points
        ? eventPoints(route, bonus, rank).toDouble()
        : eventItems(route, bonus, rank);
    final cp = (route.challengePoints[rank] ?? 0) * route.rate;
    return exchange != null
        ? reward * exchange.denominator + cp * exchange.numerator
        : reward;
  }

  final scoreCeiling = gekisoScoreBound(master, gekiso, members, snaps);
  // A single unsupported card must not disable safe score bounds for teams
  // which do not use it. Bounds are leader-independent.
  final localBounds = <String, GekisoScoreBound>{};
  GekisoScoreBound teamBound(Team team) {
    final key = ([
      for (final (slot, member) in team.members.indexed)
        '$member:${team.snaps[slot]}',
    ]..sort()).join('|');
    final known = localBounds.remove(key);
    if (known != null) return localBounds[key] = known;
    final bound = gekisoScoreBound(
      master,
      gekiso,
      [for (final i in team.members) members[i]],
      const [],
      [for (final j in team.snaps) j < 0 ? null : snaps[j]],
    );
    if (localBounds.length >= 256) localBounds.remove(localBounds.keys.first);
    return localBounds[key] = bound;
  }

  double ceiling(double power, num bonus, [GekisoScoreBound? bound]) {
    final upper = (bound ?? scoreCeiling)(power.toInt());
    var best = -inf;
    for (final rank in ranks) {
      if (rank == 2 ||
          chart.ranks.any(
            (r) =>
                r.rank == rank &&
                r.battleRequired > 0 &&
                r.battleRequired <= upper,
          )) {
        best = math.max(best, value(bonus, rank));
      }
    }
    return best;
  }

  Exact<GekisoRewardDetail>? evaluate(
    Team team,
    int power, [
    RewardCutoff? cutoff,
  ]) {
    SnapState? snapOf(int slot) =>
        team.snaps[slot] < 0 ? null : snaps[team.snaps[slot]];
    final deck = [
      for (final (slot, i) in team.members.indexed)
        performer(master, members[i], snapOf(slot)),
    ];
    final skills = [
      for (final (slot, i) in team.members.indexed)
        resolveSlotSkill(master, members[i], snapOf(slot)),
    ];
    var bonus = 0;
    for (final i in team.members) {
      bonus += memberBonus(i);
    }
    for (final j in team.snaps) {
      if (j >= 0) bonus += snapBonus(j);
    }
    final runs = gekiso.luck ? luckSamples : 1;
    if (runs < 1) throw StateError('gekiso-reward-samples');
    final scores = Float64List(orders.length);
    var min = inf, max = -inf;
    var minOrder = 0, maxOrder = 0;
    GekisoJustSummary? just;
    // Each outcome is settled immediately, before averaging rewards.
    Iterable<Float64List> samples() sync* {
      for (var seed = 0; seed < runs; seed++) {
        final context = gekisoContext(master, gekiso, deck, [seed]);
        final current = gekisoJustSummary(gekiso, context);
        final result = scoreOrdersGekiso(
          master,
          gekiso,
          context,
          power,
          skills,
        );
        final summary = just ??= GekisoJustSummary(
          current.eligible,
          current.baselineHits,
          0,
          0,
        );
        summary.effectiveHits += current.effectiveHits / runs;
        summary.convertedHits += current.convertedHits / runs;
        for (var i = 0; i < scores.length; i++) {
          scores[i] += result.scores[i] / runs;
        }
        if (result.min < min) {
          min = result.min;
          minOrder = result.minOrder;
        }
        if (result.max > max) {
          max = result.max;
          maxOrder = result.maxOrder;
        }
        yield result.scores;
      }
    }

    final settlement = settleGekisoRewards(
      chart,
      route,
      points,
      bonus,
      samples(),
      exchange: exchange,
      progress: cutoff != null && cutoff.key.isFinite
          ? (
              observations: runs * orders.length,
              ceiling: ceiling(power.toDouble(), bonus, teamBound(team)),
              cutoff: cutoff,
            )
          : null,
    );
    if (settlement == null) return null;
    final meanScore = scores.fold(0.0, (a, b) => a + b) / orders.length;
    return Exact(
      rewardTarget == null
          ? settlement.mean
          : settlement.mean == rewardTarget
          ? meanScore
          : -1,
      GekisoRewardDetail(
        settlement: settlement,
        bonus: bonus,
        scores: OrderScores(
          power,
          scores,
          meanScore,
          min,
          max,
          minOrder,
          maxOrder,
        ),
        just: just!,
        luckSamples: runs,
        sampled: gekiso.luck,
      ),
    );
  }

  return ObjectiveAdapter(
    skill: (_, _) => (0, 0),
    memberBonus: memberBonus,
    snapBonus: snapBonus,
    preserveSnapOptions: rewardTarget != null,
    // No empirical score bound or capped shortlist participates in pruning.
    bound: (totals) => rewardTarget == null
        ? ceiling(totals.power, totals.bonus)
        : ceiling(totals.power, totals.bonus) < rewardTarget
        ? -1
        : scoreCeiling(totals.power.toInt()),
    leafBound: (team, totals) {
      final bound = teamBound(team);
      final reward = ceiling(totals.power, totals.bonus, bound);
      return rewardTarget == null
          ? reward
          : reward < rewardTarget
          ? -1
          : bound(totals.power.toInt());
    },
    interval: (team, totals) {
      final bound = teamBound(team);
      final low = ranks
          .map((rank) => value(totals.bonus, rank))
          .reduce(math.min);
      final high = ceiling(totals.power, totals.bonus, bound);
      return rewardTarget == null
          ? (low, high)
          : low > rewardTarget || high < rewardTarget
          ? (-1, -1)
          : (-1, bound(totals.power.toInt()));
    },
    // The equality pass compares scores; progressive settlement still compares
    // rewards and keeps every outcome that can reach the target reward.
    evaluate: (team, power, _, cutoff) => evaluate(
      team,
      power,
      rewardTarget == null ? cutoff : (key: rewardTarget, pruneEqual: false),
    ),
    exact: (team, power, _) =>
        evaluate(team, power) ??
        (throw StateError('gekiso-reward-unexpected-cutoff')),
  );
}
