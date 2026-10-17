import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show
        haneokaShaderBundle,
        loadHaneokaProfileAsset,
        loadHaneokaProfileTexture;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vega_plugin_haneoka/render_profile.dart';
import 'package:vega_renderer_flutter/vega_renderer_flutter.dart';

import 'native_story_document.dart';
import 'native_numeric_texture.dart';
import 'native_story_colour_host.dart';
import 'native_story_frame_data.dart';
import 'native_story_playback.dart';

/// Pure updates consume the one actual captured player stamp synchronously.
/// GPU submissions occur in the ordinary widget phase, after command state
/// continuations, using that same source-scoped clock observation.
final class NativeStoryFrameHost {
  NativeStoryFrameHost({
    required this.document,
    StoryRenderProfileBinding? renderProfile,
    required this.data,
    required this.epoch,
    required this.fetch,
    required NativeStoryUpdateStamp initialStamp,
    required int actualFadeEase,
    required this.resolvePlanarClip,
  }) {
    if (initialStamp.sourceEpoch != epoch) {
      throw const FormatException('native_frame_initial_epoch');
    }
    playback = StoryFramePlayback(
      sourceIdentity: document.chapter.sourceIdentity,
      sourceEpoch: epoch,
      actualFrames: data.frames,
      actualSnapshotCatalog: data.snapshotCatalog,
      renderProfile: renderProfile,
      actualFadeEase: actualFadeEase,
      actualStoryUs: initialStamp.storyUs,
      actualUpdateIndex: initialStamp.updateIndex,
      currentSpeed: initialStamp.speed,
      actualLayoutResolver: (source, poses) {
        final metrics = _metrics;
        if (metrics == null) {
          throw StateError('native_frame_viewport_not_ready');
        }
        return StoryFrameGeometry.layoutAt(
          source,
          poses,
          actualCanvasWidth: metrics.width,
          actualCanvasHeight: metrics.height,
        );
      },
    );
  }
  final NativeStoryDocument document;
  final NativeStoryFrameData data;
  final int epoch;
  final Future<Uint8List> Function(Uri) fetch;
  final Float32List Function(StoryFrameCanvasMetrics) resolvePlanarClip;
  late final StoryFramePlayback playback;
  final _particles = StoryFrameParticleProjector();
  Map<String, NativeTextureData> _dataTextures = const {};
  Map<String, NativeTextureData> get dataTextures => _dataTextures;
  Future<void>? _resourceWork;
  final _renderWork = <Future<void>>{};
  VegaRenderSession? _session;
  StoryFrameCanvasMetrics? _metrics;
  StoryFrameRenderSnapshot? _last;
  NativeStoryColourHost? _sharedOwner;
  int _intent = 0, _width = 0, _height = 0, _frames = 0;
  bool _disposed = false, _presenting = false, _renderedVisible = false;
  ValueListenable<ui.Image?>? get image => _session?.image;
  bool get hasRenderedFrame =>
      (_last?.frame.passes.any((pass) => pass.draws.isNotEmpty) ?? false) &&
      (_session?.image.value != null || _sharedOwner?.hasCurrentImage == true);

  Future<void> prepare(bool Function() current) async {
    await (_resourceWork ??= _prepare(current));
  }

  Future<void> _prepare(bool Function() current) async {
    final plan = StoryFramePreparationPlan.forChapter(
      document.chapter,
      data.frames,
    );
    final straightBytes = <String, Uint8List>{};
    for (final entry in plan.texturesByHash.entries) {
      final expected = entry.key, texture = entry.value;
      final bytes = await fetch(document.assets.pinned(texture));
      if (_disposed || !current()) throw StateError('story_source_replaced');
      if (sha256.convert(bytes).toString() != expected) {
        throw StateError('native_frame_actual_texture_hash:$texture');
      }
      for (final straight in plan.straightTexturePaths.entries) {
        if (straight.value == texture) straightBytes[straight.key] = bytes;
      }
    }
    if (straightBytes.length != plan.straightTexturePaths.length) {
      throw StateError('native_frame_straight_texture_unprepared');
    }
    final decoded = straightBytes.isEmpty
        ? const <String, NativeTextureData>{}
        : await decodeNativeNumericTextures(
            straightBytes,
            alpha: NativeTextureAlpha.straight,
          );
    if (_disposed || !current()) throw StateError('story_source_replaced');
    _dataTextures = Map.unmodifiable(decoded);
  }

