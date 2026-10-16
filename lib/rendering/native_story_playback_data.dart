part of 'native_story_playback.dart';

extension NativeStoryPlaybackPortable on NativeStoryPlayback {
  Future<Map<String, Object?>> snapshotData({
    required Future<Uint8List> Function(Uri) fetch,
  }) async => (await captureCheckpoint()).toData(fetch: fetch);

  Future<void> restoreData(
    Map data, {
    required Future<Uint8List> Function(Uri) fetch,
    List<VegaExecutionRecord>? executionHistory,
  }) async {
    requireStorySourceData(
      data['source'] as Map,
      document.chapter.sourceIdentity,
    );
    if (!const {1, 2}.contains(data['version']) ||
        data['runtimeHash'] != document.runtimeHash) {
      throw const FormatException('story_playback_data_version');
    }
    await quiesceForSeek();
    if (executionHistory != null) {
      _seekHistory = List.of(executionHistory);
    }
    final cues = await media.restoreData(
      data['media'] as Map,
      resourceHash: (uri) async => sha256.convert(await fetch(uri)).toString(),
    );
    double number(Object? value) => (value as num).toDouble();
    _updates = data['updates'] as int;
    _speed = number(data['speed']);
    _forceAuto = data['forceAuto'] as bool;
    completed = data['completed'] as bool;
    _audioStartedUpdate = data['audioStartedUpdate'] as int;
    final legacy = data['version'] == 1;
    int? legacyExecution(int? commandIndex) {
      if (commandIndex == null || executionHistory == null) return null;
      return executionHistory.reversed
          .where(
            (row) =>
                row.commandIndex == commandIndex && row.completedAtUs == null,
          )
          .firstOrNull
          ?.executionId;
    }

    _restoredPendingExecutions
      ..clear()
      ..addAll(
        legacy
            ? [
                if (legacyExecution(data['pendingCommand'] as int?)
                    case final int id)
                  id,
              ]
            : (data['pendingExecutions'] as List).cast<int>(),
      );
    _dialogueWaits
      ..clear()
      ..addAll({
        for (final entry in (data['dialogueWaits'] as Map? ?? const {}).entries)
          int.parse(entry.key as String): StoryDialogueWaitState.fromData(
            entry.value as Map,
          ),
      });
    _moviePhases
      ..clear()
      ..addAll({
        for (final entry in (data['moviePhases'] as Map).entries)
          if (!legacy ||
              legacyExecution(int.parse(entry.key as String)) != null)
            (legacy
                    ? legacyExecution(int.parse(entry.key as String))!
                    : int.parse(entry.key as String)):
                entry.value as int,
      });
    _categoryVolumes
      ..clear()
      ..addAll({
        for (final entry in (data['categoryVolumes'] as Map).entries)
          StoryMediaKind.values.byName(entry.key as String): number(
            entry.value,
          ),
      });
    _namedVolumes
      ..clear()
      ..addAll({
        for (final entry in (data['namedVolumes'] as Map).entries)
          entry.key as String: number(entry.value),
      });
    _acks
      ..clear()
      ..addAll([
        for (final raw in data['acks'] as List)
          StoryAcknowledgement(
            commandIndex: (raw as List)[0] as int,
            atUs: raw[1] as int,
            choiceKey: raw[2] as String?,
          ),
      ]);
    _sourceVolumes.clear();
    _cueGains.clear();
    _gainFades.clear();
    _categoryFades.clear();
    _scheduledStops
      ..clear()
      ..addAll({
        for (final raw in data['scheduledStops'] as List? ?? const [])
          if (cues[(raw as List)[0] as int] case final NativeStoryMediaCue cue)
            cue: _ScheduledCueStop(
              raw[1] as int,
              number(raw[2]),
              raw[3] as bool,
              raw[4] as int,
            ),
      });
    if (legacy && executionHistory != null) {
      final legacyTiming = data['timing'] as Map;
      for (final cue in cues.values) {
        if (cue.kind != StoryMediaKind.bgm && cue.kind != StoryMediaKind.sfx) {
          continue;
        }
        final command = document.chapter.commands.singleWhere(
          (row) => row.index == cue.commandIndex,
        );
        if (command.durationUs <= 0 ||
            !const {15, 31}.contains(command.opcode)) {
          continue;
        }
        final deadlines =
            (legacyTiming['${command.index}'] as List? ?? const [])
                .cast<List>()
                .where((row) => row[2] == false && row[3] == false)
                .toList();
        if (deadlines.isEmpty) continue;
        final owners = executionHistory
            .where((row) => row.commandIndex == command.index)
            .toList();
        if (deadlines.length != 1 || owners.length != 1) {
          throw const FormatException('story_legacy_cue_stop_owner');
        }
        final sound = command.opcode == 31;
        _scheduledStops[cue] = _ScheduledCueStop(
          deadlines.single[0] as int,
          command.numericParameter(sound ? 1 : 2) ?? 0,
          sound,
          owners.single.executionId,
        );
      }
    }
    for (final entry in (data['sourceVolumes'] as Map).entries) {
      _sourceVolumes[cues[int.parse(entry.key as String)]!] = number(
        entry.value,
      );
    }
    for (final entry in (data['gains'] as Map).entries) {
      _cueGains[cues[int.parse(entry.key as String)]!] = number(entry.value);
    }
    final generation = _generation;
    bool current() => !_disposed && generation == _generation;
    for (final raw in data['gainFades'] as List) {
      final value = raw as List, cue = cues[value[0] as int]!;
      final fade = _CueGainFade(
        cue,
        number(value[1]),
        number(value[2]),
        value[3] as int,
        value[4] as int,
        current,
        releaseWhenComplete: value[5] as bool,
        commandIndex: value[6] as int,
        executionId: legacy
            ? legacyExecution(value[6] as int) ?? -1
            : value[7] as int,
      );
      _gainFades.add(fade);
      if (fade.releaseWhenComplete) {
        unawaited(
          fade.completed.future.then((_) async {
            if (!current()) return;
            _cueGains.remove(cue);
            _sourceVolumes.remove(cue);
            await media.releaseCue(cue);
          }),
        );
      }
    }
    for (final raw in data['categoryFades'] as List) {
      final value = raw as List;
      _categoryFades[value[0] as String] = _CategoryVolumeFade(
        value[0] as String,
        number(value[1]),
        number(value[2]),
        value[3] as int,
        value[4] as int,
        current,
        commandIndex: value[5] as int,
        executionId: legacy
            ? legacyExecution(value[5] as int) ?? -1
            : value[6] as int,
      );
    }
    _movieCues
      ..clear()
      ..addAll({
        for (final entry in (data['movieCues'] as Map? ?? const {}).entries)
          if (cues[entry.value as int] case final NativeStoryMediaCue cue)
            int.parse(entry.key as String): cue,
      });
    if (legacy) {
      for (final id in _restoredPendingExecutions) {
        final commandIndex = executionHistory!
            .firstWhere((row) => row.executionId == id)
            .commandIndex;
        final command = document.chapter.commands.singleWhere(
          (row) => row.index == commandIndex,
        );
        if (command.opcode != 26 && command.opcode != 27) continue;
        final candidates = cues.values
            .where(
              (cue) =>
                  cue.kind == StoryMediaKind.movie &&
                  cue.id == command.videoId &&
                  cue.commandIndex == command.index,
            )
            .toList();
        if (candidates.length > 1) {
          throw const FormatException('story_legacy_movie_owner');
        }
        if (candidates.isNotEmpty) _movieCues[id] = candidates.single;
      }
    }
    final clip = data['clip'] as List;
    _clip = clip[0] == null ? null : cues[clip[0] as int];
    _clipStartUs = clip[1] as int;
    _clipElapsedUs = clip[2] as int;
    _clipTargetUs = clip[3] as int;
    _clipSkipped = clip[4] as bool;
    _restoredWaiters
      ..clear()
      ..addAll({
        for (final entry in (data['timing'] as Map).entries)
          if (!legacy ||
              legacyExecution(int.parse(entry.key as String)) != null)
            (legacy
                ? legacyExecution(int.parse(entry.key as String))!
                : int.parse(entry.key as String)): [
              for (final raw in entry.value as List)
                _RestoredCommandDeadline(
                  (raw as List)[0] as int,
                  raw[1] as int,
                  raw[2] as bool,
                  raw[3] as bool,
                ),
            ],
      });
    _seekHistory = executionHistory == null ? null : List.of(executionHistory);
    restoreClock(data['atUs'] as int);
    _observations = await media.sample();
  }
}

