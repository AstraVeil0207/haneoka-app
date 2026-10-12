/// Whole-live simulation, frame by frame, with live skills, snap skills
/// and, optionally, Gekisou (`engine/full/model.ts`). Each frame: fevers
/// and Gekisou ranges step; due chart skill events fire; judged notes go
/// through conversion, combo, damage and the note score command; the score
/// advances; live skills restart; skills update in phase 1 then 2 (live
/// skills by key, then condition skills) with their appliers; life syncs;
/// the score advances again; Gekisou ranges take the judged notes and a
/// completed range gets its rank bonus.
library;

import 'dart:math' as math;

import '../master.dart';
import '../num.dart';
import 'conditions.dart';
import 'convert.dart';
import 'core.dart';
import 'effects.dart';
import 'gekisou.dart';
import 'score.dart';

class LiveNote {
  LiveNote(this.id, this.timeMs, this.op, this.judgementType);
  final int id;
  final int timeMs;
  final int op;
  final int judgementType;
}

class JudgedNote {
  JudgedNote(this.noteId, this.judgement, this.timeMs);
  final int noteId;

  /// Note judgement before conversion: 1 Miss … 6 Just.
  final int judgement;
  final int timeMs;
}

class PlayFrame {
  PlayFrame(this.timeMs, this.judged);
  final int timeMs;
  final List<JudgedNote> judged;
}

class LiveParams {
  LiveParams({
    required this.skillTargetMusicType,
    required this.power,
    required this.level,
    required this.convertedCount,
    required this.musicLengthMs,
    this.assist = 1,
  });
  final int skillTargetMusicType;
  final int power;
  final num level;
  final int convertedCount;
  final int musicLengthMs;
  final double assist;
}

class LuckAction {
  LuckAction(
    this.frame,
    this.range,
    this.type,
    this.value,
    this.limit,
    this.chance,
  );
  final int frame;
  final int range;
  final int type;
  final int value;
  final int limit;
  final double chance;
}

final _recordedFrames = <String, LuckFrame>{};
var _nextRecordedFrame = 0;

class LuckFrame {
  factory LuckFrame(List<int> states, List<int> updates, int playing) {
    final key = '${states.join(',')}/${updates.join(',')}/$playing';
    final known = _recordedFrames[key];
    if (known != null) return known;
    if (_recordedFrames.length >= 4096) _recordedFrames.clear();
    return _recordedFrames[key] = LuckFrame._(
      List.unmodifiable(states),
      List.unmodifiable(updates),
      playing,
      _nextRecordedFrame++,
    );
  }
  LuckFrame._(this.states, this.updates, this.playing, this.id);
  final int id;
  final List<int> states;
  final List<int> updates;
  final int playing;
}

class LuckNote {
  LuckNote(
    this.frame,
    this.range,
    this.op,
    this.judgement,
    this.timeMs,
    this.speed,
    this.buff,
  );
  final int frame;
  final int range;
  final int op;
  final int judgement;
  final int timeMs;
  final double speed;
  final int buff;
}

/// Luck recording: what the luck DP reads from one lottery-free run.
class LuckRecord {
  final actions = <LuckAction>[];
  final frames = <LuckFrame>[];
  final notes = <LuckNote>[];
}

class GekisouSetup {
  GekisouSetup(this.fevers, this.missions);
  final List<(int, int)> fevers;
  final List<int> missions;
}

const _skillSupport = 3;
const _skillGekisou = 4;
const _skillGekisouSupport = 5;
const _ownerMember = 1;
const _ownerSnap = 2;
const _gekisouApplierTypes = {
  11000, 11001, 11002, 11003, 11004, 11005, 12000, 12002, 12003, 12004, //
  13000, 13002, 13003, 13004,
};
int _convertScoreType(int j) =>
    j + 1 >= 0 && j + 1 < 9 ? const [0, 0, 6, 5, 4, 3, 2, 1, 0][j + 1] : 0;
bool _approximately(double a, double b) {
  final tol = math.max(
    f(f(1e-6) * math.max(a.abs(), b.abs())),
    f(1.401298464324817e-45 * 8),
  );
  return f(b - a).abs() < tol;
}

const _noLots = <int>[];
int _minimumResultOf(int v) => v - 2 >= 0 && v - 2 <= 2 ? v - 1 : 0;
int _gekisouMissionGroup(int mission) {
  if (mission >= 1 && mission <= 3) return mission;
  if (mission == 4) return 1;
  throw StateError('KeyNotFoundException: Gekisou mission type $mission');
}

class _EffectRow {
  _EffectRow(
    this.id,
    this.type,
    this.value,
    this.maxValue,
    this.limitCount,
    this.targets,
  );
  final int id;
  final int type;
  final int value;
  final int maxValue;
  final int limitCount;

