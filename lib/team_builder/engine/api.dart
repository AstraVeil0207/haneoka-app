/// Serializable engine requests and their evaluation
/// (`team-builder/engine/api.ts`). Charts come from an injected loader.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../chart/runtime_chart.dart' show RuntimeChart;
import 'box.dart';
import 'chart.dart';
import 'full/play.dart' show Accuracy;
import 'gekiso.dart';
import 'gekiso_objective.dart';
import 'live.dart';
import 'master.dart';
import 'num.dart';
import 'objectives.dart';
import 'power.dart';
import 'pt_eligibility.dart';
import 'search.dart';
import 'skills.dart';

class SongRef {
  const SongRef(this.songId, this.difficulty);
  factory SongRef.fromJson(Map<String, Object?> json) => SongRef(
    (json['songId'] as num).toInt(),
    (json['difficulty'] as num).toInt(),
  );
  final int songId;
  final int difficulty;
  String get key => '$songId:$difficulty';
  Map<String, Object?> toJson() => {'songId': songId, 'difficulty': difficulty};
  @override
  bool operator ==(Object other) =>
      other is SongRef &&
      other.songId == songId &&
      other.difficulty == difficulty;
  @override
  int get hashCode => Object.hash(songId, difficulty);
}

Map<String, int?> _nullableInts(Object? value) => {
  for (final entry in objectRow(value).entries)
    entry.key: (entry.value as num?)?.toInt(),
};

class PlayerInput {
  const PlayerInput({
    this.characterRanks = const {},
    this.characterTotalRank,
    this.bandItems = const {},
    this.vipRank,
    this.characterMemory = const {},
    this.musicMemory = const {},
  });
  factory PlayerInput.fromJson(Map<String, Object?> json) => PlayerInput(
    characterRanks: _nullableInts(json['characterRanks']),
    characterTotalRank: (json['characterTotalRank'] as num?)?.toInt(),
    bandItems: _nullableInts(json['bandItems']),
    vipRank: (json['vipRank'] as num?)?.toInt(),
    characterMemory: _nullableInts(json['characterMemory']),
    musicMemory: _nullableInts(json['musicMemory']),
  );
  final Map<String, int?> characterRanks;
  final int? characterTotalRank;
  final Map<String, int?> bandItems;
  final int? vipRank;
  final Map<String, int?> characterMemory;
  final Map<String, int?> musicMemory;
  Map<String, Object?> toJson() => {
    'characterRanks': characterRanks,
    'characterTotalRank': characterTotalRank,
    'bandItems': bandItems,
    'vipRank': vipRank,
    'characterMemory': characterMemory,
    'musicMemory': musicMemory,
  };
}

class ConstraintInput {
  const ConstraintInput({
    this.requiredMembers = const [],
    this.excludedMembers = const [],
    this.requiredSnaps = const [],
    this.excludedSnaps = const [],
    this.leader,
    this.bindings = const [],
    this.noSnaps = false,
    this.minBonusPercent,
  });
  factory ConstraintInput.fromJson(Map<String, Object?> json) {
    List<String> strings(Object? value) => [
      for (final item in value as List? ?? const []) '$item',
    ];
    return ConstraintInput(
      requiredMembers: strings(json['requiredMembers']),
      excludedMembers: strings(json['excludedMembers']),
      requiredSnaps: strings(json['requiredSnaps']),
      excludedSnaps: strings(json['excludedSnaps']),
      leader: json['leader'] as String?,
      bindings: [
        for (final pair in json['bindings'] as List? ?? const [])
          ('${(pair as List)[0]}', pair[1] as String?),
      ],
      noSnaps: json['noSnaps'] == true,
      minBonusPercent: (json['minBonusPercent'] as num?)?.toDouble(),
    );
  }
  final List<String> requiredMembers;
  final List<String> excludedMembers;
  final List<String> requiredSnaps;
  final List<String> excludedSnaps;
  final String? leader;
  final List<(String, String?)> bindings;
  final bool noSnaps;
  Map<String, Object?> toJson() => {
    'requiredMembers': requiredMembers,
    'excludedMembers': excludedMembers,
    'requiredSnaps': requiredSnaps,
    'excludedSnaps': excludedSnaps,
    'leader': leader,
    'bindings': [
      for (final (member, snap) in bindings) [member, snap],
    ],
    'noSnaps': noSnaps,
    'minBonusPercent': minBonusPercent,
  };

  /// Event bonus floor in percent.
  final double? minBonusPercent;
}

sealed class Goal {
  const Goal();
  factory Goal.fromJson(Map<String, Object?> json) {
    List<SongRef> songs(Object? value) => [
      for (final song in value as List? ?? const [])
        SongRef.fromJson(objectRow(song)),
    ];
    PlayModel play() => PlayModel.fromJson(objectRow(json['play']));
    Criterion criterion() =>
        Criterion.values.byName('${json['criterion'] ?? 'mean'}');
    return switch (json['kind']) {
      'power' => PowerGoal(
        json['song'] == null ? null : SongRef.fromJson(objectRow(json['song'])),
        (json['challengeEventId'] as num?)?.toInt(),
      ),
      'score' => ScoreGoal(
        songs(json['songs']),
        criterion(),
        play(),
        (json['challengeEventId'] as num?)?.toInt(),
      ),
      'event' => EventGoal(
        measure: '${json['measure']}',
        route: RouteKind.values.byName('${json['route']}'),
        eventId: (json['eventId'] as num).toInt(),
        songs: songs(json['songs']),
        consumption: (json['consumption'] as num).toInt(),
        play: play(),
        ptOnly: json['ranking'] == 'pt-only',
        cpExchange: json['cpExchange'] is Map
            ? CpExchange(
                intOf(objectRow(json['cpExchange'])['numerator']),
                intOf(objectRow(json['cpExchange'])['denominator'], 1),
              )
            : null,
        gekiso: json['gekiso'] is Map
            ? (
                just: numOf(objectRow(json['gekiso'])['just']),
                luckSamples: intOf(objectRow(json['gekiso'])['luckSamples'], 1),
              )
            : null,
      ),
      'gekiso' => GekisoGoal(
        songs: songs(json['songs']),
        criterion: criterion(),
        accuracy: Accuracy(
          great: numOf(objectRow(json['accuracy'])['great']),
          just: numOf(objectRow(json['accuracy'])['just'], 1),
          missEvery: intOf(objectRow(json['accuracy'])['missEvery']),
        ),
        rank: intOf(json['rank'], 1),
        seeds: intOf(json['seeds']),
      ),
      'potential' => PotentialGoal(numOf(json['windowSeconds'], 100)),
      'plan' => PlanGoal(
        eventId: (json['eventId'] as num).toInt(),
        normalSongs: songs(json['normalSongs']),
        challengeSongs: songs(json['challengeSongs']),
        boostsPerLive: (json['boostsPerLive'] as num).toInt(),
        boostBudget: (json['boostBudget'] as num).toInt(),
        startingChallengePoints: (json['startingChallengePoints'] as num)
            .toInt(),
        challengePointsPerLive: (json['challengePointsPerLive'] as num).toInt(),
        play: play(),
      ),
      final kind => throw UnsupportedError('goal:$kind'),
    };
  }
}

