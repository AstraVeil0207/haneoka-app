/// The engine in a background isolate: it compiles the release once and
/// serves searches. Cancelling kills the isolate, so a long search never
/// blocks; the next call starts a fresh one (`engine/client.ts`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../chart/runtime_chart.dart' show RuntimeChart;
import '../core/net.dart';
import 'engine/api.dart';
import 'engine/box.dart';
import 'engine/live.dart' show PlayModel;
import 'engine/master.dart';
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

class EngineClient {
  EngineClient(this.data, this.chartUrl);

  /// The merged release document.
  final Doc data;

  /// The pinned chart address of a song difficulty, or null when unknown.
  final String? Function(SongRef song) chartUrl;

  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _replies;
  Future<void>? _ready;
  var _nextId = 1;
  final _pending = <int, (Completer<Object?>, void Function(int, int)?)>{};
  final _bytes = <String, Uint8List>{};

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

  /// Compiles the release ahead of the first call.
  void warm() => _spawn().ignore();

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
      final response = await netClient.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw StateError('chart-http-${response.statusCode}');
      }
      out[song.key] = _bytes[song.key] = response.bodyBytes;
    }
    return out;
  }

  Future<T> _call<T>(
    String kind,
    Object request,
    List<SongRef> songs, [
    void Function(int done, int total)? progress,
  ]) async {
    final charts = await _charts(songs);
    await _spawn();
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = (completer, progress);
    _port!.send((id, kind, request, charts));
    return (await completer.future) as T;
  }

  Future<EngineResponse> run(
    EngineRequest request, [
    void Function(int done, int total)? progress,
  ]) => _call('run', request, _songsOf(request.goal), progress);

  Future<List<TeamEvaluation>> evaluate(EvaluateRequest request) =>
      _call('evaluate', request, request.songs);

  Future<Timeline> timeline(TimelineRequest request) =>
      _call('timeline', request, [request.song]);

  /// Stops every call in flight.
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
