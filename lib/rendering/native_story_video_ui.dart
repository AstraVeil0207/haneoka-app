import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show haneokaProfileAssetRoot, loadHaneokaProfileAsset;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_colour_scene.dart';
import 'native_story_playback.dart';

/// Exact local VideoCanvas inputs from the selected UIAdvWidget source.
final class NativeStoryVideoUi {
  NativeStoryVideoUi._(this.records, this.controller, this.scaler);
  final Map<String, Map<String, Object?>> records;
  final Map<String, Object?> controller, scaler;
  static Future<NativeStoryVideoUi> load(StorySourceIdentity source) async {
    const path =
        '${haneokaProfileAssetRoot}story-ui/source-bindings/video-ui-bindings.json';
    final data = await loadHaneokaProfileAsset(path);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final j = jsonDecode(utf8.decode(bytes)) as Map;
    if (sha256.convert(bytes).toString() !=
            '076a14a06f067f9a2433c3c312f41143812ed11fd5ed8e7230ca9dd09f837c9d' ||
        source.server != 'intl' ||
        source.sourceId != j['sourceId'] ||
        j['schema'] != 'haneoka-native-video-ui-bindings-v1') {
      throw const FormatException('native_video_ui_source');
    }
    final records = <String, Map<String, Object?>>{
      for (final r in j['records'] as List)
        (r as Map)['pathId'] as String: Map<String, Object?>.from(r),
    };
    final widget = records[j['widgetId']]!['data'] as Map;
    if ((widget['_videoView'] as Map)['m_PathID'] != j['videoViewId']) {
      throw const FormatException('native_video_ui_view_pointer');
    }
    final controller = Map<String, Object?>.from(
      records[j['videoViewId']]!['data'] as Map,
    );
    final image =
        records[(controller['_video'] as Map)['m_PathID']]!['data'] as Map;
    if (((image['m_Script'] as Map)['reference'] as Map)['name'] != 'Image' ||
        (image['m_Sprite'] as Map)['m_PathID'] != '0' ||
        image['m_Type'] != 0) {
      throw const FormatException('native_video_ui_actual_image');
    }
    final canvas =
        records.values.singleWhere((r) => r['type'] == 'Canvas')['data'] as Map;
    if (canvas['m_RenderMode'] != 1 ||
        canvas['m_SortingOrder'] != 301 ||
        canvas['m_PixelPerfect'] != false) {
      throw const FormatException('native_video_canvas_contract');
    }
    final scaler =
        records.values.singleWhere(
              (r) =>
                  r['type'] == 'MonoBehaviour' &&
                  ((r['data'] as Map)['m_Script'] as Map)['reference'] is Map &&
                  (((r['data'] as Map)['m_Script'] as Map)['reference']
                          as Map)['name'] ==
                      'CanvasScaler',
            )['data']
            as Map;
    if (scaler['m_UiScaleMode'] != 1 || scaler['m_ScreenMatchMode'] != 1) {
      throw const FormatException('native_video_scaler_contract');
    }
    return NativeStoryVideoUi._(
      Map.unmodifiable(records),
      Map.unmodifiable(controller),
      Map.unmodifiable(Map<String, Object?>.from(scaler)),
    );
  }

  /// Source CalcContainedSize (Single arithmetic), converted to physical pixels.
  StoryUiRect containedPixels(
    int width,
    int height,
    int sourceWidth,
    int sourceHeight,
  ) {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw const FormatException('native_video_actual_size');
    }
    final ref = scaler['m_ReferenceResolution'] as Map;
    final scale = math.min(
      width / (ref['x'] as num),
      height / (ref['y'] as num),
    );
    final slot = Float32List(1);
    double f(double v) {
      slot[0] = v;
      return slot[0];
    }

    final w = f(width / scale),
        h = f(height / scale),
        aspect = f(sourceWidth / sourceHeight);
    final rw = f(w / h) <= aspect ? w : f(aspect * h),
        rh = f(w / h) <= aspect ? f(w / aspect) : h;
    return StoryUiRect(
      (width - rw * scale) / 2,
      (height - rh * scale) / 2,
      rw * scale,
      rh * scale,
    );
  }

  NativeStoryColourLayer layer({
    required RenderSource source,
    required NativeStoryUpdateStamp stamp,
    required int width,
    required int height,
    required int sourceWidth,
    required int sourceHeight,
    required String decodedTextureKey,
    required double videoAlpha,
    required double curtainAlpha,
  }) {
    final r = containedPixels(width, height, sourceWidth, sourceHeight);
    ProjectedMesh quad(StoryUiRect rect, List<double> colour) =>
        buildStoryImageMesh(
          rect: rect,
          canvasWidth: width.toDouble(),
          canvasHeight: height.toDouble(),
          color: colour,
          imageType: 0,
          spriteSize: const [1, 1],
          trimmedPixels: const StoryUiRect(0, 0, 1, 1),
          border: const StoryImageBorders(left: 0, bottom: 0, right: 0, top: 0),
          pixelsPerUnit: 1,
          fillCenter: true,
        );
    List<double> imageColor(String componentId, double opacity) {
      final data = records[componentId]!['data'] as Map;
      final c = data['m_Color'] as Map;
      final out = storyFrameColor32([
        for (final k in ['r', 'g', 'b', 'a']) (c[k] as num).toDouble(),
      ]);
      out[3] *= opacity;
      return out;
    }

    final curtainGroup =
        records[(controller['_curtainCanvasGroup'] as Map)['m_PathID']]!['data']
            as Map;
    final curtainGo = (curtainGroup['m_GameObject'] as Map)['m_PathID'];
    final curtain = records.values.singleWhere(
      (r) =>
          r['type'] == 'MonoBehaviour' &&
          ((r['data'] as Map)['m_GameObject'] as Map)['m_PathID'] ==
              curtainGo &&
          (((r['data'] as Map)['m_Script'] as Map)['reference']
                  as Map)['name'] ==
              'Image',
    );
    final meshes = {
      'video:curtain': quad(
        StoryUiRect(0, 0, width.toDouble(), height.toDouble()),
        imageColor(curtain['pathId'] as String, curtainAlpha),
      ),
      'video:decoded': quad(
        r,
        imageColor(
          (controller['_video'] as Map)['m_PathID'] as String,
          videoAlpha,
        ),
      ),
    };
    final materials = {
      'video:curtain': const NativeMaterial(
        texture: '',
        recipe: NativeMaterialRecipe.solidColor,
      ),
      'video:decoded': NativeMaterial(
        texture: decodedTextureKey,
        textureAlpha: NativeTextureAlpha.premultiplied,
      ),
    };
    return NativeStoryColourLayer(
      sortingOrder: 301,
      contentTarget: 'video:main',
      scene: NativeSceneResources(
        epoch: stamp.sourceEpoch,
        source: source,
        meshes: meshes,
        materials: materials,
        targets: {
          'video:main': NativeTarget(
            width: width,
            height: height,
            presentable: true,
          ),
        },
      ),
      frame: NativeFrame(
        epoch: stamp.sourceEpoch,
        mediaMicroseconds: stamp.storyUs,
        outputTarget: 'video:main',
        passes: [
          NativePass(
            target: 'video:main',
            draws: const [
              NativeDraw(mesh: 'video:curtain', material: 'video:curtain'),
              NativeDraw(mesh: 'video:decoded', material: 'video:decoded'),
            ],
          ),
        ],
      ),
      textures: const {},
      decodedTextureKeys: {decodedTextureKey},
    );
  }
}
