import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show haneokaProfileAssetRoot, loadHaneokaProfileString;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vega_plugin_haneoka/render_profile.dart';
import 'package:vega_plugin_haneoka/native_cubism.dart';
import 'package:vega_plugin_cubism/motion_sync.dart';

import '../core/api.dart';
import 'native_cubism_model_source.dart';
import 'native_cubism_scene_source.dart';
import 'native_unity_source_archive.dart';

import 'native_story_colour_scene.dart';
import 'native_story_document.dart';
import 'native_story_playback.dart';
import 'native_story_media.dart';
import 'story_snapshot_data.dart';

part 'native_story_world_data.dart';

bool _retainFocusRecord(Map record) => record['type'] == 'MonoBehaviour';

/// Pinned resources, model ownership and render composition for the App host.
/// Source character rules are applied by the game plugin's presentation state.
final class NativeStoryWorld {
  NativeStoryWorld({
    required this.api,
    required this.document,
    required this.epoch,
    required this.current,
    required this.currentStamp,
    required this.motionClockUs,
    required this.timing,
    required this.fetch,
  });
  final HaneokaApi api;
  final NativeStoryDocument document;
  final int epoch;
  final bool Function() current;
  final NativeStoryUpdateStamp Function() currentStamp;
  final int Function() motionClockUs;
  final StoryPresentationTiming Function() timing;
  int _durationUs(StoryDecodedCommand command, {int? overrideUs}) =>
      timing().durationUs(overrideUs ?? command.durationUs);
  final Future<Uint8List> Function(Uri) fetch;
  Future<MotionSyncController>? _voiceEngine;
  final _voiceChannels = <_WorldActor, Future<MotionSyncController>>{};
  final _voiceBindings = <_WorldActor, _WorldVoiceBinding>{};
  late final _voiceSources = StoryVoiceSourceBindings(
    document.chapter.commands,
  );
  Object? _voiceError;
  int? _voiceEngineVersion;

  Future<MotionSyncController> _prepareVoiceEngine() =>
      _voiceEngine ??= () async {
        final bytes = MotionSyncController.requiresExternalCore()
            ? await fetch(
                document.assets.pinned(
                  '/Core/CRI/live2dcubismmotionsynccore.min.js',
                ),
              )
            : null;
        if (!_alive()) throw StateError('story_voice_source_closed');
        final engine = await MotionSyncController.open(coreBytes: bytes);
        if (!_alive()) {
          await engine.dispose();
          throw StateError('story_voice_source_closed');
        }
        _voiceEngineVersion = engine.engineVersion;
        return engine;
      }();

  /// Cue identity owns the binding; media restoration creates a new cue and
  /// rebuilds its Core context from that cue's actual played position.
  void syncVoiceCues(
    Iterable<NativeStoryMediaCue> cues, {
    required bool paused,
    required double storySpeed,
    required bool shortcut,
    List<StoryMediaObservation>? observations,
  }) {
    if (!_alive()) return;
    final desired = <_WorldActor, NativeStoryMediaCue>{};
    for (final cue in cues) {
      if (cue.kind != StoryMediaKind.voice ||
          !cue.ready ||
          cue.player.state.completed ||
          cue.error != null) {
        continue;
      }
      for (final name in _voiceSources.targets(
        commandIndex: cue.commandIndex,
        voiceId: cue.id,
        resourceRef: cue.resourceRef,
        storySpeed: storySpeed,
        shortcut: shortcut,
        showingTargets: _actors.values
            .where((actor) => actor.model.visible)
            .map((actor) => actor.name),
      )) {
        final actor = _actors[name];
        if (actor?.motionSync != null) desired[actor!] = cue;
      }
    }
    for (final entry in _voiceBindings.entries.toList()) {
      if (!identical(desired[entry.key], entry.value.cue)) {
        _voiceBindings.remove(entry.key);
        _retireVoice(entry.key, entry.value);
      }
    }
    for (final entry in desired.entries) {
      final actor = entry.key;
      var binding = _voiceBindings[actor];
      if (binding == null) {
        binding = _WorldVoiceBinding(entry.value);
        _voiceBindings[actor] = binding;
        unawaited(_bindVoice(actor, binding));
      }
      if (paused || observations == null || binding.failed) continue;
      final observation = observations
          .where(
            (value) =>
                value.kind == StoryMediaKind.voice &&
                value.cueId == binding!.cue.id,
          )
          .firstOrNull;
      if (observation == null || observation.completed) continue;
      unawaited(_sampleVoice(actor, binding, observation));
    }
  }

  bool _voiceCurrent(_WorldActor actor, _WorldVoiceBinding binding) =>
      _alive() &&
      identical(_actors[actor.name], actor) &&
      identical(_voiceBindings[actor], binding) &&
      binding.cue.ready &&
      !binding.cue.player.state.completed;

  Future<void> _bindVoice(_WorldActor actor, _WorldVoiceBinding binding) async {
    try {
      final profile = actor.motionSync!;
      final channel = await _voiceChannels.putIfAbsent(
        actor,
        () async => (await _prepareVoiceEngine()).createChannel(),
      );
      if (!_voiceCurrent(actor, binding)) return;
      binding.channel = channel;
      final bytes = await binding.cue.encodedBytes();
      if (!_voiceCurrent(actor, binding)) return;
      final initial = actor.model.parameterValues(profile.parameterIds);
      final voice = await channel.prepare(
        cacheKey: binding.cue.uri.toString(),
        encodedAudio: bytes,
        setting: profile.setting,
        initialValues: [
          for (final id in profile.parameterIds) initial[id] ?? 0,
        ],
      );
      if (!_voiceCurrent(actor, binding) || voice == null) return;
      binding.voice = voice;
      final observation = await binding.cue.sample();
      if (!_voiceCurrent(actor, binding) || observation == null) return;
      final frame = await channel.seek(
        generation: voice.generation,
        positionFrames: observation.positionUs * 48000 ~/ 1000000,
      );
      _applyVoiceFrame(actor, binding, frame);
    } catch (error) {
      if (_voiceCurrent(actor, binding)) {
        binding.failed = true;
        _voiceError = error;
        actor.model.setVoiceParameters(null);
      }
    }
  }

  Future<void> _sampleVoice(
    _WorldActor actor,
    _WorldVoiceBinding binding,
    StoryMediaObservation observation,
  ) async {
    final voice = binding.voice, channel = binding.channel;
    if (voice == null || channel == null || !_voiceCurrent(actor, binding)) {
      return;
    }
    final position = observation.positionUs * 48000 ~/ 1000000;
    if (position == binding.positionFrames) return;
    binding.positionFrames = position;
    try {
      final frame = await channel.update(
        generation: voice.generation,
        positionFrames: position,
        playing: observation.playing,
      );
      _applyVoiceFrame(actor, binding, frame);
    } catch (error) {
      if (_voiceCurrent(actor, binding)) {
        binding.failed = true;
        _voiceError = error;
        actor.model.setVoiceParameters(null);
      }
    }
  }

  void _applyVoiceFrame(
    _WorldActor actor,
    _WorldVoiceBinding binding,
    MotionSyncFrame? frame,
  ) {
    if (frame == null || !_voiceCurrent(actor, binding)) return;
    actor.model.setVoiceParameters({
      for (var i = 0; i < frame.parameterIds.length; i++)
        frame.parameterIds[i]: frame.values[i],
    }, neutral: actor.motionSync!.neutral);
    binding.frame = frame;
  }

