/// Gekisou team search (`engine/gekiso-objective.ts`). Given the members'
/// Gekisou context, snap Gekisou support skills add their score-ups
/// independently and live skills add theirs on top, so every slot
/// contributes additively. The members' Gekisou combo bonus couples them,
/// so the search runs once per combo bonus level: a synthetic member
/// holding that bonus for every whole combo range bounds every team of the
/// level from above, the context without Gekisou skills bounds it from
/// below, and survivors are scored by whole-live simulation. A completed
/// search is proven, except with luck ranges, whose lottery expectation
/// the bounds only estimate.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'full/conditions.dart';
import 'full/gekisou.dart' show missionAll, missionCombo;
import 'full/play.dart' show performer;
import 'gekiso.dart';
import 'live.dart';
import 'master.dart';
import 'model.dart' show lowerIndex;
import 'num.dart';
import 'objectives.dart';
import 'power.dart';
import 'search.dart';
import 'skills.dart';

class GekisoDetail {
  GekisoDetail(this.scores, this.skills, this.seeds);
  final OrderScores scores;
  final List<SlotSkill> skills;

  /// Lottery seeds averaged (1: deterministic).
  final int seeds;
}

const _syntheticSkill = -1;

/// Relative slack of the additive estimate (measured: under 4e-5).
const _refineSlack = 1e-4;

List<List<int>> _pairs(List<(int, int)> skills) => [
  for (final (id, level) in skills) [id, level],
];

/// The band a support's formation condition favours (0 when it has none).
int _favouredBand(EngineMaster master, List<(int, int)> skills) {
  for (final (id, level) in skills) {
    for (final row
        in master.gekisoSupportSkills[id]?.effects ??
            const <SkillEffectRow>[]) {
      if (row.level != level) continue;
      for (final set
          in master.conditionSets[row.conditionGroup] ?? const <List<int>>[]) {
        for (final cid in set) {
          final condition = master.conditions[cid];
          if (condition?.type != 5000 || !condition!.positive) continue;
          for (final target in condition.targetIds) {
            final band = master.targets[target]?.bandId ?? 0;
            if (band != 0) return band;
          }
        }
      }
    }
  }
  return 0;
}

/// Performer attributes any Gekisou skill condition reads.
List<String> _readAttributes(EngineMaster master, bool all) {
  final out = <String>{};
  final groups = <int>{};
  final cumulative = <int>{};
  for (final table in [
    master.gekisoSkills,
    if (all) master.gekisoSupportSkills,
  ]) {
    for (final skill in table.values) {
      for (final row in skill.effects) {
        for (final group in [
          row.triggerGroup,
          row.conditionGroup,
          row.releaseGroup,
          row.resetGroup,
        ]) {
          if (group != 0) groups.add(group);
        }
        if (row.cumulativeId != 0) cumulative.add(row.cumulativeId);
      }
    }
  }
  void note(List<int> targetIds) {
    for (final id in targetIds) {
      final t = master.targets[id];
      if (t == null) continue;
      if (t.bandId != 0) out.add('bandId');
      if (t.cardType != 0) out.add('cardType');
      if (t.characterId != 0) out.add('characterId');
      if (t.tagId != 0) out.add('tagIds');
      if (t.liveSkillCategories.isNotEmpty) out.add('liveSkillCategories');
      if (t.gekisouSkillCategories.isNotEmpty) {
        out.add('gekisouSkillCategories');
      }
      if (t.gekisouMissionType != 0) out.add('gekisouMissionType');
    }
  }

  for (final group in groups) {
    for (final set in master.conditionSets[group] ?? const <List<int>>[]) {
      for (final id in set) {
        final c = master.conditions[id];
        if (c != null && (c.type == 5000 || c.type == 3000 || c.type == 3001)) {
          note(c.targetIds);
        }
      }
    }
  }
  for (final id in cumulative) {
    final c = master.cumulative[id];
    if (c == null) continue;
    if (c.type == 3000 || c.type == 3001) note(c.targetIds);
    if (c.type == 3002 || c.type == 3003 || c.type == 3004) out.add('bandId');
    if (c.type == 3005) out.add('cardType');
  }
  return out.toList()..sort();
}