  /// Judgements of the targets.
  final List<int> targets;
}

class _LiveEffect {
  _LiveEffect(
    this.row,
    this.act,
    this.phase,
    this.state,
    this.condition,
    this.release,
    this.cumulative,
  );
  final int row;
  final double act;
  final int phase;
  final EffectState state;
  final Checker? condition;
  final Checker? release;
  final Cumulative? cumulative;
}

class _LiveSkill {
  _LiveSkill(this.key, this.member, this.index, this.effects);
  final int key;
  final int member;
  final int index;
  int parentState = stay;
  Trigger trigger = noTrigger;
  final List<_LiveEffect> effects;
}

class _LivePool {
  _LivePool(this.key, this.member, this.available);
  final int key;
  final int member;
  final List<int> available;
}

class _CondSkill {
  _CondSkill(this.member, this.skillType, this.updater);
  final int member;
  final int skillType;
  final ConditionSkillUpdater updater;
}

/// A live effect (skill, effect) or a condition updater (updater, u).
class _Listed {
  _Listed.live(this.skill, this.effect) : live = true, updater = 0, u = 0;
  _Listed.cond(this.updater, this.u) : live = false, skill = 0, effect = 0;
  final bool live;
  final int skill;
  final int effect;
  final int updater;
  final int u;
}

class _ScoreCtl implements LuckHandle {
  _ScoreCtl(this._score);
  final IncrementalScore _score;
  int _counter = 0;
  final _cmds = <int, FactorCommand>{};

  int put(FactorCommand cmd) {
    _counter = i32(_counter + 1);
    _cmds[_counter] = cmd;
    _score.addFactor(cmd);
    return _counter;
  }

  FactorCommand _take(int id) =>
      _cmds.remove(id) ?? (throw StateError('score factor $id not found'));

  int addNoteScoreUp(int owner, int t, double factor) =>
      put(FactorCommand(t, owner, note: noteFactorMill(factor)));
  void disableNoteScoreUp(int t, int id) {
    final c = _take(id);
    _score.addFactor(FactorCommand(t, c.owner, note: i32(-c.note)));
  }

  int addComboBonus(int owner, int t, double factor) =>
      put(FactorCommand(t, owner, combo: judgementFactorMill(factor)));
  void disableComboBonus(int t, int id) {
    final c = _take(id);
    _score.addFactor(FactorCommand(t, c.owner, combo: i32(-c.combo)));
  }

  double comboBonusFactor(int id) {
    final c = _cmds[id];
    return c != null && c.combo != 0 ? f(f(c.combo) / 100000) : 0;
  }

  double scoreUpFactor(int id) {
    final c = _cmds[id];
    return c != null && c.note != 0 ? f(f(c.note) / 100000) : 0;
  }

  @override
  int add(int t, int percent) => put(FactorCommand(t, -1, luck: percent));
  @override
  void disable(int t, int id) {
    final c = _take(id);
    _score.addFactor(FactorCommand(t, -1, luck: i32(-c.luck)));
  }
}

class _GkAppliers {
  final ids = <String, int>{};
  final exhausted = <String>{};
  final limitFinished = <String, int>{};
  void add(String key, int id) {
    if (ids.containsKey(key)) throw StateError('effect state registered twice');
    ids[key] = id;
  }

  int pop(String key) =>
      ids.remove(key) ?? (throw StateError('effect state not registered'));

  void limit(String key, EffectState st) {
    final t = limitFinished.remove(key);
    if (t != null) {
      st.state = endFrame;
      st.finishMs = t;
    }
  }
}

class RankBonus {
  RankBonus(this.range, this.rank, this.bonus, this.percent);
  final int range;
  final int rank;
  final int bonus;
  final int percent;
}

class GekisouLive {
  GekisouLive(this.ctrl, this.fever, this.factors);
  final GekisouController ctrl;
  final FeverUpdater fever;
  final List<List<int>> factors;
  List<(int, int)> feverUpdates = const [];
  List<int> prevLots = const [];
  int prevLotMs = 0;
  final rankBonus = <RankBonus>[];
}

