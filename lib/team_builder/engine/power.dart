/// Exact deck power (CardParameterCalculator) split into additive per-slot
/// terms. One stat point is 10 000 BP; percentages use 10 000 BP = 100 %.
/// Float steps are binary32. A port of `team-builder/engine/power.ts`.
library;

import 'dart:math' as math;

import 'master.dart';
import 'num.dart';

typedef BP3 = List<int>;

int _floorF32Div(num numerator) =>
    (f(f(numerator) / 10000)).floorToDouble().toInt();

class PlayerState {
  PlayerState({
    required this.characterRanks,
    required this.totalRank,
    required this.bandItems,
    required this.vipRank,
    required this.characterMemory,
    required this.musicMemory,
  });

  /// character → rank; absent characters count as rank 1.
  final Map<int, int> characterRanks;
  final int totalRank;
  final Map<int, int> bandItems;
  final int vipRank;

  /// Direct points per component, from character and song memories.
  final Map<int, int> characterMemory;
  final Map<int, int> musicMemory;
}

class MemberGrowth {
  MemberGrowth(
    this.level,
    this.awake,
    this.rank,
    this.liveSkillLevel,
    this.gekisoSkillLevel,
  );
  final int level;
  final int awake;
  final int rank;
  final int liveSkillLevel;
  final int gekisoSkillLevel;
}

class SnapGrowth {
  SnapGrowth(this.level, this.rank);
  final int level;
  final int rank;
}

class MemberState {
  MemberState({
    required this.key,
    required this.card,
    required this.growth,
    required this.leaderSkillLevel,
    required this.musicTypeRate,
    required this.musicTagRate,
    required this.own,
    required this.liveSkillCategories,
    required this.gekisoSkillCategories,
    required this.gekisoMissionType,
  });
  final String key;
  final MemberCard card;
  final MemberGrowth growth;
  final int leaderSkillLevel;
  final int musicTypeRate;
  final int musicTagRate;

  /// Level + awake + rank stats, BP.
  final BP3 own;
  final List<int> liveSkillCategories;
  final List<int> gekisoSkillCategories;
  final int gekisoMissionType;
}

class SnapState {
  SnapState({
    required this.key,
    required this.card,
    required this.growth,
    required this.percent,
    required this.typeLinkRate,
    required this.skillLevels,
    required this.gekisoSkillLevels,
  });
  final String key;
  final SnapCard card;
  final SnapGrowth growth;

  /// Snap power bonus percentage, BP.
  final BP3 percent;
  final int typeLinkRate;
  final List<int> skillLevels;
  final List<int> gekisoSkillLevels;
}

class MusicView {
  MusicView(this.musicType, this.bestTags, this.memoryKey);
  final int musicType;
  final List<int> bestTags;
  final int memoryKey;
}

/// CardPower.mul then to_floor: trunc(a·b/10000), then binary32 floor to whole points.
BP3 pctFloor(BP3 base, List<int> pct) => [
  for (var i = 0; i < 3; i++)
    _floorF32Div((base[i] * pct[i] / 10000).truncate()) * 10000,
];
BP3 _pctUniform(BP3 base, int pct) => pctFloor(base, [pct, pct, pct]);

/// Displayed total: floor of each component's points, summed.
int points(List<int> bp) =>
    (bp[0] / 10000).floor() + (bp[1] / 10000).floor() + (bp[2] / 10000).floor();

int _maxKey(Map<int, Object?>? map) =>
    map == null || map.isEmpty ? 1 : map.keys.reduce(math.max);

int memberLevelCap(EngineMaster master, MemberCard card, int awake) {
  final cap = card.levelLimits != null
      ? card.levelLimits!['$awake']
      : master.memberLevelLimits['${card.rarity}:$awake'];
  return cap ?? _maxKey(master.memberLevels[card.levelGroup]);
}

int snapLevelCap(EngineMaster master, SnapCard card, int rank) =>
    master.snapRanks[card.rankGroup]?[rank]?.limitLevel ??
    _maxKey(master.snapLevels[card.levelGroup]);