  Future<void> settleResources() async {
    final work = _resourceWork;
    if (work == null || _disposed) {
      throw StateError('native_frame_resources_unprepared');
    }
    await work;
    if (_disposed) throw StateError('story_source_replaced');
  }

  Map<String, Object?> snapshotData() => snapshot().toData();
  Future<void> restoreData(
    Map saved, {
    required NativeStoryUpdateStamp stamp,
  }) async {
    if (_disposed ||
        saved['version'] != 1 ||
        StorySourceIdentity.fromJson(saved['source'] as Map) !=
            document.chapter.sourceIdentity ||
        stamp.sourceEpoch != epoch) {
      throw const FormatException('native_frame_data_source');
    }
    final hashes = Map<String, String>.from(saved['hashes'] as Map);
    final value = playback.decodeSnapshotData(
      saved['playback'] as Map,
      actualPacketHashes: hashes,
    );
    await prepare(() => !_disposed);
    await quiesce();
    _watchRestored(
      playback.restore(
        value,
        actualStoryUs: stamp.storyUs,
        actualUpdateIndex: stamp.updateIndex,
        paused: stamp.paused,
      ),
    );
    _last = null;
    await settleResources();
  }

  NativeStoryFrameHostSnapshot snapshot() {
    if (_disposed) throw StateError('story_source_replaced');
    return NativeStoryFrameHostSnapshot(
      document.chapter.sourceIdentity,
      epoch,
      Map.unmodifiable(data.hashes),
      playback.snapshot(),
    );
  }

  Future<void> quiesce() async {
    ++_intent;
    final state = playback.snapshot();
    _watchRestored(playback.restore(state));
    await Future.wait(_renderWork.toList());
    await settleResources();
  }

  Future<void> restore(
    NativeStoryFrameHostSnapshot snapshot, {
    required NativeStoryUpdateStamp stamp,
  }) async {
    if (_disposed ||
        snapshot.sourceIdentity != document.chapter.sourceIdentity ||
        snapshot.sourceEpoch != epoch ||
        stamp.sourceEpoch != epoch ||
        snapshot.sourceHashes.length != data.hashes.length ||
        !data.hashes.entries.every(
          (entry) => snapshot.sourceHashes[entry.key] == entry.value,
        )) {
      throw const FormatException('native_frame_snapshot_source');
    }
    await quiesce();
    _watchRestored(
      playback.restore(
        snapshot.playback,
        actualStoryUs: stamp.storyUs,
        actualUpdateIndex: stamp.updateIndex,
        paused: stamp.paused,
      ),
    );
    _last = null;
  }

