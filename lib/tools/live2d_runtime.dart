import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:vega_plugin_haneoka/native_cubism.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';
import 'package:vega_renderer_flutter/vega_renderer_flutter.dart';

import '../core/api.dart';
import '../core/resource_file_cache.dart';
import '../core/resource_archive.dart';
import '../rendering/native_cubism_model_source.dart';

/// The standalone viewer uses the same original prefab evaluator as ADV.
class NativeLive2DModel {
  NativeLive2DModel._(this.api, this.source, this.current) {
    const configured = String.fromEnvironment('HANEOKA_CUBISM_CORE');
    core = NativeCubismCore.open(
      libraryPath: configured.isEmpty ? null : configured,
    );
    _createHost();
    initialParts = {
      for (final entry in host.model.parts.entries)
        entry.key: host.parameters.parts[entry.value],
    };
    bounds = _bounds(host.displayed);
    session = VegaRenderSession(
      renderer: GpuFrameRenderer(
        gpu.gpuContext,
        programs: haneokaShaderPrograms,
      ),
      fetch: _fetch,
      reuseDecodedImages: const {'jp', 'intl'}.contains(api.server),
    );
    session.image.addListener(repaint.mark);
  }
  final HaneokaApi api;
  final NativeCubismModelSource source;
  final bool Function() current;
  late final NativeCubismCore core;
  late NativeCubismModelHost host;
  late final VegaRenderSession session;
  late NativeCubismModelSnapshot _initial;
  late final ui.Rect bounds;
  late final Map<String, double> initialParts;
  final repaint = _ModelRepaint();
  final error = ValueNotifier<Object?>(null);
  final position = ValueNotifier<double>(0);
  final parameters = ValueNotifier<Map<String, double>>({});
  final locked = <String, double>{};
  final parts = <String, double>{};
  bool playing = true,
      loop = false,
      blink = true,
      breath = true,
      manual = false;
  double rate = 1, _seconds = 0, _motionStarted = 0;
  double _sampleAt = 0;
  bool _oneShot = false;
  int _frame = 0, _width = 0, _height = 0;
  String motion = '', expression = '';
  bool _closed = false, _opened = false, _dirty = false;
  Future<void>? _pending, _closing;
  double get duration => host.prefab.clips[motion]?.duration ?? 0;
  List<String> get motions => host.prefab.clips.keys.toList();
  List<String> get expressions => [
    for (final row in host.prefab.preparedExpressions) row.name,
  ];
  Map get detail => source.catalog;

  static Future<NativeLive2DModel> load(
    HaneokaApi api,
    String key,
    bool Function() current,
  ) async {
    final release = await api.release();
    if (api.sourceId == null) await api.revalidate();
    final identity = StorySourceIdentity(
      namespace: api.server,
      revision: release,
      resourceScope: api.sourceId!,
      document: key,
      contentIdentity: key,
    );
    final source = await NativeCubismModelSource.load(
      api,
      identity,
      key,
      current,
    );
    if (!current()) throw const ResourceCacheCancelled();
    return NativeLive2DModel._(api, source, current);
  }

  Future<Uint8List> _fetch(Uri uri) async {
    final bytes = await resourceFileCache.readBytes(
      uri,
      kind: ResourceFileKind.renderResource,
    );
    if (_closed || !current()) throw const ResourceCacheCancelled();
    return bytes;
  }

  void _createHost() {
    host = NativeCubismModelHost(
      core: core,
      mocBytes: source.mocBytes,
      prefabRecords: source.records,
      preparedPrefab: source.preparedPrefab,
      randomUnit: math.Random().nextDouble,
      breathMotionEnabled: breath,
    );
    host.show(true);
    host.setEyeBlinkStopped(!blink);
    _seconds = 0;
    _motionStarted = 0;
    _sampleAt = 0;
    _frame = 0;
    _initial = host.snapshot();
    motion = host.defaultMotion;
    expression = host.defaultExpression;
  }

  Map<int, Uri> get _textures => {
    for (final (index, path)
        in (((source.catalog['runtime'] as Map)['textures'] as List).indexed))
      index: api
          .asset(path as String)
          .replace(queryParameters: {'release': source.identity.release}),
  };