class LiveModel {
  LiveModel(
    EngineMaster master,
    List<Performer> deck,
    List<LiveNote> notes,
    this._events,
    this._params,
    GekisouSetup? setup, {
    int seed = 0,
    LuckRecord? record,
  }) : _record = record,
       _byTime = List.generate(_events.length, (i) => i)
         ..sort(
           (a, b) => _events[a].$2 != _events[b].$2
               ? _events[a].$2 - _events[b].$2
               : a - b,
         ),
       _random = LiveRandom(seed) {
    for (final n in notes) {
      _notes[n.id] = n;
    }
    final live = master.live;
    if (setup != null) {
      final n = math.min(setup.fevers.length, maxRanges);
      final ranges = [
        for (var i = 0; i < n; i++)
          (
            setup.fevers[i].$1,
            setup.fevers[i].$2,
            i < setup.missions.length
                ? setup.missions[i]
                : throw StateError('fewer missions than fevers'),
          ),
      ];
      if (setup.missions.length < 3) {
        throw StateError('a Gekisou song has three missions');
      }
      gk = GekisouLive(
        GekisouController(
          ranges,
          [for (final note in notes) (note.id, note.timeMs)],
          live.gekiso,
          live.gekiso.rushPercent,
          live.afterMs.toInt(),
        ),
        FeverUpdater(setup.fevers),
        rankingFactors(
          live.gekiso,
          missionPattern(
            setup.missions[0],
            setup.missions[1],
            setup.missions[2],
          ),
        ),
      );
    } else {
      gk = null;
    }
    final calc = ScoreCalculator(
      ScoreSettings(
        adjustment: live.adjustment,
        lifeOnus: live.lifeOnus,
        notePercent: live.notePercent,
        judgePercent: live.judgePercent,
        combo: live.combo,
      ),
      _params.power,
      _params.level,
      _params.convertedCount,
      _params.assist,
    );
    final lifeLength = notes.isNotEmpty
        ? notes.fold(0, (m, n) => math.max(m, n.timeMs)) + 1000
        : 1000;
    life = LifeController(live.lifeBase.toInt(), live.damage, lifeLength);
    score = IncrementalScore(calc, _params.musicLengthMs);
    _scorectl = _ScoreCtl(score);
    _conversion = Conversion({
      for (final t in live.timingTypes)
        if (!live.justTypes.contains(t)) t,
    });
    if (record != null && gk != null) gk!.ctrl.weighted = true;
    _ctx = CheckCtx(
      record: record != null,
      life: life,
      random: _random,
      frameTime: 0,
      currentCombo: 0,
      judged: _judged,
      events: _frameEvents,
      gk: gk == null ? null : GkView(gk!.ctrl, const [], 0),
      prevConfirmedRank: null,
    );
    int phase(int type) => live.phases[type] ?? 1;
    final factory = ConditionFactory(
      master,
      deck,
      live.lifeBase.toInt(),
      _params.skillTargetMusicType,
    );
    int effectRow(SkillEffectRow r) {
      _rows.add(
        _EffectRow(r.id, r.type, r.value, r.maxValue, r.limitCount, [
          for (final t in r.targetIds)
            (master.targets[t] ?? (throw StateError('unknown skill target $t')))
                .judgement,
        ]),
      );
      return _rows.length - 1;
    }

    for (final (k, p) in deck.indexed) {
      final liveSkill = p.liveSkill;
      if (liveSkill == null) continue;
      final (sid, lv) = liveSkill;
      final rs = [
        for (final r in master.liveSkills[sid] ?? const <SkillEffectRow>[])
          if (r.level == lv) r,
      ]..sort((a, b) => a.id - b.id);
      final rowIndexes = [for (final r in rs) effectRow(r)];
      final key = sid * 1000 + 100 + k;
      final pool = <int>[];
      for (var index = 0; index < 5; index++) {
        pool.add(_live.length);
        final effects = [
          for (final (i, r) in rs.indexed)
            () {
              final cumulative = factory.cumulative(r.cumulativeId, k);
              final state = EffectState();
              if (cumulative != null) {
                state.cumulativeCount = cumulative.initCount();
                state.cumulativeUnit = cumulative.unit();
                state.cumulativeMax = cumulative.max();
              }
              return _LiveEffect(
                rowIndexes[i],
                f(r.seconds),
                phase(r.type),
                state,
                factory.group(r.conditionGroup, k),
                factory.group(r.releaseGroup, k),
                cumulative,
              );
            }(),
        ];
        _live.add(_LiveSkill(key, k, index, effects));
      }
      _livePools.add(_LivePool(key, k, pool));
    }
    _livePools.sort((a, b) => a.key - b.key);

    void conditionSkill(
      List<SkillEffectRow> rows,
      int k,
      int skillType,
      int? gate,
    ) {
      final rs = [...rows]..sort((a, b) => a.id - b.id);
      final effects = <CondEffect>[];
      final releases = <int>[];
      for (final r in rs) {
        if (r.triggerType != oneShot && r.triggerType != sustained) {
          throw StateError(
            'ArgumentOutOfRangeException: skill trigger type ${r.triggerType}',
          );
        }
        effects.add(
          CondEffect(
            effectId: r.id * 100 + skillType * 10 + k,
            triggerType: r.triggerType,
            act: f(r.seconds),
            phase: phase(r.type),
            trigger: factory.group(r.triggerGroup, k),
            condition: factory.group(r.conditionGroup, k),
            executeLimit: r.executeLimit,
            reset: r.executeLimit > 0 ? factory.group(r.resetGroup, k) : null,
            row: effectRow(r),
            cumulative: r.cumulativeId != 0
                ? () => factory.cumulative(r.cumulativeId, k)
                : null,
          ),
        );
        releases.add(r.releaseGroup);
      }
      final updater = ConditionSkillUpdater(
        effects,
        (e) => factory.group(releases[e], k),
        gate,
      );
      _cond.add(_CondSkill(k, skillType, updater));
    }

    for (final (k, p) in deck.indexed) {
      for (final (sid, lv) in p.supportSkills) {
        conditionSkill(
          [
            for (final r
                in master.supportSkills[sid] ?? const <SkillEffectRow>[])
              if (r.level == lv) r,
          ],
          k,
          _skillSupport,
          null,
        );
      }
    }
    if (gk != null) {
      final mission = [
        for (final p in deck)
          () {
            if (p.missionOnly case final m? when m != 0) return m;
            final skill = p.gekisouSkill;
            if (skill == null) return null;
            final row =
                master.gekisoSkills[skill.$1] ??
                (throw StateError('unknown Gekisou skill ${skill.$1}'));
            _gekisouMissionGroup(row.missionType);
            return row.missionType;
          }(),
      ];
      for (var m = 1; m <= 3; m++) {
        for (final (k, p) in deck.indexed) {
          final mk = mission[k];
          final skill = p.gekisouSkill;
          if (skill == null || mk == null || _gekisouMissionGroup(mk) != m) {
            continue;
          }
          final (sid, lv) = skill;
          conditionSkill(
            [
              for (final r in master.gekisoSkills[sid]!.effects)
                if (r.level == lv) r,
            ],
            k,
            _skillGekisou,
            mk,
          );
        }
      }
      for (final (k, p) in deck.indexed) {
        if (mission[k] == null) continue;
        for (final (sid, lv) in p.gekisouSupportSkills) {
          final row =
              master.gekisoSupportSkills[sid] ??
              (throw StateError('unknown Gekisou support skill $sid'));
          conditionSkill(
            [
              for (final r in row.effects)
                if (r.level == lv) r,
            ],
            k,
            _skillGekisouSupport,
            row.missionType,
          );
        }
      }
    }
  }

