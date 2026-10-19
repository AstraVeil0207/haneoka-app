import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show
        haneokaShaderBundle,
        loadHaneokaProfileAsset,
        loadHaneokaProfileTexture;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vega_plugin_haneoka/render_profile.dart';
import 'package:vega_renderer_flutter/vega_renderer_flutter.dart';

import 'native_story_colour_scene.dart';

/// One actual source-scoped session owns the colour target and all layer draws.
final class NativeStoryColourHost {
  NativeStoryColourHost({required this.epoch, required this.fetch});
  final int epoch;
  final Future<Uint8List> Function(Uri) fetch;
  VegaRenderSession? _session;
  NativeStoryColourScene? _last;
  RenderFrame? _lastGpuFrame;
  final _backgroundImages = <Uri, StoryBackgroundImage>{};
  final _pendingTextures = <String, Uri>{};
  bool _disposed = false, _presenting = false;
  int _intent = 0, _frames = 0, _width = 0, _height = 0, _sessionGeneration = 0;
  ValueListenable<ui.Image?>? get image => _session?.image;
  bool get hasCurrentImage => _session?.image.value != null;

  /// The fixed LUT target survives only in a successfully submitted graph.
  /// Reopening a viewport or omitting the world retires its GPU contents.
  bool hasWorldPostLut(int width, int height) =>
      hasCurrentImage &&
      _width == width &&
      _height == height &&
      (_last?.scene.targets.containsKey('world:post:lut') ?? false);

  bool containsSubmittedLayer(
    int order,
    NativeSceneResources scene,
    NativeFrame frame,
  ) {
    final submitted = _last;
    if (!hasCurrentImage ||
        submitted == null ||
        submitted.frame.epoch != frame.epoch ||
        submitted.frame.mediaMicroseconds != frame.mediaMicroseconds ||
        !(submitted.proof['sortingOrders'] as List).contains(order)) {
      return false;
    }
    final used = frame.passes.first.draws;
    return used.every(
      (draw) => identical(
        submitted.scene.meshes['colour:$order:${draw.mesh}'],
        scene.meshes[draw.mesh],
      ),
    );
  }

  Future<void> ensureTextures(Map<String, Uri> textures) async {
    if (_disposed) throw StateError('native_story_colour_host_disposed');
    _pendingTextures.addAll(textures);
    final session = _session;
    // A cold seek can prepare text before the first displayed colour scene.
    // The first real open installs these textures together with its graph.
    if (session == null) return;
    await session.ensureTextures(textures);
    _retirePendingTextures(textures);
  }

  void _retirePendingTextures(Map<String, Uri> installed) {
    for (final entry in installed.entries) {
      if (_pendingTextures[entry.key] == entry.value) {
        _pendingTextures.remove(entry.key);
      }
    }
  }

