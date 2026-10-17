import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show haneokaProfileAssetRoot;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cassiopeia_plugin_our_notes/render_profile.dart';

import '../chart/runtime_chart.dart';
import 'native_chart_effects.dart';

final _noteGeometries = Expando<ChartNoteGeometry>();
final _sortedNotes = Expando<List<RuntimeVisualNote>>();

/// Real paused watch input. No player audio or simulation clock is replaced.
final class ChartGpuSnapshot {
  const ChartGpuSnapshot({
    required this.scene,
    required this.frame,
    required this.texturePaths,
    required this.unsupported,
    required this.roles,
    required this.holdSources,
    required this.anchors,
    required this.dataTextures,
  });
  final NativeSceneResources scene;
  final NativeFrame frame;
  final Map<String, String> texturePaths;
  final List<Map<String, Object?>> unsupported, roles, holdSources;
  final Map<String, Object?> anchors;
  final Map<String, NativeTextureData> dataTextures;
}

ChartGpuSnapshot buildChartSnapshot(
  RuntimeChart chart,
  Map<String, Object?> archive, {
  required int textureWidth,
  required int textureHeight,
  required int width,
  required int height,
  required int mediaUs,
  NativeChartProjection? stageProjection,
  int epoch = 2,
  int? outputBuffer,
  String noteSkin = 'skin001',
  String laneSkin = 'skin001',
  NativeHoldMaterialStyle? holdStyle,
  NativeChartHud? hud,
  NativeChartHeader? header,
  Map<String, NativeTextureData> headerDataTextures = const {},
  List<int>? rankScores,
  required OurNotesWatchPresentation watch,
  NativeChartEffects? effects,
  OurNotesGekisouPlan? gekisouPlan,
  OurNotesGekisouOverlayProjector? gekisouOverlay,
  OurNotesGekisouStage? gekisouStage,
  Map<String, NativeTextureData> gekisouStageTextures = const {},
  OurNotesIntroFrame? intro,
  Map<String, String> introTexturePaths = const {},
  Map<String, NativeTextureData> introDataTextures = const {},
  int effectQuality = 1,
  NativeComboTier? comboTier,
  bool continuation = true,
  bool showCombo = true,
  bool showBackground = true,
  bool effectsEnabled = true,
  bool showSimultaneousLine = true,
  bool showJudgementLine = false,
  double noteSpeed = 5,
  double noteSize = 1,
  double longAlpha = .6,
  double guideAlpha = .6,
  double backgroundBrightness = .7,
  double laneOpacity = .8,
  bool mirror = false,
  int guidelineCount = 6,
  double guidelineOpacity = .25,
  double? logicalWidth,
  double? logicalHeight,
  required RenderSource source,
  required int bandId,
  required (int, int) backgroundSize,
  NativeTextureData? backgroundData,
  bool geometryObservations = false,
}) {
  final projection =
          stageProjection ??
          NativeChartProjection(
            width,
            height,
            logicalWidth: logicalWidth,
            logicalHeight: logicalHeight,
            noteSpeed: noteSpeed,
          ),
      skin = _noteGeometries[archive] ??= ChartNoteGeometry(
        archive,
        textureWidth,
        textureHeight,
      );
  final lw = projection.logicalWidth, lh = projection.logicalHeight;
  final introActive = intro != null && !intro.complete;
  final gekisouFrame = watch.gekisou.sample(
    (watch.sampledVisualTimeMicros ?? mediaUs) / 1000,
    enabled: gekisouPlan != null,
  );
  final gekisouSprites = gekisouOverlay == null
      ? <OurNotesGekisouOverlaySprite>[]
      : gekisouOverlay.project(
          gekisouFrame,
          OurNotesGekisouOverlayViewport(
            width: lw,
            height: lh,
            worldToClip: projection.worldClip,
            displayPositionChanged:
                gekisouOverlay.viewSettings.displayPositionChanged,
            displayScale: gekisouOverlay.viewSettings.displayScale,
          ),
        );
  final meshes = <String, ProjectedMesh>{},
      materials = <String, NativeMaterial>{},
      roles = <Map<String, Object?>>[];
  if (intro != null) {
    meshes.addAll(intro.meshes);
    materials.addAll(intro.materials);
    roles.add({
      'role': 'intro',
      'elapsedSeconds': intro.elapsedSeconds,
      'durationSeconds': intro.durationSeconds,
      'complete': intro.complete,
      'gameLaneVisible': intro.gameLaneVisible,
      'tapAlpha': intro.tapAlpha,
      'gameDraws': intro.gameDraws.length,
      'effectDraws': intro.effectDraws.length,
      'screenDraws': intro.draws.length,
    });
  }
  final unsupported = <Map<String, Object?>>[],
      holds = <Map<String, Object?>>[];
  unsupported.addAll([
    if (effects == null)
      {
        'role': 'judgement-fx',
        'reason': 'exact selected source FX not installed',
      },
    if (effects == null)
      {'role': 'bloom', 'reason': 'no exact selected source FX scene'},
    if (effects == null)
      {'role': 'hold-loop-fx', 'reason': 'selected source FX not installed'},
    if (effects == null)
      {
        'role': 'lane-feedback-fx',
        'reason': 'selected source FX not installed',
      },
    if (intro == null)
      {'role': 'intro', 'reason': 'selected source intro unavailable'},
  ]);
  final backgroundDraws = <NativeDraw>[], gameDraws = <NativeDraw>[];
  final noteBodyDraws = <NativeDraw>[],
      noteArrowDraws = <NativeDraw>[],
      noteMarkDraws = <NativeDraw>[];
  final noteAnchors = <Map<String, Object?>>[];
  final anchors = <String, Object?>{'notes': noteAnchors};
  Map<String, Object?> actualAnchor(
    Float32List matrix,
    double x,
    double y,
    double z,
  ) {
    final clip = Float32List(4);
    for (var row = 0; row < 4; row++) {
      clip[row] =
          matrix[row] * x +
          matrix[row + 4] * y +
          matrix[row + 8] * z +
          matrix[row + 12];
    }
    return {
      'sourcePosition': [x, y, z],
      'clip': clip.toList(),
      'pixelTopLeft': [
        (clip[0] / clip[3] + 1) * width / 2,
        (1 - clip[1] / clip[3]) * height / 2,
      ],
    };
  }

  final texturePaths = <String, String>{
    ...introTexturePaths,
    if (hud != null) ...hud.texturePaths(source.server),
    if (header != null) ...header.texturePaths(source.server),
    if (gekisouPlan != null && gekisouOverlay != null)
      ...gekisouOverlay.texturePaths(source.server),
    'atlas': 'asset:$haneokaProfileAssetRoot$noteSkin.png',
    if (showBackground && backgroundData == null)
      'background':
          '/assets/${source.server}/Assets/AddressableResources/Band/$bandId/live_stage/lightweight_background.png',
    'lane':
        '/assets/${source.server}/Assets/AddressableResources/Live/Lane/$laneSkin/lane_base.png',
    'outside':
        '/assets/${source.server}/Assets/AddressableResources/Live/Lane/$laneSkin/out_side_line.png',
    'lane-line':
        '/assets/${source.server}/Assets/AddressableResources/Live/Images/NonAtlas/LiveStartAnim/white_line_antialiasing_side.png',
    'tap':
        '/assets/${source.server}/Assets/AddressableResources/Live/Lane/$laneSkin/lane_tap_area.png',
  };
  for (final key in [...headerDataTextures.keys, ...introDataTextures.keys]) {
    texturePaths.remove(key);
  }
  final fullClip = Float32List.fromList([
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);
  NativeSpriteGeometry quad(
    double x,
    double y,
    double w,
    double h, {
    double z = 0,
    List<double> uv = const [0, 1, 1, 1, 0, 0, 1, 0],
  }) => NativeSpriteGeometry(
    positions: Float32List.fromList([
      x - w / 2,
      y - h / 2,
      z,
      x + w / 2,
      y - h / 2,
      z,
      x - w / 2,
      y + h / 2,
      z,
      x + w / 2,
      y + h / 2,
      z,
    ]),
    uv: Float32List.fromList(uv),
    indices: Uint16List.fromList([0, 1, 2, 2, 1, 3]),
  );
  void add(
    String key,
    String texture,
    NativeSpriteGeometry geometry,
    Float32List clip,
    List<double> tint,
    List<NativeDraw> output, {
    NativeMaterialRecipe recipe = NativeMaterialRecipe.textured,
    bool depth = false,
    NativeTextureAlpha textureAlpha = NativeTextureAlpha.premultiplied,
  }) {
    meshes[key] = projectSprite(geometry, clip, Float32List.fromList(tint));
    materials[key] = NativeMaterial(
      texture: texture,
      recipe: recipe,
      textureAlpha: textureAlpha,
      depthTest: depth,
    );
    output.add(NativeDraw(mesh: key, material: key));
  }

  add(
    'background-base',
    '',
    quad(0, 0, 2, 2),
    fullClip,
    [3 / 255, 3 / 255, 10 / 255, 1],
    backgroundDraws,
    recipe: NativeMaterialRecipe.solidColor,
  );
  final ratio = backgroundSize.$1 / backgroundSize.$2,
      targetRatio = projection.aspect;
  final ru = ratio > targetRatio ? targetRatio / ratio : 1.0,
      rv = ratio > targetRatio ? 1.0 : ratio / targetRatio;
  final ou = (1 - ru) / 2, ov = (1 - rv) / 2;
  if (showBackground) {
    add(
      'background-image',
      'background',
      quad(
        0,
        0,
        2 * (intro?.backgroundScale[0] ?? 1),
        2 * (intro?.backgroundScale[1] ?? 1),
        uv: [ou, ov + rv, ou + ru, ov + rv, ou, ov, ou + ru, ov],
      ),
      fullClip,
      [1, 1, 1, 1],
      backgroundDraws,
      textureAlpha: backgroundData?.alpha ?? NativeTextureAlpha.premultiplied,
    );
  }
  add(
    'background-shadow',
    '',
    quad(0, 0, 2, 2),
    fullClip,
    [0, 0, 0, 1 - backgroundBrightness],
    backgroundDraws,
    recipe: NativeMaterialRecipe.solidColor,
  );
  final screenScale = math.min(lw / 1920, lh / 1080);
  final pixelClip = Float32List.fromList([
    2 / lw,
    0,
    0,
    0,
    0,
    2 / lh,
    0,
    0,
    0,
    0,
    1,
    0,
    -1,
    -1,
    0,
    1,
  ]);
  if (geometryObservations) {
    anchors['logicalOrthographicClip'] = pixelClip.toList();
    anchors['backgroundCrop'] = {
      'offset': [ou, ov],
      'repeat': [ru, rv],
    };
  }
  add(
    'lane-screen',
    'lane',
    quad(
      lw / 2,
      lh / 2 - 247 * screenScale,
      2048 * screenScale,
      1644 * screenScale,
    ),
    pixelClip,
    [.035294119, .074509792, .180392116, .749019623 * laneOpacity],
    gameDraws,
  );
  if (effects != null && effectsEnabled) {
    final feedbackDraws = effects.appendLaneFeedback(
      projection: projection,
      meshes: meshes,
      materials: materials,
      mirror: mirror,
    );
    gameDraws.addAll(feedbackDraws);
    roles.add({
      'role': 'lane-feedback-fx',
      'sortingOrder': 4099,
      'actualDraws': feedbackDraws.length,
      'sourceLaneCount': effects.source.laneFeedback.laneCount,
    });
  }
  for (final entry in nativeStageLineMeshes(
    projection,
    guidelineCount: guidelineCount,
    opacity: guidelineOpacity,
  ).entries) {
    final key = 'stage-line:${entry.key}';
    meshes[key] = entry.value;
    materials[key] = NativeMaterial(
      texture: entry.key == 'outside' ? 'outside' : 'lane-line',
      recipe: NativeMaterialRecipe.textured,
      textureAlpha: NativeTextureAlpha.premultiplied,
      depthTest: true,
    );
    gameDraws.add(NativeDraw(mesh: key, material: key));
    roles.add({
      'role': 'stage-line',
      'profile': entry.key,
      'sortingOrder': 4100,
    });
  }
  final worldGekisou =
      gekisouSprites.where((sprite) => !sprite.screenSpace).toList()
        ..sort((a, b) => a.sortingOrder.compareTo(b.sortingOrder));
  for (final sprite in worldGekisou) {
    final key = 'gekisou:${sprite.id}';
    meshes[key] = sprite.geometry;
    materials[key] = NativeMaterial(
      texture: sprite.textureKey,
      textureAlpha: NativeTextureAlpha.premultiplied,
    );
    gameDraws.add(NativeDraw(mesh: key, material: key));
  }
  roles.add({
    'role': 'gekisou-presentation',
    'enabled': gekisouFrame.enabled,
    'rangeIndex': gekisouFrame.countdown.rangeIndex,
    'countdown': gekisouFrame.countdown.count,
    'clip': gekisouFrame.countdown.clip?.name,
    'clipTimeSeconds': gekisouFrame.countdown.clipTimeSeconds,
    'justCount': gekisouFrame.just.count,
    'worldDraws': worldGekisou.length,
    'screenDraws': gekisouSprites.where((sprite) => sprite.screenSpace).length,
  });
  // Exact tap-area piecewise UV map: 46/96 texture border, .46 world units.
  // Unity X=-90 maps local top to lower world Z; PNG rows start at that top.
  const tapX = [-9.8, -9.8 + .46, 9.8 - .46, 9.8];
  const tapZ = [9.62 - .85, 9.62 - .85 + .46, 9.62 + .85 - .46, 9.62 + .85];
  const tapUv = [0.0, 46 / 96, 50 / 96, 1.0];
  final tapPositions = Float32List(16 * 3), tapTextureUv = Float32List(16 * 2);
  for (var row = 0; row < 4; row++) {
    for (var column = 0; column < 4; column++) {
      final vertex = row * 4 + column;
      tapPositions[vertex * 3] = tapX[column];
      tapPositions[vertex * 3 + 2] = tapZ[row];
      tapTextureUv[vertex * 2] = tapUv[column];
      tapTextureUv[vertex * 2 + 1] = tapUv[row];
    }
  }
  final tapIndices = <int>[];
  for (var row = 0; row < 3; row++) {
    for (var column = 0; column < 3; column++) {
      final vertex = row * 4 + column;
      tapIndices.addAll([
        vertex,
        vertex + 1,
        vertex + 4,
        vertex + 4,
        vertex + 1,
        vertex + 5,
      ]);
    }
  }
  final tap = NativeSpriteGeometry(
    positions: tapPositions,
    uv: tapTextureUv,
    indices: Uint16List.fromList(tapIndices),
  );
  if (geometryObservations) {
    anchors['tapCorners'] = [
      for (final vertex in [0, 3, 12, 15])
        {
          'vertex': vertex,
          ...actualAnchor(
            projection.worldClip,
            tap.positions[vertex * 3].toDouble(),
            tap.positions[vertex * 3 + 1].toDouble(),
            tap.positions[vertex * 3 + 2].toDouble(),
          ),
        },
    ];
  }
  add(
    'tap-area',
    'tap',
    tap,
    projection.worldClip,
    [1, 1, 1, .8 * (intro?.tapAlpha ?? 1)],
    gameDraws,
    depth: true,
  );
  if (showJudgementLine) {
    final angle = 29.60445665468814 * math.pi / 180;
    final halfWidth = 19.2 / 2, halfHeight = .06 / 2;
    add(
      'judgement-line',
      '',
      NativeSpriteGeometry(
        positions: Float32List.fromList([
          -halfWidth,
          -math.cos(angle) * halfHeight,
          9.62 + math.sin(angle) * halfHeight,
          halfWidth,
          -math.cos(angle) * halfHeight,
          9.62 + math.sin(angle) * halfHeight,
          -halfWidth,
          math.cos(angle) * halfHeight,
          9.62 - math.sin(angle) * halfHeight,
          halfWidth,
          math.cos(angle) * halfHeight,
          9.62 - math.sin(angle) * halfHeight,
        ]),
        uv: Float32List.fromList([0, 1, 1, 1, 0, 0, 1, 0]),
        indices: Uint16List.fromList([0, 1, 2, 2, 1, 3]),
      ),
      projection.worldClip,
      [250 / 255, 246 / 255, 1, .4],
      gameDraws,
      recipe: NativeMaterialRecipe.solidColor,
      depth: true,
    );
  }
  final timeMs = mediaUs / 1000, viewMs = projection.viewTimeMs;
  double displayedLane(double lane, double width) =>
      mirror ? 24 - lane - width : lane;
  int displayedDirection(int direction) => !mirror
      ? direction
      : switch (direction) {
          1 => 2,
          2 => 1,
          _ => direction,
        };
  String? kind(int op, int direction) => switch (op) {
    1 || 101 => 'tap',
    40 || 41 || 42 || 102 =>
      direction == 1
          ? 'flick-left'
          : direction == 2
          ? 'flick-right'
          : 'flick',
    20 || 61 || 80 => 'slide-start',
    22 || 62 || 82 => 'slide-end',
    21 || 63 => 'slide-node',
    60 || 104 || 105 => 'trace',
    100 || 103 => 'guide',
    _ => null,
  };
  final visible = _sortedNotes[chart] ??= [
    for (final i in chart.visualTimeSortedIndices) chart.visualNotes[i],
  ];
  final firstVisibleMs = timeMs - viewMs * .16;
  final lastVisibleMs = timeMs + viewMs * 1.1;
  var first = 0, upper = visible.length;
  while (first < upper) {
    final middle = first + ((upper - first) >> 1);
    if (visible[middle].timeMicroseconds / 1000 < firstVisibleMs) {
      first = middle + 1;
    } else {
      upper = middle;
    }
  }
  for (var index = first; index < visible.length; index++) {
    final note = visible[index];
    if (note.timeMicroseconds / 1000 > lastVisibleMs) break;
    if (note.visible == null) {
      unsupported.add({
        'role': 'sprite',
        'nativeId': note.id,
        'reason': 'source-visible-unavailable',
      });
      continue;
    }
    if (note.visible == false ||
        [100, 101, 102, 104].contains(note.operateType)) {
      continue;
    }
    // Core watch.advance processes judged notes strictly before current time.
    if (isJudgementNote(note.operateType) && note.timeMicroseconds < mediaUs) {
      continue;
    }
    final direction = displayedDirection(note.direction);
    final lane = displayedLane(note.visualLane, note.visualWidth);
    final noteKind = kind(note.operateType, direction);
    if (noteKind == null) {
      unsupported.add({
        'role': 'sprite',
        'nativeId': note.id,
        'reason': 'operate-type-unmapped',
        'op': note.operateType,
      });
      continue;
    }
    final approach = (note.timeMicroseconds / 1000 - timeMs) / viewMs;
    final alpha = approach < 0 ? math.max(0.0, 1 + approach / .16) : 1.0;
    final progress = projection.progress(approach);
    if (geometryObservations) {
      noteAnchors.add({
        'id': note.id,
        'timeUs': note.timeMicroseconds,
        'lane': note.lane,
        'width': note.width,
        'visualLane': note.visualLane,
        'visualWidth': note.visualWidth,
        'kind': noteKind,
        'approach': approach,
        'viewProgress': progress,
        ...actualAnchor(
          projection.screenClip,
          projection.laneX(lane + note.visualWidth / 2) * progress,
          projection.y(progress),
          10.6077995,
        ),
      });
    }
    try {
      final parts = skin.note(
        kind: noteKind,
        direction: direction,
        lane: lane,
        laneWidth: note.visualWidth,
        timeSeconds: timeMs / 1000,
      );
      for (final entry in parts.entries) {
        final key = 'note:${note.id}:${entry.key}';
        add(
          key,
          'atlas',
          projection.placeNote(
            entry.value.geometry,
            lane,
            note.visualWidth,
            approach,
            scale: noteSize,
          ),
          projection.screenClip,
          [1, 1, 1, alpha * entry.value.alpha],
          entry.key == 'mark'
              ? noteMarkDraws
              : entry.key == 'arrow'
              ? noteArrowDraws
              : noteBodyDraws,
          depth: true,
        );
        if (geometryObservations) {
          roles.add({
            'role': entry.key,
            'nativeId': note.id,
            'sourceOrdinal': note.sourceOrdinal,
            'timeMicroseconds': note.timeMicroseconds,
            'kind': noteKind,
            'lane': note.lane,
            'width': note.width,
            'visualLane': note.visualLane,
            'visualWidth': note.visualWidth,
            'direction': note.direction,
            'displayLane': lane,
            'displayDirection': direction,
            'approach': approach,
            'viewProgress': projection.progress(approach),
            'alpha': alpha,
            'scale': noteSize,
            'critical': note.critical,
          });
        }
      }
    } on UnsupportedError catch (error) {
      unsupported.add({
        'role': 'sprite',
        'nativeId': note.id,
        'reason': '$error',
      });
    }
  }
  // Retain actual invisible node/guide endpoints. No Sprite visibility filter here.
  for (final line in chart.visualLines) {
    final points = line.points;
    if (points.length < 2 || !line.completeGeometry) {
      unsupported.add({
        'role': 'line',
        'nativeLineId': line.nativeLineId,
        'reason': 'geometry-source-unresolved',
      });
      continue;
    }
    final spanTimes = [
      ...points.map((p) => p.timeMicroseconds),
      ...line.comboEvents.map((p) => p.timeMicroseconds),
      ...line.endComboEvents.map((p) => p.timeMicroseconds),
    ];
    final start = spanTimes.reduce(math.min), end = spanTimes.reduce(math.max);
    if (end < mediaUs || start > mediaUs + (viewMs * 1100).round()) continue;
    final active =
        line.family == RuntimeVisualLineFamily.line &&
        start <= mediaUs &&
        mediaUs < end;
    NativeHoldGeometrySource? prepared;
    try {
      prepared = prepareNativeHoldGeometry(
        [
          for (final p in points)
            NativeHoldSourcePoint(
              nativeId: p.id,
              timeUs: p.timeMicroseconds,
              lane: displayedLane(p.lane.toDouble(), p.width.toDouble()),
              width: p.width.toDouble(),
              leftEase: mirror ? p.easeR : p.ease,
              rightEase: mirror ? p.ease : p.easeR,
            ),
        ],
        projection,
        mediaUs,
        widthScale: holdStyle?.widthScale ?? .9,
        glowRangeScale: holdStyle?.glowRange ?? 2.5,
      );
    } on UnsupportedError catch (error) {
      unsupported.add({
        'role': 'hold-geometry',
        'nativeLineId': line.nativeLineId,
        'reason': error.message.toString(),
      });
    } on ArgumentError catch (error) {
      unsupported.add({
        'role': 'hold-geometry',
        'nativeLineId': line.nativeLineId,
        'reason': error.message.toString(),
      });
    }
    if (geometryObservations) {
      holds.add({
        'nativeLineId': line.nativeLineId,
        'family': line.family.name,
        'watchActive': active,
        'span': [start, end],
        'pointNativeIds': line.pointNativeIds,
        'points': [
          for (final p in points)
            {
              'id': p.id,
              'timeUs': p.timeMicroseconds,
              'lane': p.lane,
              'width': p.width,
              'easeLeft': p.ease,
              'easeRight': p.easeR,
              'slideAlong': p.slideAlong,
            },
        ],
        if (prepared != null) ...{
          'minimumAuthoredWidth': prepared.minimumWidth,
          'geometrySourcePointIds': prepared.sourcePointIds,
          'sampledVisiblePoints': [
            for (final p in prepared.visiblePoints)
              {
                'timeUs': p.timeUs,
                'lane': p.lane,
                'width': p.width,
                'lineProgress': p.lineProgress,
              },
          ],
          'ribbonScreenPositionsXYZ': prepared.screenPositions.toList(),
        },
        'visibleClipUs': [
          math.max(start, mediaUs),
          math.min(end, mediaUs + (viewMs * 1100).round()),
        ],
      });
    }
    if (holdStyle != null &&
        prepared != null &&
        prepared.visiblePoints.length >= 2) {
      final key = 'hold:${line.family.name}:${line.nativeLineId}';
      meshes[key] = nativeHoldProjectedMesh(
        prepared,
        projection,
        mediaUs,
        opacity: line.family == RuntimeVisualLineFamily.guide
            ? guideAlpha
            : longAlpha,
        glowRange: holdStyle.glowRange,
        widthScale: holdStyle.widthScale,
      );
      materials[key] = NativeMaterial(
        texture: 'hold-gradient',
        recipe: NativeMaterialRecipe.holdRibbon,
        textureAlpha: NativeTextureAlpha.straight,
        depthTest: true,
        uniformFloats: holdStyle.uniforms(
          guide: line.family == RuntimeVisualLineFamily.guide,
          active: active,
        ),
      );
      gameDraws.add(NativeDraw(mesh: key, material: key));
      roles.add({
        'role': 'hold-ribbon',
        'nativeLineId': line.nativeLineId,
        'family': line.family.name,
        'actualPointIds': line.pointNativeIds,
        'watchActive': active,
        'sortingOrder': 4999,
      });
      continue;
    }
    unsupported.add({
      'role': 'hold-ribbon-material',
      'nativeLineId': line.nativeLineId,
      'reason': 'specialised-gradient/glow recipe pending',
      'geometryRetained': true,
    });
  }
  if (chart.visualUnresolvedLines.isNotEmpty) {
    unsupported.add({
      'role': 'line-source',
      'reason': 'missing-begin',
      'nativeIds': chart.visualUnresolvedLines
          .map((l) => l.nativeLineId)
          .toList(),
    });
  }
  // MusicScoreNoteCreator.IsPairNoteType, grouped by actual source tick.
  final pairGroups = <int, List<RuntimeVisualNote>>{};
  for (final note in chart.visualNotes) {
    if (note.visible != true ||
        ![1, 20, 22, 40, 41, 42].contains(note.operateType)) {
      continue;
    }
    final tick = note.sourceTick;
    if (tick == null) {
      unsupported.add({
        'role': 'pair-source',
        'reason': 'actual-tick-unavailable',
        'nativeId': note.id,
      });
      continue;
    }
    (pairGroups[tick] ??= []).add(note);
  }
  for (final group
      in showSimultaneousLine
          ? pairGroups.values
          : const <List<RuntimeVisualNote>>[]) {
    group.sort((a, b) => a.sourceOrdinal.compareTo(b.sourceOrdinal));
    for (var i = 1; i < group.length; i++) {
      final a = group[i - 1], b = group[i];
      if (a.timeMicroseconds < mediaUs || b.timeMicroseconds < mediaUs) {
        continue;
      }
      final approach = (b.timeMicroseconds / 1000 - timeMs) / viewMs;
      if (approach < -.16 || approach > 1.1) continue;
      final ac =
              displayedLane(a.lane.toDouble(), a.width.toDouble()) +
              a.width / 2,
          bc =
              displayedLane(b.lane.toDouble(), b.width.toDouble()) +
              b.width / 2;
      if (ac == bc) continue;
      final progress = projection.progress(approach);
      final left = projection.laneX(math.min(ac, bc)) * progress;
      final right = projection.laneX(math.max(ac, bc)) * progress;
      final key = 'pair:${a.sourceOrdinal}:${b.sourceOrdinal}';
      add(
        key,
        '',
        quad(
          (left + right) / 2,
          projection.y(progress),
          right - left,
          .02500000037252903,
          z: 10.6077995,
        ),
        projection.screenClip,
        [1, 1, 1, 1],
        gameDraws,
        recipe: NativeMaterialRecipe.solidColor,
      );
      roles.add({
        'role': 'pair',
        'tick': b.sourceTick,
        'nativeIds': [a.id, b.id],
        'sourceOrdinals': [a.sourceOrdinal, b.sourceOrdinal],
        'sourceWhiteRectPathId': '258144246005254427',
        'sortingOrder': 4999,
      });
    }
  }
  gameDraws.addAll([...noteBodyDraws, ...noteArrowDraws, ...noteMarkDraws]);
  final targets = <String, NativeTarget>{
    'chart-game': NativeTarget(width: width, height: height, depth: true),
    'chart-main': NativeTarget(
      width: width,
      height: height,
      format: NativeTargetFormat.rgba16f,
    ),
    'chart-output': NativeTarget(
      width: width,
      height: height,
      presentable: true,
    ),
  };
  final effectPasses = <NativePass>[];
  if (effects != null &&
      (effectsEnabled || intro?.effectDraws.isNotEmpty == true)) {
    if (effectsEnabled) {
      gameDraws.addAll(
        effects.appendLayer(
          projection: projection,
          meshes: meshes,
          materials: materials,
          mirror: mirror,
          layer: 25,
        ),
      );
    }
    if (effectQuality < 0 || effectQuality > 2) {
      throw ArgumentError('native_chart_effect_quality');
    }
    final quality = effectQuality;
    final effectWidth = math.max(
          1,
          (width * NativeEffectPostprocessing.effectScales[quality]).floor(),
        ),
        effectHeight = math.max(
          1,
          (height * NativeEffectPostprocessing.effectScales[quality]).floor(),
        );
    targets['chart-effect'] = NativeTarget(
      width: effectWidth,
      height: effectHeight,
      format: NativeTargetFormat.rgba16f,
      alpha: NativeTextureAlpha.independent,
    );
    final effectDraws = <NativeDraw>[
      if (effectsEnabled)
        ...effects.appendLayer(
          projection: projection,
          meshes: meshes,
          materials: materials,
          mirror: mirror,
          layer: 29,
        ),
      ...?intro?.effectDraws,
    ];
    if (gekisouStage != null) {
      effectDraws.addAll(
        gekisouStage.appendLayer(
          layer: 29,
          clipFromWorld: projection.worldClip,
          fieldOfViewRadians: projection.fieldOfViewRadians,
          cameraPosition:
              ((effects.source.recipe['geometry'] as Map)['cameraPosition']
                      as List)
                  .cast<num>()
                  .map((v) => v.toDouble())
                  .toList(),
          cameraXDegrees:
              ((effects.source.recipe['geometry'] as Map)['cameraXDegrees']
                      as num)
                  .toDouble(),
          meshes: meshes,
          materials: materials,
        ),
      );
    }
    final post =
        NativeEffectPostprocessing(
          bloom: effects.source.bloom,
          fxaa: effects.source.fxaa,
        ).build(
          prefix: 'chart-fx',
          sourceTarget: 'chart-effect',
          width: effectWidth,
          height: effectHeight,
          quality: quality,
          meshes: meshes,
          materials: materials,
          targets: targets,
        );
    if (effectDraws.isNotEmpty) {
      effectPasses.add(NativePass(target: 'chart-effect', draws: effectDraws));
      effectPasses.addAll(post);
      meshes['effect-composite'] = meshes['chart-fx:post-quad']!;
      materials['effect-composite'] = const NativeMaterial(
        texture: 'chart-fx:output',
        textureAlpha: NativeTextureAlpha.independent,
        blend: NativeBlend.additive,
      );
      roles.add({
        'role': 'judgement-fx',
        'actualInstances': effects.activeInstances,
        'aliveParticles': effects.liveParticles,
        'actualDraws': effectDraws.length,
        'postPasses': post.length,
        'effectTargetSize': [effectWidth, effectHeight],
        'layer': 29,
        'quality': quality,
        'sourceHashes': effects.source.sourceHashes,
      });
    }
  }
  if (gekisouStage != null) {
    backgroundDraws.addAll(
      gekisouStage.appendLayer(
        layer: 27,
        clipFromWorld: gekisouStage.uiClip(lw, lh),
        fieldOfViewRadians: projection.fieldOfViewRadians,
        cameraPosition: const [0, 0, 0],
        cameraXDegrees: 0,
        meshes: meshes,
        materials: materials,
      ),
    );
    roles.add({'role': 'gekisou-stage', ...gekisouStage.diagnostic});
  }
  add(
    'game-composite',
    'chart-game',
    quad(0, 0, 2, 2),
    fullClip,
    [1, 1, 1, 1],
    backgroundDraws,
    recipe: NativeMaterialRecipe.gameComposite,
  );
  if (materials.containsKey('effect-composite')) {
    backgroundDraws.add(
      const NativeDraw(mesh: 'effect-composite', material: 'effect-composite'),
    );
  }
  if (hud == null) {
    unsupported.add({'role': 'hud', 'reason': 'native HUD source unavailable'});
  } else {
    final result = watch.snapshot;
    final visualEvent = watch.visualLastEvent;
    final latestUs = visualEvent?.judgedAtMicros ?? 0;
    final presentationUs = watch.sampledVisualTimeMicros ?? mediaUs;
    final actualTier =
        comboTier ??
        (watch.visualAllPerfect
            ? NativeComboTier.allPerfect
            : watch.visualFullCombo
            ? NativeComboTier.fullCombo
            : NativeComboTier.normal);
    if (showCombo && !introActive) {
      backgroundDraws.addAll(
        hud.draw(
          combo: watch.visualCombo,
          sinceComboUs: presentationUs - latestUs,
          tier: actualTier,
          continuation: continuation,
          width: lw,
          height: lh,
          screenScale: screenScale,
          meshes: meshes,
          materials: materials,
        ),
      );
    }
    if (!introActive) {
      backgroundDraws.addAll(
        hud.drawJudgement(
          sinceJudgementUs: presentationUs - latestUs,
          hasJudgement: visualEvent != null,
          judgementValue: visualEvent?.judgement ?? 5,
          width: lw,
          height: lh,
          screenScale: screenScale,
          meshes: meshes,
          materials: materials,
        ),
      );
    }
    roles.add({
      'role': 'hud',
      'combo': watch.visualCombo,
      'businessCombo': result.combo,
      'maxCombo': result.maxCombo,
      'isAllPerfect': watch.visualAllPerfect,
      'isFullCombo': watch.visualFullCombo,
      'tier': continuation ? actualTier.name : 'normal',
      'displayed': showCombo,
      'totalJudgements': result.total,
      'finishedAllJudgements': result.processed == result.total,
      'judgementMode': gekisouPlan == null
          ? 'automatic-perfect-preview'
          : 'automatic-gekisou-preview',
      'judgement': visualEvent?.judgement,
      'justCount': watch.justCount,
      'perfectCount': watch.perfectCount,
      'sinceComboUs': presentationUs - latestUs,
      'sampledVisualTimeUs': watch.sampledVisualTimeMicros,
      'score': result.score,
      'life': result.life,
      'processed': result.processed,
      'runtimeTimeUs': result.timeMicros,
      'gekisouRangeJustCount': gekisouFrame.just.count,
    });
  }
  if (header != null && !introActive) {
    backgroundDraws.addAll(
      header.draw(
        snapshot: watch.snapshot,
        lastEvent: watch.lastEvent,
        rankScores: rankScores,
        mediaUs: mediaUs,
        width: lw,
        height: lh,
        pixelRatio: width / lw,
        meshes: meshes,
        materials: materials,
      ),
    );
  }
  final screenGekisou =
      gekisouSprites.where((sprite) => sprite.screenSpace).toList()
        ..sort((a, b) => a.sortingOrder.compareTo(b.sortingOrder));
  for (final sprite in screenGekisou) {
    final key = 'gekisou:${sprite.id}';
    meshes[key] = sprite.geometry;
    materials[key] = NativeMaterial(
      texture: sprite.textureKey,
      textureAlpha: NativeTextureAlpha.premultiplied,
    );
    backgroundDraws.add(NativeDraw(mesh: key, material: key));
  }
  backgroundDraws.addAll(intro?.draws ?? const []);
  const outputTarget = 'chart-output';
  final outputDraws = <NativeDraw>[];
  add('output-copy', 'chart-main', quad(0, 0, 2, 2), fullClip, [
    1,
    1,
    1,
    1,
  ], outputDraws);
  return ChartGpuSnapshot(
    scene: NativeSceneResources(
      epoch: epoch,
      source: source,
      meshes: meshes,
      materials: materials,
      targets: targets,
    ),
    frame: NativeFrame(
      epoch: epoch,
      mediaMicroseconds: mediaUs,
      outputTarget: outputTarget,
      passes: [
        ...effectPasses,
        NativePass(
          target: 'chart-game',
          draws: [
            ...?intro?.gameDraws,
            if (!introActive || intro.gameLaneVisible) ...gameDraws,
          ],
        ),
        NativePass(target: 'chart-main', draws: backgroundDraws),
        NativePass(target: outputTarget, draws: outputDraws),
      ],
    ),
    texturePaths: Map.unmodifiable(texturePaths),
    unsupported: List.unmodifiable(unsupported),
    roles: List.unmodifiable(roles),
    holdSources: List.unmodifiable(holds),
    anchors: Map.unmodifiable(anchors),
    dataTextures: {
      ...headerDataTextures,
      ...introDataTextures,
      if (gekisouPlan != null) ...gekisouStageTextures,
      if (showBackground && backgroundData != null)
        'background': backgroundData,
      if (effects != null) ...effects.source.textureData,
      if (holdStyle != null) 'hold-gradient': holdStyle.gradient(),
    },
  );
}
