import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show HaneokaProfileAssets, haneokaProfileAssetRoot;

import 'dart:convert';

import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_ui_graphics_source.dart';
import 'native_story_font_material_bindings.dart';
import 'native_story_ui_layout_source.dart';
import 'native_story_front_ui_source.dart';

/// Original local UI resources, scoped to their actual source release family.
/// Geometry, font metrics and component bindings retain separate provenance.
final class NativeStoryUiSource {
  NativeStoryUiSource._(
    this.scenes,
    this.fonts,
    this.materials,
    this.bindings,
    this.typing,
    this.lineBreakRules,
    this.sourceHashes,
    this.graphics,
    this.controls,
    this.fontMaterialBindings,
    this.layoutSource,
    this.front,
    this.frontFontPresets,
    this.frontScene,
    this.frontLayout,
    this.localizedFontMaterials,
    Map<String, bool> textExtraPadding,
  ) : _textExtraPadding = Map.unmodifiable(textExtraPadding);
  static const sourceId = 'v25-c0b6a1541e45-3a5d2eec9935-n653c6392';
  static const base = '${haneokaProfileAssetRoot}story-ui/';
  final StoryUiSceneData scenes;
  final Map<String, StoryFontData> fonts;
  final Map<String, Object?> materials;
  final Map<String, Object?> bindings, typing;
  final StoryLineBreakRules lineBreakRules;
  final Map<String, String> sourceHashes;
  final NativeStoryUiGraphicsSource graphics;
  final StoryUiControlBindings controls;
  final NativeStoryFontMaterialBindings fontMaterialBindings;
  final NativeStoryUiLayoutSource layoutSource;
  final NativeStoryFrontUiSource front;
  final StoryUiSceneData frontScene;
  final NativeStoryUiLayoutWindow frontLayout;
  final Map<String, Object?> localizedFontMaterials;
  final Map<String, NativeStoryFontMaterialBindings> frontFontPresets;
  final Map<String, bool> _textExtraPadding;

  StoryRetainedUiSourceBinding retainedLayoutBinding(
    StorySourceIdentity identity,
    String layoutHash,
  ) => StoryRetainedUiSourceBinding(
    sourceIdentity: jsonEncode(identity.toJson()),
    layoutHash: layoutHash,
  );

  void validateSavedResources(Object? saved) {
    if (saved is! Map ||
        saved.length != sourceHashes.length ||
        sourceHashes.entries.any((entry) => saved[entry.key] != entry.value)) {
      throw const FormatException('story_ui_save_resources_changed');
    }
  }