  final _notes = <int, LiveNote>{};
  final List<int> _byTime;
  final LiveRandom _random;
  late final LifeController life;
  final _combo = ComboCounter();
  late final IncrementalScore score;
  late final Conversion _conversion;
  final _rows = <_EffectRow>[];
  final _live = <_LiveSkill>[];
  final _livePools = <_LivePool>[];
  var _enabledLive = <int>[];
  final _cond = <_CondSkill>[];
  final _guards = <String, int>{};
  final _reductions = <String, int>{};
  final _limits = <String, int>{};
  final _frameEvents = <(int, int)>[];
  final _judged = <(int, int, int)>[];
  final _results = <(LiveNote, int)>[];
  int _firedCount = 0;
  late final CheckCtx _ctx;
  final trace = <(int, int)>[];
  int _frameTime = 0;
  int? _prevConfirmedRank;
  int _simulatorPreviousCombo = 0;
  int _currentCombo = 0;
  late final _ScoreCtl _scorectl;
  late final GekisouLive? gk;
  final _ga = _GkAppliers();
  final bool _finished = false;
  final List<(int, int)> _events;
  final LiveParams _params;
  final LuckRecord? _record;
  bool recordTrace = false;

  GekisouEnv _env() => GekisouEnv(_random, _scorectl);
  GekisouComboInfo? _info() => gk?.ctrl;