int maxAwake(EngineMaster master, MemberCard card) =>
    math.max(1, _maxKey(master.memberAwake[card.awakeGroup]));
int maxMemberRank(EngineMaster master, MemberCard card) =>
    math.max(1, _maxKey(master.memberRanks[card.rankGroup]));
int maxSnapRank(EngineMaster master, SnapCard card) =>
    math.max(1, _maxKey(master.snapRanks[card.rankGroup]));
int maxSkillLevel(List<SkillEffectRow>? rows) =>
    (rows ?? const <SkillEffectRow>[]).fold(
      1,
      (m, row) => math.max(m, row.level),
    );

MemberState? resolveMember(
  EngineMaster master,
  String key,
  MemberCard card,
  MemberGrowth growth,
) {
  final level = master.memberLevels[card.levelGroup]?[growth.level];
  final awake =
      master.memberAwake[card.awakeGroup]?[growth.awake] ??
      (growth.awake <= 1 ? const [0, 0, 0] : null);
  final rank = master.memberRanks[card.rankGroup]?[growth.rank];
  if (level == null || awake == null || rank == null) return null;
  final max = card.statMax;
  final own = <int>[0, 0, 0];
  for (var i = 0; i < 3; i++) {
    final levelPoints = _floorF32Div(level[i] * max[i]);
    final awakePoints = f(f(awake[i] / 10000) * f(max[i])).floor();
    final rankPoints = _floorF32Div(imul(rank.rates[i], max[i]));
    own[i] = (levelPoints + awakePoints + rankPoints) * 10000;
  }
  final gekiso = master.gekisoSkills[card.gekisoSkillId];
  return MemberState(
    key: key,
    card: card,
    growth: growth,
    leaderSkillLevel: rank.leaderSkillLevel,
    musicTypeRate: rank.musicTypeRate,
    musicTagRate: rank.musicTagRate,
    own: own,
    liveSkillCategories:
        master.liveSkillCategories[card.liveSkillId] ?? const [],
    gekisoSkillCategories:
        master.gekisoSkillCategories[card.gekisoSkillId] ?? const [],
    gekisoMissionType: gekiso?.missionType ?? 0,
  );
}

SnapState? resolveSnap(
  EngineMaster master,
  String key,
  SnapCard card,
  SnapGrowth growth,
) {
  final level = master.snapLevels[card.levelGroup]?[growth.level];
  final rank = master.snapRanks[card.rankGroup]?[growth.rank];
  if (level == null || rank == null) return null;
  return SnapState(
    key: key,
    card: card,
    growth: growth,
    percent: [
      for (var i = 0; i < 3; i++) _floorF32Div(imul(level[i], card.statMax[i])),
    ],
    typeLinkRate: rank.typeLinkRate,
    skillLevels: rank.skillLevels,
    gekisoSkillLevels: rank.gekisoSkillLevels,
  );
}

/// Whether a skill target selects a member: first matching key among band,
/// type, character, tag, categories, mission.
bool isTargetMember(MemberState member, TargetRow target) {
  final card = member.card;
  if (target.bandId > 0 && target.bandId == card.bandId) return true;
  if (target.cardType != 0 && target.cardType == card.cardType) return true;
  if (target.characterId > 0 && target.characterId == card.characterId) {
    return true;
  }
  if (target.tagId > 0 && card.bestTags.contains(target.tagId)) return true;
  if (target.liveSkillCategories.isNotEmpty &&
      target.liveSkillCategories.any(member.liveSkillCategories.contains)) {
    return true;
  }
  if (target.gekisouSkillCategories.isNotEmpty &&
      target.gekisouSkillCategories.any(
        member.gekisoSkillCategories.contains,
      )) {
    return true;
  }
  return target.gekisouMissionType != 0 &&
      target.gekisouMissionType == member.gekisoMissionType;
}