  void _retireVoice(_WorldActor actor, _WorldVoiceBinding binding) {
    actor.model.setVoiceParameters(null);
    final channel = binding.channel;
    if (channel != null) {
      unawaited(
        channel.reset().then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            if (_alive()) _voiceError = error;
          },
        ),
      );
    }
  }

  void clearVoiceBindings() {
    for (final entry in _voiceBindings.entries) {
      _retireVoice(entry.key, entry.value);
    }
    _voiceBindings.clear();
  }

  NativeCubismCore? _core;
  NativeCubismSceneSource? _scene;
  NativeCubismStageSource? _stage;
  Uri? _background;
  Map? _focusSettings;
  final _cameraTweens = <String, _WorldTween>{};
  final _movementTweens = <_WorldTween>[];
  final _pendingCamera = <Future<void>>[];
  final _focusCamera = Float32List(3);
  double _focusZoom = 1;
  int _focusDistance = 0;
  double _curvedLensRate = 1;
  StoryPostVolumeState? _postVolume;
  final _postPasses = StoryPostPasses();
  final _characterPresentation = StoryCharacterPresentation();
  final _motionQueue = StoryCharacterMotionQueue<_WorldActor>();
  final _postWeights = <String, double>{};
  final _postEnabled = <String, bool>{};
  int _postEnvironment = 0, _lightEnvironment = 0;
  HaneokaCharacterLighting? get _characterLighting => _stage?.lighting.select(
    _lightEnvironment,
    baseQualityMode:
        (document.runtime['baseQualityMode'] as num?)?.toInt() ?? 3,
    allowUnityLighting: document.runtime['allowUnityLighting'] == true,
  );
  double _backgroundBrightness = 1;
  double _backgroundBlur = 0, _blurRadiusMax = .75;
  final _blurGenerations = <int, int>{};
  final _characterBlur = StoryCharacterBlurChannels();
  int _backgroundBlurGeneration = 0;
  Float32List? _baseCamera;
  final _panOffset = Float32List(3);
  Float32List get _cameraBase => _baseCamera ??= Float32List(3);

  final _actors = <String, _WorldActor>{};
  final _assets = <String, Map<int, _WorldActor>>{};
  final _ownedActors = <_WorldActor>{};
  final _actorResources = <(String, int, String), _WorldActorResource>{};
  final _actorSources = <String, Future<NativeCubismModelSource>>{};
  final _preparationTimings = <Map<String, Object?>>[];
  int _preparedModels = 0, _preparationModels = 0;
  final _checkpointOwner = Object();
  final _pendingResources = <Future<void>>{};
  final _random = math.Random();
  final _randomValues = <double>[];
  int _randomPosition = 0;
  double _randomUnit() {
    if (_randomPosition == _randomValues.length) {
      _randomValues.add(_random.nextDouble());
    }
    return _randomValues[_randomPosition++];
  }

  NativeStoryUpdateStamp? _lastStamp;
  double _sceneUs = 0;
  int _shakeUs = 0;
  final _backgroundShake = AuthoredShakeTrack();
  final _characterShake = AuthoredShakeTrack();
  final _stillShake = AuthoredShakeTrack();
  final _talkShake = AuthoredShakeTrack();
  final _cameraShake = AuthoredCameraShakeTrack();
  final _shakeWaits = <_WorldShakeWait>[];
  int _shakeGeneration = 0;
  int get shakeGeneration => _shakeGeneration;
  Float32List get stillShakeOffset => _stillShake.offset;
  Float32List get talkShakeOffset => _talkShake.offset;
  bool get cameraShakePlaying => _cameraShake.isPlaying;
  bool _disposed = false;
  bool get active =>
      _stage != null || _actors.values.any((actor) => actor.model.visible);
  Float32List get cameraClearColor => _scene!.cameraClearRgba;
  bool get hasPendingResources => _pendingResources.isNotEmpty;

  Future<void> settleResources() async {
    while (_pendingResources.isNotEmpty) {
      await Future.wait(_pendingResources.toList());
    }
    if (!_alive()) throw StateError('story_world_source_closed');
  }

  Future<void> quiesce() async {
    final camera = {
      for (final entry in _cameraTweens.entries) entry.key: entry.value.copy(),
    };
    final movement = [for (final value in _movementTweens) value.copy()];
    for (final tween in [..._cameraTweens.values, ..._movementTweens]) {
      tween.finish();
    }
    _cameraTweens
      ..clear()
      ..addAll(camera);
    _movementTweens
      ..clear()
      ..addAll(movement);
    _pendingCamera.clear();
    final waits = [for (final wait in _shakeWaits) wait.copy()];
    for (final wait in _shakeWaits) {
      wait.finish();
    }
    _shakeWaits
      ..clear()
      ..addAll(waits);
    await settleResources();
  }

  Future<void> waitPendingVisualsForExecution(
    int executionId, {
    required int commandIndex,
    required bool blocking,
  }) {
    final tweens = [..._cameraTweens.values, ..._movementTweens];
    final owned = [
      for (final tween in tweens)
        if (tween.executionId == executionId) tween.done.future,
      for (final wait in _shakeWaits)
        if (wait.executionId == executionId) wait.done.future,
    ];
    if (owned.isNotEmpty) return Future.wait(owned);
    for (final tween in tweens) {
      if (tween.executionId == null &&
          tween.commandIndex == commandIndex &&
          tween.waitForCompletion == true &&
          blocking) {
        tween.executionId = executionId;
        owned.add(tween.done.future);
      }
    }
    for (final wait in _shakeWaits) {
      if (wait.executionId == null &&
          wait.commandIndex == commandIndex &&
          wait.waitForCompletion == true &&
          blocking) {
        wait.executionId = executionId;
        owned.add(wait.done.future);
      }
    }
    if (owned.isEmpty &&
        blocking &&
        (tweens.any((value) => value.executionId == null) ||
            _shakeWaits.any((value) => value.executionId == null))) {
      throw FormatException('story_world_legacy_execution_owner:$commandIndex');
    }
    return Future.wait(owned);
  }

  int? replayDeadlineUs(NativeStoryUpdateStamp stamp) {
    double? end;
    for (final tween in [..._cameraTweens.values, ..._movementTweens]) {
      end = math.max(
        end ?? _sceneUs,
        (tween.startUs + tween.durationUs).toDouble(),
      );
    }
    for (final actor in _actors.values) {
      if (actor.fadeDuration > 0 &&
          actor.fadeStart + actor.fadeDuration > _sceneUs) {
        end = math.max(
          end ?? _sceneUs,
          (actor.fadeStart + actor.fadeDuration).toDouble(),
        );
      }
    }
    int? deadline = end == null
        ? null
        : stamp.storyUs + ((end - _sceneUs) / stamp.speed).ceil();
    for (final wait in _shakeWaits) {
      final end = wait.untilIdle
          ? _cameraShake.nextBoundaryUs ?? wait.untilUs
          : wait.untilUs;
      deadline = math.max(deadline ?? stamp.storyUs, end);
    }
    final motionWait = _motionQueue.nextWaitSeconds(
      showing: _motionControllerShowing,
    );
    if (motionWait != null && stamp.speed > 0) {
      final atUs = stamp.storyUs + (motionWait * 1000000 / stamp.speed).ceil();
      deadline = math.min(deadline ?? atUs, atUs);
    }
    return deadline;
  }

  NativeStoryWorldCheckpoint captureCheckpoint() {
    if (_scene == null || _postVolume == null || _pendingResources.isNotEmpty) {
      throw StateError('story_world_checkpoint_unsettled');
    }
    final projection = _ProjectionCheckpoint(_scene!.projection);
    final stage = _stage, background = _background;
    final lightEnvironment = _lightEnvironment;
    final assets = {
      for (final entry in _assets.entries)
        entry.key: Map<int, _WorldActor>.of(entry.value),
    };
    final actors = Map<String, _WorldActor>.of(_actors);
    final motions = _motionQueue.snapshot();
    final actorStates = {
      for (final actor in {
        ...assets.values.expand((values) => values.values),
        for (final motion in motions) motion.controller,
      })
        actor: actor.captureCheckpoint(),
    };
    final post = _postVolume!.snapshot();
    final weights = Map<String, double>.of(_postWeights);
    final enabled = Map<String, bool>.of(_postEnabled);
    final placements = _characterPresentation.placements.snapshot(),
        order = _characterPresentation.order.slots;
    final characterControls = _characterPresentation.controls.snapshot();
    final focus = Float32List.fromList(_focusCamera);
    final cameraBase = _baseCamera == null
        ? null
        : Float32List.fromList(_baseCamera!);
    final pan = Float32List.fromList(_panOffset);
    final values = (
      _focusZoom,
      _focusDistance,
      _curvedLensRate,
      _postEnvironment,
      _backgroundBrightness,
      _backgroundBlur,
      _blurRadiusMax,
      _backgroundBlurGeneration,
    );
    final blur = _characterBlur.values;
    final blurGenerations = Map<int, int>.of(_blurGenerations);
    final cameraTweens = {
      for (final entry in _cameraTweens.entries) entry.key: entry.value.copy(),
    };
    final movements = [for (final value in _movementTweens) value.copy()];
    final shakes = (
      _backgroundShake.snapshot(),
      _characterShake.snapshot(),
      _stillShake.snapshot(),
      _talkShake.snapshot(),
      _cameraShake.snapshot(),
    );
    final clocks = (
      _sceneUs,
      _shakeUs,
      _lastStamp,
      _randomPosition,
      _shakeGeneration,
    );
    final waits = [for (final wait in _shakeWaits) wait.copy()];
    return NativeStoryWorldCheckpoint._(
      _checkpointOwner,
      document.chapter.sourceIdentity,
      epoch,
      List.unmodifiable({
        ?background,
        for (final actor in actorStates.keys) ...actor.textures.values,
      }),
      Map.unmodifiable({
        for (final actor in actorStates.keys)
          '${actor.name}:${actor.assetIndex}':
              '${actor.key}:${actor.sourceFingerprint}',
      }),
      () {
        for (final actor in _ownedActors) {
          if (!actorStates.containsKey(actor)) actor.model.show(false);
        }
        _assets
          ..clear()
          ..addAll({
            for (final entry in assets.entries)
              entry.key: Map<int, _WorldActor>.of(entry.value),
          });
        _actors
          ..clear()
          ..addAll(actors);
        for (final entry in actorStates.entries) {
          entry.value();
        }
        _stage = stage;
        _lightEnvironment = lightEnvironment;
        _background = background;
        projection.restore(_scene!.projection);
        _postVolume!.restore(post);
        _postWeights
          ..clear()
          ..addAll(weights);
        _postEnabled
          ..clear()
          ..addAll(enabled);
        _characterPresentation.placements.restore(placements);
        _characterPresentation.controls.restore(characterControls);
        _characterPresentation.order.restore(order);
        _motionQueue.restore(motions);
        _focusCamera.setAll(0, focus);
        _baseCamera = cameraBase == null
            ? null
            : Float32List.fromList(cameraBase);
        _panOffset.setAll(0, pan);
        _focusZoom = values.$1;
        _focusDistance = values.$2;
        _curvedLensRate = values.$3;
        _postEnvironment = values.$4;
        _backgroundBrightness = values.$5;
        _backgroundBlur = values.$6;
        _blurRadiusMax = values.$7;
        _backgroundBlurGeneration = values.$8;
        for (var i = 0; i < blur.length; i++) {
          _characterBlur.write(i, blur[i]);
        }
        _blurGenerations
          ..clear()
          ..addAll(blurGenerations);
        _cameraTweens
          ..clear()
          ..addAll({
            for (final entry in cameraTweens.entries)
              entry.key: entry.value.copy(),
          });
        _movementTweens
          ..clear()
          ..addAll(movements.map((value) => value.copy()));
        _backgroundShake.restore(shakes.$1);
        _characterShake.restore(shakes.$2);
        _stillShake.restore(shakes.$3);
        _talkShake.restore(shakes.$4);
        _cameraShake.restore(shakes.$5);
        _shakeWaits
          ..clear()
          ..addAll([for (final wait in waits) wait.copy()]);
        _sceneUs = clocks.$1;
        _shakeUs = clocks.$2;
        _lastStamp = clocks.$3;
        _randomPosition = clocks.$4;
        _shakeGeneration = clocks.$5;
        _syncShakeOffsets();
      },
    );
  }

  Future<void> restoreCheckpoint(NativeStoryWorldCheckpoint checkpoint) async {
    if (checkpoint.sourceIdentity != document.chapter.sourceIdentity ||
        checkpoint.sourceEpoch != epoch ||
        !identical(checkpoint._owner, _checkpointOwner)) {
      throw const FormatException('story_world_checkpoint_source');
    }
    await quiesce();
    checkpoint._restore();
  }

  Future<void>? _preparing;
  Future<void> prepare() => _preparing ??= _trackedPrepare();

  Future<void> _trackedPrepare() async {
    final work = _prepare();
    _pendingResources.add(work);
    try {
      await work;
    } finally {
      _pendingResources.remove(work);
    }
  }

  Future<void> _prepare() async {
    if (_scene != null) return;
    const configured = String.fromEnvironment('HANEOKA_CUBISM_CORE');
    _core ??= NativeCubismCore.open(
      libraryPath: configured.isNotEmpty ? configured : null,
    );
    _scene = await NativeCubismSceneSource.load(
      api: api,
      identity: document.chapter.sourceIdentity,
      current: _alive,
    );
    final focus = await NativeUnitySourceArchive.load(
      api: api,
      identity: document.chapter.sourceIdentity,
      sourcePath: 'Assets/AddressableResources/Common/Adv/Settings/FocusData/AdvFocusDataSettings-Sirius.asset',
      current: _alive,
      decodeOffThread: true,
      retain: _retainFocusRecord,
    );
    _focusSettings = focus.requireScript('AdvFocusDataSettings')['data'] as Map;
    final defaults = jsonDecode(
      await loadHaneokaProfileString(
        '${haneokaProfileAssetRoot}story-default-volume-profile.json',
      ),
    ) as Map;
    _postVolume = StoryPostVolumeState(
      defaults: StoryPostSettings.fromDefaultProfile(defaults),
    );
  }

  bool _alive() => !_disposed && current();

  double _playerNumber(String key) => (document.runtime[key] as num).toDouble();
  int _shakeDuration(int microseconds) =>
      (microseconds / currentStamp().speed).round();

  int shake(StoryDecodedCommand command) {
    update(currentStamp());
    final generation = ++_shakeGeneration;
    final power = command.numericParameter(0) ?? 0;
    final layers = (command.payload['canvasLayers'] as List? ?? const [])
        .cast<num>();
    void start(AuthoredShakeTrack track, bool vectorBased) {
      track.start(
        nowUs: _shakeUs,
        durationUs: _shakeDuration(command.durationUs),
        strength:
            power *
            _playerNumber(
              vectorBased ? 'shakeFieldStrength' : 'shakeUIStrength',
            ),
        vectorBased: vectorBased,
        randomUnit: _randomUnit,
      );
    }

    if (layers.isEmpty || layers.contains(0)) start(_backgroundShake, true);
    if (layers.isEmpty || layers.contains(1) || layers.contains(2)) {
      start(_characterShake, true);
    }
    if (layers.isEmpty || layers.contains(7)) start(_stillShake, false);
    if (layers.isEmpty || layers.contains(9)) start(_talkShake, false);
    _syncShakeOffsets();
    return generation;
  }

  Future<void> cameraShake(
    StoryDecodedCommand command, {
    required int executionId,
  }) async {
    await prepare();
    if (!_alive()) return;
    update(currentStamp());
    final fadeParameter = command.numericParameter(0) ?? 0;
    final fadeUs = _shakeDuration(
      fadeParameter > 0
          ? (fadeParameter * 1000000).round()
          : command.durationUs,
    );
    final stopping = _cameraShake.isPlaying;
    for (final wait in _shakeWaits.where((wait) => wait.untilIdle)) {
      wait.finish();
    }
    _shakeWaits.removeWhere((wait) => wait.done.isCompleted);
    if (stopping) {
      _cameraShake.disable(nowUs: _shakeUs, fadeUs: fadeUs);
    } else {
      final parameter = command.numericParameter(1) ?? 0;
      _cameraShake.enable(
        nowUs: _shakeUs,
        fadeUs: fadeUs,
        cycleUs: (_playerNumber('cameraShakeDuration') * 1000000).round(),
        strength: parameter > 0
            ? parameter
            : _playerNumber('cameraShakeStrength'),
        vibrato: _playerNumber('cameraShakeVibrato').toInt(),
        randomness: _playerNumber('cameraShakeRandomness'),
        randomUnit: _randomUnit,
      );
    }
    if (!stopping && fadeUs <= 0) return;
    final wait = _WorldShakeWait(
      untilUs: _shakeUs + fadeUs,
      untilIdle: stopping,
      executionId: executionId,
      commandIndex: command.index,
      waitForCompletion: !command.noWait,
    );
    _shakeWaits.add(wait);
    await wait.done.future;
  }

  void _syncShakeOffsets() {
    final projection = _scene?.projection;
    if (projection == null) return;
    projection.backgroundOffset.setAll(0, _backgroundShake.offset);
    projection.fieldOffset.setAll(0, _characterShake.offset);
    projection.cameraOffset.setAll(0, _cameraShake.offset);
  }

  void resetShakes() {
    ++_shakeGeneration;
    _backgroundShake.stop();
    _characterShake.stop();
    _stillShake.stop();
    _talkShake.stop();
    _cameraShake.reset();
    _syncShakeOffsets();
    for (final wait in _shakeWaits) {
      wait.finish();
    }
    _shakeWaits.clear();
  }

  Future<void> stage(String reference) async {
    final work = _selectStage(reference);
    _pendingResources.add(work);
    try {
      await work;
    } finally {
      _pendingResources.remove(work);
    }
  }

  Future<void> _selectStage(String reference) async {
    await prepare();
    final selected = await _scene!.loadStage(
      api: api,
      exactStageRef: reference,
      current: _alive,
    );
    if (!_alive()) return;
    _stage = selected;
    _background = document.assets.pinned(
      document.assets.backgrounds[reference]!['url'] as String,
    );
    _scene!.projection.selectStage(selected.geometry);
    _lightEnvironment = 0;
    _postEnvironment = 0;
    _applyStagePost(0);
    _baseCamera = Float32List.fromList(selected.geometry.initialCameraPosition);
    _panOffset.fillRange(0, 3, 0);
    for (final key
        in _cameraTweens.keys
            .where((key) => key == 'yaw' || key.startsWith('slotYaw:'))
            .toList()) {
      _cameraTweens.remove(key)?.finish();
    }
  }

  void _applyStagePost(int index) {
    final stages = document.runtime['stages'] as Map;
    final stage = stages[_stage?.ref] as Map?;
    final refs = stage?['environmentPostEffectRefs'] as List? ?? const [];
    final profiles = document.runtime['postEffects'] as Map;
    final profile =
        document.runtime['allowStagePostEffect'] == true &&
            index >= 0 &&
            index < refs.length
        ? profiles[refs[index]] as Map?
        : null;
    _postVolume!.setStage(profile);
    _postEnvironment = index;
  }

  void postEffect(StoryDecodedCommand command, {required int executionId}) {
    if (document.runtime['allowStagePostEffect'] != true) return;
    update(currentStamp());
    final ref =
        command.resourceRefs['postEffectRef'] ??
        (command.payload['targetAssetName'] as String? ?? '').split('/').last;
    final fade = command.numericParameter(0) ?? 0;
    final duration = fade > 0 ? (fade * 1000000).round() : command.durationUs;
    final keys = ref.isEmpty ? _postEnabled.keys.toList() : [ref];
    for (final key in keys) {
      final profile = (document.runtime['postEffects'] as Map)[key] as Map?;
      if (profile == null) throw StateError('story_post_profile_missing:$key');
      final enabled = ref.isNotEmpty && !(_postEnabled[key] ?? false);
      _postEnabled[key] = enabled;
      final from = _postWeights[key] ?? 0;
      _postVolume!.setChild(key, profile, weight: from, priority: 1);
      unawaited(
        _sceneValue(
          'post:$key',
          from,
          enabled ? 1 : 0,
          command,
          6,
          (value) {
            _postWeights[key] = value;
            _postVolume!.setWeight(key, value);
          },
          durationUs: duration,
          executionId: executionId,
        ),
      );
    }
  }

  List<String> stageEnvironment(StoryDecodedCommand command) {
    final kind = command.parameter(0)?.trim() ?? '';
    final type =
        const {
          'All': 0,
          'Light': 1,
          'Effect': 2,
          'PostEffect': 3,
          'FocusPosition': 4,
        }[kind] ??
        int.tryParse(kind) ??
        0;
    final index = command.numericParameter(1)?.toInt() ?? 0;
    if (type == 0 || type == 1) _lightEnvironment = index;
    if (type == 0 || type == 3) _applyStagePost(index);
    if ((type == 0 || type == 4) && _stage != null) {
      _scene!.projection.selectFocusSet(_stage!.geometry, index);
      _sortCharacterDepths(resetPriority: true);
    }
    return [
      if ((type == 0 || type == 2) &&
          document.runtime['allowStageParticleEffect'] == true)
        'stage_particles',
    ];
  }

  Future<void> load(StoryDecodedCommand command) async {
    final work = _load(command);
    _pendingResources.add(work);
    try {
      await work;
    } finally {
      _pendingResources.remove(work);
    }
  }

  Future<void> _load(StoryDecodedCommand command) async {
    final name = command.payload['targetName'] as String;
    final key = command.payload['live2dKey'] as String;
    final assetIndex = command.payload['targetAssetIndex'] as int? ?? 0;
    await _loadRegistered(name, key, assetIndex);
  }

  Future<void> _loadRegistered(String name, String key, int assetIndex) async {
    await prepare();
    final registered = _assets.putIfAbsent(name, () => {});
    if (registered[assetIndex]?.key == key) return;
    final identity = (name, assetIndex, key);
    final cached =
        _actorResources[identity] ??
        await _constructActor(name, key, assetIndex);
    if (!_alive() || cached == null) return;
    cached.restoreInitial();
    cached.actor.model.resetInitialClock(
      seconds: _sceneUs / 1000000,
      frame: currentStamp().updateIndex,
    );
    _installActor(registered, cached.actor);
  }

  Future<NativeCubismModelSource> _actorSource(String key) =>
      _actorSources.putIfAbsent(
        key,
        () => NativeCubismModelSource.load(
          api,
          document.chapter.sourceIdentity,
          key,
          _alive,
          onTiming: (phase, us) => _preparationTiming(key, phase, us),
        ),
      );

  void _preparationTiming(String resource, String phase, int us) {
    _preparationTimings.add({
      'resource': resource,
      'phase': phase,
      'microseconds': us,
    });
    if (_preparationTimings.length > 96) _preparationTimings.removeAt(0);
  }

  Future<_WorldActorResource?> _constructActor(
    String name,
    String key,
    int assetIndex,
  ) async {
    final original = await _actorSource(key);
    if (!_alive()) return null;
    final timer = Stopwatch()..start();
    final model = NativeCubismModelHost(
      breathMotionEnabled:
          document.runtime['allowCharacterBreathMotion'] != false &&
          ((document.runtime['baseQualityMode'] as num?)?.toInt() ?? 3) > 2,
      core: _core!,
      mocBytes: original.mocBytes,
      prefabRecords: original.records,
      preparedPrefab: original.preparedPrefab,
      onPreparationPhase: (phase, us) =>
          _preparationTiming(key, 'construct.$phase', us),
      randomUnit: _randomUnit,
      initialSeconds: _sceneUs / 1000000,
      initialFrame: currentStamp().updateIndex,
    );
    _preparationTiming(key, 'construct', timer.elapsedMicroseconds);
    timer.reset();
    final profile = original.catalog['profile'] as Map;
    final position = profile['basePosition'] as Map;
    final textures = (original.catalog['runtime'] as Map)['textures'] as List;
    final head = (profile['anchors'] as Map)['head'] as Map;
    final headPosition = head['position'] as Map;
    final actor = _WorldActor(
      name,
      original.key,
      assetIndex,
      model,
      Float32List.fromList([
        for (final axis in ['x', 'y', 'z']) (position[axis] as num).toDouble(),
      ]),
      (profile['baseScale'] as num).toDouble(),
      Float32List.fromList([
        for (final axis in ['x', 'y', 'z'])
          (headPosition[axis] as num).toDouble(),
      ]),
      {
        for (final (index, path) in textures.indexed)
          index: document.assets.pinned(path as String),
      },
      _characterBlur,
      '${original.archiveHash}:${original.mocHash}',
      storyMotionSyncProfileFromCatalog(original.catalog),
    );
    if (!_alive()) {
      model.dispose();
      return null;
    }
    _ownedActors.add(actor);
    if (actor.motionSync != null) {
      unawaited(
        _prepareVoiceEngine().then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            if (_alive()) _voiceError = error;
          },
        ),
      );
    }
    final resource = _WorldActorResource(actor, actor.captureCheckpoint());
    _actorResources[(name, assetIndex, key)] = resource;
    _actorSources.remove(key);
    _preparationTiming(key, 'initialSnapshot', timer.elapsedMicroseconds);
    return resource;
  }

  Future<void> prewarmInitialModels(
    void Function(int completed, int total) progress,
  ) async {
    final plan = storyInitialCharacterLoads(document.chapter.commands);
    _preparedModels = 0;
    _preparationModels = plan.length;
    progress(0, plan.length);
    await prepare();
    for (var offset = 0; offset < plan.length; offset += 2) {
      final batch = plan.skip(offset).take(2).toList();
      await Future.wait([
        for (final command in batch)
          _actorSource(command.payload['live2dKey'] as String),
      ]);
      if (!_alive()) return;
      // Keep constructor RNG draws in authored registration order.
      for (final command in batch) {
        final name = command.payload['targetName'] as String;
        final key = command.payload['live2dKey'] as String;
        final index = command.payload['targetAssetIndex'] as int? ?? 0;
        final resource =
            _actorResources[(name, index, key)] ??
            await _constructActor(name, key, index);
        if (!_alive() || resource == null) return;
        final textures = resource.actor.textures.values.toList();
        for (var i = 0; i < textures.length; i += 2) {
          await Future.wait([
            for (final uri in textures.skip(i).take(2)) fetch(uri),
          ]);
          if (!_alive()) return;
        }
        progress(++_preparedModels, plan.length);
      }
    }
  }

  void _installActor(Map<int, _WorldActor> registered, _WorldActor actor) {
    final previous = registered.remove(actor.assetIndex);
    registered[actor.assetIndex] = actor;
    if (_actors[actor.name] == null ||
        identical(_actors[actor.name], previous)) {
      _actors[actor.name] = actor;
    }
  }

  void costume(StoryDecodedCommand command) {
    final index = command.payload['targetAssetIndex'] as int? ?? 0;
    for (final name in command.targets) {
      final selected = _assets[name]?[index];
      if (selected == null) {
        throw StateError('story_costume_not_registered:$name:$index');
      }
      final previous = _actors[name];
      if (identical(selected, previous)) continue;
      if (previous != null) {
        selected.slot = previous.slot;
        selected.opacity = previous.opacity;
        selected.fadeStart = previous.fadeStart;
        selected.fadeDuration = previous.fadeDuration;
        selected.from = previous.from;
        selected.to = previous.to;
        selected.brightness = previous.brightness;
        selected.model.show(previous.model.visible);
        previous.model.show(false);
      }
      _actors[name] = selected;
    }
    update(currentStamp());
  }

  void show(StoryDecodedCommand command, bool visible) {
    update(currentStamp());
    _characterPresentation.show(
      command,
      actors: _actors,
      visible: visible,
      atUs: _sceneUs.round(),
      timing: timing(),
      apply: _applyCharacterPresentation,
    );
  }

  void _applyCharacterPresentation(
    _WorldActor actor,
    StoryCharacterPresentationEffect effect,
  ) {
    switch (effect) {
      case StoryCharacterVisibility(:final visible):
        actor.model.show(visible);
      case StoryCharacterEyeBlink(:final stopped, :final transitionSeconds):
        actor.model.setEyeBlinkStopped(
          stopped,
          transitionSeconds: transitionSeconds,
        );
      case StoryCharacterSourcePause(:final paused):
        actor.model.setSourcePaused(paused);
      case StoryCharacterAngleLookReset():
        _resetAngleLook(actor);
      case StoryCharacterDepthSort():
        _sortCharacterDepths();
    }
  }

  void _resetAngleLook(_WorldActor actor) {
    for (final key in [
      'angle:${actor.name}',
      'bodyAngle:${actor.name}',
      'look:${actor.name}:x',
      'look:${actor.name}:y',
    ]) {
      _cameraTweens.remove(key)?.finish();
    }
    actor.lookIntent++;
    actor.headAngle = actor.bodyAngle = 0;
    actor.lookX = actor.lookY = 0;
    actor.originalLookX = actor.originalLookY = 0;
    actor.lookEnabled = false;
    actor.lookStopPending = false;
    actor.model.setAngleOffsets(null, null);
    actor.model.setEyeLook(null, null);
  }

  void reorder(StoryDecodedCommand command) =>
      _characterPresentation.reorder(command);

  /// AdvMotionController observes Unity frame time independently of transport.
  /// Source replay supplies its accepted clock through update instead.
  void advanceMotionFrame({
    required double deltaSeconds,
    required int atUs,
    required double speed,
    required bool transportPaused,
  }) {
    if (!_alive() || timing().shortcut || _motionQueue.isEmpty) return;
    if (transportPaused) {
      final stamp = currentStamp();
      update(
        NativeStoryUpdateStamp(
          sourceEpoch: stamp.sourceEpoch,
          updateIndex: stamp.updateIndex,
          storyUs: stamp.storyUs,
          speed: speed,
          paused: true,
        ),
      );
    }
    _motionQueue.advance(
      deltaSeconds * speed,
      atUs: atUs,
      speed: speed,
      showing: _motionControllerShowing,
      play: _playCharacterMotion,
    );
  }

  bool _motionControllerShowing(String _, _WorldActor actor) =>
      actor.model.visible;

  void _playCharacterMotion(
    _WorldActor actor,
    StoryCharacterMotionRequest request,
  ) {
    if (request.motionName.isNotEmpty) {
      actor.model.playMotion(request.motionName, fade: request.fade);
    }
    if (request.expressionName.isNotEmpty) {
      actor.model.playExpression(request.expressionName, fade: request.fade);
    }
  }

  void motion(StoryDecodedCommand command) {
    update(currentStamp());
    final request = StoryCharacterMotionRequest.fromCommand(
      command,
      shortcut: timing().shortcut,
    );
    final atUs = command.opcode == 21 ? motionClockUs() : 0;
    for (final name in command.targets) {
      final actor = _actors[name];
      if (actor == null) continue;
      if (command.opcode == 21) {
        _motionQueue.dispatch(
          target: name,
          controller: actor,
          request: request,
          atUs: atUs,
          play: _playCharacterMotion,
        );
      } else {
        _playCharacterMotion(actor, request);
      }
    }
  }

  void parameterLoop(StoryDecodedCommand command, {required bool shortcut}) {
    update(currentStamp());
    final request = storyParameterLoopRequest(command, shortcut: shortcut);
    for (final name in command.targets) {
      final actor = _actors[name];
      if (actor == null) continue;
      if (request.stop) {
        actor.model.stopParameterLoop(fade: request.fade);
      } else if (request.motionName.isNotEmpty) {
        actor.model.playParameterLoop(request.motionName, fade: request.fade);
      }
    }
  }

  void characterControl(StoryDecodedCommand command, {required bool shortcut}) {
    update(currentStamp());
    _characterPresentation.characterControl(
      command,
      actors: _actors,
      shortcut: shortcut,
      apply: _applyCharacterPresentation,
    );
  }

  Future<void> brightness(
    StoryDecodedCommand command,
    Future<void> Function() delay,
    bool Function() currentCommand, {
    required int executionId,
  }) async {
    final value = command.numericParameter(0) ?? 1;
    final targets = command.targets
        .map((name) => _actors[name])
        .whereType<_WorldActor>()
        .toList();
    final position = command.payload['positionType'] as int? ?? 0;
    final layers = (command.payload['canvasLayers'] as List? ?? const [])
        .cast<num>();
    final pending = <Future<void>>[];
    if (targets.isEmpty && (position != 0 || layers.contains(2))) {
      final selected = _actors.values
          .where((a) => a.slot * 2 + 1 == position)
          .lastOrNull;
      if (selected == null) return;
      targets.add(selected);
    }
    await delay();
    if (!_alive() || !currentCommand()) return;
    for (final actor in targets) {
      pending.add(
        _sceneValue(
          'brightness:${actor.name}',
          actor.brightness,
          value,
          command,
          0,
          (v) => actor.brightness = v,
          executionId: executionId,
        ),
      );
    }
    if (layers.contains(0) ||
        (targets.isEmpty && layers.isEmpty && position == 0)) {
      pending.add(
        _sceneValue(
          'brightness:background',
          _backgroundBrightness,
          value,
          command,
          0,
          (v) => _backgroundBrightness = v,
          executionId: executionId,
        ),
      );
    }
    await Future.wait(pending);
  }

  Future<void> depthOfField(
    StoryDecodedCommand command,
    Future<void> Function() delay,
    bool Function() currentCommand, {
    required int executionId,
  }) async {
    final layers = (command.payload['canvasLayers'] as List? ?? const [])
        .cast<num>();
    final intensity = (command.numericParameter(0) ?? 0).clamp(0.0, 1.0);
    final ease = parseTweenEase(command.parameter(1));
    final routes = <(int, int)>[];
    if ((layers.isEmpty || layers.contains(2)) &&
        document.runtime['allowCharacterBlur'] == true) {
      final position = command.payload['positionType'] as int? ?? 0;
      final slots = position > 0
          ? {(position - 1) ~/ 2}
          : {
              for (final name in command.targets)
                if (_actors[name] != null) _actors[name]!.slot,
            };
      for (final slot in slots) {
        if (!_actors.values.any(
          (actor) => actor.slot == slot && actor.model.visible,
        )) {
          continue;
        }
        final generation = (_blurGenerations[slot] ?? 0) + 1;
        _blurGenerations[slot] = generation;
        _cameraTweens.remove('blur:slot:$slot')?.finish();
        routes.add((slot, generation));
      }
    }
    final background =
        layers.contains(0) && document.runtime['allowBackgroundBlur'] == true;
    final backgroundGeneration = background ? ++_backgroundBlurGeneration : 0;
    if (background) _cameraTweens.remove('blur:background')?.finish();
    if (!background && routes.isEmpty) return;
    await delay();
    if (!_alive() || !currentCommand()) return;
    update(currentStamp());
    _blurRadiusMax = StoryFieldBlur.radiusForCameraDistance(_focusDistance);
    final tasks = <Future<void>>[];
    if (background && backgroundGeneration == _backgroundBlurGeneration) {
      tasks.add(
        _sceneValue(
          'blur:background',
          _backgroundBlur,
          intensity,
          command,
          ease,
          (value) => _backgroundBlur = value,
          executionId: executionId,
        ),
      );
    }
    for (final (slot, generation) in routes) {
      if (_blurGenerations[slot] != generation) continue;
      tasks.add(
        _sceneValue(
          'blur:slot:$slot',
          _characterBlur.read(slot),
          intensity,
          command,
          ease,
          (value) => _characterBlur.write(slot, value),
          executionId: executionId,
        ),
      );
    }
    await Future.wait(tasks);
  }

  void _focusBlur(
    Map focus,
    int position,
    StoryDecodedCommand command,
    int ease, {
    required int executionId,
  }) {
    final backgroundEnabled =
        document.runtime['allowBackgroundBlur'] == true &&
        (_focusSettings!['_backgroundBlurEnabled'] == 1 ||
            _focusSettings!['_backgroundBlurEnabled'] == true);
    final charactersEnabled =
        document.runtime['allowCharacterBlur'] == true &&
        (_focusSettings!['_characterBlurEnabled'] == 1 ||
            _focusSettings!['_characterBlurEnabled'] == true);
    if (backgroundEnabled) {
      _backgroundBlurGeneration++;
      _cameraValue(
        'blur:background',
        _backgroundBlur,
        (focus['_backgroundBlurIntensity'] as num).toDouble().clamp(0.0, 1.0),
        command,
        ease,
        (value) => _backgroundBlur = value,
        executionId: executionId,
      );
    }
    if (charactersEnabled) {
      final focused =
          _actors[_characterPresentation.placements.nameAt(position)];
      for (final current in _characterPresentation.placements.positions) {
        if (current < 1 || current > 9 || current.isEven) continue;
        final slot = (current - 1) ~/ 2;
        final entrySlot = slot;
        _blurGenerations[slot] = (_blurGenerations[slot] ?? 0) + 1;
        _cameraValue(
          'blur:slot:$slot',
          _characterBlur.read(slot),
          focused != null && current != position
              ? (focus['_characterBlurIntensity'] as num).toDouble().clamp(
                  0.0,
                  1.0,
                )
              : 0,
          command,
          ease,
          (value) => _characterBlur.write(entrySlot, value),
          executionId: executionId,
        );
      }
    }
  }

  Float32List _headWorld(_WorldActor actor) =>
      _scene!.projection.modelPointWorld(
        slotIndex: actor.slot,
        basePosition: actor.basePosition,
        baseScale: actor.baseScale,
        point: actor.head,
      );

  Future<void> look(
    StoryDecodedCommand command,
    Future<void> Function() delay,
    bool Function() currentCommand, {
    required int executionId,
  }) async {
    update(currentStamp());
    final enabled = command.parameter(2)?.trim().toLowerCase() != 'stop';
    final prepared = <(_WorldActor, double, double)>[];
    _WorldActor? destination;
    if (command.opcode == 66 && enabled) {
      final position = command.payload['positionType'] as int? ?? 0;
      destination = _actors[_characterPresentation.placements.nameAt(position)];
      if (destination == null) return;
    }
    for (final name in command.targets) {
      final actor = _actors[name];
      if (actor == null) continue;
      double x = command.numericParameter(0) ?? 0;
      double y = command.numericParameter(1) ?? 0;
      if (enabled && destination != null) {
        final from = _headWorld(actor), to = _headWorld(destination);
        x = ((to[0] - from[0]) * .2).clamp(-1.0, 1.0);
        y = (to[1] - from[1]).clamp(-1.0, 1.0);
      }
      if (enabled && !actor.lookEnabled) {
        final original = actor.model.eyePosition;
        actor.originalLookX = actor.lookX = original.$1;
        actor.originalLookY = actor.lookY = original.$2;
        actor.lookEnabled = true;
        actor.model.setEyeLook(actor.lookX, actor.lookY);
      }
      if (!enabled) {
        x = actor.lookEnabled ? actor.originalLookX : 0;
        y = actor.lookEnabled ? actor.originalLookY : 0;
      }
      prepared.add((actor, x, y));
    }
    if (prepared.isEmpty) return;
    await delay();
    if (!_alive() || !currentCommand()) return;
    final pending = <Future<void>>[];
    for (final (actor, x, y) in prepared) {
      if (!identical(_actors[actor.name], actor)) continue;
      final intent = ++actor.lookIntent;
      actor.lookStopPending = !enabled;
      void write() {
        if (_durationUs(command) <= 0) {
          actor.model.forceEyeLook(actor.lookX, actor.lookY);
        } else {
          actor.model.setEyeLook(actor.lookX, actor.lookY);
        }
      }

      final tweens = [
        _sceneValue('look:${actor.name}:x', actor.lookX, x, command, 0, (v) {
          actor.lookX = v;
          write();
        }, executionId: executionId),
        _sceneValue('look:${actor.name}:y', actor.lookY, y, command, 0, (v) {
          actor.lookY = v;
          write();
        }, executionId: executionId),
      ];
      pending.add(
        Future.wait(tweens).then((_) {
          if (!enabled &&
              actor.lookIntent == intent &&
              _alive() &&
              currentCommand()) {
            actor.lookEnabled = false;
            actor.lookStopPending = false;
            actor.originalLookX = actor.originalLookY = 0;
            actor.model.setEyeLook(null, null);
          }
        }),
      );
    }
    await Future.wait(pending);
  }

  void update(NativeStoryUpdateStamp stamp) {
    if (_disposed) return;
    final previousStamp = _lastStamp;
    final previousSceneUs = _sceneUs;
    if (previousStamp != null &&
        stamp.updateIndex != previousStamp.updateIndex &&
        !stamp.paused) {
      _sceneUs +=
          math.max(0, stamp.storyUs - previousStamp.storyUs) * stamp.speed;
    }
    _lastStamp = stamp;
    _shakeUs = stamp.storyUs;
    final sceneUs = _sceneUs.round();
    for (final actor in _assets.values.expand((assets) => assets.values)) {
      final previous = actor.lastUs;
      final delta = previous == null
          ? 0.0
          : math.max(0, sceneUs - previous) / 1000000;
      actor.model.acceptedStep(
        frame: stamp.updateIndex,
        seconds: _sceneUs / 1000000,
        delta: delta,
        paused: stamp.paused,
      );
      actor.lastUs = sceneUs;
    }
    if (previousStamp != null &&
        stamp.updateIndex != previousStamp.updateIndex &&
        !stamp.paused &&
        timing().shortcut &&
        !_motionQueue.isEmpty) {
      _motionQueue.advance(
        (_sceneUs - previousSceneUs) / 1000000,
        showing: _motionControllerShowing,
        play: _playCharacterMotion,
      );
    }
    if (!stamp.paused) {
      _backgroundShake.update(_shakeUs);
      _characterShake.update(_shakeUs);
      _stillShake.update(_shakeUs);
      _talkShake.update(_shakeUs);
      _cameraShake.update(_shakeUs, stamp.updateIndex);
      _syncShakeOffsets();
      for (final wait in _shakeWaits.toList()) {
        if (wait.untilIdle
            ? _cameraShake.state == AuthoredCameraShakeState.idle
            : _shakeUs >= wait.untilUs) {
          _shakeWaits.remove(wait);
          wait.finish();
        }
      }
      for (final key in _cameraTweens.keys.toList()) {
        final tween = _cameraTweens[key]!;
        final t = ((_sceneUs - tween.startUs) / tween.durationUs).clamp(
          0.0,
          1.0,
        );
        tween.write(
          tween.from + (tween.to - tween.from) * sampleTweenEase(tween.ease, t),
        );
        if (t >= 1) {
          _cameraTweens.remove(key);
          tween.finish();
        }
      }
      for (final tween in _movementTweens.toList()) {
        final t = ((_sceneUs - tween.startUs) / tween.durationUs).clamp(
          0.0,
          1.0,
        );
        tween.write(sampleTweenEase(tween.ease, t));
        if (t >= 1) {
          _movementTweens.remove(tween);
          tween.finish();
        }
      }
      for (final actor in _actors.values) {
        if (actor.lookStopPending &&
            !_cameraTweens.containsKey('look:${actor.name}:x') &&
            !_cameraTweens.containsKey('look:${actor.name}:y')) {
          actor.lookStopPending = false;
          actor.lookEnabled = false;
          actor.originalLookX = actor.originalLookY = 0;
          actor.model.setEyeLook(null, null);
        }
        _characterPresentation.advanceFade(
          actor,
          visible: actor.model.visible,
          atUs: _sceneUs,
          apply: _applyCharacterPresentation,
        );
      }
    }
  }

  void _cameraValue(
    String key,
    double from,
    double to,
    StoryDecodedCommand command,
    int ease,
    void Function(double) write, {
    required int executionId,
  }) {
    _pendingCamera.add(
      _sceneValue(
        key,
        from,
        to,
        command,
        ease,
        write,
        executionId: executionId,
      ),
    );
  }

  Future<void> _sceneValue(
    String key,
    double from,
    double to,
    StoryDecodedCommand command,
    int ease,
    void Function(double) write, {
    int? durationUs,
    required int executionId,
  }) {
    _cameraTweens.remove(key)?.finish();
    final duration = _durationUs(command, overrideUs: durationUs);
    if (duration <= 0) {
      write(to);
      return Future.value();
    }
    final tween = _WorldTween(
      _sceneUs.round(),
      duration,
      from,
      to,
      ease,
      write,
      executionId: executionId,
      commandIndex: command.index,
      waitForCompletion: !command.noWait,
    );
    _cameraTweens[key] = tween;
    return tween.done.future;
  }

  Future<void> camera(
    StoryDecodedCommand command, {
    required int executionId,
  }) async {
    update(currentStamp());
    _pendingCamera.clear();
    final projection = _scene!.projection;
    var ease = parseTweenEase(command.parameter(1));
    final value = double.tryParse(command.parameter(0) ?? '') ?? 0;
    switch (command.opcode) {
      case 7:
        ease = parseTweenEase(
          command.parameter(1),
          fallback: _focusSettings!['_focusEase'] as int,
        );
        final distance = command.payload['cameraDistance'] as int;
        _focusDistance = distance;
        _cameraValue(
          'curvedLensRate',
          _curvedLensRate,
          StoryPostPasses.curvedRateForCameraDistance(distance),
          command,
          ease,
          (value) => _curvedLensRate = value,
          executionId: executionId,
        );
        final focus = (_focusSettings!['_focusData'] as List)
            .cast<Map>()
            .singleWhere((row) => row['_cameraDistance'] == distance);
        final authoredPosition = command.payload['positionType'] as int;
        final target = command.payload['targetName'] as String? ?? '';
        final controller = _actors[target];
        final namedPosition = controller == null
            ? null
            : _characterPresentation.placements.positionOf(target);
        final actor = namedPosition == null ? null : controller;
        final subjectPosition = controller == null
            ? authoredPosition
            : namedPosition ?? 0;
        _cameraValue(
          'blurRadius',
          _blurRadiusMax,
          StoryFieldBlur.radiusForCameraDistance(distance),
          command,
          ease,
          (value) => _blurRadiusMax = value,
          executionId: executionId,
        );
        _focusBlur(
          focus,
          subjectPosition,
          command,
          ease,
          executionId: executionId,
        );
        final x = authoredPosition == 0
            ? 0.0
            : projection.focusPointWorld(authoredPosition)[0];
        var y = (focus['_fieldZoomOffsetY'] as num).toDouble();
        if (actor != null) {
          y =
              _headWorld(actor)[1] -
              (focus['_characterHeadFocusOffsetY'] as num).toDouble();
        }
        _focusCamera.setAll(0, [x, y, 0]);
        _focusZoom = (focus['_fieldZoomRatio'] as num).toDouble();
        _cameraBase.setAll(0, _focusCamera);
        _panOffset.fillRange(0, 3, 0);
        for (var axis = 0; axis < 3; axis++) {
          final i = axis;
          _cameraValue(
            'position:$i',
            projection.cameraPosition[i],
            _focusCamera[i],
            command,
            ease,
            (v) {
              projection.cameraPosition[i] = v;
            },
            executionId: executionId,
          );
        }
        _cameraValue(
          'yaw',
          projection.cameraEuler[1],
          0,
          command,
          ease,
          (v) => projection.cameraEuler[1] = v,
          executionId: executionId,
        );
        for (var slot = 0; slot < projection.slotEuler.length; slot++) {
          final index = slot;
          _cameraValue(
            'slotYaw:$index',
            projection.slotEuler[index][1],
            0,
            command,
            ease,
            (v) => projection.slotEuler[index][1] = v,
            executionId: executionId,
          );
        }
        _cameraValue(
          'zoom',
          projection.zoomRatio,
          _focusZoom,
          command,
          ease,
          (v) => projection.zoomRatio = v,
          executionId: executionId,
        );
      case 50:
        _cameraValue(
          'roll',
          projection.cameraEuler[2],
          value,
          command,
          ease,
          (v) => projection.cameraEuler[2] = v,
          executionId: executionId,
        );
      case 34:
        _cameraValue(
          'pitch',
          projection.cameraEuler[0],
          -value,
          command,
          ease,
          (v) => projection.cameraEuler[0] = v,
          executionId: executionId,
        );
      case 33:
        _cameraValue(
          'yaw',
          projection.cameraEuler[1],
          value,
          command,
          ease,
          (v) => projection.cameraEuler[1] = v,
          executionId: executionId,
        );
        _cameraValue(
          'fieldYaw',
          projection.fieldEuler[1],
          value,
          command,
          ease,
          (v) {
            projection.fieldEuler[1] = projection.backgroundEuler[1] = v;
          },
          executionId: executionId,
        );
      case 67:
        final rate =
            command.numericParameter(2) ??
            (document.runtime['defaultPanV2FocusSlideRate'] as num?)
                ?.toDouble() ??
            .5;
        final distance = (projection.fieldPosition[2] - _focusCamera[2]).abs();
        final radius = (1 - rate) * distance;
        final radians = value * math.pi / 180;
        final offsets = [
          -radius * math.sin(radians),
          0.0,
          radius * (1 - math.cos(radians)),
        ];
        _cameraValue(
          'yaw',
          projection.cameraEuler[1],
          value,
          command,
          ease,
          (v) => projection.cameraEuler[1] = v,
          executionId: executionId,
        );
        for (var slot = 0; slot < projection.slotEuler.length; slot++) {
          final index = slot;
          _cameraValue(
            'slotYaw:$index',
            projection.slotEuler[index][1],
            value,
            command,
            ease,
            (v) => projection.slotEuler[index][1] = v,
            executionId: executionId,
          );
        }
        for (final axis in [0, 2]) {
          _panOffset[axis] = offsets[axis];
          _cameraValue(
            'position:$axis',
            projection.cameraPosition[axis],
            _cameraBase[axis] + offsets[axis],
            command,
            ease,
            (v) {
              projection.cameraPosition[axis] = v;
            },
            executionId: executionId,
          );
        }
      case 48:
        _cameraBase[0] = _focusCamera[0] + value;
        _panOffset[0] = 0;
        _cameraValue(
          'position:0',
          projection.cameraPosition[0],
          _cameraBase[0],
          command,
          ease,
          (v) {
            projection.cameraPosition[0] = v;
          },
          executionId: executionId,
        );
      case 47:
        _cameraBase[1] = _focusCamera[1] + value;
        _cameraValue(
          'position:1',
          projection.cameraPosition[1],
          _cameraBase[1],
          command,
          ease,
          (v) {
            projection.cameraPosition[1] = v;
          },
          executionId: executionId,
        );
      case 53:
        final ratio = _focusZoom * (value > 0 ? value : 1);
        final focusRows = (_focusSettings!['_focusData'] as List).cast<Map>();
        final closest = focusRows.reduce(
          (left, right) =>
              ((right['_fieldZoomRatio'] as num).toDouble() - ratio).abs() <
                  ((left['_fieldZoomRatio'] as num).toDouble() - ratio).abs()
              ? right
              : left,
        );
        _focusDistance = closest['_cameraDistance'] as int;
        _cameraValue(
          'curvedLensRate',
          _curvedLensRate,
          StoryPostPasses.curvedRateForCameraDistance(_focusDistance),
          command,
          ease,
          (value) => _curvedLensRate = value,
          executionId: executionId,
        );
        _cameraValue(
          'blurRadius',
          _blurRadiusMax,
          StoryFieldBlur.radiusForCameraDistance(_focusDistance),
          command,
          ease,
          (value) => _blurRadiusMax = value,
          executionId: executionId,
        );
        final offsetText = command.parameter(2)?.trim() ?? '';
        final backgroundEnabled =
            document.runtime['allowBackgroundBlur'] == true &&
            (_focusSettings!['_backgroundBlurEnabled'] == 1 ||
                _focusSettings!['_backgroundBlurEnabled'] == true);
        if (backgroundEnabled && offsetText.toLowerCase() != 'sharp') {
          _backgroundBlurGeneration++;
          final intensity =
              ((closest['_backgroundBlurIntensity'] as num).toDouble() +
                      (double.tryParse(offsetText) ?? 0))
                  .clamp(0.0, 1.0);
          _cameraValue(
            'blur:background',
            _backgroundBlur,
            intensity,
            command,
            ease,
            (value) => _backgroundBlur = value,
            executionId: executionId,
          );
        }
        _cameraValue(
          'zoom',
          projection.zoomRatio,
          ratio,
          command,
          ease,
          (v) => projection.zoomRatio = v,
          executionId: executionId,
        );
      default:
        throw UnsupportedError('story_camera_command:${command.opcode}');
    }
    final operations = List<Future<void>>.of(_pendingCamera);
    _pendingCamera.clear();
    await Future.wait(operations);
  }

  Future<void> angle(
    StoryDecodedCommand command,
    Future<void> Function() delay,
    bool Function() currentCommand, {
    required int executionId,
  }) async {
    update(currentStamp());
    final target = command.payload['targetName'] as String? ?? '';
    final actor = _actors[target];
    if (actor == null) return;
    actor.model.setAngleOffsets(actor.headAngle, actor.bodyAngle);
    await delay();
    if (!_alive() || !currentCommand() || !identical(_actors[target], actor)) {
      return;
    }
    update(currentStamp());
    void write() {
      if (_durationUs(command) <= 0) {
        actor.model.forceAngleOffsets(actor.headAngle, actor.bodyAngle);
      } else {
        actor.model.setAngleOffsets(actor.headAngle, actor.bodyAngle);
      }
    }

    await Future.wait([
      _sceneValue(
        'angle:$target',
        actor.headAngle,
        command.numericParameter(0) ?? 0,
        command,
        7,
        (value) {
          actor.headAngle = value;
          write();
        },
        executionId: executionId,
      ),
      _sceneValue(
        'bodyAngle:$target',
        actor.bodyAngle,
        command.numericParameter(1) ?? 0,
        command,
        7,
        (value) {
          actor.bodyAngle = value;
          write();
        },
        executionId: executionId,
      ),
    ]);
  }

  Future<void> moveToDirection(
    StoryDecodedCommand command, {
    required int executionId,
  }) async {
    update(currentStamp());
    final position = command.payload['positionType'] as int;
    if (position < 1 || position > 9 || position.isEven) {
      throw ArgumentError('story_character_position:$position');
    }
    final index = (position - 1) ~/ 2;
    final slot = _scene!.projection.slots[index];
    final movement = storyCharacterMovement(command);
    final from = Float32List.fromList(slot);
    final to = Float32List.fromList([
      for (var axis = 0; axis < 3; axis++) from[axis] + movement.offset[axis],
    ]);
    void write(double progress) {
      for (var axis = 0; axis < 3; axis++) {
        slot[axis] = from[axis] + (to[axis] - from[axis]) * progress;
      }
      if (movement.sortDepth) _sortCharacterDepths(resetPriority: true);
    }

    final durationUs = _durationUs(command);
    if (durationUs <= 0) {
      write(1);
      return;
    }
    final tween = _WorldTween(
      _sceneUs.round(),
      durationUs,
      0,
      1,
      StoryCharacterMovement.ease,
      write,
      executionId: executionId,
      commandIndex: command.index,
      waitForCompletion: !command.noWait,
      descriptor: {
        'slot': index,
        'from': from.toList(),
        'to': to.toList(),
        'sortDepth': movement.sortDepth,
      },
    );
    _movementTweens.add(tween);
    await tween.done.future;
  }

  void _sortCharacterDepths({bool resetPriority = false}) {
    if (resetPriority) _characterPresentation.order.reset();
    for (final actor in _actors.values) {
      if (!actor.model.visible) continue;
      actor.sortingDepth = _scene!.projection.modelPointWorld(
        slotIndex: actor.slot,
        basePosition: actor.basePosition,
        baseScale: actor.baseScale,
        point: Float32List(3),
      )[2];
    }
  }

  List<_WorldActor> get _orderedActors =>
      _characterPresentation.order.orderByDepth(
        _actors.values,
        slot: (actor) => actor.slot,
        worldDepth: (actor) => actor.sortingDepth,
      );

  NativeStoryColourLayer snapshot(
    NativeStoryUpdateStamp stamp,
    int width,
    int height,
  ) {
    if (_scene == null) throw StateError('story_world_not_prepared');
    update(stamp);
    final projection = _scene!.projection..resize(width, height);
    final meshes = <String, ProjectedMesh>{},
        materials = <String, NativeMaterial>{};
    final targets = <String, NativeTarget>{
      'world:main': NativeTarget(
        width: width,
        height: height,
        format: NativeTargetFormat.rgba16f,
        alpha: NativeTextureAlpha.independent,
      ),
    };
    final passes = <NativePass>[],
        draws = <NativeDraw>[],
        textures = <String, Uri>{};
    final stage = _stage;
    if (stage != null && _background != null) {
      final sprite = stage.backgroundSprite['data'] as Map;
      final rect = sprite['m_Rect'] as Map, pivot = sprite['m_Pivot'] as Map;
      final ppu = (sprite['m_PixelsToUnits'] as num).toDouble();
      final w = (rect['width'] as num).toDouble() / ppu;
      final h = (rect['height'] as num).toDouble() / ppu;
      final l = -(pivot['x'] as num).toDouble() * w;
      final b = -(pivot['y'] as num).toDouble() * h;
      final geometry = NativeSpriteGeometry(
        positions: Float32List.fromList([
          l,
          b,
          0,
          l,
          b + h,
          0,
          l + w,
          b + h,
          0,
          l + w,
          b,
          0,
        ]),
        uv: Float32List.fromList([0, 1, 0, 0, 1, 0, 1, 1]),
        indices: Uint16List.fromList([0, 1, 2, 0, 2, 3]),
      );
      final color = stage.component['_backgroundColor'] as Map;
      meshes['world:background'] = projectSprite(
        geometry,
        projection.clipFromBackground(
          localPosition: _scene!.backgroundLocalPosition,
          localEuler: _scene!.backgroundLocalEuler,
          localScale: 1,
        ),
        Float32List.fromList([
          for (final key in ['r', 'g', 'b', 'a'])
            (color[key] as num).toDouble() *
                (key == 'a' ? 1 : _backgroundBrightness),
        ]),
      );
      final textureKey = 'world:background:${stage.ref}';
      textures[textureKey] = _background!;
      materials['world:background'] = NativeMaterial(
        texture: textureKey,
        textureAlpha: NativeTextureAlpha.premultiplied,
        blend: NativeBlend.premultipliedAlpha,
      );
      const backgroundDraw = NativeDraw(
        mesh: 'world:background',
        material: 'world:background',
      );
      if (_backgroundBlur > .01) {
        const key = 'world:background-blur';
        targets[key] = NativeTarget(
          width: width,
          height: height,
          format: NativeTargetFormat.rgba16f,
        );
        passes.add(
          NativePass(
            target: key,
            draws: [backgroundDraw],
            clearColor: _scene!.cameraClearRgba,
          ),
        );
        passes.addAll(
          StoryFieldBlur.append(
            prefix: key,
            sourceTarget: key,
            width: width,
            height: height,
            intensity: _backgroundBlur,
            radiusMax: _blurRadiusMax,
            meshes: meshes,
            materials: materials,
            targets: targets,
          ),
        );
        meshes['$key:composite'] = StoryFieldBlur.fullscreen();
        materials['$key:composite'] = NativeMaterial(
          texture: key,
          textureAlpha: NativeTextureAlpha.premultiplied,
          blend: NativeBlend.opaque,
        );
        draws.add(
          const NativeDraw(mesh: '$key:composite', material: '$key:composite'),
        );
      } else {
        draws.add(backgroundDraw);
      }
    }
    final orderedActors = _orderedActors;
    final lighting = _characterLighting;
    final groups = <List<_WorldActor>>[];
    for (final actor in orderedActors) {
      if (!actor.model.visible) continue;
      if (actor.opacity <= .0001) continue;
      final previous = groups.lastOrNull?.first;
      if (previous != null &&
          (previous.blur - actor.blur).abs() < .000001 &&
          (previous.opacity - actor.opacity).abs() < .000001 &&
          (previous.brightness - actor.brightness).abs() < .000001) {
        groups.last.add(actor);
      } else {
        groups.add([actor]);
      }
    }
    for (final (index, group) in groups.indexed) {
      final settings = group.first;
      final isolated =
          settings.blur > .0001 ||
          (settings.opacity - 1).abs() > .000001 ||
          (settings.brightness - 1).abs() > .000001;
      final groupDraws = <NativeDraw>[];
      for (final actor in group) {
        final keys = {
          for (final entry in actor.textures.entries)
            entry.key: 'model:${actor.key}:texture:${entry.key}',
        };
        for (final entry in actor.textures.entries) {
          textures[keys[entry.key]!] = entry.value;
        }
        final generated = buildNativeCubismMeshes(
          modelKey: actor.name,
          evaluated: actor.model.displayed,
          clipTransform: projection.clipFromModel(
            slotIndex: actor.slot,
            basePosition: actor.basePosition,
            baseScale: actor.baseScale,
          ),
          textureKeys: keys,
          maskTextureSize: actor.model.maskTextureSize,
          meshes: meshes,
          materials: materials,
          modelOpacity: (isolated ? 1 : actor.opacity) * actor.model.opacity,
          brightness: isolated ? 1 : actor.brightness,
          lightingRgb: lighting == null
              ? const [1, 1, 1]
              : lighting.factorForModel(
                  projection.modelWorld(
                    slotIndex: actor.slot,
                    basePosition: actor.basePosition,
                    baseScale: actor.baseScale,
                  ),
                ),
        );
        passes.addAll(generated.maskPasses);
        groupDraws.addAll(generated.draws);
        targets.addAll(generated.targets);
      }
      if (groupDraws.isEmpty) {
        continue;
      }
      if (isolated) {
        final key = 'world:character-group:$index';
        targets[key] = NativeTarget(
          width: width,
          height: height,
          format: NativeTargetFormat.rgba16f,
        );
        passes.add(NativePass(target: key, draws: groupDraws));
        if (settings.blur > .0001) {
          passes.addAll(
            StoryFieldBlur.append(
              prefix: key,
              sourceTarget: key,
              width: width,
              height: height,
              intensity: settings.blur,
              radiusMax: _blurRadiusMax,
              meshes: meshes,
              materials: materials,
              targets: targets,
            ),
          );
        }
        meshes['$key:composite'] = StoryFieldBlur.fullscreen(
          alpha: settings.opacity,
          brightness: settings.brightness,
        );
        materials['$key:composite'] = NativeMaterial(
          texture: key,
          textureAlpha: NativeTextureAlpha.premultiplied,
          blend: NativeBlend.premultipliedAlpha,
        );
        draws.add(
          NativeDraw(mesh: '$key:composite', material: '$key:composite'),
        );
      } else {
        draws.addAll(groupDraws);
      }
    }
    passes.add(
      NativePass(
        target: 'world:main',
        draws: draws,
        clearColor: _scene!.cameraClearRgba,
      ),
    );
    var contentTarget = 'world:main';
    Map<String, NativeTextureData> dataTextures = const {};
    void Function()? onPresented;
    if (_stage != null) {
      final plan = _postPasses.append(
        prefix: 'world:post',
        sourceTarget: 'world:main',
        width: width,
        height: height,
        settings: _postVolume!.resolve(),
        meshes: meshes,
        materials: materials,
        targets: targets,
        cameraDistance: _focusDistance,
        curvedLensRate: _curvedLensRate,
      );
      passes.addAll(plan.passes);
      dataTextures = plan.dataTextures;
      onPresented = () => _postPasses.didPresent(plan.presentationTicket);
      contentTarget = 'world:content';
      targets[contentTarget] = NativeTarget(width: width, height: height);
      meshes['world:post-composite'] = StoryFieldBlur.fullscreen();
      materials['world:post-composite'] = NativeMaterial(
        texture: plan.target,
        textureAlpha: NativeTextureAlpha.independent,
        blend: NativeBlend.opaque,
      );
      passes.add(
        NativePass(
          target: contentTarget,
          draws: [
            const NativeDraw(
              mesh: 'world:post-composite',
              material: 'world:post-composite',
            ),
          ],
        ),
      );
    }
    final identity = document.chapter.sourceIdentity;
    return NativeStoryColourLayer(
      sortingOrder: 300,
      replacesBackground: _stage != null,
      clearColor: _scene!.cameraClearRgba,
      contentTarget: contentTarget,
      scene: NativeSceneResources(
        epoch: epoch,
        source: RenderSource(
          server: identity.server,
          release: identity.release,
          document: identity.document,
        ),
        meshes: meshes,
        materials: materials,
        targets: targets,
      ),
      frame: NativeFrame(
        epoch: epoch,
        mediaMicroseconds: stamp.storyUs,
        outputTarget: contentTarget,
        passes: passes,
      ),
      textures: textures,
      dataTextures: dataTextures,
      onPresented: onPresented,
    );
  }

  Map<String, Object?> get observation => {
    'core': _core?.capabilityRecord(),
    'preparation': {
      'completedModels': _preparedModels,
      'totalModels': _preparationModels,
      'cachedModels': _actorResources.length,
      'timings': _preparationTimings,
    },
    'motionSync': {
      'engineVersion': _voiceEngineVersion,
      'error': _voiceError?.toString(),
      'voices': {
        for (final entry in _voiceBindings.entries)
          '${entry.key.name}:${entry.key.key}:${entry.key.assetIndex}': {
            'cueId': entry.value.cue.id,
            'instanceId': entry.value.cue.instanceId,
            'commandIndex': entry.value.cue.commandIndex,
            'ready': entry.value.voice != null,
            'failed': entry.value.failed,
            'positionFrames': entry.value.frame?.positionFrames,
            'analyzedFrames': entry.value.frame?.analyzedFrames,
            'parameterIds': entry.value.frame?.parameterIds,
            'values': entry.value.frame?.values.toList(),
            'neutral': entry.key.motionSync?.neutral,
          },
      },
    },
    'projection': _scene?.projection.observation,
    'stage': _stage?.ref,
    'lighting': {
      'environment': _lightEnvironment,
      'quality': (document.runtime['baseQualityMode'] as num?)?.toInt() ?? 3,
      'enabled': _characterLighting?.enabled ?? false,
      'activeLights': _characterLighting?.lights.length ?? 0,
      'actors': {
        if (_scene != null)
          for (final actor in _orderedActors)
            if (actor.model.visible)
              actor.name:
                  _characterLighting
                      ?.factorForModel(
                        _scene!.projection.modelWorld(
                          slotIndex: actor.slot,
                          basePosition: actor.basePosition,
                          baseScale: actor.baseScale,
                        ),
                      )
                      .toList() ??
                  const [1, 1, 1],
      },
    },
    'characterPriorityOrder': _characterPresentation.order.slots,
    'characterPlacement': _characterPresentation.placements.observation,
    'eyeBlinkStoppedTargets': _characterPresentation.controls.snapshot(),
    'characterDrawOrder': [
      for (final actor in _orderedActors)
        if (actor.model.visible) actor.name,
    ],
    'activeMovements': _movementTweens.length,
    'motionWaits': [
      for (final entry in _motionQueue.snapshot())
        {
          'commandIndex': entry.request.commandIndex,
          'target': entry.target,
          'key': entry.controller.key,
          'assetIndex': entry.controller.assetIndex,
          'remainingSeconds': entry.remainingSeconds,
          'motion': entry.request.motionName,
          'expression': entry.request.expressionName,
        },
    ],
    'fieldBlur': {'background': _backgroundBlur, 'radiusMax': _blurRadiusMax},
    'post': {
      'environment': _postEnvironment,
      'weights': _postWeights,
      'curvedLensRate': _curvedLensRate,
      'defaultSource': 'formal-Play1.0.3',
    },
    'shake': {
      'generation': _shakeGeneration,
      'background': _backgroundShake.offset.toList(),
      'character': _characterShake.offset.toList(),
      'still': _stillShake.offset.toList(),
      'talk': _talkShake.offset.toList(),
      'camera': _cameraShake.offset.toList(),
      'cameraState': _cameraShake.state.name,
    },
    'actors': {
      for (final actor in _actors.values)
        actor.name: {
          'key': actor.key,
          'assetIndex': actor.assetIndex,
          'visible': actor.model.visible,
          'slot': actor.slot,
          'sortingDepth': actor.sortingDepth,
          'lookEnabled': actor.lookEnabled,
          'look': [actor.lookX, actor.lookY],
          'eyeParameters': [
            actor.model.eyePosition.$1,
            actor.model.eyePosition.$2,
          ],
          'opacity': actor.opacity,
          'brightness': actor.brightness,
          'blur': actor.blur,
          'angle': [actor.headAngle, actor.bodyAngle],
          'capability': actor.model.capability,
          'drawables': actor.model.displayed.length,
          'frame': actor.model.acceptedFrame,
          'controls': actor.model.sourceControlObservation,
        },
    },
  };
  void close() {
    clearVoiceBindings();
    _disposed = true;
    final voiceEngine = _voiceEngine;
    if (voiceEngine != null) {
      unawaited(
        voiceEngine.then<void>(
          (engine) => engine.dispose(),
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
    _voiceChannels.clear();
    resetShakes();
    for (final tween in _cameraTweens.values) {
      tween.finish();
    }
    _cameraTweens.clear();
    for (final tween in _movementTweens) {
      tween.finish();
    }
    _movementTweens.clear();
    for (final actor in _ownedActors) {
      actor.model.dispose();
    }
    _ownedActors.clear();
    _actorResources.clear();
    _actorSources.clear();
    _assets.clear();
    _actors.clear();
    _motionQueue.clear();
  }
}

final class _WorldVoiceBinding {
  _WorldVoiceBinding(this.cue);
  final NativeStoryMediaCue cue;
  MotionSyncController? channel;
  MotionSyncVoice? voice;
  MotionSyncFrame? frame;
  int positionFrames = -1;
  bool failed = false;
}

final class _WorldShakeWait {
  _WorldShakeWait({
    required this.untilUs,
    required this.untilIdle,
    this.executionId,
    this.commandIndex,
    this.waitForCompletion,
  });
  int? executionId;
  final int? commandIndex;
  final bool? waitForCompletion;
  final int untilUs;
  final bool untilIdle;
  final done = Completer<void>();
  _WorldShakeWait copy() => _WorldShakeWait(
    untilUs: untilUs,
    untilIdle: untilIdle,
    executionId: executionId,
    commandIndex: commandIndex,
    waitForCompletion: waitForCompletion,
  );
  void finish() {
    if (!done.isCompleted) done.complete();
  }
}

final class _WorldActorResource {
  _WorldActorResource(this.actor, this.restoreInitial);
  final _WorldActor actor;
  final void Function() restoreInitial;
}

final class _WorldActor extends StoryCharacterPresentationState {
  _WorldActor(
    this.name,
    this.key,
    this.assetIndex,
    this.model,
    this.basePosition,
    this.baseScale,
    this.head,
    this.textures,
    this.blurChannels,
    this.sourceFingerprint,
    this.motionSync,
  );
  final String name, key;
  final String sourceFingerprint;
  final MotionSyncProfile? motionSync;
  final int assetIndex;
  final NativeCubismModelHost model;
  final Float32List basePosition, head;
  final double baseScale;
  final Map<int, Uri> textures;
  final StoryCharacterBlurChannels blurChannels;
  int? lastUs;
  double get blur => blurChannels.read(slot);
  double headAngle = 0, bodyAngle = 0;
  bool lookEnabled = false;
  bool lookStopPending = false;
  int lookIntent = 0;
  double lookX = 0, lookY = 0, originalLookX = 0, originalLookY = 0;
  void Function() captureCheckpoint() {
    final modelState = model.snapshot();
    final values = (
      slot,
      fadeStart,
      fadeDuration,
      lastUs,
      opacity,
      from,
      to,
      brightness,
      sortingDepth,
      headAngle,
      bodyAngle,
      lookEnabled,
      lookIntent,
      lookX,
      lookY,
      originalLookX,
      originalLookY,
      lookStopPending,
    );
    return () {
      model.restore(modelState);
      slot = values.$1;
      fadeStart = values.$2;
      fadeDuration = values.$3;
      lastUs = values.$4;
      opacity = values.$5;
      from = values.$6;
      to = values.$7;
      brightness = values.$8;
      sortingDepth = values.$9;
      headAngle = values.$10;
      bodyAngle = values.$11;
      lookEnabled = values.$12;
      lookIntent = values.$13;
      lookX = values.$14;
      lookY = values.$15;
      originalLookX = values.$16;
      originalLookY = values.$17;
      lookStopPending = values.$18;
    };
  }
}

final class _WorldTween {
  _WorldTween(
    this.startUs,
    this.durationUs,
    this.from,
    this.to,
    this.ease,
    this.write, {
    this.descriptor,
    this.executionId,
    this.commandIndex,
    this.waitForCompletion,
  });
  final int startUs, durationUs, ease;
  final double from, to;
  final void Function(double) write;
  final Map<String, Object?>? descriptor;
  int? executionId;
  final int? commandIndex;
  final bool? waitForCompletion;
  final done = Completer<void>();
  _WorldTween copy() => _WorldTween(
    startUs,
    durationUs,
    from,
    to,
    ease,
    write,
    descriptor: descriptor,
    executionId: executionId,
    commandIndex: commandIndex,
    waitForCompletion: waitForCompletion,
  );
  void finish() {
    if (!done.isCompleted) done.complete();
  }
}

final class NativeStoryWorldCheckpoint {
  NativeStoryWorldCheckpoint._(
    this._owner,
    this.sourceIdentity,
    this.sourceEpoch,
    this.textureReferences,
    this.modelIdentities,
    this._restore,
  );
  final StorySourceIdentity sourceIdentity;
  final Object _owner;
  final int sourceEpoch;
  final List<Uri> textureReferences;
  final Map<String, String> modelIdentities;
  final void Function() _restore;
}

final class _ProjectionCheckpoint {
  _ProjectionCheckpoint(NativeCubismWorldProjection projection)
    : vectors = [
        for (final value in _vectors(projection)) Float32List.fromList(value),
      ],
      scalars = (
        projection.fieldOfView,
        projection.zoomRatio,
        projection.slotScale,
        projection.backgroundScale,
      );
  final List<Float32List> vectors;
  final (double, double, double, double) scalars;
  static List<Float32List> _vectors(NativeCubismWorldProjection projection) => [
    projection.cameraPosition,
    projection.cameraEuler,
    projection.cameraOffset,
    projection.fieldEuler,
    projection.backgroundEuler,
    projection.fieldOffset,
    projection.backgroundOffset,
    projection.fieldPosition,
    projection.backgroundPosition,
    ...projection.slots,
    ...projection.focusPoints,
    ...projection.slotEuler,
  ];
  void restore(NativeCubismWorldProjection projection) {
    final destinations = _vectors(projection);
    for (var i = 0; i < vectors.length; i++) {
      destinations[i].setAll(0, vectors[i]);
    }
    projection.fieldOfView = scalars.$1;
    projection.zoomRatio = scalars.$2;
    projection.slotScale = scalars.$3;
    projection.backgroundScale = scalars.$4;
  }
}
