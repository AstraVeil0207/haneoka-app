/// Objective adapters: bounds for the search and exact values for survivors
/// (`team-builder/engine/objectives.ts`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'chart.dart';
import 'live.dart';
import 'master.dart';
import 'model.dart';
import 'num.dart';
import 'power.dart';
import 'search.dart';
import 'skills.dart';

enum Criterion { mean, min, max }

class LiveDetail {
  LiveDetail(this.scores, this.skills);
  final OrderScores scores;
  final List<SlotSkill> skills;
}

class EventDetail {
  EventDetail({
    this.live,
    this.perOrder,
    required this.mean,
    required this.bonus,
    this.ranks = const {},
    this.challengePoints = 0,
    this.rewardSum,
    this.comparisonSum,
    this.directMin,
    this.directMax,
  });
  final LiveDetail? live;

  /// Points (or items) per play for each order.
  final Float64List? perOrder;
  final double mean;
  final int bonus;
  final Map<int, int> ranks;
  final double challengePoints;
  final double? rewardSum;
  final double? comparisonSum;
  final double? directMin;
  final double? directMax;
}

class PotentialDetail {
  PotentialDetail(this.potential, this.area);
  final double potential;
  final double area;
}

class Shared {
  Shared(this.master, this.members, this.snaps);
  final EngineMaster master;
  final List<MemberState> members;
  final List<SnapState> snaps;
}

class LiveContext extends Shared {
  LiveContext(
    super.master,
    super.members,
    super.snaps,
    this.live,
    this.play, [
    this.settings,
  ]);
  final PreparedLive live;
  final PlayModel play;
  final LiveSettings? settings;
}

SlotSkill Function(int member, int snap) _slotSkillCache(Shared shared) {
  final cache = <int, SlotSkill>{};
  final width = shared.snaps.length + 2;
  return (member, snap) => cache[member * width + snap + 1] ??= resolveSlotSkill(
    shared.master,
    shared.members[member],
    snap < 0 ? null : shared.snaps[snap],
  );
}

/// Exact scores shared by reward objectives; eviction only causes recomputation.
class LiveScoreCache {
  LiveScoreCache([this.maxEntries = 4096]);
  final int maxEntries;
  final _entries = <String, OrderScores>{};
  final _charts = Expando<int>();
  var _nextChart = 0;

  OrderScores score(
    PreparedLive live,
    PlayModel play,
    LiveSettings? settings,
    int power,
    List<SlotSkill> skills,
    OrderScores Function() compute,
  ) {
    final chart = _charts[live] ??= _nextChart++;
    final key =
        '$chart|${play.signature}|${settings?.signature}|$power|${skills.map((s) => s.signature).join('/')}';
    final found = _entries.remove(key);
    if (found != null) return _entries[key] = found;
    final scores = compute();
    if (_entries.length >= maxEntries) _entries.remove(_entries.keys.first);
    return _entries[key] = scores;
  }
}

final liveScoreCache = LiveScoreCache();

ObjectiveAdapter<Null> powerObjective() => ObjectiveAdapter(
  skill: (_, _) => (0, 0),
  memberBonus: (_) => 0,
  snapBonus: (_) => 0,
  bound: (totals) => totals.power,
  interval: (_, totals) => (totals.power, totals.power),
  exact: (_, power, _) => Exact(power.toDouble(), null),
);

class _Weights {
  _Weights(this.high, this.low);
  final SkillWeights high;
  final SkillWeights low;
}

class _LiveCore {
  _LiveCore._(this.context);
  final LiveContext context;
  late final Int8List? judgements;
  late final SlotSkill Function(int, int) slotSkill;
  late final LinearChart high;
  late final LinearChart low;
  late final double factorCap;
  late final int maxRecovery;
  late final int divisor;
  late final PlayBoundsChart? playBounds;
  late final bool drains;
  late final double productScale;
  final _weights = <String, _Weights>{};
  final _teamModels = <int, ({LinearChart model, Map<String, double> weights})>{};

  bool get play => judgements != null;
  double get productBase => high.total;