class PowerGoal extends Goal {
  const PowerGoal(this.song, this.challengeEventId);
  final SongRef? song;
  final int? challengeEventId;
}

class ScoreGoal extends Goal {
  const ScoreGoal(this.songs, this.criterion, this.play, this.challengeEventId);
  final List<SongRef> songs;
  final Criterion criterion;
  final PlayModel play;
  final int? challengeEventId;
}

class EventGoal extends Goal {
  const EventGoal({
    required this.measure,
    required this.route,
    required this.eventId,
    required this.songs,
    required this.consumption,
    required this.play,
    this.ptOnly = false,
    this.cpExchange,
    this.gekiso,
  });

  /// Strict reward recommendation: exact inputs, AP solo/challenge lives,
  /// reward-only ordering (`ranking: "pt-only"`).
  final bool ptOnly;

  /// Best challenge payout per CP for this objective (solo trial only).
  final CpExchange? cpExchange;

  /// Non-challenge Gekisou rewards, using per-outcome settlement.
  final ({double just, int luckSamples})? gekiso;

  EventGoal copyWith({
    String? measure,
    RouteKind? route,
    List<SongRef>? songs,
    int? consumption,
    CpExchange? cpExchange,
    bool dropGekiso = false,
  }) => EventGoal(
    measure: measure ?? this.measure,
    route: route ?? this.route,
    eventId: eventId,
    songs: songs ?? this.songs,
    consumption: consumption ?? this.consumption,
    play: play,
    ptOnly: ptOnly,
    cpExchange: cpExchange ?? this.cpExchange,
    gekiso: dropGekiso ? null : gekiso,
  );

  Map<String, Object?> toJson() => {
    'kind': 'event',
    'measure': measure,
    'route': route.name,
    'eventId': eventId,
    'songs': [for (final song in songs) song.toJson()],
    'consumption': consumption,
    'play': play.toJson(),
    if (ptOnly) 'ranking': 'pt-only',
    if (cpExchange case final cp?)
      'cpExchange': {'numerator': cp.numerator, 'denominator': cp.denominator},
    if (gekiso case final g?)
      'gekiso': {'just': g.just, 'luckSamples': g.luckSamples, 'rank': 1},
  };

  /// `points`, `items` or `challenge-points`.
  final String measure;
  final RouteKind route;
  final int eventId;
  final List<SongRef> songs;

  /// Boosts per normal live (0–10) or challenge points per challenge live.
  final int consumption;
  final PlayModel play;
}

class GekisoGoal extends Goal {
  const GekisoGoal({
    required this.songs,
    required this.criterion,
    required this.accuracy,
    this.rank = 1,
    this.seeds = 0,
  });
  final List<SongRef> songs;
  final Criterion criterion;

  /// Share of notes hit Great, and of the Just-eligible rest hit Just.
  final Accuracy accuracy;

  /// Assumed placement in every range (1 for solo Mission lives).
  final int rank;

  /// Luck ranges: 0 takes the exact nominal lottery expectation; n > 0
  /// averages n native lottery seeds instead.
  final int seeds;
}

class PotentialGoal extends Goal {
  const PotentialGoal(this.windowSeconds);
  final double windowSeconds;
}

class PlanGoal extends Goal {
  const PlanGoal({
    required this.eventId,
    required this.normalSongs,
    required this.challengeSongs,
    required this.boostsPerLive,
    required this.boostBudget,
    required this.startingChallengePoints,
    required this.challengePointsPerLive,
    required this.play,
  });
  final int eventId;
  final List<SongRef> normalSongs;
  final List<SongRef> challengeSongs;
  final int boostsPerLive;
  final int boostBudget;
  final int startingChallengePoints;
  final int challengePointsPerLive;
  final PlayModel play;
}

class EngineRequest {
  EngineRequest({
    required this.members,
    required this.snaps,
    this.player = const PlayerInput(),
    this.unknownPolicy = UnknownPolicy.max,
    required this.goal,
    this.constraints = const ConstraintInput(),
    this.k = 5,
    this.timeLimitMs,
    this.rewardCutoff,
  });
  factory EngineRequest.fromJson(Map<String, Object?> json) => EngineRequest(
    members: [
      for (final row in json['members'] as List)
        MemberInput.fromJson(objectRow(row)),
    ],
    snaps: [
      for (final row in json['snaps'] as List)
        SnapInput.fromJson(objectRow(row)),
    ],
    player: PlayerInput.fromJson(objectRow(json['player'])),
    unknownPolicy: UnknownPolicy.values.byName(
      '${json['unknownPolicy'] ?? 'max'}',
    ),
    goal: Goal.fromJson(objectRow(json['goal'])),
    constraints: ConstraintInput.fromJson(objectRow(json['constraints'])),
    k: (json['k'] as num?)?.toInt() ?? 5,
    timeLimitMs: (json['timeLimitMs'] as num?)?.toDouble(),
    rewardCutoff: (json['rewardCutoff'] as num?)?.toDouble(),
  );

  /// Other songs' Top-K key. Only a pt-only k=1 request may prove this song
  /// strictly below the cutoff.
  final double? rewardCutoff;
  final List<MemberInput> members;
  final List<SnapInput> snaps;
  final PlayerInput player;
  final UnknownPolicy unknownPolicy;
  final Goal goal;
  final ConstraintInput constraints;
  final int k;
  final double? timeLimitMs;

  EngineRequest withGoal(
    Goal goal,
    double? timeLimitMs, {
    double? rewardCutoff,
  }) => EngineRequest(
    members: members,
    snaps: snaps,
    player: player,
    unknownPolicy: unknownPolicy,
    goal: goal,
    constraints: constraints,
    k: k,
    timeLimitMs: timeLimitMs,
    rewardCutoff: rewardCutoff,
  );

  /// Event requests only (the reward recommendation keeps them).
  Map<String, Object?> toJson() => {
    'members': [for (final row in members) row.toJson()],
    'snaps': [for (final row in snaps) row.toJson()],
    'player': player.toJson(),
    'unknownPolicy': unknownPolicy.name,
    'goal': (goal as EventGoal).toJson(),
    'constraints': constraints.toJson(),
    'k': k,
    'timeLimitMs': timeLimitMs,
  };
}

