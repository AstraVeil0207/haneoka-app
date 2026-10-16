import 'dart:typed_data';

import 'package:cassiopeia_plugin_our_notes/render_profile.dart';
import 'package:cassiopeia_runtime/cassiopeia_runtime.dart';

import '../chart/runtime_chart.dart';
import 'native_chart_effect_source.dart';

/// Normal watch judgements are acquired from successive actual native audio
/// samples. A source change/seek clears instances, without rewriting note IDs.
final class NativeChartEffects {
  NativeChartEffects(
    this.source,
    this.chart, {
    required this.tier,
    required int initialMediaUs,
    OurNotesGekisouPlan? gekisouPlan,
  }) : _mediaUs = initialMediaUs,
       _rawObservedMediaUs = initialMediaUs {
    _gekisouPlan = gekisouPlan;
    _laneFeedback = ChartLaneFeedback(source.laneFeedback);
    _notes = {for (final note in chart.visualNotes) note.id: note};
    _lines =
        chart.visualLines
            .where(
              (line) =>
                  line.family == RuntimeVisualLineFamily.line &&
                  line.completeGeometry &&
                  line.points.length > 1 &&
                  isJudgementNote(line.points.first.operateType),
            )
            .toList()
          ..sort(
            (a, b) => a.points.first.timeMicroseconds.compareTo(
              b.points.first.timeMicroseconds,
            ),
          );
  }
  final NativeChartEffectSource source;
  final RuntimeChart chart;
  final String tier;
  OurNotesGekisouPlan? _gekisouPlan;
  int _gekisouActivations = 0;

  void setGekisouPlan(OurNotesGekisouPlan? plan) {
    if (identical(plan, _gekisouPlan)) return;
    _gekisouPlan = plan;
    resetOnNextObservation();
  }

  late final ChartLaneFeedback _laneFeedback;
  late final Map<int, RuntimeVisualNote> _notes;
  late final List<RuntimeVisualLine> _lines;
  final _lineLoops = <int, _FxInstance>{};
  late final _lineSources = {
    for (final line in _lines) line.nativeLineId: line,
  };
  int _lineCursor = 0;
  int get activeHoldLoops => _lineLoops.length;
  final _templates = <String, _FxTemplate>{};
  final _instances = <_FxInstance>[];
  int _mediaUs, _activation = 0, _explicitResets = 0;
  int _rawObservedMediaUs, _backwardObservations = 0;
  int _advancedFrames = 0;
  double _lastFrameDelta = 0;
  int? _lastResetFromUs, _lastResetToUs;
  bool _pendingReset = false;
  bool get needsRestore => _pendingReset;
  int get observedMediaUs => _mediaUs;
  int _historicalRebuilds = 0, _historicalFrames = 0;
  void resetOnNextObservation() {
    _instances.clear();
    _laneFeedback.clear();
    _lineLoops.clear();
    _lineCursor = 0;
    _pendingReset = true;
  }

