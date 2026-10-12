/// The client's live score: note score from the factor state, and the
/// incremental 40 ms frame log with undo (`engine/full/score.ts`). Undoing
/// a frame subtracts the float sum of each factor field the frame applied,
/// so the state after an undo can differ in the last bits from before the
/// frame ran; the score follows that state exactly.
library;

import '../num.dart';
import 'core.dart';

const scoreJust = 1;
const scorePerfect = 2;
const scoreGreat = 3;
const scoreGood = 4;
const _extraFrames = 50;
final _levelStep = f(0.005);

class FactorCommand {
  FactorCommand(
    this.timeMs,
    this.owner, {
    this.note = 0,
    this.combo = 0,
    this.judgement = 0,
    this.judge = 0,
    this.luck = 0,
  });
  final int timeMs;
  final int owner;
  final int note;
  final int combo;

  /// Note judgement (6 Just, 5 Perfect, 4 Great, 3 Good) of [judge].
  final int judgement;
  final int judge;
  final int luck;
}

/// `floor(factor * 100000f)` with the floor conversion's saturation.
int noteFactorMill(double factor) => floorToI32(f(factor * 100000));

/// `round((double)(factor * 100000f))` half to even.
int judgementFactorMill(double factor) {
  final x = f(factor * 100000);
  return x.isFinite ? floorToI32F64(roundTiesEven(x)) : floorToI32(x);
}

double _mill(int m) => m != 0 ? f(f(m) / 100000) : 0;

class FactorState {
  double combo = 0;
  double note = 1;
  double just = 0;
  double perfect = 0;
  double great = 0;
  double good = 0;
  int luck = 0;

  double judgementFactor(int scoreType) => switch (scoreType) {
    scoreJust => just,
    scorePerfect => perfect,
    scoreGreat => great,
    scoreGood => good,
    _ => 0,
  };

  void apply(FactorCommand cmd) {
    final fc = _mill(cmd.combo), fn = _mill(cmd.note), fj = _mill(cmd.judge);
    if (fc != 0) combo = f(combo + fc);
    if (fn != 0) note = f(note + fn);
    switch (cmd.judgement) {
      case 6:
        just = f(just + fj);
      case 5:
        perfect = f(perfect + fj);
      case 4:
        great = f(great + fj);
      case 3:
        good = f(good + fj);
    }
    luck = i32(luck + cmd.luck);
  }
}

class _FrameDiff {
  double combo = 0, note = 0, just = 0, perfect = 0, great = 0, good = 0;
  int luck = 0;

  void add(FactorCommand cmd) {
    luck = i32(luck + cmd.luck);
    final fc = _mill(cmd.combo), fn = _mill(cmd.note), fj = _mill(cmd.judge);
    if (fc != 0) combo = f(combo + fc);
    if (fn != 0) note = f(note + fn);
    switch (cmd.judgement) {
      case 6:
        just = f(just + fj);
      case 5:
        perfect = f(perfect + fj);
      case 4:
        great = f(great + fj);
      case 3:
        good = f(good + fj);
    }
  }

  void undo(FactorState s) {
    s.just = f(s.just - just);
    s.perfect = f(s.perfect - perfect);
    s.combo = f(s.combo - combo);
    s.note = f(s.note - note);
    s.luck = i32(s.luck - luck);
    s.great = f(s.great - great);
    s.good = f(s.good - good);
    combo = note = just = perfect = great = good = 0;
    luck = 0;
  }
}

/// Gekisou combo of the range covering a time, or null outside every combo range.
abstract interface class GekisouComboInfo {
  int? gekisouCombo(int timeMs);
}

class ScoreSettings {
  ScoreSettings({
    required this.adjustment,
    required this.lifeOnus,
    required this.notePercent,
    required this.judgePercent,
    required this.combo,
  });
  final double adjustment;
  final double lifeOnus;
  final Map<int, double> notePercent;
  final Map<int, double> judgePercent;

  /// Combo bonus type → ascending `[required count, cumulative factor]`.
  final Map<int, List<(int, double)>> combo;
}

