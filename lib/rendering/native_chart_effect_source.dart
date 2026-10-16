import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show haneokaProfileAssetRoot;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:cassiopeia_plugin_our_notes/render_profile.dart';

import 'native_numeric_texture.dart';

/// Local immutable original-data closure shared with the native effect producer.
/// Shader programs are independently authored in the renderer package.
final class NativeChartEffectSource implements AuthoredParticleSource {
  NativeChartEffectSource._(
    this.graph,
    this.recipe,
    this.sourceHashes,
    this.textureData,
    this.materialTextureKeys,
    this.textureIdentityKeys,
    this.animationBindings,
    this.noteWidthAssets,
    this.loopControllers,
    this.laneFeedback,
  );
  @override
  final NativeAuthoredEffectGraph graph;
  final Map recipe;
  final Map<String, String> sourceHashes;
  final Map<String, NativeTextureData> textureData;
  @override
  final Map<String, String> materialTextureKeys;
  final Map<String, String> textureIdentityKeys;
  final Map<String, Map> animationBindings;
  final Map<String, Map> noteWidthAssets, loopControllers;
  final ChartLaneFeedbackProfile laneFeedback;
  static final NativeAuthoredRandom _sharedParticleRandom =
      NativeAuthoredRandom(DateTime.now().millisecondsSinceEpoch);
  static NativeAuthoredRandom get sharedParticleRandom => _sharedParticleRandom;
  @override
  NativeAuthoredRandom randomFor(NativeEffectObject system) =>
      system.data['autoRandomSeed'] == true
      ? _sharedParticleRandom
      : NativeAuthoredRandom(system.data['randomSeed'] as int);
  Map get bloom => recipe['bloom'] as Map;
  Map get fxaa => recipe['fxaa'] as Map;

  static const supportedServer = 'intl',
      supportedSourceId = 'v25-c0b6a1541e45-3a5d2eec9935-n653c6392';
  static Future<NativeChartEffectSource>? _cachedSource;
  static Future<NativeChartEffectSource> load({
    required String server,
    required String? sourceId,
  }) async {
    if (server != supportedServer || sourceId != supportedSourceId) {
      throw UnsupportedError('native_effect_source_scope:$server:$sourceId');
    }
    try {
      return await (_cachedSource ??= _load(
        server: server,
        sourceId: sourceId,
      ));
    } catch (_) {
      _cachedSource = null;
      rethrow;
    }
  }