bool matchesTargets(
  EngineMaster master,
  MemberState member,
  List<int> targetIds,
) {
  for (final id in targetIds) {
    final target = master.targets[id];
    if (target != null && isTargetMember(member, target)) return true;
  }
  return false;
}

void _accumulate(int type, int value, BP3 acc) {
  switch (type) {
    case 1000:
    case 1500:
      acc[0] = i32(acc[0] + value);
      acc[1] = i32(acc[1] + value);
      acc[2] = i32(acc[2] + value);
    case 1001:
    case 1501:
      acc[1] = i32(acc[1] + value);
    case 1002:
    case 1502:
      acc[2] = i32(acc[2] + value);
    case 1003:
    case 1503:
      acc[0] = i32(acc[0] + value);
  }
}

bool _isCumulative(int type) => (type & ~3) == 1500;

/// Band item percentage of a member (character, band and card-type targets).
BP3 bandItemPercent(
  EngineMaster master,
  PlayerState player,
  MemberState member,
) {
  final acc = <int>[0, 0, 0];
  final card = member.card;
  for (final entry in player.bandItems.entries) {
    final effects = master.bandItems[entry.key]?.levels[entry.value];
    if (effects == null) continue;
    for (final effect in effects) {
      for (final id in effect.targetIds) {
        final target = master.targets[id];
        if (target == null) continue;
        final hits =
            (target.bandId > 0 && target.bandId == card.bandId ? 1 : 0) +
            (target.characterId > 0 && target.characterId == card.characterId
                ? 1
                : 0) +
            (target.cardType != 0 && target.cardType == card.cardType ? 1 : 0);
        final type = effect.type >= 1000 && effect.type <= 1003
            ? effect.type
            : -1;
        for (var i = 0; i < hits; i++) {
          _accumulate(type, effect.value, acc);
        }
      }
    }
  }
  return acc;
}

bool _conditionHolds(
  EngineMaster master,
  int groupId,
  List<MemberState> members,
  MusicView? music,
) {
  if (groupId <= 0) return true;
  for (final set in master.conditionSets[groupId] ?? const <List<int>>[]) {
    for (final id in set) {
      final condition = master.conditions[id];
      if (condition == null ||
          condition.type == 0 ||
          condition.targetIds.isEmpty) {
        continue;
      }
      bool any(MemberState member) =>
          matchesTargets(master, member, condition.targetIds);
      var holds = true;
      if (condition.type == 3000) {
        holds = members.any(any);
      } else if (condition.type == 3001) {
        holds = members.every(any);
      } else if (condition.type == 4012) {
        holds =
            music != null &&
            condition.targetIds.any((target) {
              final row = master.targets[target];
              return row != null &&
                  row.liveMusicType != 0 &&
                  row.liveMusicType == music.musicType;
            });
      }
      if (!holds) return false;
    }
  }
  return true;
}

int _cumulativeCount(
  EngineMaster master,
  int id,
  List<MemberState> members,
  int leader,
) {
  final row = id > 0 ? master.cumulative[id] : null;
  if (row == null) return 1;
  bool hit(MemberState member) => matchesTargets(master, member, row.targetIds);
  final int count;
  switch (row.type) {
    case 3000:
      count = members.where(hit).length;
    case 3001:
      count = [
        for (final (index, member) in members.indexed)
          if (index != leader && hit(member)) member,
      ].length;
    case 3002:
      count = members
          .where((m) => m.card.bandId == members[leader].card.bandId)
          .length;
    case 3003:
      count = members
          .where((m) => m.card.bandId != members[leader].card.bandId)
          .length;
    case 3004:
      count = members.map((m) => m.card.bandId).toSet().length;
    case 3005:
      count = members.map((m) => m.card.cardType).toSet().length;
    default:
      return 1;
  }
  return row.cap < 1 ? count : math.min(count, row.cap);
}

class LeaderProfile {
  LeaderProfile(this.effects, this.simple);
  final List<SkillEffectRow> effects;

  /// Unconditional, non-cumulative: a member's percentage depends on that member alone.
  final bool simple;
}

