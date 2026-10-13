/// Gekisou team search (`engine/gekiso-objective.ts`). Given the members'
/// Gekisou context, snap Gekisou support skills add their score-ups
/// independently and live skills add theirs on top, so every slot
/// contributes additively. The members' Gekisou combo bonus couples them,
/// so the search runs once per combo bonus level: a synthetic member
/// holding that bonus for every whole combo range bounds every team of the
/// level from above, the context without Gekisou skills bounds it from
/// below, and survivors are scored by whole-live simulation. The proving pass uses safe bounds for deterministic and nominal Luck results.
library;

import 'worker_policy.dart';

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

bool _favouredDominates(EngineMaster master, List<(int, int)> skills) {
  ConditionRow? band(int id) {
    final c = master.conditions[id];
    return c?.type == 5000 ? c : null;
  }

  String shape(int group, bool flip) => jsonEncode([
    for (final set in master.conditionSets[group] ?? const <List<int>>[])
      [
        for (final id in set)
          if (band(id) case final c?)
            [5000, flip || c.positive, c.targetIds]
          else
            id,
      ],
  ]);
  for (final (id, level) in skills) {
    final rows =
        (master.gekisoSupportSkills[id]?.effects ?? const <SkillEffectRow>[])
            .where((row) => row.level == level)
            .toList();
    for (final row in rows) {
      if ([row.triggerGroup, row.releaseGroup, row.resetGroup].any(
        (group) => (master.conditionSets[group] ?? const <List<int>>[])
            .expand((set) => set)
            .any((id) => band(id) != null),
      )) {
        return false;
      }
      final negative =
          (master.conditionSets[row.conditionGroup] ?? const <List<int>>[])
              .expand((set) => set)
              .any((id) => band(id) != null && !band(id)!.positive);
      if (!negative) continue;
      final wanted = shape(row.conditionGroup, true);
      if (!rows.any(
        (other) =>
            !identical(other, row) &&
            other.type == row.type &&
            other.triggerType == row.triggerType &&
            other.executeLimit == row.executeLimit &&
            other.seconds == row.seconds &&
            other.limitCount == row.limitCount &&
            other.maxValue == row.maxValue &&
            jsonEncode(other.targetIds) == jsonEncode(row.targetIds) &&
            other.triggerGroup == row.triggerGroup &&
            other.releaseGroup == row.releaseGroup &&
            other.resetGroup == row.resetGroup &&
            other.value >= row.value &&
            shape(other.conditionGroup, false) == wanted,
      )) {
        return false;
      }
    }
  }
  return true;
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

const _contextBudget = 16 * 1024 * 1024;
int _contextBytes(String key, GekisoContext value) =>
    key.length * 2 +
    128 +
    value.judgement.lengthInBytes +
    value.gk.lengthInBytes +
    value.up.lengthInBytes +
    value.luck.lengthInBytes;
GekisoChart? _contextChart;
final _levelTags = Expando<String>();
final _weightCache = Expando<_Weights>();

class _Weights {
  _Weights(this.base, this.general, this.byJudgement, this.rush);
  final double base;
  final double rush;
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
  List<Team> initialTeams = const [],
  void Function(List<SearchHit<GekisoDetail>> hits)? onCandidate,
  bool seedOnly = false,
  bool seeded = false,
  ({int index, int count})? shard,
  double? floor,
  void Function(int done, int total)? progress,
  bool Function()? cancelled,
}) {
  computeThreadPolicy();
  final clock = Stopwatch()..start();
  double now() => clock.elapsedMicroseconds / 1000;
  final deadline = timeLimitMs ?? inf;
  bool late() => now() > deadline || (cancelled?.call() ?? false);
  double? remaining() =>
      deadline.isFinite ? math.max(1, deadline - now()) : null;
  final n = chart.notes.length;
  final count = chart.full.convertedCount;
  if (!identical(_contextChart, chart)) {
    _contextChart?.contexts.clear();
    if (_contextChart != null) _contextChart!.contextBytes = 0;
    _contextChart = chart;
  }
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

  final performerKeys = Expando<int>();
  final performerIds = chart.performerIds;
  final performerJson = chart.performerJson;
  int performerKey(Performer p) {
    final known = performerKeys[p];
    if (known != null) return known;
    final json = jsonEncode([
      p.gekisouSkill == null ? null : [p.gekisouSkill!.$1, p.gekisouSkill!.$2],
      p.missionOnly ?? 0,
      _pairs(p.gekisouSupportSkills),
      for (final field
          in p.gekisouSupportSkills.isNotEmpty ? readAll : readMembers)
        p.field(field),
    ]);
    final id = performerIds.putIfAbsent(json, () {
      performerJson.add(json);
      return performerJson.length - 1;
    });
    performerKeys[p] = id;
    return id;
  }

  int byFields(int a, int b) => performerJson[a].compareTo(performerJson[b]);
  String contextKey(List<Performer> deck) =>
      (deck.map(performerKey).toList()..sort(byFields)).join(',');
  GekisoContext contextOf(List<Performer> deck, [EngineMaster? withinMaster]) {
    final within = withinMaster ?? master;
    final tag =
        '${identical(within, master) ? 'base' : (_levelTags[within] ?? '?')}|$seedTag';
    final cache = chart.contexts[tag] ??= {};
    final keyed = stableSorted([
      for (final p in deck) (p: p, key: performerKey(p)),
    ], (a, b) => byFields(a.key, b.key));
    final key = keyed.map((item) => item.key).join(',');
    final known = cache[key];
    if (known != null) return known;
    final value = cache[key] = gekisoContext(within, chart, [
      for (final item in keyed) item.p,
    ], seeds);
    // A context holds four note-sized arrays and a search simulates
    // thousands of decks: past a fixed budget the oldest are dropped and
    // simulated again when asked for.
    chart.contextBytes += _contextBytes(key, value);
    if (chart.contextBytes > _contextBudget) {
      evict:
      for (final old in chart.contexts.values) {
        for (final oldKey in old.keys.toList()) {
          final oldValue = old[oldKey]!;
          if (identical(oldValue, value)) continue;
          old.remove(oldKey);
          chart.contextBytes -= _contextBytes(oldKey, oldValue);
          if (chart.contextBytes <= _contextBudget * 3 ~/ 4) break evict;
        }
      }
    }
    return value;
  }

  /// Linear weight of a context per unit power: `base` without live skills,
  /// prefix sums of live-factor weights.
  _Weights weights(GekisoContext ctx) => _weightCache[ctx] ??= () {
    final general = Float64List(n + 1);
    final byJudgement = [for (var j = 0; j < 3; j++) Float64List(n + 1)];
    var base = 0.0, rush = 0.0;
    final probabilities = ctx.nominal?.probabilities;
    final bonus = ctx.nominal == null ? 0 : ctx.nominal!.rushFactor - 1;
    for (var i = 0; i < n; i++) {
      final beta =
          rangeFactor[i] *
          unit *
          chart.noteFrac[i] *
          chart.judgeFrac[ctx.judgement[i]] *
          chart.comboFactor[i] *
          ctx.gk[i];
      base += beta * ctx.up[i];
      if (probabilities != null) {
        rush +=
            beta *
            (probabilities[2][i] +
                probabilities[3][i] +
                bonus * probabilities[3][i]);
      }
      final live = beta * ctx.luck[i];
      general[i + 1] = general[i] + live;
      for (var j = 0; j < 3; j++) {
        byJudgement[j][i + 1] =
            byJudgement[j][i] + (ctx.judgement[i] == j + 4 ? live : 0);
      }
    }
    return _Weights(base, general, byJudgement, rush);
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
  final luckMembers = <Performer>[];
  final luckSupports = <Performer>[];
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
  _Weights? base;
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
          base ??= weights(contextOf(const [])),
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
  bool calibrateLuck() {
    if (!chart.luck) return true;
    const baseDeck = <Performer>[];
    final memberValues = <({int i, double value})>[];
    for (var i = 0; i < members.length; i++) {
      if (now() >= deadline) return false;
      memberValues.add((
        i: i,
        value: gkMember[i].gekisouSkill != null && bonusOf[i] == 0
            ? gain([gkMember[i]], baseDeck)
            : 0.0,
      ));
    }
    final memberLuck = stableSorted(
      memberValues.where((item) => item.value > 0),
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
      if (now() >= deadline) return false;
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
    luckMembers.addAll([for (final item in memberLuck) gkMember[item.i]]);
    for (final item in supports) {
      final p = item.p;
      if (!luckChain(p)) continue;
      luckSupports.add(p);
      if (p.bandId != 0 &&
          !_favouredDominates(master, p.gekisouSupportSkills)) {
        luckSupports.add(
          p.withSupport(p.bandId == 1 ? 2 : 1, p.gekisouSupportSkills),
        );
      }
    }
    return true;
  }

  final rushFactors = <Performer, double?>{};
  double? rushFactorOf(Performer p) {
    if (!rushFactors.containsKey(p)) rushFactors[p] = rushOnlyFactor(master, p);
    return rushFactors[p];
  }

  String shapeOf(Performer p) => jsonEncode([
    p.liveSkill,
    _pairs(p.supportSkills),
    p.bandId,
    p.characterId,
    p.cardType,
    p.tagIds,
    p.liveSkillCategories,
    p.gekisouSkillCategories,
    p.gekisouMissionType,
    p.gekisouSkill == null ? null : [p.gekisouSkill!.$1, p.gekisouSkill!.$2],
    _pairs(p.gekisouSupportSkills),
    p.missionOnly,
  ]);
  final memberBases = <String, double>{};
  final dominance = <String, bool>{};
  List<Performer> strongest(Set<Performer> variants) {
    final list = variants.toList();
    if (list.length < 2) return list;
    final skills = jsonEncode(_pairs(list.first.gekisouSupportSkills));
    if (list.any((p) => jsonEncode(_pairs(p.gekisouSupportSkills)) != skills)) {
      return list;
    }
    final favoured = list
        .where((p) => p.bandId == _favouredBand(master, p.gekisouSupportSkills))
        .firstOrNull;
    if (favoured == null) return list;
    return (dominance[skills] ??= _favouredDominates(
          master,
          favoured.gekisouSupportSkills,
        ))
        ? [favoured]
        : list;
  }

  final luckBases = <String, _RefineBase>{};
  _RefineBase luckBase(List<Performer> memberDeck, List<Performer> chained) {
    final key = contextKey([...memberDeck, ...chained]);
    final known = luckBases[key];
    if (known != null) return known;
    if (luckBases.length >= 2048) luckBases.clear();
    final deck = [...memberDeck, ...chained];
    return luckBases[key] = _RefineBase(weights(contextOf(deck)), deck);
  }

  double luckSlot(_RefineBase base, int member, int snap, Criterion pick) {
    final index =
        (member * (snaps.length + 1) + snap + 1) * 3 +
        (pick == Criterion.mean
            ? 0
            : pick == Criterion.max
            ? 1
            : 2);
    final known = base.lives[index];
    if (known != null) return known;
    var value = liveWeight(slotSkill(member, snap), base.w, pick);
    final p = snap >= 0 ? supportPerformer(member, snap) : null;
    if (p != null && !luckChain(p)) {
      value += base.gains[p] ??= (() {
        final factor = rushFactorOf(p);
        return factor == null ? gain([p], base.deck) : factor * base.w.rush;
      })();
    }
    return base.lives[index] = value;
  }

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
      if (refineBases.length >= 2048) refineBases.clear();
      final deck = [for (final i in team.members) gkMember[i], ...chained];
      return _RefineBase(weights(contextOf(deck)), deck);
    }();
    var total = refineBase.w.base;
    for (final (slot, member) in team.members.indexed) {
      final snap = team.snaps[slot];
      final p = supports[slot];
      if (p != null && !(chart.luck && luckChain(p))) {
        total += refineBase.gains[p] ??= (() {
          final factor = chart.luck ? rushFactorOf(p) : null;
          return factor == null
              ? gain([p], refineBase.deck)
              : factor * refineBase.w.rush;
        })();
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
  Exact<GekisoDetail> exact(Team team, int power, {bool settle = true}) {
    final ctx = contextOf(deckOf(team));
    final skills = [
      for (final (slot, member) in team.members.indexed)
        slotSkill(member, team.snaps[slot]),
    ];
    final scores = scoreOrdersGekiso(
      master,
      chart,
      ctx,
      power,
      skills,
      settle: settle,
    );
    final key = switch (criterion) {
      Criterion.min => scores.min,
      Criterion.max => scores.max,
      Criterion.mean => scores.mean,
    };
    return Exact(key, GekisoDetail(scores, skills, ctx.seeds));
  }

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
  var proven = true;
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
  bool warm(ObjectiveAdapter<Object?> objective) {
    final excluded = constraints.excludedSnaps.toSet();
    for (var i = 0; i < members.length; i++) {
      if (now() >= deadline) return false;
      if (constraints.excludedMembers.contains(i)) continue;
      objective.skill(i, -1);
      if (!constraints.noSnaps) {
        for (var j = 0; j < snaps.length; j++) {
          if (now() >= deadline) return false;
          if (!excluded.contains(j)) objective.skill(i, j);
        }
      }
    }
    return true;
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
      memberBound: chart.luck && !surrogate
          ? (chosen, totals, left) {
              if (!readAll.every((field) => field == 'bandId')) return inf;
              final deck = [for (final i in chosen) gkMember[i]];
              final key =
                  '${(deck.map(shapeOf).toList()..sort()).join('+')}|$left';
              final base = memberBases[key] ??= (() {
                final copies = <String, List<Performer>>{};
                for (final p in luckMembers) {
                  final list = copies.putIfAbsent(shapeOf(p), () => []);
                  if (list.length < left) list.add(p);
                }
                return weights(
                  contextOf([
                    ...deck,
                    ...copies.values.expand((row) => row),
                    ...luckSupports,
                  ]),
                ).base;
              })();
              return totals.power *
                      (base + totals.skill) /
                      count *
                      (1 + relative) +
                  absolute;
            }
          : null,
      assignmentBound: chart.luck && !surrogate
          ? (team, options) {
              final memberDeck = [for (final i in team) gkMember[i]];
              Performer? chainOf(int slot, int snap) {
                final p = snap >= 0 ? supportPerformer(team[slot], snap) : null;
                return p != null && luckChain(p) ? p : null;
              }

              final chainSnaps = {
                for (var slot = 0; slot < options.length; slot++)
                  for (final snap in options[slot])
                    if (chainOf(slot, snap) != null) snap,
              };
              final pick = criterion == Criterion.max
                  ? Criterion.max
                  : Criterion.mean;
              return (totals, assigned, from) {
                final taken = assigned.take(from).toList();
                final chained = <Performer>[];
                for (final snap in chainSnaps) {
                  final at = taken.indexOf(snap);
                  if (at >= 0) {
                    final p = chainOf(at, snap);
                    if (p != null) chained.add(p);
                    continue;
                  }
                  final variants = {
                    for (var slot = from; slot < 5; slot++)
                      if (options[slot].contains(snap)) ?chainOf(slot, snap),
                  };
                  chained.addAll(strongest(variants));
                }
                final base = luckBase(memberDeck, chained);
                var value = base.w.base;
                for (var slot = 0; slot < from; slot++) {
                  value += luckSlot(base, team[slot], assigned[slot], pick);
                }
                for (var slot = from; slot < 5; slot++) {
                  var top = -inf;
                  for (final snap in options[slot]) {
                    if (snap >= 0 && taken.contains(snap)) continue;
                    top = math.max(
                      top,
                      luckSlot(
                        base,
                        team[slot],
                        chainOf(slot, snap) != null ? -1 : snap,
                        pick,
                      ),
                    );
                  }
                  value += top;
                }
                return totals.power * value / count * (1 + _refineSlack) +
                    absolute;
              };
            }
          : null,
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
  void publish() => onCandidate?.call(
    stableSorted(
      hits.values,
      (a, b) => b.key.compareTo(a.key),
    ).take(k).toList(),
  );
  GekisoSearchOutput finish() {
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

  void retainExact(Team team) {
    final power = teamPowerOf(team),
        evaluated = exact(team, teamPowerOf(team).total);
    stats.exact++;
    hits[setKey(team)] = SearchHit(
      team,
      power.total,
      power.slots,
      Totals(power: power.total.toDouble(), skill: 0),
      evaluated.key,
      evaluated.detail,
    );
    publish();
  }

  for (final team in initialTeams) {
    if (late()) break;
    retainExact(team);
  }
  if (chart.luck && hits.isEmpty && now() < deadline) {
    final feasible = searchTeams<Object?>(
      master: master,
      player: player,
      members: members,
      snaps: snaps,
      music: music,
      objective: ObjectiveAdapter(
        skill: (_, _) => (0, 0),
        memberBonus: (i) => bonusOf[i],
        snapBonus: (_) => 0,
        bound: (_) => 0,
        interval: (_, _) => (0, 0),
        exact: (_, _, _) => Exact(0, null),
        preferSnap: (_, snap) => snap < 0 ? 1 : 0,
        preferMember: (i) {
          final skill = gkMember[i].gekisouSkill;
          return skill == null
              ? 0
              : -(master.gekisoSkills[skill.$1]?.effects ??
                        const <SkillEffectRow>[])
                    .where(
                      (row) =>
                          row.level == skill.$2 &&
                          row.type >= 11000 &&
                          row.type <= 11005,
                    )
                    .length
                    .toDouble();
        },
      ),
      constraints: constraints,
      k: 1,
      timeLimitMs: math.min(100, deadline - now()),
    );
    if (feasible.hits.isNotEmpty && now() < deadline) {
      retainExact(feasible.hits.first.team);
    }
  }
  if (now() >= deadline || !calibrateLuck()) {
    proven = false;
    return finish();
  }
  bool ownsLuckSet(List<int> team) {
    final key = ([
      for (final i in team) performerJson[performerKey(gkMember[i])],
    ]..sort()).join('|');
    var hash = 0x811c9dc5;
    for (final code in key.codeUnits) {
      hash = ((hash ^ code) * 0x01000193) & 0xffffffff;
    }
    return hash % shard!.count == shard.index;
  }

  final cachedSeeds = seeded
      ? <SearchHit<GekisoDetail>>[]
      : chart.seeded[seedKey] as List<SearchHit<GekisoDetail>>?;
  if (cachedSeeds != null) {
    for (final hit in cachedSeeds) {
      final key = setKey(hit.team);
      if (!hits.containsKey(key) || hits[key]!.key < hit.key) hits[key] = hit;
    }
  } else {
    final pool = <String, ({Team team, double value})>{};
    for (final level in grid.reversed) {
      if (late()) break;
      final surrogate = objectiveFor(level, true);
      if (!warm(surrogate)) break;
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
    var ranked = stableSorted(
      pool.values,
      (a, b) => b.value.compareTo(a.value),
    ).take(chart.luck ? math.max(120, k * 12) : math.max(60, k * 12)).toList();
    final upper = <Team, double>{};
    if (chart.luck && settleSlack(chart) > 0) {
      for (final item in ranked) {
        if (late()) break;
        upper[item.team] = exact(
          item.team,
          teamPowerOf(item.team).total,
          settle: false,
        ).key;
      }
      ranked = stableSorted(
        ranked.where((item) => upper.containsKey(item.team)),
        (a, b) => upper[b.team]!.compareTo(upper[a.team]!),
      );
    }
    double kth() {
      final keys = ([for (final hit in hits.values) hit.key]
        ..sort((a, b) => b.compareTo(a)));
      return keys.length >= k ? keys[k - 1] : -inf;
    }

    for (final item in ranked) {
      if (late()) break;
      final team = item.team;
      if (chart.luck && settleSlack(chart) > 0 && upper[team]! <= kth()) break;
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
      publish();
    }
    if (!late()) {
      if (chart.seeded.length > 8) chart.seeded.clear();
      chart.seeded[seedKey] = [...hits.values];
    }
  }

  if (seedOnly) {
    proven = false;
    return finish();
  }
  for (final (index, level) in levels.indexed) {
    progress?.call(index, levels.length);
    if (late()) {
      proven = false;
      break;
    }
    final objective = objectiveFor(level, false);
    if (!warm(objective)) {
      proven = false;
      break;
    }
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
      shard: chart.luck && shard != null && shard.count > 1 ? null : shard,
      owns: chart.luck && shard != null && shard.count > 1 ? ownsLuckSet : null,
      onCandidate: (candidates) {
        for (final hit in candidates) {
          final detail = hit.detail;
          if (detail == null) continue;
          final key = setKey(hit.team);
          if (hits[key] == null || hits[key]!.key < hit.key) {
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
        publish();
      },
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