  Future<void> present({
    required StoryBackgroundImage lower,
    required NativeStoryColourScene snapshot,
    required bool Function() current,
    double spatialSharpness = .8705505632961241,
    Future<NativeStoryColourScene?> Function(
      GpuFrameRenderer,
      int,
      bool Function(),
    )?
    prepareDecodedVideo,
  }) async {
    if (_disposed || !current() || _presenting) return;
    if (lower.epoch != epoch ||
        snapshot.scene.epoch != epoch ||
        snapshot.frame.epoch != epoch) {
      throw StateError('native_story_colour_host_epoch');
    }
    _presenting = true;
    final priorProof = _backgroundImages[lower.uri];
    if (priorProof != null && priorProof.encodedSHA256 != lower.encodedSHA256) {
      _presenting = false;
      throw StateError('native_story_colour_pinned_lower_changed');
    }
    _backgroundImages[lower.uri] = lower;
    final target = snapshot.scene.targets[snapshot.frame.outputTarget]!;
    final intent = _intent;
    bool active() => !_disposed && current() && intent == _intent;
    Future<Uint8List> verifiedFetch(Uri uri) async {
      final bytes = await fetch(uri);
      // The session's resource transport belongs to the chapter. A viewport
      // transition invalidates presentation, not already pinned source bytes.
      if (_disposed || intent != _intent) {
        throw StateError('story_source_replaced');
      }
      _backgroundImages[uri]?.verifyBoundEncodedBytes(bytes);
      return bytes;
    }

    try {
      var session = _session;
      var finalSnapshot = snapshot;
      var gpuSnapshot = _spatial(snapshot, spatialSharpness);
      var opened = false;
      final textures = {..._pendingTextures, ...snapshot.textures};
      if (session == null ||
          _width != target.width ||
          _height != target.height) {
        final created = session == null;
        _sessionGeneration++;
        if (!active()) return;
        // Keep the image notifier bound to RawImage during viewport changes.
        // RenderSession.open serializes the new graph after the last GPU work.
        session ??= VegaRenderSession(
          renderer: GpuFrameRenderer(
            gpu.gpuContext,
            programs: {...haneokaShaderPrograms, ...SpatialUpscaler.programs},
            additionalShaderBundles: [await SpatialUpscaler.loadShaders()],
          ),
          fetch: verifiedFetch,
          textureDataFetch: loadHaneokaProfileTexture,
        );
        try {
          await session.open(
            handwrittenShaderBundle: await loadHaneokaProfileAsset(
              haneokaShaderBundle,
            ),
            scene: gpuSnapshot.scene,
            textures: textures,
            dataTextures: snapshot.dataTextures,
            initialFrame: gpuSnapshot.frame,
          );
          if (!active()) {
            if (created) await session.dispose();
            return;
          }
          _session = session;
          _width = target.width;
          _height = target.height;
          opened = true;
        } catch (_) {
          if (created) await session.dispose();
          rethrow;
        }
      } else {
        await session.ensureTextures(textures);
        if (!active()) return;
        await session.ensureDataTextures(snapshot.dataTextures);
        if (!active()) return;
      }
      _retirePendingTextures(textures);
      if (prepareDecodedVideo != null && active()) {
        final prepared = await prepareDecodedVideo(
          session.renderer,
          _sessionGeneration,
          active,
        );
        if (!active()) return;
        if (prepared != null) {
          finalSnapshot = prepared;
          gpuSnapshot = _spatial(prepared, spatialSharpness);
          await session.ensureTextures(prepared.textures);
          if (!active()) return;
          await session.ensureDataTextures(prepared.dataTextures);
          if (!active()) return;
        }
      }
      if (active() && (!opened || !identical(finalSnapshot, snapshot))) {
        await session.present(
          gpuSnapshot.frame,
          resources: gpuSnapshot.scene,
          stillCurrent: active,
        );
      }
      if (active()) {
        _last = finalSnapshot;
        _lastGpuFrame = gpuSnapshot.frame;
        _frames++;
        finalSnapshot.onPresented?.call();
      }
    } catch (_) {
      // A newer viewport may supersede an in-flight open or presentation.
      // The next frame will create/use its own current graph.
      if (active()) rethrow;
    } finally {
      _presenting = false;
    }
  }

  ({RenderScene scene, RenderFrame frame}) _spatial(
    NativeStoryColourScene value,
    double sharpness,
  ) {
    final scene = toRenderScene(value.scene);
    if (!scene.targets.containsKey('colour:world-input')) {
      return (scene: scene, frame: value.frame);
    }
    final target = scene.targets[value.frame.outputTarget]!;
    return SpatialUpscaler(sharpness: sharpness).append(
      scene: scene,
      frame: value.frame,
      inputTarget: 'colour:world-input',
      outputTarget: 'colour:main',
      width: target.width,
      height: target.height,
    );
  }

  Map<String, Object?> get observation => {
    'gpuFrames': _frames,
    'gpuStoryUs': _last?.frame.mediaMicroseconds,
    'gpuPasses': _lastGpuFrame?.passes.length,
    'gpuDraws': _lastGpuFrame?.passes.fold<int>(
      0,
      (n, p) => n + p.draws.length,
    ),
    'actualProof': _last?.proof,
    'workingTargets': _last?.scene.targets.length,
    'viewport': [_width, _height],
    'pendingTextures': _pendingTextures.length,
    'resources': _session?.renderer.resourceCounts,
    'textureResources': _session?.renderer.textureResources,
    'targetResources': _session?.renderer.targetResources,
  };
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_intent;
    final session = _session;
    _session = null;
    _pendingTextures.clear();
    await session?.dispose();
  }
}
