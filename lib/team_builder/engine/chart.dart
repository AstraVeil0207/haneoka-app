/// Chart compilation: judged notes in chart order with their static score
/// factors (`team-builder/engine/chart.ts`). Sources come from
/// [RuntimeChart], the app's port of the client's chart conversion.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../chart/runtime_chart.dart' show RuntimeChart;
import 'master.dart';
import 'num.dart';

class CompiledChart {
  CompiledChart({
    required this.key,
    required this.song,
    required this.difficulty,
    required this.count,
    required this.times,
    required this.noteTypes,
    required this.judgementTypes,
    required this.noteFrac,
    required this.convertedCount,
    required this.difficultyFactor,
    required this.skillTimes,
    required this.skillOrder,
    required this.feverMs,
    required this.durationMs,
    required this.lastNoteMs,
    required this.ranks,
    required this.skipNoteFrac,
  });
  final String key;
  final Song song;
  final SongDifficulty difficulty;
  final int count;
  final Int32List times;
  final Int32List noteTypes;
  final Int32List judgementTypes;

  /// Note percent / 100, binary32.
  final Float32List noteFrac;
  final int convertedCount;
  final double difficultyFactor;
  final List<int> skillTimes;

  /// Skill event indices in firing order (time, then index).
  final List<int> skillOrder;
  final List<(int, int)> feverMs;
  final int durationMs;
  final int lastNoteMs;

  /// Ascending score thresholds of the song's rank group.
  final List<ScoreRankRow> ranks;

  /// Skip: notes scored as Great with combo 0, life full and no skills.
  final Float32List skipNoteFrac;
}

String chartKey(int songId, int difficulty) => '$songId:$difficulty';

/// Gekisou lives use battle thresholds, not solo score thresholds.
int battleRank(CompiledChart chart, double score) {
  var rank = 2;
  for (final row in chart.ranks) {
    if (row.battleRequired > 0 &&
        row.battleRequired <= score &&
        row.rank > rank) {
      rank = row.rank;
    }
  }
  return rank;
}

double difficultyFactor(double playLevel) =>
    f(f((playLevel - 5) * f(0.005)) + 1);

/// Keeps only notes that score; skip-valid types exclude combo-only notes (120).
CompiledChart compileChart(
  EngineMaster master,
  Song song,
  SongDifficulty difficulty,
  RuntimeChart source,
) {
  final judged = [
    for (final note in source.notes)
      if (note.judged) note,
  ];
  final count = judged.length;
  final times = Int32List(count);
  final noteTypes = Int32List(count);
  final judgementTypes = Int32List(count);
  final noteFrac = Float32List(count);
  var percentSum = 0;
  for (final (index, note) in judged.indexed) {
    times[index] = note.timeMs;
    noteTypes[index] = note.operateType;
    judgementTypes[index] = note.judgementType;
    final percent = master.live.notePercent[note.operateType] ?? 0;
    percentSum = i32(percentSum + percent);
    noteFrac[index] = f(percent / 100);
  }
  // Skip: valid notes in enumeration order up to the frame of the last one
  // enumerated (frames of 40 ms, capped one frame before the live's end frame).
  int frame(int ms) => ms < 0 ? 0 : f(f(ms) / 40).ceil();
  final enumeration = source.enumeration;
  final lastTiming = enumeration.fold(
    0,
    (best, note) => math.max(best, note.timeMs),
  );
  final maxFrame = frame(lastTiming + 1000) + 50;
  final valid = [
    for (final note in enumeration)
      if (note.operateType != 120 &&
          master.live.notePercent.containsKey(note.operateType))
        note,
  ];
  int capped(int ms) => math.min(frame(ms), maxFrame - 1);
  final toFrame = valid.isNotEmpty
      ? math.max(0, capped(valid.last.timeMs))
      : -1;
  final skipNoteFrac = Float32List.fromList([
    for (final note in valid)
      if (capped(note.timeMs) <= toFrame)
        f((master.live.notePercent[note.operateType] ?? 0) / 100),
  ]);
  final skillTimes = source.skillTimesMs;
  final skillOrder = [for (var i = 0; i < skillTimes.length; i++) i]
    ..sort((a, b) {
      final d = skillTimes[a] - skillTimes[b];
      return d != 0 ? d : a - b;
    });
  return CompiledChart(
    key: chartKey(song.id, difficulty.difficulty),
    song: song,
    difficulty: difficulty,
    count: count,
    times: times,
    noteTypes: noteTypes,
    judgementTypes: judgementTypes,
    noteFrac: noteFrac,
    convertedCount: math.max(1, f(percentSum / 100).ceil()),
    difficultyFactor: difficultyFactor(difficulty.playLevel),
    skillTimes: skillTimes,
    skillOrder: skillOrder,
    feverMs: source.feverMs,
    durationMs: source.durationMs,
    lastNoteMs: count > 0 ? times[count - 1] : 0,
    ranks: master.scoreRanks[song.rankGroup] ?? const [],
    skipNoteFrac: skipNoteFrac,
  );
}

/// Live rank shown in play and used for rewards: the highest rank whose
/// threshold the score reaches.
int scoreRank(CompiledChart chart, double score) {
  var rank = 2;
  for (final row in chart.ranks) {
    if (row.required <= score && row.rank > rank) rank = row.rank;
  }
  return rank;
}
