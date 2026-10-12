/// The skill effect state machine and the condition skill updater (snap,
/// Gekisou and Gekisou support skills) (`engine/full/effects.ts`). An
/// effect state moves Stay → ExecuteFrame (with the trigger time) →
/// Executing → EndFrame (with the finish time) → Stay.
library;

import 'dart:math' as math;

import '../num.dart';
import 'conditions.dart';
import 'core.dart';
import 'gekisou.dart';

const stay = 0;
const executeFrame = 2;
const executing = 3;
const endFrame = 4;
const oneShot = 1;
const sustained = 2;
const _pool = 5;

class EffectState {
  int state = stay;
  int executeMs = -1;
  int finishMs = -1;

  /// Duration added by extensions, ms (binary32).
  double extendedMs = 0;
  int cumulativeCount = 0;
  int cumulativeUnit = 0;
  int cumulativeMax = 0;
}

class FrameInput {
  FrameInput(this.timeMs, this.musicLengthMs, this.finished);
  int timeMs;
  int musicLengthMs;
  bool finished;
}

class Trigger {
  const Trigger(this.hit, this.timeMs);
  final bool hit;
  final int timeMs;
}

const noTrigger = Trigger(false, 0);

/// One update of an effect state; returns whether it changed (or started).
bool effectUpdate(
  EffectState st,
  double act,
  FrameInput inp,
  Trigger trigger,
  Checker? condition,
  Checker? release,
  bool finishFrame,
  CheckCtx ctx,
) {
  switch (st.state) {
    case stay:
      final ok = condition != null ? condition.check(ctx).$1 : true;
      if (ok && trigger.hit) {
        st.state = executeFrame;
        st.executeMs = trigger.timeMs;
      }
      return ok && trigger.hit;
    case executeFrame:
      final t = inp.timeMs;
      if (finishFrame) {
        st.state = endFrame;
        st.finishMs = t;
      } else if (release != null) {
        st.state = executing;
      } else {
        final dur = f(f(act * 1000) + st.extendedMs);
        final elapsed = f(i32(t - st.executeMs));
        if (dur > elapsed) {
          st.state = executing;
        } else {
          st.state = endFrame;
          st.finishMs = t;
        }
      }
      return true;
    case executing:
      final released = release != null ? release.check(ctx).$1 : false;
      final dur = f(f(act * 1000) + st.extendedMs);
      final elapsed = f(i32(inp.timeMs - st.executeMs));
      final byTime = dur < elapsed && act > 0;
      if (!(released || finishFrame || byTime)) return false;
      st.state = endFrame;
      var finish = !released && !finishFrame
          ? i32(st.executeMs + ceilToI32(dur))
          : inp.timeMs;
      if (inp.musicLengthMs > 0 && inp.musicLengthMs <= finish) {
        finish = inp.musicLengthMs;
      }
      st.finishMs = finish;
      return true;
    case endFrame:
      st.state = stay;
      return true;
    default:
      throw StateError('effect state ${st.state} out of range');
  }
}

/// Whether a sustained effect has an activation time: `act > 0` and not
/// approximately `int.MaxValue`.
bool _hasActivationTime(double act) {
  if (act.isNaN || act <= 0) return false;
  final big = f(2147483647);
  final m = math.max(act.abs(), big);
  final tol = math.max(f(m * f(1e-6)), f(1.401298464324817e-45 * 8));
  return tol <= f(big - act).abs();
}

/// One effect of a condition skill.
class CondEffect {
  CondEffect({
    required this.effectId,
    required this.triggerType,
    required this.act,
    required this.phase,
    required this.trigger,
    required this.condition,
    required this.executeLimit,
    required this.reset,
    required this.row,
    required this.cumulative,
  });
  final int effectId;
  final int triggerType;
  final double act;
  final int phase;
  final Checker? trigger;
  final Checker? condition;
  final int executeLimit;
  final Checker? reset;

  /// Index of the effect's row in the live model.
  final int row;
  final Cumulative? Function()? cumulative;
}

class EffectUpdater {
  EffectUpdater(
    this.effect,
    this.index,
    this.release,
    this.phase,
    this.cumulative,
  ) {
    if (cumulative case final c?) {
      state.cumulativeCount = c.initCount();
      state.cumulativeUnit = c.unit();
      state.cumulativeMax = c.max();
    }
  }
  final EffectState state = EffectState();
  final int effect;
  final int index;
  final Checker? release;
  final int phase;
  final Cumulative? cumulative;

  bool update(
    double act,
    FrameInput inp,
    Trigger trigger,
    bool finishFrame,
    CheckCtx ctx,
  ) {
    final s0 = state.state;
    final r = effectUpdate(
      state,
      act,
      inp,
      trigger,
      null,
      release,
      finishFrame,
      ctx,
    );
    if (cumulative case final c?) {
      final s1 = state.state;
      if ((s0 == stay && s1 == executeFrame) ||
          s0 == executeFrame ||
          (s0 == executing && s1 == executing)) {
        state.cumulativeCount = c.updateCount(ctx);
      } else if (s0 == endFrame) {
        c.reset();
      }
    }
    return r;
  }
}

