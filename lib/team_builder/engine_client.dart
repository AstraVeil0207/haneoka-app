/// The engine in a background isolate: it compiles the release once and
/// serves searches. Cancelling kills the isolate, so a long search never
/// blocks; the next call starts a fresh one (`engine/client.ts`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../chart/runtime_chart.dart' show RuntimeChart;
import '../core/net.dart';
import 'engine/api.dart';
import 'engine/box.dart';
import 'engine/live.dart' show PlayModel;
import 'engine/master.dart';
import 'engine/merge.dart';
import 'engine/num.dart';
import 'engine/objectives.dart' show RouteKind;
import 'engine/power.dart';

class EngineCancelled implements Exception {
  const EngineCancelled();
}

/// A search for one team's skill windows, for the timeline view.
class TimelineRequest {
  TimelineRequest({
    required this.members,
    required this.snaps,
    required this.unknownPolicy,
    required this.memberKeys,
    required this.snapKeys,
    required this.song,
    required this.order,
  });
  final List<MemberInput> members;
  final List<SnapInput> snaps;
  final UnknownPolicy unknownPolicy;

  /// Formation slots, leader first.
  final List<String> memberKeys;
  final List<String?> snapKeys;
  final SongRef song;

  /// Formation slot firing at each chart skill event.
  final List<int> order;
}

class Timeline {
  Timeline(this.durationMs, this.density, this.fever, this.windows);
  final int durationMs;

  /// Note counts per 500 ms.
  final List<int> density;
  final List<(int, int)> fever;
  final List<SkillWindow> windows;
}

typedef _Call = (
  int id,
  String kind,
  Object request,
  Map<String, Uint8List> charts,
);

/// One engine isolate: compiles the release once, then serves calls.
class _Worker {
  _Worker(this.data);
  final Doc data;
  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _replies;
  Future<void>? _ready;
  var _nextId = 1;
  final _pending = <int, (Completer<Object?>, void Function(int, int)?)>{};

  /// Calls in flight; 0 when idle.
  int get load => _pending.length;
  bool get started => _ready != null;

  Future<void> _spawn() => _ready ??= () async {
    final replies = _replies = ReceivePort();
    final ready = Completer<SendPort>();
    replies.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      final (id, kind, payload) = message as (int, String, Object?);
      final pending = _pending[id];
      if (pending == null) return;
      if (kind == 'progress') {
        final (done, total) = payload as (int, int);
        pending.$2?.call(done, total);
        return;
      }
      _pending.remove(id);
      if (kind == 'error') {
        pending.$1.completeError(StateError('$payload'));
      } else {
        pending.$1.complete(payload);
      }
    });
    _isolate = await Isolate.spawn(_main, (
      replies.sendPort,
      jsonEncode(data),
    ), errorsAreFatal: false);
    _port = await ready.future;
  }();

  void warm() => _spawn().ignore();

  Future<T> call<T>(
    String kind,
    Object request,
    Map<String, Uint8List> charts, [
    void Function(int done, int total)? progress,
  ]) async {
    await _spawn();
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = (completer, progress);
    _port!.send((id, kind, request, charts));
    return (await completer.future) as T;
  }

  void cancel() {
    for (final pending in _pending.values) {
      pending.$1.completeError(const EngineCancelled());
    }
    _pending.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    _isolate = null;
    _port = null;
    _ready = null;
  }
}

/// How many isolates share a search: the device's cores minus one for the
/// interface; each holds its own compiled release, so phones get fewer.
int _poolSize() {
  final cores = Platform.numberOfProcessors;
  final limit = Platform.isAndroid || Platform.isIOS ? 3 : 8;
  return math.max(1, math.min(limit, cores - 1));
}

/// Below this many members one isolate finishes before the others compile.
const _parallelMinMembers = 15;

/// How long one isolate tries before a song fans out over the pool.
const _quickMs = 700.0;

/// Leader shards per isolate: enough for free isolates to even out uneven
/// subtrees.
const _shardsPerWorker = 4;

/// The engine isolates (`engine/client.ts`): a search runs one song at a
/// time; quick proofs spread over the pool, harder songs split by leader.
class EngineClient {
  EngineClient(this.data, this.chartUrl)
    : _pool = [for (var i = 0; i < _poolSize(); i++) _Worker(data)];

