import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:vega_plugin_haneoka/render_profile.dart';
import 'package:vega_runtime_ffi/vega_runtime_ffi.dart';

import 'native_story_playback.dart';
import 'native_story_world.dart';

final class NativeStorySeekCallbacks<T> {
  const NativeStorySeekCallbacks({
    required this.captureUi,
    required this.restoreUi,
    required this.quiesceUi,
    required this.settleUi,
    required this.present,
    required this.replayText,
    required this.advanceUi,
    this.resumeText,
    this.resumeCommand,
    this.uiDeadline,
    this.captureUiData,
    this.restoreUiData,
    this.preparationBarrier,
  });
  final FutureOr<T> Function() captureUi;
  final String? Function(StoryDecodedCommand command)? preparationBarrier;
  final Future<void> Function(T, VegaSeekContext) restoreUi;
  final Future<void> Function(VegaSeekContext) quiesceUi, settleUi;
  final Future<void> Function(NativeStoryUpdateStamp, VegaSeekContext) present;
  final Future<void> Function(StoryDecodedCommand, StoryDispatchContext)
  replayText;
  final FutureOr<void> Function(NativeStoryUpdateStamp, VegaSeekContext)
  advanceUi;
  final Future<NativeStoryTextSession> Function(
    StoryDecodedCommand,
    StoryDispatchContext,
  )?
  resumeText;
  final Future<StoryDispatchCompletion> Function(
    StoryDecodedCommand,
    StoryDispatchContext,
  )?
  resumeCommand;

  final FutureOr<Map<String, Object?>> Function(T)? captureUiData;
  final Future<void> Function(Map<String, Object?>, VegaSeekContext)?
  restoreUiData;

  /// Pending finite command operations only; persistent indicator loops have
  /// no completion boundary for seek.
  final int? Function(NativeStoryUpdateStamp)? uiDeadline;
}

final class NativeStorySeekSnapshot<T> {
  const NativeStorySeekSnapshot({
    required this.world,
    required this.playback,
    required this.ui,
    required this.runtimeHash,
    required this.decisions,
    this.portableData,
    this.portableExecutionHistory,
  });
  final NativeStoryWorldCheckpoint world;
  final NativeStoryPlaybackCheckpoint playback;
  final T ui;
  final String runtimeHash;
  final Map<int, int?> decisions;
  final Map<String, Object?>? portableData;
  final List<VegaExecutionRecord>? portableExecutionHistory;

  NativeStorySeekSnapshot<T> withDecisions(Map<int, int?> values) =>
      NativeStorySeekSnapshot(
        world: world,
        playback: playback,
        ui: ui,
        runtimeHash: runtimeHash,
        decisions: Map.unmodifiable(values),
        portableData: portableData,
        portableExecutionHistory: portableExecutionHistory,
      );
}

