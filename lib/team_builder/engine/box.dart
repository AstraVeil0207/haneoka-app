/// Card box → resolved member and snap states (`team-builder/engine/box.ts`).
library;

import 'dart:math' as math;

import 'master.dart';
import 'power.dart';

class MemberInput {
  MemberInput({
    required this.key,
    required this.cardId,
    this.level,
    this.awake,
    this.rank,
    this.liveSkillLevel,
    this.gekisoSkillLevel,
  });
  factory MemberInput.fromJson(Map<String, Object?> json) => MemberInput(
    key: '${json['key']}',
    cardId: (json['cardId'] as num).toInt(),
    level: (json['level'] as num?)?.toInt(),
    awake: (json['awake'] as num?)?.toInt(),
    rank: (json['rank'] as num?)?.toInt(),
    liveSkillLevel: (json['liveSkillLevel'] as num?)?.toInt(),
    gekisoSkillLevel: (json['gekisoSkillLevel'] as num?)?.toInt(),
  );
  final String key;
  final int cardId;
  final int? level;
  final int? awake;
  final int? rank;
  final int? liveSkillLevel;
  final int? gekisoSkillLevel;
  Map<String, Object?> toJson() => {
    'key': key,
    'cardId': cardId,
    'level': level,
    'awake': awake,
    'rank': rank,
    'liveSkillLevel': liveSkillLevel,
    'gekisoSkillLevel': gekisoSkillLevel,
  };
}

class SnapInput {
  SnapInput({required this.key, required this.cardId, this.level, this.rank});
  factory SnapInput.fromJson(Map<String, Object?> json) => SnapInput(
    key: '${json['key']}',
    cardId: (json['cardId'] as num).toInt(),
    level: (json['level'] as num?)?.toInt(),
    rank: (json['rank'] as num?)?.toInt(),
  );
  final String key;
  final int cardId;
  final int? level;
  final int? rank;
  Map<String, Object?> toJson() => {
    'key': key,
    'cardId': cardId,
    'level': level,
    'rank': rank,
  };
}

/// How unknown growth fields are filled: `max` or `min`.
enum UnknownPolicy { max, min }

MemberGrowth maxMemberGrowth(EngineMaster master, MemberCard card) {
  final awake = maxAwake(master, card);
  return MemberGrowth(
    memberLevelCap(master, card, awake),
    awake,
    maxMemberRank(master, card),
    maxSkillLevel(master.liveSkills[card.liveSkillId]),
    maxSkillLevel(master.gekisoSkills[card.gekisoSkillId]?.effects),
  );
}

SnapGrowth maxSnapGrowth(EngineMaster master, SnapCard card) {
  final rank = maxSnapRank(master, card);
  return SnapGrowth(snapLevelCap(master, card, rank), rank);
}

MemberGrowth memberGrowth(
  EngineMaster master,
  MemberCard card,
  MemberInput input,
  UnknownPolicy policy,
) {
  final max = maxMemberGrowth(master, card);
  int pick(int? value, int high) =>
      value ?? (policy == UnknownPolicy.max ? high : 1);
  final awake = math.min(pick(input.awake, max.awake), max.awake);
  final cap = memberLevelCap(master, card, awake);
  return MemberGrowth(
    math.max(1, math.min(pick(input.level, cap), cap)),
    awake,
    math.min(pick(input.rank, max.rank), max.rank),
    math.min(pick(input.liveSkillLevel, max.liveSkillLevel), max.liveSkillLevel),
    math.min(
      pick(input.gekisoSkillLevel, max.gekisoSkillLevel),
      max.gekisoSkillLevel,
    ),
  );
}

SnapGrowth snapGrowth(
  EngineMaster master,
  SnapCard card,
  SnapInput input,
  UnknownPolicy policy,
) {
  final max = maxSnapGrowth(master, card);
  final rank = math.min(
    input.rank ?? (policy == UnknownPolicy.max ? max.rank : 1),
    max.rank,
  );
  final cap = snapLevelCap(master, card, rank);
  return SnapGrowth(
    math.max(
      1,
      math.min(input.level ?? (policy == UnknownPolicy.max ? cap : 1), cap),
    ),
    rank,
  );
}

class ResolvedBox {
  ResolvedBox(this.members, this.snaps, this.unknown);
  final List<MemberState> members;
  final List<SnapState> snaps;

  /// Entries whose card is unknown to this release.
  final List<String> unknown;
}

ResolvedBox resolveBox(
  EngineMaster master,
  List<MemberInput> members,
  List<SnapInput> snaps, [
  UnknownPolicy policy = UnknownPolicy.max,
]) {
  final unknown = <String>[];
  final resolvedMembers = <MemberState>[];
  for (final input in members) {
    final card = master.members[input.cardId];
    final state = card == null
        ? null
        : resolveMember(
            master,
            input.key,
            card,
            memberGrowth(master, card, input, policy),
          );
    if (state != null) {
      resolvedMembers.add(state);
    } else {
      unknown.add(input.key);
    }
  }
  final resolvedSnaps = <SnapState>[];
  for (final input in snaps) {
    final card = master.snaps[input.cardId];
    final state = card == null
        ? null
        : resolveSnap(
            master,
            input.key,
            card,
            snapGrowth(master, card, input, policy),
          );
    if (state != null) {
      resolvedSnaps.add(state);
    } else {
      unknown.add(input.key);
    }
  }
  return ResolvedBox(resolvedMembers, resolvedSnaps, unknown);
}

/// Every card at full growth: the reference box.
({List<MemberInput> members, List<SnapInput> snaps}) theoreticalInputs(
  EngineMaster master,
) => (
  members: [
    for (final card in master.members.values)
      MemberInput(key: 'm${card.id}', cardId: card.id),
  ],
  snaps: [
    for (final card in master.snaps.values)
      SnapInput(key: 's${card.id}', cardId: card.id),
  ],
);

PlayerState emptyPlayer() => PlayerState(
  characterRanks: {},
  totalRank: 0,
  bandItems: {},
  vipRank: 1,
  characterMemory: {},
  musicMemory: {},
);