class HitScore {
  HitScore({
    required this.mean,
    required this.min,
    required this.max,
    required this.median,
    required this.worstOrder,
    required this.bestOrder,
    required this.orders,
    required this.ranks,
  });
  factory HitScore.fromJson(Map<String, Object?> json) => HitScore(
    mean: numOf(json['mean']),
    min: numOf(json['min']),
    max: numOf(json['max']),
    median: numOf(json['median']),
    worstOrder: [
      for (final key in json['worstOrder'] as List? ?? const []) '$key',
    ],
    bestOrder: [
      for (final key in json['bestOrder'] as List? ?? const []) '$key',
    ],
    orders: intListOf(json['orders']),
    ranks: {
      for (final entry in objectRow(json['ranks']).entries)
        int.parse(entry.key): intOf(entry.value),
    },
  );
  final double mean;
  final double min;
  final double max;
  final double median;

  /// Member keys at each chart skill event, for the worst and best orders.
  final List<String> worstOrder;
  final List<String> bestOrder;

  /// Score of every skill order, indexed like [orders].
  final List<int> orders;
  final Map<int, int> ranks;
  Map<String, Object?> toJson() => {
    'mean': mean,
    'min': min,
    'max': max,
    'median': median,
    'worstOrder': worstOrder,
    'bestOrder': bestOrder,
    'orders': orders,
    'ranks': {for (final e in ranks.entries) '${e.key}': e.value},
  };
}

class HitEvent {
  HitEvent({
    required this.mean,
    required this.bonusPercent,
    required this.challengePoints,
    required this.perPlayMin,
    required this.perPlayMax,
    this.rewardSum,
    this.comparisonSum,
    this.orders,
    this.directMean,
    this.convertedMean,
  });
  factory HitEvent.fromJson(Map<String, Object?> json) => HitEvent(
    mean: numOf(json['mean']),
    bonusPercent: numOf(json['bonusPercent']),
    challengePoints: numOf(json['challengePoints']),
    perPlayMin: numOf(json['perPlayMin']),
    perPlayMax: numOf(json['perPlayMax']),
    rewardSum: (json['rewardSum'] as num?)?.toDouble(),
    comparisonSum: (json['comparisonSum'] as num?)?.toDouble(),
    orders: (json['orders'] as num?)?.toInt(),
    directMean: (json['directMean'] as num?)?.toDouble(),
    convertedMean: (json['convertedMean'] as num?)?.toDouble(),
  );

  /// Exact order sums of the strict trial; mean includes CP conversion.
  final double? rewardSum;
  final double? comparisonSum;
  final int? orders;
  final double? directMean;
  final double? convertedMean;
  final double mean;
  final double bonusPercent;
  final double challengePoints;
  final double perPlayMin;
  final double perPlayMax;
  Map<String, Object?> toJson() => {
    'mean': mean,
    'bonusPercent': bonusPercent,
    'challengePoints': challengePoints,
    'perPlayMin': perPlayMin,
    'perPlayMax': perPlayMax,
    'rewardSum': ?rewardSum,
    'comparisonSum': ?comparisonSum,
    'orders': ?orders,
    'directMean': ?directMean,
    'convertedMean': ?convertedMean,
  };
}

class EngineHit {
  EngineHit({
    required this.song,
    required this.members,
    required this.snaps,
    required this.power,
    required this.slotPowers,
    required this.key,
  });
  factory EngineHit.fromJson(Map<String, Object?> json) =>
      EngineHit(
          song: json['song'] is Map
              ? SongRef.fromJson(objectRow(json['song']))
              : null,
          members: [for (final key in json['members'] as List) '$key'],
          snaps: [for (final key in json['snaps'] as List) key as String?],
          power: intOf(json['power']),
          slotPowers: intListOf(json['slotPowers']),
          key: numOf(json['key']),
        )
        ..score = json['score'] is Map
            ? HitScore.fromJson(objectRow(json['score']))
            : null
        ..skipScore = (json['skipScore'] as num?)?.toInt()
        ..event = json['event'] is Map
            ? HitEvent.fromJson(objectRow(json['event']))
            : null;
  final SongRef? song;

  /// Leader first.
  final List<String> members;
  final List<String?> snaps;
  final int power;
  final List<int> slotPowers;
  final double key;
  HitScore? score;
  int? skipScore;
  HitEvent? event;
  PotentialDetail? potential;

  Map<String, Object?> toJson() => {
    'song': song?.toJson(),
    'members': members,
    'snaps': snaps,
    'power': power,
    'slotPowers': slotPowers,
    'key': key,
    'score': score?.toJson(),
    'skipScore': skipScore,
    'event': event?.toJson(),
    'potential': potential == null
        ? null
        : {'value': potential!.potential, 'area': potential!.area},
  };
}

class SongResult {
  SongResult({
    required this.song,
    required this.hits,
    required this.proven,
    required this.bound,
    required this.stats,
    this.excludedBelow,
  });
  factory SongResult.fromJson(Map<String, Object?> json) => SongResult(
    song: json['song'] is Map
        ? SongRef.fromJson(objectRow(json['song']))
        : null,
    hits: [
      for (final hit in json['hits'] as List? ?? const [])
        EngineHit.fromJson(objectRow(hit)),
    ],
    proven: json['proven'] == true,
    bound: (json['bound'] as num?)?.toDouble(),
    stats: SearchStats(),
    excludedBelow: (json['excludedBelow'] as num?)?.toDouble(),
  );
  final SongRef? song;
  List<EngineHit> hits;
  bool proven;
  double? bound;
  final SearchStats stats;

  /// Exhaustive proof that no team in this scope reaches this key.
  double? excludedBelow;
  Map<String, Object?> toJson() => {
    'song': song?.toJson(),
    'proven': proven,
    'bound': bound,
    'excludedBelow': ?excludedBelow,
    'stats': stats.toJson(),
    'hits': [for (final hit in hits) hit.toJson()],
  };
}

class PlanSummary {
  PlanSummary({
    required this.normal,
    required this.challenge,
    required this.normalLives,
    required this.challengeLives,
    required this.challengePointsEarned,
    required this.leftoverChallengePoints,
    required this.eventPoints,
    required this.perBoost,
  });
  final EngineHit? normal;
  final EngineHit? challenge;
  final int normalLives;
  final int challengeLives;
  final int challengePointsEarned;
  final int leftoverChallengePoints;
  final double eventPoints;

  /// Event points per boost spent, over the whole cycle.
  final double perBoost;
}

class EngineResponse {
  EngineResponse({
    required this.results,
    required this.overall,
    required this.unknownCards,
    required this.elapsedMs,
    this.plan,
  });
  final PlanSummary? plan;
  final List<SongResult> results;

  /// Best (song, team) pairs over every song, distinct by song + member set.
  final List<EngineHit> overall;
  final List<String> unknownCards;
  final double elapsedMs;
  Map<String, Object?> toJson() => {
    'results': [for (final result in results) result.toJson()],
    'overall': [for (final hit in overall) hit.toJson()],
    'unknownCards': unknownCards,
    'elapsedMs': elapsedMs,
  };
}

typedef ChartLoader = Future<RuntimeChart> Function(SongRef song);