  static Future<NativeStoryUiSource> load(StorySourceIdentity source) async {
    if (source.server != 'intl' || source.sourceId != sourceId) {
      throw UnsupportedError(
        'native_story_ui_source:${source.server}:${source.sourceId}',
      );
    }
    final profile = await HaneokaProfileAssets.open();
    final hashes = <String, String>{'profile-manifest': profile.manifestSHA256};
    Future<Map<String, Object?>> read(String path) async {
      final packet = await profile.loadJson('$base$path');
      hashes[path] = packet.sha256;
      return packet.data;
    }

    final sceneData = await read('ui/scenes.json');
    final fontData = <String, StoryFontData>{};
    for (final name in [
      'dialogue',
      'bold',
      'symbols',
      'chat',
      'numeric',
      'chinese',
      'korean',
    ]) {
      final path = 'fonts/$name.json', raw = await read('fonts/$name.json');
      final atlases = (raw['atlases'] as List).cast<String>();
      if (atlases.any((path) => path.contains('/') || !path.endsWith('.png'))) {
        throw const FormatException('native_story_font_atlas_asset');
      }
      fontData[name] = StoryFontData.fromJson(
        raw,
        sourceHash: hashes[path]!,
        coverageChannel: profile.fontCoverageChannel([
          for (final atlas in atlases) '${base}fonts/$atlas',
        ]),
        actualAtlasAssetKeys: [
          for (final atlas in atlases) '${base}fonts/$atlas',
        ],
      );
    }
    final materials = await read('fonts/materials.json');
    final localizedFontMaterials = await read(
      'source-bindings/localized-font-materials.json',
    );
    if (localizedFontMaterials['schema'] !=
        'haneoka-localized-font-materials-v1') {
      throw const FormatException('native_localized_font_material_schema');
    }
    for (final entry in (localizedFontMaterials['sources'] as Map).entries) {
      if ((entry.value as Map)['compactSHA256'] !=
          fontData[entry.key]?.sourceHash) {
        throw const FormatException('native_localized_font_material_binding');
      }
    }
    materials.addAll(
      Map<String, Object?>.from(localizedFontMaterials['materials'] as Map),
    );
    final bindings = await read('source-bindings/text-components.json');
    final typing = await read('source-bindings/typing.json');
    final linebreak = await read('source-bindings/linebreak.json');
    if (bindings['sourceId'] != source.sourceId ||
        typing['sourceId'] != source.sourceId ||
        linebreak['sourceId'] != source.sourceId ||
        hashes['source-bindings/linebreak.json'] !=
            'e679e4fcc79d37e1f2b53ef59e7cf60ce7729110caef00335c2a93fab91ae138') {
      throw const FormatException('native_story_ui_binding_source');
    }
    final graphics = await NativeStoryUiGraphicsSource.load(source);
    hashes['source-bindings/graphics-components.json'] = graphics.sourceHash;
    final scenes = StoryUiSceneData.fromJson(
      sceneData,
      hashes['ui/scenes.json']!,
    );
    final frontPacket = await read('source-bindings/front-ui-bindings.json');
    final baseFront = NativeStoryFrontUiSource.fromPacket(
      packet: frontPacket,
      hash: hashes['source-bindings/front-ui-bindings.json']!,
      source: source,
    );
    final nextPacket = await read('source-bindings/front-next-bindings.json');
    final nextFront = baseFront.withNext(
      nextPacket,
      hashes['source-bindings/front-next-bindings.json']!,
    );
    final spritePacket = await read('source-bindings/front-sprites.json');
    final spriteFront = nextFront.withSprites(
      spritePacket,
      hashes['source-bindings/front-sprites.json']!,
    );
    final locationPacket = await read(
      'source-bindings/location-ui-bindings.json',
    );
    final locationFront = spriteFront.withLocation(
      locationPacket,
      hashes['source-bindings/location-ui-bindings.json']!,
    );
    final front = locationFront.withLocationAnimation(
      await read('source-bindings/location-animation.json'),
    );

    final controlData = await read('source-bindings/talk-controls.json');
    if (hashes['source-bindings/talk-controls.json'] !=
        '777b064e58c76a24d1ef17479de8299b7640625966673fb29e87b9ab07083414') {
      throw const FormatException('native_story_talk_controls_identity');
    }
    final controls = StoryUiControlBindings.fromPacket(
      packet: controlData,
      source: source,
      packetSHA256: hashes['source-bindings/talk-controls.json']!,
      scenes: scenes,
    );
    graphics.verifyControls(controls);
    final layoutPacket = await read('source-bindings/ui-layout-nodes.json');
    final layoutSource = NativeStoryUiLayoutSource.fromPacket(
      packet: layoutPacket,
      hash: hashes['source-bindings/ui-layout-nodes.json']!,
      source: source,
      scenes: scenes,
      controls: controls,
    );
    final fontBindingData = await read(
      'source-bindings/font-material-bindings.json',
    );
    final fontBindings = NativeStoryFontMaterialBindings.fromPacket(
      packet: fontBindingData,
      packetSHA256: hashes['source-bindings/font-material-bindings.json']!,
      source: source,
      fonts: fontData,
      materials: materials,
      materialSHA256: hashes['fonts/materials.json']!,
      assetBase: base,
    );
    if (hashes['source-bindings/text-components.json'] !=
        'd926a4f0883197a4a12d1bfb88cf9c14819404978761cd377413200a0f5934ac') {
      throw const FormatException('native_story_text_padding_packet');
    }
    final textPadding = <String, bool>{};
    for (final entry in controls.windows.entries) {
      final mode = entry.key, window = entry.value;
      final proofs = (bindings['sources'] as List).cast<Map>().where(
        (v) => v['mode'] == mode,
      );
      if (proofs.length != 1 ||
          proofs.single['sourceUiHash'] != window.visibility.sourceUiHash) {
        throw const FormatException('native_story_text_padding_source');
      }
      for (final field in ['TalkText', 'SpeakerText']) {
        final endpoint = window.endpoints[field];
        if (endpoint == null) continue;
        final originalRef =
            ((window.visibility.original['references'] as Map)[field] as Map);
        final originalEndpoint = originalRef['endpoint'] as Map;
        final wrapper = (originalEndpoint['object'] as Map)['data'] as Map;
        final target = wrapper['_targetText'] as Map;
        final components = (originalEndpoint['components'] as List)
            .cast<Map>()
            .where((v) => v['pathId'] == target['m_PathID']);
        final text = (bindings[mode] as Map)[field] as Map;
        if (target['m_FileID'] != 0 ||
            components.length != 1 ||
            components.single['serializedFile'] != window.serializedFile ||
            (text['m_GameObject'] as Map)['m_PathID'].toString() !=
                endpoint.gameObjectId) {
          throw const FormatException('native_story_text_padding_component');
        }
        final original = components.single['data'] as Map;
        if ((original['m_GameObject'] as Map)['m_PathID'] !=
                endpoint.gameObjectId ||
            !(proofs.single['selectedObjects'] as List).cast<Map>().any(
              (v) =>
                  v['pathId'] == target['m_PathID'] &&
                  v['serializedFile'] == window.serializedFile,
            )) {
          throw const FormatException('native_story_text_padding_original');
        }
        final flag = text['m_enableExtraPadding'];
        if (flag != original['m_enableExtraPadding'] ||
            (flag != 0 && flag != 1 && flag != false && flag != true)) {
          throw const FormatException('native_story_text_padding_flag');
        }
        textPadding['$mode\u0000${endpoint.path}'] = flag == 1 || flag == true;
      }
    }
    final frontFontPacket = await read(
      'source-bindings/front-font-materials.json',
    );
    final frontFontPresets = fontBindings.frontPresets(
      packet: frontFontPacket,
      hash: hashes['source-bindings/front-font-materials.json']!,
    );
    final frontScene = front.scene(
      scenes,
      graphicSprites: graphics.spriteRecords,
    );
    final frontLayout = front.retainedWindow(frontScene);
    return NativeStoryUiSource._(
      scenes,
      Map.unmodifiable(fontData),
      Map.unmodifiable(materials),
      Map.unmodifiable(bindings),
      Map.unmodifiable(typing),
      StoryLineBreakRules(
        leading: (linebreak['lineBreaking'] as Map)['leading'] as String,
        following: (linebreak['lineBreaking'] as Map)['following'] as String,
        useModernHangulLineBreakingRules:
            (linebreak['lineBreaking']
                    as Map)['useModernHangulLineBreakingRules']
                as bool,
      ),
      Map.unmodifiable(hashes),
      graphics,
      controls,
      fontBindings,
      layoutSource,
      front,
      frontFontPresets,
      frontScene,
      frontLayout,
      Map.unmodifiable(localizedFontMaterials),
      textPadding,
    );
  }

