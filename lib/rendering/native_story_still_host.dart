import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show haneokaShaderBundle;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vega_plugin_haneoka/render_profile.dart';
import 'package:vega_renderer_flutter/vega_renderer_flutter.dart';

import 'native_story_document.dart';
import 'native_story_colour_host.dart';
import 'native_story_playback.dart';
import 'native_story_still_frame.dart';
import 'native_story_still_source.dart';

/// Owns the normal episode's still resources, source command controller, GPU
/// session and current surface. Every frame receives the host's actual story
/// clock; source replacement cancels both command work and GPU submissions.
final class NativeStoryStillHost {
  NativeStoryStillHost({
    required this.document,
    required this.epoch,
    required this.fetch,
    required NativeStoryStillSource source,
    required int actualStoryUs,
    required double speed,
    this.shakeOffset,
  }) {
    externalLayout = NativeStoryStillSource.externalLayout(
      document.chapter.sourceIdentity,
      document.assets.stills,
    );
    playback = StoryStillPlayback(
      sourceIdentity: document.chapter.sourceIdentity,
      sourceEpoch: epoch,
      actualStills: document.assets.stills,
      actualFadeEase: source.fadeEase,
      actualInitialOverlayAlpha: source.initialOverlayAlpha,
      actualStoryUs: actualStoryUs,
      currentSpeed: speed,
      externalLayoutSource: externalLayout,
    );
  }
  final NativeStoryDocument document;
  final int epoch;
  final List<double> Function()? shakeOffset;
  final Future<Uint8List> Function(Uri) fetch;
  late final StoryStillPlayback playback;
  late final StoryStillExternalLayoutSource? externalLayout;
  final _sizes = <String, (int, int)>{};
  Future<void>? _resourceWork;
  final _renderWork = <Future<void>>{};
  VegaRenderSession? _session;
  bool _disposed = false, _presenting = false;
  bool _renderedVisible = false;
  bool _sharedHasImage = false;
  NativeStoryColourHost? _sharedOwner;
  int _intent = 0, _width = 0, _height = 0, _frames = 0;
  NativeStoryStillCanvasFrame? _lastFrame;
  ValueListenable<ui.Image?>? get image => _session?.image;
  bool get hasRenderedStill =>
      (_session?.image.value != null || _sharedHasImage) &&
      _frames > 1 &&
      playback.frame.visibleInstances.any((instance) => instance.alpha > 0) &&
      (_lastFrame?.scene.meshes.entries.any(
            (entry) =>
                entry.key.startsWith('story-still:') &&
                entry.value.indices.isNotEmpty,
          ) ??
          false);
  int? get renderedStoryUs => _lastFrame?.frame.mediaMicroseconds;
  Map<String, Object?> get observation {
    final state = playback.snapshot();
    return {
      'storyUs': playback.frame.actualStoryUs,
      'currentRef': playback.frame.currentRef,
      'visible': [
        for (final i in playback.frame.visibleInstances)
          {
            'ref': i.ref,
            'alpha': i.alpha,
            'sequence': i.sequenceId,
            'sequenceSeconds': i.sequenceSeconds,
            'playing': state.instances[i.ref]!.sequencePlaying,
            'pendingSequence': state.instances[i.ref]!.pendingSequence,
            'animatorSequence': state.instances[i.ref]!.animator.sequence,
          },
      ],
      'backgroundAlpha': playback.frame.backgroundAlpha,
      'overlayAlpha': playback.frame.overlayAlpha,
      'postEffectSuppressed': playback.frame.postEffectSuppressed,
      'renderedFrames': _frames,
      'gpuFrameStoryUs': _lastFrame?.frame.mediaMicroseconds,
      'viewport': [_width, _height],
      'renderOwner': _sharedOwner == null ? 'standalone302' : 'sharedColour',
      'gpuPasses':
          _sharedOwner?.observation['gpuPasses'] ??
          _lastFrame?.frame.passes.length ??
          0,
      'gpuDraws':
          _sharedOwner?.observation['gpuDraws'] ??
          _lastFrame?.frame.passes.fold<int>(
            0,
            (total, pass) => total + pass.draws.length,
          ) ??
          0,
      'preparedTextures': _sizes.length,
      'unsupported': _lastFrame?.unsupported ?? const <String>[],
      'warnings': playback.frame.warnings,
      'renderedImageGeometry': _lastFrame?.imageGeometry,
    };
  }

  Future<void> prepare(bool Function() current) async {
    await (_resourceWork ??= _prepare(current));
  }