  int get activeInstances => _instances.length;
  Map<String, Object?> get diagnostic => {
    'instances': activeInstances,
    'gekisouEnabled': _gekisouPlan != null,
    'gekisouActivations': _gekisouActivations,
    'holdLoops': activeHoldLoops,
    'laneFeedback': {
      'visible': _laneFeedback.visible(_mediaUs).length,
      'activations': _laneFeedback.activations,
      'suppressedEmpty': _laneFeedback.suppressedEmpty,
      'capacity': source.laneFeedback.laneCount,
    },
    'activations': _activation,
    'explicitResets': _explicitResets,
    'lastExplicitResetUs': [_lastResetFromUs, _lastResetToUs],
    'noteCount': _notes.length,
    'historicalRebuilds': _historicalRebuilds,
    'historicalSimulationFrames': _historicalFrames,
    'observedMediaUs': _mediaUs,
    'rawObservedMediaUs': _rawObservedMediaUs,
    'backwardObservations': _backwardObservations,
    'advancedFrames': _advancedFrames,
    'lastFrameDeltaSeconds': _lastFrameDelta,
    'templateDurations': {
      for (final entry in _templates.entries)
        entry.key: entry.value.clip.duration,
    },
    'particles': liveParticles,
    'firstSystems': _instances.isEmpty
        ? const []
        : [for (final system in _instances.first.systems) system.diagnostic],
  };
  final _drawOrders = <String, (int, int, int)>{};
  int get liveParticles => _instances.fold(
    0,
    (count, effect) =>
        count + effect.systems.fold(0, (n, system) => n + system.alive),
  );
  List<NativeDraw> appendLayer({
    required NativeChartProjection projection,
    required Map<String, ProjectedMesh> meshes,
    required Map<String, NativeMaterial> materials,
    required bool mirror,
    required int layer,
  }) {
    _drawOrders.clear();
    final draws = [
      ...appendSprites(
        projection: projection,
        meshes: meshes,
        materials: materials,
        mirror: mirror,
        layer: layer,
      ),
      ...appendParticles(
        projection: projection,
        meshes: meshes,
        materials: materials,
        mirror: mirror,
        layer: layer,
      ),
    ];
    draws.sort((a, b) {
      final x = _drawOrders[a.mesh]!, y = _drawOrders[b.mesh]!;
      final order = x.$1.compareTo(y.$1), instance = x.$2.compareTo(y.$2);
      return order != 0
          ? order
          : instance != 0
          ? instance
          : x.$3.compareTo(y.$3);
    });
    return draws;
  }

  void seek(int mediaUs) {
    _instances.clear();
    _laneFeedback.clear();
    _lineLoops.clear();
    _lineCursor = 0;
    _mediaUs = mediaUs;
    _rawObservedMediaUs = mediaUs;
    _lastFrameDelta = 0;
  }

  Future<void> observe(
    int mediaUs, {
    required CassiopeiaObservation observation,
    required Iterable<CassiopeiaJudgementView> history,
    required bool mirror,
    required bool playing,
    required double playbackRate,
    required bool Function() current,
    bool forceRestore = false,
  }) async {
    _rawObservedMediaUs = mediaUs;
    if (_pendingReset ||
        observation.historical ||
        forceRestore ||
        (!playing && (observation.events.isNotEmpty || mediaUs != _mediaUs))) {
      _pendingReset = false;
      _explicitResets++;
      _lastResetFromUs = _mediaUs;
      _lastResetToUs = mediaUs;
      seek(mediaUs);
      await _restoreHistory(
        history,
        mediaUs,
        ourNotesRuntimeObservationMicros(mediaUs),
        mirror: mirror,
        current: current,
      );
      return;
    }
    if (mediaUs < _mediaUs) {
      _backwardObservations++;
      return;
    }
    if (!playing || mediaUs == _mediaUs) return;
    if (!playbackRate.isFinite || playbackRate <= 0) {
      throw ArgumentError('native_effect_playback_rate');
    }
    if (mediaUs - _mediaUs > 2000000) {
      seek(mediaUs);
      return;
    }
    // Audio position already includes the playback rate. Preserve this actual
    // frame interval before each particle system applies simulationSpeed.
    final delta = (mediaUs - _mediaUs) / 1000000;
    _lastFrameDelta = delta;
    _advancedFrames++;
    _advanceFrame(mediaUs, delta, observation, mirror: mirror);
  }

  _FxInstance? _admit(
    CassiopeiaJudgementView event, {
    required bool mirror,
    int? visibleAtUs,
  }) {
    final note = _notes[event.noteId];
    if (note == null) return null;
    final feedback = ourNotesWatchFeedback(
      noteTimeMs: note.timeMicroseconds ~/ 1000,
      operateType: note.operateType,
      direction: note.direction,
      judgement: event.judgement,
      differenceMicros: event.differenceMicros,
      judgedAtMicros: event.judgedAtMicros,
      mirror: mirror,
      plan: _gekisouPlan,
    );
    final kind = feedback.effectKind;
    final template = kind == null
        ? null
        : _templates.putIfAbsent(
            kind,
            () => _FxTemplate(source, source.template(tier, kind)),
          );
    final age = visibleAtUs == null
        ? 0
        : (visibleAtUs - event.judgedAtMicros) / 1000000;
    final laneKind = feedback.laneKind;
    if (age < 0) return null;
    if (laneKind != null) {
      if (visibleAtUs == null && laneKind == ChartLaneFeedbackKind.gekisou) {
        _gekisouActivations++;
      }
      _laneFeedback.trigger(
        laneKind,
        note.visualLane,
        note.visualWidth,
        event.judgedAtMicros,
      );
    }
    if (template == null || age >= template.clip.duration) {
      return null;
    }
    final instance = _FxInstance(
      _activation + 1,
      note,
      event.judgedAtMicros,
      template,
    );
    _instances.add(instance);
    _activation++;
    return instance;
  }