  /// Plays one frame at music time [t] with delta time [dt] in seconds.
  void frame(int t, List<JudgedNote> judged, double dt) {
    _frameTime = t;
    final frameRank = _prevConfirmedRank;
    _prevConfirmedRank = null;
    final gk = this.gk;
    if (gk != null) {
      gk.feverUpdates = gk.fever.update(t);
      gk.ctrl.beforeUpdate(dt, t, gk.feverUpdates, score.score, _env());
      _record?.frames.add(
        LuckFrame(
          [for (final s in gk.ctrl.states) s.state],
          [...gk.ctrl.stateUpdates],
          gk.ctrl.currentPlayingIndex,
        ),
      );
    }
    _frameEvents.clear();
    if (_firedCount < _events.length && _events[_byTime[_firedCount]].$2 <= t) {
      final due = <int>[];
      while (_firedCount < _events.length &&
          _events[_byTime[_firedCount]].$2 <= t) {
        due.add(_byTime[_firedCount++]);
      }
      if (due.length > 1) due.sort();
      for (final i in due) {
        _frameEvents.add(_events[i]);
      }
    }
    _judged.clear();
    final results = _results..clear();
    var broken = false;
    for (final j in judged) {
      final n =
          _notes[j.noteId] ?? (throw StateError('unknown note ${j.noteId}'));
      final conv = _conversion.convert(j.judgement, n.judgementType, j.timeMs);
      _combo.addJudgement(n.timeMs, conv);
      results.add((n, conv));
      _judged.add((n.id, conv, n.timeMs));
      if (conv == 1 || conv == 2) broken = true;
    }
    final simulatorCombo = _combo.timingCombo(t);
    final addedCombo = math.max(0, simulatorCombo - _simulatorPreviousCombo);
    _simulatorPreviousCombo = simulatorCombo;
    if (broken) _currentCombo = 0;
    _currentCombo = i32(_currentCombo + addedCombo);
    final notePercent = score.calc.settings.notePercent;
    for (final (n, conv) in results) {
      life.noteDamage(n.timeMs, conv);
      final lifeNow = life.lifeAt(n.timeMs);
      if (notePercent.containsKey(n.op)) {
        score.addNote(n.timeMs, lifeNow, n.id, n.op, _convertScoreType(conv));
      }
    }
    score.calculate(t, _combo, _info());
    final inp = FrameInput(t, _params.musicLengthMs, _finished);
    for (final si in _enabledLive) {
      _live[si].trigger = noTrigger;
    }
    var started = false;
    if (_frameEvents.isNotEmpty) {
      for (final pool in _livePools) {
        (int, int)? ev;
        for (var i = _frameEvents.length - 1; i >= 0; i--) {
          if (_frameEvents[i].$1 == pool.member) {
            ev = _frameEvents[i];
            break;
          }
        }
        if (ev == null) continue;
        if (pool.available.isEmpty) {
          throw StateError('live skill pool is empty');
        }
        final si = pool.available.removeAt(0);
        final s = _live[si];
        s.trigger = Trigger(true, ev.$2);
        for (final e in s.effects) {
          e.state.state = stay;
        }
        _enabledLive.add(si);
        started = true;
      }
    }
    if (started && _enabledLive.length > 1) {
      _enabledLive.sort(
        (a, b) =>
            (_live[a].key * 10 + _live[a].index) -
            (_live[b].key * 10 + _live[b].index),
      );
    }
    for (final c in _cond) {
      c.updater.beginFrame();
    }
    final ctx = _ctx
      ..frameTime = t
      ..currentCombo = _currentCombo
      ..prevConfirmedRank = frameRank;
    if (ctx.gk != null && gk != null) {
      ctx.gk = GkView(gk.ctrl, gk.prevLots, gk.prevLotMs);
    }
    for (var ph = 1; ph <= 2; ph++) {
      final listed = <_Listed>[];
      for (final si in _enabledLive) {
        final s = _live[si];
        if (s.parentState == endFrame) {
          s.parentState = stay;
          for (final e in s.effects) {
            e.state.state = stay;
          }
          continue;
        }
        var changed = false;
        for (final e in s.effects) {
          if (e.phase == ph) {
            changed = _updateLiveEffect(e, inp, s.trigger, ctx) || changed;
          }
        }
        if (changed) s.parentState = _aggregateLiveState(s.effects);
        for (final (ei, e) in s.effects.indexed) {
          if (e.state.state != stay && e.phase == ph) {
            listed.add(_Listed.live(si, ei));
          }
        }
      }
      for (var ui = 0; ui < _cond.length; ui++) {
        final updater = _cond[ui].updater;
        for (final x in updater.update(ph, inp, ctx)) {
          if (updater.updaters[x].state.state != stay) {
            listed.add(_Listed.cond(ui, x));
          }
        }
      }
      for (final item in listed) {
        _apply(item);
      }
    }
    if (_enabledLive.isNotEmpty) {
      var stayed = false;
      for (final si in _enabledLive) {
        final s = _live[si];
        if (s.parentState == stay) {
          final pool = _livePools
              .where((p) => p.key == s.key && p.member == s.member)
              .firstOrNull;
          if (pool == null) throw StateError('missing live skill pool');
          pool.available.add(si);
          stayed = true;
        }
      }
      if (stayed) {
        _enabledLive = [
          for (final si in _enabledLive)
            if (_live[si].parentState != stay) si,
        ];
      }
    }
    life.syncCurrent(t);
    score.calculate(t, _combo, _info());
    if (gk != null) _gekisouAfter(t, results);
    if (recordTrace) trace.add((t, score.score));
  }