LeaderProfile leaderProfile(EngineMaster master, MemberState leader) {
  final effects = [
    for (final row
        in master.leaderSkills[leader.card.leaderSkillId] ??
            const <SkillEffectRow>[])
      if (row.level == leader.leaderSkillLevel) row,
  ];
  return LeaderProfile(
    effects,
    effects.every((row) => row.conditionGroup <= 0 && !_isCumulative(row.type)),
  );
}

/// Exact leader percentages of [members] (leader at [leader]).
List<BP3> leaderPercents(
  EngineMaster master,
  LeaderProfile profile,
  List<MemberState> members,
  int leader,
  MusicView? music,
) {
  final out = [
    for (final _ in members) <int>[0, 0, 0],
  ];
  for (final effect in profile.effects) {
    if (!_conditionHolds(master, effect.conditionGroup, members, music)) {
      continue;
    }
    final value = _isCumulative(effect.type)
        ? imul(
            effect.value,
            _cumulativeCount(master, effect.cumulativeId, members, leader),
          )
        : effect.value;
    for (final (index, member) in members.indexed) {
      if (effect.targetIds.isEmpty ||
          matchesTargets(master, member, effect.targetIds)) {
        _accumulate(effect.type, value, out[index]);
      }
    }
  }
  return out;
}

/// Percentage of one member when the profile is simple, or a component-wise
/// upper bound otherwise.
BP3 leaderPercentBound(
  EngineMaster master,
  LeaderProfile profile,
  MemberState member,
) {
  final acc = <int>[0, 0, 0];
  for (final effect in profile.effects) {
    if (effect.targetIds.isNotEmpty &&
        !matchesTargets(master, member, effect.targetIds)) {
      continue;
    }
    var value = effect.value;
    if (_isCumulative(effect.type)) {
      final cap = master.cumulative[effect.cumulativeId]?.cap ?? 5;
      value = math.max(value, value * (cap >= 1 ? math.min(cap, 5) : 5));
    }
    _accumulate(effect.type, profile.simple ? value : math.max(0, value), acc);
  }
  return acc;
}

/// Everything of a slot that does not depend on the snap or the leader.
class SlotBase {
  SlotBase(this.common, this.fixedPoints);

  /// Common base the percentages multiply.
  final BP3 common;

  /// Points of base, ranks, memory, band item, music type/tag and VIP.
  final int fixedPoints;
}

SlotBase slotBase(
  EngineMaster master,
  PlayerState player,
  MemberState member,
  MusicView? music,
  int memberEventPct,
) {
  final own = member.own;
  final base = memberEventPct != 0
      ? [
          for (final (i, v) in _pctUniform(own, memberEventPct).indexed)
            own[i] + v,
        ]
      : [...own];
  final rank = player.characterRanks[member.card.characterId] ?? 1;
  var cr = 0;
  for (final (threshold, bonus) in master.characterRankBonus) {
    if (threshold <= rank) cr = bonus;
  }
  var ctr = 0;
  for (final (threshold, bonus) in master.totalRankBonus) {
    if (threshold <= player.totalRank) ctr = bonus;
  }
  final memory =
      (player.characterMemory[member.card.characterId] ?? 0) +
      (music != null ? (player.musicMemory[music.memoryKey] ?? 0) : 0);
  final flat = (cr + ctr + memory) * 10000;
  final common = [base[0] + flat, base[1] + flat, base[2] + flat];
  var total = points(common);
  total += points(pctFloor(common, bandItemPercent(master, player, member)));
  if (music != null) {
    final card = member.card;
    if (card.cardType == 99 ||
        music.musicType == 99 ||
        card.cardType == music.musicType) {
      total += points(
        _pctUniform(common, master.params.musicTypeBase + member.musicTypeRate),
      );
    }
    if (card.bestTags.any(music.bestTags.contains)) {
      total += points(
        _pctUniform(common, master.params.musicTagBase + member.musicTagRate),
      );
    }
  }
  final vip = master.vipBonus[player.vipRank] ?? 0;
  if (vip != 0) total += points(_pctUniform(common, vip));
  return SlotBase(common, total);
}