  void _watchRestored(Map<int, StoryDispatchOperation> operations) {
    for (final entry in operations.entries) {
      final operation = entry.value;
      unawaited(
        operation.completion.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
  }

  Future<StoryDispatchCompletion>? pendingCompletionForExecution(
    int executionId, {
    int? legacyCommandIndex,
  }) => playback.pendingCompletionForExecution(
    executionId,
    legacyCommandIndex: legacyCommandIndex,
  );

  void actualUpdate(NativeStoryUpdateStamp stamp) {
    if (_disposed || stamp.sourceEpoch != epoch) return;
    playback.advance(
      stamp.storyUs,
      speed: stamp.speed,
      paused: stamp.paused,
      epoch: epoch,
      actualUpdateIndex: stamp.updateIndex,
    );
  }

  StoryDispatchOperation dispatch(
    StoryDecodedCommand command,
    StoryDispatchContext context,
    NativeStoryUpdateStamp stamp,
    List<String> actualLocalizedTargetTexts,
  ) {
    if (_disposed || stamp.sourceEpoch != epoch || !context.isCurrent()) {
      throw StateError('story_source_replaced');
    }
    if (_metrics == null) throw StateError('native_frame_viewport_not_ready');
    if (actualLocalizedTargetTexts.isNotEmpty) {
      throw UnsupportedError('native_frame_text_receiver_pending');
    }
    return playback.dispatch(
      command,
      stamp.storyUs,
      stamp.speed,
      stamp.updateIndex,
      localizedTargetTexts: actualLocalizedTargetTexts,
      executionId: context.executionId,
    );
  }

  void cancelDelay() {
    if (!_disposed) playback.cancelDelay();
  }

  StoryFrameRenderSnapshot snapshotForColour(NativeStoryUpdateStamp stamp) {
    if (_disposed || stamp.sourceEpoch != epoch || _metrics == null) {
      throw StateError('native_frame_colour_actual_update_pair');
    }
    final frame = playback.frame;
    if (stamp.updateIndex != frame.actualUpdateIndex ||
        stamp.storyUs != frame.actualStoryUs) {
      throw StateError('native_frame_colour_actual_update_pair');
    }
    return _snapshot(sharedColour: true, playbackFrame: frame);
  }

  Future<void> retireSurfaceForColour() async {
    final session = _session;
    _session = null;
    await session?.dispose();
  }

  void configureColourViewport(int width, int height) {
    if (_disposed) throw StateError('story_source_replaced');
    _width = width;
    _height = height;
    _metrics = data.metrics(width, height);
  }

  void recordColourPresentation(
    StoryFrameRenderSnapshot snapshot,
    NativeStoryColourHost owner,
  ) {
    if (!owner.containsSubmittedLayer(303, snapshot.scene, snapshot.frame)) {
      throw StateError('native_frame_colour_submission_missing');
    }
    _last = snapshot;
    _sharedOwner = owner;
    _frames++;
  }

  StoryFrameRenderSnapshot _snapshot({
    bool sharedColour = false,
    StoryFramePlaybackFrame? playbackFrame,
  }) {
    final snapshot = compileStoryFrame(
      playback: playbackFrame ?? playback.frame,
      metrics: _metrics!,
      actualViewPivot: data.viewPivot,
      actualPlanarClip: resolvePlanarClip(_metrics!),
      width: _width,
      height: _height,
      source: RenderSource(
        server: document.chapter.sourceIdentity.server,
        release: document.chapter.sourceIdentity.release,
        document: document.chapter.sourceIdentity.document,
      ),
      sourceId: data.snapshotCatalog.sourceId,
      sharedColour: sharedColour,
      particleProjector: _particles,
      resolveTexture: document.assets.pinned,
      resolveTiledSource: data.tiledSource,
    );
    return StoryFrameRenderSnapshot(snapshot.scene, snapshot.frame, {
      for (final entry in snapshot.textures.entries)
        if (!_dataTextures.containsKey(entry.key)) entry.key: entry.value,
    });
  }

  Future<void> open(int width, int height, bool Function() current) async {
    final work = _open(width, height, current);
    _renderWork.add(work);
    try {
      await work;
    } finally {
      _renderWork.remove(work);
    }
  }

  Future<void> _open(int width, int height, bool Function() current) async {
    final intent = ++_intent;
    final old = _session;
    _session = null;
    await old?.dispose();
    if (_disposed || !current() || intent != _intent) return;
    _width = width;
    _height = height;
    _metrics = data.metrics(width, height);
    _renderedVisible = false;
    final frame = _snapshot();
    final session = VegaRenderSession(
      renderer: GpuFrameRenderer(
        gpu.gpuContext,
        programs: haneokaShaderPrograms,
      ),
      fetch: fetch,
      textureDataFetch: loadHaneokaProfileTexture,
    );
    try {
      await session.open(
        handwrittenShaderBundle: await loadHaneokaProfileAsset(
          haneokaShaderBundle,
        ),
        scene: toRenderScene(frame.scene),
        textures: frame.textures,
        dataTextures: _dataTextures,
        initialFrame: frame.frame,
      );
      if (_disposed || !current() || intent != _intent) {
        await session.dispose();
        return;
      }
      _session = session;
      _last = frame;
      _frames++;
    } catch (_) {
      await session.dispose();
      rethrow;
    }
  }

  Future<void> present(bool Function() current) async {
    final work = _present(current);
    _renderWork.add(work);
    try {
      await work;
    } finally {
      _renderWork.remove(work);
    }
  }

  Future<void> _present(bool Function() current) async {
    final session = _session;
    if (_disposed || !current() || session == null || _presenting) return;
    final playbackFrame = playback.frame;
    final visible = playbackFrame.visibleInstances.any((i) => i.alpha > 0);
    if (!visible && !_renderedVisible) return;
    _presenting = true;
    final intent = _intent;
    bool active() =>
        !_disposed &&
        current() &&
        intent == _intent &&
        identical(session, _session);
    try {
      final frame = _snapshot(playbackFrame: playbackFrame);
      await session.ensureTextures(frame.textures);
      await session.ensureDataTextures(_dataTextures);
      if (!active()) return;
      await session.present(
        frame.frame,
        resources: toRenderScene(frame.scene),
        stillCurrent: active,
      );
      if (active()) {
        _last = frame;
        _frames++;
        _renderedVisible = visible;
      }
    } finally {
      _presenting = false;
    }
  }

  Map<String, Object?> get observation => {
    'actualUpdateIndex': playback.frame.actualUpdateIndex,
    'actualStoryUs': playback.frame.actualStoryUs,
    'gpuStoryUs': _last?.frame.mediaMicroseconds,
    'gpuFrames': _frames,
    'renderOwner': _sharedOwner == null ? 'standalone303' : 'sharedColour',
    'gpuPasses':
        _sharedOwner?.observation['gpuPasses'] ?? _last?.frame.passes.length,
    'gpuDraws':
        _sharedOwner?.observation['gpuDraws'] ??
        _last?.frame.passes.fold<int>(
          0,
          (total, pass) => total + pass.draws.length,
        ),
    'gpuMeshes': _last == null || _sharedOwner != null
        ? null
        : {
            for (final entry in _last!.scene.meshes.entries)
              entry.key: {
                'vertices': entry.value.vertices.length ~/ 10,
                'indices': entry.value.indices.length,
                'geometrySHA256': sha256
                    .convert(
                      entry.value.vertices.buffer.asUint8List(
                        entry.value.vertices.offsetInBytes,
                        entry.value.vertices.lengthInBytes,
                      ),
                    )
                    .toString(),
              },
          },
    'visible': [
      for (final i in playback.frame.visibleInstances)
        {
          'ref': i.ref,
          'alpha': i.alpha,
          'state': i.stateName,
          'stateSeconds': i.stateSeconds,
          'capturedSpeed': i.capturedAnimatorSpeed,
        },
    ],
    'sourceHashes': data.hashes,
    'canvasLogicalSize': _metrics == null
        ? null
        : [_metrics!.width, _metrics!.height],
    'canvasScale': _metrics?.scale,
    'warnings': playback.frame.warnings,
    'particles': _particles.diagnostic,
    'scope': 'Source planar Frame and shared-colour UIParticle BakeMesh',
  };
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_intent;
    playback.close('source_replaced');
    final session = _session;
    _session = null;
    await session?.dispose();
    _particles.clear();
    _dataTextures = const {};
  }
}

final class NativeStoryFrameHostSnapshot {
  const NativeStoryFrameHostSnapshot(
    this.sourceIdentity,
    this.sourceEpoch,
    this.sourceHashes,
    this.playback,
  );
  final StorySourceIdentity sourceIdentity;
  final int sourceEpoch;
  final Map<String, String> sourceHashes;
  final StoryFramePlaybackSnapshot playback;
  Map<String, Object?> toData() => {
    'version': 1,
    'source': sourceIdentity.toJson(),
    'hashes': sourceHashes,
    'playback': playback.toData(),
  };
}