  bool _updateLiveEffect(
    _LiveEffect e,
    FrameInput inp,
    Trigger trigger,
    CheckCtx ctx,
  ) {
    final before = e.state.state;
    final changed = effectUpdate(
      e.state,
      e.act,
      inp,
      trigger,
      e.condition,
      e.release,
      false,
      ctx,
    );
    if (e.cumulative case final c?) {
      final after = e.state.state;
      if ((before == stay && after == executeFrame) ||
          before == executeFrame ||
          (before == executing && after == executing)) {
        e.state.cumulativeCount = c.updateCount(ctx);
      } else if (before == endFrame) {
        c.reset();
      }
    }
    return changed;
  }

  void _gekisouAfter(int t, List<(LiveNote, int)> results) {
    final gk = this.gk!;
    final judged = [for (final (n, j) in results) (n.id, n.op, n.timeMs, j)];
    final record = _record;
    if (record != null) {
      final frame = record.frames.length - 1;
      for (final (r, range) in gk.ctrl.ranges.indexed) {
        if (range.mission != 2) continue;
        for (final (id, op, timeMs, judgement) in judged) {
          if (range.targets.contains(id) && judgement != 0 && judgement != 7) {
            record.notes.add(
              LuckNote(
                frame,
                r,
                op,
                judgement,
                timeMs,
                gk.ctrl.gaugeSpeedAt(timeMs),
                gk.ctrl.lotBuffAt(timeMs),
              ),
            );
          }
        }
      }
    }
    gk.ctrl.update(t, judged, gk.feverUpdates, score.score, _env());
    gk.prevLots = gk.ctrl.lotResults.isNotEmpty
        ? [...gk.ctrl.lotResults]
        : _noLots;
    gk.prevLotMs = gk.prevLots.isNotEmpty ? t : 0;
    final idx = gk.ctrl.stateUpdates
        .where((i) => gk.ctrl.states[i].state == sComplete)
        .firstOrNull;
    if (idx == null) return;
    final range = gk.ctrl.ranges[idx];
    final s0 = score.calculate(range.startMs, _combo, gk.ctrl);
    final s1 = score.calculate(range.endMs, _combo, gk.ctrl);
    gk.ctrl.states[idx].startScore = s0;
    gk.ctrl.states[idx].endScore = s1;
    if (idx < gk.factors.length) {
      final percent = gk.factors[idx][0];
      final p = gk.ctrl.states[idx].score * percent;
      final bonus = i32(p >= 0 ? (p / 100).floor() : -((-p) / 100).floor());
      score.addFixed(range.endMs, bonus);
      gk.rankBonus.add(RankBonus(idx, 1, bonus, percent));
      _prevConfirmedRank = 1;
    }
  }

  EffectState _state(_Listed item) => item.live
      ? _live[item.skill].effects[item.effect].state
      : _cond[item.updater].updater.updaters[item.u].state;