/// The Screen supplies real UI state and frame acknowledgement; the facade
/// owns source replay, resources, media and the renderer-neutral seek gate.
final class NativeStorySeekFacade<T>
    implements VegaNarrativeSeekHost<NativeStorySeekSnapshot<T>> {
  NativeStorySeekFacade({
    required this.player,
    required this.world,
    required this.callbacks,
  }) {
    if (player.document.chapter.sourceIdentity !=
            world.document.chapter.sourceIdentity ||
        player.sourceEpoch != world.epoch) {
      throw const FormatException('story_seek_host_source');
    }
    coordinator = VegaNarrativeSeekCoordinator(
      driver: player.checkpointDriver,
      host: this,
    );
    player.resumeRestoredText = callbacks.resumeText;
    player.resumeRestoredCommand = callbacks.resumeCommand;
  }
  final NativeStoryPlayback player;
  final NativeStoryWorld world;
  final NativeStorySeekCallbacks<T> callbacks;
  late final VegaNarrativeSeekCoordinator<NativeStorySeekSnapshot<T>>
  coordinator;
  final _decisions = <int, int?>{};
  final _paths = <String, Map<int, int?>>{};
  VegaNarrativeCheckpoint<NativeStorySeekSnapshot<T>>? _anchor;
  T? _quiescedUi;
  NativeStoryPlaybackCheckpoint? _quiescedPlayback;
  bool _hasQuiescedUi = false, _disposed = false;
  bool get seeking => coordinator.seeking;
  final _preparationUs = <String, int>{};
  final _preparationCalls = <String, int>{};
  Map<String, Object?>? _beforeCache;
  Map<String, Object?> get preparationObservation => {
    'microseconds': Map.of(_preparationUs),
    'calls': Map.of(_preparationCalls),
    'cacheBefore': _beforeCache,
    'cacheAfter': coordinator.checkpointStoreObservation,
  };

  Future<R> _measure<R>(String phase, Future<R> Function() work) async {
    final timer = Stopwatch()..start();
    try {
      return await work();
    } finally {
      _preparationUs.update(
        phase,
        (value) => value + timer.elapsedMicroseconds,
        ifAbsent: () => timer.elapsedMicroseconds,
      );
      _preparationCalls.update(phase, (value) => value + 1, ifAbsent: () => 1);
    }
  }

  void _beginPreparation() {
    _preparationUs.clear();
    _preparationCalls.clear();
    _beforeCache = coordinator.checkpointStoreObservation;
  }

  String get decisionSignature {
    final entries = _decisions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return jsonEncode([
      for (final value in entries) [value.key, value.value],
    ]);
  }

  @override
  StorySourceIdentity get sourceIdentity =>
      player.document.chapter.sourceIdentity;
  @override
  int get logicalTimeUs => player.storyUs;

  void recordChoice(int commandIndex, int? nextCommandIndex) {
    _decisions[commandIndex] = nextCommandIndex;
    _rememberPath();
  }

  String _rememberPath() {
    final signature = decisionSignature;
    _paths[signature] = Map.unmodifiable(_decisions);
    final anchor = _anchor;
    if (anchor != null && coordinator.checkpointAt(0, signature) == null) {
      coordinator.remember(
        VegaNarrativeCheckpoint(
          sourceIdentity: anchor.sourceIdentity,
          decisionSignature: signature,
          execution: anchor.execution,
          atUs: anchor.atUs,
          hostState: anchor.hostState.withDecisions(_decisions),
        ),
      );
    }
    return signature;
  }

  Future<void> seed() async {
    if (_anchor != null) return;
    await world.prepare();
    await world.settleResources();
    if (player.controller.cursor != 0 || player.checkpointDriver.playing) {
      throw StateError('story_seek_anchor_requires_initial_boundary');
    }
    _anchor = await coordinator.capture(decisionSignature: _rememberPath());
  }

  VegaSeekIndexCompilation? _preparedIndex;
  int? _indexPreparationUs;
  String? _indexBlockedReason;
  Map<String, Object?> get indexPreparationObservation => {
    'processed': _preparedIndex?.processed,
    'total': _preparedIndex?.commandCount,
    'blockedAt': _preparedIndex?.blockedAt,
    'blockedReason': _indexBlockedReason,
    'microseconds': _indexPreparationUs,
    'cache': coordinator.checkpointStoreObservation,
  };

  Future<void> prepareIndex(
    void Function(int completed, int total) progress,
  ) async {
    final timer = Stopwatch()..start();
    await seed();
    final plan = storySeekPreparationPlan(
      player.document.chapter.commands,
      checkpointBudget: coordinator.indexCheckpointBudget,
      knownChoices: _decisions.keys.toSet(),
      backendBarrier: callbacks.preparationBarrier,
    );
    _indexBlockedReason = plan.blockedReason;
    try {
      _preparedIndex = await coordinator.compileIndex(
        decisionSignature: _rememberPath(),
        checkpointPositions: plan.checkpointPositions,
        canReplay: (position) => position < plan.commandLimit,
        onProgress: (completed, _) => progress(completed, plan.commandLimit),
      );
    } finally {
      _indexPreparationUs = timer.elapsedMicroseconds;
    }
  }

  Future<VegaNarrativeCheckpoint<NativeStorySeekSnapshot<T>>> save() async {
    if (seeking) throw StateError('story_seek_active');
    return coordinator.capture(decisionSignature: _rememberPath());
  }

  static const portableCodec = 'haneoka-native-story-v1';

  Future<VegaSaveEnvelope> saveEnvelope({
    required Future<Uint8List> Function(Uri) fetch,
  }) async => encodeEnvelope(await save(), fetch: fetch);

  Future<VegaSaveEnvelope> encodeEnvelope(
    VegaNarrativeCheckpoint<NativeStorySeekSnapshot<T>> checkpoint, {
    required Future<Uint8List> Function(Uri) fetch,
  }) async {
    final encodeUi = callbacks.captureUiData;
    if (encodeUi == null) {
      throw StateError('story_portable_ui_codec_missing');
    }
    if (checkpoint.sourceIdentity != sourceIdentity ||
        checkpoint.hostState.runtimeHash != player.document.runtimeHash ||
        checkpoint.atUs != player.storyUs) {
      throw const FormatException('story_portable_checkpoint_source');
    }
    final worldData = world.snapshotData();
    final ui = await encodeUi(checkpoint.hostState.ui);
    final playback = await checkpoint.hostState.playback.toData(fetch: fetch);
    return VegaSaveEnvelope(
      sourceIdentity: sourceIdentity,
      decisionSignature: checkpoint.decisionSignature,
      execution: checkpoint.execution,
      atUs: checkpoint.atUs,
      hostCodec: portableCodec,
      hostData: {
        'runtimeHash': player.document.runtimeHash,
        'world': worldData,
        'playback': playback,
        'ui': ui,
        'decisions': {
          for (final e in checkpoint.hostState.decisions.entries)
            '${e.key}': e.value,
        },
      },
    );
  }

  Future<void> loadEnvelope(
    VegaSaveEnvelope envelope, {
    required Future<Uint8List> Function(Uri) fetch,
    bool resume = false,
  }) async {
    if (seeking || callbacks.restoreUiData == null) {
      throw StateError('story_portable_ui_codec_missing');
    }
    if (envelope.sourceIdentity != sourceIdentity ||
        envelope.hostCodec != portableCodec ||
        envelope.hostData['runtimeHash'] != player.document.runtimeHash ||
        (envelope.hostData['playback'] as Map)['atUs'] != envelope.atUs) {
      throw const FormatException('story_portable_source');
    }
    final decisions = {
      for (final e in (envelope.hostData['decisions'] as Map).entries)
        int.parse(e.key as String): e.value as int?,
    };
    final sorted = decisions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (jsonEncode([
          for (final e in sorted) [e.key, e.value],
        ]) !=
        envelope.decisionSignature) {
      throw const FormatException('story_portable_decisions');
    }
    var execution = envelope.execution;
    if (execution.version == 1) {
      final pendingCommand =
          (envelope.hostData['playback'] as Map)['pendingCommand'] as int?;
      if (pendingCommand != null) {
        final words = execution.words;
        final start = 5 + execution.commandCount;
        int? pendingId;
        for (var row = 0; row < words[3]; row++) {
          final offset = start + row * 6;
          if (words[offset + 1] == pendingCommand &&
              words[offset + 3] == -1 &&
              words[offset + 5] == 1) {
            pendingId = words[offset];
          }
        }
        if (pendingId != null) {
          execution = execution.withActiveExecutions({
            pendingId,
          }, blockingExecutionId: pendingId);
        }
      }
    }
    final verifier = player.checkpointDriver.forkReplay(execution);
    late final List<VegaExecutionRecord> history;
    try {
      history = verifier.history;
    } finally {
      verifier.dispose();
    }
    await world.settleResources();
    final state = NativeStorySeekSnapshot<T>(
      world: world.captureCheckpoint(),
      playback: await player.captureCheckpoint(),
      ui: await callbacks.captureUi(),
      runtimeHash: player.document.runtimeHash,
      decisions: Map.unmodifiable(decisions),
      portableData: envelope.hostData,
      portableExecutionHistory: history,
    );
    _portableFetch = fetch;
    await load(
      VegaNarrativeCheckpoint(
        sourceIdentity: sourceIdentity,
        decisionSignature: envelope.decisionSignature,
        execution: execution,
        atUs: envelope.atUs,
        hostState: state,
      ),
      resume: resume,
    );
  }

  Future<Uint8List> Function(Uri)? _portableFetch;

  Future<void> seek(int commandPosition, {bool resume = false}) {
    _beginPreparation();
    return _measure(
      'total',
      () => coordinator.seek(
        commandPosition,
        decisionSignature: _rememberPath(),
        resume: resume,
      ),
    );
  }

  Future<void> load(
    VegaNarrativeCheckpoint<NativeStorySeekSnapshot<T>> checkpoint, {
    bool resume = false,
  }) {
    _paths[checkpoint.decisionSignature] = checkpoint.hostState.decisions;
    _beginPreparation();
    return _measure(
      'total',
      () => coordinator.restore(checkpoint, resume: resume),
    );
  }

  @override
  Future<VegaExecutionCheckpoint> quiesce(VegaSeekContext context) async {
    context.checkCurrent();
    await player.pause();
    await settle(context);
    // Drain already queued acknowledgements before retiring command ownership.
    await Future<void>.value();
    context.checkCurrent();
    final execution = player.freezeForSeek();
    _quiescedUi = await callbacks.captureUi();
    _hasQuiescedUi = true;
    _quiescedPlayback = await player.captureCheckpoint(
      activeExecutionIds: execution.activeExecutionIds.toSet(),
    );
    await player.quiesceForSeek();
    await callbacks.quiesceUi(context);
    await world.quiesce();
    context.checkCurrent();
    return execution;
  }

  @override
  Future<NativeStorySeekSnapshot<T>> capture(VegaSeekContext context) async {
    context.checkCurrent();
    final playback = _quiescedPlayback ?? await player.captureCheckpoint();
    _quiescedPlayback = null;
    final ui = _hasQuiescedUi ? _quiescedUi as T : await callbacks.captureUi();
    _hasQuiescedUi = false;
    _quiescedUi = null;
    context.checkCurrent();
    return NativeStorySeekSnapshot(
      world: world.captureCheckpoint(),
      playback: playback,
      ui: ui,
      runtimeHash: player.document.runtimeHash,
      decisions: Map.unmodifiable(_decisions),
    );
  }

  @override
  Future<void> restore(
    NativeStorySeekSnapshot<T> state, {
    required int atUs,
    required VegaSeekContext context,
  }) =>
      _measure('restore', () => _restore(state, atUs: atUs, context: context));

  Future<void> _restore(
    NativeStorySeekSnapshot<T> state, {
    required int atUs,
    required VegaSeekContext context,
  }) async {
    context.checkCurrent();
    if (state.runtimeHash != player.document.runtimeHash ||
        state.playback.sourceIdentity != sourceIdentity ||
        state.playback.sourceEpoch != player.sourceEpoch) {
      throw const FormatException('story_seek_snapshot_source');
    }
    final portable = state.portableData;
    if (portable != null) {
      final fetch = _portableFetch;
      final restoreUi = callbacks.restoreUiData;
      if (fetch == null || restoreUi == null) {
        throw StateError('story_portable_restore_context');
      }
      await player.restoreData(
        portable['playback'] as Map,
        fetch: fetch,
        executionHistory: state.portableExecutionHistory,
      );
      context.checkCurrent();
      await world.restoreData(
        portable['world'] as Map,
        stamp: player.actualUpdateStamp,
      );
      context.checkCurrent();
      _decisions
        ..clear()
        ..addAll(state.decisions);
      await restoreUi(
        Map<String, Object?>.from(portable['ui'] as Map),
        context,
      );
      context.checkCurrent();
      return;
    }
    await player.restoreCheckpoint(state.playback);
    await world.restoreCheckpoint(state.world);
    _decisions
      ..clear()
      ..addAll(state.decisions);
    player.restoreClock(atUs);
    await callbacks.restoreUi(state.ui, context);
    context.checkCurrent();
  }

  @override
  Future<void> settle(VegaSeekContext context) => _measure('settle', () async {
    context.checkCurrent();
    await player.settleForCheckpoint();
    if (world.hasPendingResources) {
      await world.settleResources();
    }
    await callbacks.settleUi(context);
    context.checkCurrent();
  });

  @override
  Future<void> present(VegaSeekContext context) =>
      _measure('present', () async {
        context.checkCurrent();
        await callbacks.present(player.actualUpdateStamp, context);
        context.checkCurrent();
      });

  @override
  Future<VegaReplayOperation> replay(
    VegaExecutionRecord execution,
    VegaSeekContext context, {
    bool resuming = false,
  }) => _measure(
    'replay',
    () => player.replayCommand(
      execution,
      context,
      resuming: resuming,
      text: callbacks.replayText,
      choice: (command, dispatch) async {
        final path = _paths[context.decisionSignature];
        if (path == null || !path.containsKey(command.index)) {
          throw StateError('story_seek_choice_missing:${command.index}');
        }
        return path[command.index];
      },
    ),
  );

  @override
  Future<VegaReplayCompletion> waitForReplay(
    Future<VegaReplayCompletion> completion,
    VegaSeekContext context,
  ) => _measure(
    'waitReplay',
    () => player.waitForReplay(
      completion,
      context,
      advanceUi: (stamp) async => callbacks.advanceUi(stamp, context),
      settle: () => settle(context),
      visualDeadline: (stamp) {
        final worldDeadline = world.replayDeadlineUs(stamp);
        final ui = callbacks.uiDeadline?.call(stamp);
        return worldDeadline == null
            ? ui
            : ui == null
            ? worldDeadline
            : ui < worldDeadline
            ? ui
            : worldDeadline;
      },
    ),
  );

  @override
  Future<void> finishSeek({
    required bool resume,
    required int atUs,
    required VegaSeekContext context,
  }) async {
    context.checkCurrent();
    await player.finishSeek(atUs: atUs, resume: false);
    await callbacks.advanceUi(player.actualUpdateStamp, context);
    if (resume && !player.completed) await player.resume();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    coordinator.dispose();
    _paths.clear();
    _anchor = null;
    _quiescedUi = null;
    _portableFetch = null;
  }
}