  factory _LiveCore(LiveContext context) {
    final core = _LiveCore._(context);
    final judgements = context.play.isAllPerfect
        ? null
        : playJudgements(context.live.chart.count, context.play);
    core.judgements = judgements;
    final slotSkill = core.slotSkill = _slotSkillCache(context);
    var raise = 0.0;
    var maxRecovery = 0;
    if (judgements != null) {
      for (var member = 0; member < context.members.length; member++) {
        for (var snap = -1; snap < context.snaps.length; snap++) {
          final skill = slotSkill(member, snap);
          raise = math.max(
            raise,
            skill.effects.fold(0.0, (total, e) => total + e.delta / 100000),
          );
          maxRecovery = math.max(maxRecovery, skill.recovery);
        }
      }
    }
    core.maxRecovery = maxRecovery;
    core.high = judgements != null
        ? linearPlayChart(context.live, judgements, true, 0, 1, maxRecovery)
        : linearChart(context.live);
    // How many skill windows can cover one note bounds any note's factor.
    var overlap = 1;
    {
      final times = context.live.chart.skillTimes;
      var longest = 0;
      for (var member = 0; member < context.members.length; member++) {
        for (var snap = -1; snap < context.snaps.length; snap++) {
          final skill = slotSkill(member, snap);
          for (final effect in skill.effects) {
            longest = math.max(
              longest,
              windowMs(effect.seconds, skill.extensionMs),
            );
          }
        }
      }
      for (final time in times) {
        overlap = math.max(
          overlap,
          times.where((other) => other <= time && time < other + longest).length,
        );
      }
    }
    core.factorCap = 1 + overlap * raise;
    core.low = judgements != null
        ? linearPlayChart(context.live, judgements, false)
        : core.high;
    core.divisor = context.live.chart.convertedCount;
    core.playBounds = judgements != null
        ? playBoundsChart(context.live, judgements)
        : null;
    core.drains =
        core.playBounds != null &&
        core.playBounds!.damage.fold(0.0, (t, row) => t + row.$2) >=
            context.live.master.live.lifeBase;
    core.productScale = core.divisor / (1 + core.high.relativeError);
    return core;
  }

  _Weights weightOf(int member, int snap) =>
      _weights['$member:$snap'] ??= () {
        final skill = slotSkill(member, snap);
        final upper = skillWeights(high, skill);
        if (judgements != null && skill.convert != null) {
          // Conversions are this slot's own upside; fold them into its optimistic weights.
          final extra = conversionWeights(high, judgements!, skill, factorCap);
          var total = 0.0;
          for (var event = 0; event < 5; event++) {
            upper.perEvent[event] += extra[event];
            total += upper.perEvent[event];
          }
          upper.mean = total / 5;
          upper.best = maxOf(upper.perEvent);
        }
        return _Weights(
          upper,
          identical(low, high) ? upper : skillWeights(low, skill),
        );
      }();

  double scoreHigh(Totals totals) =>
      totals.power * (high.total + totals.skill) / divisor *
      (1 + high.relativeError);

  double scoreLow(Totals totals) => math.max(
    0,
    totals.power * (low.total + totals.skillLow) / divisor *
            (1 - low.relativeError) -
        low.absoluteError,
  );

  List<SlotSkill> skillsOf(Team team) => [
    for (final (slot, member) in team.members.indexed)
      slotSkill(member, team.snaps[slot]),
  ];

  LiveDetail evaluate(Team team, int power) {
    final skills = skillsOf(team);
    final scores = liveScoreCache.score(
      context.live,
      context.play,
      context.settings,
      power,
      skills,
      () => judgements != null
          ? scoreOrdersPlay(
              context.live,
              power,
              skills,
              judgements!,
              context.settings ?? normalSettings,
            )
          : scoreOrdersAP(
              context.live,
              power,
              skills,
              context.settings ?? normalSettings,
            ),
    );
    return LiveDetail(scores, skills);
  }

  /// Per-order linear scores of a complete team: [low, high] for each order.
  (Float64List, Float64List) orderBounds(Team team, int power) {
    final lows = Float64List(orders.length), highs = Float64List(orders.length);
    if (playBounds != null) {
      final skills = skillsOf(team);
      for (final (index, order) in orders.indexed) {
        final (low, high) = playOrderBounds(playBounds!, skills, order, power);
        lows[index] = low;
        highs[index] = high;
      }
      return (lows, highs);
    }
    final slots = [
      for (final (slot, member) in team.members.indexed)
        weightOf(member, team.snaps[slot]),
    ];
    for (final (index, order) in orders.indexed) {
      var lowSum = 0.0, highSum = 0.0;
      for (var event = 0; event < 5; event++) {
        final slot = slots[order[event]];
        lowSum += slot.low.perEvent[event];
        highSum += slot.high.perEvent[event];
      }
      lows[index] = scoreLow(
        Totals(power: power.toDouble(), skill: 0, skillLow: lowSum),
      );
      highs[index] = scoreHigh(
        Totals(power: power.toDouble(), skill: highSum),
      );
    }
    return (lows, highs);
  }