typedef NoteObserver = void Function(
  int noteId,
  int scoreType,
  double note,
  double gk,
  double luck,
  double judge,
);

class ScoreCalculator {
  ScoreCalculator(
    this.settings,
    this.power,
    num level,
    this.convertedCount, [
    this.assist = 1,
  ]) : levelFactor = f(f(f(i32(level - 5)) * _levelStep) + 1);
  final FactorState state = FactorState();
  final ScoreSettings settings;
  final int power;
  final int convertedCount;
  final double assist;
  final double levelFactor;

  /// Optional observer of every executed note (the last execution is final).
  NoteObserver? onNote;

  double table(int type, int combo) {
    final rows = settings.combo[type];
    if (rows == null || rows.isEmpty || rows.first.$1 > combo) return 0;
    var lo = 0, hi = rows.length - 1;
    while (lo < hi) {
      final mid = lo + ((hi - lo) / 2).ceil();
      if (rows[mid].$1 > combo) {
        hi = mid - 1;
      } else {
        lo = mid;
      }
    }
    return rows[lo].$2;
  }

  double gekisouComboFactor(GekisouComboInfo? info, int timeMs) {
    final c = info?.gekisouCombo(timeMs);
    if (c == null) return 1;
    return f(minIgnoringNaN(table(1, c), 1) + 1);
  }

  int noteScore(
    int combo,
    int life,
    int timeMs,
    int op,
    int scoreType,
    GekisouComboInfo? info, [
    int noteId = 0,
  ]) {
    final cum = table(0, combo);
    final gk = gekisouComboFactor(info, timeMs);
    final scoreUp = f(state.note + state.judgementFactor(scoreType));
    final luckPercent = i32(state.luck + 100) < 200
        ? i32(state.luck + 100)
        : 200;
    final luck = f(f(luckPercent) / 100);
    final comboFactor = f(gk * f(state.combo + f(minIgnoringNaN(cum, 1) + 1)));
    onNote?.call(
      noteId,
      scoreType,
      state.note,
      gk,
      luck,
      state.judgementFactor(scoreType),
    );
    return noteScoreCore(life, op, scoreType, comboFactor, scoreUp, luck);
  }

  int noteScoreCore(
    int life,
    int op,
    int scoreType,
    double comboFactor,
    double scoreUp,
    double luck,
  ) {
    final notePct = settings.notePercent[op];
    final judgePct = settings.judgePercent[scoreType];
    if (notePct == null || judgePct == null) {
      throw StateError('score percent missing: note $op score $scoreType');
    }
    final lifeFactor = life > 0 ? 1.0 : settings.lifeOnus;
    final t = f(f(settings.adjustment * f(power)) * levelFactor);
    final a = f(f(f(notePct) / 100) * t);
    final b = f(f(f(judgePct) / 100) * a);
    final c = f(f(b * comboFactor) * scoreUp);
    final d = f(luck * c);
    final x = f(d / f(convertedCount));
    final floored = x.floorToDouble();
    final y = floored == double.infinity ? -2147483648.0 : f(satI32(floored));
    final z = f(assist * f(lifeFactor * y));
    return floorToI32(z);
  }
}

class NoteCommand {
  NoteCommand(this.timeMs, this.life, this.noteId, this.op, this.scoreType);
  final int timeMs;
  final int life;
  final int noteId;
  final int op;
  final int scoreType;
  int added = 0;
}

class IncrementalScore {
  IncrementalScore(this.calc, int musicLengthMs)
    : maxFrame = getFrame(musicLengthMs) + _extraFrames {
    _notes = List.filled(maxFrame, null);
    _factors = List.filled(maxFrame, null);
    _diffs = List.filled(maxFrame, null);
  }
  final ScoreCalculator calc;
  final int maxFrame;
  late final List<List<NoteCommand>?> _notes;
  late final List<List<FactorCommand>?> _factors;
  late final List<_FrameDiff?> _diffs;
  int _prev = -1;
  int _added = -1;
  int score = 0;
  final _fixed = <int, int>{};
  (int, int)? _pendingFixed;
  int rankBonus = 0;