  Future<void> _prepare(bool Function() current) async {
    for (final presentation in document.assets.stills.values) {
      final nodes = (presentation['layout'] as Map)['nodes'] as List;
      for (final node in nodes.cast<Map>()) {
        final image = node['image'];
        if (image is! Map || image['texture'] is! String) continue;
        final texture = image['texture'] as String;
        if (_sizes.containsKey(texture)) continue;
        final data = await fetch(document.assets.pinned(texture));
        if (_disposed || !current()) throw StateError('story_source_replaced');
        final geometry = image['sprite'];
        if (geometry is! Map || geometry['outputSHA256'] is! String) {
          throw StateError('native_still_source_sprite_geometry_missing');
        }
        if (sha256.convert(data).toString() != geometry['outputSHA256']) {
          throw StateError('native_still_source_sprite_output_hash:$texture');
        }
        final codec = await ui.instantiateImageCodec(data);
        try {
          final frame = await codec.getNextFrame();
          try {
            if (_disposed || !current()) {
              throw StateError('story_source_replaced');
            }
            _sizes[texture] = (frame.image.width, frame.image.height);
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    }
  }

  Future<void> settleResources() async {
    final work = _resourceWork;
    if (work == null || _disposed) {
      throw StateError('native_still_resources_unprepared');
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
      throw const FormatException('native_still_data_source');
    }
    if (saved['runtimeHash'] != document.runtimeHash ||
        saved['layoutHash'] != externalLayout?.packetSHA256) {
      throw const FormatException('native_still_data_hashes');
    }
    await prepare(() => !_disposed);
    await quiesce();
    final value = saved['playback'] as Map;
    _watchRestored(
      playback.restoreData(
        value,
        actualStoryUs: stamp.storyUs,
        speed: stamp.speed,
        paused: stamp.paused,
        epoch: epoch,
      ),
    );
    _sharedHasImage = false;
    _lastFrame = null;
    await settleResources();
  }

  NativeStoryStillHostSnapshot snapshot() {
    if (_disposed) throw StateError('story_source_replaced');
    return NativeStoryStillHostSnapshot(
      document.chapter.sourceIdentity,
      epoch,
      document.runtimeHash,
      externalLayout?.packetSHA256,
      playback.snapshot(),
    );
  }

  Future<void> quiesce() async {
    ++_intent;
    final state = playback.snapshot();
    _watchRestored(
      playback.restore(
        state,
        state.actualStoryUs,
        speed: state.speed,
        paused: true,
        epoch: epoch,
      ),
    );
    await Future.wait(_renderWork.toList());
    await settleResources();
  }

  Future<void> restore(
    NativeStoryStillHostSnapshot snapshot, {
    required NativeStoryUpdateStamp stamp,
  }) async {
    if (_disposed ||
        snapshot.sourceIdentity != document.chapter.sourceIdentity ||
        snapshot.sourceEpoch != epoch ||
        snapshot.runtimeHash != document.runtimeHash ||
        snapshot.layoutHash != externalLayout?.packetSHA256 ||
        stamp.sourceEpoch != epoch) {
      throw const FormatException('native_still_snapshot_source');
    }
    await quiesce();
    _watchRestored(
      playback.restore(
        snapshot.playback,
        stamp.storyUs,
        speed: stamp.speed,
        paused: stamp.paused,
        epoch: epoch,
      ),
    );
    _sharedHasImage = false;
    _lastFrame = null;
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

  NativeStoryStillCanvasFrame _snapshot() {
    StoryStillExternalLayout? external;
    if (externalLayout != null && _width > 0 && _height > 0) {
      external = StoryStillExternalLayout.resolve(
        source: externalLayout!,
        physicalWidth: _width.toDouble(),
        physicalHeight: _height.toDouble(),
      );
      // Reference layouts every descendant, including hidden/alpha-zero stills.
      playback.consumeAttachments(external);
    }
    final frame = playback.frame;
    final captureGeometry =
        const bool.fromEnvironment('HANEOKA_NATIVE_TRACE') &&
        const String.fromEnvironment('HANEOKA_NATIVE_STORY_EXPORT').isNotEmpty;
    return buildNativeStoryStillCanvas(
      instances: [
        for (final i in frame.visibleInstances)
          NativeStoryStillCanvasInstance(
            reference: i.ref,
            presentation: document.assets.stills[i.ref]!,
            currentLayout: i.layout,
            rootAlpha: i.alpha,
            attachment: captureGeometry ? playback.attachmentFor(i.ref) : null,
          ),
      ],
      backgroundAlpha: frame.backgroundAlpha,
      overlayAlpha: frame.overlayAlpha,
      source: RenderSource(
        server: document.chapter.sourceIdentity.server,
        release: document.chapter.sourceIdentity.release,
        document: document.chapter.sourceIdentity.document,
      ),
      epoch: epoch,
      actualStoryUs: frame.actualStoryUs,
      width: _width,
      height: _height,
      resolveTexture: document.assets.pinned,
      textureSizes: _sizes,
      externalLayout: external,
      captureGeometryProof: captureGeometry,
      offset: shakeOffset?.call() ?? const [0, 0, 0],
    );
  }

  NativeStoryStillCanvasFrame snapshotForColour(NativeStoryUpdateStamp stamp) {
    if (_disposed ||
        stamp.sourceEpoch != epoch ||
        _width <= 0 ||
        _height <= 0) {
      throw StateError('native_still_colour_actual_update');
    }
    playback.update(
      stamp.storyUs,
      speed: stamp.speed,
      paused: stamp.paused,
      epoch: epoch,
    );
    return _snapshot();
  }

  Future<void> retireSurfaceForColour() async {
    final session = _session;
    _session = null;
    await session?.dispose();
  }

  void actualUpdate(NativeStoryUpdateStamp stamp) {
    if (_disposed || stamp.sourceEpoch != epoch) return;
    playback.update(
      stamp.storyUs,
      speed: stamp.speed,
      paused: stamp.paused,
      epoch: epoch,
    );
  }

  void configureColourViewport(int width, int height) {
    if (_disposed) throw StateError('story_source_replaced');
    _width = width;
    _height = height;
  }

  void recordColourPresentation(
    NativeStoryStillCanvasFrame snapshot,
    NativeStoryColourHost owner,
  ) {
    if (!owner.containsSubmittedLayer(302, snapshot.scene, snapshot.frame)) {
      throw StateError('native_still_colour_submission_missing');
    }
    _lastFrame = snapshot;
    _sharedHasImage = true;
    _sharedOwner = owner;
    _frames++;
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
    final previous = _session;
    _session = null;
    await previous?.dispose();
    if (_disposed || !current() || intent != _intent) return;
    _width = width;
    _height = height;
    _renderedVisible = false;
    final frame = _snapshot();
    final session = VegaRenderSession(
      renderer: GpuFrameRenderer(
        gpu.gpuContext,
        programs: haneokaShaderPrograms,
      ),
      fetch: fetch,
    );
    try {
      await session.open(
        handwrittenShaderBundle: await rootBundle.load(haneokaShaderBundle),
        scene: toRenderScene(frame.scene),
        textures: frame.textures,
        initialFrame: frame.frame,
      );
      if (_disposed || !current() || intent != _intent) {
        await session.dispose();
        return;
      }
      _session = session;
      _lastFrame = frame;
      _frames++;
    } catch (_) {
      await session.dispose();
      rethrow;
    }
  }

  Future<void> dispatch(
    StoryDecodedCommand command,
    StoryDispatchContext context,
    int actualStoryUs,
    double speed,
  ) async {
    if (_disposed || !context.isCurrent()) {
      throw StateError('story_source_replaced');
    }
    final operation = playback.dispatch(
      command,
      actualStoryUs,
      speed,
      executionId: context.executionId,
    );
    await operation.completion;
    if (_disposed || !context.isCurrent()) {
      throw StateError('story_source_replaced');
    }
  }

  Future<void> update(
    int actualStoryUs,
    double speed,
    bool paused,
    bool Function() current,
  ) async {
    final work = _update(actualStoryUs, speed, paused, current);
    _renderWork.add(work);
    try {
      await work;
    } finally {
      _renderWork.remove(work);
    }
  }

  Future<void> _update(
    int actualStoryUs,
    double speed,
    bool paused,
    bool Function() current,
  ) async {
    if (_disposed || !current()) return;
    playback.update(actualStoryUs, speed: speed, paused: paused, epoch: epoch);
    final session = _session;
    if (session == null || _presenting || _width <= 0 || _height <= 0) return;
    // Layout still runs when every instance is hidden; visibility gates drawing.
    final frame = _snapshot();
    final state = playback.frame;
    final visible =
        state.visibleInstances.isNotEmpty ||
        state.backgroundAlpha > 0 ||
        state.overlayAlpha > 0;
    if (!visible && !_renderedVisible) return;
    _presenting = true;
    final intent = _intent;
    bool active() =>
        !_disposed &&
        current() &&
        intent == _intent &&
        identical(_session, session);
    try {
      await session.ensureTextures(frame.textures);
      if (!active()) return;
      await session.present(
        frame.frame,
        resources: toRenderScene(frame.scene),
        stillCurrent: active,
      );
      if (active()) {
        _lastFrame = frame;
        _frames++;
        _renderedVisible = visible;
      }
    } finally {
      _presenting = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sharedHasImage = false;
    ++_intent;
    playback.close('source_replaced');
    final session = _session;
    _session = null;
    await session?.dispose();
  }
}

final class NativeStoryStillHostSnapshot {
  const NativeStoryStillHostSnapshot(
    this.sourceIdentity,
    this.sourceEpoch,
    this.runtimeHash,
    this.layoutHash,
    this.playback,
  );
  final StorySourceIdentity sourceIdentity;
  final int sourceEpoch;
  final String runtimeHash;
  final String? layoutHash;
  final StoryStillPlaybackSnapshot playback;
  Map<String, Object?> toData() => {
    'version': 1,
    'source': sourceIdentity.toJson(),
    'runtimeHash': runtimeHash,
    'layoutHash': layoutHash,
    'playback': playback.toData(),
  };
}