  /// A complete team recovers at most its own best recovery per activation.
  double teamHigh(Team team, Totals totals) {
    if (judgements == null) return scoreHigh(totals);
    var recovery = 0;
    for (final (slot, member) in team.members.indexed) {
      recovery = math.max(recovery, slotSkill(member, team.snaps[slot]).recovery);
    }
    if (recovery >= maxRecovery) return scoreHigh(totals);
    final entry = _teamModels[recovery] ??= (
      model: linearPlayChart(
        context.live,
        judgements!,
        true,
        0,
        1,
        recovery,
      ),
      weights: <String, double>{},
    );
    var skill = 0.0;
    for (final (slot, member) in team.members.indexed) {
      skill += entry.weights['$member:${team.snaps[slot]}'] ??= () {
        final value = slotSkill(member, team.snaps[slot]);
        final weights = skillWeights(entry.model, value);
        if (value.convert != null) {
          final extra = conversionWeights(
            entry.model,
            judgements!,
            value,
            factorCap,
          );
          for (var event = 0; event < 5; event++) {
            weights.perEvent[event] += extra[event];
          }
        }
        return maxOf(weights.perEvent);
      }();
    }
    return totals.power * (entry.model.total + skill) / divisor *
        (1 + high.relativeError);
  }
}

double _criterionKey(OrderScores scores, Criterion criterion) =>
    switch (criterion) {
      Criterion.min => scores.min,
      Criterion.max => scores.max,
      Criterion.mean => scores.mean,
    };

ObjectiveAdapter<LiveDetail> liveScoreObjective(
  LiveContext context,
  Criterion criterion,
) {
  final core = _LiveCore(context);
  return ObjectiveAdapter(
    skill: (member, snap) {
      final w = core.weightOf(member, snap);
      return switch (criterion) {
        Criterion.min => (w.low.worst, w.high.mean),
        Criterion.max => (w.low.mean, w.high.best),
        Criterion.mean => (w.low.mean, w.high.mean),
      };
    },
    memberBonus: (_) => 0,
    snapBonus: (_) => 0,
    bound: core.scoreHigh,
    productBase: core.productBase,
    leafBound: core.play ? core.teamHigh : null,
    hard: core.drains,
    preferSnap: core.drains
        ? (member, snap) => core.slotSkill(member, snap).recovery.toDouble()
        : null,
    interval: (team, totals) {
      if (criterion == Criterion.mean && !core.play) {
        return (core.scoreLow(totals), core.scoreHigh(totals));
      }
      // Converting a Miss or Bad also spares its damage and combo: exact score.
      if (core.play &&
          [
            for (final (slot, m) in team.members.indexed)
              core.slotSkill(m, team.snaps[slot]),
          ].any((s) => s.convert?.judgements.any((j) => j <= 2) ?? false)) {
        final key = _criterionKey(
          core.evaluate(team, totals.power.toInt()).scores,
          criterion,
        );
        return (key, key);
      }
      final (lows, highs) = core.orderBounds(team, totals.power.toInt());
      if (criterion == Criterion.mean) {
        return (
          lows.fold(0.0, (a, b) => a + b) / lows.length,
          highs.fold(0.0, (a, b) => a + b) / highs.length,
        );
      }
      return criterion == Criterion.min
          ? (lows.reduce(math.min), highs.reduce(math.min))
          : (lows.reduce(math.max), highs.reduce(math.max));
    },
    exact: (team, power, _) {
      final detail = core.evaluate(team, power);
      return Exact(_criterionKey(detail.scores, criterion), detail);
    },
  );
}