  void _advanceFrame(
    int mediaUs,
    double delta,
    CassiopeiaObservation observation, {
    required bool mirror,
  }) {
    _mediaUs = mediaUs;
    for (final event in observation.events) {
      _admit(event, mirror: mirror);
    }
    while (_lineCursor < _lines.length &&
        _lines[_lineCursor].points.first.timeMicroseconds <
            observation.snapshot.timeMicros) {
      final line = _lines[_lineCursor++];
      if (line.points.last.timeMicroseconds <= mediaUs) continue;
      final template = _templates.putIfAbsent(
        'SlideLoop',
        () => _FxTemplate(source, source.template(tier, 'SlideLoop')),
      );
      final instance = _FxInstance(
        ++_activation,
        line.points.first,
        mediaUs,
        template,
      );
      _lineLoops[line.nativeLineId] = instance;
      _instances.add(instance);
    }
    for (final lineId in _lineLoops.keys.toList()) {
      final instance = _lineLoops[lineId]!;
      final line = _lineSources[lineId]!;
      if (mediaUs >= line.points.last.timeMicroseconds) {
        _instances.remove(instance);
        _lineLoops.remove(lineId);
        continue;
      }
      _poseHold(instance, line, mediaUs);
    }
    for (final instance in _instances) {
      final sinceSpawn = (mediaUs - instance.spawnedUs) / 1000000;
      instance.advance(sinceSpawn < delta ? sinceSpawn : delta, mirror: mirror);
    }
    _instances.removeWhere((effect) => effect.finished);
  }

  void _poseHold(_FxInstance instance, RuntimeVisualLine line, int mediaUs) {
    final points = line.points;
    var next = 1;
    while (next < points.length - 1 &&
        points[next].timeMicroseconds < mediaUs) {
      ++next;
    }
    final a = points[next - 1], b = points[next];
    final t = f(
      (mediaUs - a.timeMicroseconds) /
          (b.timeMicroseconds - a.timeMicroseconds),
    ).clamp(0.0, 1.0);
    double ease(int value) => switch (value) {
      0 => t,
      1 => f(f(2 - t) * t),
      2 => f(t * t),
      _ => throw UnsupportedError('hold_effect_ease:$value'),
    };
    final left = f(
      a.visualLane + f(f(b.visualLane - a.visualLane) * ease(a.ease)),
    );
    final ar = f(a.visualLane + a.visualWidth),
        br = f(b.visualLane + b.visualWidth);
    final right = f(ar + f(f(br - ar) * ease(a.easeR)));
    final l = left.clamp(0.0, 24.0), r = right.clamp(0.0, 24.0);
    instance.setPose(l, f(r - l));
  }

