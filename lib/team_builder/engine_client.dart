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
import 'engine/execution.dart';
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
  _Worker(this.data, this.chartUrl);
  final Doc data;
  final String? Function(SongRef) chartUrl;
  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _replies;
  ReceivePort? _failures;
  Completer<SendPort>? _spawnReady;
  int _generation = 0;
  Future<void>? _ready;
  var _nextId = 1;
  final _pending =
      <
        int,
        (
          Completer<Object?>,
          void Function(int, int)?,
          void Function(EngineSnapshot)?,
        )
      >{};
  final _times = <String, double>{
    'initializationMs': 0,
    'networkMs': 0,
    'computationMs': 0,
  };
  String? _phase;
  double _phaseAt = 0;
  void _setPhase(String? phase) {
    final now = executionClock();
    if (_phase != null) _times[_phase!] = _times[_phase!]! + now - _phaseAt;
    _phase = phase;
    _phaseAt = now;
  }

  double _time(String phase) =>
      _times[phase]! + (_phase == phase ? executionClock() - _phaseAt : 0);
  double get initializationMs => _time('initializationMs');
  double get networkMs => _time('networkMs');
  double get computationMs => _time('computationMs');

  /// Calls in flight; 0 when idle.
  int get load => _pending.length;
  bool get started => _ready != null;

  Future<void> _spawn() => _ready ??= () async {
    _setPhase('initializationMs');
    final replies = _replies = ReceivePort();
    final ready = _spawnReady = Completer<SendPort>();
    final generation = _generation;
    final failures = _failures = ReceivePort();
    failures.listen((failure) {
      final error = StateError(
        'engine-crashed:${failure is List ? failure.first : 'worker exited'}',
      );
      if (!ready.isCompleted) ready.completeError(error);
      for (final pending in _pending.values) {
        pending.$1.completeError(error);
      }
      _pending.clear();
      _setPhase(null);
      _isolate?.kill(priority: Isolate.immediate);
      _replies?.close();
      _failures?.close();
      _isolate = null;
      _port = null;
      _ready = null;
    });
    replies.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      final (id, kind, payload) = message as (int, String, Object?);
      final pending = _pending[id];
      if (pending == null) return;
      if (kind == 'phase') {
        _setPhase(payload as String);
        return;
      }
      if (kind == 'snapshot') {
        pending.$3?.call(payload as EngineSnapshot);
        return;
      }
      if (kind == 'progress') {
        final (done, total) = payload as (int, int);
        pending.$2?.call(done, total);
        return;
      }
      _setPhase(null);
      _pending.remove(id);
      if (kind == 'error') {
        pending.$1.completeError(StateError('$payload'));
      } else {
        pending.$1.complete(payload);
      }
    });
    late final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _main,
        (
          replies.sendPort,
          jsonEncode(data),
          {
            for (final value in objectRow(data['songs']).values)
              for (final difficulty in dataRows(objectRow(value)['difficulty']))
                '${intOf(objectRow(value)['musicId'])}:${intOf(difficulty['difficulty'])}':
                    chartUrl(
                      SongRef(
                        intOf(objectRow(value)['musicId']),
                        intOf(difficulty['difficulty']),
                      ),
                    ) ??
                    '',
          },
        ),
        errorsAreFatal: true,
        onError: failures.sendPort,
        onExit: failures.sendPort,
      );
    } catch (_) {
      failures.close();
      replies.close();
      _spawnReady = null;
      _ready = null;
      _setPhase(null);
      rethrow;
    }
    if (generation != _generation) {
      isolate.kill(priority: Isolate.immediate);
      throw const EngineCancelled();
    }
    _isolate = isolate;
    _port = await ready.future;
    _setPhase(null);
  }();

  Future<void> warm() => _spawn();

  Future<T> call<T>(
    String kind,
    Object request,
    Map<String, Uint8List> charts, [
    void Function(int done, int total)? progress,
    void Function(EngineSnapshot)? snapshot,
  ]) async {
    await _spawn();
    _setPhase('computationMs');
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = (completer, progress, snapshot);
    _port!.send((id, kind, request, charts));
    return (await completer.future) as T;
  }

  void cancel() {
    _generation++;
    if (_spawnReady != null && !_spawnReady!.isCompleted) {
      _spawnReady!.completeError(const EngineCancelled());
    }
    _failures?.close();
    _failures = null;
    _setPhase(null);
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
  final limit = Platform.isAndroid || Platform.isIOS ? 2 : 8;
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
    : _pool = [for (var i = 0; i < _poolSize(); i++) _Worker(data, chartUrl)];

  /// The merged release document.
  final Doc data;

  /// The pinned chart address of a song difficulty, or null when unknown.
  final String? Function(SongRef song) chartUrl;

  final List<_Worker> _pool;
  final _bytes = <String, Uint8List>{};

  /// Compiles the release ahead of the first call; the other isolates
  /// compile only when a search fans out.
  void warm() => _pool.first.warm().then((_) {
    for (final worker in _pool.skip(1)) {
      worker.warm().ignore();
    }
  }).ignore();

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
      final release = response.headers['x-haneoka-release-id'];
      if (release != null &&
          release != Uri.parse(url).queryParameters['release']) {
        throw StateError('chart-release-identity-mismatch');
      }
      if (_bytes.length >= 16) _bytes.remove(_bytes.keys.first);
      out[song.key] = _bytes[song.key] = response.bodyBytes;
    }
    return out;
  }

  Future<void> _queue = Future.value();
  int _generation = 0, _requestId = 0;
  void Function(String)? _activeStop;

  Future<EngineResponse> run(
    EngineRequest request, [
    void Function(int done, int total)? progress,
    void Function(EngineSnapshot)? snapshot,
  ]) {
    final started = executionClock(), generation = _generation;
    final task = request.copyWith(
      deadline: deadlineOf(request),
      requestId:
          request.requestId ??
          'native-${DateTime.now().microsecondsSinceEpoch}-${++_requestId}',
      contextKey:
          request.contextKey ??
          jsonEncode([data['identity'], data['crossServer'], request.toJson()]),
    );
    var expired = false;
    Timer? timer;
    final waiting = Completer<EngineResponse>();
    if (task.deadline!.isFinite) {
      timer = Timer(
        Duration(microseconds: (remaining(task.deadline!) * 1000).ceil()),
        () {
          expired = true;
          final response = emptyResponse(task)..stopReason = 'budget';
          snapshot?.call(
            EngineSnapshot(
              requestId: task.requestId!,
              contextKey: task.contextKey!,
              response: response,
              completed: 0,
              total: response.results.length,
              stopReason: 'budget',
            ),
          );
          waiting.complete(response);
        },
      );
    }
    final queued = _queue.then<EngineResponse>((_) {
      timer?.cancel();
      if (expired || generation != _generation) {
        return emptyResponse(task)
          ..stopReason = expired ? 'budget' : 'cancelled';
      }
      return _execute(task, started, progress, snapshot);
    });
    _queue = queued.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return Future.any([queued, waiting.future])
        .whenComplete(() => timer?.cancel());
  }

  EngineRequest _of(EngineRequest request, SongRef song, double deadline) =>
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
        deadline: deadline,
        seeds: request.seeds.where((hit) => hit.song == song).toList(),
        completed: request.completed
            .where((result) => result.song == song)
            .toList(),
      );

  Future<EngineResponse> _execute(
    EngineRequest request,
    double started,
    void Function(int, int)? progress,
    void Function(EngineSnapshot)? snapshot,
  ) async {
    final before = [
      for (final worker in _pool)
        (worker.initializationMs, worker.computationMs, worker.networkMs),
    ];
    var latest = emptyResponse(request);
    for (final result in latest.results) {
      result.hits = request.seeds
          .where((hit) => hit.song == result.song)
          .take(request.k)
          .toList();
    }
    latest.overall.addAll(
      stableSorted([
        for (final result in latest.results) ...result.hits,
      ], compareHits).take(request.k),
    );
    var stopped = false, lastShown = -double.infinity;
    void publish(EngineResponse response, [bool force = false]) {
      if (stopped) return;
      final hadCandidate = latest.overall.isNotEmpty;
      for (final result in response.results) {
        final previous = latest.results
            .where((r) => r.song == result.song)
            .firstOrNull;
        if (previous != null && !result.proven) {
          final seen = <String>{};
          result.hits =
              stableSorted([...result.hits, ...previous.hits], compareHits)
                  .where(
                    (hit) => seen.add(([...hit.members]..sort()).join(',')),
                  )
                  .take(request.k)
                  .toList();
        }
      }
      latest = EngineResponse(
        results: response.results,
        overall: stableSorted([
          for (final r in response.results) ...r.hits,
        ], compareHits).take(request.k).toList(),
        unknownCards: response.unknownCards,
        elapsedMs: executionClock() - started,
        plan: response.plan,
        stopReason: response.stopReason,
        error: response.error,
        timing: EngineTiming(
          initializationMs: [
            for (final (i, worker) in _pool.indexed)
              worker.initializationMs - before[i].$1,
          ].fold(0, (a, b) => a + b),
          computationMs: [
            for (final (i, worker) in _pool.indexed)
              worker.computationMs - before[i].$2,
          ].fold(0, (a, b) => a + b),
          networkMs: [
            for (final (i, worker) in _pool.indexed)
              worker.networkMs - before[i].$3,
          ].fold(0, (a, b) => a + b),
          wallMs: executionClock() - started,
        ),
      );
      if (!force &&
          (hadCandidate || latest.overall.isEmpty) &&
          executionClock() - lastShown < 100) {
        return;
      }
      lastShown = executionClock();
      snapshot?.call(
        EngineSnapshot(
          requestId: request.requestId!,
          contextKey: request.contextKey!,
          response: latest,
          completed: latest.results
              .where((r) => r.proven || r.exclusion != null)
              .length,
          total: latest.results.length,
          stopReason: latest.stopReason,
        ),
      );
    }

    final interrupted = Completer<EngineResponse>();
    void stop(String reason) {
      if (stopped) return;
      latest.stopReason = reason;
      publish(latest, true);
      stopped = true;
      for (final worker in _pool) {
        worker.cancel();
      }
      interrupted.complete(latest);
    }

    _activeStop = stop;
    final deadline = request.deadline!;
    final timer = deadline.isFinite
        ? Timer(
            Duration(microseconds: (remaining(deadline) * 1000).ceil()),
            () => stop('budget'),
          )
        : null;
    void accept(EngineSnapshot value) {
      if (!stopped &&
          value.requestId == request.requestId &&
          value.contextKey == request.contextKey) {
        publish(value.response);
      }
    }

    Future<EngineResponse> send(
      _Worker worker,
      EngineRequest task, [
      void Function(EngineSnapshot)? onSnapshot,
    ]) async {
      if (stopped || remaining(task.deadline!) == 0) return emptyResponse(task);
      return worker.call('run', task, const {}, progress, onSnapshot ?? accept);
    }

    Future<EngineResponse> work() async {
      if (remaining(deadline) == 0) {
        stop('budget');
        return latest;
      }
      if (completeResponse(latest)) return latest;
      final parallel =
          _pool.length > 1 &&
          request.members.length >= _parallelMinMembers &&
          request.goal is! PlanGoal;
      if (!parallel) return send(_idlest(), request);
      final songs = requestSongs(request);
      if (songs.length > 1 && songs.every((song) => song != null)) {
        final parts = [...latest.results];
        EngineResponse merged() => EngineResponse(
          results: [...parts],
          overall: [],
          unknownCards: latest.unknownCards,
          elapsedMs: executionClock() - started,
        );
        var next = 0, done = 0;
        Future<void> runSong(_Worker worker) async {
          while (!stopped && remaining(deadline) > 0 && next < songs.length) {
            final index = next++, song = songs[index]!;
            if (parts[index].proven) {
              progress?.call(++done, songs.length);
              continue;
            }
            final share =
                remaining(deadline) * _pool.length / (songs.length - index);
            final task = _of(
              request,
              song,
              math.min(deadline, executionClock() + share),
            );
            final response = await send(worker, task, (value) {
              if (stopped ||
                  value.contextKey != request.contextKey ||
                  value.requestId != request.requestId) {
                return;
              }
              parts[index] = value.response.results.firstOrNull ?? parts[index];
              publish(merged());
            });
            if (stopped) return;
            parts[index] = response.results.firstOrNull ?? parts[index];
            publish(merged());
            progress?.call(++done, songs.length);
          }
        }

        await Future.wait([for (final worker in _pool) runSong(worker)]);
        return merged();
      }
      var seeds = request.seeds;
      final gekiso = request.goal is GekisoGoal;
      if (gekiso) {
        final seeding = await send(_idlest(), request.copyWith(seedOnly: true));
        publish(seeding);
        seeds = [for (final r in seeding.results) ...r.hits];
      } else if (!request.noFloor) {
        final quick = await send(
          _idlest(),
          request.copyWith(
            deadline: math.min(deadline, executionClock() + _quickMs),
          ),
        );
        publish(quick);
        if (completeResponse(quick)) return quick;
        seeds = [for (final r in quick.results) ...r.hits];
      }
      final count = _pool.length * _shardsPerWorker;
      final responses = [
        for (var i = 0; i < count; i++) emptyResponse(request),
      ];
      for (final response in responses) {
        for (final result in response.results) {
          result.hits = seeds
              .where((hit) => hit.song == result.song)
              .take(request.k)
              .toList();
        }
      }
      var next = 0, done = 0;
      EngineResponse merge() =>
          mergeShardResponses(responses, request.k, executionClock() - started);
      Future<void> runShard(_Worker worker) async {
        while (!stopped && remaining(deadline) > 0 && next < count) {
          final index = next++, current = merge();
          final floors = {
            for (final result in current.results)
              if (result.song != null && result.hits.length >= request.k)
                result.song!.key: result.hits[request.k - 1].key,
          };
          final response = await send(
            worker,
            request.copyWith(
              seeds: seeds,
              seeded: gekiso,
              shard: (index: index, count: count),
              floors: floors,
            ),
            (value) {
              if (stopped ||
                  value.contextKey != request.contextKey ||
                  value.requestId != request.requestId) {
                return;
              }
              responses[index] = value.response;
              publish(merge());
            },
          );
          if (stopped) return;
          responses[index] = response;
          publish(merge());
          progress?.call(++done, count);
        }
      }

      await Future.wait([for (final worker in _pool) runShard(worker)]);
      final merged = merge();
      if (!aspirationHeld(merged, request.k) &&
          !request.noFloor &&
          remaining(deadline) > 0) {
        return send(
          _idlest(),
          request.copyWith(seeds: merged.overall, noFloor: true),
        );
      }
      return merged;
    }

    try {
      final response = await Future.any([work(), interrupted.future]);
      if (!stopped) {
        response.stopReason = completeResponse(response)
            ? 'complete'
            : 'budget';
        publish(response, true);
      }
      return latest;
    } catch (error) {
      if (stopped) return latest;
      latest.error = '$error';
      stop('error');
      if (latest.overall.isNotEmpty) return latest;
      rethrow;
    } finally {
      timer?.cancel();
      if (_activeStop == stop) _activeStop = null;
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() work) {
    final generation = _generation;
    final queued = _queue.then((_) {
      if (generation != _generation) throw const EngineCancelled();
      return work();
    });
    _queue = queued.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return queued;
  }

  Future<List<TeamEvaluation>> evaluate(EvaluateRequest request) => _enqueue(
    () async =>
        _pool.first.call('evaluate', request, await _charts(request.songs)),
  );
  Future<Timeline> timeline(TimelineRequest request) => _enqueue(
    () async =>
        _pool.first.call('timeline', request, await _charts([request.song])),
  );

  /// Stops every call in flight.
  void cancel() {
    _generation++;
    _activeStop?.call('cancelled');
    for (final worker in _pool) {
      worker.cancel();
    }
  }

  void dispose() => cancel();
}

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