/// Event bonus first, power second: a near-instant search whose top teams
/// are strong seeds for event payoffs.
ObjectiveAdapter<Null> eventBonusSurrogate(
  Shared shared,
  List<EventEffectRow> effects,
  bool points, [
  double bonusWeight = 16777216,
]) {
  final bonusType = points ? 0 : 1;
  double key(double bonus, double power) => bonus * bonusWeight + power;
  return ObjectiveAdapter(
    skill: (_, _) => (0, 0),
    memberBonus: (i) => memberEventPercent(effects, shared.members[i], bonusType),
    snapBonus: (j) => snapEventPercent(effects, shared.snaps[j], bonusType),
    bound: (totals) => key(totals.bonus, totals.power),
    interval: (_, totals) =>
        (key(totals.bonus, totals.power), key(totals.bonus, totals.power)),
    exact: (team, power, _) {
      var bonus = 0;
      for (final i in team.members) {
        bonus += memberEventPercent(effects, shared.members[i], bonusType);
      }
      for (final j in team.snaps) {
        if (j >= 0) bonus += snapEventPercent(effects, shared.snaps[j], bonusType);
      }
      return Exact(key(bonus.toDouble(), power.toDouble()), null);
    },
  );
}

/// The largest linear upper bound on any order's score over all teams.
ObjectiveAdapter<Null> scoreCapObjective(LiveContext context) {
  final core = _LiveCore(context);
  return ObjectiveAdapter(
    skill: (member, snap) {
      final best = core.weightOf(member, snap).high.best;
      return (best, best);
    },
    memberBonus: (_) => 0,
    snapBonus: (_) => 0,
    bound: core.scoreHigh,
    productBase: core.productBase,
    interval: (_, totals) {
      final value = core.scoreHigh(totals);
      return (value, value);
    },
    exact: (team, power, _) {
      var skill = 0.0;
      for (final (slot, member) in team.members.indexed) {
        skill += core.weightOf(member, team.snaps[slot]).high.best;
      }
      return Exact(
        core.scoreHigh(Totals(power: power.toDouble(), skill: skill)),
        null,
      );
    },
  );
}

final _order5 = Float64List(32);

/// Best total of five rows assigned to five distinct columns: bitmask DP.
double bestOrder5(List<Float64List> rows) {
  _order5.fillRange(0, 32, -inf);
  _order5[0] = 0;
  for (var mask = 0; mask < 31; mask++) {
    final base = _order5[mask];
    if (base == -inf) continue;
    var row = 0;
    for (var m = mask; m != 0; m &= m - 1) {
      row++;
    }
    final weights = rows[row];
    for (var column = 0; column < 5; column++) {
      final bit = 1 << column;
      if (mask & bit != 0) continue;
      final value = base + weights[column];
      if (value > _order5[mask | bit]) _order5[mask | bit] = value;
    }
  }
  return _order5[31];
}

enum RouteKind { live, challenge, skip }

/// Event point / item rules of one play route.
class EventRoute {
  EventRoute({
    required this.kind,
    required this.rate,
    required this.rewardRate,
    required this.points,
    required this.rewards,
    required this.itemId,
    required this.challengePoints,
    required this.effects,
  });
  final RouteKind kind;

  /// Event point multiplier of the boost / challenge-point consumption.
  final double rate;

  /// Reward multiplier for items.
  final double rewardRate;

  /// rank → points per play at rate 1.
  final Map<int, int> points;
  final List<RewardRow> rewards;
  final int itemId;

  /// rank → challenge points at rate 1 (normal lives earn them).
  final Map<int, int> challengePoints;
  final List<EventEffectRow> effects;
}

int eventPoints(EventRoute route, num bonus, int rank) {
  final value = route.points[rank] ?? 0;
  return route.kind == RouteKind.challenge
      ? (imul(imul(value, route.rate), i32(bonus + 10000)) / 10000).truncate()
      : (imul(imul(i32(bonus + 10000), route.rate), value) / 10000).truncate();
}

double eventItems(EventRoute route, num bonus, int rank) {
  var total = 0.0;
  for (final reward in route.rewards) {
    if (reward.scoreRank == rank &&
        (route.itemId == 0 || reward.resourceId == route.itemId)) {
      total +=
          (imul(imul(reward.count, i32(bonus + 10000)), route.rewardRate) /
                  10000)
              .truncate() *
          reward.probability /
          10000;
    }
  }
  return total;
}