  static ui.Rect _bounds(List<NativeCubismDrawable> drawables) {
    final maskSources = {for (final drawable in drawables) ...drawable.masks};
    double left = double.infinity, right = double.negativeInfinity;
    double top = double.infinity, bottom = double.negativeInfinity;
    for (final drawable in drawables) {
      if (!drawable.visible ||
          drawable.opacity == 0 ||
          maskSources.contains(drawable.sourceIndex)) {
        continue;
      }
      for (var i = 0; i < drawable.positions.length; i += 2) {
        left = math.min(left, drawable.positions[i]);
        right = math.max(right, drawable.positions[i]);
        top = math.min(top, drawable.positions[i + 1]);
        bottom = math.max(bottom, drawable.positions[i + 1]);
      }
    }
    return ui.Rect.fromLTRB(left, top, right, bottom);
  }

  void configure(ui.Size size, double pixelRatio) {
    final factor = math.min(
      pixelRatio,
      4096 / math.max(size.width, size.height),
    );
    final width = (size.width * factor).round().clamp(1, 4096);
    final height = (size.height * factor).round().clamp(1, 4096);
    if (_width == width && _height == height) return;
    _width = width;
    _height = height;
    unawaited(render());
  }

  void advance(double delta) {
    if (_closed || !playing || manual || error.value != null) return;
    delta *= rate;
    if (_oneShot && duration > 0) {
      delta = math.min(
        delta,
        math.max(0, duration - (_seconds - _motionStarted)),
      );
    }
    _seconds += delta;
    host.acceptedStep(
      frame: ++_frame,
      seconds: _seconds,
      delta: delta,
      paused: false,
    );
    final end = duration;
    final elapsed = _seconds - _motionStarted;
    position.value = end > 0
        ? (loop ? elapsed % end : math.min(elapsed, end))
        : 0;
    if (_seconds - _sampleAt >= .1) {
      _sampleAt = _seconds;
      parameters.value = {
        for (final entry in host.model.parameters.entries)
          entry.key: host.parameters.values[entry.value],
      };
    }
    unawaited(render());
  }

  void playMotion(String name, {bool oneShot = false}) {
    if (name.isEmpty) return;
    if (manual) {
      for (final entry in locked.entries) {
        host.parameters.overwrite(
          host.model.parameters[entry.key]!,
          entry.value,
        );
      }
      host.parameters.save();
    }
    locked.clear();
    _oneShot = oneShot;
    motion = name;
    manual = false;
    _motionStarted = _seconds;
    host.playMotion(name, repeat: !oneShot && loop);
    position.value = 0;
    unawaited(render());
  }

  void playExpression(String name) {
    expression = name;
    host.playExpression(name);
    unawaited(render());
  }

  void setBlink(bool enabled) {
    blink = enabled;
    host.setEyeBlinkStopped(!enabled);
  }

  void setBreath(bool enabled) {
    breath = enabled;
    host.setBreathMotionEnabled(enabled);
  }

  void look(ui.Offset? direction, {bool sway = false}) {
    host.setEyeLook(direction?.dx, direction?.dy);
    host.setAngleOffsets(
      sway ? direction?.dx : null,
      sway ? direction?.dx : null,
    );
  }

  void setParameter(String id, double value) {
    locked[id] = value;
    unawaited(render());
  }

  void setPart(String id, double value) {
    parts[id] = value;
    final index = host.model.parts[id]!;
    host.parameters.parts[index] = value;
    host.parameters.savedParts[index] = value;
    unawaited(render());
  }

  void resetPose() {
    locked.clear();
    parts.clear();
    manual = false;
    host.dispose();
    _createHost();
    position.value = 0;
    unawaited(render());
  }