void _main((SendPort, String, Map<String, String>) args) {
  final (reply, json, urls) = args;
  var activeId = 0;
  final client = http.Client();
  final master = compileTeamData(jsonDecode(json) as Doc);
  final bytes = <String, Uint8List>{};
  final charts = ChartCache(master, (song) async {
    final cached = bytes.remove(song.key);
    if (cached != null) return RuntimeChart.fromBytes(cached);
    final url = urls[song.key];
    if (url == null || url.isEmpty) throw StateError('chart-file-missing');
    reply.send((activeId, 'phase', 'networkMs'));
    http.Response? response;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
      try {
        response = await client.get(Uri.parse(url));
        if (response.statusCode < 500) break;
      } catch (_) {
        response = null;
      }
    }
    if (response == null) throw StateError('chart-network');
    if (response.statusCode != 200) {
      throw StateError('chart-http:${response.statusCode}');
    }
    final release = response.headers['x-haneoka-release-id'];
    final pinned = Uri.parse(url).queryParameters['release'];
    if (release != null && release != pinned) {
      throw StateError('chart-release-identity-mismatch');
    }
    reply.send((activeId, 'phase', 'computationMs'));
    return RuntimeChart.fromBytes(response.bodyBytes);
  });
  final port = ReceivePort();
  reply.send(port.sendPort);
  port.listen((message) async {
    final (id, kind, request, chartBytes) = message as _Call;
    activeId = id;
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
            onSnapshot: (snapshot) => reply.send((id, 'snapshot', snapshot)),
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
