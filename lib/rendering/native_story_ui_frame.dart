import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_sdf.dart';
import 'native_story_ui_source.dart';
import 'native_story_talk_ui_runtime.dart';
import 'native_story_front_ui_runtime.dart';
import 'native_story_front_ui_frame.dart';

final class _NativeStorySdfSourceCache {
  final materials = <String, StorySdfMaterialData>{};
  final fallbacks = <String, NativeStoryResolvedSdfMaterial>{};
  final padding = <String, StoryGlyphPadding>{};
  final extraPadding = <String, bool>{};
  final glyphs = <String, StoryGlyphLayout>{};
  final retainedLayouts = <Object, StoryRetainedUiLayoutState>{};
}

final _sdfSourceCaches = Expando<_NativeStorySdfSourceCache>();

final class NativeStoryUiRetainedCheckpoint {
  NativeStoryUiRetainedCheckpoint._(
    _NativeStorySdfSourceCache cache,
    this._front,
  ) : _layouts = Map.unmodifiable({
        for (final entry in cache.retainedLayouts.entries)
          entry.key: (entry.value, entry.value.snapshot()),
      });
  final Map<Object, (StoryRetainedUiLayoutState, StoryRetainedUiLayoutSnapshot)>
  _layouts;
  final NativeStoryFrontRetainedCheckpoint _front;

  Map<String, Object?> toData({
    required NativeStoryUiSource ui,
    required StorySourceIdentity identity,
  }) {
    final windows = <String, Object?>{};
    for (final entry in _layouts.entries) {
      final scope = entry.key as (String, String, String, int, String, String);
      if (scope.$1 != identity.server ||
          scope.$2 != identity.release ||
          scope.$3 != identity.document ||
          ui.layoutSource.windows[scope.$5]?.sourceHash != scope.$6) {
        throw const FormatException('story_ui_layout_data_scope');
      }
      windows[scope.$5] = entry.value.$2.toData(
        binding: ui.retainedLayoutBinding(identity, scope.$6),
      );
    }
    return {
      'version': 1,
      'windows': windows,
      'front': _front.toData(ui: ui, identity: identity),
    };
  }
}

void restoreNativeStoryUiRetainedData(
  NativeStoryUiSource ui,
  Map data, {
  required StorySourceIdentity identity,
  required int epoch,
  required int storyUs,
  required int updateIndex,
}) {
  if (data['version'] != 1) {
    throw const FormatException('story_ui_layout_data_version');
  }
  final cache = _sdfSourceCaches[ui] ??= _NativeStorySdfSourceCache();
  cache.retainedLayouts.clear();
  for (final entry in (data['windows'] as Map).entries) {
    final mode = entry.key as String, source = ui.layoutSource.windows[mode];
    if (source == null) {
      throw const FormatException('story_ui_layout_data_window');
    }
    final scope = (
      identity.server,
      identity.release,
      identity.document,
      epoch,
      mode,
      source.sourceHash,
    );
    final state = StoryRetainedUiLayoutState(
      sourceScope: scope,
      nodes: source.nodes,
    );
    state.restoreData(
      entry.value as Map,
      expectedBinding: ui.retainedLayoutBinding(identity, source.sourceHash),
      actualUs: storyUs,
      actualUpdateIndex: updateIndex,
    );
    cache.retainedLayouts[scope] = state;
  }
  restoreNativeStoryFrontRetainedData(
    ui,
    data['front'] as Map,
    identity: identity,
    epoch: epoch,
    storyUs: storyUs,
    updateIndex: updateIndex,
  );
}

NativeStoryUiRetainedCheckpoint captureNativeStoryUiRetainedLayout(
  NativeStoryUiSource ui,
) => NativeStoryUiRetainedCheckpoint._(
  _sdfSourceCaches[ui] ??= _NativeStorySdfSourceCache(),
  captureNativeStoryFrontRetainedLayout(ui),
);