/// Compiled and prepared charts, keeping only a few recent ones.
class ChartCache {
  ChartCache(this.master, this.load);
  final EngineMaster master;
  final ChartLoader load;
  final _charts = <SongRef, Future<CompiledChart>>{};
  final _prepared = Expando<PreparedLive>();
  final _gekiso = <String, Future<GekisoChart>>{};

  /// The Gekisou chart of a song at a stated accuracy and assumed range rank.
  Future<GekisoChart> gekiso(SongRef ref, Accuracy accuracy, int rank) {
    final key =
        '${ref.key}:${accuracy.great}:${accuracy.just}:${accuracy.missEvery}:$rank';
    var value = _gekiso.remove(key);
    if (value == null) {
      final song = master.songs[ref.songId];
      final difficulty = song?.difficulties
          .where((item) => item.difficulty == ref.difficulty)
          .firstOrNull;
      if (song == null || difficulty == null) {
        return Future.error(RangeError('unknown-chart:${ref.key}'));
      }
      value = source(ref).then(
        (source) => gekisoChart(
          master,
          source,
          difficulty.playLevel,
          song.gekisoMissions,
          accuracy,
          rank,
        ),
      );
    }
    _gekiso[key] = value;
    if (_gekiso.length > 4) _gekiso.remove(_gekiso.keys.first);
    return value;
  }

  final _sources = <SongRef, Future<RuntimeChart>>{};

  /// The converted chart file, kept for the few most recent songs.
  Future<RuntimeChart> source(SongRef ref) {
    final value = _sources.remove(ref) ?? load(ref);
    _sources[ref] = value;
    if (_sources.length > 4) _sources.remove(_sources.keys.first);
    return value;
  }

  Future<CompiledChart> chart(SongRef ref) {
    var value = _charts.remove(ref);
    if (value == null) {
      final song = master.songs[ref.songId];
      final difficulty = song?.difficulties
          .where((item) => item.difficulty == ref.difficulty)
          .firstOrNull;
      if (song == null || difficulty == null) {
        return Future.error(RangeError('unknown-chart:${ref.key}'));
      }
      value = source(ref)
          .then((source) => compileChart(master, song, difficulty, source));
      final pending = value;
      pending.catchError((Object _) {
        if (identical(_charts[ref], pending)) _charts.remove(ref);
        return pending;
      });
    }
    _charts[ref] = value;
    if (_charts.length > 4) _charts.remove(_charts.keys.first);
    return value;
  }

  PreparedLive live(CompiledChart chart) =>
      _prepared[chart] ??= prepareLive(master, chart);
}

PlayerState playerState(EngineMaster master, PlayerInput input) {
  final ranks = <int, int>{
    for (final entry in input.characterRanks.entries)
      if ((entry.value ?? 0) != 0) int.parse(entry.key): entry.value!,
  };
  final total =
      input.characterTotalRank ??
      master.characters.keys.fold<int>(0, (sum, id) => sum + (ranks[id] ?? 1));
  Map<int, int> nonZero(Map<String, int?> record) => {
    for (final entry in record.entries)
      if ((entry.value ?? 0) != 0) int.parse(entry.key): entry.value!,
  };
  return PlayerState(
    characterRanks: ranks,
    totalRank: total,
    bandItems: nonZero(input.bandItems),
    vipRank: input.vipRank ?? 1,
    characterMemory: nonZero(input.characterMemory),
    musicMemory: nonZero(input.musicMemory),
  );
}

/// Song view of a chart; a challenge song uses its own nonzero music type.
MusicView musicView(EngineMaster master, int songId, int? challengeEventId) {
  final song = master.songs[songId]!;
  var musicType = song.musicType;
  if (challengeEventId != null) {
    final challenge = master.challengeMusics
        .where(
          (row) => row.eventId == challengeEventId && row.liveMusicId == songId,
        )
        .firstOrNull;
    if ((challenge?.musicType ?? 0) != 0) musicType = challenge!.musicType;
  }
  return MusicView(musicType, song.bestTags, songId);
}

const liveBoostCosts = [0, 1, 2, 3, 4, 5, 10];

EventRoute eventRoute(
  EngineMaster master,
  int eventId,
  RouteKind route,
  int consumption,
) {
  final event = master.events[eventId];
  if (event == null) throw RangeError('unknown-event:$eventId');
  final challenge =
      route == RouteKind.challenge ||
      (route == RouteKind.skip && consumption > 10);
  if (!challenge && !liveBoostCosts.contains(consumption)) {
    throw StateError('unsupported-live-boost-cost');
  }
  final table = challenge ? master.challengeBoosts : master.boosts;
  final row = table.where((item) => item.consumed == consumption).firstOrNull;
  final rate = challenge
      ? row?.eventPointRate ?? 1
      : consumption < 1
      ? 1.0
      : row?.eventPointRate ?? 1;
  final rewardRate = challenge
      ? row?.rewardRate ?? 1
      : consumption < 1
      ? 1.0
      : row?.rewardRate ?? 1;
  return EventRoute(
    kind: route,
    rate: rate,
    rewardRate: rewardRate,
    points: challenge ? event.challengePoints : event.livePoints,
    rewards: challenge ? event.challengeRewards : event.liveRewards,
    itemId: event.itemId,
    challengePoints: master.liveChallengePoints,
    effects: event.effects,
  );
}

Constraints constraintsOf(
  ConstraintInput input,
  List<MemberState> members,
  List<SnapState> snaps,
) {
  final memberIndex = {
    for (final (index, member) in members.indexed) member.key: index,
  };
  final snapIndex = {
    for (final (index, snap) in snaps.indexed) snap.key: index,
  };
  List<int> ids(List<String> keys, Map<String, int> index) => [
    for (final key in keys) ?index[key],
  ];
  final bindings = <int, int>{};
  for (final (member, snap) in input.bindings) {
    final i = memberIndex[member];
    if (i == null) continue;
    if (snap == null) {
      bindings[i] = -1;
    } else if (snapIndex[snap] case final j?) {
      bindings[i] = j;
    }
  }
  return Constraints(
    requiredMembers: ids(input.requiredMembers, memberIndex),
    excludedMembers: ids(input.excludedMembers, memberIndex),
    requiredSnaps: ids(input.requiredSnaps, snapIndex),
    excludedSnaps: ids(input.excludedSnaps, snapIndex),
    leader: input.leader != null ? (memberIndex[input.leader] ?? -1) : null,
    bindings: bindings,
    noSnaps: input.noSnaps,
    minBonus: input.minBonusPercent == null
        ? null
        : jsRound(input.minBonusPercent! * 100).toDouble(),
  );
}

double _median(Float64List values) {
  final sorted = Float64List.fromList(values)..sort();
  return (sorted[59] + sorted[60]) / 2;
}