/// One CP's long-run reward value, kept rational so tied teams stay tied.
class CpExchange {
  CpExchange(this.numerator, this.denominator);
  final int numerator;
  final int denominator;
}

double _topFive(List<num> values) =>
    (values.map((v) => v.toDouble()).toList()..sort((a, b) => b.compareTo(a)))
        .take(5)
        .fold(0.0, (a, b) => a + b);

/// Fixed skip rank, or the rank of each played order.
ObjectiveAdapter<EventDetail> eventObjective(
  Shared context,
  LiveContext? live,
  CompiledChart? chart,
  EventRoute route,
  bool pointsMeasure,
  int skipRank, {
  double challengePointWeight = 0,
  double scoreCap = inf,
  bool ptOnly = false,
  CpExchange? exchange,
}) {
  final bonusType = pointsMeasure ? 0 : 1;
  double direct(num bonus, int rank) => pointsMeasure
      ? eventPoints(route, bonus, rank).toDouble()
      : eventItems(route, bonus, rank);
  double value(num bonus, int rank) {
    final cp = route.kind == RouteKind.live
        ? (route.challengePoints[rank] ?? 0) * route.rate
        : 0.0;
    return exchange != null
        ? direct(bonus, rank) * exchange.denominator + cp * exchange.numerator
        : direct(bonus, rank) + challengePointWeight * cp;
  }

  int memberBonus(int i) =>
      memberEventPercent(route.effects, context.members[i], bonusType);
  int snapBonus(int j) =>
      snapEventPercent(route.effects, context.snaps[j], bonusType);
  // Equal rewards prefer more of the other reward, weighted below the
  // reward's smallest step.
  final tie = ptOnly ? 0.0 : 1 / 16777216;
  final otherType = 1 - bonusType;
  double other(num bonus, int rank) => pointsMeasure
      ? eventItems(route, bonus, rank)
      : eventPoints(route, bonus, rank).toDouble();
  final otherMemberBonuses = [
    for (final member in context.members)
      memberEventPercent(route.effects, member, otherType),
  ];
  final otherSnapBonuses = [
    for (final snap in context.snaps)
      snapEventPercent(route.effects, snap, otherType),
  ];
  int otherSnapBonus(int snap) => snap < 0 ? 0 : otherSnapBonuses[snap];
  int otherBonus(Team team) =>
      team.members.fold(0, (sum, i) => sum + otherMemberBonuses[i]) +
      team.snaps.fold(0, (sum, j) => sum + otherSnapBonus(j));
  final maxOtherBonus = tie != 0
      ? _topFive([for (final b in otherMemberBonuses) math.max(0, b)]) +
            _topFive([
              for (var s = 0; s < context.snaps.length; s++)
                math.max(0, otherSnapBonus(s)),
            ])
      : 0.0;
  final tieBounds = <int, double>{};
  double tieBound(int rank) => tieBounds[rank] ??= tie != 0
      ? tie * other(maxOtherBonus, rank)
      : 0;
  double rewardBound(num bonus, int rank) => value(bonus, rank) + tieBound(rank);
  List<double> snapDominance(int member, int snap) =>
      tie != 0 ? [otherSnapBonus(snap).toDouble()] : const [];
  AssignmentBound Function(List<int>, List<List<int>>) assignmentBound(
    int Function(Totals totals) rankOfTotals,
  ) => (members, options) {
    final memberOther = members.fold(0, (sum, i) => sum + otherMemberBonuses[i]);
    final suffix = Float64List(6);
    for (var slot = 4; slot >= 0; slot--) {
      suffix[slot] =
          suffix[slot + 1] + maxOf(options[slot].map(otherSnapBonus));
    }
    final orderedSnaps = [
      for (final snap in {for (final o in options) ...o})
        if (snap >= 0 && otherSnapBonus(snap) > 0) snap,
    ]..sort((a, b) => otherSnapBonus(b) - otherSnapBonus(a));
    return (totals, assigned, from) {
      final rank = rankOfTotals(totals);
      var distinct = 0.0;
      var left = 5 - from;
      for (final snap in orderedSnaps) {
        if (left == 0) break;
        var used = false;
        for (var slot = 0; slot < from; slot++) {
          if (assigned[slot] == snap) used = true;
        }
        if (used) continue;
        distinct += otherSnapBonus(snap);
        left--;
      }
      var bonus = memberOther + math.min(suffix[from], distinct);
      for (var slot = 0; slot < from; slot++) {
        bonus += otherSnapBonus(assigned[slot]);
      }
      return value(totals.bonus, rank) + tie * other(bonus, rank);
    };
  };
  final maxBonus = ptOnly
      ? _topFive([for (var i = 0; i < context.members.length; i++) memberBonus(i)]) +
            _topFive([for (var j = 0; j < context.snaps.length; j++) snapBonus(j)])
      : 1000000.0;
  int teamBonus(Team team) =>
      team.members.fold(0, (sum, i) => sum + memberBonus(i)) +
      team.snaps.fold(0, (sum, j) => sum + (j < 0 ? 0 : snapBonus(j)));

  if (route.kind == RouteKind.skip || live == null || chart == null) {
    return ObjectiveAdapter(
      skill: (member, snap) {
        final bonus = tie != 0
            ? (otherMemberBonuses[member] + otherSnapBonus(snap)).toDouble()
            : 0.0;
        return (bonus, bonus);
      },
      memberBonus: memberBonus,
      snapBonus: snapBonus,
      snapDominance: snapDominance,
      bound: (totals) =>
          value(totals.bonus, skipRank) + tie * other(totals.skill, skipRank),
      leafBound: (team, totals) =>
          value(totals.bonus, skipRank) +
          tie * other(otherBonus(team), skipRank),
      interval: (team, totals) {
        final key =
            value(totals.bonus, skipRank) +
            tie * other(otherBonus(team), skipRank);
        return (key, key);
      },
      exact: (team, _, _) {
        final bonus = teamBonus(team);
        final mean = value(bonus, skipRank);
        return Exact(
          mean + tie * other(otherBonus(team), skipRank),
          EventDetail(mean: mean, bonus: bonus),
        );
      },
    );
  }
  final core = _LiveCore(live);
  // scoreRank starts at 2 even when the table omits that zero-score row.
  final rankTargets = [
    (rank: 2, required: 0),
    for (final row in chart.ranks)
      if (row.rank > 2) (rank: row.rank, required: row.required),
  ];
  int rankOf(double score) => scoreRank(chart, score);

  /// Least bonus whose payoff at [rank] reaches [target].
  double bonusFor(int rank, double target) {
    if (rewardBound(maxBonus, rank) < target) return inf;
    var low = 0, high = maxBonus.toInt();
    while (low < high) {
      final mid = (low + high) >> 1;
      if (rewardBound(mid, rank) >= target) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low.toDouble();
  }

  final targetCache = <double, List<JointTarget>>{};
  // Bounds only: the cap is a proven maximum score.
  int rankBound(double score) => scoreRank(chart, math.min(score, scoreCap));
  late final ObjectiveAdapter<EventDetail> adapter;
  Exact<EventDetail> exact(Team team, int power, List<int> _) {
    final detail = core.evaluate(team, power);
    final bonus = teamBonus(team);
    final perOrder = Float64List(orders.length);
    final ranks = <int, int>{};
    var total = 0.0, challenge = 0.0;
    var rewardSum = 0.0, directMin = inf, directMax = -inf, otherSum = 0.0;
    final bonus2 = otherBonus(team);
    for (final (index, score) in detail.scores.scores.indexed) {
      final rank = rankOf(score);
      otherSum += other(bonus2, rank);
      ranks[rank] = (ranks[rank] ?? 0) + 1;
      perOrder[index] = value(bonus, rank);
      total += perOrder[index];
      challenge += (route.challengePoints[rank] ?? 0) * route.rate;
      final reward = direct(bonus, rank);
      rewardSum += reward;
      directMin = math.min(directMin, reward);
      directMax = math.max(directMax, reward);
    }
    final mean = total / orders.length;
    return Exact(
      mean + tie * otherSum / orders.length,
      EventDetail(
        live: detail,
        perOrder: perOrder,
        mean: mean,
        bonus: bonus,
        ranks: ranks,
        rewardSum: rewardSum,
        comparisonSum: total,
        directMin: directMin,
        directMax: directMax,
        challengePoints: route.kind == RouteKind.live
            ? challenge / orders.length
            : 0,
      ),
    );
  }

  adapter = ObjectiveAdapter(
    skill: (member, snap) {
      final w = core.weightOf(member, snap);
      return (w.low.worst, w.high.best);
    },
    memberBonus: memberBonus,
    snapBonus: snapBonus,
    snapDominance: snapDominance,
    productBase: core.productBase,
    jointTargets: (limit) {
      var targets = targetCache[limit];
      if (targets == null) {
        targets = [
          for (final row in rankTargets)
            if (row.required <= scoreCap)
              JointTarget(
                bonusFor(row.rank, limit),
                row.required * core.productScale,
              ),
        ].where((row) => row.bonus.isFinite).toList();
        if (targetCache.length > 64) targetCache.clear();
        targetCache[limit] = targets;
      }
      return targets;
    },
    assignmentBound: tie != 0
        ? assignmentBound((totals) => rankBound(core.scoreHigh(totals)))
        : null,
    // The best order of a complete team assigns each slot a distinct skill event.
    leafBound: (team, totals) {
      final score = core.play
          ? core.teamHigh(team, totals)
          : core.scoreHigh(
              totals.copyWith(
                skill: bestOrder5([
                  for (final (slot, member) in team.members.indexed)
                    core.weightOf(member, team.snaps[slot]).high.perEvent,
                ]),
              ),
            );
      final rank = rankBound(score);
      return value(totals.bonus, rank) + tie * other(otherBonus(team), rank);
    },
    bound: (totals) =>
        rewardBound(totals.bonus, rankBound(core.scoreHigh(totals))),
    interval: (team, totals) {
      final scoreLow = core.scoreLow(totals), scoreHigh = core.scoreHigh(totals);
      final rank = rankOf(scoreLow);
      if (rank == rankBound(scoreHigh)) {
        final key =
            value(totals.bonus, rank) + tie * other(otherBonus(team), rank);
        return (key, key);
      }
      final (lows, highs) = core.orderBounds(team, totals.power.toInt());
      var low = 0.0, high = 0.0;
      var straddles = false;
      for (var index = 0; index < lows.length; index++) {
        final lowRank = rankOf(lows[index]), highRank = rankBound(highs[index]);
        if (lowRank != highRank) straddles = true;
        low += value(totals.bonus, lowRank);
        high += value(totals.bonus, highRank);
      }
      // A straddling order leaves the interval wide open; scoring exactly is cheaper.
      if (straddles) {
        final key = exact(team, totals.power.toInt(), const []).key;
        return (key, key);
      }
      final bonus2 = otherBonus(team);
      var otherLow = 0.0, otherHigh = 0.0;
      for (var index = 0; index < lows.length; index++) {
        otherLow += other(bonus2, rankOf(lows[index]));
        otherHigh += other(bonus2, rankBound(highs[index]));
      }
      return (
        (low + tie * otherLow) / lows.length,
        (high + tie * otherHigh) / highs.length,
      );
    },
    exact: exact,
  );
  return adapter;
}

/// Among teams whose event key is exactly [target], the highest mean score.
ObjectiveAdapter<EventDetail> eventScoreTieObjective(
  LiveContext context,
  ObjectiveAdapter<EventDetail> event,
  double target, [
  List<Team> higherRewardTeams = const [],
]) {
  final mean = liveScoreObjective(context, Criterion.mean);
  Totals eventTotals(Team team, Totals totals) {
    var skill = 0.0, skillLow = 0.0;
    for (final (slot, member) in team.members.indexed) {
      final (low, high) = event.skill(member, team.snaps[slot]);
      skill += high;
      skillLow += low;
    }
    return totals.copyWith(skill: skill, skillLow: skillLow);
  }

  String setKey(List<int> members) => ([...members]..sort()).join(',');
  final excluded = {for (final team in higherRewardTeams) setKey(team.members)};
  bool eligible(Team team) => !excluded.contains(setKey(team.members));
  return ObjectiveAdapter(
    preserveSnapOptions: true,
    skill: mean.skill,
    memberBonus: event.memberBonus,
    snapBonus: event.snapBonus,
    bound: mean.bound,
    assignmentBound: (members, options) {
      if (excluded.contains(setKey(members))) return (_, _, _) => -1;
      final rewardBound = event.assignmentBound?.call(members, options);
      final suffix = Float64List(6);
      for (var slot = 4; slot >= 0; slot--) {
        suffix[slot] =
            suffix[slot + 1] +
            maxOf(options[slot].map((snap) => event.skill(members[slot], snap).$2));
      }
      return (totals, assigned, from) {
        var skill = suffix[from];
        for (var slot = 0; slot < from; slot++) {
          skill += event.skill(members[slot], assigned[slot]).$2;
        }
        final optimistic = totals.copyWith(skill: skill);
        return (rewardBound != null
                    ? rewardBound(optimistic, assigned, from)
                    : event.bound(optimistic)) <
                target
            ? -1
            : mean.bound(totals);
      };
    },
    leafBound: (team, totals) {
      if (!eligible(team)) return -1;
      final t = eventTotals(team, totals);
      final bound = event.leafBound?.call(team, t) ?? event.bound(t);
      return bound < target ? -1 : mean.bound(totals);
    },
    interval: (team, totals) {
      if (!eligible(team)) return (-1, -1);
      final (low, high) = event.interval(team, eventTotals(team, totals));
      if (high < target || low > target) return (-1, -1);
      final (scoreLow, scoreHigh) = mean.interval(team, totals);
      return (low == target && high == target ? scoreLow : -1, scoreHigh);
    },
    exact: (team, power, slotPowers) {
      final result = event.exact(team, power, slotPowers);
      return Exact(
        eligible(team) && result.key == target
            ? result.detail.live!.scores.mean
            : -1,
        result.detail,
      );
    },
  );
}

/// Songless potential P·(1 + A/T): A sums each skill's raise × its window seconds.
ObjectiveAdapter<PotentialDetail> potentialObjective(
  Shared shared,
  double windowSeconds,
) {
  final slotSkill = _slotSkillCache(shared);
  double area(int member, int snap) {
    final skill = slotSkill(member, snap);
    var total = 0.0;
    for (final effect in skill.effects) {
      if ((effect.type == 2000 || effect.judgements.contains(5)) &&
          !effect.gate.blocks(shared.master.live.lifeBase)) {
        total +=
            effect.delta /
            100000 *
            (windowMs(effect.seconds, skill.extensionMs) / 1000);
      }
    }
    return total;
  }

  double key(double power, double sum) => power * (1 + sum / windowSeconds);
  return ObjectiveAdapter(
    skill: (member, snap) {
      final value = area(member, snap);
      return (value, value);
    },
    memberBonus: (_) => 0,
    snapBonus: (_) => 0,
    bound: (totals) => key(totals.power, totals.skill) * (1 + 1e-12),
    interval: (_, totals) =>
        (key(totals.power, totals.skillLow), key(totals.power, totals.skill)),
    exact: (team, power, _) {
      var sum = 0.0;
      for (final (slot, member) in team.members.indexed) {
        sum += area(member, team.snaps[slot]);
      }
      final value = key(power.toDouble(), sum);
      return Exact(value, PotentialDetail(value, sum));
    },
  );
}

/// Normal-live challenge points per play: CP(rank) × rate, mean over orders;
/// ties prefer score.
ObjectiveAdapter<EventDetail> challengePointObjective(
  ObjectiveAdapter<LiveDetail> base,
  CompiledChart chart,
  EventRoute route,
) {
  double value(int rank) => (route.challengePoints[rank] ?? 0) * route.rate;
  const tie = 1 / 68719476736;
  return ObjectiveAdapter(
    skill: base.skill,
    memberBonus: (_) => 0,
    snapBonus: (_) => 0,
    bound: (totals) {
      final high = base.bound(totals);
      return value(scoreRank(chart, high)) + tie * high;
    },
    interval: (team, totals) {
      final (low, high) = base.interval(team, totals);
      return (
        value(scoreRank(chart, low)) + tie * low,
        value(scoreRank(chart, high)) + tie * high,
      );
    },
    exact: (team, power, slots) {
      final detail = base.exact(team, power, slots).detail;
      final perOrder = Float64List.fromList([
        for (final score in detail.scores.scores) value(scoreRank(chart, score)),
      ]);
      final mean = perOrder.fold(0.0, (a, b) => a + b) / perOrder.length;
      return Exact(
        mean + tie * detail.scores.mean,
        EventDetail(
          live: detail,
          perOrder: perOrder,
          mean: mean,
          bonus: 0,
          challengePoints: mean,
        ),
      );
    },
  );
}