  static Future<NativeChartEffectSource> _load({
    required String server,
    required String? sourceId,
  }) async {
    const base = '${haneokaProfileAssetRoot}effects/';
    final hashes = <String, String>{};
    Future<Map> read(String name) async {
      final bytes = await rootBundle.load('$base$name');
      final body = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      hashes[name] = sha256.convert(body).toString();
      return jsonDecode(utf8.decode(body)) as Map;
    }

    final components = await read('components.json'),
        recipe = await read('recipes.json');
    if (recipe['missingPaths'] is! List ||
        (recipe['missingPaths'] as List).isNotEmpty) {
      throw const FormatException('native_effect_recipe_source_incomplete');
    }
    final graph = NativeAuthoredEffectGraph(components)
      ..mergeNormalizedRecords(recipe['objects'] as Map);
    final animationData = await read('animation-bindings.json');
    if (animationData['schema'] != 'haneoka-native-fx-animation-bindings-v1' ||
        animationData['server'] != server ||
        animationData['sourceId'] != sourceId) {
      throw const FormatException('native_effect_animation_binding_source');
    }
    final animationBindings = <String, Map>{};
    for (final raw in animationData['bindings'] as List) {
      final binding = raw as Map, file = binding['serializedFile'] as String;
      final component = binding['animationComponent'] as Map;
      final transform =
          graph.objects['$file:${binding['animationTransformId']}'];
      if (animationBindings.containsKey(file) ||
          transform?.type != 'Transform' ||
          component['serializedFile'] != file ||
          component['pathId'].toString() != binding['animationComponentId'] ||
          !const ['Animator', 'Animation'].contains(component['type']) ||
          graph.gameObject(transform!).id != binding['gameObjectId']) {
        throw FormatException('native_effect_animation_binding_identity:$file');
      }
      final pointer = (component['data'] as Map)['m_GameObject'] as Map;
      if (pointer['m_FileID'] != 0 ||
          pointer['m_PathID'] != binding['gameObjectId']) {
        throw FormatException('native_effect_animation_binding_go:$file');
      }
      animationBindings[file] = binding;
    }
    // Duplicate PS/Sprite rows have been checked against the shared source hash.
    // Keep the single graph and release their second parsed object hierarchy.
    recipe.remove('objects');
    final widthData = await read('note-width-bindings.json');
    if (widthData['schema'] != 'haneoka-native-note-fx-width-bindings-v1' ||
        widthData['server'] != server ||
        widthData['sourceId'] != sourceId) {
      throw const FormatException('native_effect_width_binding_source');
    }
    final widthAssets = <String, Map>{};
    const targets = {
      '_particleShapeWidthSetParams': ('particleSystem', 'ParticleSystem'),
      '_spriteRendererWidthSetParams': ('spriteRenderer', 'SpriteRenderer'),
      '_transformWidthSetParams': ('transform', 'Transform'),
      '_transformWidthSetRangeParams': ('transform', 'Transform'),
      '_leftCenterWidthSetParams': ('transform', 'Transform'),
      '_rightCenterWidthSetParams': ('transform', 'Transform'),
    };
    for (final raw in widthData['bindings'] as List) {
      final binding = raw as Map, file = binding['serializedFile'] as String;
      final asset = binding['asset'] as Map, data = asset['data'] as Map;
      final script = (data['m_Script'] as Map)['reference'] as Map;
      if (asset['type'] != 'MonoBehaviour' ||
          asset['serializedFile'] != file ||
          script['status'] != 'resolved' ||
          script['type'] != 'MonoScript' ||
          script['name'] != 'LiveNoteEffectAsset' ||
          script['pathId'] != (data['m_Script'] as Map)['m_PathID'] ||
          widthAssets.containsKey(file)) {
        throw FormatException('native_effect_width_asset_identity:$file');
      }
      for (final entry in targets.entries) {
        for (final value in data[entry.key] as List) {
          final pointer = (value as Map)[entry.value.$1] as Map;
          final target = graph.objects['$file:${pointer['m_PathID']}'];
          if (pointer['m_FileID'] != 0 ||
              pointer['m_PathID'] is! String ||
              target?.type != entry.value.$2) {
            throw FormatException(
              'native_effect_width_target:$file:${entry.key}',
            );
          }
        }
      }
      widthAssets[file] = _freezeWidth(binding) as Map;
    }
    final bindings = await read('texture-bindings.json');
    if (bindings['schema'] != 'haneoka-native-fx-texture-bindings-v1') {
      throw const FormatException('native_effect_texture_binding_schema');
    }
    if (bindings['sourceId'] != sourceId ||
        recipe['sourceId'] != sourceId ||
        components['sourceId'] != sourceId ||
        recipe['server'] != server ||
        components['server'] != server) {
      throw const FormatException('native_effect_source_identity_mismatch');
    }
    final textures = <String, NativeTextureData>{};
    final identities = <String, String>{};
    for (final row in bindings['textures'] as List) {
      final key = (row as Map)['key'] as String,
          path = row['assetPath'] as String;
      final identity = '${row['serializedFile']}:${row['pathId']}';
      if (identities.containsKey(identity)) {
        throw StateError('native_effect_duplicate_texture_identity:$identity');
      }
      identities[identity] = 'fx:$key';
      if (textures.containsKey('fx:$key')) continue;
      final data = await rootBundle.load('$haneokaProfileAssetRoot$path');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (sha256.convert(bytes).toString() != row['sha256']) {
        throw StateError('native_effect_original_texture_hash:$key');
      }
      textures['fx:$key'] = await decodeNativeNumericTexture(bytes);
    }
    final materialTextureKeys = <String, String>{};
    for (final row in bindings['materials'] as List) {
      final key = (row as Map)['materialKey'] as String,
          value = 'fx:${row['textureKey']}';
      if (materialTextureKeys.containsKey(key) ||
          !textures.containsKey(value)) {
        throw StateError('native_effect_texture_binding_identity:$key');
      }
      final material = graph.objects[key];
      if (material == null || material.type != 'Material') {
        throw StateError('native_effect_bound_material_missing:$key');
      }
      final typed = NativeMobileHdrMaterial(material);
      final original = row['originalTexturePointer'] as Map;
      if (typed.texturePointer['m_PathID'] != original['m_PathID'] ||
          typed.texturePointer['m_FileID'] != original['m_FileID']) {
        throw StateError('native_effect_bound_material_pptr:$key');
      }
      materialTextureKeys[key] = value;
    }
    final loopData = await read('loop-controller-bindings.json');
    final loopControllers = <String, Map>{};
    for (final row in loopData['controllers'] as List) {
      final controller = row as Map;
      for (final rawBinding in controller['bindings'] as List) {
        final binding = rawBinding as Map;
        loopControllers[binding['serializedFile'] as String] =
            (controller['record'] as Map)['data'] as Map;
      }
    }
    final laneData = await read('lane-feedback.json');
    if (laneData['server'] != server || laneData['sourceId'] != sourceId) {
      throw const FormatException('chart_lane_feedback_source_identity');
    }
    final laneMaterial =
        ((laneData['material'] as Map)['record'] as Map)['data'] as Map;
    final properties = laneMaterial['m_SavedProperties'] as Map;
    final tint = (properties['m_Colors'] as List).single as List;
    if (((laneMaterial['m_Shader'] as Map)['reference'] as Map)['name'] !=
            'UI/Additive' ||
        tint.first != '_Color' ||
        (tint.last as Map).values.any((value) => value != 1)) {
      throw const FormatException('chart_lane_feedback_material');
    }
    final laneTexture = laneData['texture'] as Map;
    final laneBytes = await rootBundle.load('$base${laneTexture['filename']}');
    final lanePixels = laneBytes.buffer.asUint8List(
      laneBytes.offsetInBytes,
      laneBytes.lengthInBytes,
    );
    if (sha256.convert(lanePixels).toString() != laneTexture['sha256']) {
      throw const FormatException('chart_lane_feedback_texture_hash');
    }
    textures['fx:laneEffect'] = await decodeNativeNumericTexture(lanePixels);
    return NativeChartEffectSource._(
      graph,
      recipe,
      Map.unmodifiable(hashes),
      Map.unmodifiable(textures),
      Map.unmodifiable(materialTextureKeys),
      Map.unmodifiable(identities),
      Map.unmodifiable(animationBindings),
      Map.unmodifiable(widthAssets),
      Map.unmodifiable(loopControllers),
      ChartLaneFeedbackProfile(laneData),
    );
  }