  Future<void> _restoreHistory(
    Iterable<CassiopeiaJudgementView> history,
    int mediaUs,
    int sourceUs, {
    required bool mirror,
    required bool Function() current,
  }) async {
    ++_historicalRebuilds;
    final events = history.toList();
    final byId = {for (final event in events) event.noteId: event};
    final operations =
        <({CassiopeiaJudgementView event, RuntimeVisualLine? line, int order})>[
          for (final (index, event) in events.indexed)
            (event: event, line: null, order: index * 2),
        ];
    while (_lineCursor < _lines.length &&
        _lines[_lineCursor].points.first.timeMicroseconds < sourceUs) {
      final line = _lines[_lineCursor++];
      if (line.points.last.timeMicroseconds <= sourceUs) continue;
      final begin = byId[line.beginNativeId];
      if (begin == null) {
        throw StateError('hold_begin_judgement_missing:${line.beginNativeId}');
      }
      if (begin.judgedAtMicros > mediaUs) continue;
      operations.add((
        event: begin,
        line: line,
        order: events.indexOf(begin) * 2 + 1,
      ));
    }
    operations.sort((a, b) {
      final time = a.event.judgedAtMicros.compareTo(b.event.judgedAtMicros);
      return time != 0 ? time : a.order.compareTo(b.order);
    });
    final budget = Stopwatch()..start();
    for (final operation in operations) {
      if (!current()) return;
      final line = operation.line;
      final _FxInstance? instance;
      if (line == null) {
        instance = _admit(
          operation.event,
          mirror: mirror,
          visibleAtUs: mediaUs,
        );
      } else {
        final template = _templates.putIfAbsent(
          'SlideLoop',
          () => _FxTemplate(source, source.template(tier, 'SlideLoop')),
        );
        instance = _FxInstance(
          ++_activation,
          line.points.first,
          operation.event.judgedAtMicros,
          template,
        );
        _lineLoops[line.nativeLineId] = instance;
        _instances.add(instance);
      }
      if (instance == null) continue;
      final age = (mediaUs - instance.spawnedUs) / 1000000;
      if (age == 0) instance.advance(0, mirror: mirror);
      var elapsed = 0.0;
      var frame = 0;
      while (elapsed < age) {
        if (!current()) return;
        final next = (++frame / instance.template.sampleRate).clamp(0.0, age);
        if (line != null) {
          _poseHold(
            instance,
            line,
            instance.spawnedUs + (next * 1000000).round(),
          );
        }
        instance.advance(next - elapsed, mirror: mirror);
        elapsed = next;
        ++_historicalFrames;
        if (budget.elapsedMilliseconds >= 6) {
          await Future<void>.delayed(Duration.zero);
          budget.reset();
        }
      }
    }
    _instances.removeWhere((effect) => effect.finished);
  }

  /// Layer-25 UI/Additive feedback shares one texture and one draw across all
  /// 24 half-lanes. HDR note effects retain their separate layer/pass.
  List<NativeDraw> appendLaneFeedback({
    required NativeChartProjection projection,
    required Map<String, ProjectedMesh> meshes,
    required Map<String, NativeMaterial> materials,
    required bool mirror,
  }) {
    final vertices = <double>[], indices = <int>[];
    for (final feedback in _laneFeedback.visible(_mediaUs)) {
      final lane = mirror
          ? source.laneFeedback.laneCount - feedback.lane - 1
          : feedback.lane;
      final kind = !mirror
          ? feedback.kind
          : switch (feedback.kind) {
              ChartLaneFeedbackKind.flickLeft =>
                ChartLaneFeedbackKind.flickRight,
              ChartLaneFeedbackKind.flickRight =>
                ChartLaneFeedbackKind.flickLeft,
              _ => feedback.kind,
            };
      final shape = source.laneFeedback.shape(kind, feedback.age, lane);
      if (shape == null) continue;
      final mesh = projectSprite(
        shape,
        projection.worldClip,
        source.laneFeedback.color(kind, feedback.age),
      );
      final base = vertices.length ~/ 10;
      vertices.addAll(mesh.vertices);
      indices.addAll([for (final index in mesh.indices) base + index]);
    }
    if (indices.isEmpty) return const [];
    const key = 'lane-feedback';
    meshes[key] = ProjectedMesh(
      Float32List.fromList(vertices),
      Uint16List.fromList(indices),
    );
    // Textured/straight supplies coverage once and One/One adds the result,
    // matching the source UI/Additive fragment without MobileAddHdrColor tint.
    materials[key] = const NativeMaterial(
      texture: 'fx:laneEffect',
      blend: NativeBlend.additive,
      textureAlpha: NativeTextureAlpha.straight,
      depthTest: true,
    );
    return const [NativeDraw(mesh: key, material: key)];
  }