HitScore scoreSummary(
  OrderScores scores,
  CompiledChart chart,
  Team team,
  List<MemberState> members, [
  bool battle = false,
]) {
  List<String> keysOf(List<int> order) => [
    for (final slot in order) members[team.members[slot]].key,
  ];
  final ranks = <int, int>{};
  for (final value in scores.scores) {
    final rank = battle ? battleRank(chart, value) : scoreRank(chart, value);
    ranks[rank] = (ranks[rank] ?? 0) + 1;
  }
  return HitScore(
    mean: scores.mean,
    min: scores.min,
    max: scores.max,
    median: _median(scores.scores),
    worstOrder: keysOf(orders[scores.minOrder]),
    bestOrder: keysOf(orders[scores.maxOrder]),
    orders: [for (final score in scores.scores) jsRound(score)],
    ranks: ranks,
  );
}

/// Higher key first; equal keys prefer the higher mean score.
int compareHits(EngineHit a, EngineHit b) {
  final d = b.key.compareTo(a.key);
  return d != 0 ? d : (b.score?.mean ?? 0).compareTo(a.score?.mean ?? 0);
}

List<EngineHit> _overall(List<SongResult> results, int k) => stableSorted([
  for (final result in results) ...result.hits,
], compareHits).take(math.max(k, 3)).toList();

typedef Progress = void Function(int done, int total);

final _eventPrep = <String, ({List<Team> seeds, double? aspiration})>{};
final _scoreCaps = <String, double>{};