  NativeStoryFontMaterialBinding fontMaterialBinding(
    String primaryFontId,
    String selectedFontId,
    String primaryMaterialName,
  ) {
    if ((localizedFontMaterials['sources'] as Map).containsKey(primaryFontId)) {
      return fontMaterialBindings.resolveLocalized(
        primaryFontId: primaryFontId,
        selectedFontId: selectedFontId,
        primaryMaterialName: primaryMaterialName,
        packet: localizedFontMaterials,
        localizedPacketHash:
            sourceHashes['source-bindings/localized-font-materials.json']!,
        localizedSourcePath:
            '${base}source-bindings/localized-font-materials.json',
        fontData: fonts,
        donorBindings: frontFontPresets.values,
      );
    }
    return fontMaterialBindings.resolve(
      primaryFontId,
      selectedFontId,
      primaryMaterialName,
    );
  }

  bool fontMaterialExtraPadding(String mode, String nodePath) {
    final key = '$mode\u0000$nodePath';
    final value = _textExtraPadding[key];
    if (value == null) {
      throw UnsupportedError('native_story_text_padding_binding:$key');
    }
    return value;
  }

  StoryTextSourceBinding textBinding(String mode, {bool speaker = false}) {
    final components = bindings[mode] as Map?;
    final textKey = speaker ? 'SpeakerText' : 'TalkText';
    final rubyKey = speaker ? 'SpeakerRuby' : 'TalkRuby';
    final component = components?[textKey];
    if (component is! Map) {
      throw UnsupportedError('native_story_ui_component:$mode:$textKey');
    }
    final proof = (bindings['sources'] as List).cast<Map>().singleWhere(
      (row) => row['mode'] == mode,
    );
    final window = controls.windows[mode]!;
    final reference =
        (window.visibility.original['references'] as Map)[textKey] as Map;
    final endpoint = reference['endpoint'] as Map;
    final wrapper = (endpoint['object'] as Map)['data'] as Map;
    final localize = wrapper['_localizeText'] as Map;
    final localizeComponent = (endpoint['components'] as List)
        .cast<Map>()
        .singleWhere(
          (record) =>
              record['pathId'] == localize['m_PathID'] &&
              record['serializedFile'] == window.serializedFile,
        );
    return StoryTextSourceBinding.fromRaw(
      sourceHash: proof['archiveSHA256'] as String,
      component: Map<String, Object?>.from(component),
      uiRubyComponent: components?[rubyKey] is Map
          ? Map<String, Object?>.from(components![rubyKey] as Map)
          : null,
      localizeComponent: Map<String, Object?>.from(
        localizeComponent['data'] as Map,
      ),
    );
  }

