/// Reward recommendation jobs (`team-builder/pt-recommendation.ts`,
/// `pt-checkpoint.ts`): the best team of every chosen song for event
/// points and shop medals, with the challenge lives its challenge points
/// pay for. A completed or certified-excluded chart is the smallest
/// resumable unit; the job is kept on the device only.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'engine/api.dart';
import 'engine/num.dart';
import 'engine/objectives.dart' show CpExchange, RouteKind;

const ptVersion = 'solo-cp-rewards-v2';

class PtCycle {
  PtCycle(this.songs, this.consumption);
  factory PtCycle.fromJson(Map<String, Object?> json) => PtCycle([
    for (final song in json['songs'] as List? ?? const [])
      SongRef.fromJson(objectRow(song)),
  ], intOf(json['consumption']));
  final List<SongRef> songs;
  final int consumption;
  Map<String, Object?> toJson() => {
    'songs': [for (final song in songs) song.toJson()],
    'consumption': consumption,
  };
}

/// `queued`, `running`, `complete`, `empty`, `pruned` or `failed`.
class PtTask {
  PtTask(this.route, this.measure, this.song);
  factory PtTask.fromJson(Map<String, Object?> json) =>
      PtTask(
          RouteKind.values.byName('${json['route']}'),
          '${json['measure']}',
          SongRef.fromJson(objectRow(json['song'])),
        )
        ..status = '${json['status'] ?? 'queued'}'
        ..result = json['result'] is Map
            ? SongResult.fromJson(objectRow(json['result']))
            : null
        ..error = '${json['error'] ?? ''}';
  final RouteKind route;
  final String measure;
  final SongRef song;
  String status = 'queued';
  SongResult? result;
  String error = '';
  Map<String, Object?> toJson() => {
    'route': route.name,
    'measure': measure,
    'song': song.toJson(),
    'status': status,
    'result': result?.toJson(),
    'error': error,
  };

  bool get complete =>
      (status == 'complete' || status == 'empty') && result?.proven == true;

  bool excluded(double? cutoff) {
    final below = result?.excludedBelow;
    return route == RouteKind.live &&
        status == 'pruned' &&
        below != null &&
        below.isFinite &&
        cutoff != null &&
        // The proof bound is the cutoff the task ran under plus its tie
        // margin (see [PtRunner]): compare with the same margin.
        below <= cutoffWithMargin(cutoff) &&
        (result?.hits.isEmpty ?? false) &&
        result?.proven == false;
  }
}