  /// Original SpriteRenderers are rendered with their own Sprite texture, which
  /// overrides a Material's serialized default _MainTex in the source renderer.
  List<NativeDraw> appendSprites({
    required NativeChartProjection projection,
    required Map<String, ProjectedMesh> meshes,
    required Map<String, NativeMaterial> materials,
    required bool mirror,
    required int layer,
  }) {
    final draws = <(int, int, NativeDraw)>[];
    for (final instance in _instances) {
      final template = instance.template, frame = instance.frame;
      if (frame == null) continue;
      final positions = <String, Float32List>{...instance.widthSet.positions};
      for (final entry in template.pathHashes.entries) {
        final value =
            frame.channels[entry.value]?[NativeEffectProperty.position];
        if (value != null) positions[entry.key] = value;
      }
      final sourceLane = mirror
          ? 24 - instance.lane - instance.width
          : instance.lane;
      final geometry = source.recipe['geometry'] as Map;
      final laneUnit =
              (geometry['laneWidth'] as num) /
              (geometry['chartLaneCount'] as num),
          centerX = (sourceLane + instance.width / 2 - 12) * laneUnit;
      final root = Float32List.fromList([
        1, // The prefab graph owns its authored root reflection.
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
        centerX,
        0,
        (geometry['judgementRootZ'] as num).toDouble(),
        1,
      ]);
      for (final (ordinal, renderer) in template.sprites.indexed) {
        final go = source.graph.gameObject(renderer);
        if (go.data['m_Layer'] != layer || renderer.data['m_Enabled'] != true) {
          continue;
        }
        final transform = source.graph.transform(renderer),
            hash = template.pathHashes[transform.key]!;
        var active = true, node = transform;
        while (true) {
          final nodeGo = source.graph.gameObject(node);
          final original = node.key == template.root.key
              ? true
              : nodeGo.data['m_IsActive'] as bool;
          final path = template.pathHashes[node.key];
          if (!(path == null ? original : frame.active(path, original))) {
            active = false;
            break;
          }
          if (node.key == template.root.key) break;
          node = source.graph.reference(node, node.data['m_Father'] as Map)!;
        }
        if (!active) continue;
        final rawColor = renderer.data['m_Color'] as Map;
        final color = frame.color(hash, [
          for (final c in ['r', 'g', 'b', 'a']) (rawColor[c] as num).toDouble(),
        ]);
        if (color[3] <= 0) continue;
        final material = source.graph.reference(
              renderer,
              (renderer.data['m_Materials'] as List).single as Map,
            )!,
            typed = NativeMobileHdrMaterial(material),
            sprite = source.graph.reference(
              renderer,
              renderer.data['m_Sprite'] as Map,
            )!,
            texture = source.spriteTextureKey(sprite),
            pixels = source.textureData[texture]!;
        final size = renderer.data['m_Size'] as Map;
        final width =
                frame.scalar(hash, NativeEffectProperty.sizeX) ??
                instance.widthSet.spriteWidths[renderer.key] ??
                (size['x'] as num).toDouble(),
            height = (size['y'] as num).toDouble();
        final mesh = switch (renderer.data['m_DrawMode']) {
          0 => source.graph.spriteGeometry(
            sprite,
            textureSize: (pixels.width, pixels.height),
          ),
          1 => nativeAuthoredSlicedSprite(
            sprite.data,
            width: width,
            height: height,
            textureWidth: pixels.width,
            textureHeight: pixels.height,
          ),
          _ => throw UnsupportedError(
            'native_effect_sprite_draw_mode:${renderer.data['m_DrawMode']}',
          ),
        };
        final xyz = Float32List.fromList(mesh.positions);
        if (mesh.indices.isEmpty) continue;
        for (var vertex = 0; vertex < xyz.length ~/ 3; vertex++) {
          if (renderer.data['m_FlipX'] == true) {
            xyz[vertex * 3] = -xyz[vertex * 3];
          }
          if (renderer.data['m_FlipY'] == true) {
            xyz[vertex * 3 + 1] = -xyz[vertex * 3 + 1];
          }
        }
        final transformMatrix = NativeAuthoredEffectGraph.multiply(
          root,
          source.graph.worldMatrix(
            transform,
            positions: positions,
            scales: instance.widthSet.scales,
          ),
        );
        final clip = NativeAuthoredEffectGraph.multiply(
          projection.worldClip,
          transformMatrix,
        );
        final key = 'fx:${instance.activation}:sprite:${renderer.key}';
        _drawOrders[key] = (
          renderer.data['m_SortingOrder'] as int,
          instance.activation,
          template.nodeOrdinals[transform.key]!,
        );
        meshes[key] = projectSprite(
          NativeSpriteGeometry(
            positions: xyz,
            uv: mesh.uv,
            indices: mesh.indices,
          ),
          clip,
          typed.hdrVertexColor(color.toList()),
        );
        materials[key] = NativeMaterial(
          texture: texture,
          recipe: NativeMaterialRecipe.mobileHdr,
          textureAlpha: NativeTextureAlpha.straight,
          blend: NativeBlend.sourceAlphaAdditive,
        );
        draws.add((
          renderer.data['m_SortingOrder'] as int,
          ordinal,
          NativeDraw(mesh: key, material: key),
        ));
      }
    }
    draws.sort((a, b) {
      final order = a.$1.compareTo(b.$1);
      return order == 0 ? a.$2.compareTo(b.$2) : order;
    });
    return [for (final draw in draws) draw.$3];
  }