class _Sustained {
  _Sustained(this.queue, this.timed);
  List<int> queue;
  int? current;
  bool enabled = false;
  final bool timed;
  var executing = <int>[];
}

/// The gate of a Gekisou (support) skill: a range of its mission changed
/// state this frame, or one is playing.
bool missionGateOpen(int? gate, CheckCtx ctx) {
  if (gate == null || gate == missionAll) return true;
  final gk = ctx.gk;
  if (gk == null) throw StateError('Gekisou skill in a live without Gekisou');
  final c = gk.ctrl;
  if (c.stateUpdates.any((i) => c.ranges[i].mission == gate)) return true;
  final i = c.currentPlayingIndex;
  return i >= 0 && c.ranges[i].mission == gate;
}

class ConditionSkillUpdater {
  ConditionSkillUpdater(
    this.effects,
    Checker? Function(int e) release,
    this.gate,
  ) {
    final ids = [for (final e in effects) e.effectId]..sort();
    for (var i = 1; i < ids.length; i++) {
      if (ids[i - 1] == ids[i]) {
        throw StateError('condition skill with a duplicate effect id');
      }
    }
    _sorted = [for (var i = 0; i < effects.length; i++) i]
      ..sort((a, b) => effects[a].effectId - effects[b].effectId);
    _stacks = [for (final _ in effects) <int>[]];
    _sustained = List.filled(effects.length, null);
    for (final (e, ef) in effects.indexed) {
      if (ef.triggerType != oneShot && ef.triggerType != sustained) continue;
      final pool = <int>[];
      for (var index = 0; index < _pool; index++) {
        pool.add(updaters.length);
        updaters.add(
          EffectUpdater(e, index, release(e), ef.phase, ef.cumulative?.call()),
        );
      }
      if (ef.triggerType == oneShot) {
        _stacks[e] = pool;
      } else {
        _sustained[e] = _Sustained(pool, _hasActivationTime(ef.act));
      }
    }
    _cache = List.filled(effects.length, null);
    List<int>? idle = effects.isNotEmpty ? [] : null;
    for (final ef in effects) {
      final member = ef.trigger?.idleMember();
      if (idle == null ||
          ef.triggerType != oneShot ||
          ef.reset != null ||
          member == null) {
        idle = null;
        break;
      }
      if (member >= 0 && !idle.contains(member)) idle.add(member);
    }
    _idleMembers = idle;
  }
  final List<CondEffect> effects;
  final int? gate;
  final updaters = <EffectUpdater>[];
  late final List<int> _sorted;
  late final List<List<int>> _stacks;
  late final List<_Sustained?> _sustained;
  final _executing = <int>[];
  final _executeCount = <int, int>{};
  bool _triggerChecked = false;
  late final List<Trigger?> _cache;
  late final List<int>? _idleMembers;
  bool _quietFrame = false;

  void beginFrame() {
    _triggerChecked = false;
    _quietFrame = false;
  }

  bool _updateOne(
    int u,
    FrameInput inp,
    Trigger trigger,
    bool finishFrame,
    CheckCtx ctx,
  ) {
    final upd = updaters[u];
    return upd.update(effects[upd.effect].act, inp, trigger, finishFrame, ctx);
  }