/// A sustained Gekisou combo bonus row that runs for whole combo ranges.
SkillEffectRow? _comboTemplate(EngineMaster master) {
  for (final skill in master.gekisoSkills.values) {
    if (skill.missionType != missionCombo) continue;
    for (final row in skill.effects) {
      if (row.type != 12000 ||
          row.triggerType != 2 ||
          row.conditionGroup != 0) {
        continue;
      }
      final sets =
          master.conditionSets[row.triggerGroup] ?? const <List<int>>[];
      final playing =
          sets.length == 1 &&
          sets[0].length == 1 &&
          master.conditions[sets[0][0]]?.type == 7020;
      if (playing) return row;
    }
  }
  return null;
}

final _levelTags = Expando<String>();
final _weightCache = Expando<_Weights>();
final _performerKeys = Expando<String>();

class _Weights {
  _Weights(this.base, this.general, this.byJudgement);
  final double base;
  final Float64List general;
  final List<Float64List> byJudgement;
}

class _RefineBase {
  _RefineBase(this.w, this.deck);
  final _Weights w;
  final List<Performer> deck;
  final gains = <Performer, double>{};
  final lives = <int, double>{};
}

class GekisoSearchOutput extends SearchOutput<GekisoDetail> {
  GekisoSearchOutput(
    super.hits,
    super.proven,
    super.bound,
    super.stats,
    this.levels,
  );
  final int levels;
}