  Map<String, Object?> pose() => {
    'model': source.key,
    'name': '',
    'mode': 'pose',
    'parameters': {
      for (final entry in host.model.parameters.entries)
        entry.key: locked[entry.key] ?? host.parameters.values[entry.value],
    },
    'parts': {
      for (final entry in host.model.parts.entries)
        entry.key: parts[entry.key] ?? host.parameters.parts[entry.value],
    },
  };
  void applyPose(Map document) {
    final values = document['parameters'] ?? document;
    if (values is! Map) throw const FormatException('invalidParameterPose');
    final parameters = <String, double>{
      for (final entry in host.model.parameters.entries)
        entry.key: locked[entry.key] ?? host.parameters.values[entry.value],
    };
    final visibility = <String, double>{};
    if (!values.entries.any(
      (entry) =>
          host.model.parameters.containsKey(entry.key) &&
          entry.value is num &&
          (entry.value as num).isFinite,
    )) {
      throw const FormatException('invalidParameterPose');
    }
    for (final entry in values.entries) {
      if (!host.model.parameters.containsKey(entry.key)) continue;
      if (entry.value is! num || !(entry.value as num).isFinite) continue;
      final index = host.model.parameters[entry.key]!;
      parameters['${entry.key}'] = (entry.value as num).toDouble().clamp(
        host.parameters.minimum[index],
        host.parameters.maximum[index],
      );
    }
    for (final entry in (document['parts'] as Map? ?? const {}).entries) {
      if (!host.model.parts.containsKey(entry.key)) continue;
      if (entry.value is! num || !(entry.value as num).isFinite) continue;
      visibility['${entry.key}'] = (entry.value as num).toDouble().clamp(0, 1);
    }
    locked
      ..clear()
      ..addAll(parameters);
    parts
      ..clear()
      ..addAll(visibility);
    manual = true;
    _oneShot = false;
    unawaited(render());
  }

  void seek(double seconds) {
    host.restore(_initial);
    _seconds = 0;
    _frame = 0;
    _motionStarted = 0;
    host.playMotion(motion, fade: 0, repeat: loop);
    if (expression.isNotEmpty) host.playExpression(expression, fade: 0);
    while (_seconds < seconds) {
      final delta = math.min(1 / 60, seconds - _seconds);
      _seconds += delta;
      host.acceptedStep(
        frame: ++_frame,
        seconds: _seconds,
        delta: delta,
        paused: false,
      );
    }
    position.value = seconds;
    unawaited(render());
  }

  Future<void> render() {
    if (_closed || _width == 0) return Future.value();
    _dirty = true;
    if (_pending != null) return _pending!;
    final work = _drain();
    _pending = work;
    unawaited(
      work.then<void>(
        (_) {
          _pending = null;
        },
        onError: (Object error, StackTrace stack) {
          _pending = null;
          if (!_closed) {
            lastError = error;
            this.error.value = error;
          }
        },
      ),
    );
    return work;
  }

  Object? lastError;
  Future<void> _drain() async {
    do {
      _dirty = false;
      final width = _width, height = _height;
      var drawables = host.displayed;
      if (manual || locked.isNotEmpty || parts.isNotEmpty) {
        if (manual) host.model.resetParameters();
        for (final entry in locked.entries) {
          host.model.setParameter(entry.key, entry.value);
        }
        for (final entry in parts.entries) {
          host.model.setPartOpacity(entry.key, entry.value);
        }
        drawables = host.model.evaluate();
      }
      final fit = math.min(width / bounds.width, height / bounds.height) * .9;
      final projection = Float32List.fromList([
        2 * fit / width,
        0,
        0,
        0,
        0,
        2 * fit / height,
        0,
        0,
        0,
        0,
        1,
        0,
        -bounds.center.dx * 2 * fit / width,
        -bounds.center.dy * 2 * fit / height,
        0,
        1,
      ]);
      final meshes = <String, ProjectedMesh>{},
          materials = <String, NativeMaterial>{};
      final textures = _textures;
      final generated = buildNativeCubismMeshes(
        modelKey: source.key,
        evaluated: drawables,
        clipTransform: projection,
        textureKeys: {
          for (final index in textures.keys) index: 'texture:$index',
        },
        maskTextureSize: host.maskTextureSize,
        meshes: meshes,
        materials: materials,
      );
      final scene = NativeSceneResources(
        epoch: 1,
        source: RenderSource(
          server: api.server,
          release: source.identity.release,
          document: source.key,
        ),
        meshes: meshes,
        materials: materials,
        targets: {
          ...generated.targets,
          'output': NativeTarget(
            width: width,
            height: height,
            presentable: true,
          ),
        },
      );
      final frame = NativeFrame(
        epoch: 1,
        mediaMicroseconds: (_seconds * 1000000).round(),
        outputTarget: 'output',
        passes: [
          ...generated.maskPasses,
          NativePass(target: 'output', draws: generated.draws),
        ],
      );
      if (!_opened) {
        await session.open(
          handwrittenShaderBundle: await loadHaneokaProfileAsset(
            haneokaShaderBundle,
          ),
          scene: toRenderScene(scene),
          textures: {
            for (final entry in textures.entries)
              'texture:${entry.key}': entry.value,
          },
          initialFrame: frame,
        );
        _opened = true;
      } else {
        await session.present(
          frame,
          resources: toRenderScene(scene),
          stillCurrent: () => !_closed && current(),
        );
      }
    } while (_dirty && !_closed && current());
  }