  /// The merged release document.
  final Doc data;

  /// The pinned chart address of a song difficulty, or null when unknown.
  final String? Function(SongRef song) chartUrl;

  final List<_Worker> _pool;
  final _bytes = <String, Uint8List>{};

  /// Compiles the release ahead of the first call; the other isolates
  /// compile only when a search fans out.
  void warm() => _pool.first.warm();

  _Worker _idlest() => stableSorted(
    _pool,
    (a, b) => a.load != b.load
        ? a.load - b.load
        : (b.started ? 1 : 0) - (a.started ? 1 : 0),
  ).first;

  Future<Map<String, Uint8List>> _charts(List<SongRef> songs) async {
    final out = <String, Uint8List>{};
    for (final song in songs) {
      final known = _bytes[song.key];
      if (known != null) {
        out[song.key] = known;
        continue;
      }
      final url = chartUrl(song);
      if (url == null) throw RangeError('unknown-chart:${song.key}');
      // One dropped request must not fail a search over many songs.
      http.Response? response;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
        try {
          response = await netClient.get(Uri.parse(url));
          if (response.statusCode < 500) break;
        } catch (_) {
          response = null;
        }
      }
      if (response == null) throw StateError('chart-network');
      if (response.statusCode != 200) {
        throw StateError('chart-http-${response.statusCode}');
      }
      out[song.key] = _bytes[song.key] = response.bodyBytes;
    }
    return out;
  }

  Future<EngineResponse> run(
    EngineRequest request, [
    void Function(int done, int total)? progress,
  ]) async {
    final charts = await _charts(_songsOf(request.goal));
    final songCount = switch (request.goal) {
      GekisoGoal(:final songs) => songs.length,
      _ => 2,
    };
    // One Gekiso song stays whole: its seeding pass would run in every shard.
    final parallel =
        _pool.length > 1 &&
        request.members.length >= _parallelMinMembers &&
        request.goal is! PlanGoal &&
        songCount > 1;
    if (!parallel) {
      return _idlest().call('run', request, charts, progress);
    }
    final songs = switch (request.goal) {
      ScoreGoal(:final songs) ||
      GekisoGoal(:final songs) ||
      EventGoal(:final songs) => songs,
      _ => const <SongRef>[],
    };
    return songs.length > 1
        ? _songs(request, songs, charts, progress)
        : _song(request, charts, progress);
  }

  /// One song's request of a many-song search.
  EngineRequest _of(EngineRequest request, SongRef song, double? limit) =>
      request.copyWith(
        goal: switch (request.goal) {
          ScoreGoal(:final criterion, :final play, :final challengeEventId) =>
            ScoreGoal([song], criterion, play, challengeEventId),
          GekisoGoal(
            :final criterion,
            :final accuracy,
            :final rank,
            :final seeds,
          ) =>
            GekisoGoal(
              songs: [song],
              criterion: criterion,
              accuracy: accuracy,
              rank: rank,
              seeds: seeds,
            ),
          final EventGoal goal => goal.copyWith(songs: [song]),
          final goal => goal,
        },
        timeLimitMs: limit,
        keepTimeLimit: false,
      );

  /// A worker keeps a song's chart, seeds and contexts only while that song
  /// is current, so songs go one at a time, never one shard per song list.
  Future<EngineResponse> _songs(
    EngineRequest request,
    List<SongRef> songs,
    Map<String, Uint8List> charts,
    void Function(int done, int total)? progress,
  ) async {
    final clock = Stopwatch()..start();
    final end = request.timeLimitMs;
    double? left(int done) => end == null
        ? null
        : math.max(
            250,
            (end - clock.elapsedMilliseconds) / (songs.length - done),
          );
    final responses = List<EngineResponse?>.filled(songs.length, null);
    var done = 0;
    final hard = <(int, double?)>[];
    if (request.goal is GekisoGoal) {
      // Every shard would repeat the song's seeding pass, which is most of a
      // Gekiso search: songs run whole, side by side.
      var next = 0;
      Future<void> worker(_Worker engine) async {
        while (next < songs.length) {
          final index = next++;
          responses[index] = await engine.call<EngineResponse>(
            'run',
            _of(request, songs[index], left(done)),
            charts,
          );
          progress?.call(++done, songs.length);
        }
      }

      await Future.wait([for (final engine in _pool) worker(engine)]);
    } else if (request.noFloor) {
      hard.addAll([for (var i = 0; i < songs.length; i++) (i, null)]);
    } else {
      var next = 0;
      Future<void> worker(_Worker engine) async {
        while (next < songs.length) {
          final index = next++;
          final quick = await engine.call<EngineResponse>(
            'run',
            _of(
              request,
              songs[index],
              math.min(_quickMs, left(done) ?? _quickMs),
            ),
            charts,
          );
          final result = quick.results.first;
          if (result.proven || result.excludedBelow != null) {
            responses[index] = quick;
            progress?.call(++done, songs.length);
          } else {
            hard.add((
              index,
              result.hits.length >= request.k
                  ? result.hits[request.k - 1].key
                  : null,
            ));
          }
        }
      }

      await Future.wait([for (final engine in _pool) worker(engine)]);
    }
    hard.sort((a, b) => a.$1 - b.$1);
    for (final (index, floor) in hard) {
      final song = songs[index];
      responses[index] = await _fan(
        _of(request, song, left(done)),
        floor == null ? const {} : {song.key: floor},
        charts,
        progress,
        done.toDouble(),
        songs.length,
      );
      progress?.call(++done, songs.length);
    }
    final results = [for (final response in responses) ...response!.results];
    return EngineResponse(
      results: results,
      overall: stableSorted([
        for (final result in results) ...result.hits,
      ], compareHits).take(math.max(request.k, 3)).toList(),
      unknownCards: responses.first!.unknownCards,
      elapsedMs: clock.elapsedMicroseconds / 1000,
    );
  }

  Future<EngineResponse> _song(
    EngineRequest request,
    Map<String, Uint8List> charts,
    void Function(int done, int total)? progress,
  ) async {
    final clock = Stopwatch()..start();
    // Most searches prove their ranking in well under a second on one
    // isolate; the teams found so far give every shard its starting floor.
    final initial = <String, double>{};
    if (!request.noFloor && request.goal is! GekisoGoal) {
      final quick = await _idlest().call<EngineResponse>(
        'run',
        request.copyWith(
          timeLimitMs: math.min(request.timeLimitMs ?? _quickMs, _quickMs),
        ),
        charts,
      );
      if (quick.results.every(
        (result) => result.proven || result.excludedBelow != null,
      )) {
        return quick;
      }
      for (final result in quick.results) {
        if (result.song != null && result.hits.length >= request.k) {
          initial[result.song!.key] = result.hits[request.k - 1].key;
        }
      }
    }
    final merged = await _fan(request, initial, charts, progress);
    return EngineResponse(
      results: merged.results,
      overall: merged.overall,
      unknownCards: merged.unknownCards,
      elapsedMs: clock.elapsedMicroseconds / 1000,
    );
  }

  /// The sharded search of one request; a floor that admitted fewer than
  /// k teams is searched again without it.
  Future<EngineResponse> _fan(
    EngineRequest request,
    Map<String, double> initial,
    Map<String, Uint8List> charts,
    void Function(int done, int total)? progress, [
    double offset = 0,
    int total = 1,
  ]) async {
    final merged = await _sharded(
      request,
      initial,
      charts,
      progress,
      offset,
      total,
    );
    if (aspirationHeld(merged, request.k) || request.noFloor) return merged;
    return _sharded(
      request.copyWith(noFloor: true),
      const {},
      charts,
      progress,
      offset,
      total,
    );
  }

  /// Leader shards are many and small, handed to whichever isolate is free;
  /// each starts from the best k-th key found so far.
  Future<EngineResponse> _sharded(
    EngineRequest request,
    Map<String, double> initial,
    Map<String, Uint8List> charts,
    void Function(int done, int total)? progress,
    double offset,
    int total,
  ) async {
    final count = _pool.length * _shardsPerWorker;
    final responses = <EngineResponse>[];
    var next = 0;
    Map<String, double> floors() {
      if (responses.isEmpty) return initial;
      final out = {...initial};
      for (final result in mergeShardResponses(
        responses,
        request.k,
        0,
      ).results) {
        if (result.song != null && result.hits.length >= request.k) {
          final key = result.song!.key;
          out[key] = math.max(
            out[key] ?? -double.infinity,
            result.hits[request.k - 1].key,
          );
        }
      }
      return out;
    }

    Future<void> worker(_Worker engine) async {
      while (next < count) {
        final index = next++;
        responses.add(
          await engine.call<EngineResponse>(
            'run',
            request.copyWith(
              shard: (index: index, count: count),
              floors: floors(),
            ),
            charts,
          ),
        );
        progress?.call((offset + responses.length / count).floor(), total);
      }
    }

    await Future.wait([for (final engine in _pool) worker(engine)]);
    return mergeShardResponses(responses, request.k, 0);
  }

  Future<List<TeamEvaluation>> evaluate(EvaluateRequest request) async =>
      _pool.first.call('evaluate', request, await _charts(request.songs));

  Future<Timeline> timeline(TimelineRequest request) async =>
      _pool.first.call('timeline', request, await _charts([request.song]));

  /// Stops every call in flight.
  void cancel() {
    for (final worker in _pool) {
      worker.cancel();
    }
  }

  void dispose() => cancel();
}