void restoreNativeStoryUiRetainedLayout(
  NativeStoryUiSource ui,
  NativeStoryUiRetainedCheckpoint checkpoint,
) {
  final cache = _sdfSourceCaches[ui] ??= _NativeStorySdfSourceCache();
  cache.retainedLayouts.clear();
  for (final entry in checkpoint._layouts.entries) {
    entry.value.$1.restore(entry.value.$2);
    cache.retainedLayouts[entry.key] = entry.value.$1;
  }
  restoreNativeStoryFrontRetainedLayout(ui, checkpoint._front);
}

final class NativeStoryUiSnapshot {
  const NativeStoryUiSnapshot(
    this.scene,
    this.frame,
    this.textures,
    this.talk,
    this.layout,
    this.unsupported,
    this.textMeasurements, [
    this.front,
  ]);
  final NativeSceneResources scene;
  final NativeFrame frame;
  final Map<String, Uri> textures;
  final StoryGlyphLayout talk;
  final StoryMeasuredUiLayout layout;
  final List<String> unsupported;
  final Map<String, Object?> textMeasurements;
  final NativeStoryFrontUiSnapshot? front;
}

/// A normal story UI layer built from the selected source prefab and measured
/// glyphs. The host owns text visibility and supplies the actual story clock.
NativeStoryUiSnapshot buildNativeStoryUiFrame({
  required NativeStoryUiSource ui,
  required RenderSource source,
  required int epoch,
  required int storyUs,
  required int width,
  required int height,
  required String locale,
  required String mode,
  required String text,
  required String speaker,
  required int visibleCharacters,
  required bool auto,
  required bool nextVisible,
  required bool windowVisible,
  required bool revealAll,
  required NativeStoryTalkUiFrame controlFrame,
  NativeStoryFrontUiRuntime? frontRuntime,
  double textSize = 1,
  List<double> talkOffset = const [0, 0, 0],
  bool layoutOnly = false,
}) {
  final sceneName = mode == 'Default'
      ? 'UIDefaultTalkWindow'
      : mode == 'Center'
      ? 'UICenterTalkWindow'
      : throw UnsupportedError('native_story_ui_mode:$mode');
  final roots = ui.scenes.scenes[sceneName]!;
  final nodes = <StoryUiLayoutNode>[];
  void collect(StoryUiLayoutNode n) {
    nodes.add(n);
    for (final child in n.children) {
      collect(child);
    }
  }

  for (final root in roots) {
    collect(root);
  }
  final scaler = ui.graphics.frontScaler;
  if (scaler['m_UiScaleMode'] != 1 || scaler['m_ScreenMatchMode'] != 1) {
    throw UnsupportedError('native_story_front_canvas_scale_mode');
  }
  final reference = scaler['m_ReferenceResolution'] as Map;
  final screenScale = math.min(
    width / (reference['x'] as num),
    height / (reference['y'] as num),
  );
  final canvas = StoryUiRect(0, 0, width / screenScale, height / screenScale);
  final sourceLayout = ui.layoutSource.windows[mode]!;
  final controls = ui.controls.windows[mode]!;
  final windowState = controlFrame.visibility.windows[mode]!;
  final talkPath = controls.endpoints['TalkText']!.path;
  final speakerPath = controls.endpoints['SpeakerText']?.path;
  final sdfCache = _sdfSourceCaches[ui] ??= _NativeStorySdfSourceCache();
  final scope = (
    source.server,
    source.release,
    source.document,
    epoch,
    mode,
    sourceLayout.sourceHash,
  );
  final retained = sdfCache.retainedLayouts.putIfAbsent(
    scope,
    () => StoryRetainedUiLayoutState(
      sourceScope: scope,
      nodes: sourceLayout.nodes,
    ),
  );
  final active = <String, bool>{
    sourceLayout.gameObjectToId[controls.visibility.rootGameObjectId]!:
        windowState.rootActive,
    sourceLayout.gameObjectToId[controls.visibility.talkAreaGameObjectId]!:
        windowState.talkAreaActive,
  };
  for (final field in ['_autoIcon', '_fastIcon', '_talkNextIndicator']) {
    final endpoint = controls.endpoints[field];
    if (endpoint != null) {
      active[endpoint.transformId] =
          controlFrame.effectiveIcons['$mode:$field'] ?? false;
    }
  }
  final controller =
      ((controls.visibility.original['controller'] as Map)['data'] as Map);
  for (final pointer
      in controller['_speakerNameObjects'] as List? ?? const []) {
    final id =
        sourceLayout.gameObjectToId[(pointer as Map)['m_PathID'].toString()];
    if (id == null) throw const FormatException('native_ui_speaker_binding');
    active[id] = speaker.isNotEmpty;
  }
  final poses = <String, StoryRetainedUiPose>{};
  final rootId =
      sourceLayout.gameObjectToId[controls.visibility.rootGameObjectId]!;
  final rootNode = sourceLayout.nodes.singleWhere((node) => node.id == rootId);
  poses[rootId] = StoryRetainedUiPose(
    anchoredX: rootNode.anchoredPosition[0] + talkOffset[0],
    anchoredY: rootNode.anchoredPosition[1] + talkOffset[1],
  );
  for (final indicator in controlFrame.indicators.values) {
    if (indicator.source.mode != mode) continue;
    poses[indicator.pose.transformId] = StoryRetainedUiPose(
      anchoredY: indicator.pose.anchoredY,
      localQuaternion: indicator.pose.localRotationQuaternion,
      eulerDegrees: indicator.pose.eulerDegrees,
    );
  }
  retained.beginLayout(
    sourceScope: scope,
    actualUs: controlFrame.visibility.actualStoryUs,
    actualUpdateIndex: controlFrame.visibility.actualUpdateIndex,
    canvas: StoryUiRect(
      -canvas.width / 2,
      -canvas.height / 2,
      canvas.width,
      canvas.height,
    ),
    activeOverrides: active,
    poses: poses,
  );
  final elements = <String, List<StoryLayoutElementData>>{
    for (final entry in sourceLayout.elements.entries)
      entry.key: List.of(entry.value),
  };
  for (final node in nodes) {
    if (node.raw['image'] is! Map) continue;
    final graphic = ui.graphics.image(mode, node.path),
        image = (graphic['object'] as Map)['data'] as Map;
    if (image['m_Enabled'] != 1 && image['m_Enabled'] != true) continue;
    final sprite = ((graphic['sprite'] as Map)['object'] as Map)['data'] as Map;
    final border = sprite['m_Border'] as Map, rect = sprite['m_Rect'] as Map;
    final ppu =
        (sprite['m_PixelsToUnits'] as num).toDouble() /
        (scaler['m_ReferencePixelsPerUnit'] as num).toDouble() *
        (image['m_PixelsPerUnitMultiplier'] as num).toDouble();
    final sliced = image['m_Type'] == 1 || image['m_Type'] == 2;
    elements
        .putIfAbsent(node.path, () => [])
        .add(
          StoryLayoutElementData(
            priority: 0,
            minimum: const [0, 0],
            preferred: [
              (sliced
                      ? (border['x'] as num) + (border['z'] as num)
                      : rect['width'] as num) /
                  ppu,
              (sliced
                      ? (border['y'] as num) + (border['w'] as num)
                      : rect['height'] as num) /
                  ppu,
            ],
            flexible: const [-1, -1],
            ignoreLayout: false,
          ),
        );
  }
  final fonts = ui.fontBank(locale), intrinsic = <String, StoryGlyphLayout>{};
  final materialPackets = sdfCache.materials;
  final fallbackMaterialSources = sdfCache.fallbacks;
  final currentMaterialKeys = <String>{};
  String materialIdentity(StoryUiLayoutNode node, StoryFontData font) =>
      '${node.path}:$mode:${fonts.fonts.first.sourceHash}:'
      '${font.id}:${font.sourceHash}:${node.text!.materialName}';
  StorySdfMaterialData materialFor(StoryUiLayoutNode node, StoryFontData font) {
    final cacheKey = materialIdentity(node, font);
    currentMaterialKeys.add(cacheKey);
    return materialPackets.putIfAbsent(cacheKey, () {
      final primary = fonts.fonts.first;
      if (font.id != primary.id) {
        final binding = ui.fontMaterialBinding(
          primary.id,
          font.id,
          node.text!.materialName,
        );
        final resolved = nativeStoryFallbackSdfMaterial(
          primaryFont: primary,
          actualFont: font,
          primaryMaterialName: node.text!.materialName,
          fallbackAssetName: binding.fallbackAssetName,
          primaryMaterialKey: binding.primaryMaterialKey,
          targetDefaultMaterialKey: binding.targetDefaultMaterialKey,
          primaryMaterial: binding.primaryMaterial,
          targetDefaultMaterial: binding.targetDefaultMaterial,
          primaryProvenance: binding.primaryProvenance,
          targetProvenance: binding.targetProvenance,
          sourcePath: binding.sourcePath,
          sourceHash: binding.sourceHash,
          matchMaterialPreset: binding.matchMaterialPreset,
        );
        fallbackMaterialSources[cacheKey] = resolved;
        return resolved.material;
      }
      final role = mode == 'Center'
          ? 'center'
          : node.path == speakerPath
          ? 'outline'
          : 'default';
      final exact = '${font.id}:${node.text!.materialName}';
      final key = ui.materials.containsKey(exact) ? exact : '${font.id}-$role';
      final originalRaw = ui.materials[key];
      var raw = originalRaw;
      if (raw is! Map) {
        throw UnsupportedError('native_story_font_material:$key');
      }
      final style = controls.visibility.style;
      if (style != null && node.path == talkPath) {
        raw = <String, Object?>{
          ...Map<String, Object?>.from(raw),
          'colors': <String, Object?>{
            ...Map<String, Object?>.from(raw['colors'] as Map),
            '_OutlineColor': style.outlineColor,
          },
        };
      }
      return StorySdfMaterialData.fromRaw(
        Map<String, Object?>.from(raw),
        actualFont: font,
        sourceMaterialKey: key,
        sourcePath: '${NativeStoryUiSource.base}fonts/materials.json',
        sourceHash: ui.sourceHashes['fonts/materials.json']!,
      );
    });
  }

  StoryGlyphPadding paddingFor(
    StoryUiLayoutNode node,
    StoryFontData font,
    bool bold,
  ) => sdfCache.padding.putIfAbsent(
    '${materialIdentity(node, font)}:$bold',
    () => nativeStorySdfGlyphPadding(
      materialFor(node, font),
      font,
      bold: bold,
      extraPadding: sdfCache.extraPadding.putIfAbsent(
        '$mode:${node.path}',
        () => ui.fontMaterialExtraPadding(mode, node.path),
      ),
    ),
  );
  StoryGlyphLayout compileNode(
    StoryUiLayoutNode n,
    String value,
    bool isSpeaker,
    double width,
    double height,
  ) {
    final key = '$mode:$locale:${n.path}:$width:$height:$textSize:$value';
    if (sdfCache.glyphs.length > 256) sdfCache.glyphs.clear();
    return sdfCache.glyphs.putIfAbsent(
      key,
      () => compileMeasuredStoryUiText(
        source: value,
        textData: n.text!,
        binding: ui.textBinding(mode, speaker: isSpeaker),
        fonts: fonts,
        width: width,
        height: height,
        lineBreakRules: ui.lineBreakRules,
        paddingResolver: (font, bold) => paddingFor(n, font, bold),
        fontScale: textSize,
      ),
    );
  }

  for (final n in nodes) {
    final isTalk = n.path == talkPath, isSpeaker = n.path == speakerPath;
    if (n.text == null || (!isTalk && !isSpeaker)) {
      continue;
    }
    // LayoutGroup's preferred size starts from the actual unbounded glyph
    // measurement. The driven parent rectangle then constrains wrapping.
    intrinsic[n.path] = compileNode(
      n,
      isTalk ? text : speaker,
      isSpeaker,
      0,
      0,
    );
  }
  final first = layoutRetainedMeasuredStoryUi(
    roots: roots,
    state: retained,
    pathToId: sourceLayout.pathToId,
    measuredText: intrinsic,
    actualGroups: sourceLayout.groups,
    actualFits: sourceLayout.fits,
    actualElements: elements,
  );
  final measured = <String, StoryGlyphLayout>{};
  final strings = <String, String>{};
  for (final n in nodes) {
    if (n.text == null) {
      continue;
    }
    final isTalk = n.path == talkPath, isSpeaker = n.path == speakerPath;
    if (!isTalk && !isSpeaker) {
      continue;
    }
    final value = isTalk ? text : speaker,
        rect =
            retained.basePlacements[sourceLayout.pathToId[n.path]]!.localRect;
    measured[n.path] = compileNode(
      n,
      value,
      isSpeaker,
      rect.width,
      rect.height,
    );
    strings[n.path] = value;
  }
  final layout = layoutRetainedMeasuredStoryUi(
    roots: roots,
    state: retained,
    pathToId: sourceLayout.pathToId,
    measuredText: measured,
    actualGroups: sourceLayout.groups,
    actualFits: sourceLayout.fits,
    actualElements: elements,
  );
  final talk = measured[talkPath]!;
  if (layoutOnly) {
    // Replay retains every authored layout update. Projected GPU geometry and
    // texture uploads belong to the final presented frame.
    final front = frontRuntime == null
        ? null
        : buildNativeStoryFrontUiFrame(
            textSize: textSize,
            ui: ui,
            runtime: frontRuntime,
            source: source,
            epoch: epoch,
            storyUs: controlFrame.visibility.actualStoryUs,
            updateIndex: controlFrame.visibility.actualUpdateIndex,
            width: width,
            height: height,
            locale: locale,
            layoutOnly: true,
          );
    return NativeStoryUiSnapshot(
      NativeSceneResources(
        epoch: epoch,
        source: source,
        meshes: const {},
        materials: const {},
        targets: {
          'story-ui': NativeTarget(
            width: width,
            height: height,
            presentable: true,
          ),
        },
      ),
      NativeFrame(
        epoch: epoch,
        mediaMicroseconds: storyUs,
        outputTarget: 'story-ui',
        passes: [NativePass(target: 'story-ui', draws: const [])],
      ),
      const {},
      talk,
      layout,
      const [],
      const {},
      front,
    );
  }
  final placements = retained.basePlacements;
  final affine = resolveRetainedStoryUiAffine(retained);
  final meshes = <String, ProjectedMesh>{},
      materials = <String, NativeMaterial>{};
  final textures = <String, Uri>{},
      draws = <NativeDraw>[],
      unsupported = <String>[];
  if (controlFrame.visibility.backdropAlpha > 0) {
    final color = storyFrameColor32(
      controlFrame.visibility.backdropColor ??
          ui.controls.backdrop.initialColor,
    );
    color[3] *= controlFrame.visibility.backdropAlpha;
    final mesh = buildStoryImageMesh(
      rect: StoryUiRect(0, 0, canvas.width, canvas.height),
      canvasWidth: canvas.width,
      canvasHeight: canvas.height,
      color: color,
      imageType: 0,
      spriteSize: const [1, 1],
      trimmedPixels: const StoryUiRect(0, 0, 1, 1),
      border: const StoryImageBorders(left: 0, bottom: 0, right: 0, top: 0),
      pixelsPerUnit: 1,
      fillCenter: true,
    );
    meshes['source-center-backdrop'] = mesh;
    materials['source-center-backdrop'] = const NativeMaterial(
      texture: 'source-center-backdrop-white',
      textureAlpha: NativeTextureAlpha.premultiplied,
    );
    textures['source-center-backdrop-white'] = Uri.parse(
      'haneoka-asset:${NativeStoryUiSource.base}ui/WhiteRect_258144246005254427.png',
    );
    draws.add(
      const NativeDraw(
        mesh: 'source-center-backdrop',
        material: 'source-center-backdrop',
      ),
    );
    unsupported.add('source_center_background_blur_pass_pending');
  }
  final alpha = <String, double>{};
  double opacity(String id) {
    if (alpha[id] case final known?) return known;
    final node = placements[id]!.node;
    var own = sourceLayout.groupAlpha[id] ?? 1.0;
    if (controls.visibility.backgroundGameObjectId != null &&
        id ==
            sourceLayout.gameObjectToId[controls
                .visibility
                .backgroundGameObjectId]) {
      own = windowState.backgroundAlpha;
    }
    if (!own.isFinite) {
      throw UnsupportedError('native_talk_canvas_group_alpha:$id:$own');
    }
    return alpha[id] =
        own.clamp(0.0, 1.0) *
        (node.parentId == null ? 1.0 : opacity(node.parentId!));
  }

  bool hidden(String path) =>
      !placements[sourceLayout.pathToId[path]]!.activeInHierarchy;
  ProjectedMesh projectUi(ProjectedMesh mesh, String path) {
    final m = affine[sourceLayout.pathToId[path]]!,
        vertices = Float32List.fromList(mesh.vertices);
    final a = opacity(sourceLayout.pathToId[path]!);
    for (var i = 0; i < vertices.length; i += 10) {
      final x = (vertices[i] + 1) * canvas.width / 2,
          y = (vertices[i + 1] - 1) * canvas.height / 2;
      final px = m[0] * x + m[2] * y + m[4], py = m[1] * x + m[3] * y + m[5];
      vertices[i] = 2 * px / canvas.width - 1;
      vertices[i + 1] = 2 * py / canvas.height - 1;
      vertices[i + 9] *= a;
    }
    return ProjectedMesh(vertices, mesh.indices);
  }

  void image(StoryUiLayoutNode node, StoryUiRect rect, Map raw) {
    final graphic = ui.graphics.image(mode, node.path);
    final original = (graphic['object'] as Map)['data'] as Map;
    if (original['m_Enabled'] == 0 || original['m_Enabled'] == false) return;
    final sprite = ((graphic['sprite'] as Map)['object'] as Map)['data'] as Map;
    final sr = sprite['m_Rect'] as Map,
        tr = (sprite['m_RD'] as Map)['textureRect'] as Map,
        offset = (sprite['m_RD'] as Map)['textureRectOffset'] as Map,
        b = sprite['m_Border'] as Map;
    final asset = raw['asset'] as String;
    final key = 'story-ui:$asset';
    final imageType = original['m_Type'] as int;
    final c = original['m_Color'] as Map;
    final color = [
      for (final name in ['r', 'g', 'b', 'a']) (c[name] as num).toDouble(),
    ];
    final size = [
      (sr['width'] as num).toDouble(),
      (sr['height'] as num).toDouble(),
    ];
    var r = rect;
    if (imageType == 0 &&
        (original['m_PreserveAspect'] == 1 ||
            original['m_PreserveAspect'] == true) &&
        size[0] > 0 &&
        size[1] > 0) {
      final ratio = math.min(rect.width / size[0], rect.height / size[1]);
      final w = size[0] * ratio, h = size[1] * ratio;
      r = StoryUiRect(
        rect.x + (rect.width - w) * node.rect[4][0],
        rect.y + (rect.height - h) * (1 - node.rect[4][1]),
        w,
        h,
      );
    }
    meshes[node.path] = projectUi(
      buildStoryImageMesh(
        rect: r,
        canvasWidth: canvas.width,
        canvasHeight: canvas.height,
        color: color,
        imageType: imageType,
        spriteSize: size,
        trimmedPixels: StoryUiRect(
          (offset['x'] as num).toDouble(),
          (offset['y'] as num).toDouble(),
          (tr['width'] as num).toDouble(),
          (tr['height'] as num).toDouble(),
        ),
        border: StoryImageBorders(
          left: (b['x'] as num).toDouble(),
          bottom: (b['y'] as num).toDouble(),
          right: (b['z'] as num).toDouble(),
          top: (b['w'] as num).toDouble(),
        ),
        pixelsPerUnit:
            (sprite['m_PixelsToUnits'] as num).toDouble() /
            (scaler['m_ReferencePixelsPerUnit'] as num).toDouble() *
            (original['m_PixelsPerUnitMultiplier'] as num).toDouble(),
        fillCenter:
            original['m_FillCenter'] == 1 || original['m_FillCenter'] == true,
        gradient: ui.graphics.gradient(
          mode,
          node.path,
          (graphic['object'] as Map)['pathId'] as String,
        ),
      ),
      node.path,
    );
    materials[node.path] = NativeMaterial(
      texture: key,
      textureAlpha: NativeTextureAlpha.premultiplied,
    );
    textures[key] = Uri.parse(
      'haneoka-asset:${NativeStoryUiSource.base}ui/$asset.png',
    );
    draws.add(NativeDraw(mesh: node.path, material: node.path));
  }

  for (final node in nodes) {
    if (hidden(node.path)) {
      continue;
    }
    final sourceRect = placements[sourceLayout.pathToId[node.path]]!.localRect;
    if (sourceRect.width <= 0 || sourceRect.height <= 0) {
      continue;
    }
    final rect = StoryUiRect(
      sourceRect.x,
      -sourceRect.y - sourceRect.height,
      sourceRect.width,
      sourceRect.height,
    );
    if (node.raw['image'] case final Map raw) {
      image(node, rect, raw);
    }
    final glyphs = measured[node.path];
    if (glyphs == null) {
      continue;
    }
    unsupported.addAll(glyphs.unsupported);
    if (glyphs.missingGlyphs.isNotEmpty) {
      unsupported.add('missing_source_glyphs:${glyphs.missingGlyphs}');
    }
    final speakerNode = node.path == speakerPath;
    final binding = ui.textBinding(mode, speaker: speakerNode);
    final max = speakerNode || revealAll
        ? glyphs.meshCharacterCount
        : visibleCharacters;
    final visible = glyphs.visibleQuads(max).toList();
    var start = 0, batch = 0;
    while (start < visible.length) {
      final firstGlyph = visible[start];
      var end = start + 1;
      while (end < visible.length &&
          visible[end].atlasAsset == firstGlyph.atlasAsset &&
          visible[end].fontId == firstGlyph.fontId &&
          visible[end].bold == firstGlyph.bold &&
          visible[end].glyphScale == firstGlyph.glyphScale) {
        end++;
      }
      final font = ui.fonts[firstGlyph.fontId]!;
      final packet = materialFor(node, font);
      final key = '${node.path}:glyph:${batch++}';
      final verticalOffset = switch (node.text!.vertical) {
        256 => 0.0,
        512 => (rect.height - glyphs.height) / 2,
        1024 => rect.height - glyphs.height,
        final value => throw UnsupportedError(
          'native_story_text_vertical:$value',
        ),
      };
      meshes[key] = projectUi(
        nativeStoryGlyphMesh(
          visible.sublist(start, end),
          originX: rect.x,
          originY:
              rect.y +
              verticalOffset +
              binding.marginTopFor(strings[node.path]!),
          canvasWidth: canvas.width,
          canvasHeight: canvas.height,
        ),
        node.path,
      );
      materials[key] = NativeMaterial(
        texture: firstGlyph.atlasAsset,
        recipe: NativeMaterialRecipe.sdfText,
        textureAlpha: NativeTextureAlpha.premultiplied,
        uniformFloats: nativeStorySdfUniforms(
          packet,
          glyphScale: firstGlyph.glyphScale!,
          screenScale: screenScale,
          bold: firstGlyph.bold,
        ),
      );
      textures[firstGlyph.atlasAsset] = Uri.parse(
        'haneoka-asset:${firstGlyph.atlasAsset}',
      );
      draws.add(NativeDraw(mesh: key, material: key));
      start = end;
    }
  }
  NativeStoryFrontUiSnapshot? front;
  if (frontRuntime != null) {
    front = buildNativeStoryFrontUiFrame(
      textSize: textSize,
      ui: ui,
      runtime: frontRuntime,
      source: source,
      epoch: epoch,
      storyUs: controlFrame.visibility.actualStoryUs,
      updateIndex: controlFrame.visibility.actualUpdateIndex,
      width: width,
      height: height,
      locale: locale,
    );
    meshes.addAll(front.meshes);
    materials.addAll(front.materials);
    textures.addAll(front.textures);
    final at = draws.isNotEmpty && draws.first.mesh == 'source-center-backdrop'
        ? 1
        : 0;
    draws.insertAll(at, front.draws);
    unsupported.addAll(front.unsupported);
  }
  final resources = NativeSceneResources(
    epoch: epoch,
    source: source,
    meshes: meshes,
    materials: materials,
    targets: {
      'story-ui': NativeTarget(width: width, height: height, presentable: true),
    },
  );
  return NativeStoryUiSnapshot(
    resources,
    NativeFrame(
      epoch: epoch,
      mediaMicroseconds: storyUs,
      outputTarget: 'story-ui',
      passes: [NativePass(target: 'story-ui', draws: draws)],
    ),
    textures,
    talk,
    layout,
    unsupported,
    {
      for (final entry in measured.entries)
        entry.key: {
          'intrinsicWidth': intrinsic[entry.key]!.width,
          'intrinsicHeight': intrinsic[entry.key]!.height,
          'constrainedWidth': first.rects[entry.key]!.width,
          'constrainedHeight': first.rects[entry.key]!.height,
          'measuredWidth': entry.value.width,
          'measuredHeight': entry.value.height,
          'lineBaselines': entry.value.lineBaselines,
          'glyphQuads': entry.value.quads.length,
          if (currentMaterialKeys.any(
            (key) =>
                key.startsWith('${entry.key}:') &&
                fallbackMaterialSources.containsKey(key),
          ))
            'fallbackMaterials': {
              for (final key in currentMaterialKeys)
                if (key.startsWith('${entry.key}:') &&
                    fallbackMaterialSources.containsKey(key))
                  fallbackMaterialSources[key]!.material.fontId: {
                    'materialName': fallbackMaterialSources[key]!.materialName,
                    'primaryProvenance':
                        fallbackMaterialSources[key]!.primaryProvenance,
                    'targetProvenance':
                        fallbackMaterialSources[key]!.targetProvenance,
                    'scaleRatioA':
                        fallbackMaterialSources[key]!.material.scaleRatioA,
                    'scaleRatioC':
                        fallbackMaterialSources[key]!.material.scaleRatioC,
                  },
            },
          'finalRect': [
            layout.rects[entry.key]!.x,
            layout.rects[entry.key]!.y,
            layout.rects[entry.key]!.width,
            layout.rects[entry.key]!.height,
          ],
        },
    },
    front,
  );
}