  static Object? _freezeWidth(Object? value) => switch (value) {
    Map() => Map.unmodifiable({
      for (final e in value.entries) e.key: _freezeWidth(e.value),
    }),
    List() => List.unmodifiable(value.map(_freezeWidth)),
    _ => value,
  };

  String spriteTextureKey(NativeEffectObject sprite) {
    if (sprite.type != 'Sprite') {
      throw ArgumentError('native_effect_sprite_texture_type');
    }
    final pointer = (sprite.data['m_RD'] as Map)['texture'] as Map;
    if (pointer['m_FileID'] != 0 || pointer['m_PathID'] is! String) {
      throw UnsupportedError('native_effect_external_sprite_texture_identity');
    }
    final identity = '${sprite.serializedFile}:${pointer['m_PathID']}';
    final key = textureIdentityKeys[identity];
    if (key == null) {
      throw StateError('native_effect_sprite_texture_not_bound:$identity');
    }
    return key;
  }

  Map template(String tier, String kind) {
    final templates = (recipe['manifestTemplates'] as Map)[tier] as Map?;
    final value = templates?[kind];
    if (value is! Map) throw StateError('native_effect_template:$tier:$kind');
    return value;
  }

  @override
  NativeEffectObject component(String templateUrl) {
    const prefix = '/runtime/__release_template__/';
    if (!templateUrl.startsWith(prefix)) {
      throw FormatException('native_effect_template_uri:$templateUrl');
    }
    final path = 'runtime/${templateUrl.substring(prefix.length)}';
    final value = graph.paths[path];
    if (value == null) {
      throw StateError('native_effect_component_source_missing:$path');
    }
    return value;
  }

  NativeEffectObject animationRoot(NativeEffectObject owner) {
    final binding = animationBindings[owner.serializedFile];
    if (binding == null) {
      throw StateError('native_effect_animation_binding_missing:${owner.key}');
    }
    return graph
        .objects['${owner.serializedFile}:${binding['animationTransformId']}']!;
  }
}
