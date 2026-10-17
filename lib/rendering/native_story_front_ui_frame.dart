import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_front_ui_runtime.dart';
import 'native_story_sdf.dart';
import 'native_story_ui_source.dart';

final class NativeStoryFrontUiSnapshot {
  const NativeStoryFrontUiSnapshot(
    this.meshes,
    this.materials,
    this.draws,
    this.textures,
    this.glyphs,
    this.hitRects,
    this.unsupported,
  );
  final Map<String, ProjectedMesh> meshes;
  final Map<String, NativeMaterial> materials;
  final List<NativeDraw> draws;
  final Map<String, Uri> textures;
  final Map<String, StoryGlyphLayout> glyphs;
  final Map<int, StoryUiRect> hitRects;
  final List<String> unsupported;
}

final class _FrontCache {
  StoryRetainedUiLayoutState? retained;
  Object? scope;
  final materials = <String, StorySdfMaterialData>{};
  final glyphs = <String, StoryGlyphLayout>{};
}

final _caches = Expando<_FrontCache>();

final class NativeStoryFrontRetainedCheckpoint {
  NativeStoryFrontRetainedCheckpoint._(_FrontCache cache)
    : _scope = cache.scope,
      _state = cache.retained,
      _snapshot = cache.retained?.snapshot();
  final Object? _scope;
  final StoryRetainedUiLayoutState? _state;
  final StoryRetainedUiLayoutSnapshot? _snapshot;

  Map<String, Object?> toData({
    required NativeStoryUiSource ui,
    required StorySourceIdentity identity,
  }) {
    if (_snapshot != null) {
      final scope = _scope as (String, String, String, int, String, String?);
      if (scope.$1 != identity.server ||
          scope.$2 != identity.release ||
          scope.$3 != identity.document ||
          scope.$5 != ui.front.hash ||
          scope.$6 != ui.front.nextBindingHash) {
        throw const FormatException('story_front_layout_data_scope');
      }
    }
    return {
      'version': 1,
      'layout': _snapshot?.toData(
        binding: ui.retainedLayoutBinding(
          identity,
          '${ui.front.hash}:${ui.front.nextBindingHash}',
        ),
      ),
    };
  }
}

void restoreNativeStoryFrontRetainedData(
  NativeStoryUiSource ui,
  Map data, {
  required StorySourceIdentity identity,
  required int epoch,
  required int storyUs,
  required int updateIndex,
}) {
  if (data['version'] != 1) {
    throw const FormatException('story_front_layout_data_version');
  }
  final cache = _caches[ui] ??= _FrontCache();
  cache.scope = (
    identity.server,
    identity.release,
    identity.document,
    epoch,
    ui.front.hash,
    ui.front.nextBindingHash,
  );
  cache.retained = StoryRetainedUiLayoutState(
    sourceScope: cache.scope!,
    nodes: ui.frontLayout.nodes,
  );
  if (data['layout'] != null) {
    cache.retained!.restoreData(
      data['layout'] as Map,
      expectedBinding: ui.retainedLayoutBinding(
        identity,
        '${ui.front.hash}:${ui.front.nextBindingHash}',
      ),
      actualUs: storyUs,
      actualUpdateIndex: updateIndex,
    );
  }
}

NativeStoryFrontRetainedCheckpoint captureNativeStoryFrontRetainedLayout(
  NativeStoryUiSource ui,
) => NativeStoryFrontRetainedCheckpoint._(_caches[ui] ??= _FrontCache());

void restoreNativeStoryFrontRetainedLayout(
  NativeStoryUiSource ui,
  NativeStoryFrontRetainedCheckpoint checkpoint,
) {
  final cache = _caches[ui] ??= _FrontCache();
  cache.scope = checkpoint._scope;
  cache.retained = checkpoint._state;
  if (checkpoint._snapshot != null) {
    cache.retained!.restore(checkpoint._snapshot);
  }
}