  /// Updates the skill for one phase; returns the updaters whose states the
  /// appliers see, in order.
  List<int> update(int phase, FrameInput inp, CheckCtx ctx) {
    if (!_triggerChecked && _executing.isEmpty) {
      final idle = _idleMembers;
      if ((idle != null && !ctx.events.any((e) => idle.contains(e.$1))) ||
          inp.finished ||
          !missionGateOpen(gate, ctx)) {
        // Nothing runs and no trigger can hit.
        _triggerChecked = true;
        _quietFrame = true;
      }
    }
    if (_quietFrame) return const [];
    final updated = <int>[];
    final done = <int>[];
    for (final u in _executing.length > 1 ? [..._executing] : _executing) {
      if (phase < 1 || updaters[u].phase == phase) {
        _updateOne(u, inp, noTrigger, false, ctx);
        if (updaters[u].state.state == stay) {
          done.add(u);
        } else {
          updated.add(u);
        }
      }
    }
    if (!_triggerChecked) {
      _triggerChecked = true;
      _cache.fillRange(0, _cache.length, null);
      if (inp.finished || !missionGateOpen(gate, ctx)) {
        _finish(done);
        return updated;
      }
      for (final ef in effects) {
        if (ef.reset != null && ef.reset!.check(ctx).$1) {
          _executeCount.remove(ef.effectId);
        }
      }
      for (final e in _sorted) {
        final c = effects[e].trigger;
        if (c == null) {
          _cache[e] = noTrigger;
        } else {
          final (hit, _) = c.check(ctx);
          _cache[e] = Trigger(hit, c.overrideTime() ?? inp.timeMs);
        }
      }
    }
    for (final e in _sorted) {
      final tr = _cache[e];
      if (tr == null) continue;
      final ef = effects[e];
      if (ef.triggerType == sustained) {
        if (phase < 1 || ef.phase == phase) {
          _updateSustained(e, inp, tr, ctx, updated);
        }
        continue;
      }
      if (ef.triggerType != oneShot) {
        throw StateError(
          'ArgumentOutOfRangeException: skill trigger type ${ef.triggerType}',
        );
      }
      if (!tr.hit) continue;
      final stack = _stacks[e];
      if (stack.isEmpty) continue;
      final top = stack.last;
      if (phase >= 1 && updaters[top].phase != phase) continue;
      final executed = _executeCount[ef.effectId];
      if (ef.executeLimit > 0 &&
          executed != null &&
          ef.executeLimit <= executed) {
        continue;
      }
      if (ef.condition != null && !ef.condition!.check(ctx).$1) continue;
      final u = stack.removeLast();
      _updateOne(u, inp, Trigger(true, tr.timeMs), false, ctx);
      _executing.add(u);
      updated.add(u);
      if (ef.executeLimit > 0) {
        _executeCount[ef.effectId] = (_executeCount[ef.effectId] ?? 0) + 1;
      }
    }
    _finish(done);
    return updated;
  }

  void _finish(List<int> done) {
    for (final u in done) {
      _stacks[updaters[u].effect].add(u);
      _executing.remove(u);
    }
  }

  void _updateSustained(
    int e,
    FrameInput inp,
    Trigger tr,
    CheckCtx ctx,
    List<int> updated,
  ) {
    final s = _sustained[e]!;
    if (s.timed) {
      _timedStep(s, e, inp, tr, ctx, updated);
    } else {
      final u = _step(s, e, tr.hit ? tr.timeMs : inp.timeMs, inp, tr, ctx);
      if (u != null) updated.add(u);
    }
  }

  void _timedStep(
    _Sustained s,
    int e,
    FrameInput inp,
    Trigger tr,
    CheckCtx ctx,
    List<int> updated,
  ) {
    if (tr.hit) {
      final condition =
          effects[e].condition ??
          (throw StateError('timed sustained effect has no condition checker'));
      if (!s.enabled) {
        condition.reset(ctx);
        s.enabled = true;
      }
      int? fresh;
      if (condition.check(ctx).$1) {
        condition.reset(ctx);
        if (s.queue.isEmpty) {
          throw StateError('sustained effect queue is empty');
        }
        final u = s.queue.removeAt(0);
        s.executing.add(u);
        fresh = u;
      }
      final done = <int>[];
      for (final u in s.executing) {
        final trigger = Trigger(
          fresh == u,
          fresh == u ? tr.timeMs : inp.timeMs,
        );
        if (_updateOne(u, inp, trigger, false, ctx)) {
          updated.add(u);
          if (updaters[u].state.state == stay) done.add(u);
        }
      }
      for (final u in done) {
        s.queue.add(u);
        s.executing = [
          for (final x in s.executing)
            if (x != u) x,
        ];
      }
    } else {
      for (final u in s.executing) {
        _updateOne(u, inp, noTrigger, true, ctx);
        updated.add(u);
        s.queue.add(u);
      }
      s.executing = [];
      s.enabled = false;
    }
  }

  int? _step(
    _Sustained s,
    int e,
    int executeMs,
    FrameInput inp,
    Trigger tr,
    CheckCtx ctx,
  ) {
    var cur = s.current;
    if (cur != null && updaters[cur].state.state == endFrame) {
      _updateOne(cur, inp, noTrigger, false, ctx);
      s.queue.add(cur);
      s.current = null;
      cur = null;
    }
    if (cur != null && updaters[cur].state.state == executeFrame) {
      updaters[cur].state.state = executing;
    }
    final condition = effects[e].condition;
    if (tr.hit) {
      if (!s.enabled) {
        condition?.reset(ctx);
        s.enabled = true;
      }
      if (condition != null && !condition.check(ctx).$1) return null;
      if (cur == null) {
        if (s.queue.isEmpty) {
          throw StateError('sustained effect queue is empty');
        }
        final c = s.queue.removeAt(0);
        s.current = c;
        if (_updateOne(c, inp, Trigger(true, executeMs), false, ctx)) return c;
      }
    } else {
      if (cur != null) {
        _updateOne(cur, inp, noTrigger, true, ctx);
        s.enabled = false;
        return cur;
      }
      s.enabled = false;
    }
    return null;
  }
}