  int _file(int t) {
    var frame = getFrame(t);
    if (maxFrame <= frame) frame = maxFrame - 1;
    _added = _added < 0 ? frame : (_added < frame ? _added : frame);
    return frame;
  }

  void addNote(int timeMs, int life, int noteId, int op, int scoreType) {
    final frame = _file(timeMs);
    (_notes[frame] ??= []).add(
      NoteCommand(timeMs, life, noteId, op, scoreType),
    );
  }

  void addFactor(FactorCommand cmd) {
    final frame = _file(cmd.timeMs);
    (_factors[frame] ??= []).add(cmd);
  }

  /// Every filed note with the score of its last execution.
  List<NoteCommand> filedNotes() => [for (final list in _notes) ...?list];

  /// Sets the fixed score filed by the next calculation.
  void addFixed(int timeMs, int score) => _pendingFixed = (timeMs, score);

  /// Brings the score to the frame of [t], undoing first down to the
  /// earliest frame that received a command.
  int calculate(int t, ComboCounter combo, GekisouComboInfo? info) {
    final g = getFrame(t);
    var to = g < 0 ? 0 : g;
    if (maxFrame <= g) to = maxFrame - 1;
    final u = _added < 0 ? to : (to < _added - 1 ? to : _added - 1);
    int start;
    if (u < _prev) {
      for (var frame = _prev; frame > u; frame--) {
        _undo(frame);
      }
      start = u + 1;
    } else {
      start = _prev + 1;
    }
    for (var frame = start; frame <= to; frame++) {
      _execute(frame, combo, info);
    }
    if (_pendingFixed case (final ft, final fs)) {
      _pendingFixed = null;
      final ff = getFrame(ft);
      if (_fixed.containsKey(ff)) {
        throw StateError('two fixed scores in one frame');
      }
      _fixed[ff] = fs;
      score = i32(score + fs);
    }
    _prev = to;
    _added = -1;
    return score;
  }

  void _undo(int frame) {
    final notes = _notes[frame];
    if (notes != null) {
      for (final n in notes) {
        score = i32(score - n.added);
      }
    }
    final v = _fixed[frame];
    if (v != null) score = i32(score - v);
    _diffs[frame]?.undo(calc.state);
  }

  void _execute(int frame, ComboCounter combo, GekisouComboInfo? info) {
    final fl = _factors[frame] ?? const <FactorCommand>[];
    final nl = _notes[frame] ?? const <NoteCommand>[];
    if (fl.isEmpty && nl.isEmpty) {
      final v = _fixed[frame];
      if (v != null) {
        score = i32(score + v);
        rankBonus = i32(rankBonus + v);
      }
      return;
    }
    final of = [for (var i = 0; i < fl.length; i++) i];
    if (fl.length > 1) {
      of.sort((a, b) {
        var d = fl[a].timeMs - fl[b].timeMs;
        if (d != 0) return d;
        d = fl[a].owner - fl[b].owner;
        return d != 0 ? d : a - b;
      });
    }
    final on = [for (var i = 0; i < nl.length; i++) i];
    if (nl.length > 1) {
      on.sort((a, b) {
        var d = nl[a].timeMs - nl[b].timeMs;
        if (d != 0) return d;
        d = nl[a].noteId - nl[b].noteId;
        return d != 0 ? d : a - b;
      });
    }
    var a = 0, b = 0;
    while (a < fl.length || b < nl.length) {
      if (a < fl.length &&
          (b >= nl.length || nl[on[b]].timeMs >= fl[of[a]].timeMs)) {
        final c = fl[of[a]];
        calc.state.apply(c);
        (_diffs[frame] ??= _FrameDiff()).add(c);
        a++;
      } else {
        final n = nl[on[b]];
        final s = calc.noteScore(
          combo.timingCombo(n.timeMs),
          n.life,
          n.timeMs,
          n.op,
          n.scoreType,
          info,
          n.noteId,
        );
        n.added = s;
        score = i32(score + s);
        b++;
      }
    }
    final v = _fixed[frame];
    if (v != null) {
      score = i32(score + v);
      rankBonus = i32(rankBonus + v);
    }
  }
}