NativeStoryFrontUiSnapshot buildNativeStoryFrontUiFrame({
  required NativeStoryUiSource ui,
  required NativeStoryFrontUiRuntime runtime,
  required RenderSource source,
  required int epoch,
  required int storyUs,
  required int updateIndex,
  required int width,
  required int height,
  required String locale,
  double textSize = 1,
  bool layoutOnly = false,
}) {
  final cache = _caches[ui] ??= _FrontCache();
  final scaler = ui.graphics.frontScaler,
      reference = scaler['m_ReferenceResolution'] as Map;
  final screenScale = math.min(
    width / (reference['x'] as num),
    height / (reference['y'] as num),
  );
  final cw = width / screenScale, ch = height / screenScale;
  final data = ui.frontLayout, roots = ui.frontScene.scenes['Front']!;
  final scope = (
    source.server,
    source.release,
    source.document,
    epoch,
    ui.front.hash,
    ui.front.nextBindingHash,
  );
  if (cache.scope != scope) {
    cache.scope = scope;
    cache.retained = StoryRetainedUiLayoutState(
      sourceScope: scope,
      nodes: data.nodes,
    );
  }
  final retained = cache.retained!;
  final active = <String, bool>{
    data.gameObjectToId[ui.front.domains['Subtitles']!['rootGameObjectId']]!:
        runtime.captionVisible,
  };
  final nextIndicator = data.pathToId.entries
      .singleWhere((entry) => entry.key.endsWith('/UIContainer/NextIndicator'))
      .value;
  active[nextIndicator] =
      runtime.captionVisible && runtime.nextVisible && !runtime.nextLocked;
  active[data.gameObjectToId[ui
          .front
          .domains['Location']!['rootGameObjectId']]!] =
      runtime.locationVisible;
  final itemIds = ui.front.choiceItemIds;
  final choice = runtime.choices;
  for (var i = 0; i < itemIds.length; i++) {
    final component = ui.front.records[itemIds[i]]!['data'] as Map;
    final go = (component['m_GameObject'] as Map)['m_PathID'];
    active[data.gameObjectToId[go]!] =
        choice != null && choice.nextButtonLocked && i < choice.choices.length;
  }
  retained.beginLayout(
    canvas: StoryUiRect(-cw / 2, -ch / 2, cw, ch),
    actualUs: storyUs,
    actualUpdateIndex: updateIndex,
    sourceScope: scope,
    activeOverrides: active,
    poses: {
      for (final id in {
        ...runtime.anchoredXOverrides.keys,
        ...runtime.anchoredYOverrides.keys,
      })
        id: StoryRetainedUiPose(
          anchoredX: runtime.anchoredXOverrides[id],
          anchoredY: runtime.anchoredYOverrides[id],
        ),
    },
  );
  final nodes = <StoryUiLayoutNode>[];
  void collect(StoryUiLayoutNode n) {
    nodes.add(n);
    for (final c in n.children) {
      collect(c);
    }
  }

  for (final n in roots) {
    collect(n);
  }
  final rubyByPath = <String, String>{};
  final canvasPrefix = ui.front.paths[data.pathToId[roots.first.path]]!;
  for (final ruby in runtime.textByRubyId.keys) {
    final tmp = ui.front.textComponent(ruby)['data'] as Map;
    final go = (tmp['m_GameObject'] as Map)['m_PathID'];
    final id = data.gameObjectToId[go]!;
    final original = ui.front.paths[id]!;
    rubyByPath['${roots.first.path}${original.substring(canvasPrefix.length)}'] =
        ruby;
  }
  final texts = {
    for (final e in rubyByPath.entries) e.key: runtime.textByRubyId[e.value]!,
  };
  final fonts = ui.fontBank(locale), measured = <String, StoryGlyphLayout>{};
  StorySdfMaterialData material(StoryUiLayoutNode n, StoryFontData font) {
    final key = '${n.text!.materialName}:${font.id}:${font.sourceHash}';
    return cache.materials.putIfAbsent(key, () {
      final primary = fonts.fonts.first;
      if (font.id == primary.id) {
        return ui.sdfMaterial(font, n.text!.materialName);
      }
      final bindings = ui.frontFontPresets[n.text!.materialName];
      if (bindings == null) {
        throw UnsupportedError(
          'native_front_font_preset:${n.text!.materialName}',
        );
      }
      final binding = ui.fontMaterialBinding(
        primary.id,
        font.id,
        n.text!.materialName,
        originalBindings: bindings,
      );
      return nativeStoryFallbackSdfMaterial(
        primaryFont: primary,
        actualFont: font,
        primaryMaterialName: n.text!.materialName,
        fallbackAssetName: binding.fallbackAssetName,
        primaryMaterialKey: binding.primaryMaterialKey,
        targetDefaultMaterialKey: binding.targetDefaultMaterialKey,
        primaryMaterial: binding.primaryMaterial,
        targetDefaultMaterial: binding.targetDefaultMaterial,
        primaryProvenance: binding.primaryProvenance,
        targetProvenance: binding.targetProvenance,
        sourcePath: binding.sourcePath,
        sourceHash: binding.sourceHash,
        targetSourcePath: binding.targetSourcePath,
        targetSourceHash: binding.targetSourceHash,
        matchMaterialPreset: binding.matchMaterialPreset,
      ).material;
    });
  }

  StoryGlyphLayout compile(StoryUiLayoutNode n, double w, double h) {
    final ruby = rubyByPath[n.path]!, text = texts[n.path]!;
    final key = '$locale:${n.path}:$w:$h:$textSize:$text';
    if (cache.glyphs.length > 128) cache.glyphs.clear();
    return cache.glyphs.putIfAbsent(
      key,
      () => compileMeasuredStoryUiText(
        source: text,
        textData: n.text!,
        fontScale: textSize,
        binding: ui.front.textBinding(ruby),
        fonts: fonts,
        width: w,
        height: h,
        lineBreakRules: ui.lineBreakRules,
        paddingResolver: (f, bold) => nativeStorySdfGlyphPadding(
          material(n, f),
          f,
          bold: bold,
          extraPadding: ui.front.textExtraPadding(ruby),
        ),
      ),
    );
  }

  for (final n in nodes) {
    if (rubyByPath.containsKey(n.path)) measured[n.path] = compile(n, 0, 0);
  }
  final first = layoutRetainedMeasuredStoryUi(
    roots: roots,
    state: retained,
    pathToId: data.pathToId,
    measuredText: measured,
    actualGroups: data.groups,
    actualFits: data.fits,
    actualElements: data.elements,
  );
  for (final n in nodes) {
    if (rubyByPath.containsKey(n.path)) {
      final r = first.rects[n.path]!;
      measured[n.path] = compile(n, r.width, r.height);
    }
  }
  layoutRetainedMeasuredStoryUi(
    roots: roots,
    state: retained,
    pathToId: data.pathToId,
    measuredText: measured,
    actualGroups: data.groups,
    actualFits: data.fits,
    actualElements: data.elements,
  );
  if (layoutOnly) {
    return NativeStoryFrontUiSnapshot(
      const {},
      const {},
      const [],
      const {},
      measured,
      const {},
      const [],
    );
  }
  final positions = retained.basePlacements,
      matrices = resolveRetainedStoryUiAffine(retained);
  final meshes = <String, ProjectedMesh>{},
      materials = <String, NativeMaterial>{},
      textures = <String, Uri>{};
  final draws = <NativeDraw>[], unsupported = <String>[];
  final alphaOverrides = <String, double>{};
  for (final e in runtime.alphaOverrides.entries) {
    final component = ui.front.records[e.key]!['data'] as Map;
    final go = (component['m_GameObject'] as Map)['m_PathID'];
    alphaOverrides[data.gameObjectToId[go]!] = e.value;
  }
  final choiceGroup =
      (ui.front.controller('Choice')['_canvasGroup'] as Map)['m_PathID'];
  final choiceGroupGo =
      ((ui.front.records[choiceGroup]!['data'] as Map)['m_GameObject']
          as Map)['m_PathID'];
  alphaOverrides[data.gameObjectToId[choiceGroupGo]!] =
      choice != null && choice.nextButtonLocked ? 1.0 : 0.0;
  final alpha = <String, double>{};
  double opacity(String id) {
    if (alpha[id] case final v?) return v;
    final p = positions[id]!;
    // CanvasGroup alpha is bounded coverage; Animator float evaluation can
    // overshoot an authored endpoint by one float32 ULP.
    final raw = alphaOverrides[id] ?? data.groupAlpha[id] ?? 1.0;
    if (!raw.isFinite) {
      throw UnsupportedError('native_front_canvas_group_alpha:$id:$raw');
    }
    final own = raw.clamp(0.0, 1.0);
    final f = Float32List(1)
      ..[0] = own * (p.node.parentId == null ? 1 : opacity(p.node.parentId!));
    return alpha[id] = f[0];
  }

  ProjectedMesh project(ProjectedMesh mesh, String path) {
    final id = data.pathToId[path]!,
        m = matrices[id]!,
        a = opacity(id),
        v = Float32List.fromList(mesh.vertices);
    for (var i = 0; i < v.length; i += 10) {
      final x = (v[i] + 1) * cw / 2, y = (v[i + 1] - 1) * ch / 2;
      v[i] = 2 * (m[0] * x + m[2] * y + m[4]) / cw - 1;
      v[i + 1] = 2 * (m[1] * x + m[3] * y + m[5]) / ch - 1;
      v[i + 9] *= a;
    }
    return ProjectedMesh(v, mesh.indices);
  }

  for (final n in nodes) {
    final p = positions[data.pathToId[n.path]]!;
    if (!p.activeInHierarchy ||
        p.localRect.width <= 0 ||
        p.localRect.height <= 0) {
      continue;
    }
    final r = StoryUiRect(
      p.localRect.x,
      -p.localRect.y - p.localRect.height,
      p.localRect.width,
      p.localRect.height,
    );
    if (n.raw['image'] case final Map image) {
      final original =
          ui.front.records[image['sourceComponentId']]!['data'] as Map;
      if (original['m_Enabled'] == 0 || original['m_Enabled'] == false) {
        continue;
      }
      final size = (image['size'] as List).cast<num>(),
          border = (image['border'] as List).cast<num>(),
          trim = (image['trim'] as List).cast<num>();
      final c = storyFrameColor32(
        (image['color'] as List).cast<num>().map((e) => e.toDouble()).toList(),
      );
      final asset = image['asset'] as String, key = 'front:image:${n.path}';
      meshes[key] = project(
        buildStoryImageMesh(
          rect: r,
          canvasWidth: cw,
          canvasHeight: ch,
          color: c,
          imageType: (image['mode'] as num).toInt(),
          spriteSize: [size[0].toDouble(), size[1].toDouble()],
          trimmedPixels: StoryUiRect(
            trim[0].toDouble(),
            trim[1].toDouble(),
            trim[2].toDouble(),
            trim[3].toDouble(),
          ),
          border: StoryImageBorders(
            left: border[0].toDouble(),
            bottom: border[1].toDouble(),
            right: border[2].toDouble(),
            top: border[3].toDouble(),
          ),
          pixelsPerUnit: 1,
          fillCenter: image['fillCenter'] == true,
          gradient: n.raw['gradient'] as Map?,
        ),
        n.path,
      );
      materials[key] = NativeMaterial(
        texture: key,
        textureAlpha: NativeTextureAlpha.premultiplied,
      );
      textures[key] = Uri.parse(
        'haneoka-asset:${NativeStoryUiSource.base}ui/$asset.png',
      );
      draws.add(NativeDraw(mesh: key, material: key));
    }
    final glyph = measured[n.path];
    if (glyph == null) continue;
    unsupported.addAll(glyph.unsupported);
    if (glyph.missingGlyphs.isNotEmpty) {
      unsupported.add('front_missing_glyphs:${glyph.missingGlyphs}');
    }
    final quads = glyph.quads;
    var start = 0, batch = 0;
    while (start < quads.length) {
      final q = quads[start];
      var end = start + 1;
      while (end < quads.length &&
          quads[end].atlasAsset == q.atlasAsset &&
          quads[end].fontId == q.fontId &&
          quads[end].bold == q.bold &&
          quads[end].glyphScale == q.glyphScale) {
        end++;
      }
      final font = ui.fonts[q.fontId]!,
          packet = material(n, font),
          key = 'front:glyph:${n.path}:${batch++}';
      final dy = switch (n.text!.vertical) {
        256 => 0.0,
        512 => (r.height - glyph.height) / 2,
        1024 => r.height - glyph.height,
        _ => throw UnsupportedError('front_text_alignment'),
      };
      meshes[key] = project(
        nativeStoryGlyphMesh(
          quads.sublist(start, end),
          originX: r.x,
          originY:
              r.y +
              dy +
              ui.front
                  .textBinding(rubyByPath[n.path]!)
                  .marginTopFor(texts[n.path]!),
          canvasWidth: cw,
          canvasHeight: ch,
        ),
        n.path,
      );
      materials[key] = NativeMaterial(
        texture: q.atlasAsset,
        recipe: NativeMaterialRecipe.sdfText,
        coverageChannel: font.coverageChannel,
        textureAlpha: font.coverageChannel == TextureChannel.red
            ? NativeTextureAlpha.independent
            : NativeTextureAlpha.premultiplied,
        uniformFloats: nativeStorySdfUniforms(
          packet,
          glyphScale: q.glyphScale!,
          screenScale: screenScale,
          bold: q.bold,
        ),
      );
      textures[q.atlasAsset] = Uri.parse('haneoka-asset:${q.atlasAsset}');
      draws.add(NativeDraw(mesh: key, material: key));
      start = end;
    }
  }
  final hit = <int, StoryUiRect>{};
  if (choice != null && choice.nextButtonLocked) {
    for (var i = 0; i < choice.choices.length; i++) {
      final component = ui.front.records[itemIds[i]]!['data'] as Map;
      final id = data
              .gameObjectToId[(component['m_GameObject'] as Map)['m_PathID']]!,
          p = positions[id]!,
          m = matrices[id]!;
      if (m[1] != 0 || m[2] != 0) {
        throw UnsupportedError('front_choice_rotated_hit');
      }
      hit[i] = StoryUiRect(
        m[0] * p.localRect.x + m[4],
        ch - (m[3] * (p.localRect.y + p.localRect.height) + m[5]),
        m[0] * p.localRect.width,
        m[3] * p.localRect.height,
      );
    }
  }
  ProjectedMesh screenQuad(List<double> color) => ProjectedMesh(
    Float32List.fromList([
      for (final p in const [
        [-1.0, -1.0, 0.0, 1.0],
        [-1.0, 1.0, 0.0, 0.0],
        [1.0, 1.0, 1.0, 0.0],
        [1.0, -1.0, 1.0, 1.0],
      ]) ...[p[0], p[1], 0, 1, p[2], p[3], ...color],
    ]),
    Uint16List.fromList([0, 1, 2, 0, 2, 3]),
  );
  if (runtime.ruleVisible && runtime.ruleTexture != null) {
    const key = 'front:rule-transition';
    meshes[key] = screenQuad(runtime.ruleColor);
    textures[key] = runtime.ruleTexture!;
    materials[key] = NativeMaterial(
      texture: key,
      recipe: NativeMaterialRecipe.ruleTransition,
      textureAlpha: NativeTextureAlpha.premultiplied,
      uniformFloats: Float32List.fromList([
        runtime.ruleValue,
        runtime.ruleGradient ? 1 : 0,
        0,
        0,
      ]),
    );
    draws.add(const NativeDraw(mesh: key, material: key));
  }
  if (runtime.flashAlpha > 0) {
    const key = 'front:flash';
    meshes[key] = screenQuad([1, 1, 1, runtime.flashAlpha]);
    materials[key] = const NativeMaterial(
      texture: '',
      recipe: NativeMaterialRecipe.solidColor,
    );
    draws.add(const NativeDraw(mesh: key, material: key));
  }
  return NativeStoryFrontUiSnapshot(
    Map.unmodifiable(meshes),
    Map.unmodifiable(materials),
    List.unmodifiable(draws),
    Map.unmodifiable(textures),
    Map.unmodifiable(measured),
    Map.unmodifiable(hit),
    List.unmodifiable(unsupported),
  );
}