GekisoSearchOutput gekisoSearch({
  required EngineMaster master,
  required PlayerState player,
  required List<MemberState> members,
  required List<SnapState> snaps,
  required MusicView? music,
  required GekisoChart chart,
  required List<int> seeds,
  required Criterion criterion,
  required Constraints constraints,
  required int k,
  double? timeLimitMs,
  ({int index, int count})? shard,
  double? floor,
  void Function(int done, int total)? progress,
  bool Function()? cancelled,
}) {
  final clock = Stopwatch()..start();
  double now() => clock.elapsedMicroseconds / 1000;
  final n = chart.notes.length;
  final count = chart.full.convertedCount;
  final unit = master.live.adjustment * chart.difficultyFactor;
  final rangeFactor = Float64List.fromList([
    for (final r in chart.rangeOf)
      r >= 0 ? 1 + chart.rangePercent[r] / 100 : 1.0,
  ]);
  final missions = chart.setup.missions.take(chart.full.fevers.length).toList();
  final comboRanges = missions.any((m) => m == missionCombo || m == missionAll);
  final seedTag = seeds.join(',');
  final readAll = _readAttributes(master, true);
  final readMembers = _readAttributes(master, false);

  GekisoContext contextOf(List<Performer> deck, [EngineMaster? withinMaster]) {
    final within = withinMaster ?? master;
    final tag =
        '${identical(within, master) ? 'base' : (_levelTags[within] ?? '?')}|$seedTag';
    final cache = chart.contexts[tag] ??= {};
    final keyed = stableSorted([
      for (final p in deck)
        (
          p: p,
          key: _performerKeys[p] ??= jsonEncode([
            p.gekisouSkill == null
                ? null
                : [p.gekisouSkill!.$1, p.gekisouSkill!.$2],
            p.missionOnly ?? 0,
            _pairs(p.gekisouSupportSkills),
            for (final field
                in p.gekisouSupportSkills.isNotEmpty ? readAll : readMembers)
              p.field(field),
          ]),
        ),
    ], (a, b) => a.key.compareTo(b.key));
    final key = keyed.map((item) => item.key).join('|');
    return cache[key] ??= gekisoContext(within, chart, [
      for (final item in keyed) item.p,
    ], seeds);
  }

  /// Linear weight of a context per unit power: `base` without live skills,
  /// prefix sums of live-factor weights.
  _Weights weights(GekisoContext ctx) => _weightCache[ctx] ??= () {
    final general = Float64List(n + 1);
    final byJudgement = [for (var j = 0; j < 3; j++) Float64List(n + 1)];
    var base = 0.0;
    for (var i = 0; i < n; i++) {
      final beta =
          rangeFactor[i] *
          unit *
          chart.noteFrac[i] *
          chart.judgeFrac[ctx.judgement[i]] *
          chart.comboFactor[i] *
          ctx.gk[i];
      base += beta * ctx.up[i];
      final live = beta * ctx.luck[i];
      general[i + 1] = general[i] + live;
      for (var j = 0; j < 3; j++) {
        byJudgement[j][i + 1] =
            byJudgement[j][i] + (ctx.judgement[i] == j + 4 ? live : 0);
      }
    }
    return _Weights(base, general, byJudgement);
  }();
  double gain(
    List<Performer> deck,
    List<Performer> ref, [
    EngineMaster? within,
  ]) =>
      weights(contextOf([...ref, ...deck], within)).base -
      weights(contextOf(ref, within)).base;

  // A Gekisou skill runs only in ranges of its mission: one of another
  // mission still lets the member's snap support skills run.
  final songMissions = missions.toSet();
  final hasGekiso = [
    for (final m in members) performer(master, m, null).gekisouSkill != null,
  ];
  final gkMember = [
    for (final m in members)
      () {
        final p = performer(master, m, null).gekisoOnly;
        final skill = p.gekisouSkill;
        if (skill == null) return p;
        final mission = master.gekisoSkills[skill.$1]?.missionType ?? 0;
        if (mission == missionAll || songMissions.contains(mission)) return p;
        return Performer.empty(missionOnly: mission != 0 ? mission : 1);
      }(),
  ];
  // A support runs only in ranges of its own mission; its formation
  // condition reads the member's band, so the band reduces to "favoured or not".
  final supportPerformers = <String, Performer>{};
  final supportBySlot = <int, Performer?>{};
  Performer? supportPerformerOf(int member, int snap) {
    final p = performer(master, members[member], snaps[snap]);
    if (p.gekisouSupportSkills.isEmpty) return null;
    final runs = p.gekisouSupportSkills.any((skill) {
      final mission = master.gekisoSupportSkills[skill.$1]?.missionType ?? 0;
      return mission == missionAll ||
          songMissions.contains(mission) ||
          songMissions.contains(missionAll);
    });
    if (!runs) return null;
    final bandOnly = readAll.length == 1 && readAll[0] == 'bandId';
    final favoured = _favouredBand(master, p.gekisouSupportSkills);
    final bandId = bandOnly && favoured != 0
        ? (p.bandId == favoured
              ? favoured
              : favoured == 1
              ? 2
              : 1)
        : p.bandId;
    final key = jsonEncode([
      _pairs(p.gekisouSupportSkills),
      bandOnly ? bandId : [p.bandId, p.cardType, p.characterId],
    ]);
    return supportPerformers[key] ??= bandOnly
        ? Performer.empty(
            bandId: bandId,
            missionOnly: 1,
            gekisouSupportSkills: p.gekisouSupportSkills,
          )
        : p.supportOnly;
  }

  Performer? supportPerformer(int member, int snap) {
    if (snap < 0 || !hasGekiso[member]) return null;
    final index = member * snaps.length + snap;
    if (supportBySlot.containsKey(index)) return supportBySlot[index];
    return supportBySlot[index] = supportPerformerOf(member, snap);
  }

  /// Each member's largest Gekisou combo bonus (0 without combo ranges).
  final bonusOf = [
    for (var i = 0; i < members.length; i++)
      () {
        final own = gkMember[i].gekisouSkill;
        if (!comboRanges || own == null) return 0;
        final skill = master.gekisoSkills[own.$1];
        if (skill == null ||
            (skill.missionType != missionCombo &&
                skill.missionType != missionAll)) {
          return 0;
        }
        var best = 0;
        for (final row in skill.effects) {
          if (row.level == own.$2 && row.type == 12000) {
            best = math.max(best, row.value);
          }
        }
        return best;
      }(),
  ];
  final template = comboRanges ? _comboTemplate(master) : null;
  // Highest reachable level: the best bonus per character, five characters.
  final bestPerCharacter = <int, int>{};
  for (final (i, m) in members.indexed) {
    bestPerCharacter[m.card.characterId] = math.max(
      bestPerCharacter[m.card.characterId] ?? 0,
      bonusOf[i],
    );
  }
  final maxLevel = template != null
      ? (bestPerCharacter.values.toList()..sort((a, b) => b - a))
            .take(5)
            .fold(0, (a, b) => a + b)
      : 0;

  // Luck: the strongest luck members and supports at once raise every rush
  // skill's odds; the estimate uses them.
  final luckDeck = <Performer>[];
  if (chart.luck) {
    const baseDeck = <Performer>[];
    final memberLuck = stableSorted(
      [
        for (var i = 0; i < members.length; i++)
          (
            i: i,
            value: gkMember[i].gekisouSkill != null && bonusOf[i] == 0
                ? gain([gkMember[i]], baseDeck)
                : 0.0,
          ),
      ].where((item) => item.value > 0),
      (a, b) => b.value.compareTo(a.value),
    );
    final characters = <int>{};
    for (final item in memberLuck) {
      final character = members[item.i].card.characterId;
      if (characters.contains(character) || characters.length == 5) continue;
      characters.add(character);
      luckDeck.add(gkMember[item.i]);
    }
    final seen = <String>{};
    final supports = <({Performer p, double value})>[];
    for (final snap in snaps) {
      final skills = [
        for (final (index, id) in snap.card.gekisoSupportSkillIds.indexed)
          if (id != 0)
            (
              id,
              index < snap.gekisoSkillLevels.length
                  ? snap.gekisoSkillLevels[index]
                  : 1,
            ),
      ];
      final key = jsonEncode(_pairs(skills));
      if (skills.isEmpty || !seen.add(key)) continue;
      final p = Performer.empty(
        bandId: _favouredBand(master, skills),
        missionOnly: 1,
        gekisouSupportSkills: skills,
      );
      supports.add((p: p, value: gain([p], baseDeck)));
    }
    for (final item in stableSorted(
      supports,
      (a, b) => b.value.compareTo(a.value),
    ).take(5)) {
      luckDeck.add(item.p);
    }
  }

  final slotSkills = <int, SlotSkill>{};
  SlotSkill slotSkill(int member, int snap) =>
      slotSkills[member * (snaps.length + 1) + snap + 1] ??= resolveSlotSkill(
        master,
        members[member],
        snap < 0 ? null : snaps[snap],
      );
  final eventTimes = [for (final (_, time) in chart.full.events) time];
  int lower(int time) => lowerIndex(chart.times, time);
  Float64List eventWeights(SlotSkill skill, _Weights w) {
    final perEvent = Float64List(5);
    for (var event = 0; event < math.min(5, eventTimes.length); event++) {
      for (final effect in skill.effects) {
        if (effect.gate.blocks(master.live.lifeBase)) continue;
        final start = lower(eventTimes[event]);
        final end = lower(
          eventTimes[event] + windowMs(effect.seconds, skill.extensionMs),
        );
        final factor = effect.delta / 100000;
        if (effect.type == 2000) {
          perEvent[event] += factor * (w.general[end] - w.general[start]);
        } else {
          for (final j in effect.judgements) {
            if (j >= 4 && j <= 6) {
              perEvent[event] +=
                  factor *
                  (w.byJudgement[j - 4][end] - w.byJudgement[j - 4][start]);
            }
          }
        }
      }
    }
    return perEvent;
  }

  double liveWeight(SlotSkill skill, _Weights w, Criterion pick) {
    final perEvent = eventWeights(skill, w);
    if (pick == Criterion.max) return perEvent.reduce(math.max);
    if (pick == Criterion.min) return perEvent.reduce(math.min);
    return perEvent.fold(0.0, (a, b) => a + b) / 5;
  }

  // Lower bounds: no Gekisou member skills, each support alone.
  final base = weights(contextOf(const []));
  final supportLow = <String, double>{};
  double lowOf(int member, int snap) {
    final p = supportPerformer(member, snap);
    var support = 0.0;
    if (p != null) {
      final key = jsonEncode([_pairs(p.gekisouSupportSkills), p.bandId]);
      support = supportLow[key] ??= math.max(0, gain([p], const []));
    }
    return liveWeight(
          slotSkill(member, snap),
          base,
          criterion == Criterion.min ? Criterion.min : Criterion.mean,
        ) +
        support;
  }

  const relative = 3e-6;
  final absolute = n + 4;
  List<Performer> deckOf(Team team) => [
    for (final (slot, member) in team.members.indexed)
      () {
        final support = supportPerformer(member, team.snaps[slot]);
        return support != null
            ? gkMember[member].withSupport(
                support.bandId,
                support.gekisouSupportSkills,
              )
            : gkMember[member];
      }(),
  ];
  // Supports that change the lottery itself (gauge, guarantees).
  final chainCache = <Performer, bool>{};
  bool luckChain(Performer p) => chainCache[p] ??= p.gekisouSupportSkills.any(
    (skill) =>
        (master.gekisoSupportSkills[skill.$1]?.effects ??
                const <SkillEffectRow>[])
            .any(
              (row) =>
                  row.level == skill.$2 &&
                  row.type >= 11000 &&
                  row.type <= 11005,
            ),
  );
  final refineBases = <String, _RefineBase>{};
  final supportIds = <Performer, int>{};
  double refine(Team team, double power) {
    final supports = [
      for (final (slot, member) in team.members.indexed)
        supportPerformer(member, team.snaps[slot]),
    ];
    // With luck ranges the lottery-changing supports join the base.
    final chained = chart.luck
        ? [
            for (final p in supports)
              if (p != null && luckChain(p)) p,
          ]
        : const <Performer>[];
    var key = ([...team.members]..sort()).join(',');
    if (chained.isNotEmpty) {
      final ids = [for (final p in chained) supportIds[p] ??= supportIds.length]
        ..sort();
      key += '|${ids.join(',')}';
    }
    final refineBase = refineBases[key] ??= () {
      final deck = [for (final i in team.members) gkMember[i], ...chained];
      return _RefineBase(weights(contextOf(deck)), deck);
    }();
    var total = refineBase.w.base;
    for (final (slot, member) in team.members.indexed) {
      final snap = team.snaps[slot];
      final p = supports[slot];
      if (p != null && !(chart.luck && luckChain(p))) {
        total += refineBase.gains[p] ??= gain([p], refineBase.deck);
      }
      final index = member * (snaps.length + 1) + snap + 1;
      total += refineBase.lives[index] ??= liveWeight(
        slotSkill(member, snap),
        refineBase.w,
        criterion,
      );
    }
    return power * total / count;
  }

  final stats = SearchStats();
  Exact<GekisoDetail> exact(Team team, int power) {
    final ctx = contextOf(deckOf(team));
    final skills = [
      for (final (slot, member) in team.members.indexed)
        slotSkill(member, team.snaps[slot]),
    ];
    final scores = scoreOrdersGekiso(master, chart, ctx, power, skills);
    final key = switch (criterion) {
      Criterion.min => scores.min,
      Criterion.max => scores.max,
      Criterion.mean => scores.mean,
    };
    return Exact(key, GekisoDetail(scores, skills, ctx.seeds));
  }

  final deadline = timeLimitMs != null && timeLimitMs > 0 ? timeLimitMs : inf;
  bool late() => now() > deadline || (cancelled?.call() ?? false);
  double? remaining() =>
      deadline.isFinite ? math.max(1, deadline - now()) : null;

  /// Exact power of a complete team (leader first).
  TeamPower teamPowerOf(Team team) => teamPower(
    master,
    player,
    [for (final i in team.members) members[i]],
    [for (final j in team.snaps) j < 0 ? null : snaps[j]],
    0,
    music,
  );
  final levels = maxLevel > 0
      ? [for (var level = maxLevel; level >= 0; level--) level]
      : [0];
  final hits = <String, SearchHit<GekisoDetail>>{};
  String setKey(Team team) =>
      ([for (final i in team.members) members[i].key]..sort()).join('|');
  var proven = !chart.luck;
  double? bound;
  // Support gains on a coarse level grid: a gain at a higher level bounds
  // every lower one.
  final grid = maxLevel > 0
      ? ({
          0,
          (maxLevel / 4).ceil(),
          (maxLevel / 2).ceil(),
          (3 * maxLevel / 4).ceil(),
          maxLevel,
        }.toList()..sort())
      : [0];
  final levelData =
      <int, ({EngineMaster within, List<Performer> deck, _Weights weights})>{};
  ({EngineMaster within, List<Performer> deck, _Weights weights}) levelOf(
    int level,
  ) => levelData[level] ??= () {
    final within = level > 0 && template != null
        ? master.withGekisoSkills({
            ...master.gekisoSkills,
            _syntheticSkill: GekisoSkill(missionCombo, [
              template.copyWith(id: 2000000000 + level, level: 1, value: level),
            ]),
          })
        : master;
    if (!identical(within, master)) _levelTags[within] = 'L$level';
    final deck = <Performer>[
      ...luckDeck,
      if (level > 0 && template != null)
        Performer.empty(
          gekisouSkill: (_syntheticSkill, 1),
          gekisouMissionType: missionCombo,
        ),
    ];
    return (
      within: within,
      deck: deck,
      weights: weights(contextOf(deck, within)),
    );
  }();
  final supportHigh = <String, double>{};
  final supportHighBySlot = <int, double>{};
  double supportHighAt(Performer p, int at) =>
      supportHigh[jsonEncode([
        _pairs(p.gekisouSupportSkills),
        p.bandId,
        at,
      ])] ??= () {
        final data = levelOf(at);
        return math.max(0.0, gain([p], data.deck, data.within));
      }();
  double supportHighOf(int member, int snap, int level) {
    final p = supportPerformer(member, snap);
    if (p == null) return 0;
    final at = grid.where((g) => g >= level).firstOrNull ?? maxLevel;
    final index = (member * snaps.length + snap) * (maxLevel + 1) + at;
    return supportHighBySlot[index] ??= supportHighAt(p, at);
  }

  /// Fills an objective's per-slot caches before a timed search starts.
  void warm(ObjectiveAdapter<Object?> objective) {
    final excluded = constraints.excludedSnaps.toSet();
    for (var i = 0; i < members.length; i++) {
      if (constraints.excludedMembers.contains(i)) continue;
      objective.skill(i, -1);
      if (!constraints.noSnaps) {
        for (var j = 0; j < snaps.length; j++) {
          if (!excluded.contains(j)) objective.skill(i, j);
        }
      }
    }
  }

  Constraints levelConstraints(int level) => Constraints(
    requiredMembers: constraints.requiredMembers,
    excludedMembers: constraints.excludedMembers,
    requiredSnaps: constraints.requiredSnaps,
    excludedSnaps: constraints.excludedSnaps,
    leader: constraints.leader,
    bindings: constraints.bindings,
    noSnaps: constraints.noSnaps,
    minBonus: maxLevel > 0 ? level.toDouble() : constraints.minBonus,
    maxBonus: maxLevel > 0 ? level.toDouble() : null,
  );
  ObjectiveAdapter<GekisoDetail?> objectiveFor(int level, bool surrogate) {
    final data = levelOf(level);
    final ranges = <int, (double, double)>{};
    final orderRows = <int, ({Float64List perEvent, double best})>{};
    int slotIndex(int member, int snap) =>
        member * (snaps.length + 1) + snap + 1;
    ({Float64List perEvent, double best}) orderOf(int member, int snap) =>
        orderRows[slotIndex(member, snap)] ??= () {
          final perEvent = eventWeights(slotSkill(member, snap), data.weights);
          return (perEvent: perEvent, best: perEvent.reduce(math.max));
        }();
    double high(Totals totals) =>
        totals.power *
            (data.weights.base + totals.skill) /
            count *
            (1 + relative) +
        absolute;
    return ObjectiveAdapter(
      skill: (member, snap) => ranges[slotIndex(member, snap)] ??= () {
        final top =
            liveWeight(
              slotSkill(member, snap),
              data.weights,
              criterion == Criterion.max ? Criterion.max : Criterion.mean,
            ) +
            supportHighOf(member, snap, level);
        return (surrogate ? top : lowOf(member, snap), top);
      }(),
      memberBonus: (member) => bonusOf[member],
      snapBonus: (_) => 0,
      bound: high,
      // Best order: the five live skills take distinct events.
      leafBound: criterion == Criterion.max && !surrogate
          ? (team, totals) {
              final rows = [
                for (final (slot, member) in team.members.indexed)
                  orderOf(member, team.snaps[slot]),
              ];
              final separate = rows.fold(0.0, (sum, row) => sum + row.best);
              return high(
                totals.copyWith(
                  skill:
                      totals.skill -
                      separate +
                      bestOrder5([for (final row in rows) row.perEvent]),
                ),
              );
            }
          : null,
      productBase: data.weights.base,
      interval: (team, totals) {
        if (surrogate) return (high(totals), high(totals));
        // The additive estimate is within a few 1e-5 of the whole-live mean.
        final slack = chart.accuracy.great > 0
            ? 10 * _refineSlack
            : _refineSlack;
        final value = refine(team, totals.power);
        return (
          math.max(0, value * (1 - slack) - absolute),
          math.max(
            math.min(high(totals), value * (1 + slack) + absolute),
            value * (1 + slack),
          ),
        );
      },
      exact: (team, power, slotPowers) {
        if (surrogate) {
          return Exact(high(Totals(power: power.toDouble(), skill: 0)), null);
        }
        stats.exact++;
        final result = exact(team, power);
        return Exact(result.key, result.detail);
      },
    );
  }

  // Seeding: the best teams of each level by its optimistic values, scored
  // exactly, so the proving pass starts from a threshold near the optimum.
  final seedKey = [
    members.map((m) => m.key).join(','),
    snaps.map((x) => x.key).join(','),
    criterion.name,
    k,
    constraints.requiredMembers,
    constraints.excludedMembers,
    constraints.requiredSnaps,
    constraints.excludedSnaps,
    constraints.leader,
    constraints.bindings,
    constraints.noSnaps,
    seeds,
  ].join('|');
  // Luck charts are ranked by the whole-pool estimate, which ignores leader
  // shards: one shard does it.
  if (chart.luck && shard != null && shard.index != 0) {
    stats.elapsedMs = now();
    return GekisoSearchOutput([], false, null, stats, levels.length);
  }
  final seeded = chart.seeded[seedKey] as List<SearchHit<GekisoDetail>>?;
  if (seeded != null) {
    for (final hit in seeded) {
      hits[setKey(hit.team)] = hit;
    }
  } else {
    final pool = <String, ({Team team, double value})>{};
    for (final level in grid.reversed) {
      if (late()) break;
      final surrogate = objectiveFor(level, true);
      warm(surrogate);
      double teamSkill(Team team) {
        var sum = 0.0;
        for (final (slot, member) in team.members.indexed) {
          sum += surrogate.skill(member, team.snaps[slot]).$2;
        }
        return sum;
      }

      final out = searchTeams<GekisoDetail?>(
        master: master,
        player: player,
        members: members,
        snaps: snaps,
        music: music,
        objective: ObjectiveAdapter(
          skill: surrogate.skill,
          memberBonus: surrogate.memberBonus,
          snapBonus: surrogate.snapBonus,
          bound: surrogate.bound,
          leafBound: surrogate.leafBound,
          productBase: surrogate.productBase,
          interval: surrogate.interval,
          exact: (team, power, _) => Exact(
            surrogate.bound(
              Totals(power: power.toDouble(), skill: teamSkill(team)),
            ),
            null,
          ),
        ),
        constraints: levelConstraints(level),
        // Luck charts rank on this estimate, so it runs to completion and
        // keeps a deeper pool for the exact rescoring below.
        k: chart.luck ? math.max(k * 12, 120) : math.max(k * 3, 16),
        timeLimitMs: chart.luck
            ? remaining()
            : math.min(400.0, remaining() ?? 400.0),
        cancelled: cancelled,
      );
      for (final hit in out.hits) {
        pool['${setKey(hit.team)}#${hit.team.snaps.join(',')}'] = (
          team: hit.team,
          value: hit.key,
        );
      }
    }
    // The optimistic values overrate some teams by a few percent: score the
    // most promising ones exactly.
    final ranked = stableSorted(
      pool.values,
      (a, b) => b.value.compareTo(a.value),
    ).take(chart.luck ? math.max(120, k * 12) : math.max(60, k * 12));
    for (final item in ranked) {
      if (late()) break;
      final team = item.team;
      final power = teamPowerOf(team);
      final result = exact(team, power.total);
      stats.exact++;
      final hitKey = setKey(team);
      final previous = hits[hitKey];
      if (previous == null || previous.key < result.key) {
        hits[hitKey] = SearchHit(
          team,
          power.total,
          power.slots,
          Totals(power: power.total.toDouble(), skill: 0),
          result.key,
          result.detail,
        );
      }
    }
    if (!late()) {
      if (chart.seeded.length > 8) chart.seeded.clear();
      chart.seeded[seedKey] = [...hits.values];
    }
  }

  // Luck ranges: the exact rescoring of the estimate's best teams above is
  // the result.
  for (final (index, level) in (chart.luck ? const <int>[] : levels).indexed) {
    progress?.call(index, levels.length);
    if (late()) {
      proven = false;
      break;
    }
    final objective = objectiveFor(level, false);
    warm(objective);
    final best = stableSorted(
      hits.values,
      (a, b) => b.key.compareTo(a.key),
    ).take(k).toList();
    // The k-th best of every level so far is the floor any team must beat.
    final levelFloor = math.max(
      floor ?? -inf,
      best.length >= k ? best[k - 1].key : -inf,
    );
    final out = searchTeams<GekisoDetail?>(
      shard: shard,
      master: master,
      player: player,
      members: members,
      snaps: snaps,
      music: music,
      objective: objective,
      constraints: levelConstraints(level),
      k: k,
      seeds: [for (final hit in best) hit.team],
      floor: levelFloor.isFinite ? levelFloor : null,
      timeLimitMs: remaining(),
      cancelled: cancelled,
    );
    stats
      ..leaders += out.stats.leaders
      ..memberNodes += out.stats.memberNodes
      ..snapNodes += out.stats.snapNodes
      ..candidates += out.stats.candidates;
    if (!out.proven) {
      proven = false;
      bound = math.max(bound ?? -inf, out.bound ?? -inf);
    }
    for (final hit in out.hits) {
      final detail = hit.detail;
      if (detail == null) continue;
      final key = setKey(hit.team);
      final previous = hits[key];
      if (previous == null || previous.key < hit.key) {
        hits[key] = SearchHit(
          hit.team,
          hit.power,
          hit.slotPowers,
          hit.totals,
          hit.key,
          detail,
        );
      }
    }
  }
  stats.elapsedMs = now();
  return GekisoSearchOutput(
    stableSorted(
      hits.values,
      (a, b) => b.key.compareTo(a.key),
    ).take(k).toList(),
    proven,
    bound,
    stats,
    levels.length,
  );
}
