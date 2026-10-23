/// Normal-live skill shapes of one member and its equipped snap
/// (`team-builder/engine/skills.ts`).
library;

import 'master.dart';
import 'num.dart';
import 'power.dart';

enum GateKind { always, lifeAtLeast, never }

/// Static checks resolved before the live; dynamic ones stay symbolic.
class LifeGate {
  const LifeGate.always() : kind = GateKind.always, value = 0, positive = true;
  const LifeGate.never() : kind = GateKind.never, value = 0, positive = true;
  const LifeGate.lifeAtLeast(this.value, this.positive)
    : kind = GateKind.lifeAtLeast;
  final GateKind kind;
  final double value;
  final bool positive;

  /// Whether a life-gated effect is off at [life].
  bool blocks(double life) =>
      kind == GateKind.lifeAtLeast && (life >= value) != positive;
}

class LiveEffect {
  LiveEffect(this.type, this.delta, this.seconds, this.gate, this.judgements);

  /// 2000 or 2004.
  final int type;

  /// Native mill-percent delta added to the factor (value/10000·100000).
  final int delta;
  final double seconds;
  final LifeGate gate;

  /// 2004 only: simulate judgements whose factor it raises (5 Perfect, 6 Just, 4 Great).
  final List<int> judgements;
}

class SkillConvert {
  SkillConvert(this.judgements, this.limit);
  final List<int> judgements;

  /// [inf] when unlimited.
  final double limit;
}

class SlotSkill {
  SlotSkill(this.effects, this.extensionMs, this.recovery, this.convert);
  final List<LiveEffect> effects;

  /// 15000 sum, ms, binary32.
  final double extensionMs;

  /// 3001 life recovery on the member's activation.
  final int recovery;

  /// 12006: judgements converted to Perfect inside the member's window.
  final SkillConvert? convert;

  String? _signature;

  /// Value identity, for the score cache.
  String get signature => _signature ??= [
    extensionMs,
    recovery,
    convert == null
        ? '-'
        : '${convert!.judgements.join('.')}/${convert!.limit}',
    for (final e in effects)
      '${e.type}:${e.delta}:${e.seconds}:${e.gate.kind.index}:${e.gate.value}:${e.gate.positive}:${e.judgements.join('.')}',
  ].join('|');
}

double effectPercent(SlotSkill skill, int type) => skill.effects
    .where(
      (effect) =>
          effect.type == type &&
          (type != 2004 || effect.judgements.contains(5)),
    )
    .fold<double>(
      0,
      (best, effect) => effect.delta / 1000 > best ? effect.delta / 1000 : best,
    );

int scoreDelta(int value) => f(f(f(value) / f(10000)) * f(100000)).floor();

/// AddJudgementNoteScoreUpFactor rounds (ties to even) after the binary32 product.
int judgementDelta(int value) {
  final scaled = f(f(f(value) / f(10000)) * 100000);
  final lower = scaled.floor();
  final fraction = scaled - lower;
  return fraction < 0.5
      ? lower
      : fraction > 0.5
      ? lower + 1
      : lower.isEven
      ? lower
      : lower + 1;
}

/// true, false, 'life' (a dynamic life comparison) or null (unsupported).
Object? _conditionValue(
  EngineMaster master,
  ConditionRow row,
  MemberState member,
) {
  bool? match;
  switch (row.type) {
    case 5000:
      match = matchesTargets(master, member, row.targetIds);
    case 4010:
    case 5020:
      // Same-member live skill trigger: the snap fires with its member's activation.
      return row.positive ? true : null;
    case 2001:
      return 'life';
    default:
      match = null;
  }
  return match == null ? null : (row.positive ? match : !match);
}

/// OR over sets of AND conditions; a life comparison stays dynamic.
({bool holds, ConditionRow? life})? _groupHolds(
  EngineMaster master,
  int group,
  MemberState member,
) {
  if (group <= 0) return (holds: true, life: null);
  final sets = master.conditionSets[group];
  if (sets == null || sets.isEmpty) return null;
  var any = false;
  ConditionRow? life;
  for (final set in sets) {
    var all = true;
    for (final id in set) {
      final row = master.conditions[id];
      final value = row == null ? null : _conditionValue(master, row, member);
      if (value == null) return null;
      if (value == 'life') {
        life = row;
      } else if (value == false) {
        all = false;
      }
    }
    if (all) any = true;
  }
  return (holds: any, life: life);
}

List<int> _judgementsOf(EngineMaster master, List<int> ids) => [
  for (final id in ids)
    if ((master.targets[id]?.judgement ?? -1) case final j
        when j >= 3 && j <= 6)
      j,
];

Iterable<SkillEffectRow> _atLevel(List<SkillEffectRow>? rows, int level) =>
    (rows ?? const <SkillEffectRow>[]).where((row) => row.level == level);

SlotSkill resolveSlotSkill(
  EngineMaster master,
  MemberState member,
  SnapState? snap, [
  List<String>? unsupported,
]) {
  final effects = <LiveEffect>[];
  for (final row in _atLevel(
    master.liveSkills[member.card.liveSkillId],
    member.growth.liveSkillLevel,
  )) {
    if (row.type != 2000 && row.type != 2004) {
      unsupported?.add('live:${member.card.liveSkillId}:${row.type}');
      continue;
    }
    final condition = _groupHolds(master, row.conditionGroup, member);
    if (condition == null) {
      unsupported?.add('live-condition:${row.conditionGroup}');
      continue;
    }
    if (!condition.holds) continue;
    final life = condition.life;
    effects.add(
      LiveEffect(
        row.type,
        row.type == 2000 ? scoreDelta(row.value) : judgementDelta(row.value),
        f(row.seconds),
        life != null
            ? LifeGate.lifeAtLeast(life.values.firstOrNull ?? 0, life.positive)
            : const LifeGate.always(),
        row.type == 2004 ? _judgementsOf(master, row.targetIds) : const [],
      ),
    );
  }
  var extensionMs = f(0);
  var recovery = 0;
  SkillConvert? convert;
  if (snap != null) {
    for (final (slot, skillId) in snap.card.supportSkillIds.indexed) {
      if (skillId == 0) continue;
      for (final row in _atLevel(
        master.supportSkills[skillId],
        snap.skillLevels.elementAtOrNull(slot) ?? 1,
      )) {
        final enabled = _groupHolds(master, row.conditionGroup, member);
        final trigger = _groupHolds(master, row.triggerGroup, member);
        if (enabled == null || trigger == null) {
          unsupported?.add('support-condition:$skillId');
          continue;
        }
        if (!enabled.holds) continue;
        if (row.type == 15000) {
          extensionMs = f(extensionMs + f(row.value));
        } else if (row.type == 3001) {
          recovery += row.value;
        } else if (row.type == 12006) {
          convert = SkillConvert(
            _judgementsOf(master, row.targetIds),
            row.limitCount != 0 ? row.limitCount.toDouble() : inf,
          );
        } else if (row.type != 3003) {
          unsupported?.add('support:$skillId:${row.type}');
        }
      }
    }
  }
  return SlotSkill(effects, extensionMs, recovery, convert);
}

/// Window length of an effect: ceil(seconds·1000 + extension) in binary32.
int windowMs(double seconds, double extensionMs) =>
    f(f(f(seconds) * f(1000)) + extensionMs).ceil();