/// Runs a request. [cancelled] stops every search early (results stay exact
/// but unproven).
Future<EngineResponse> runEngine(
  EngineMaster master,
  ChartCache charts,
  EngineRequest request, {
  Progress? onProgress,
  bool Function()? cancelled,
  String? fingerprint,
}) async {
  final clock = Stopwatch()..start();
  double now() => clock.elapsedMicroseconds / 1000;
  final goal = request.goal;
  final ptTrial = goal is EventGoal && goal.ptOnly;
  final rewardCutoff = request.rewardCutoff;
  if (rewardCutoff != null &&
      (!ptTrial || request.k != 1 || !rewardCutoff.isFinite)) {
    throw StateError('invalid-reward-cutoff');
  }
  if (ptTrial) {
    final issues = validatePtRequest(master, request);
    if (issues.isNotEmpty) {
      throw StateError('pt-input:${[for (final i in issues) i.key].join(',')}');
    }
  }
  if (goal is PlanGoal) {
    return _runPlan(
      master,
      charts,
      request,
      goal,
      clock,
      onProgress,
      cancelled,
    );
  }
  final box = resolveBox(
    master,
    request.members,
    request.snaps,
    request.unknownPolicy,
  );
  final members = box.members, snaps = box.snaps;
  final player = playerState(master, request.player);
  final constraints = constraintsOf(request.constraints, members, snaps);
  final shared = Shared(master, members, snaps);
  final results = <SongResult>[];
  EngineHit toHit(SongRef? song, SearchHit<Object?> hit, [double? key]) =>
      EngineHit(
        song: song,
        members: [for (final i in hit.team.members) members[i].key],
        snaps: [for (final j in hit.team.snaps) j < 0 ? null : snaps[j].key],
        power: hit.power,
        slotPowers: hit.slotPowers,
        key: key ?? hit.key,
      );
  final songs = switch (goal) {
    PowerGoal(:final song) => <SongRef?>[song],
    PotentialGoal() => <SongRef?>[null],
    EventGoal(route: RouteKind.skip, songs: final s) when s.isEmpty =>
      <SongRef?>[null],
    EventGoal(:final songs) => <SongRef?>[...songs],
    ScoreGoal(:final songs) => <SongRef?>[...songs],
    GekisoGoal(:final songs) => <SongRef?>[...songs],
    PlanGoal() => <SongRef?>[],
  };
  final budgetEnd = request.timeLimitMs == null ? inf : request.timeLimitMs!;
  var songsLeft = songs.length;
  double songBudget() => budgetEnd == inf
      ? inf
      : math.max(250, (budgetEnd - now()) / math.max(1, songsLeft));
  SearchOutput<D> run<D>(
    ObjectiveAdapter<D> objective,
    MusicView? music,
    List<EventEffectRow> powerEffects, {
    int? k,
    List<Team>? seeds,
    double? limitMs,
    double? floor,
  }) => searchTeams(
    master: master,
    player: player,
    members: members,
    snaps: snaps,
    music: music,
    objective: objective,
    constraints: constraints,
    k: k ?? request.k,
    seeds: seeds,
    floor: floor,
    timeLimitMs: limitMs ?? songBudget(),
    cancelled: cancelled,
    memberPowerPercent: powerEffects.isNotEmpty
        ? (member) => memberEventPercent(powerEffects, member)
        : null,
    snapPowerPercent: powerEffects.isNotEmpty
        ? (snap) => snapEventPercent(powerEffects, snap)
        : null,
  );
  for (final (index, song) in songs.indexed) {
    if (ptTrial && song != null) {
      validatePtChart(master, song, await charts.source(song));
    }
    songsLeft = songs.length - index;
    onProgress?.call(index, songs.length);
    final challengeId = switch (goal) {
      PowerGoal(:final challengeEventId) => challengeEventId,
      ScoreGoal(:final challengeEventId) => challengeEventId,
      EventGoal(route: RouteKind.challenge, :final eventId) => eventId,
      _ => null,
    };
    final music = song != null
        ? musicView(master, song.songId, challengeId)
        : null;
    final powerEffects = challengeId != null
        ? master.events[challengeId]?.effects ?? const <EventEffectRow>[]
        : const <EventEffectRow>[];
    final chart = song != null && goal is! PowerGoal
        ? await charts.chart(song)
        : null;
    final live = chart != null ? charts.live(chart) : null;
    switch (goal) {
      case PowerGoal():
        final out = run(powerObjective(), music, powerEffects);
        final compiled = song != null ? await charts.chart(song) : null;
        results.add(
          SongResult(
            song: song,
            proven: out.proven,
            bound: out.bound,
            stats: out.stats,
            hits: [
              for (final hit in out.hits)
                toHit(song, hit)
                  ..skipScore = compiled == null
                      ? null
                      : skipScore(master, compiled, hit.power),
            ],
          ),
        );
      case ScoreGoal():
        final context = LiveContext(master, members, snaps, live!, goal.play);
        final objective = liveScoreObjective(context, goal.criterion);
        // Loose-bound plays start from the best all-Perfect teams.
        final seeds = objective.hard
            ? [
                for (final hit in run(
                  liveScoreObjective(
                    LiveContext(master, members, snaps, live, ap),
                    goal.criterion,
                  ),
                  music,
                  powerEffects,
                  k: math.max(20, request.k * 3),
                ).hits)
                  hit.team,
              ]
            : null;
        final out = run(objective, music, powerEffects, seeds: seeds);
        results.add(
          SongResult(
            song: song,
            proven: out.proven,
            bound: out.bound,
            stats: out.stats,
            hits: [
              for (final hit in out.hits)
                toHit(song, hit)
                  ..score = scoreSummary(
                    hit.detail.scores,
                    chart!,
                    hit.team,
                    members,
                  ),
            ],
          ),
        );
      case EventGoal():
        final route = eventRoute(
          master,
          goal.eventId,
          goal.route,
          goal.consumption,
        );
        final points = goal.measure != 'items';
        final played = chart != null && goal.route != RouteKind.skip;
        final context = played
            ? LiveContext(master, members, snaps, live!, goal.play)
            : null;
        final measured = played && goal.measure != 'challenge-points';
        // Under another song's cutoff, the uncapped bounds alone usually
        // prove this song cannot reach it.
        if (rewardCutoff != null && measured) {
          final quick = eventObjective(
            shared,
            context,
            chart,
            route,
            points,
            master.params.skipRank,
            ptOnly: goal.ptOnly,
            exchange: goal.cpExchange,
          );
          final probe = run(
            quick,
            music,
            powerEffects,
            limitMs: 150,
            floor: rewardCutoff,
          );
          if (probe.proven &&
              !probe.hits.any((hit) => hit.key >= rewardCutoff)) {
            results.add(
              SongResult(
                song: song,
                proven: false,
                bound: rewardCutoff,
                excludedBelow: rewardCutoff,
                stats: probe.stats,
                hits: [],
              ),
            );
            continue;
          }
        }
        var scoreCap = inf;
        if (played) {
          final capKey =
              'cap|${fingerprint ?? identityHashCode(request)}|${song!.key}';
          final cached = _scoreCaps[capKey];
          if (cached != null) {
            scoreCap = cached;
          } else {
            final best = run(
              scoreCapObjective(context!),
              music,
              powerEffects,
              k: 1,
              limitMs: songBudget() / 4,
            );
            final top = best.hits.firstOrNull?.key ?? inf;
            scoreCap = best.proven ? top : math.max(top, best.bound ?? inf);
            if (_scoreCaps.length > 64) _scoreCaps.clear();
            _scoreCaps[capKey] = scoreCap;
          }
        }
        final objective = eventObjective(
          shared,
          played ? context : null,
          played ? chart : null,
          route,
          points,
          master.params.skipRank,
          scoreCap: scoreCap,
          ptOnly: goal.ptOnly,
          exchange: goal.cpExchange,
        );
        var adapter = objective;
        if (goal.measure == 'challenge-points' && chart != null) {
          adapter = challengePointObjective(
            liveScoreObjective(
              LiveContext(master, members, snaps, live!, goal.play),
              Criterion.mean,
            ),
            chart,
            route,
          );
        }
        SearchOutput<EventDetail> out;
        if (played && goal.measure != 'challenge-points') {
          // Seeds along the bonus/power front, and a floor at the k-th best seed's key.
          final prepKey =
              '${fingerprint ?? identityHashCode(request)}|${song!.key}';
          var prep = _eventPrep[prepKey];
          if (prep == null) {
            final seeds = <Team>[];
            for (final weight in const [
              16777216.0,
              64.0,
              32.0,
              16.0,
              8.0,
              4.0,
              2.0,
            ]) {
              seeds.addAll([
                for (final hit in run(
                  eventBonusSurrogate(shared, route.effects, points, weight),
                  music,
                  powerEffects,
                  limitMs: 100,
                ).hits)
                  hit.team,
              ]);
            }
            final probe = run(
              adapter,
              music,
              powerEffects,
              seeds: seeds,
              limitMs: 1,
            );
            prep = (
              seeds: seeds,
              aspiration: probe.hits.length >= request.k
                  ? probe.hits[request.k - 1].key
                  : null,
            );
            if (_eventPrep.length > 64) _eventPrep.clear();
            _eventPrep[prepKey] = prep;
          }
          final floor = prep.aspiration;
          final searchFloor = math.max(floor ?? -inf, rewardCutoff ?? -inf);
          out = run(
            adapter,
            music,
            powerEffects,
            seeds: prep.seeds,
            floor: searchFloor.isFinite ? searchFloor : null,
          );
          final enough =
              out.hits
                  .where((hit) => floor == null || hit.key >= floor)
                  .length >=
              request.k;
          if (!enough && rewardCutoff == null) {
            out = run(adapter, music, powerEffects, seeds: prep.seeds);
          }
        } else {
          out = run(adapter, music, powerEffects);
        }
        // Teams tied at one reward are ordered by mean score.
        var hits = out.hits;
        var proven = out.proven;
        var bound = out.bound;
        if (hits.isNotEmpty && measured && !goal.ptOnly) {
          final ordered = <SearchHit<EventDetail>>[];
          final keys = {for (final hit in hits) hit.key}.toList()
            ..sort((a, b) => b.compareTo(a));
          for (final key in keys) {
            if (ordered.length >= request.k) break;
            final group = [
              for (final hit in hits)
                if (hit.key == key) hit.team,
            ];
            final tie = run(
              eventScoreTieObjective(context!, objective, key, [
                for (final hit in ordered) hit.team,
              ]),
              music,
              powerEffects,
              k: request.k - ordered.length,
              seeds: group,
              floor: 0,
            );
            if (!tie.proven) {
              proven = false;
              bound = math.max(bound ?? -inf, key);
            }
            out.stats.add(tie.stats);
            for (final hit in tie.hits) {
              if (hit.key < 0) continue;
              ordered.add(
                SearchHit(
                  hit.team,
                  hit.power,
                  hit.slotPowers,
                  hit.totals,
                  key,
                  objective.exact(hit.team, hit.power, hit.slotPowers).detail,
                ),
              );
            }
          }
          hits = ordered.take(request.k).toList();
        }
        results.add(
          SongResult(
            song: song,
            proven: proven,
            bound: bound,
            stats: out.stats,
            hits: [
              for (final hit in hits)
                () {
                  final detail = hit.detail;
                  final base = toHit(song, hit);
                  if (detail.live != null && chart != null) {
                    base.score = scoreSummary(
                      detail.live!.scores,
                      chart,
                      hit.team,
                      members,
                    );
                  }
                  final perOrder = detail.perOrder;
                  final exchange = goal.cpExchange;
                  return base
                    ..event = HitEvent(
                      rewardSum: ptTrial ? detail.rewardSum : null,
                      comparisonSum: ptTrial ? detail.comparisonSum : null,
                      orders: ptTrial ? orders.length : null,
                      directMean: ptTrial && detail.rewardSum != null
                          ? detail.rewardSum! / orders.length
                          : null,
                      convertedMean: !ptTrial
                          ? null
                          : exchange != null
                          ? detail.challengePoints *
                                exchange.numerator /
                                exchange.denominator
                          : 0,
                      mean: detail.mean / (exchange?.denominator ?? 1),
                      bonusPercent: detail.bonus / 100,
                      challengePoints: detail.challengePoints,
                      perPlayMin:
                          detail.directMin ??
                          (perOrder != null
                              ? perOrder.reduce(math.min)
                              : detail.mean),
                      perPlayMax:
                          detail.directMax ??
                          (perOrder != null
                              ? perOrder.reduce(math.max)
                              : detail.mean),
                    );
                }(),
            ],
          ),
        );
      case GekisoGoal():
        final gekiso = await charts.gekiso(song!, goal.accuracy, goal.rank);
        final out = gekisoSearch(
          master: master,
          player: player,
          members: members,
          snaps: snaps,
          music: music,
          chart: gekiso,
          // 0 seeds: the exact nominal luck expectation.
          seeds: [for (var i = 0; i < goal.seeds; i++) i],
          criterion: goal.criterion,
          constraints: constraints,
          k: request.k,
          timeLimitMs: songBudget(),
          cancelled: cancelled,
        );
        results.add(
          SongResult(
            song: song,
            proven: out.proven,
            bound: out.bound,
            stats: out.stats,
            hits: [
              for (final hit in out.hits)
                toHit(song, hit)
                  ..score = scoreSummary(
                    hit.detail.scores,
                    chart!,
                    hit.team,
                    members,
                    true,
                  ),
            ],
          ),
        );
      case PotentialGoal():
        final out = run(
          potentialObjective(shared, goal.windowSeconds),
          null,
          const [],
        );
        results.add(
          SongResult(
            song: null,
            proven: out.proven,
            bound: out.bound,
            stats: out.stats,
            hits: [
              for (final hit in out.hits)
                toHit(null, hit)..potential = hit.detail,
            ],
          ),
        );
      case PlanGoal():
        break;
    }
    if (rewardCutoff != null && results.isNotEmpty) {
      final result = results.last;
      result.hits = [
        for (final hit in result.hits)
          if (hit.key >= rewardCutoff) hit,
      ];
      if (result.proven && result.hits.isEmpty) {
        result.excludedBelow = rewardCutoff;
        result.proven = false;
        result.bound = rewardCutoff;
      }
    }
  }
  return EngineResponse(
    results: results,
    overall: _overall(results, request.k),
    unknownCards: box.unknown,
    elapsedMs: now(),
  );
}