  void _apply(_Listed item) {
    int ri, k, ownerType, skillType;
    String key;
    if (item.live) {
      final s = _live[item.skill];
      ri = s.effects[item.effect].row;
      k = s.member;
      ownerType = _ownerMember;
      skillType = 1;
      key = 'L${_rows[ri].id}:${s.member}:${s.index}';
    } else {
      final c = _cond[item.updater];
      final upd = c.updater.updaters[item.u];
      final ef = c.updater.effects[upd.effect];
      ri = ef.row;
      k = c.member;
      ownerType = c.skillType == _skillGekisou ? _ownerMember : _ownerSnap;
      skillType = c.skillType;
      key = 'C${ef.effectId}:${upd.index}';
    }
    final st = _state(item);
    final owner = i32(imul(k, 100) + ownerType);
    final gkSkill =
        skillType == _skillGekisou || skillType == _skillGekisouSupport;
    final row = _rows[ri];
    final type = row.type;
    final gkType = _gekisouApplierTypes.contains(type);
    if ((gkType || type == 13001) && !gkSkill && gk == null) return;
    final record = _record;
    if (record != null && (type == 11003 || type == 11005)) {
      // The luck DP applies these with their chance; record the executions only.
      if (st.state == executeFrame && !item.live) {
        final c = _cond[item.updater];
        final ef = c.updater.effects[c.updater.updaters[item.u].effect];
        record.actions.add(
          LuckAction(
            record.frames.length - 1,
            gk!.ctrl.playingRangeIndex(),
            type,
            row.value,
            row.limitCount,
            chanceOf(ef.condition, _ctx),
          ),
        );
      }
      return;
    }
    if ((gkSkill || gkType) && _applyGekisou(row, st, owner, key)) return;
    final value = row.value;
    switch (type) {
      case 0 || 1000 || 1001 || 1002 || 1003 || 1500 || 1501 || 1502 || 1503:
        return;
      case 2000 || 2005:
        final m = noteFactorMill(f(f(value) / (type == 2005 ? -10000 : 10000)));
        if (st.state == executeFrame) {
          score.addFactor(FactorCommand(st.executeMs, owner, note: m));
        } else if (st.state == endFrame) {
          score.addFactor(FactorCommand(st.finishMs, owner, note: i32(-m)));
        }
      case 2001 || 2003:
        _applyCumulativeScore(row, st, owner, key);
      case 2002:
        final m = judgementFactorMill(f(f(value) / 10000));
        if (st.state == executeFrame) {
          score.addFactor(FactorCommand(st.executeMs, owner, combo: m));
        } else if (st.state == endFrame) {
          score.addFactor(FactorCommand(st.finishMs, owner, combo: i32(-m)));
        }
      case 2004:
        final m = judgementFactorMill(f(f(value) / 10000));
        for (final j in row.targets) {
          if (st.state == executeFrame) {
            score.addFactor(
              FactorCommand(st.executeMs, owner, judgement: j, judge: m),
            );
          } else if (st.state == endFrame) {
            score.addFactor(
              FactorCommand(st.finishMs, owner, judgement: j, judge: i32(-m)),
            );
          }
        }
      case 15000:
        if (st.state == executeFrame) _extend(k, f(value));
      case 3000:
        if (st.state == executeFrame) {
          if (_limits.containsKey(key)) {
            throw StateError('duplicate life limit effect state');
          }
          _limits[key] = life.addLimit(value);
        } else if (st.state == endFrame) {
          final id =
              _limits.remove(key) ??
              (throw StateError('missing life limit effect state'));
          life.subtractLimit(id);
        }
      case 3002:
        if (st.state == executeFrame) {
          life.skillDamage(st.executeMs, value, true);
        }
      case 3004:
        if (st.state == executeFrame) {
          if (_reductions.containsKey(key)) {
            throw StateError('duplicate damage reduction effect state');
          }
          _reductions[key] = life.enableReduction(st.executeMs, value);
        } else if (st.state == endFrame) {
          final id = _reductions.remove(key);
          if (id != null) life.disableReduction(st.finishMs, id);
        }
      case 3001:
        if (st.state == executeFrame) life.recovery(st.executeMs, value, true);
      case 3003:
        if (st.state == executeFrame) {
          if (_guards.containsKey(key)) {
            throw StateError('duplicate guard effect state');
          }
          _guards[key] = life.enableGuard(st.executeMs);
        } else if (st.state == endFrame) {
          final id =
              _guards[key] ?? (throw StateError('missing guard effect state'));
          life.disableGuard(st.finishMs, id);
          _guards.remove(key);
        }
      case 12006 || 13005:
        if (type == 13005 && gk == null) return;
        final t = _conversion.update(
          key,
          st.state,
          ConvertEffect(type, value, row.limitCount, row.targets, row.id),
        );
        if (t != null) {
          st.state = endFrame;
          st.finishMs = t;
        }
      default:
        throw StateError('unsupported skill effect type $type');
    }
  }

  void _applyCumulativeScore(
    _EffectRow row,
    EffectState st,
    int owner,
    String key,
  ) {
    final combo = row.type == 2003;
    var value = imul(row.value, st.cumulativeCount);
    if (row.maxValue > 0) value = math.min(value, row.maxValue);
    final factor = f(f(value) / 10000);
    final sc = _scorectl;
    int add(int t) => combo
        ? sc.addComboBonus(owner, t, factor)
        : sc.addNoteScoreUp(owner, t, factor);
    void disable(int t, int id) =>
        combo ? sc.disableComboBonus(t, id) : sc.disableNoteScoreUp(t, id);
    if (st.state == executeFrame) {
      _ga.add(key, add(st.executeMs));
    } else if (st.state == executing) {
      final id =
          _ga.ids[key] ?? (throw StateError('effect state not registered'));
      final old = combo ? sc.comboBonusFactor(id) : sc.scoreUpFactor(id);
      if (!_approximately(old, factor)) {
        disable(_frameTime, id);
        _ga.ids[key] = add(_frameTime);
      }
    } else if (st.state == endFrame) {
      disable(st.finishMs, _ga.pop(key));
    }
  }