  List<NativeDraw> appendParticles({
    required NativeChartProjection projection,
    required Map<String, ProjectedMesh> meshes,
    required Map<String, NativeMaterial> materials,
    required bool mirror,
    required int layer,
  }) {
    final result = <NativeDraw>[];
    for (final instance in _instances) {
      final template = instance.template;
      for (final system in instance.systems) {
        final go = source.graph.gameObject(system.object);
        if (go.data['m_Layer'] != layer ||
            !instance.activeSystems.contains(system.object.key)) {
          continue;
        }
        final matrix = instance.matrices[system.object.key]!;
        final mesh = system.buildMesh(
          matrix: matrix,
          nativeWidth: instance.widthSet.width,
          clipFromWorld: projection.worldClip,
          fieldOfViewRadians: projection.fieldOfViewRadians,
          cameraPosition:
              ((source.recipe['geometry'] as Map)['cameraPosition'] as List)
                  .cast<num>()
                  .map((v) => v.toDouble())
                  .toList(),
          cameraXDegrees:
              ((source.recipe['geometry'] as Map)['cameraXDegrees'] as num)
                  .toDouble(),
        );
        if (mesh == null) continue;
        final key = 'fx:${instance.activation}:ps:${system.object.key}';
        meshes[key] = mesh;
        materials[key] = NativeMaterial(
          texture: system.texture,
          recipe: NativeMaterialRecipe.mobileHdr,
          textureAlpha: NativeTextureAlpha.straight,
          blend: NativeBlend.sourceAlphaAdditive,
        );
        _drawOrders[key] = (
          system.spec.sortingOrder,
          instance.activation,
          template.nodeOrdinals[system.transform.key]!,
        );
        result.add(NativeDraw(mesh: key, material: key));
      }
    }
    return result;
  }
}

final class _FxTemplate {
  _FxTemplate(this.source, this.manifest) {
    final first = (manifest['particleSystems'] as List).first as Map;
    final firstSystem = source.component(first['metadataUrl'] as String);
    root = source.graph.rootTransform(firstSystem);
    animationRoot = source.animationRoot(firstSystem);
    for (final (index, node) in source.graph.descendants(root).indexed) {
      nodeOrdinals[node.key] = index;
    }
    for (final node in source.graph.descendants(animationRoot)) {
      pathHashes[node.key] = nativeEffectPathHash(
        source.graph.relativePath(node, animationRoot),
      );
    }
    final clipData = source
        .component(manifest['animationClipUrl'] as String)
        .data;
    clip = NativeAuthoredAnimationClip(clipData);
    sampleRate = (clipData['m_SampleRate'] as num).toDouble();
    if (!sampleRate.isFinite || sampleRate <= 0) {
      throw const FormatException('effect_clip_sample_rate');
    }
    sprites = [
      for (final entry in manifest['sprites'] as List)
        source.component((entry as Map)['metadataUrl'] as String),
    ];
  }
  final NativeChartEffectSource source;
  final Map manifest;
  late final NativeEffectObject root;
  late final NativeEffectObject animationRoot;
  late final NativeAuthoredAnimationClip clip;
  late final double sampleRate;
  late final List<NativeEffectObject> sprites;
  final pathHashes = <String, int>{};
  final nodeOrdinals = <String, int>{};
  final _activationStarts = <String, List<double>>{};
  late final _activationFrames = [
    for (final time in ({0.0, ...clip.keyTimes}.toList()..sort()))
      (time, NativeEffectAnimationFrame(clip, time)),
  ];