Future<EngineResponse> _runPlan(
  EngineMaster master,
  ChartCache charts,
  EngineRequest request,
  PlanGoal goal,
  Stopwatch clock,
  Progress? onProgress,
  bool Function()? cancelled,
) async {
  double now() => clock.elapsedMicroseconds / 1000;
  final total = goal.challengeSongs.length + goal.normalSongs.length;
  var done = 0;
  void step(int inner, int _) => onProgress?.call(done + inner, total);
  final budget = request.timeLimitMs;
  final budgetEnd = budget ?? inf;
  // Challenge stage first: its best points per challenge point prices what normal lives earn.
  final challenge = await runEngine(
    master,
    charts,
    request.withGoal(
      EventGoal(
        measure: 'points',
        route: RouteKind.challenge,
        eventId: goal.eventId,
        songs: goal.challengeSongs,
        consumption: goal.challengePointsPerLive,
        play: goal.play,
      ),
      budget == null
          ? null
          : budget * goal.challengeSongs.length / math.max(1, total),
    ),
    onProgress: step,
    cancelled: cancelled,
  );
  done += goal.challengeSongs.length;
  final bestChallenge = challenge.overall.firstOrNull;
  final pointsPerChallenge = bestChallenge?.event?.mean ?? 0;
  final weight = goal.challengePointsPerLive > 0
      ? pointsPerChallenge / goal.challengePointsPerLive
      : 0.0;
  final box = resolveBox(
    master,
    request.members,
    request.snaps,
    request.unknownPolicy,
  );
  final player = playerState(master, request.player);
  final constraints = constraintsOf(
    request.constraints,
    box.members,
    box.snaps,
  );
  final shared = Shared(master, box.members, box.snaps);
  final route = eventRoute(
    master,
    goal.eventId,
    RouteKind.live,
    goal.boostsPerLive,
  );
  final normalResults = <SongResult>[];
  for (final (index, song) in goal.normalSongs.indexed) {
    step(index, total);
    final chart = await charts.chart(song);
    final live = charts.live(chart);
    final music = musicView(master, song.songId, null);
    final songBudget = budgetEnd == inf
        ? inf
        : math.max(
            250.0,
            (budgetEnd - now()) / math.max(1, goal.normalSongs.length - index),
          );
    final context = LiveContext(
      master,
      box.members,
      box.snaps,
      live,
      goal.play,
    );
    final best = searchTeams(
      master: master,
      player: player,
      members: box.members,
      snaps: box.snaps,
      music: music,
      objective: scoreCapObjective(context),
      constraints: constraints,
      k: 1,
      timeLimitMs: songBudget / 4,
      cancelled: cancelled,
    );
    final top = best.hits.firstOrNull?.key ?? inf;
    final scoreCap = best.proven ? top : math.max(top, best.bound ?? inf);
    final objective = eventObjective(
      shared,
      context,
      chart,
      route,
      true,
      master.params.skipRank,
      challengePointWeight: weight,
      scoreCap: scoreCap,
    );
    final out = searchTeams(
      master: master,
      player: player,
      members: box.members,
      snaps: box.snaps,
      music: music,
      objective: objective,
      constraints: constraints,
      k: request.k,
      timeLimitMs: songBudget,
      cancelled: cancelled,
    );
    normalResults.add(
      SongResult(
        song: song,
        proven: out.proven,
        bound: out.bound,
        stats: out.stats,
        hits: [
          for (final hit in out.hits)
            () {
              final detail = hit.detail;
              final perOrder = detail.perOrder;
              final pointsOnly = perOrder != null
                  ? perOrder.fold(0.0, (a, b) => a + b) / perOrder.length
                  : 0.0;
              return EngineHit(
                  song: song,
                  members: [
                    for (final i in hit.team.members) box.members[i].key,
                  ],
                  snaps: [
                    for (final j in hit.team.snaps)
                      j < 0 ? null : box.snaps[j].key,
                  ],
                  power: hit.power,
                  slotPowers: hit.slotPowers,
                  key: hit.key,
                )
                ..score = detail.live == null
                    ? null
                    : scoreSummary(
                        detail.live!.scores,
                        chart,
                        hit.team,
                        box.members,
                      )
                // perOrder includes the challenge-point weight; report plain points per play.
                ..event = HitEvent(
                  mean: pointsOnly - weight * detail.challengePoints,
                  bonusPercent: detail.bonus / 100,
                  challengePoints: detail.challengePoints,
                  perPlayMin: 0,
                  perPlayMax: 0,
                );
            }(),
        ],
      ),
    );
  }
  final bestNormal = ([
    for (final r in normalResults) ...r.hits,
  ]..sort(compareHits)).firstOrNull;
  final lives = goal.boostsPerLive > 0
      ? goal.boostBudget ~/ goal.boostsPerLive
      : goal.boostBudget;
  final earned = (lives * (bestNormal?.event?.challengePoints ?? 0)).floor();
  final pool = goal.startingChallengePoints + earned;
  final challengeLives = goal.challengePointsPerLive > 0
      ? pool ~/ goal.challengePointsPerLive
      : 0;
  final eventPointsTotal =
      lives * (bestNormal?.event?.mean ?? 0) +
      challengeLives * pointsPerChallenge;
  return EngineResponse(
    plan: PlanSummary(
      normal: bestNormal,
      challenge: bestChallenge,
      normalLives: lives,
      challengeLives: challengeLives,
      challengePointsEarned: earned,
      leftoverChallengePoints:
          pool - challengeLives * goal.challengePointsPerLive,
      eventPoints: eventPointsTotal,
      perBoost: goal.boostBudget != 0
          ? eventPointsTotal /
                math.max(
                  1,
                  goal.boostsPerLive > 0
                      ? lives * goal.boostsPerLive
                      : goal.boostBudget,
                )
          : 0,
    ),
    results: [...challenge.results, ...normalResults],
    overall: [?bestNormal, ?bestChallenge],
    unknownCards: challenge.unknownCards,
    elapsedMs: now(),
  );
}