  Future<Uint8List> package() async {
    final runtime = source.catalog['runtime'] as Map;
    final uri = api
        .asset(runtime['model'] as String)
        .replace(queryParameters: {'release': source.identity.release});
    final bytes = await _fetch(uri);
    final document = jsonDecode(utf8.decode(bytes)) as Map;
    final refs = document['FileReferences'] as Map;
    final resources = <Uri, String>{};
    String local(String source, String target) => resources.putIfAbsent(
      uri.resolve(source).replace(queryParameters: uri.queryParameters),
      () => target,
    );
    refs['Moc'] = local(refs['Moc'] as String, 'model.moc3');
    final textures = refs['Textures'] as List;
    for (var i = 0; i < textures.length; i++) {
      final source = textures[i] as String;
      textures[i] = local(
        source,
        'textures/texture_$i${p.extension(Uri.parse(source).path)}',
      );
    }
    for (final field in const ['Physics', 'Pose', 'UserData', 'DisplayInfo']) {
      if (refs[field] case final String path) {
        refs[field] = local(path, '${field.toLowerCase()}.json');
      }
    }
    for (final (index, value)
        in (refs['Expressions'] as List? ?? const []).indexed) {
      final expression = value as Map;
      expression['File'] = local(
        expression['File'] as String,
        'expressions/expression_$index.exp3.json',
      );
    }
    var index = 0;
    for (final group in (refs['Motions'] as Map? ?? const {}).values) {
      for (final value in group as List) {
        final motion = value as Map;
        motion['File'] = local(
          motion['File'] as String,
          'motions/motion_${index++}.motion3.json',
        );
        if (motion['Sound'] case final String sound) {
          motion['Sound'] = local(
            sound,
            'sounds/sound_$index${p.extension(Uri.parse(sound).path)}',
          );
        }
      }
    }
    final modelBytes = utf8.encode(jsonEncode(document));
    final files = <String, Uint8List>{'model3.json': modelBytes};
    final entries = resources.entries.toList();
    for (var index = 0; index < entries.length; index += 4) {
      await Future.wait([
        for (final entry in entries.skip(index).take(4))
          () async {
            files[entry.value] = await _fetch(entry.key);
          }(),
      ]);
    }
    return createResourceArchive(
      files,
      checkCurrent: () {
        if (_closed || !current()) throw const ResourceCacheCancelled();
      },
    );
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    try {
      await _pending;
    } catch (_) {}
    session.image.removeListener(repaint.mark);
    await session.dispose();
    host.dispose();
    position.dispose();
    parameters.dispose();
    repaint.dispose();
    error.dispose();
  }
}

class _ModelRepaint extends ChangeNotifier {
  void mark() => notifyListeners();
}

class NativeLive2DPainter extends CustomPainter {
  NativeLive2DPainter(this.model, this.background)
    : super(repaint: model.repaint);
  final NativeLive2DModel model;
  final ui.Color? background;
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (background != null) {
      canvas.drawRect(ui.Offset.zero & size, ui.Paint()..color = background!);
    }
    final image = model.session.image.value;
    if (image != null) {
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Offset.zero & size,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    }
  }

  @override
  bool shouldRepaint(NativeLive2DPainter old) =>
      old.model != model || old.background != background;
}
