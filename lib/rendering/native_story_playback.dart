import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';
import 'package:vega_runtime_ffi/vega_runtime_ffi.dart';

import '../core/playback_focus.dart';
import '../core/media_lifecycle.dart';
import 'native_story_document.dart';
import 'native_story_media.dart';
import 'story_snapshot_data.dart';

part 'native_story_playback_data.dart';

/// One real host Update owns one immutable timestamp/index pair. Scene
/// dispatches resumed between Updates read this captured clock observation.
final class NativeStoryUpdateStamp {
  const NativeStoryUpdateStamp({
    required this.sourceEpoch,
    required this.updateIndex,
    required this.storyUs,
    required this.speed,
    required this.paused,
  });
  final int sourceEpoch, updateIndex, storyUs;
  final double speed;
  final bool paused;
}

/// These futures originate in a displayed native UI, including real reveal
/// and accepted Next events. The interpreter never derives text duration.
final class NativeStoryTextSession {
  const NativeStoryTextSession({
    required this.fullyRevealed,
    required this.firstTap,
    required this.waitForNextStep,
    required this.renderedLength,
    this.skipAdvance = false,
  });
  final Future<void> fullyRevealed, firstTap;
  final Future<void> Function() waitForNextStep;
  Future<void> get nextStep => waitForNextStep();
  final int renderedLength;
  final bool skipAdvance;
}

final class NativeStoryHandlers {
  const NativeStoryHandlers({
    required this.visual,
    required this.framePrepare,
    required this.text,
    required this.choice,
    required this.goto,
    required this.movieFade,
    this.onActualUpdate,
    this.onTalkBegin,
    this.subtitleNext,
    this.videoUi,
    this.frameDispatch,
    this.cancelFrameDelay,
  });
  final Future<void> Function(StoryDecodedCommand, StoryDispatchContext) visual;

  /// Select/load only; visibility/Animator changes happen after Frame's delay.
  final Future<void> Function(StoryDecodedCommand, StoryDispatchContext)
  framePrepare;
  final Future<NativeStoryTextSession> Function(
    StoryDecodedCommand,
    StoryDispatchContext,
  )
  text;
  final Future<int?> Function(StoryDecodedCommand, StoryDispatchContext) choice;
  final int? Function(StoryDecodedCommand) goto;
  final Future<void> Function(
    double alpha,
    double seconds,
    StoryDispatchContext,
  )
  movieFade;

  /// Pure scene updates run synchronously before command waiters resume.
  final void Function(NativeStoryUpdateStamp)? onActualUpdate;
  final bool Function(StoryDecodedCommand, StoryDispatchContext)? onTalkBegin;
  final void Function(bool, StoryDispatchContext)? subtitleNext;
  final void Function(StoryDecodedCommand, StoryDispatchContext)? videoUi;

  /// A complete Frame handler owns SetFrame, row delay, state and completion.
  /// The legacy prepare/delay/visual branch is used only without this handler.
  final StoryDispatchOperation Function(
    StoryDecodedCommand,
    StoryDispatchContext,
    NativeStoryUpdateStamp,
  )?
  frameDispatch;
  final void Function()? cancelFrameDelay;
}

/// Actual monotonic story phase time runs independently of every native cue's
/// decoded time-pos. Pause excludes inactive wall time from scene animations.
final class NativeStoryPlayback extends ChangeNotifier {
  NativeStoryPlayback({
    required this.document,
    required this.handlers,
    required this.sourceEpoch,
  }) {
    _actualUpdateStamp = NativeStoryUpdateStamp(
      sourceEpoch: sourceEpoch,
      updateIndex: _updates,
      storyUs: storyUs,
      speed: _speed,
      paused: paused,
    );
    media = NativeStoryMediaHost(
      sourceEpoch: sourceEpoch,
      resolve: document.assets.resolve,
      preparationPlan: StoryMediaPreparationPlan(document.chapter.commands),
      resolveUpcoming: (event) => document.assets.resolve(
        event.resourceRef ??
            document.assets.referenceFor(event.kind, event.cueId),
        event.kind,
      ),
    );
    controller = StoryPlaybackController(
      chapter: document.chapter,
      inputs: _inputs,
      dispatcher: _dispatch,
      driver: VegaFfiExecutionDriver.open(
        commandIndices: [
          for (final command in document.chapter.commands) command.index,
        ],
      ),
    );
    final volumes =
        ((document.runtime['audio'] as Map)['categoryVolumes'] as Map);
    _categoryVolumes.addAll({
      StoryMediaKind.bgm: (volumes['Bgm'] as num).toDouble(),
      StoryMediaKind.voice: (volumes['Voice'] as num).toDouble(),
      StoryMediaKind.sfx: (volumes['Se'] as num).toDouble(),
      StoryMediaKind.movie: 1,
    });
    for (final entry in volumes.entries) {
      final name = entry.key as String, value = _float32(entry.value as num);
      _namedDefaults[name] = value;
      _namedVolumes[name] = value;
    }
    MediaLifecycle.register(this, close);
  }
  bool _initialMediaPrepared = false;
  Future<void> prepareInitialMedia() async {
    await media.prepareInitialMedia();
    if (!_disposed) _initialMediaPrepared = true;
  }

  void _prepareMediaAtCursor() {
    if (_disposed || _seekReplaying || !_initialMediaPrepared) return;
    final index = controller.cursor;
    media.prepareForCommand(
      index < document.chapter.commands.length
          ? document.chapter.commands[index].index
          : (document.chapter.commands.lastOrNull?.index ?? 0) + 1,
    );
  }

  final NativeStoryDocument document;
  final NativeStoryHandlers handlers;
  final int sourceEpoch;
  late final NativeStoryMediaHost media;
  late final StoryPlaybackController controller;
  final Stopwatch _clock = Stopwatch();
  int _clockOffsetUs = 0;
  late final _focus = PlaybackFocus(pause);
  late NativeStoryUpdateStamp _actualUpdateStamp;
  NativeStoryUpdateStamp get actualUpdateStamp => _actualUpdateStamp;
  final _commandObservations = <Map<String, Object?>>[];
  List<Map<String, Object?>> get commandObservations =>
      List.unmodifiable(_commandObservations);

  void _observeCommand(Map<String, Object?> event) {
    if (!const bool.fromEnvironment('HANEOKA_NATIVE_TRACE')) return;
    final stamp = actualUpdateStamp;
    final observed = <String, Object?>{
      ...event,
      'actualUpdateIndex': stamp.updateIndex,
      'actualUpdateUs': stamp.storyUs,
      'observedStoryUs': storyUs,
    };
    _commandObservations.add(Map.unmodifiable(observed));
    if (_commandObservations.length > 32) _commandObservations.removeAt(0);
    debugPrint('HANEOKA_NATIVE_COMMAND_OBSERVATION $observed');
  }

  StoryDispatchOperation _observeOperation(
    StoryDecodedCommand command,
    StoryDispatchContext context,
    StoryDispatchOperation operation,
  ) {
    if (const bool.fromEnvironment('HANEOKA_NATIVE_TRACE') &&
        const {3, 30}.contains(command.opcode)) {
      unawaited(
        operation.completion.then<void>(
          (_) {
            _observeCommand({
              'phase': 'complete',
              'executionId': context.executionId,
              'commandIndex': command.index,
              'opcode': command.opcode,
            });
          },
          onError: (Object error, StackTrace stack) {
            _observeCommand({
              'phase': 'failed',
              'executionId': context.executionId,
              'commandIndex': command.index,
              'opcode': command.opcode,
              'error': error.toString(),
            });
          },
        ),
      );
    }
    // The original operation and original completion future remain the
    // executor's wait authority. Diagnostics attach a separate observer.
    return operation;
  }

  final _waiters = <_StoryDeadline>[];
  final _restoredWaiters = <int, List<_RestoredCommandDeadline>>{};
  final _dialogueWaits = <int, StoryDialogueWaitState>{};
  int? _skipRestoredCommonDelayExecution;
  final _moviePhases = <int, int>{};
  final _movieCues = <int, NativeStoryMediaCue>{};
  final _gainFades = <_CueGainFade>[];
  final _categoryFades = <String, _CategoryVolumeFade>{};
  final _sourceVolumes = <NativeStoryMediaCue, double>{};
  final _cueGains = <NativeStoryMediaCue, double>{};
  final _scheduledStops = <NativeStoryMediaCue, _ScheduledCueStop>{};
  bool _updatingVolumes = false;
  List<StoryMediaObservation> _observations = const [];
  List<StoryMediaObservation> get mediaObservations => _observations;
  bool get voiceShortcut => _seekReplaying;
  StoryPresentationTiming get visualTiming =>
      StoryPresentationTiming(shortcut: _seekReplaying);
  int _transportIntent = 0;
  bool _wantsPlayback = false;
  final _acks = <StoryAcknowledgement>[];
  NativeStoryMediaCue? _clip;
  int _clipStartUs = 0, _clipElapsedUs = 0, _clipTargetUs = 0;
  bool _clipSkipped = false;
  Completer<void> _updated = Completer<void>();
  void skipClip() {
    if (_disposed || _clip == null) return;
    _clipSkipped = true;
    _clipTargetUs = _clipElapsedUs;
    notifyListeners();
  }

  final _categoryVolumes = <StoryMediaKind, double>{};
  final _namedDefaults = <String, double>{}, _namedVolumes = <String, double>{};
  StoryMediaKind? _categoryKind(String name) => switch (name) {
    'Bgm' => StoryMediaKind.bgm,
    'Voice' => StoryMediaKind.voice,
    'Se' => StoryMediaKind.sfx,
    _ => null,
  };
  bool _autoPlayback = false;
  bool _forceAuto = false;
  bool get autoPlayback => _autoPlayback || _forceAuto;
  int _autoToken = 0;
  Completer<void> _autoChanged = Completer<void>();
  void setAutoPlayback(bool enabled) {
    if (_disposed || enabled == _autoPlayback) return;
    _autoPlayback = enabled;
    _autoToken++;
    _autoChanged.complete();
    _autoChanged = Completer<void>();
    notifyListeners();
  }

  bool completed = false;
  bool voiceEnabled = true, _disposed = false, paused = true, _sampling = false;
  double _speed = 1, userVolume = 1;
  double userBgmVolume = 1, autoDelaySeconds = .5;
  bool bgmEnabled = true;
  bool get canSkipClip => !_disposed && _clip != null;
  bool _fastForward = false;
  bool _seekReplaying = false;
  List<VegaExecutionRecord>? _seekHistory;
  final _replayActiveExecutions = <int>{};
  final _restoredPendingExecutions = <int>{};
  Future<NativeStoryTextSession> Function(
    StoryDecodedCommand,
    StoryDispatchContext,
  )?
  resumeRestoredText;
  Future<StoryDispatchCompletion> Function(
    StoryDecodedCommand,
    StoryDispatchContext,
  )?
  resumeRestoredCommand;
  bool get fastForward => _fastForward;