/// A fixed team across songs (team check / comparison).
class TeamSpec {
  TeamSpec(this.members, this.snaps, this.leader);
  final List<String> members;
  final List<String?> snaps;
  final String leader;
}

class TeamEvaluation {
  TeamEvaluation({
    required this.song,
    required this.power,
    required this.slotPowers,
    required this.score,
    required this.skipScore,
    required this.event,
  });
  final SongRef song;
  final int power;
  final List<int> slotPowers;
  final HitScore score;
  final int skipScore;
  final ({
    double points,
    double items,
    double bonusPercent,
    double itemBonusPercent,
  })?
  event;
}

Future<List<TeamEvaluation>> evaluateTeam(
  EngineMaster master,
  ChartCache charts, {
  required List<MemberInput> members,
  required List<SnapInput> snaps,
  required PlayerInput player,
  UnknownPolicy unknownPolicy = UnknownPolicy.max,
  required TeamSpec team,
  required List<SongRef> songs,
  PlayModel play = ap,
  int? challengeEventId,
  ({int eventId, RouteKind route, int consumption})? event,
}) async {
  final box = resolveBox(master, members, snaps, unknownPolicy);
  final playerValue = playerState(master, player);
  final order = [
    team.leader,
    ...team.members.where((key) => key != team.leader),
  ];
  final memberStates = [
    for (final key in order)
      box.members.where((member) => member.key == key).firstOrNull,
  ];
  if (memberStates.any((member) => member == null)) {
    throw RangeError('unknown-team-member');
  }
  final teamMembers = memberStates.cast<MemberState>();
  final snapByMember = {
    for (final (index, key) in team.members.indexed)
      key: team.snaps.elementAtOrNull(index),
  };
  final snapStates = [
    for (final key in order)
      if (snapByMember[key] case final snap?)
        box.snaps.where((item) => item.key == snap).firstOrNull
      else
        null,
  ];
  final out = <TeamEvaluation>[];
  for (final song in songs) {
    final chart = await charts.chart(song);
    final live = charts.live(chart);
    final challengeId = event?.route == RouteKind.challenge
        ? event!.eventId
        : challengeEventId;
    final effects = challengeId != null
        ? master.events[challengeId]?.effects ?? const <EventEffectRow>[]
        : const <EventEffectRow>[];
    final power = teamPower(
      master,
      playerValue,
      teamMembers,
      snapStates,
      0,
      musicView(master, song.songId, challengeId),
      effects,
    );
    final usedSnaps = snapStates.whereType<SnapState>().toList();
    final evaluated = Team(
      [0, 1, 2, 3, 4],
      [
        for (final snap in snapStates)
          snap == null ? -1 : usedSnaps.indexOf(snap),
      ],
    );
    final objective = liveScoreObjective(
      LiveContext(master, teamMembers, usedSnaps, live, play),
      Criterion.mean,
    );
    final detail = objective.exact(evaluated, power.total, power.slots).detail;
    ({
      double points,
      double items,
      double bonusPercent,
      double itemBonusPercent,
    })?
    eventValue;
    if (event != null) {
      final route = eventRoute(
        master,
        event.eventId,
        event.route,
        event.consumption,
      );
      int bonus(int type) =>
          teamMembers.fold(
            0,
            (sum, member) =>
                sum + memberEventPercent(route.effects, member, type),
          ) +
          usedSnaps.fold(
            0,
            (sum, snap) => sum + snapEventPercent(route.effects, snap, type),
          );
      final pointBonus = bonus(0), itemBonus = bonus(1);
      var points = 0.0, items = 0.0;
      for (final score in detail.scores.scores) {
        final rank = scoreRank(chart, score);
        points += eventPoints(route, pointBonus, rank);
        items += eventItems(route, itemBonus, rank);
      }
      eventValue = (
        points: points / orders.length,
        items: items / orders.length,
        bonusPercent: pointBonus / 100,
        itemBonusPercent: itemBonus / 100,
      );
    }
    out.add(
      TeamEvaluation(
        song: song,
        power: power.total,
        slotPowers: power.slots,
        score: scoreSummary(detail.scores, chart, evaluated, teamMembers),
        skipScore: skipScore(master, chart, power.total),
        event: eventValue,
      ),
    );
  }
  return out;
}

/// The skill windows of one order, for the timeline view.
class SkillWindow {
  SkillWindow(
    this.member,
    this.event,
    this.startMs,
    this.endMs,
    this.percent,
    this.perfectPercent,
  );
  final String member;
  final int event;
  final int startMs;
  final int endMs;
  final double percent;
  final double perfectPercent;
}

List<SkillWindow> skillWindows(
  EngineMaster master,
  CompiledChart chart,
  List<MemberState> members,
  List<SnapState?> snaps,
  List<int> order,
) => [
  for (final (event, slot) in order.indexed)
    if (event < chart.skillTimes.length)
      () {
        final skill = resolveSlotSkill(master, members[slot], snaps[slot]);
        var percent = 0.0, perfect = 0.0;
        var length = 0;
        for (final effect in skill.effects) {
          if (effect.gate.blocks(master.live.lifeBase)) continue;
          if (effect.type == 2000) {
            percent += effect.delta / 1000;
          } else {
            perfect += effect.delta / 1000;
          }
          length = math.max(
            length,
            windowMs(effect.seconds, skill.extensionMs),
          );
        }
        final start = chart.skillTimes[event];
        return SkillWindow(
          members[slot].key,
          event,
          start,
          start + length,
          percent,
          perfect,
        );
      }(),
];