  /// The Gekisou appliers; false when the effect type is not one of them.
  bool _applyGekisou(_EffectRow row, EffectState st, int owner, String key) {
    final et = row.type;
    final v = row.value;
    final frameT = _frameTime;
    final ga = _ga;
    final c = (gk ?? (throw StateError('Gekisou effect without Gekisou'))).ctrl;
    final s = st.state;
    switch (et) {
      case 12000 || 13000:
        if (s == executeFrame) {
          ga.add(
            key,
            et == 12000
                ? c.addComboBonus(st.executeMs, f(v).toInt())
                : c.addJustBonus(st.executeMs, f(v).toInt()),
          );
        } else if (s == endFrame) {
          final id = ga.pop(key);
          if (et == 12000) {
            c.subtractComboBonus(st.finishMs, id);
          } else {
            c.subtractJustBonus(st.finishMs, id);
          }
        }
        return true;
      case 13002:
        if (s == endFrame) {
          final id = ga.ids.remove(key);
          if (id != null) c.removeCumulativeRule(id);
        } else if (s == executeFrame && !ga.ids.containsKey(key)) {
          ga.ids[key] = c.addCumulativeRule(
            st.cumulativeUnit,
            v,
            st.cumulativeMax,
            row.maxValue,
          );
        }
        return true;
      case 11000 || 11001:
        if (s == executeFrame) {
          final value = f(f(v) / 10000);
          ga.add(
            key,
            et == 11000
                ? c.addLotProbabilityUp(st.executeMs, value)
                : c.addGaugeUp(st.executeMs, value),
          );
        } else if (s == endFrame) {
          final id = ga.pop(key);
          if (et == 11000) {
            c.subtractLotProbabilityUp(st.finishMs, id);
          } else {
            c.subtractGaugeUp(st.finishMs, id);
          }
        }
        return true;
      case 11002 || 11004 || 12002 || 12003 || 13003 || 13004:
        if (s == executeFrame) {
          var count = i32(v);
          if (et == 11004 || et == 12003 || et == 13004) {
            count = imul(count, st.cumulativeCount);
            if (row.maxValue > 0) count = math.min(count, row.maxValue);
          }
          if (et == 11002 || et == 11004) {
            c.addLuckPoint(count);
          } else if (et == 12002 || et == 12003) {
            c.addGekisouCombo(frameT, count);
          } else {
            c.addJustCount(frameT, count);
          }
        }
        return true;
      case 11003:
        if (s == executeFrame) {
          final g = i32(c.currentGaugeMax() * v);
          c.addLuckGaugePercent(floorToI32(f(f(g) / 10000)));
        }
        return true;
      case 12004:
        ga.limit(key, st);
        if (st.state == executeFrame) {
          var mask = 0;
          for (final j in row.targets) {
            if (j != 0 && j != -1) mask |= 1 << (j & 31);
          }
          ga.add(
            key,
            c.enableComboProtect(st.executeMs, row.limitCount, mask & 0xff),
          );
        } else if (st.state == endFrame && !ga.exhausted.remove(key)) {
          final id = ga.ids.remove(key);
          if (id != null) c.disableComboProtect(st.finishMs, id);
        }
        return true;
      case 11005:
        ga.limit(key, st);
        if (st.state == executeFrame) {
          ga.add(
            key,
            c.machine.enableMinimum(_minimumResultOf(v), row.limitCount),
          );
        } else if (st.state == executing) {
          final id = ga.ids[key];
          if (id != null && !c.machine.isMinimumActive(id)) {
            var t = c.machine.takeLastConsumed(id);
            if (t < 0) t = frameT;
            c.machine.disableMinimum(id);
            ga.ids.remove(key);
            ga.exhausted.add(key);
            ga.limitFinished[key] = t;
          }
        } else if (st.state == endFrame && !ga.exhausted.remove(key)) {
          final id = ga.ids.remove(key);
          if (id != null) c.machine.disableMinimum(id);
        }
        return true;
      case 2001:
        var n = i32(v * st.cumulativeCount);
        if (row.maxValue > 0 && row.maxValue < n) n = row.maxValue;
        final factor = f(f(n) / 10000);
        final sc = _scorectl;
        if (s == executeFrame) {
          ga.add(key, sc.addNoteScoreUp(owner, st.executeMs, factor));
        } else if (s == executing) {
          final id =
              ga.ids[key] ?? (throw StateError('effect state not registered'));
          if (!_approximately(sc.scoreUpFactor(id), factor)) {
            sc.disableNoteScoreUp(frameT, id);
            ga.ids[key] = sc.addNoteScoreUp(owner, frameT, factor);
          }
        } else if (s == endFrame) {
          sc.disableNoteScoreUp(st.finishMs, ga.pop(key));
        }
        return true;
      case 4004:
        return true;
      default:
        return false;
    }
  }

  void _extend(int member, double ms) {
    for (final s in _live) {
      if (s.member != member) continue;
      for (final e in s.effects) {
        if (e.state.state == executeFrame || e.state.state == executing) {
          e.state.extendedMs = f(e.state.extendedMs + ms);
        }
      }
    }
  }
}

int _aggregateLiveState(List<_LiveEffect> effects) {
  for (final state in const [executing, executeFrame, endFrame]) {
    if (effects.any((e) => e.state.state == state)) return state;
  }
  return stay;
}