  bool particleActive(
    NativeEffectObject transform,
    NativeEffectAnimationFrame frame,
  ) {
    var node = transform;
    while (true) {
      final original = node.key == root.key
          ? true
          : source.graph.gameObject(node).data['m_IsActive'] as bool;
      final path = pathHashes[node.key];
      if (!(path == null ? original : frame.active(path, original))) {
        return false;
      }
      if (node.key == root.key) return true;
      node = source.graph.reference(node, node.data['m_Father'] as Map)!;
    }
  }

  double particleActiveAge(NativeEffectObject transform, double seconds) {
    final phase = manifest['loopAnimation'] == true && clip.duration > 0
        ? seconds % clip.duration
        : seconds;
    final starts = _activationStarts.putIfAbsent(transform.key, () {
      final output = <double>[];
      var active = false;
      for (final (time, frame) in _activationFrames) {
        final next = particleActive(transform, frame);
        if (next && !active) output.add(time);
        active = next;
      }
      return output;
    });
    var start = 0.0;
    for (final value in starts) {
      if (value > phase) break;
      start = value;
    }
    return phase - start;
  }
}

final class _FxInstance {
  _FxInstance(this.activation, this.note, this.spawnedUs, this.template)
    : systems = [
        for (final reference in template.manifest['particleSystems'] as List)
          AuthoredParticleSystem(template.source, reference as Map),
      ] {
    systems.sort(
      (a, b) => template.nodeOrdinals[a.transform.key]!.compareTo(
        template.nodeOrdinals[b.transform.key]!,
      ),
    );
    final geometry = template.source.recipe['geometry'] as Map;
    widthSet = _FxWidthSet(
      template,
      f(
        note.visualWidth *
            f(
              f(geometry['laneWidth'] as num) /
                  f(geometry['chartLaneCount'] as num),
            ),
      ),
    );
    _applyWidth();
    if (template.manifest['loopAnimation'] == true) {
      final controller =
          template.source.loopControllers[template.root.serializedFile];
      if (controller == null) {
        throw StateError('hold_effect_controller_missing');
      }
      _clock = NativeSingleStateClock(controller, template.clip.duration);
    }
  }
  final int activation, spawnedUs;
  final RuntimeVisualNote note;
  final _FxTemplate template;
  final List<AuthoredParticleSystem> systems;
  late _FxWidthSet widthSet;
  late double lane = note.visualLane, width = note.visualWidth;
  NativeSingleStateClock? _clock;
  void setPose(double nextLane, double nextWidth) {
    lane = nextLane;
    if (width == nextWidth) return;
    width = nextWidth;
    final geometry = template.source.recipe['geometry'] as Map;
    widthSet = _FxWidthSet(
      template,
      f(
        width *
            f(
              f(geometry['laneWidth'] as num) /
                  f(geometry['chartLaneCount'] as num),
            ),
      ),
    );
    _applyWidth();
  }

  void _applyWidth() {
    for (final system in systems) {
      system.sourceWidthBound = true;
      system.shapeWidthOverride = widthSet.shapeWidths[system.object.key];
      final scale = widthSet.scales[system.transform.key];
      if (scale != null) {
        system.localScaleOverride = Float64List.fromList(scale);
      }
    }
  }

  double animationSeconds = 0;
  NativeEffectAnimationFrame? frame;
  bool finished = false;
  final matrices = <String, Float32List>{};
  final activeSystems = <String>{};
  final Float32List _scalar = Float32List(1);