  Future<void> toggleFastForward() async {
    if (_disposed) return;
    _fastForward = !_fastForward;
    await setSpeed(_fastForward ? 2 : 1);
    ++_voiceScope;
    await media.stopKind(StoryMediaKind.voice);
    if (!_disposed) notifyListeners();
  }

  Future<void> skipToEnd() async {
    if (_disposed || completed) return;
    ++_generation;
    ++_voiceScope;
    controller.driver.reposition(document.chapter.commands.length);
    controller.stop();
    _clock.stop();
    paused = true;
    completed = true;
    await Future.wait([
      for (final kind in StoryMediaKind.values) media.stopKind(kind),
    ]);
    if (!_disposed) notifyListeners();
  }

  Future<void> setUserAudio({
    required double master,
    required double bgm,
    required bool enabled,
  }) async {
    if (!master.isFinite || !bgm.isFinite) {
      throw ArgumentError('story_user_audio');
    }
    userVolume = master.clamp(0.0, 1.0);
    userBgmVolume = bgm.clamp(0.0, 1.0);
    bgmEnabled = enabled;
    await Future.wait([for (final cue in media.cues) _applyVolume(cue)]);
    if (!_disposed) notifyListeners();
  }

  double _userGain(StoryMediaKind kind) =>
      userVolume *
      (kind == StoryMediaKind.bgm ? (bgmEnabled ? userBgmVolume : 0) : 1);
  double get speed => _speed;
  Future<void> setSpeed(double value) async {
    if (_disposed) return;
    if (!value.isFinite || value <= 0) {
      throw ArgumentError('story_playback_speed');
    }
    final now = storyUs, ratio = _speed / value;
    for (final waiter in _waiters) {
      if (waiter.scaled) {
        waiter.atUs =
            now +
            ((waiter.atUs - now) * ratio).clamp(0, double.infinity).round();
      }
    }
    for (final pending in _restoredWaiters.values) {
      for (final waiter in pending) {
        if (waiter.scaled) {
          waiter.atUs =
              now +
              ((waiter.atUs - now) * ratio).clamp(0, double.infinity).round();
        }
      }
    }
    _speed = value;
    await Future.wait([
      for (final cue in media.cues)
        if (cue.kind == StoryMediaKind.voice ||
            cue.kind == StoryMediaKind.movie)
          cue.setRate(value),
    ]);
    if (!_disposed) notifyListeners();
  }

  int _generation = 0,
      _voiceScope = 0,
      _updates = 0,
      _audioStartedUpdate = -100;
  double runtimeNumber(String key) => (document.runtime[key] as num).toDouble();
  double get minTalkDisplaySeconds => runtimeNumber('minTalkDisplayTime');
  double get waitAfterVoiceSeconds => runtimeNumber('waitAfterVoiceTime');
  double get waitTextUnitSeconds => runtimeNumber('waitTalkTextUnitTime');
  int get storyUs => _clockOffsetUs + _clock.elapsedMicroseconds;
  VegaCheckpointExecutionDriver get checkpointDriver =>
      controller.driver as VegaCheckpointExecutionDriver;
  StorySceneState get state => _seekHistory == null
      ? controller.snapshot()
      : StoryTimeline(document.chapter, _seekHistory!).evaluateAt(_inputs());
  Object? error;
  StackTrace? errorStackTrace;

  StoryRuntimeInputs _inputs() {
    final driver = controller.driver;
    final known =
        _seekHistory == null && driver is VegaExecutionOwnershipDriver;
    return StoryRuntimeInputs(
      sourceIdentity: document.chapter.sourceIdentity,
      atUs: storyUs,
      sourceEpoch: sourceEpoch,
      executionOwnershipKnown: known,
      blockingExecutionId: known
          ? (driver as VegaExecutionOwnershipDriver).blockingExecutionId
          : null,
      mediaObservations: _observations,
      acknowledgements: _acks,
    );
  }