List<SongRef> _songsOf(Goal goal) => switch (goal) {
  PowerGoal(:final song) => [?song],
  ScoreGoal(:final songs) => songs,
  GekisoGoal(:final songs) => songs,
  EventGoal(:final songs, :final route) =>
    route == RouteKind.skip ? const [] : songs,
  PotentialGoal() => const [],
  PlanGoal(:final normalSongs, :final challengeSongs) => [
    ...challengeSongs,
    ...normalSongs,
  ],
};

class EvaluateRequest {
  EvaluateRequest({
    required this.members,
    required this.snaps,
    required this.player,
    required this.unknownPolicy,
    required this.team,
    required this.songs,
    required this.play,
    required this.challengeEventId,
    required this.event,
  });
  final List<MemberInput> members;
  final List<SnapInput> snaps;
  final PlayerInput player;
  final UnknownPolicy unknownPolicy;
  final TeamSpec team;
  final List<SongRef> songs;
  final PlayModel play;
  final int? challengeEventId;
  final ({int eventId, RouteKind route, int consumption})? event;
}

void _main((SendPort, String) args) {
  final (reply, json) = args;
  final master = compileTeamData(jsonDecode(json) as Doc);
  final bytes = <String, Uint8List>{};
  final charts = ChartCache(
    master,
    (song) async => RuntimeChart.fromBytes(bytes[song.key]!),
  );
  final port = ReceivePort();
  reply.send(port.sendPort);
  port.listen((message) async {
    final (id, kind, request, chartBytes) = message as _Call;
    bytes.addAll(chartBytes);
    try {
      final Object result;
      switch (kind) {
        case 'run':
          result = await runEngine(
            master,
            charts,
            request as EngineRequest,
            onProgress: (done, total) =>
                reply.send((id, 'progress', (done, total))),
          );
        case 'evaluate':
          final r = request as EvaluateRequest;
          result = await evaluateTeam(
            master,
            charts,
            members: r.members,
            snaps: r.snaps,
            player: r.player,
            unknownPolicy: r.unknownPolicy,
            team: r.team,
            songs: r.songs,
            play: r.play,
            challengeEventId: r.challengeEventId,
            event: r.event,
          );
        case 'timeline':
          result = await _timeline(master, charts, request as TimelineRequest);
        default:
          throw UnsupportedError(kind);
      }
      reply.send((id, 'result', result));
    } catch (error) {
      reply.send((id, 'error', '$error'));
    }
  });
}

Future<Timeline> _timeline(
  EngineMaster master,
  ChartCache charts,
  TimelineRequest request,
) async {
  final box = resolveBox(
    master,
    request.members,
    request.snaps,
    request.unknownPolicy,
  );
  final chart = await charts.chart(request.song);
  final density = List<int>.filled(((chart.lastNoteMs + 1000) / 500).ceil(), 0);
  for (final time in chart.times) {
    density[time ~/ 500]++;
  }
  final members = [
    for (final key in request.memberKeys)
      box.members.firstWhere((member) => member.key == key),
  ];
  final snaps = <SnapState?>[
    for (final key in request.snapKeys)
      key == null
          ? null
          : box.snaps.where((snap) => snap.key == key).firstOrNull,
  ];
  return Timeline(
    chart.lastNoteMs + 1000,
    density,
    chart.feverMs,
    skillWindows(master, chart, members, snaps, request.order),
  );
}