Future<Map<String, Object?>> _playbackCheckpointData({
  required StorySourceIdentity source,
  required String runtimeHash,
  required int atUs,
  required NativeStoryMediaSnapshot media,
  required Future<Uint8List> Function(Uri) fetch,
  required (int, double, bool, bool, int) state,
  required Set<int> pendingExecutions,
  required Map<int, StoryDialogueWaitState> dialogueWaits,
  required Map<int, int> moviePhases,
  required Map<int, String> movieCues,
  required Map<String, double> sourceVolumes,
  gains,
  required List<(String, double, double, int, int, bool, int, int)> gainFades,
  required List<(String, double, double, int, int, int, int)> categoryFades,
  required List<(String, int, double, bool, int)> scheduledStops,
  required Map<StoryMediaKind, double> volumes,
  required Map<String, double> named,
  required List<StoryAcknowledgement> acknowledgements,
  required String? clipKey,
  required (int, int, int, bool) clip,
  required Map<int, List<_RestoredCommandDeadline>> timing,
}) async {
  final slots = {
    for (final (slot, cue) in media.cues.indexed) '${cue.instanceId}': slot,
  };
  return {
    'version': 2,
    'source': source.toJson(),
    'runtimeHash': runtimeHash,
    'atUs': atUs,
    'updates': state.$1,
    'speed': state.$2,
    'forceAuto': state.$3,
    'completed': state.$4,
    'audioStartedUpdate': state.$5,
    'pendingExecutions': pendingExecutions.toList()..sort(),
    'dialogueWaits': {
      for (final entry in dialogueWaits.entries)
        '${entry.key}': entry.value.toData(),
    },
    'moviePhases': {for (final e in moviePhases.entries) '${e.key}': e.value},
    'movieCues': {
      for (final e in movieCues.entries)
        if (slots[e.value] != null) '${e.key}': slots[e.value],
    },
    'media': await media.toData(
      resourceHash: (uri) async => sha256.convert(await fetch(uri)).toString(),
    ),
    'sourceVolumes': {
      for (final e in sourceVolumes.entries)
        if (slots[e.key] != null) '${slots[e.key]}': e.value,
    },
    'gains': {
      for (final e in gains.entries)
        if (slots[e.key] != null) '${slots[e.key]}': e.value,
    },
    'gainFades': [
      for (final f in gainFades)
        if (slots[f.$1] != null)
          [slots[f.$1], f.$2, f.$3, f.$4, f.$5, f.$6, f.$7, f.$8],
    ],
    'categoryFades': [
      for (final f in categoryFades) [f.$1, f.$2, f.$3, f.$4, f.$5, f.$6, f.$7],
    ],
    'scheduledStops': [
      for (final stop in scheduledStops)
        if (slots[stop.$1] != null)
          [slots[stop.$1], stop.$2, stop.$3, stop.$4, stop.$5],
    ],
    'categoryVolumes': {for (final e in volumes.entries) e.key.name: e.value},
    'namedVolumes': named,
    'acks': [
      for (final value in acknowledgements)
        [value.commandIndex, value.atUs, value.choiceKey],
    ],
    'clip': [slots[clipKey], clip.$1, clip.$2, clip.$3, clip.$4],
    'timing': {
      for (final e in timing.entries)
        '${e.key}': [
          for (final w in e.value)
            [w.atUs, w.remainingUpdates, w.scaled, w.commonDelay],
        ],
    },
  };
}