  Future<void> play() async {
    if (_disposed || completed) return;
    final intent = ++_transportIntent;
    _wantsPlayback = true;
    final generation = _generation;
    bool current() =>
        !_disposed &&
        !completed &&
        generation == _generation &&
        intent == _transportIntent;
    await _focus.activate(() async {
      if (!await _resumeMediaIfCurrent(current)) return;
      _clock.start();
      paused = false;
    });
    if (_disposed ||
        generation != _generation ||
        intent != _transportIntent ||
        controller.driver.playing) {
      return;
    }
    try {
      await controller.play();
      if (_disposed || generation != _generation) {
        return;
      }
      final failure = controller.failure;
      if (failure != null) {
        throw StateError(
          'story_command:${failure.commandIndex}: ${failure.reason}',
        );
      }
      final context = StoryDispatchContext(
        executionId: -1,
        inputs: _inputs(),
        isCurrent: () => !_disposed && generation == _generation,
      );
      await Future.wait([
        for (final cue in media.cues.toList())
          _fadeAndRelease(cue, .3, context),
      ]);
      if (_disposed || generation != _generation) return;
      _clock.stop();
      paused = true;
      completed = true;
      _wantsPlayback = false;
      ++_transportIntent;
      if (const bool.fromEnvironment('HANEOKA_NATIVE_TRACE')) {
        debugPrint(
          'HANEOKA_NATIVE_STORY_COMPLETE source=${document.chapter.sourceIdentity.document} '
          'commands=${document.chapter.commands.length} cursor=${controller.cursor} '
          'storyUs=$storyUs cues=${media.cues.length} error=$error',
        );
      }
    } catch (failure, stack) {
      if (_disposed || generation != _generation) return;
      error = failure;
      errorStackTrace = stack;
      paused = true;
      _wantsPlayback = false;
      ++_transportIntent;
      _clock.stop();
      await media.pause();
      rethrow;
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    ++_transportIntent;
    _wantsPlayback = false;
    controller.pause();
    _clock.stop();
    paused = true;
    await media.pause();
    if (!_disposed) notifyListeners();
  }

  Future<bool> _resumeMediaIfCurrent(bool Function() current) async {
    if (!current()) return false;
    await media.resume();
    if (current()) return true;
    if (!_disposed && !_wantsPlayback) await media.pause();
    return false;
  }

  Future<void> resume() {
    if (_disposed || completed) return Future.value();
    final intent = ++_transportIntent, generation = _generation;
    _wantsPlayback = true;
    bool current() =>
        !_disposed &&
        !completed &&
        generation == _generation &&
        intent == _transportIntent;
    return _focus.activate(() async {
      if (!await _resumeMediaIfCurrent(current)) return;
      paused = false;
      _clock.start();
      if (controller.driver.playing) {
        controller.resume();
      } else {
        unawaited(
          play().catchError((Object failure, StackTrace stack) {
            if (_disposed || generation != _generation || error != null) return;
            error = failure;
            errorStackTrace = stack;
            paused = true;
            _wantsPlayback = false;
            ++_transportIntent;
            _clock.stop();
            unawaited(media.pause());
            notifyListeners();
          }),
        );
      }
      notifyListeners();
    });
  }

  /// Capture active execution ownership before retiring asynchronous handlers.
  /// Deadlines stay available until the host has captured its paused state.
  VegaExecutionCheckpoint freezeForSeek() {
    if (_disposed) throw StateError('story_source_closed');
    for (final waiter in _waiters.toList()) {
      if (waiter.current()) continue;
      _waiters.remove(waiter);
      if (!waiter.completion.isCompleted) {
        waiter.completion.completeError(StateError('story_wait_cancelled'));
      }
    }
    final execution = checkpointDriver.captureCheckpoint();
    _retireForSeek();
    return execution;
  }

  void _retireForSeek() {
    ++_transportIntent;
    _wantsPlayback = false;
    ++_generation;
    ++_voiceScope;
    controller.stop();
    _replayActiveExecutions.clear();
    _skipRestoredCommonDelayExecution = null;
    _clock.stop();
    paused = true;
  }

  Future<void> settleForCheckpoint() async {
    do {
      await media.settleResources();
      // Dispatch completion may queue another cue or its scheduled stop.
      await Future<void>.delayed(Duration.zero);
    } while (media.hasPendingResources || _updatingVolumes);
  }

  Future<void> quiesceForSeek() async {
    if (_disposed) throw StateError('story_source_closed');
    _retireForSeek();
    handlers.cancelFrameDelay?.call();
    for (final waiter in _waiters) {
      if (!waiter.completion.isCompleted) {
        waiter.completion.completeError(StateError('story_seek_retired'));
      }
    }
    _waiters.clear();
    for (final fade in _gainFades) {
      if (!fade.completed.isCompleted) fade.completed.complete();
    }
    for (final fade in _categoryFades.values) {
      if (!fade.completed.isCompleted) fade.completed.complete();
    }
    final updated = _updated;
    _updated = Completer<void>();
    if (!updated.isCompleted) updated.complete();
    await media.pause();
    restoreClock(storyUs);
    handlers.onActualUpdate?.call(actualUpdateStamp);
    notifyListeners();
  }

  NativeStoryUpdateStamp restoreClock(int atUs, {bool replay = false}) {
    if (atUs < 0 || _disposed) throw StateError('story_restore_clock');
    _clock
      ..stop()
      ..reset();
    _clockOffsetUs = atUs;
    _actualUpdateStamp = NativeStoryUpdateStamp(
      sourceEpoch: sourceEpoch,
      updateIndex: ++_updates,
      storyUs: atUs,
      speed: speed,
      paused: !replay,
    );
    controller.invalidateSnapshot();
    return _actualUpdateStamp;
  }

  Future<void> advanceReplayTo(int atUs) async {
    final stamp = restoreClock(atUs < storyUs ? storyUs : atUs, replay: true);
    media.advanceReplayTo(stamp.storyUs);
    handlers.onActualUpdate?.call(stamp);
    await _updateVolumes(stamp.storyUs);
    for (final waiter in _waiters.toList()) {
      if (!waiter.current()) {
        _waiters.remove(waiter);
        if (!waiter.completion.isCompleted) {
          waiter.completion.completeError(StateError('story_seek_retired'));
        }
      } else if (stamp.storyUs >= waiter.atUs && _updates >= waiter.update) {
        _waiters.remove(waiter);
        if (!waiter.completion.isCompleted) waiter.completion.complete();
      }
    }
    final updated = _updated;
    _updated = Completer<void>();
    if (!updated.isCompleted) updated.complete();
  }

  Future<void> finishSeek({required int atUs, required bool resume}) async {
    ++_transportIntent;
    _wantsPlayback = false;
    await media.finishReplay();
    _seekHistory = null;
    _seekReplaying = false;
    _prepareMediaAtCursor();
    await Future.wait([for (final cue in media.cues) _applyVolume(cue)]);
    restoreClock(atUs);
    handlers.onActualUpdate?.call(actualUpdateStamp);
    completed =
        controller.cursor >= document.chapter.commands.length &&
        checkpointDriver.captureCheckpoint().activeExecutionIds.isEmpty;
    error = null;
    errorStackTrace = null;
    controller.failure = null;
    paused = true;
    await media.pause();
    notifyListeners();
    if (resume && !completed) await this.resume();
  }

  Future<NativeStoryPlaybackCheckpoint> captureCheckpoint({
    Set<int>? activeExecutionIds,
  }) async {
    final active =
        activeExecutionIds ??
        (_seekHistory == null
            ? checkpointDriver.captureCheckpoint().activeExecutionIds.toSet()
            : {..._restoredPendingExecutions, ..._replayActiveExecutions});
    final mediaState = await media.snapshot(projectedVolume: _cueVolume);
    final moviePhases = Map<int, int>.of(_moviePhases);
    String cueKey(NativeStoryMediaCue cue) => '${cue.instanceId}';
    final movieCues = {
      for (final entry in _movieCues.entries) entry.key: cueKey(entry.value),
    };
    final sourceVolumes = {
      for (final entry in _sourceVolumes.entries)
        cueKey(entry.key): entry.value,
    };
    final gains = {
      for (final entry in _cueGains.entries) cueKey(entry.key): entry.value,
    };
    final gainFades = [
      for (final fade in _gainFades)
        (
          cueKey(fade.cue),
          fade.from,
          fade.to,
          fade.startUs,
          fade.durationUs,
          fade.releaseWhenComplete,
          fade.commandIndex,
          fade.executionId,
        ),
    ];
    final categoryFades = [
      for (final fade in _categoryFades.values)
        (
          fade.name,
          fade.from,
          fade.to,
          fade.startUs,
          fade.durationUs,
          fade.commandIndex,
          fade.executionId,
        ),
    ];
    final scheduledStops = [
      for (final entry in _scheduledStops.entries)
        (
          cueKey(entry.key),
          entry.value.atUs,
          entry.value.fadeSeconds,
          entry.value.scaleFadeBySpeed,
          entry.value.executionId,
        ),
    ];
    final volumes = Map<StoryMediaKind, double>.of(_categoryVolumes);
    final named = Map<String, double>.of(_namedVolumes);
    final acknowledgements = List<StoryAcknowledgement>.of(_acks);
    final clipKey = _clip == null ? null : cueKey(_clip!);
    final clip = (_clipStartUs, _clipElapsedUs, _clipTargetUs, _clipSkipped);
    final state = (
      _updates,
      _speed,
      _forceAuto,
      completed,
      _audioStartedUpdate,
    );
    final history = List<VegaExecutionRecord>.of(
      _seekHistory ?? controller.driver.history,
    );
    final pendingExecutions = Set<int>.of(active);
    final dialogueWaits = {
      for (final entry in _dialogueWaits.entries)
        if (active.contains(entry.key)) entry.key: entry.value.copy(),
    };
    final timing = <int, List<_RestoredCommandDeadline>>{};
    for (final waiter in _waiters) {
      if (!active.contains(waiter.executionId)) continue;
      (timing[waiter.executionId] ??= []).add(
        _RestoredCommandDeadline(
          waiter.atUs,
          (waiter.update - _updates).clamp(0, 0x7fffffff),
          waiter.scaled,
          waiter.commonCommandDelay,
        ),
      );
    }
    for (final entry in _restoredWaiters.entries) {
      if (!active.contains(entry.key)) continue;
      timing.putIfAbsent(
        entry.key,
        () => [for (final row in entry.value) row.copy()],
      );
    }
    for (final entry in dialogueWaits.entries) {
      final state = entry.value;
      if (state.timerPhase != state.phase || state.timerDeadlineUs == null) {
        continue;
      }
      final pending = timing[entry.key];
      state.timerDeadlineUs = pending == null || pending.isEmpty
          ? storyUs
          : pending.map((value) => value.atUs).reduce((a, b) => a > b ? a : b);
    }
    final capturedAtUs = storyUs;
    return NativeStoryPlaybackCheckpoint._(
      document.chapter.sourceIdentity,
      sourceEpoch,
      storyUs,
      mediaState,
      (fetch) => _playbackCheckpointData(
        source: document.chapter.sourceIdentity,
        runtimeHash: document.runtimeHash,
        atUs: capturedAtUs,
        media: mediaState,
        fetch: fetch,
        state: state,
        pendingExecutions: pendingExecutions,
        dialogueWaits: dialogueWaits,
        moviePhases: moviePhases,
        movieCues: movieCues,
        sourceVolumes: sourceVolumes,
        gains: gains,
        gainFades: gainFades,
        categoryFades: categoryFades,
        scheduledStops: scheduledStops,
        volumes: volumes,
        named: named,
        acknowledgements: acknowledgements,
        clipKey: clipKey,
        clip: clip,
        timing: timing,
      ),
      () {
        _seekHistory = List.of(history);
        _restoredPendingExecutions
          ..clear()
          ..addAll(pendingExecutions);
        _dialogueWaits
          ..clear()
          ..addAll({
            for (final entry in dialogueWaits.entries)
              entry.key: entry.value.copy(),
          });
        _moviePhases
          ..clear()
          ..addAll(moviePhases);
        _restoredWaiters
          ..clear()
          ..addAll({
            for (final entry in timing.entries)
              entry.key: [for (final row in entry.value) row.copy()],
          });
        _updates = state.$1;
        _speed = state.$2;
        _forceAuto = state.$3;
        completed = state.$4;
        _audioStartedUpdate = state.$5;
        _categoryVolumes
          ..clear()
          ..addAll(volumes);
        _namedVolumes
          ..clear()
          ..addAll(named);
        _acks
          ..clear()
          ..addAll(acknowledgements);
        _observations = const [];
        _sourceVolumes.clear();
        _cueGains.clear();
        _gainFades.clear();
        _categoryFades.clear();
        final generation = _generation;
        bool current() => !_disposed && generation == _generation;
        final cuesByKey = {for (final cue in media.cues) cueKey(cue): cue};
        _movieCues
          ..clear()
          ..addAll({
            for (final entry in movieCues.entries)
              if (cuesByKey[entry.value] case final NativeStoryMediaCue cue)
                entry.key: cue,
          });
        _scheduledStops
          ..clear()
          ..addAll({
            for (final stop in scheduledStops)
              if (cuesByKey[stop.$1] case final NativeStoryMediaCue cue)
                cue: _ScheduledCueStop(stop.$2, stop.$3, stop.$4, stop.$5),
          });
        for (final cue in media.cues) {
          _sourceVolumes[cue] = sourceVolumes[cueKey(cue)] ?? 1;
          _cueGains[cue] = gains[cueKey(cue)] ?? 1;
        }
        for (final fade in gainFades) {
          final cue = cuesByKey[fade.$1];
          if (cue != null) {
            final restored = _CueGainFade(
              cue,
              fade.$2,
              fade.$3,
              fade.$4,
              fade.$5,
              current,
              releaseWhenComplete: fade.$6,
              commandIndex: fade.$7,
              executionId: fade.$8,
            );
            _gainFades.add(restored);
            if (fade.$6) {
              unawaited(
                restored.completed.future.then((_) async {
                  if (!current()) return;
                  _cueGains.remove(cue);
                  _sourceVolumes.remove(cue);
                  await media.releaseCue(cue);
                }),
              );
            }
          }
        }
        for (final fade in categoryFades) {
          _categoryFades[fade.$1] = _CategoryVolumeFade(
            fade.$1,
            fade.$2,
            fade.$3,
            fade.$4,
            fade.$5,
            current,
            commandIndex: fade.$6,
            executionId: fade.$7,
          );
        }
        _clip = clipKey == null ? null : cuesByKey[clipKey];
        _clipStartUs = clip.$1;
        _clipElapsedUs = clip.$2;
        _clipTargetUs = clip.$3;
        _clipSkipped = clip.$4;
      },
    );
  }

  Future<void> restoreCheckpoint(
    NativeStoryPlaybackCheckpoint checkpoint,
  ) async {
    if (checkpoint.sourceIdentity != document.chapter.sourceIdentity ||
        checkpoint.sourceEpoch != sourceEpoch) {
      throw const FormatException('story_playback_checkpoint_source');
    }
    await quiesceForSeek();
    await media.restore(checkpoint.media, replayAtUs: checkpoint.atUs);
    checkpoint._restore();
    restoreClock(checkpoint.atUs);
    _observations = await media.sample();
  }

  Future<void> waitRestoredExecutionTiming(
    int executionId, {
    bool Function()? additionalCurrent,
  }) async {
    final saved =
        _restoredWaiters.remove(executionId) ??
        const <_RestoredCommandDeadline>[];
    final generation = controller.driver.generation;
    final waiting = <Future<void>>[];
    for (final value in saved) {
      if (value.atUs <= storyUs && value.remainingUpdates == 0) continue;
      final done = Completer<void>();
      _waiters.add(
        _StoryDeadline(
          value.atUs,
          _updates + value.remainingUpdates,
          () =>
              !_disposed &&
              generation == controller.driver.generation &&
              (additionalCurrent?.call() ?? true),
          done,
          value.scaled,
          value.commonDelay,
          executionId,
        ),
      );
      waiting.add(done.future);
    }
    waiting.addAll([
      for (final fade in _gainFades)
        if (fade.executionId == executionId) fade.completed.future,
      for (final fade in _categoryFades.values)
        if (fade.executionId == executionId) fade.completed.future,
    ]);
    await Future.wait(waiting);
  }

  Future<StoryDispatchCompletion> _resumeRestoredVideo(
    StoryDecodedCommand command,
    StoryDispatchContext context,
    Future<StoryDispatchCompletion> Function(
      StoryDecodedCommand,
      StoryDispatchContext,
    )?
    resumeHost,
  ) async {
    final phase = _moviePhases[context.executionId] ?? 0;
    final cue = _movieCues[context.executionId];
    if (cue != null && phase <= 1) await cue.firstVideoFrame();
    if (!context.isCurrent()) return const StoryDispatchCompletion();
    if (resumeHost != null && (phase <= 1 || phase == 3)) {
      await resumeHost(command, context);
      if (!context.isCurrent()) return const StoryDispatchCompletion();
    }
    if (command.opcode == 26) {
      if (cue != null && phase <= 2) await cue.completed;
      if (!context.isCurrent()) return const StoryDispatchCompletion();
      if (phase <= 2) {
        final policy = storyWaitingPolicy(
          command,
          videoPlaying: false,
          autoPlayback: autoPlayback,
        )!;
        await handlers.movieFade(0, policy.fadeOutSeconds / speed, context);
        if (!context.isCurrent()) return const StoryDispatchCompletion();
      }
      await media.stopKind(StoryMediaKind.movie);
      if (!context.isCurrent()) return const StoryDispatchCompletion();
      _clip = null;
    }
    _moviePhases.remove(context.executionId);
    _movieCues.remove(context.executionId);
    return const StoryDispatchCompletion();
  }

  int _commandIndexForExecution(int executionId) {
    for (final row in _seekHistory ?? controller.driver.history) {
      if (row.executionId == executionId) return row.commandIndex;
    }
    return -1;
  }

  /// Starts one replay handler without advancing the source clock. Detached
  /// work remains active while following commands are admitted.
  Future<VegaReplayOperation> replayCommand(
    VegaExecutionRecord execution,
    VegaSeekContext seek, {
    required Future<void> Function(StoryDecodedCommand, StoryDispatchContext)
    text,
    required Future<int?> Function(StoryDecodedCommand, StoryDispatchContext)
    choice,
    bool resuming = false,
  }) async {
    seek.checkCurrent();
    _seekReplaying = true;
    media.cancelPreparation();
    await media.beginReplay(storyUs);
    final command = document.chapter.commands.singleWhere(
      (row) => row.index == execution.commandIndex,
    );
    final history = _seekHistory ??= [];
    final historyPosition = resuming
        ? history.indexWhere((row) => row.executionId == execution.executionId)
        : history.length;
    if (historyPosition < 0) throw StateError('story_replay_active_history');
    if (!resuming) history.add(execution);
    final generation = _generation;
    final context = StoryDispatchContext(
      executionId: execution.executionId,
      inputs: _inputs(),
      resuming: resuming,
      isCurrent: () =>
          !_disposed && generation == _generation && seek.isCurrent(),
    );
    Future<StoryDispatchCompletion> dispatchSpecial() async {
      if (command.ignoreData) return const StoryDispatchCompletion();
      if (const {2, 28, 29, 36, 37, 38, 39, 52, 65}.contains(command.opcode)) {
        if (command.opcode == 36 && !resuming) {
          await handlers.visual(command, context);
        }
        await text(command, context);
        acknowledge(command.index);
        return const StoryDispatchCompletion();
      }
      if (command.opcode == 41) {
        return StoryDispatchCompletion(
          nextCommandIndex: await choice(command, context),
        );
      }
      if (command.opcode == 26 || command.opcode == 27) {
        handlers.videoUi?.call(command, context);
        if (command.opcode == 26 || command.videoId == '0') {
          _clip = null;
          await handlers.movieFade(0, 0, context);
          await media.stopKind(StoryMediaKind.movie);
        } else {
          _clip = await _cue(
            command,
            context,
            StoryMediaKind.movie,
            command.videoId,
            reference: command.resourceRefs['videoRef'],
          );
          _clipStartUs = _clip?.player.state.position.inMicroseconds ?? 0;
          _clipElapsedUs = _clipTargetUs = 0;
          _clipSkipped = false;
          await handlers.movieFade(1, 0, context);
        }
        return const StoryDispatchCompletion();
      }
      throw StateError('story_replay_special_command');
    }

    final special =
        command.ignoreData ||
        const {
          2,
          28,
          29,
          36,
          37,
          38,
          39,
          52,
          65,
          41,
          26,
          27,
        }.contains(command.opcode);
    Future<StoryDispatchCompletion> projectSpecial() async {
      if (resuming) {
        if (!_restoredPendingExecutions.remove(execution.executionId)) {
          throw StateError('story_restored_execution:${execution.executionId}');
        }
        await waitRestoredExecutionTiming(execution.executionId);
        if (!context.isCurrent()) throw const VegaSeekCancelled();
      }
      return dispatchSpecial();
    }

    final operation = special
        ? StoryDispatchOperation(
            completion: projectSpecial(),
            waitForCompletion: resuming
                ? execution.waitForCompletion!
                : !command.ignoreData && _commandWaitsForHandler(command),
          )
        : _dispatch(command, context);
    history[historyPosition] = VegaExecutionRecord(
      executionId: execution.executionId,
      commandIndex: execution.commandIndex,
      startedAtUs: execution.startedAtUs,
      waitForCompletion: operation.waitForCompletion,
    );
    _replayActiveExecutions.add(execution.executionId);
    final completion = operation.completion.then<VegaReplayCompletion>(
      (value) {
        if (!context.isCurrent()) throw const VegaSeekCancelled();
        _replayActiveExecutions.remove(execution.executionId);
        history[historyPosition] = VegaExecutionRecord(
          executionId: execution.executionId,
          commandIndex: execution.commandIndex,
          startedAtUs: execution.startedAtUs,
          completedAtUs: storyUs,
          nextCommandIndex: value.nextCommandIndex,
          waitForCompletion: operation.waitForCompletion,
        );
        return VegaReplayCompletion(
          atUs: storyUs,
          nextCommandIndex: value.nextCommandIndex,
        );
      },
      onError: (Object error, StackTrace stack) {
        if (context.isCurrent()) {
          _replayActiveExecutions.remove(execution.executionId);
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    return VegaReplayOperation(
      waitForCompletion: operation.waitForCompletion,
      completion: completion,
    );
  }

  /// The coordinator invokes this pump only for a blocking command. All
  /// detached deadlines share the same source-update and resource frontier.
  Future<VegaReplayCompletion> waitForReplay(
    Future<VegaReplayCompletion> completion,
    VegaSeekContext seek, {
    required Future<void> Function() settle,
    required Future<void> Function(NativeStoryUpdateStamp) advanceUi,
    required int? Function(NativeStoryUpdateStamp) visualDeadline,
  }) async {
    VegaReplayCompletion? value;
    Object? failure;
    StackTrace? failureStack;
    var done = false;
    final operation = completion.then<void>(
      (result) {
        value = result;
        done = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        done = true;
      },
    );
    final eventBudget = Stopwatch()..start();
    while (!done) {
      // Resource latency stays outside the offline source clock.
      await Future<void>.value();
      seek.checkCurrent();
      if (media.hasPendingResources) await media.settleResources();
      await settle();
      if (done) break;
      int? deadline = visualDeadline(actualUpdateStamp);
      for (final waiter in _waiters) {
        deadline = deadline == null || waiter.atUs < deadline
            ? waiter.atUs
            : deadline;
      }
      for (final fade in [..._gainFades, ..._categoryFades.values]) {
        final end = switch (fade) {
          _CueGainFade value => value.startUs + value.durationUs,
          _CategoryVolumeFade value => value.startUs + value.durationUs,
          _ => storyUs,
        };
        deadline = deadline == null || end < deadline ? end : deadline;
      }
      for (final stop in _scheduledStops.values) {
        deadline = deadline == null || stop.atUs < deadline
            ? stop.atUs
            : deadline;
      }
      if (_clip != null && _clipTargetUs > _clipElapsedUs) {
        deadline = deadline == null || storyUs + 16667 < deadline
            ? storyUs + 16667
            : deadline;
      }
      if (deadline == null || eventBudget.elapsedMicroseconds >= 4000) {
        await Future<void>.delayed(Duration.zero);
        eventBudget.reset();
        seek.checkCurrent();
        if (deadline == null) continue;
      }
      final next = deadline > storyUs + 16667 ? storyUs + 16667 : deadline;
      await advanceReplayTo(next);
      await advanceUi(actualUpdateStamp);
    }
    await operation;
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    seek.checkCurrent();
    await settle();
    return value!;
  }

  /// The normal widget's actual update callback drives deadlines and native
  /// observations. It does not supply a synthetic elapsed time.
  Future<void> actualUpdate() async {
    if (_disposed || paused) return;
    final time = storyUs;
    _updates++;
    final stamp = NativeStoryUpdateStamp(
      sourceEpoch: sourceEpoch,
      updateIndex: _updates,
      storyUs: time,
      speed: _speed,
      paused: paused,
    );
    _actualUpdateStamp = stamp;
    handlers.onActualUpdate?.call(stamp);
    final updated = _updated;
    _updated = Completer<void>();
    updated.complete();
    await _updateVolumes(time);
    for (final waiter in _waiters.toList()) {
      if (!waiter.current()) {
        _waiters.remove(waiter);
        waiter.completion.completeError(StateError('story_wait_cancelled'));
      } else if (time >= waiter.atUs && _updates >= waiter.update) {
        _waiters.remove(waiter);
        waiter.completion.complete();
      }
    }
    if (_sampling) return;
    _sampling = true;
    final generation = _generation;
    try {
      final observations = await media.sample();
      if (!_disposed && generation == _generation) _observations = observations;
    } finally {
      _sampling = false;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _wait(
    double seconds,
    StoryDispatchContext context, {
    bool scaled = true,
    bool durationAlreadyScaled = false,
    bool commonCommandDelay = false,
    int updates = 0,
    bool Function()? additionalCurrent,
  }) {
    if (!context.isCurrent() || _disposed) {
      return Future.error(StateError('story_wait_cancelled'));
    }
    final time =
        (mathMax(0, seconds) *
                1000000 /
                (scaled && !durationAlreadyScaled ? speed : 1))
            .round();
    if (time == 0 && updates == 0) return Future.value();
    final completion = Completer<void>();
    _waiters.add(
      _StoryDeadline(
        storyUs + time,
        _updates + updates,
        () =>
            context.isCurrent() &&
            !_disposed &&
            (additionalCurrent?.call() ?? true),
        completion,
        scaled,
        commonCommandDelay,
        context.executionId,
      ),
    );
    if (const bool.fromEnvironment('HANEOKA_NATIVE_TRACE')) {
      final deadline = _waiters.last;
      _observeCommand({
        'phase': 'waitQueued',
        'executionId': context.executionId,
        'targetStoryUs': deadline.atUs,
        'minimumUpdateIndex': deadline.update,
        'seconds': seconds,
        'scaled': deadline.scaled,
        'commonCommandDelay': deadline.commonCommandDelay,
      });
    }
    return completion.future;
  }

  Future<void> _delay(double seconds, StoryDispatchContext context) async {
    final clip = _clip;
    if (clip == null) return _wait(seconds, context);
    _clipTargetUs += (mathMax(0, seconds) * 1000000).round();
    var stalledUs = 0, previousUpdateUs = storyUs;
    while (context.isCurrent() && !_disposed) {
      if (_clipSkipped) return;
      final sampled = identical(_clip, clip) && media.cues.contains(clip)
          ? await clip.videoClock()
          : null;
      if (!context.isCurrent() || _disposed) {
        throw StateError('story_source_replaced');
      }
      final now = storyUs,
          elapsed = sampled == null
              ? _clipElapsedUs
              : (sampled.positionUs - _clipStartUs).clamp(
                  0,
                  0x7fffffffffffffff,
                );
      if (elapsed > _clipElapsedUs) {
        _clipElapsedUs = elapsed;
        stalledUs = 0;
      } else if (sampled?.suspended == true) {
        stalledUs = 0;
      } else {
        stalledUs += now - previousUpdateUs;
      }
      previousUpdateUs = now;
      if (_clipElapsedUs >= _clipTargetUs) return;
      if (sampled == null || sampled.ended || stalledUs >= 5000000) {
        final remaining = (_clipTargetUs - _clipElapsedUs) / 1000000;
        if (identical(_clip, clip)) _clip = null;
        return _wait(remaining, context);
      }
      await _updated.future;
    }
    throw StateError('story_source_closed');
  }

  void acknowledge(int commandIndex) {
    if (_disposed) return;
    _acks.add(StoryAcknowledgement(commandIndex: commandIndex, atUs: storyUs));
  }

  /// Each original handler selects its own delay point. Common row delays
  /// capture speed once; Delay and Wait commands own separate dynamic waits.
  Future<void> waitLocation(double seconds, StoryDispatchContext context) =>
      _wait(seconds, context);

  Future<void> waitVisualDuration(
    double seconds,
    StoryDispatchContext context, {
    bool Function()? stillWaiting,
  }) async {
    try {
      await _wait(seconds, context, additionalCurrent: stillWaiting);
    } catch (_) {
      if (context.isCurrent() && stillWaiting != null && !stillWaiting()) {
        return;
      }
      rethrow;
    }
  }

  Future<void> waitCommonCommandDelay(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) {
    if (_skipRestoredCommonDelayExecution == context.executionId) {
      _skipRestoredCommonDelayExecution = null;
      return Future.value();
    }
    return _wait(
      command.delayUs / 1000000 / speed,
      context,
      scaled: false,
      commonCommandDelay: true,
    );
  }

  StoryDispatchOperation _dispatch(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) {
    if (const {3, 30}.contains(command.opcode)) {
      _observeCommand({
        'phase': 'enter',
        'executionId': context.executionId,
        'commandIndex': command.index,
        'opcode': command.opcode,
        'parameters': command.parameters,
        'durationUs': command.durationUs,
        'delayUs': command.delayUs,
      });
    }
    final frameDispatch = handlers.frameDispatch;
    if (command.opcode == 44 && frameDispatch != null && !context.resuming) {
      if (!context.isCurrent() || _disposed) {
        return StoryDispatchOperation(
          completion: Future.error(StateError('story_source_replaced')),
          waitForCompletion: true,
        );
      }
      return frameDispatch(command, context, actualUpdateStamp);
    }
    final restored = context.resuming
        ? (_seekHistory ?? controller.driver.history).firstWhere(
            (record) => record.executionId == context.executionId,
          )
        : null;
    final waiting =
        restored?.waitForCompletion ?? _commandWaitsForHandler(command);
    return _observeOperation(
      command,
      context,
      StoryDispatchOperation(
        completion: _execute(command, context),
        waitForCompletion: waiting,
      ),
    );
  }

  bool _commandWaitsForHandler(StoryDecodedCommand command) {
    final policy = storyWaitingPolicy(
      command,
      videoPlaying: media.cues.any(
        (cue) => cue.kind == StoryMediaKind.movie && cue.player.state.playing,
      ),
      autoPlayback: autoPlayback,
    );
    return const {2, 3, 29}.contains(command.opcode) ||
        policy?.alwaysAwaitHandler == true ||
        (!command.noWait && command.opcode != 31 && command.opcode != 15);
  }

  Future<StoryDispatchCompletion> _execute(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) async {
    if (!context.isCurrent() || _disposed) {
      throw StateError('story_source_replaced');
    }
    if (!_seekReplaying && _initialMediaPrepared) {
      media.prepareForCommand(command.index);
    }
    final resuming = context.resuming;
    if (resuming && !_restoredPendingExecutions.remove(context.executionId)) {
      throw StateError('story_restored_execution:${context.executionId}');
    }
    final resumeText = resumeRestoredText;
    if (resuming &&
        resumeText != null &&
        const {2, 28, 29, 36, 37, 38, 39, 52, 65}.contains(command.opcode)) {
      var state = _dialogueWaits[context.executionId];
      if (state == null) {
        // Older saves lack a dialogue phase. Rebuild the current input policy
        // once; their untyped Auto timer must not precede a second full wait.
        _restoredWaiters.remove(context.executionId);
        state = _dialogueState(command, context);
        state.phase = command.opcode == 52
            ? StoryDialogueWaitPhase.voice
            : command.opcode == 29
            ? StoryDialogueWaitPhase.manualNext
            : StoryDialogueWaitPhase.reveal;
      } else if (state.phase == StoryDialogueWaitPhase.preparing) {
        await waitRestoredExecutionTiming(context.executionId);
        if (!context.isCurrent()) throw const VegaSeekCancelled();
        state.phase = command.opcode == 52
            ? StoryDialogueWaitPhase.voice
            : StoryDialogueWaitPhase.reveal;
        state.capturedSpeed = speed;
      }
      if (state.phase == StoryDialogueWaitPhase.done) {
        _forgetDialogue(context, state);
        return const StoryDispatchCompletion();
      }
      final voices = media.cues
          .where(
            (cue) =>
                cue.kind == StoryMediaKind.voice &&
                command.voiceIds.contains(cue.id),
          )
          .toList();
      final scope = _voiceScope;
      try {
        if (command.opcode == 52) {
          await _voiceDialogue(
            command,
            context,
            voices,
            resumeText: () => resumeText(command, context),
          );
        } else {
          final session = await resumeText(command, context);
          if (command.opcode == 29) {
            await _subtitleNext(command, context, restoredSession: session);
          } else {
            await _textTalk(command, context, voices, restoredSession: session);
          }
        }
      } catch (_) {
        if (command.opcode != 52 ||
            (scope == _voiceScope && context.isCurrent())) {
          rethrow;
        }
      } finally {
        if (context.isCurrent() &&
            scope == _voiceScope &&
            (command.opcode == 52 ||
                (command.opcode == 28 && !command.noWait))) {
          await media.stopKind(StoryMediaKind.voice);
        }
        _forgetDialogue(context, state);
      }
      return const StoryDispatchCompletion();
    }
    final resumeCommand = resumeRestoredCommand;
    if (resuming && resumeCommand != null) {
      final commonDelay =
          _restoredWaiters[context.executionId]?.any(
            (waiter) => waiter.commonDelay,
          ) ??
          false;
      await waitRestoredExecutionTiming(context.executionId);
      if (!context.isCurrent()) throw const VegaSeekCancelled();
      if (command.opcode == 26 || command.opcode == 27) {
        return _resumeRestoredVideo(command, context, resumeCommand);
      }
      if (commonDelay) {
        _skipRestoredCommonDelayExecution = context.executionId;
        return _execute(
          command,
          StoryDispatchContext(
            executionId: context.executionId,
            inputs: context.inputs,
            isCurrent: context.isCurrent,
          ),
        );
      }
      if (const {3, 15, 16, 31}.contains(command.opcode)) {
        return const StoryDispatchCompletion();
      }
      return resumeCommand(command, context);
    }
    switch (command.opcode) {
      case 3:
        await _delay(command.durationUs / 1000000, context);
        break;
      case 15:
        await _bgm(command, context);
        break;
      case 16:
        await _soundVolume(command, context);
        break;
      case 31:
        await _sfx(command, context);
        break;
      case 2:
      case 28:
        await _talk(command, context);
        break;
      case 36:
        await handlers.visual(command, context);
        await _chatDialogue(command, context);
        break;
      case 37:
      case 38:
      case 39:
      case 65:
        await _chatDialogue(command, context);
        break;
      case 52:
        await _voice(command, context);
        break;
      case 26:
      case 27:
        await _video(command, context);
        break;
      case 29:
        await _subtitleNext(command, context);
        break;
      case 56:
        _forceAuto = !_forceAuto;
        _autoToken++;
        _autoChanged.complete();
        _autoChanged = Completer<void>();
        notifyListeners();
        break;
      case 59:
        handlers.cancelFrameDelay?.call();
        for (final waiter in _waiters) {
          if (waiter.commonCommandDelay) {
            waiter.atUs = storyUs;
            waiter.update = _updates + 1;
          }
        }
        break;
      case 41:
        final next = await handlers.choice(command, context);
        return StoryDispatchCompletion(nextCommandIndex: next);
      case 7:
      case 33:
      case 34:
      case 67:
      case 47:
      case 48:
      case 50:
      case 53:
        await waitCommonCommandDelay(command, context);
        await handlers.visual(command, context);
        break;
      case 44:
        await handlers.framePrepare(command, context);
        await waitCommonCommandDelay(command, context);
        await handlers.visual(command, context);
        break;
      case 42:
        return StoryDispatchCompletion(
          nextCommandIndex: handlers.goto(command),
        );
      default:
        await handlers.visual(command, context);
    }
    return const StoryDispatchCompletion();
  }

  Future<NativeStoryMediaCue?> _cue(
    StoryDecodedCommand command,
    StoryDispatchContext context,
    StoryMediaKind kind,
    String id, {
    String? reference,
    bool looping = false,
    int? positionUs,
    double initialGain = 1,
    bool retainPreviousBgm = false,
  }) async {
    if (!context.isCurrent()) return null;
    final ref = reference ?? document.assets.referenceFor(kind, id);
    final record = document.assets.mediaRecord(ref, kind);
    final volume = (record['raw'] as Map?)?['_volume'];
    final sourceVolume = volume is num ? volume.toDouble() : 1.0;
    final sampleRate = record['sampleRate'] as num?;
    int? sampleTime(Object? samples, Object? milliseconds) =>
        samples is num && sampleRate != null && sampleRate > 0
        ? (samples * 1000000 / sampleRate).round()
        : milliseconds is num
        ? (milliseconds * 1000).round()
        : null;
    final duration = sampleTime(record['totalSamples'], record['durationMs']);
    final loopInfo = record['loopInfo'] as Map?;
    final sourceLoop = loopInfo?['isLoop'] as bool?;
    final cue = await media.dispatch(
      StoryMediaEvent(
        kind: kind,
        cueId: id,
        commandIndex: command.index,
        atUs: storyUs,
        resourceRef: ref,
        positionUs: positionUs,
      ),
      looping: sourceLoop ?? looping,
      durationUs: duration,
      loopStartUs:
          sampleTime(loopInfo?['loopStartSample'], loopInfo?['loopStartMs']) ??
          0,
      loopEndUs: sampleTime(loopInfo?['loopEndSample'], loopInfo?['loopEndMs']),
      playbackRate: kind == StoryMediaKind.voice || kind == StoryMediaKind.movie
          ? speed
          : 1,
      volume:
          100 *
          _userGain(kind) *
          _categoryVolumes[kind]! *
          sourceVolume *
          initialGain,
      retainPreviousBgm: retainPreviousBgm,
      play: !_seekReplaying,
    );
    if (!context.isCurrent() && cue != null) {
      await media.releaseCue(cue);
      return null;
    }
    if (cue != null) {
      _sourceVolumes[cue] = sourceVolume;
      _cueGains[cue] = initialGain;
    }
    if (kind == StoryMediaKind.bgm || kind == StoryMediaKind.sfx) {
      _audioStartedUpdate = _updates;
    }
    return cue;
  }

  Future<void> _bgm(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) async {
    final fade = command.numericParameter(0) ?? 0;
    final old = media.cues
        .where((cue) => cue.kind == StoryMediaKind.bgm)
        .toList();
    if (int.parse(command.bgmId) < 1) {
      await Future.wait([
        for (final cue in old) _fadeAndRelease(cue, fade, context),
      ]);
      return;
    }
    final offset = ((command.numericParameter(1) ?? 0) * 1000000).round();
    final cue = await _cue(
      command,
      context,
      StoryMediaKind.bgm,
      command.bgmId,
      reference: command.resourceRefs['bgmRef'],
      looping: true,
      positionUs: offset,
      initialGain: fade > 0 ? 0 : 1,
      retainPreviousBgm: fade > 0,
    );
    if (!context.isCurrent()) return;
    if (cue != null && fade > 0) {
      unawaited(_fadeCue(cue, 1, fade, context));
      for (final previous in old) {
        unawaited(_fadeAndRelease(previous, fade, context));
      }
    }
    if (cue != null && command.durationUs > 0) {
      _scheduledStops[cue] = _ScheduledCueStop(
        storyUs + command.durationUs,
        command.numericParameter(2) ?? 0,
        false,
        context.executionId,
      );
    }
  }

  Future<void> _sfx(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) async {
    await waitCommonCommandDelay(command, context);
    if (!context.isCurrent() || _disposed) {
      throw StateError('story_source_replaced');
    }
    if ((command.parameter(0) ?? '').trim().toLowerCase() == 'stop') {
      final old = media.cues
          .where(
            (cue) =>
                cue.kind == StoryMediaKind.sfx &&
                (int.parse(command.seId) < 1 || cue.id == command.seId),
          )
          .toList();
      await Future.wait([
        for (final cue in old)
          _fadeAndRelease(cue, command.numericParameter(1) ?? 0, context),
      ]);
      return;
    }
    final cue = await _cue(
      command,
      context,
      StoryMediaKind.sfx,
      command.seId,
      reference: command.resourceRefs['seRef'],
      initialGain: (command.numericParameter(2) ?? 0) > 0 ? 0 : 1,
    );
    if (!context.isCurrent()) return;
    if (cue != null && (command.numericParameter(2) ?? 0) > 0) {
      unawaited(_fadeCue(cue, 1, command.numericParameter(2)!, context));
    }
    if (cue != null && command.durationUs > 0) {
      _scheduledStops[cue] = _ScheduledCueStop(
        storyUs + (command.durationUs / speed).round(),
        command.numericParameter(1) ?? 0,
        true,
        context.executionId,
      );
    }
  }

  Future<List<NativeStoryMediaCue>> _voices(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) async {
    final scope = ++_voiceScope;
    final old = media.cues
        .where((cue) => cue.kind == StoryMediaKind.voice)
        .toList();
    await media.stopKind(StoryMediaKind.voice);
    if (scope != _voiceScope || !context.isCurrent()) return const [];
    for (final cue in old) {
      _sourceVolumes.remove(cue);
      _cueGains.remove(cue);
    }
    if (!voiceEnabled || scope != _voiceScope || !context.isCurrent()) {
      return const [];
    }
    if (_updates == _audioStartedUpdate) await _wait(0, context, updates: 2);
    final cues = <NativeStoryMediaCue>[];
    for (final (index, id) in command.voiceIds.indexed) {
      if (scope != _voiceScope || !context.isCurrent()) break;
      final cue = await _cue(
        command,
        context,
        StoryMediaKind.voice,
        id,
        reference: index < command.voiceRefs.length
            ? command.voiceRefs[index]
            : null,
      );
      if (cue != null) {
        cues.add(cue);
      }
    }
    return cues;
  }

  StoryDialogueWaitState _dialogueState(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) => _dialogueWaits.putIfAbsent(
    context.executionId,
    () => StoryDialogueWaitState(
      commandIndex: command.index,
      opcode: command.opcode,
      automatic: autoPlayback,
      capturedSpeed: speed,
    ),
  );

  void _forgetDialogue(
    StoryDispatchContext context,
    StoryDialogueWaitState state,
  ) {
    if (context.isCurrent() &&
        identical(_dialogueWaits[context.executionId], state)) {
      _dialogueWaits.remove(context.executionId);
    }
  }

  void _resetDialogueAuto(
    StoryDialogueWaitState state,
    int executionId, {
    StoryDialogueWaitPhase phase = StoryDialogueWaitPhase.reveal,
  }) {
    _restoredWaiters.remove(executionId);
    state
      ..phase = phase
      ..automatic = autoPlayback
      ..capturedSpeed = speed
      ..autoStartedUs = 0
      ..timerPhase = null
      ..timerDeadlineUs = null;
  }

  Future<void> _dialogueAwait(
    Future<void> work,
    StoryDispatchContext context, {
    int? token,
  }) async {
    if (token != null && token != _autoToken) {
      throw StateError('story_auto_changed');
    }
    if (token == null) {
      await work;
    } else {
      await Future.any<void>([
        work,
        _autoChanged.future.then<void>(
          (_) => throw StateError('story_auto_changed'),
        ),
      ]);
    }
    if (!context.isCurrent()) throw const VegaSeekCancelled();
    if (token != null && token != _autoToken) {
      throw StateError('story_auto_changed');
    }
  }

  Future<void> _dialogueTimer(
    double seconds,
    StoryDispatchContext context, {
    required int token,
    bool durationAlreadyScaled = false,
    int updates = 0,
  }) {
    bool currentAuto() => token == _autoToken && autoPlayback;
    final state = _dialogueWaits[context.executionId]!;
    if (state.timerPhase != state.phase) {
      state
        ..timerPhase = state.phase
        ..timerDeadlineUs = null;
    }
    final existingDeadline = state.timerDeadlineUs;
    state.timerDeadlineUs ??=
        storyUs +
        (mathMax(0, seconds) * 1000000 / (durationAlreadyScaled ? 1 : speed))
            .round();
    final saved = _restoredWaiters[context.executionId];
    if (saved != null && saved.isNotEmpty) {
      state.timerDeadlineUs = saved
          .map((value) => value.atUs)
          .reduce((a, b) => a > b ? a : b);
    }
    final work = saved != null
        ? waitRestoredExecutionTiming(
            context.executionId,
            additionalCurrent: currentAuto,
          )
        : _wait(
            existingDeadline == null
                ? seconds
                : mathMax(0, existingDeadline - storyUs.toDouble()) / 1000000,
            context,
            durationAlreadyScaled:
                existingDeadline != null || durationAlreadyScaled,
            updates: existingDeadline == null ? updates : 0,
            additionalCurrent: currentAuto,
          );
    return _dialogueAwait(work, context, token: token);
  }

  Future<void> _talk(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) async {
    if (command.opcode == 2 &&
        handlers.onTalkBegin?.call(command, context) == false) {
      return;
    }
    if (command.opcode == 28) {
      final id = command.payload['advTextId'];
      if (id is! String || id.isEmpty || id == '0') {
        await handlers.text(command, context);
        return;
      }
    }
    final state = _dialogueState(command, context);
    int? scope;
    try {
      final episodeVoices =
          command.opcode == 28 && (!voiceEnabled || command.voiceIds.isEmpty)
          ? const <NativeStoryMediaCue>[]
          : await _voices(command, context);
      if (!context.isCurrent()) return;
      scope = _voiceScope;
      state
        ..phase = StoryDialogueWaitPhase.reveal
        ..capturedSpeed = speed;
      await _textTalk(command, context, episodeVoices);
    } finally {
      if (command.opcode == 28 &&
          !command.noWait &&
          scope == _voiceScope &&
          context.isCurrent()) {
        final currentVoices = media.cues
            .where((cue) => cue.kind == StoryMediaKind.voice)
            .toList();
        for (final cue in currentVoices) {
          _sourceVolumes.remove(cue);
          _cueGains.remove(cue);
        }
        await media.stopKind(StoryMediaKind.voice);
      }
      _forgetDialogue(context, state);
    }
  }

  Future<void> _chatDialogue(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) async {
    final state = _dialogueState(command, context);
    try {
      final session = await handlers.text(command, context);
      if (!context.isCurrent()) return;
      final voices = command.opcode == 37 && !session.skipAdvance
          ? await _voices(command, context)
          : const <NativeStoryMediaCue>[];
      if (!context.isCurrent()) return;
      state
        ..phase = StoryDialogueWaitPhase.reveal
        ..capturedSpeed = speed;
      await _textTalk(command, context, voices, restoredSession: session);
    } finally {
      _forgetDialogue(context, state);
    }
  }

  Future<void> playChatSound(
    String id,
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) async {
    if (voiceShortcut || id == '0') return;
    await _cue(command, context, StoryMediaKind.sfx, id);
  }

  Future<void> _textTalk(
    StoryDecodedCommand command,
    StoryDispatchContext context,
    List<NativeStoryMediaCue> episodeVoices, {
    NativeStoryTextSession? restoredSession,
  }) async {
    final voices = const {2, 37}.contains(command.opcode)
        ? episodeVoices
        : const <NativeStoryMediaCue>[];
    final text = restoredSession ?? await handlers.text(command, context);
    if (!context.isCurrent()) return;
    if (text.skipAdvance ||
        (command.noWait &&
            const {36, 37, 38, 39, 65}.contains(command.opcode))) {
      await text.fullyRevealed;
      return;
    }
    if (command.opcode == 28 && command.noWait) return;
    final state = _dialogueState(command, context);
    if (state.phase == StoryDialogueWaitPhase.done) return;
    NativeStoryMediaCue? movie;
    if (command.opcode == 28) {
      for (final cue in media.cues.where(
        (c) => c.kind == StoryMediaKind.movie,
      )) {
        if (await cue.videoPlayingOrSeekRespeeding()) {
          movie = cue;
          break;
        }
      }
      if (!context.isCurrent() || _disposed) return;
    }
    final subtitleMovie =
        command.opcode == 28 &&
        (movie != null ||
            const {
              StoryDialogueWaitPhase.subtitleMovie,
              StoryDialogueWaitPhase.subtitleNext,
              StoryDialogueWaitPhase.subtitleLingering,
            }.contains(state.phase));
    if (subtitleMovie) {
      if (state.phase == StoryDialogueWaitPhase.reveal ||
          state.phase == StoryDialogueWaitPhase.preparing) {
        state.phase = StoryDialogueWaitPhase.subtitleMovie;
      }
      if (state.phase == StoryDialogueWaitPhase.subtitleMovie) {
        await _dialogueAwait(
          Future.any([text.firstTap, movie?.completed ?? Future<void>.value()]),
          context,
        );
        final playing =
            movie != null && await movie.videoPlayingOrSeekRespeeding();
        if (!context.isCurrent()) return;
        state.phase = playing || !autoPlayback
            ? StoryDialogueWaitPhase.subtitleNext
            : StoryDialogueWaitPhase.subtitleLingering;
        state.automatic = autoPlayback;
      }
      if (state.phase == StoryDialogueWaitPhase.subtitleNext) {
        await _dialogueAwait(text.nextStep, context);
        acknowledge(command.index);
        state
          ..phase = StoryDialogueWaitPhase.subtitleLingering
          ..automatic = autoPlayback;
      }
      if (state.phase == StoryDialogueWaitPhase.subtitleLingering &&
          autoPlayback &&
          state.automatic) {
        final token = _autoToken;
        try {
          await _dialogueTimer(
            runtimeNumber('waitSubtitlesLingeringTimeOnAutoPlay'),
            context,
            token: token,
          );
        } catch (_) {
          if (!context.isCurrent() || token == _autoToken) rethrow;
          _restoredWaiters.remove(context.executionId);
        }
      } else {
        _restoredWaiters.remove(context.executionId);
      }
      state.phase = StoryDialogueWaitPhase.done;
      return;
    }
    if (command.opcode == 28) handlers.subtitleNext?.call(true, context);
    while (context.isCurrent() && !_disposed) {
      if (state.automatic != autoPlayback) {
        _resetDialogueAuto(state, context.executionId);
      }
      final token = _autoToken;
      try {
        if (autoPlayback) {
          switch (state.phase) {
            case StoryDialogueWaitPhase.preparing:
            case StoryDialogueWaitPhase.reveal:
              await _dialogueAwait(text.fullyRevealed, context, token: token);
              state.phase = StoryDialogueWaitPhase.nextUpdate;
            case StoryDialogueWaitPhase.nextUpdate:
              await _dialogueTimer(0, context, token: token, updates: 1);
              state.autoStartedUs = storyUs;
              state.phase = voices.isNotEmpty
                  ? StoryDialogueWaitPhase.voice
                  : StoryDialogueWaitPhase.textDelay;
            case StoryDialogueWaitPhase.voice:
              await _dialogueAwait(
                Future.wait([for (final cue in voices) cue.completed]),
                context,
                token: token,
              );
              state.phase = StoryDialogueWaitPhase.postVoice;
            case StoryDialogueWaitPhase.postVoice:
              await _dialogueTimer(
                waitAfterVoiceSeconds / state.capturedSpeed,
                context,
                token: token,
                durationAlreadyScaled: true,
              );
              state.phase = StoryDialogueWaitPhase.minimumDisplay;
            case StoryDialogueWaitPhase.textDelay:
              await _dialogueTimer(
                waitTextUnitSeconds * text.renderedLength / state.capturedSpeed,
                context,
                token: token,
                durationAlreadyScaled: true,
              );
              state.phase = StoryDialogueWaitPhase.minimumDisplay;
            case StoryDialogueWaitPhase.minimumDisplay:
              final remaining =
                  minTalkDisplaySeconds / state.capturedSpeed -
                  (storyUs - state.autoStartedUs) / 1000000;
              if (remaining > 0 ||
                  _restoredWaiters.containsKey(context.executionId)) {
                await _dialogueTimer(
                  remaining,
                  context,
                  token: token,
                  durationAlreadyScaled: true,
                );
              }
              state.phase = StoryDialogueWaitPhase.autoDelay;
            case StoryDialogueWaitPhase.autoDelay:
              await _dialogueTimer(
                autoDelaySeconds,
                context,
                token: token,
                durationAlreadyScaled: true,
              );
              state.phase = StoryDialogueWaitPhase.done;
            case StoryDialogueWaitPhase.done:
              if (command.opcode == 28) {
                handlers.subtitleNext?.call(false, context);
              }
              return;
            default:
              _resetDialogueAuto(state, context.executionId);
          }
        } else {
          if (state.phase == StoryDialogueWaitPhase.done) return;
          if (state.phase != StoryDialogueWaitPhase.manualNext) {
            await _dialogueAwait(text.fullyRevealed, context, token: token);
            state.phase = StoryDialogueWaitPhase.manualNext;
          }
          await _dialogueAwait(text.nextStep, context, token: token);
          acknowledge(command.index);
          state.phase = StoryDialogueWaitPhase.done;
          if (command.opcode == 28) handlers.subtitleNext?.call(false, context);
          return;
        }
      } catch (_) {
        if (!context.isCurrent() || _disposed || token == _autoToken) rethrow;
        _resetDialogueAuto(state, context.executionId);
      }
    }
  }

  Future<void> _subtitleNext(
    StoryDecodedCommand command,
    StoryDispatchContext context, {
    NativeStoryTextSession? restoredSession,
  }) async {
    final state = _dialogueState(command, context);
    try {
      final text = restoredSession ?? await handlers.text(command, context);
      if (!context.isCurrent()) return;
      if (state.phase == StoryDialogueWaitPhase.preparing ||
          state.phase == StoryDialogueWaitPhase.reveal) {
        state.phase = StoryDialogueWaitPhase.manualNext;
      }
      if (state.phase == StoryDialogueWaitPhase.manualNext) {
        await _dialogueAwait(text.nextStep, context);
        acknowledge(command.index);
        state
          ..phase = StoryDialogueWaitPhase.subtitleLingering
          ..automatic = autoPlayback;
      }
      if (state.phase == StoryDialogueWaitPhase.subtitleLingering &&
          autoPlayback &&
          state.automatic) {
        final token = _autoToken;
        try {
          await _dialogueTimer(
            runtimeNumber('waitCommandLingeringTimeOnAutoPlay'),
            context,
            token: token,
          );
        } catch (_) {
          if (!context.isCurrent() || token == _autoToken) rethrow;
          _restoredWaiters.remove(context.executionId);
        }
      } else {
        _restoredWaiters.remove(context.executionId);
      }
      state.phase = StoryDialogueWaitPhase.done;
    } finally {
      _forgetDialogue(context, state);
    }
  }

  Future<void> _voiceDialogue(
    StoryDecodedCommand command,
    StoryDispatchContext context,
    List<NativeStoryMediaCue> voices, {
    Future<NativeStoryTextSession> Function()? resumeText,
  }) async {
    final state = _dialogueState(command, context);
    NativeStoryTextSession? text;
    if (state.phase == StoryDialogueWaitPhase.preparing) {
      state.phase = StoryDialogueWaitPhase.voice;
    }
    while (context.isCurrent() && !_disposed) {
      if (state.phase == StoryDialogueWaitPhase.done) return;
      if (state.phase == StoryDialogueWaitPhase.voice) {
        await _dialogueAwait(
          Future.wait([for (final cue in voices) cue.completed]),
          context,
        );
        state
          ..phase = autoPlayback
              ? StoryDialogueWaitPhase.postVoice
              : StoryDialogueWaitPhase.manualNext
          ..automatic = autoPlayback;
      }
      if (state.automatic != autoPlayback) {
        _resetDialogueAuto(
          state,
          context.executionId,
          phase: autoPlayback
              ? StoryDialogueWaitPhase.postVoice
              : StoryDialogueWaitPhase.manualNext,
        );
      }
      final token = _autoToken;
      try {
        if (state.phase == StoryDialogueWaitPhase.postVoice) {
          await _dialogueTimer(waitAfterVoiceSeconds, context, token: token);
          state.phase = StoryDialogueWaitPhase.done;
        } else if (state.phase == StoryDialogueWaitPhase.manualNext) {
          text ??=
              await (resumeText?.call() ?? handlers.text(command, context));
          if (!context.isCurrent()) return;
          await _dialogueAwait(text.nextStep, context, token: token);
          acknowledge(command.index);
          state.phase = StoryDialogueWaitPhase.done;
        }
        if (state.phase == StoryDialogueWaitPhase.done) return;
      } catch (_) {
        if (!context.isCurrent() || _disposed || token == _autoToken) rethrow;
      }
    }
  }

  Future<void> _voice(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) async {
    if (!voiceEnabled) return;
    final state = _dialogueState(command, context);
    int? scope;
    try {
      final voices = await _voices(command, context);
      if (!context.isCurrent()) return;
      scope = _voiceScope;
      state.phase = StoryDialogueWaitPhase.voice;
      await _voiceDialogue(command, context, voices);
    } catch (_) {
      if ((scope == null || scope == _voiceScope) && context.isCurrent()) {
        rethrow;
      }
    } finally {
      if (scope == _voiceScope && context.isCurrent()) {
        await media.stopKind(StoryMediaKind.voice);
      }
      _forgetDialogue(context, state);
    }
  }

  Future<void> _video(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) async {
    _moviePhases[context.executionId] = 0;
    handlers.videoUi?.call(command, context);
    final policy = storyWaitingPolicy(
      command,
      videoPlaying: media.cues.any(
        (c) => c.kind == StoryMediaKind.movie && c.player.state.playing,
      ),
      autoPlayback: autoPlayback,
    )!;
    if (command.videoId == '0') {
      _clip = null;
      await handlers.movieFade(0, policy.fadeOutSeconds / speed, context);
      if (!context.isCurrent()) return;
      await media.stopKind(StoryMediaKind.movie);
      return;
    }
    final cue = await _cue(
      command,
      context,
      StoryMediaKind.movie,
      command.videoId,
      reference: command.resourceRefs['videoRef'],
    );
    if (cue == null) return;
    _movieCues[context.executionId] = cue;
    await cue.firstVideoFrame();
    if (!context.isCurrent()) return;
    if (policy.videoOperation == StoryVideoOperation.clipStart) {
      final clock = await cue.videoClock();
      if (!context.isCurrent()) return;
      _clip = clock == null ? null : cue;
      if (clock != null) _clipStartUs = clock.positionUs;
      _clipElapsedUs = _clipTargetUs = 0;
      _clipSkipped = false;
    } else {
      _clip = null;
    }
    _moviePhases[context.executionId] = 1;
    await handlers.movieFade(
      policy.alpha,
      policy.fadeInSeconds / speed,
      context,
    );
    if (!context.isCurrent()) return;
    _moviePhases[context.executionId] = 2;
    if (policy.videoOperation == StoryVideoOperation.movie) {
      await cue.completed;
      if (!context.isCurrent()) return;
      _moviePhases[context.executionId] = 3;
      await handlers.movieFade(0, policy.fadeOutSeconds / speed, context);
      if (!context.isCurrent()) return;
      await media.stopKind(StoryMediaKind.movie, cueIds: {cue.id});
    }
    if (context.isCurrent()) {
      _moviePhases.remove(context.executionId);
      _movieCues.remove(context.executionId);
    }
  }

  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _disposed = true;
    ++_transportIntent;
    _wantsPlayback = false;
    _focus.close();
    _autoToken++;
    _autoChanged.complete();
    _generation++;
    _voiceScope++;
    _clock.stop();
    _updated.complete();
    controller.dispose();
    for (final waiter in _waiters) {
      waiter.completion.completeError(StateError('story_source_closed'));
    }
    _waiters.clear();
    for (final fade in _gainFades) {
      if (!fade.completed.isCompleted) fade.completed.complete();
    }
    _gainFades.clear();
    for (final fade in _categoryFades.values) {
      if (!fade.completed.isCompleted) fade.completed.complete();
    }
    _categoryFades.clear();
    _cueGains.clear();
    _sourceVolumes.clear();
    _scheduledStops.clear();
    _dialogueWaits.clear();
    await media.close();
    MediaLifecycle.unregister(this);
    super.dispose();
  }

  Future<void> _fadeCue(
    NativeStoryMediaCue cue,
    double gain,
    double seconds,
    StoryDispatchContext context, {
    bool releaseWhenComplete = false,
  }) async {
    if (!context.isCurrent()) return;
    final old = _gainFades.where((fade) => identical(fade.cue, cue)).toList();
    for (final fade in old) {
      _gainFades.remove(fade);
      fade.completed.complete();
    }
    if (seconds <= 0) {
      _cueGains[cue] = gain;
      await _applyVolume(cue);
      return;
    }
    final fade = _CueGainFade(
      cue,
      _cueGains[cue] ?? 1,
      gain,
      storyUs,
      (seconds * 1000000).round(),
      context.isCurrent,
      releaseWhenComplete: releaseWhenComplete,
      commandIndex: _commandIndexForExecution(context.executionId),
      executionId: context.executionId,
    );
    _gainFades.add(fade);
    await fade.completed.future;
  }

  Future<void> _fadeAndRelease(
    NativeStoryMediaCue cue,
    double seconds,
    StoryDispatchContext context,
  ) async {
    await _fadeCue(cue, 0, seconds, context, releaseWhenComplete: true);
    if (!context.isCurrent()) return;
    _cueGains.remove(cue);
    _sourceVolumes.remove(cue);
    await media.releaseCue(cue);
  }

  double _cueVolume(NativeStoryMediaCue cue) =>
      100 *
      _userGain(cue.kind) *
      _categoryVolumes[cue.kind]! *
      (_sourceVolumes[cue] ?? 1) *
      (_cueGains[cue] ?? 1);

  Future<void> _applyVolume(NativeStoryMediaCue cue) =>
      _seekReplaying ? Future.value() : cue.setVolume(_cueVolume(cue));
  Future<void> _updateVolumes(int now) async {
    if (_updatingVolumes || _disposed) return;
    _updatingVolumes = true;
    try {
      for (final entry in _scheduledStops.entries.toList()) {
        final cue = entry.key, stop = entry.value;
        if (!media.cues.contains(cue)) {
          _scheduledStops.remove(cue);
          continue;
        }
        if (stop.atUs > now) continue;
        _scheduledStops.remove(cue);
        final generation = _generation;
        final context = StoryDispatchContext(
          executionId: stop.executionId,
          inputs: _inputs(),
          isCurrent: () => !_disposed && generation == _generation,
        );
        final fade = stop.fadeSeconds / (stop.scaleFadeBySpeed ? speed : 1);
        final Future<void> work;
        if (fade <= 0) {
          _cueGains.remove(cue);
          _sourceVolumes.remove(cue);
          work = media.releaseCue(cue);
        } else {
          work = _fadeAndRelease(cue, fade, context);
        }
        unawaited(
          work.catchError((Object failure, StackTrace stack) {
            if (!context.isCurrent()) return;
            error = failure;
            errorStackTrace = stack;
            paused = true;
            _wantsPlayback = false;
            ++_transportIntent;
            _clock.stop();
            unawaited(media.pause());
            notifyListeners();
          }),
        );
      }
      final changed = <NativeStoryMediaCue>{};
      final finishing = <_CueGainFade>[];
      for (final fade in _gainFades.toList()) {
        if (!fade.current() || !media.cues.contains(fade.cue)) {
          _gainFades.remove(fade);
          fade.completed.complete();
          continue;
        }
        final t = ((now - fade.startUs) / fade.durationUs).clamp(0.0, 1.0);
        _cueGains[fade.cue] = fade.from + (fade.to - fade.from) * t;
        changed.add(fade.cue);
        if (t >= 1) finishing.add(fade);
      }
      final endingCategories = <_CategoryVolumeFade>[];
      for (final fade in _categoryFades.values.toList()) {
        if (!fade.current()) {
          _categoryFades.remove(fade.name);
          fade.completed.complete();
          continue;
        }
        final t = ((now - fade.startUs) / fade.durationUs).clamp(0.0, 1.0);
        final value = _float32(
          _namedDefaults[fade.name]! *
              _float32(fade.from + (fade.to - fade.from) * t),
        );
        _namedVolumes[fade.name] = value;
        final kind = _categoryKind(fade.name);
        if (kind != null) {
          _categoryVolumes[kind] = value;
          changed.addAll(media.cues.where((cue) => cue.kind == kind));
        }
        if (t >= 1) endingCategories.add(fade);
      }
      await Future.wait([for (final cue in changed) _applyVolume(cue)]);
      for (final fade in finishing) {
        if (_gainFades.remove(fade) && !fade.completed.isCompleted) {
          fade.completed.complete();
        }
      }
      for (final fade in endingCategories) {
        if (identical(_categoryFades[fade.name], fade)) {
          _categoryFades.remove(fade.name);
        }
        if (!fade.completed.isCompleted) fade.completed.complete();
      }
    } finally {
      _updatingVolumes = false;
    }
  }

  Future<void> _soundVolume(
    StoryDecodedCommand command,
    StoryDispatchContext context,
  ) async {
    for (final previous in _categoryFades.values) {
      if (!previous.completed.isCompleted) previous.completed.complete();
    }
    _categoryFades.clear();
    final category = command.parameter(0) ?? '';
    final names = category.isEmpty || category.toLowerCase() == 'all'
        ? ['Bgm', 'Voice']
        : category.toLowerCase() == 'se' ||
              !_namedDefaults.containsKey(category)
        ? <String>[]
        : [category];
    final target = command.numericParameter(1) ?? 0;
    final waiting = <Future<void>>[];
    for (final name in names) {
      if (!context.isCurrent()) return;
      final kind = _categoryKind(name);
      final old = _categoryFades.remove(name);
      old?.completed.complete();
      if (command.durationUs <= 0) {
        final value = _float32(_namedDefaults[name]! * _float32(target));
        _namedVolumes[name] = value;
        if (kind != null) _categoryVolumes[kind] = value;
        await Future.wait([
          for (final cue in media.cues.where((c) => c.kind == kind))
            _applyVolume(cue),
        ]);
      } else {
        final fade = _CategoryVolumeFade(
          name,
          _namedVolumes[name]!,
          target,
          storyUs,
          (command.durationUs / speed).round(),
          context.isCurrent,
          commandIndex: command.index,
          executionId: context.executionId,
        );
        _categoryFades[name] = fade;
        waiting.add(fade.completed.future);
      }
    }
    await Future.wait(waiting);
  }
}

final class NativeStoryPlaybackCheckpoint {
  NativeStoryPlaybackCheckpoint._(
    this.sourceIdentity,
    this.sourceEpoch,
    this.atUs,
    this.media,
    this._toData,
    this._restore,
  );
  final StorySourceIdentity sourceIdentity;
  final int sourceEpoch, atUs;
  final NativeStoryMediaSnapshot media;
  final Future<Map<String, Object?>> Function(Future<Uint8List> Function(Uri))
  _toData;
  Future<Map<String, Object?>> toData({
    required Future<Uint8List> Function(Uri) fetch,
  }) => _toData(fetch);
  final void Function() _restore;
}

double mathMax(double a, double b) => a > b ? a : b;
final _scalar32 = Float32List(1);
double _float32(num value) {
  _scalar32[0] = value.toDouble();
  return _scalar32[0];
}

final class _StoryDeadline {
  _StoryDeadline(
    this.atUs,
    this.update,
    this.current,
    this.completion,
    this.scaled,
    this.commonCommandDelay,
    this.executionId,
  );
  int atUs;
  int update;
  final bool scaled;
  final bool commonCommandDelay;
  final int executionId;
  final bool Function() current;
  final Completer<void> completion;
}

final class _RestoredCommandDeadline {
  _RestoredCommandDeadline(
    this.atUs,
    this.remainingUpdates,
    this.scaled,
    this.commonDelay,
  );
  int atUs;
  final int remainingUpdates;
  final bool scaled, commonDelay;
  _RestoredCommandDeadline copy() =>
      _RestoredCommandDeadline(atUs, remainingUpdates, scaled, commonDelay);
}

final class _CueGainFade {
  _CueGainFade(
    this.cue,
    this.from,
    this.to,
    this.startUs,
    this.durationUs,
    this.current, {
    this.releaseWhenComplete = false,
    this.commandIndex = -1,
    this.executionId = -1,
  });
  final NativeStoryMediaCue cue;
  double from;
  final double to;
  int startUs, durationUs;
  final bool Function() current;
  final bool releaseWhenComplete;
  final int commandIndex, executionId;
  final Completer<void> completed = Completer<void>();
}

final class _CategoryVolumeFade {
  _CategoryVolumeFade(
    this.name,
    this.from,
    this.to,
    this.startUs,
    this.durationUs,
    this.current, {
    this.commandIndex = -1,
    this.executionId = -1,
  });
  final String name;
  double from;
  final double to;
  int startUs, durationUs;
  final bool Function() current;
  final int commandIndex, executionId;
  final Completer<void> completed = Completer<void>();
}

/// Source duration belongs to the cue, independently of command admission.
final class _ScheduledCueStop {
  const _ScheduledCueStop(
    this.atUs,
    this.fadeSeconds,
    this.scaleFadeBySpeed,
    this.executionId,
  );
  final int atUs, executionId;
  final double fadeSeconds;
  final bool scaleFadeBySpeed;
}
