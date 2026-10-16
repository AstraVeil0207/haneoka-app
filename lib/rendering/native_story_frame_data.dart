import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show haneokaProfileAssetRoot;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';

/// Exact source Frame prefab/controller/clip/image and host-canvas packets.
/// This loader preserves unsupported source capabilities for the renderer.
final class NativeStoryFrameData {
  const NativeStoryFrameData._(
    this.frames,
    this.canvas,
    this.scaler,
    this.viewTransform,
    this.hashes,
    this.tiledTexture,
    this.snapshotCatalog,
  );
  final Map<String, StoryFrameSource> frames;
  final Map<String, Object?> canvas, scaler, viewTransform;
  final Map<String, String> hashes;
  final Map<String, Object?> tiledTexture;
  final StoryFrameSnapshotCatalog snapshotCatalog;
  static const _base = '${haneokaProfileAssetRoot}story-ui/source-bindings/';

  static Future<NativeStoryFrameData> load(StorySourceIdentity source) async {
    if (source.server != 'intl' ||
        source.sourceId != 'v25-c0b6a1541e45-3a5d2eec9935-n653c6392') {
      throw UnsupportedError('native_frame_data_source:${source.sourceId}');
    }
    final hashes = <String, String>{};
    Future<Map<String, Object?>> read(String name, String expected) async {
      final data = await rootBundle.load('$_base$name');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final hash = sha256.convert(bytes).toString();
      if (hash != expected) {
        throw FormatException('native_frame_data_hash:$name');
      }
      final value = Map<String, Object?>.from(
        jsonDecode(utf8.decode(bytes)) as Map,
      );
      if (value['sourceId'] != source.sourceId) {
        throw FormatException('native_frame_packet_source:$name');
      }
      hashes[name] = hash;
      return value;
    }

    final original = await read(
      'frames-source.json',
      'd41e8f297e53741917aae025f7da148137a85ccf694ad859906a89ec78d48170',
    );
    final yume = await read(
      'yume-frames-source.json',
      '1ee7221cf0467e68081a725206f6c6026eb3548eaeb855c6d0934a05051760d3',
    );
    final shader = await read(
      'frame-shader-metadata.json',
      'dff903db6360a09247f68204551d1f0af5af77fa2c7f26851d978169df22edda',
    );
    final yumeShader = await read(
      'yume-frame-shader-bindings.json',
      '1158dd4eff0594e478455d13b7ee6e99a5722c889763c9ed4deaa9c3adffd459',
    );
    final host = await read(
      'frame-canvas-scaler.json',
      'ca9089ade47bd5af9a2fd1ba7a55adbd5ac168b7434117052ed05c354b5a7d21',
    );
    final view = await read(
      'frame-view-root.json',
      'f3b3079adeed6732f715dbb1de86e74084adb0f87ea1fb07f8f6babcd463dcd6',
    );
    final tile = await read(
      'frame-tiled-texture-wrap.json',
      'aefe6fa56ccd22d3c5f9220f7995801a118016004df30a15cb33c384c88dd6db',
    );
    final metadata = <String, Map<String, Object?>>{};
    for (final packet in [shader, yumeShader]) {
      for (final entry in (packet['materialShaderMetadata'] as Map).entries) {
        metadata[entry.key as String] = Map<String, Object?>.from(
          entry.value as Map,
        );
      }
    }
    final frames = <String, StoryFrameSource>{};
    for (final packet in [original, yume]) {
      for (final entry in (packet['frames'] as Map).entries) {
        final parsed = StoryFrameSource.fromRaw(
          Map<String, Object?>.from(entry.value as Map),
          actualShaderMetadata: metadata,
        );
        if (parsed.ref != entry.key || frames.containsKey(parsed.ref)) {
          throw FormatException('native_frame_catalog_identity:${entry.key}');
        }
        frames[parsed.ref] = parsed;
      }
    }
    final viewRect = (view['components'] as List).cast<Map>().singleWhere(
      (record) => record['type'] == 'RectTransform',
    );
    return NativeStoryFrameData._(
      Map.unmodifiable(frames),
      Map<String, Object?>.from((host['canvas'] as Map)['data'] as Map),
      Map<String, Object?>.from(
        (host['clampedCanvasScaler'] as Map)['data'] as Map,
      ),
      Map<String, Object?>.from(viewRect['data'] as Map),
      Map.unmodifiable(hashes),
      tile,
      StoryFrameSnapshotCatalog.fromRaw(
        original['snapshotCompatibility'] as Map,
        sourceId: source.sourceId,
        definitionRefs: frames.keys,
        actualPacketHashes: hashes,
      ),
    );
  }

  StoryFrameCanvasMetrics metrics(int width, int height) =>
      StoryFrameCanvasMetrics.fromRaw(
        canvas,
        scaler,
        actualPixelWidth: width.toDouble(),
        actualPixelHeight: height.toDouble(),
      );

  List<double> get viewPivot {
    final p = viewTransform['m_Pivot'] as Map;
    return [(p['x'] as num).toDouble(), (p['y'] as num).toDouble()];
  }

  StoryTiledImageSource tiledSource(StoryFrameImageData image) {
    final originalSprite = tiledTexture['sprite'] as Map;
    final reference = (image.raw['m_Sprite'] as Map)['reference'] as Map;
    final tex = tiledTexture['texture'] as Map;
    final sprite = image.spriteRaw;
    if (sprite == null ||
        reference['serializedFile'] != originalSprite['serializedFile'] ||
        reference['pathId'] != originalSprite['pathId'] ||
        ((sprite['m_RD'] as Map)['texture'] as Map)['m_PathID'].toString() !=
            tex['pathId']) {
      throw UnsupportedError(
        'native_frame_tiled_texture_identity:${image.objectId}',
      );
    }
    final raw = tex['data'] as Map, settings = raw['m_TextureSettings'] as Map;
    if (raw['m_MipCount'] != 1 || settings['m_FilterMode'] != 1) {
      throw UnsupportedError('native_frame_tiled_texture_filter');
    }
    NativeSamplerAddress wrap(Object? code) => switch (code) {
      0 => NativeSamplerAddress.repeat,
      1 => NativeSamplerAddress.clampToEdge,
      2 => NativeSamplerAddress.mirror,
      _ => throw UnsupportedError('native_frame_texture_wrap:$code'),
    };
    return StoryTiledImageSource(
      packed: (((sprite['m_RD'] as Map)['settingsRaw'] as int) & 1) != 0,
      wrapU: wrap(settings['m_WrapU']),
      wrapV: wrap(settings['m_WrapV']),
      textureWidth: raw['m_Width'] as int,
      textureHeight: raw['m_Height'] as int,
    );
  }
}