/// Snap power and type link of one slot.
int snapPoints(
  EngineMaster master,
  SlotBase base,
  MemberState member,
  SnapState? snap,
  int snapEventPct,
) {
  final percent = snap != null
      ? [for (final p in snap.percent) p + snapEventPct]
      : [0, 0, 0];
  var total = snap != null || snapEventPct != 0
      ? points(pctFloor(base.common, percent))
      : 0;
  if (snap != null && snap.card.cardType == member.card.cardType) {
    final link = master.params.typeLinkBase + snap.typeLinkRate;
    total += points(_pctUniform(base.common, link));
  }
  return total;
}

int leaderPoints(SlotBase base, BP3 percent) =>
    percent[0] != 0 || percent[1] != 0 || percent[2] != 0
    ? points(pctFloor(base.common, percent))
    : 0;

/// Event parameter percentages of a member, summed over held events.
int memberEventPercent(
  List<EventEffectRow> effects,
  MemberState member, [
  int bonusType = 2,
]) {
  var total = 0;
  final card = member.card;
  for (final effect in effects) {
    if (effect.bonusType != bonusType || effect.resourceType != 2) continue;
    if (effect.characterId > 0 && effect.characterId != card.characterId) {
      continue;
    }
    if (effect.bandId > 0 && effect.bandId != card.bandId) continue;
    if (effect.cardType != 0 && effect.cardType != card.cardType) continue;
    if (effect.tagId > 0 && !card.bestTags.contains(effect.tagId)) continue;
    if (effect.memberCardId >= 1 && effect.memberCardId != card.id) continue;
    total = i32(
      total + (effect.perRank.elementAtOrNull(member.growth.rank - 1) ?? 0),
    );
  }
  return total;
}

int snapEventPercent(
  List<EventEffectRow> effects,
  SnapState snap, [
  int bonusType = 2,
]) {
  var total = 0;
  final card = snap.card;
  for (final effect in effects) {
    if (effect.bonusType != bonusType || effect.resourceType != 3) continue;
    if (effect.characterId > 0 &&
        !card.characterIds.contains(effect.characterId)) {
      continue;
    }
    if (effect.bandId > 0 && !card.bandIds.contains(effect.bandId)) continue;
    if (effect.cardType != 0 && effect.cardType != card.cardType) continue;
    if (effect.tagId >= 1) continue;
    if (effect.supportCardId >= 1 && effect.supportCardId != card.id) continue;
    total = i32(
      total + (effect.perRank.elementAtOrNull(snap.growth.rank - 1) ?? 0),
    );
  }
  return total;
}

class TeamPower {
  TeamPower(this.total, this.slots, this.leaderPercents);
  final int total;
  final List<int> slots;
  final List<BP3> leaderPercents;
}

/// Exact power of five slots; [eventEffects] is non-empty only where
/// parameter bonuses apply (challenge).
TeamPower teamPower(
  EngineMaster master,
  PlayerState player,
  List<MemberState> members,
  List<SnapState?> snaps,
  int leader,
  MusicView? music, [
  List<EventEffectRow> eventEffects = const [],
]) {
  final percents = leaderPercents(
    master,
    leaderProfile(master, members[leader]),
    members,
    leader,
    music,
  );
  final slots = [
    for (final (index, member) in members.indexed)
      () {
        final base = slotBase(
          master,
          player,
          member,
          music,
          eventEffects.isNotEmpty
              ? memberEventPercent(eventEffects, member)
              : 0,
        );
        final snap = snaps.elementAtOrNull(index);
        final snapEvent = snap != null && eventEffects.isNotEmpty
            ? snapEventPercent(eventEffects, snap)
            : 0;
        return base.fixedPoints +
            snapPoints(master, base, member, snap, snapEvent) +
            leaderPoints(base, percents[index]);
      }(),
  ];
  return TeamPower(slots.fold(0, (a, b) => a + b), slots, percents);
}
