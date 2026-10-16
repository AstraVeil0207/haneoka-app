import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show haneokaProfileAssetRoot, loadHaneokaProfileAsset;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';

/// Original Graphic components and their modifiers retain distinct identities.
/// A disabled Image contributes no triangles, even if its modifier is enabled.
final class NativeStoryUiGraphicsSource {
  const NativeStoryUiGraphicsSource._(this.raw, this.sourceHash);
  final Map<String, Object?> raw;
  final String sourceHash;
  static const assetPath =
      '${haneokaProfileAssetRoot}story-ui/source-bindings/graphics-components.json';
  static Future<NativeStoryUiGraphicsSource> load(
    StorySourceIdentity source,
  ) async {
    final data = await loadHaneokaProfileAsset(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final hash = sha256.convert(bytes).toString();
    if (hash !=
        'b9c7ab861a37f8395ceeea726fcc6c38735be88184d00c2b98114a9b6e73f17d') {
      throw const FormatException('native_story_ui_graphics_identity');
    }
    final raw = Map<String, Object?>.from(
      jsonDecode(utf8.decode(bytes)) as Map,
    );
    if (source.server != 'intl' || raw['sourceId'] != source.sourceId) {
      throw UnsupportedError(
        'native_story_ui_graphics_source:${source.sourceId}',
      );
    }
    return NativeStoryUiGraphicsSource._(raw, hash);
  }

  List<Map> get spriteRecords {
    final found = <String, Map>{};
    void collect(Object? value) {
      if (value is Map) {
        if (value['type'] == 'Sprite' && value['record'] == 'object') {
          found['${value['serializedFile']}:${value['pathId']}'] = value;
          return;
        }
        for (final child in value.values) {
          collect(child);
        }
      } else if (value is List) {
        for (final child in value) {
          collect(child);
        }
      }
    }

    collect(raw);
    return List.unmodifiable(found.values);
  }

  Map get frontScaler =>
      ((raw['canvasSource'] as Map)['scalers'] as List).cast<Map>().singleWhere(
            (row) => row['pathId'] == '5367658026663563552',
          )['data']
          as Map;

  /// Cross-check the separately hash-bound packet once at normal UI loading.
  /// The current draw consumer keeps its existing behavior in this batch.
  void verifyControls(StoryUiControlBindings controls) {
    if (raw['sourceId'] != controls.sourceId) {
      throw const FormatException('native_story_controls_graphics_source');
    }
    for (final entry in controls.windows.entries) {
      final window = entry.value, graphic = raw[entry.key] as Map;
      final source = graphic['source'] as Map;
      final controller = graphic['controller'] as Map;
      if (source['sourceUiPath'] != window.visibility.sourceUiPath ||
          source['sourceUiHash'] != window.visibility.sourceUiHash ||
          controller['pathId'] != window.controllerId ||
          controller['serializedFile'] != window.serializedFile) {
        throw const FormatException('native_story_controls_window_identity');
      }
      final references = graphic['controllerRefs'] as Map;
      for (final binding in window.endpoints.entries) {
        final ref = references[binding.key] as Map;
        final pointer = ref['pointer'] as Map;
        if (pointer['m_FileID'] != 0) {
          throw const FormatException('native_story_controls_graphic_pointer');
        }
        final target = binding.value;
        if (target == null) {
          if (pointer['m_PathID'].toString() != '0' ||
              ref['object'] != null ||
              ref['hierarchyPath'] != null) {
            throw const FormatException('native_story_controls_null_graphic');
          }
        } else {
          final object = ref['object'] as Map;
          if (pointer['m_PathID'].toString() != target.objectId ||
              object['pathId'] != target.objectId ||
              object['type'] != target.objectType ||
              object['serializedFile'] != window.serializedFile ||
              '/${ref['hierarchyPath']}' != target.path) {
            throw const FormatException(
              'native_story_controls_graphic_binding',
            );
          }
        }
      }
    }
  }

  String? controllerPath(String mode, String field) {
    final ref = ((raw[mode] as Map)['controllerRefs'] as Map)[field] as Map;
    final path = ref['hierarchyPath'];
    return path == null ? null : '/$path';
  }

  Map image(String mode, String path) =>
      ((raw[mode] as Map)['graphics'] as List).cast<Map>().singleWhere(
        (row) =>
            row['independentGraphic'] == true &&
            row['class'] == 'Image' &&
            '/${row['hierarchyPath']}' == path,
      );

  Map? gradient(String mode, String path, String actualImageId) {
    final matches = ((raw[mode] as Map)['graphics'] as List)
        .cast<Map>()
        .where(
          (row) =>
              row['class'] == 'UIGradientImage' &&
              row['independentGraphic'] == false &&
              '/${row['hierarchyPath']}' == path,
        )
        .toList();
    if (matches.isEmpty) return null;
    final modifier = matches.single;
    if (!(modifier['modifiedGraphicObjectIds'] as List).contains(
      actualImageId,
    )) {
      throw FormatException('native_story_ui_gradient_graphic:$path');
    }
    final data = (modifier['object'] as Map)['data'] as Map;
    if (data['m_Enabled'] == 0 || data['m_Enabled'] == false) return null;
    return {
      'angle': data['_angleDeg'],
      'keys': data['_gradient'],
      'blendMode': data['_blendMode'],
      'splitAtKeysWhenAxisAligned':
          data['_splitAtKeysWhenAxisAligned'] == 1 ||
          data['_splitAtKeysWhenAxisAligned'] == true,
    };
  }
}