  void advance(double delta, {required bool mirror}) {
    _scalar[0] = animationSeconds + delta;
    animationSeconds = _clock?.advance(delta) ?? _scalar[0];
    final loop = template.manifest['loopAnimation'] == true;
    finished = !loop && animationSeconds >= template.clip.duration;
    if (finished) return;
    final current = NativeEffectAnimationFrame(
      template.clip,
      animationSeconds,
      loop: loop,
    );
    frame = current;
    final source = template.source, geometry = source.recipe['geometry'] as Map;
    final sourceLane = mirror ? 24 - lane - width : lane;
    final laneUnit =
        (geometry['laneWidth'] as num) / (geometry['chartLaneCount'] as num);
    final root = Float32List.fromList([
      1, // The prefab graph owns its authored root reflection.
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
      (sourceLane + width / 2 - 12) * laneUnit,
      0,
      (geometry['judgementRootZ'] as num).toDouble(),
      1,
    ]);
    final positions = <String, Float32List>{...widthSet.positions};
    for (final entry in template.pathHashes.entries) {
      final value =
          current.channels[entry.value]?[NativeEffectProperty.position];
      if (value != null) positions[entry.key] = value;
    }
    activeSystems.clear();
    for (final system in systems) {
      final active = template.particleActive(system.transform, current);
      final matrix = NativeAuthoredEffectGraph.multiply(
        root,
        source.graph.worldMatrix(
          system.transform,
          positions: positions,
          scales: widthSet.scales,
        ),
      );
      matrices[system.object.key] = matrix;
      if (active) activeSystems.add(system.object.key);
      system.simulateFrame(
        animationSeconds,
        frameDelta: delta,
        activeAge: active && !system.active
            ? template.particleActiveAge(system.transform, animationSeconds)
            : null,
        pathHash: template.pathHashes[system.transform.key]!,
        nativeWidth: widthSet.width,
        activeAt: (_) => active,
        frameAt: (_) => current,
        matrixAt: (_) => matrix,
      );
    }
  }
}

/// Bound source width setters run before the animator takes over its channels.
final class _FxWidthSet {
  _FxWidthSet(_FxTemplate template, this.width) {
    final source = template.source, file = template.root.serializedFile;
    final binding = source.noteWidthAssets[file];
    if (binding == null) {
      throw StateError('native_effect_width_asset_missing:$file');
    }
    final data = (binding['asset'] as Map)['data'] as Map;
    String target(Map row, String field) =>
        '$file:${(row[field] as Map)['m_PathID']}';
    double max0(double x) => x >= 0 ? x : 0;
    Float32List vector(String key, String property, double x) {
      final original = source.graph.objects[key]!.data[property] as Map;
      return Float32List.fromList([
        x,
        (original['y'] as num).toDouble(),
        (original['z'] as num).toDouble(),
      ]);
    }

    for (final row
        in (data['_particleShapeWidthSetParams'] as List).cast<Map>()) {
      shapeWidths[target(row, 'particleSystem')] = max0(
        f(f(row['scaleOffset'] as num) + width),
      );
    }
    for (final row
        in (data['_spriteRendererWidthSetParams'] as List).cast<Map>()) {
      spriteWidths[target(row, 'spriteRenderer')] = max0(
        f(f(row['sizeOffset'] as num) + width),
      );
    }
    for (final row in (data['_transformWidthSetParams'] as List).cast<Map>()) {
      final key = target(row, 'transform');
      scales[key] = vector(
        key,
        'm_LocalScale',
        max0(f(f(row['scaleOffset'] as num) + width)),
      );
    }
    for (final row
        in (data['_transformWidthSetRangeParams'] as List).cast<Map>()) {
      final key = target(row, 'transform'),
          a = f(row['min'] as num),
          b = f(row['max'] as num);
      final base = f((source.recipe['geometry'] as Map)['laneWidth'] as num);
      final t = f(width / base).clamp(0.0, 1.0);
      scales[key] = vector(key, 'm_LocalScale', max0(f(f(f(b - a) * t) + a)));
    }
    for (final row in (data['_leftCenterWidthSetParams'] as List).cast<Map>()) {
      final key = target(row, 'transform');
      positions[key] = vector(
        key,
        'm_LocalPosition',
        f(f(width * .5) + f(row['posOffset'] as num)),
      );
    }
    for (final row
        in (data['_rightCenterWidthSetParams'] as List).cast<Map>()) {
      final key = target(row, 'transform');
      positions[key] = vector(
        key,
        'm_LocalPosition',
        f(f(row['posOffset'] as num) - f(width * .5)),
      );
    }
  }
  final double width;
  final positions = <String, Float32List>{}, scales = <String, Float32List>{};
  final shapeWidths = <String, double>{}, spriteWidths = <String, double>{};
}
