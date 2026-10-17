import 'package:vega_plugin_haneoka/render_profile.dart';

Map<String, Object?> _map(Object? v) => v is Map
    ? Map<String, Object?>.from(v)
    : throw const FormatException('native_font_binding_map');
Object? _freeze(Object? value) => switch (value) {
  Map() => Map<String, Object?>.unmodifiable(
    value.map((k, v) => MapEntry(k as String, _freeze(v))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
String _pointer(Object? value, String owner) {
  final raw = _map(value), id = raw['m_PathID'];
  if (id is! String || !RegExp(r'^-?\d+$').hasMatch(id)) {
    throw const FormatException('native_font_binding_pointer_id');
  }
  if (raw['m_FileID'] == 0) return '$owner:$id';
  final ref = _map(raw['reference']);
  if (ref['status'] != 'resolved' || ref['pathId'] != id) {
    throw const FormatException('native_font_binding_pointer_reference');
  }
  return '${ref['serializedFile']}:$id';
}

final class NativeStoryFontMaterialBinding {
  const NativeStoryFontMaterialBinding._({
    required this.primaryMaterialKey,
    required this.primaryMaterial,
    required this.targetDefaultMaterialKey,
    required this.targetDefaultMaterial,
    required this.fallbackAssetName,
    required this.sourcePath,
    required this.sourceHash,
    required this.matchMaterialPreset,
    required this.primaryProvenance,
    required this.targetProvenance,
    this.targetSourcePath,
    this.targetSourceHash,
  });
  final String primaryMaterialKey,
      targetDefaultMaterialKey,
      fallbackAssetName,
      sourcePath,
      sourceHash;
  final Map<String, Object?> primaryMaterial, targetDefaultMaterial;
  final Map<String, Object?> primaryProvenance, targetProvenance;
  final bool matchMaterialPreset;
  final String? targetSourcePath, targetSourceHash;
}

/// Immutable original font/preset bindings. Font IDs identify compact assets;
/// they do not select materials by a naming convention or rich-text style.
final class NativeStoryFontMaterialBindings {
  NativeStoryFontMaterialBindings._(
    this.raw,
    this.packetSHA256,
    this.sourcePath,
    this.sourceHash,
    this.matchMaterialPreset,
    this.materials,
  );
  final Map<String, Object?> raw, materials;
  final String packetSHA256, sourcePath, sourceHash;
  final bool matchMaterialPreset;
  final _resolved = <String, NativeStoryFontMaterialBinding>{};

  factory NativeStoryFontMaterialBindings.fromPacket({
    required Map<String, Object?> packet,
    required String packetSHA256,
    required StorySourceIdentity source,
    required Map<String, StoryFontData> fonts,
    required Map<String, Object?> materials,
    required String materialSHA256,
    required String assetBase,
  }) {
    if (packetSHA256 !=
            '84fe28d6a493ff18a675252865fdd4221f5608573cceb1f52b9aa94c1e68124c' ||
        packet['schema'] != 'haneoka-font-material-bindings-v1' ||
        source.server != 'intl' ||
        source.sourceId != 'v25-c0b6a1541e45-3a5d2eec9935-n653c6392' ||
        packet['sourceId'] != source.sourceId ||
        packet['materialPath'] != 'fonts/materials.json' ||
        packet['materialSHA256'] != materialSHA256) {
      throw const FormatException('native_font_binding_source');
    }
    final raw = _freeze(packet) as Map<String, Object?>;
    final records = _map(raw['fonts']);
    for (final entry in records.entries) {
      final record = _map(entry.value), font = fonts[entry.key];
      if (font == null ||
          record['fontId'] != font.id ||
          record['compactSHA256'] != font.sourceHash ||
          record['compactPath'] != 'fonts/${font.id}.json') {
        throw const FormatException('native_font_binding_compact_font');
      }
      final fields = _map(record['fields']), face = _map(fields['m_FaceInfo']);
      final script = _map(_map(fields['m_Script'])['reference']);
      if (fields['m_Name'] != record['assetName'] ||
          script['status'] != 'resolved' ||
          script['name'] != 'TMP_FontAsset' ||
          face['m_PointSize'] != font.size ||
          face['m_AscentLine'] != font.ascent ||
          face['m_DescentLine'] != font.descent ||
          face['m_LineHeight'] != font.lineHeight ||
          face['m_Scale'] != font.scale ||
          fields['m_AtlasWidth'] != font.atlasWidth ||
          fields['m_AtlasHeight'] != font.atlasHeight ||
          fields['m_AtlasPadding'] != font.padding ||
          fields['normalStyle'] != font.normalWeight ||
          fields['boldStyle'] != font.boldWeight ||
          fields['boldSpacing'] != font.boldSpacing) {
        throw const FormatException('native_font_binding_metrics');
      }
      final atlases = (record['compactAtlasAssets'] as List).cast<String>();
      if (atlases.length != font.atlasAssets.length ||
          [
            for (var i = 0; i < atlases.length; i++)
              '$assetBase'
                      'fonts/${atlases[i]}' !=
                  font.atlasAssets[i],
          ].any((v) => v)) {
        throw const FormatException('native_font_binding_atlas_assets');
      }
    }
    final sourceMaterials = _map(raw['materials']);
    for (final entry in sourceMaterials.entries) {
      final record = _map(entry.value), fields = _map(record['fields']);
      final compact = _map(materials[record['compactKey']]);
      final saved = _map(fields['m_SavedProperties']);
      final floats = _map(compact['floats']), colors = _map(compact['colors']);
      final sourceFloats = saved['m_Floats'] as List;
      final sourceColors = saved['m_Colors'] as List;
      if (fields['m_Name'] != record['materialName'] ||
          floats.length != sourceFloats.length ||
          colors.length != sourceColors.length) {
        throw const FormatException('native_font_binding_material_properties');
      }
      for (final item in sourceFloats.cast<List>()) {
        if (floats[item[0]] != item[1]) {
          throw const FormatException('native_font_binding_material_float');
        }
      }
      for (final item in sourceColors.cast<List>()) {
        final c = _map(item[1]), expected = colors[item[0]] as List;
        if (expected.length != 4 ||
            [
              for (var i = 0; i < 4; i++)
                expected[i] != c[const ['r', 'g', 'b', 'a'][i]],
            ].any((v) => v)) {
          throw const FormatException('native_font_binding_material_color');
        }
      }
      final keywords = compact['keywords'] as List;
      final original = fields['m_ValidKeywords'] as List;
      if (keywords.length != original.length ||
          [for (var i = 0; i < keywords.length; i++) keywords[i] != original[i]]
              .any((v) => v)) {
        throw const FormatException('native_font_binding_material_keywords');
      }
    }
    final settings = _map(raw['settings']);
    if (settings['matchMaterialPreset'] != true ||
        settings['settingsPacketSHA256'] !=
            'c8ebb4afa0078f22deddabe7a942854fdc062c47038bc76ecd8614fa3c6722c8') {
      throw const FormatException('native_font_binding_tmp_settings');
    }
    final result = NativeStoryFontMaterialBindings._(
      raw,
      packetSHA256,
      '$assetBase${raw['materialPath']}',
      materialSHA256,
      settings['matchMaterialPreset'] as bool,
      _freeze(materials) as Map<String, Object?>,
    );
    for (final item in raw['fallbackBindings'] as List) {
      final binding = _map(item);
      result.resolve(
        binding['primaryFontId'] as String,
        binding['selectedFontId'] as String,
        binding['primaryMaterialName'] as String,
      );
    }
    return result;
  }

  /// The Front text components use two distinct original presets. Their
  /// source packet is independent of the admitted Talk component preset.
  Map<String, NativeStoryFontMaterialBindings> frontPresets({
    required Map<String, Object?> packet,
    required String hash,
  }) {
    if (hash !=
            '03a9e6c9db273549c3e6eddd11b7301a96621a65865a68056b44c1d12f90f668' ||
        packet['schema'] != 'haneoka-native-front-font-materials-v1' ||
        packet['sourceId'] != raw['sourceId'] ||
        packet['existingFontBindingsSHA256'] != packetSHA256 ||
        packet['materialSHA256'] != sourceHash ||
        packet['frontBindingsSHA256'] !=
            '8a3260693d03dbee2b68a498a00b87ed61aee3ee770b4c3f9622327d0346a5eb') {
      throw const FormatException('native_front_font_binding_source');
    }
    final frozen = _freeze(packet) as Map<String, Object?>;
    final entries = frozen['bindings'] as List;
    if (entries.length != 2) {
      throw const FormatException('native_front_font_binding_count');
    }
    final output = <String, NativeStoryFontMaterialBindings>{};
    for (final item in entries) {
      final row = _map(item), record = _map(row['record']);
      final fields = _map(record['data']);
      final name = row['materialName'] as String;
      final expected = switch (name) {
        'A-OTF-ShinGoPr6N-Regular SDF Material' => '2682247313041229642',
        'A-OTF-ShinGoPr6N-Regular - OutlineAdvCommon' => '-9054838721446464938',
        _ => throw const FormatException('native_front_font_binding_preset'),
      };
      if (record['type'] != 'Material' ||
          record['pathId'] != expected ||
          record['serializedFile'] != 'CAB-ddfc6812aebf4e1007ac491baf92810e' ||
          fields['m_Name'] != name ||
          row['materialKey'] != 'dialogue:$name' ||
          row['primaryFontId'] != 'dialogue' ||
          row['selectedFontId'] != 'bold' ||
          row['fallbackTableIndex'] != 0 ||
          row['archiveSHA256'] !=
              '48fdb251a70e982fa74731254b7c414aece75d1d4a9d7dc185a9752c63df9a65' ||
          !materials.containsKey(row['materialKey'])) {
        throw const FormatException('native_front_font_binding_material');
      }
      final preset = {
        'materialName': name,
        'compactKey': row['materialKey'],
        'pathId': record['pathId'],
        'serializedFile': record['serializedFile'],
        'archivePath': row['archivePath'],
        'archiveSHA256': row['archiveSHA256'],
        'fields': fields,
      };
      final bound = _freeze({
        ...raw,
        'parentBindingPacketSHA256': packetSHA256,
        'fallbackBindings': [
          {
            'primaryFontId': row['primaryFontId'],
            'selectedFontId': row['selectedFontId'],
            'primaryMaterialName': name,
            'primaryMaterialKey': row['materialKey'],
            'fallbackTableIndex': row['fallbackTableIndex'],
            'originalFallbackPointer': row['originalFallbackPointer'],
            'targetDefaultMaterialKey': row['targetDefaultMaterialKey'],
          },
        ],
        'materials': {..._map(raw['materials']), 'primaryPreset': preset},
      }) as Map<String, Object?>;
      final binding = NativeStoryFontMaterialBindings._(
        bound,
        hash,
        sourcePath,
        sourceHash,
        matchMaterialPreset,
        materials,
      );
      // Existing resolver checks the real fallback edge and both atlas PPtrs.
      binding.resolve('dialogue', 'bold', name);
      output[name] = binding;
    }
    return Map.unmodifiable(output);
  }

  /// Localized presets and native font fallback PPtrs share one source packet.
  NativeStoryFontMaterialBinding resolveLocalized({
    required String primaryFontId,
    required String selectedFontId,
    required String primaryMaterialName,
    required Map<String, Object?> packet,
    required String localizedPacketHash,
    required String localizedSourcePath,
    required Map<String, StoryFontData> fontData,
    required Iterable<NativeStoryFontMaterialBindings> donorBindings,
  }) {
    final key = '$primaryFontId\u0000$selectedFontId\u0000$primaryMaterialName';
    if (_resolved[key] case final cached?) return cached;
    final sources = _map(packet['sources']);
    final primary = _map(sources[primaryFontId]);
    final primaryIdentity = _map(primary['fontIdentity']);
    final nativeFonts = _map(raw['fonts']);
    final target = _map(nativeFonts[selectedFontId]);
    final targetFields = _map(target['fields']);
    if (packet['schema'] != 'haneoka-localized-font-materials-v1' ||
        primary['compactSHA256'] != fontData[primaryFontId]?.sourceHash ||
        target['compactSHA256'] != fontData[selectedFontId]?.sourceHash) {
      throw const FormatException('native_localized_fallback_font_source');
    }
    final identities = <String, Map<String, Object?>>{
      for (final entry in nativeFonts.entries)
        entry.key: {
          'serializedFile': _map(entry.value)['serializedFile'],
          'pathId': _map(entry.value)['pathId'],
          'atlasTextures': _map(_map(entry.value)['fields'])['m_AtlasTextures'],
          'fallbackFonts': _map(
            _map(entry.value)['fields'],
          )['m_FallbackFontAssetTable'],
        },
      for (final entry in sources.entries)
        entry.key: _map(_map(entry.value)['fontIdentity']),
    };
    List<Object?>? pathTo(String id, Set<String> visited) {
      if (id == selectedFontId) return const [];
      if (!visited.add(id)) return null;
      final identity = identities[id]!;
      for (final pointer in identity['fallbackFonts'] as List) {
        final next = _pointer(pointer, identity['serializedFile'] as String);
        for (final entry in identities.entries) {
          if ('${entry.value['serializedFile']}:${entry.value['pathId']}' !=
              next) {
            continue;
          }
          final path = pathTo(entry.key, {...visited});
          if (path != null) return [pointer, ...path];
        }
      }
      return null;
    }

    final fallbackPath = pathTo(primaryFontId, {});
    if (fallbackPath == null || fallbackPath.isEmpty) {
      throw UnsupportedError('native_localized_fallback_edge:$key');
    }
    final selected = _map(
      _map(packet['presets'])[primaryMaterialName],
    )[primaryFontId];
    if (selected is! String) {
      throw UnsupportedError('native_localized_fallback_preset:$key');
    }
    final preset = _map(_map(primary['materials'])[selected]);
    final donorIdentity = _pointer(
      targetFields['m_Material'],
      target['serializedFile'] as String,
    );
    final donors =
        [
              _map(_map(raw['materials'])['targetDefault']),
              for (final binding in donorBindings)
                _map(_map(binding.raw['materials'])['primaryPreset']),
            ]
            .where(
              (record) =>
                  '${record['serializedFile']}:${record['pathId']}' ==
                  donorIdentity,
            )
            .toList();
    if (donors.length != 1 || selected != '$primaryFontId:${preset['name']}') {
      throw const FormatException('native_localized_fallback_material_source');
    }
    final donor = donors.single;
    void atlas(Map<String, Object?> identity, List textures, String owner) {
      final main = textures.cast<List>().singleWhere(
        (entry) => entry[0] == '_MainTex',
      );
      final texture = _pointer(_map(main[1])['m_Texture'], owner);
      if (!(identity['atlasTextures'] as List).any(
        (pointer) =>
            _pointer(pointer, identity['serializedFile'] as String) == texture,
      )) {
        throw const FormatException('native_localized_fallback_atlas');
      }
    }

    atlas(
      primaryIdentity,
      preset['textures'] as List,
      preset['serializedFile'] as String,
    );
    atlas(
      identities[selectedFontId]!,
      _map(_map(donor['fields'])['m_SavedProperties'])['m_TexEnvs'] as List,
      donor['serializedFile'] as String,
    );
    final donorKey = donor['compactKey'] as String;
    final primaryMaterial = materials[selected],
        targetMaterial = materials[donorKey];
    if (primaryMaterial is! Map<String, Object?> ||
        targetMaterial is! Map<String, Object?>) {
      throw const FormatException('native_localized_fallback_compact_material');
    }
    final result = NativeStoryFontMaterialBinding._(
      primaryMaterialKey: selected,
      primaryMaterial: primaryMaterial,
      targetDefaultMaterialKey: donorKey,
      targetDefaultMaterial: targetMaterial,
      fallbackAssetName: target['assetName'] as String,
      sourcePath: localizedSourcePath,
      sourceHash: localizedPacketHash,
      targetSourcePath: sourcePath,
      targetSourceHash: sourceHash,
      matchMaterialPreset: matchMaterialPreset,
      primaryProvenance: _freeze({
        'sourceId': primary['sourceId'],
        'bindingPacketSHA256': localizedPacketHash,
        'materialPacketSHA256': localizedPacketHash,
        'font': primary,
        'material': preset,
        'fallbackPath': fallbackPath,
        'settings': raw['settings'],
      }) as Map<String, Object?>,
      targetProvenance: _freeze({
        'sourceId': raw['sourceId'],
        'bindingPacketSHA256': packetSHA256,
        'materialPacketSHA256': sourceHash,
        'font': target,
        'material': donor,
        'fallbackPath': fallbackPath,
        'settings': raw['settings'],
      }) as Map<String, Object?>,
    );
    _resolved[key] = result;
    return result;
  }

  NativeStoryFontMaterialBinding resolve(
    String primaryFontId,
    String selectedFontId,
    String primaryMaterialName,
  ) {
    final key = '$primaryFontId\u0000$selectedFontId\u0000$primaryMaterialName';
    if (_resolved[key] case final cached?) return cached;
    final bindings = (raw['fallbackBindings'] as List).cast<Map>().where(
      (v) =>
          v['primaryFontId'] == primaryFontId &&
          v['selectedFontId'] == selectedFontId &&
          v['primaryMaterialName'] == primaryMaterialName,
    );
    if (primaryFontId == selectedFontId || bindings.length != 1) {
      throw UnsupportedError('native_font_material_binding:$key');
    }
    final binding = bindings.single;
    final fonts = _map(raw['fonts']);
    final primary = _map(fonts[primaryFontId]),
        target = _map(fonts[selectedFontId]);
    final sourceMaterials = _map(raw['materials']);
    final preset = _map(sourceMaterials['primaryPreset']);
    final donor = _map(sourceMaterials['targetDefault']);
    final primaryFields = _map(primary['fields']),
        targetFields = _map(target['fields']);
    final targetIdentity = '${target['serializedFile']}:${target['pathId']}';
    final fallbacks = primaryFields['m_FallbackFontAssetTable'] as List;
    final index = binding['fallbackTableIndex'] as int;
    if (index < 0 ||
        index >= fallbacks.length ||
        _pointer(fallbacks[index], primary['serializedFile'] as String) !=
            targetIdentity ||
        _pointer(
              binding['originalFallbackPointer'],
              primary['serializedFile'] as String,
            ) !=
            targetIdentity ||
        preset['materialName'] != primaryMaterialName ||
        preset['compactKey'] != binding['primaryMaterialKey'] ||
        donor['compactKey'] != binding['targetDefaultMaterialKey'] ||
        _pointer(
              targetFields['m_Material'],
              target['serializedFile'] as String,
            ) !=
            '${donor['serializedFile']}:${donor['pathId']}') {
      throw const FormatException('native_font_binding_fallback_edge');
    }
    void atlas(Map<String, Object?> font, Map<String, Object?> material) {
      final fields = _map(material['fields']);
      final textures = _map(fields['m_SavedProperties'])['m_TexEnvs'] as List;
      final main = textures.cast<List>().singleWhere((v) => v[0] == '_MainTex');
      final pointer = _map(main[1])['m_Texture'];
      final fontAtlases = _map(font['fields'])['m_AtlasTextures'] as List;
      if (fontAtlases.length != 1 ||
          _pointer(pointer, material['serializedFile'] as String) !=
              _pointer(fontAtlases.single, font['serializedFile'] as String)) {
        throw const FormatException('native_font_binding_material_atlas');
      }
    }

    atlas(primary, preset);
    atlas(target, donor);
    Map<String, Object?> provenance(
      Map<String, Object?> font,
      Map<String, Object?> material,
    ) => _freeze({
      'sourceId': raw['sourceId'],
      'bindingPacketSHA256': packetSHA256,
      if (raw['parentBindingPacketSHA256'] case final String parentHash)
        'parentBindingPacketSHA256': parentHash,
      'materialPacketSHA256': sourceHash,
      'font': font,
      'material': material,
      'fallbackEdge': binding,
      'settings': raw['settings'],
    }) as Map<String, Object?>;
    final result = NativeStoryFontMaterialBinding._(
      primaryMaterialKey: preset['compactKey'] as String,
      primaryMaterial: materials[preset['compactKey']] as Map<String, Object?>,
      targetDefaultMaterialKey: donor['compactKey'] as String,
      targetDefaultMaterial:
          materials[donor['compactKey']] as Map<String, Object?>,
      fallbackAssetName: target['assetName'] as String,
      sourcePath: sourcePath,
      sourceHash: sourceHash,
      matchMaterialPreset: matchMaterialPreset,
      primaryProvenance: provenance(primary, preset),
      targetProvenance: provenance(target, donor),
    );
    _resolved[key] = result;
    return result;
  }
}