  double typingDelay(String mode) {
    final path = mode == 'Default'
        ? 'UIDefaultTalkWindow.prefab'
        : mode == 'Center'
        ? 'UICenterTalkWindow.prefab'
        : null;
    if (path == null) {
      throw UnsupportedError('native_story_typing_window:$mode');
    }
    final row = (typing['rows'] as List).cast<Map>().singleWhere(
      (row) => (row['sourceUiPath'] as String).endsWith(path),
    );
    return (row['typingDelaySeconds'] as num).toDouble();
  }

  StoryFontBank fontBank(String locale, {bool chat = false}) {
    final primary = locale.startsWith('zh')
        ? 'chinese'
        : locale.startsWith('ko')
        ? 'korean'
        : 'dialogue';
    final names = <String>[
      if (chat && locale.startsWith('ja')) 'chat',
      primary,
      'dialogue',
      'bold',
      'symbols',
      'chinese',
      'korean',
    ];
    return StoryFontBank([for (final name in names.toSet()) fonts[name]!]);
  }

  StorySdfMaterialData sdfMaterial(
    StoryFontData font,
    String sourceMaterialName,
  ) {
    final key = localizedMaterialKey(font, sourceMaterialName);
    final value = materials[key];
    if (key == null || value is! Map) {
      throw UnsupportedError('native_story_source_font_material:$key');
    }
    return StorySdfMaterialData.fromRaw(
      Map<String, Object?>.from(value),
      actualFont: font,
      sourceMaterialKey: key,
      sourcePath: materialSourcePath(key),
      sourceHash: materialSourceHash(key),
    );
  }

  String? localizedMaterialKey(StoryFontData font, String sourceName) {
    final exact = '${font.id}:$sourceName';
    if (materials.containsKey(exact)) return exact;
    final selected =
        ((localizedFontMaterials['presets'] as Map)[sourceName]
            as Map?)?[font.id];
    return selected is String ? selected : null;
  }

  String _materialSource(String key) =>
      (localizedFontMaterials['materials'] as Map).containsKey(key)
      ? 'source-bindings/localized-font-materials.json'
      : 'fonts/materials.json';

  String materialSourcePath(String key) => '$base${_materialSource(key)}';
  String materialSourceHash(String key) => sourceHashes[_materialSource(key)]!;
}