class PtJob {
  PtJob({
    required this.id,
    required this.fingerprint,
    required this.dataFingerprint,
    required this.owner,
    required this.server,
    required this.request,
    required this.cycle,
    required this.tasks,
    this.topFive = true,
    int? createdAt,
    int? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
  factory PtJob.fromJson(Map<String, Object?> json) => PtJob(
    id: '${json['id']}',
    fingerprint: '${json['fingerprint']}',
    dataFingerprint: '${json['dataFingerprint']}',
    owner: '${json['owner']}',
    server: '${json['server']}',
    request: EngineRequest.fromJson(objectRow(json['request'])),
    cycle: json['cycle'] is Map
        ? PtCycle.fromJson(objectRow(json['cycle']))
        : null,
    tasks: [
      for (final task in json['tasks'] as List? ?? const [])
        PtTask.fromJson(objectRow(task)),
    ],
    topFive: json['scope'] != 'all',
    createdAt: intOf(json['createdAt']),
    updatedAt: intOf(json['updatedAt']),
  );
  final String id;
  final String fingerprint;
  final String dataFingerprint;
  final String owner;
  final String server;
  final EngineRequest request;
  final PtCycle? cycle;
  final List<PtTask> tasks;

  /// The scope: the top five songs, or every song to proof.
  bool topFive;
  final int createdAt;
  int updatedAt;
  Map<String, Object?> toJson() => {
    'version': ptVersion,
    'id': id,
    'fingerprint': fingerprint,
    'dataFingerprint': dataFingerprint,
    'owner': owner,
    'server': server,
    'request': request.toJson(),
    'cycle': cycle?.toJson(),
    'scope': topFive ? 'top-five' : 'all',
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'tasks': [for (final task in tasks) task.toJson()],
  };
}

Object? _canonical(Object? value) => switch (value) {
  final Map map => {
    for (final key in map.keys.map((k) => '$k').toList()..sort())
      key: _canonical(map[key]),
  },
  final List list => [for (final item in list) _canonical(item)],
  _ => value,
};

/// Canonical JSON: key order cannot change identity.
String canonical(Object? value) => jsonEncode(_canonical(value));

String ptFingerprint(
  EngineRequest request,
  String dataFingerprint,
  String owner,
  PtCycle? cycle,
) => sha256
    .convert(
      utf8.encode(
        canonical({
          'version': ptVersion,
          'dataFingerprint': dataFingerprint,
          'owner': owner,
          'request': request.toJson(),
          'cycle': cycle?.toJson(),
        }),
      ),
    )
    .toString();

PtJob createPtJob(
  EngineRequest request, {
  required String server,
  required String dataFingerprint,
  required String owner,
  PtCycle? cycle,
}) {
  final goal = request.goal;
  if (goal is! EventGoal ||
      !goal.ptOnly ||
      goal.route != RouteKind.live ||
      !(goal.measure == 'points' || goal.measure == 'items')) {
    throw StateError('pt-mode');
  }
  if (cycle != null && (cycle.songs.isEmpty || cycle.consumption <= 0)) {
    throw StateError('pt-cycle-input');
  }
  final tasks = <PtTask>[
    if (cycle != null)
      for (final song in cycle.songs)
        for (final measure in const ['points', 'items'])
          PtTask(RouteKind.challenge, measure, song),
    for (final song in goal.songs)
      for (final measure
          in cycle != null ? const ['points', 'items'] : [goal.measure])
        PtTask(RouteKind.live, measure, song),
  ];
  return PtJob(
    id: '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}',
    fingerprint: ptFingerprint(request, dataFingerprint, owner, cycle),
    dataFingerprint: dataFingerprint,
    owner: owner,
    server: server,
    request: request,
    cycle: cycle,
    tasks: tasks,
  );
}

int _compareHit(EngineHit a, EngineHit b) {
  final key = b.key.compareTo(a.key);
  if (key != 0) return key;
  if (a.song!.songId != b.song!.songId) return a.song!.songId - b.song!.songId;
  if (a.song!.difficulty != b.song!.difficulty) {
    return a.song!.difficulty - b.song!.difficulty;
  }
  return canonical([a.members, a.snaps])
      .compareTo(canonical([b.members, b.snaps]));
}

/// The best hit of each song, best first.
List<EngineHit> ptSongRanking(
  PtJob job,
  String measure, [
  RouteKind route = RouteKind.live,
]) {
  final songs = <int, EngineHit>{};
  for (final task in job.tasks) {
    if (task.status != 'complete' ||
        task.measure != measure ||
        task.route != route) {
      continue;
    }
    for (final hit in task.result?.hits ?? const <EngineHit>[]) {
      if (hit.song == null || hit.event == null || !hit.event!.mean.isFinite) {
        continue;
      }
      final previous = songs[hit.song!.songId];
      if (previous == null || _compareHit(hit, previous) < 0) {
        songs[hit.song!.songId] = hit;
      }
    }
  }
  return stableSorted(songs.values, _compareHit);
}

EngineHit? ptChallengeBest(PtJob job, String measure) {
  final tasks = [
    for (final task in job.tasks)
      if (task.route == RouteKind.challenge && task.measure == measure) task,
  ];
  if (tasks.isEmpty || !tasks.every((task) => task.complete)) return null;
  return ptSongRanking(job, measure, RouteKind.challenge).firstOrNull;
}

/// A threshold only exists after five different songs have exact, legal solutions.
double? ptCutoff(PtJob job, String measure) {
  final ranking = ptSongRanking(job, measure);
  return ranking.length >= 5 ? ranking[4].key : null;
}

bool ptAllComplete(PtJob job) =>
    job.tasks.isNotEmpty && job.tasks.every((task) => task.complete);

bool ptComplete(PtJob job) {
  if (job.tasks.isEmpty) return false;
  final cutoffs = {
    'points': ptCutoff(job, 'points'),
    'items': ptCutoff(job, 'items'),
  };
  return job.tasks.every(
    (task) =>
        task.complete || (job.topFive && task.excluded(cutoffs[task.measure])),
  );
}

/// One CP's long-run reward value as a reduced fraction (`cpExchange`).
CpExchange cpExchangeOf(double rewardSum, int orders, int consumption) {
  final sum = rewardSum.toInt();
  if (sum != rewardSum || sum < 0 || orders < 1 || consumption < 1) {
    throw StateError('pt-invalid-cp-value');
  }
  final denominator = orders * consumption;
  var a = sum, b = denominator;
  while (b != 0) {
    final r = a % b;
    a = b;
    b = r;
  }
  return CpExchange(sum ~/ a, denominator ~/ a);
}

/// The cutoff a later song must strictly beat: equal rewards rank by song.
double cutoffWithMargin(double cutoff) =>
    cutoff + math.max(1, cutoff.abs()) * 1e-9;

typedef PtEngineRun = Future<EngineResponse> Function(EngineRequest request);

class PtRunner {
  PtRunner({
    required this.run,
    required this.cancel,
    required this.changed,
    required this.save,
  });
  final PtEngineRun run;
  final void Function() cancel;
  final void Function(PtJob job) changed;
  final Future<void> Function(PtJob job) save;
  bool running = false;
  bool _stopped = false;

  void stop() {
    _stopped = true;
    cancel();
  }

  Future<void> start(PtJob job, {bool? topFive}) async {
    if (running) throw StateError('pt-busy');
    running = true;
    _stopped = false;
    job.topFive = topFive ?? job.topFive;
    final scopeTopFive = job.topFive;
    // The page redraws at most four times a second and the checkpoint is
    // written at most once a second; both once more at the end.
    var savedAt = 0, shownAt = 0;
    Future<void> publish([bool force = false]) async {
      job.updatedAt = DateTime.now().millisecondsSinceEpoch;
      if (force || job.updatedAt - shownAt >= 250) {
        shownAt = job.updatedAt;
        changed(job);
      }
      if (!force && job.updatedAt - savedAt < 1000) return;
      savedAt = job.updatedAt;
      await save(job);
    }

    try {
      final cutoffs = {
        'points': ptCutoff(job, 'points'),
        'items': ptCutoff(job, 'items'),
      };
      for (final task in job.tasks) {
        if (!task.complete &&
            !(scopeTopFive && task.excluded(cutoffs[task.measure]))) {
          task
            ..status = 'queued'
            ..result = null
            ..error = '';
        }
      }
      await publish();
      int flag(bool value) => value ? 1 : 0;
      final tasks = stableSorted(job.tasks, (a, b) {
        var d =
            flag(a.route == RouteKind.live) - flag(b.route == RouteKind.live);
        if (d != 0) return d;
        d = a.song.songId - b.song.songId;
        if (d != 0) return d;
        d = a.song.difficulty - b.song.difficulty;
        if (d != 0) return d;
        return flag(a.measure == 'items') - flag(b.measure == 'items');
      });
      final base = job.request.goal as EventGoal;
      for (final task in tasks) {
        if (_stopped) break;
        if (task.complete || (scopeTopFive && task.status == 'pruned')) {
          continue;
        }
        final cycle = job.cycle;
        final challenge = cycle != null && task.route == RouteKind.live
            ? ptChallengeBest(job, task.measure)
            : null;
        if (cycle != null &&
            task.route == RouteKind.live &&
            challenge == null) {
          continue;
        }
        task.status = 'running';
        await publish();
        if (_stopped) {
          task.status = 'queued';
          break;
        }
        try {
          final cutoff = scopeTopFive && task.route == RouteKind.live
              ? ptCutoff(job, task.measure)
              : null;
          final isChallenge = task.route == RouteKind.challenge;
          final goal = EventGoal(
            measure: task.measure,
            route: task.route,
            eventId: base.eventId,
            songs: [task.song],
            consumption: isChallenge ? cycle!.consumption : base.consumption,
            play: base.play,
            ptOnly: true,
            cpExchange: challenge != null
                ? cpExchangeOf(
                    challenge.event!.rewardSum!,
                    challenge.event!.orders!,
                    cycle!.consumption,
                  )
                : null,
            gekiso: isChallenge ? null : base.gekiso,
          );
          // Tasks run in song order and equal rewards rank by song, so a
          // later song only enters the top five by beating the fifth reward.
          final response = await run(
            job.request.withGoal(
              goal,
              null,
              rewardCutoff: cutoff == null ? null : cutoffWithMargin(cutoff),
            ),
          );
          if (_stopped) {
            task.status = 'queued';
            break;
          }
          final result = response.results
              .where((r) => r.song == task.song)
              .firstOrNull;
          if (result == null) throw StateError('pt-incomplete');
          if (result.excludedBelow != null) {
            task
              ..result = result
              ..status = 'pruned';
            await publish();
            continue;
          }
          if (!result.proven) throw StateError('pt-incomplete');
          task
            ..result = result
            ..status = result.hits.isNotEmpty ? 'complete' : 'empty';
        } catch (error) {
          if (_stopped) {
            task.status = 'queued';
            break;
          }
          task
            ..status = 'failed'
            ..error = '$error';
        }
        await publish();
      }
    } finally {
      for (final task in job.tasks) {
        if (task.status == 'running') task.status = 'queued';
      }
      running = false;
      await publish(true);
    }
  }
}

/// Device-only job storage, separate from the synced box.
class PtCheckpoint {
  Future<File> _file(String server, String owner) async {
    final dir = await getApplicationSupportDirectory();
    return File(
      p.join(
        dir.path,
        'team-box',
        'pt-${Uri.encodeComponent(owner)}-$server.json',
      ),
    );
  }

  Future<void> save(PtJob job) async {
    final file = await _file(job.server, job.owner);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(job.toJson()));
    await temp.rename(file.path);
  }

  Future<PtJob?> latest(String server, String owner) async {
    final file = await _file(server, owner);
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString());
    if (json is! Map || json['version'] != ptVersion) return null;
    return PtJob.fromJson(json.cast<String, Object?>());
  }
}
