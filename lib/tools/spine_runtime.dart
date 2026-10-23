import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:spine_flutter/spine_flutter.dart' as spine;

import '../core/api.dart';
import '../core/resource_file_cache.dart';
import '../core/resource_archive.dart';

Future<void>? _spineInitialization;

class NativeSpineModel extends ChangeNotifier {
  NativeSpineModel._(this.drawable, this.resources, this.bounds);
  final spine.SkeletonDrawable drawable;
  final Map<String, Uint8List> resources;
  final ui.Rect bounds;
  bool _disposed = false;
  List<String> get animations => [
    for (final animation in drawable.skeletonData.getAnimations())
      animation.getName(),
  ];
  List<String> get skins => [
    for (final skin in drawable.skeletonData.getSkins()) skin.getName(),
  ];
  String animation = '', skin = '';
  bool playing = true, loop = true;
  double rate = 1;
  final position = ValueNotifier<double>(0);
  double get duration =>
      drawable.animationState.getCurrent(0)?.getAnimation().getDuration() ?? 0;

  static Future<NativeSpineModel> load(
    HaneokaApi api,
    Map detail, {
    required bool Function() current,
  }) async {
    await (_spineInitialization ??= spine.initSpineFlutter());
    final runtime = detail['runtime'] as Map;
    final atlasPath = '${(runtime['atlas'] as Map)['url']}';
    final binary = runtime['format'] == 'binary';
    final skeletonPath = '${(runtime['json'] as Map)['url']}';
    final resources = <String, Uint8List>{};
    Future<Uint8List> read(String path) async {
      final bytes = await resourceFileCache.readBytes(
        api.asset(path),
        kind: ResourceFileKind.renderResource,
      );
      if (!current()) throw const ResourceCacheCancelled();
      return bytes;
    }

    resources['model.atlas'] = await read(atlasPath);
    resources[binary ? 'model.skel' : 'model.json'] = await read(skeletonPath);
    for (final atlas in detail['atlases'] as List) {
      for (final page in (atlas as Map)['pages'] as List) {
        resources['${(page as Map)['name']}'] = await read('${page['url']}');
      }
    }
    spine.Atlas? atlas;
    spine.SkeletonData? data;
    spine.SkeletonDrawable? drawable;
    try {
      spine.Atlas.filterQuality = FilterQuality.medium;
      atlas = await spine.Atlas.fromAsset(
        'model.atlas',
        bundle: _ModelBundle(resources),
      );
      if (!current()) throw const ResourceCacheCancelled();
      data = binary
          ? spine.SkeletonData.fromBinary(atlas, resources['model.skel']!)
          : spine.SkeletonData.fromJson(
              atlas,
              utf8.decode(resources['model.json']!),
            );
      drawable = spine.SkeletonDrawable(atlas, data, true);
      drawable.animationStateData.setDefaultMix(
        (detail['defaultMix'] as num?)?.toDouble() ?? .2,
      );
      final authored = (detail['bounds'] as Map?) ?? const {};
      final setup = drawable.skeleton.getBounds();
      final bounds = ui.Rect.fromLTWH(
        (authored['x'] as num?)?.toDouble() ?? setup.x,
        authored['y'] is num && authored['height'] is num
            ? -(authored['y'] as num).toDouble() - (authored['height'] as num).toDouble()
            : setup.y,
        (authored['width'] as num?)?.toDouble() ?? setup.width,
        (authored['height'] as num?)?.toDouble() ?? setup.height,
      );
      final model = NativeSpineModel._(drawable, resources, bounds);
      final skins = model.skins;
      final initialSkin = [
        'skin',
        'default',
        ...skins,
      ].where(skins.contains).firstOrNull;
      if (initialSkin != null) model.setSkin(initialSkin);
      final animations = model.animations;
      final initial = [
        'f_idle',
        'idle',
        ...animations,
      ].where(animations.contains).firstOrNull;
      if (initial != null) model.play(initial);
      return model;
    } catch (_) {
      if (drawable != null) {
        drawable.dispose();
      } else {
        data?.dispose();
        atlas?.dispose();
      }
      rethrow;
    }
  }

  void advance(double seconds) {
    if (!playing || _disposed) return;
    drawable.update(seconds * rate);
    final entry = drawable.animationState.getCurrent(0);
    position.value = entry?.getAnimationTime() ?? 0;
    notifyListeners();
  }

  void play(String name) {
    animation = name;
    drawable.animationState.setAnimationByName(0, name, loop);
    drawable.update(0);
    position.value = 0;
    notifyListeners();
  }

  void setSkin(String name) {
    skin = name;
    drawable.skeleton.setSkinByName(name);
    drawable.skeleton.setSlotsToSetupPose();
    drawable.update(0);
    notifyListeners();
  }

  void seek(double time) {
    final entry = drawable.animationState.getCurrent(0);
    entry?.setTrackTime(time);
    drawable.skeleton.setToSetupPose();
    drawable.skeleton.updateWorldTransform(spine.Physics.reset);
    drawable.update(0);
    position.value = time;
    notifyListeners();
  }

  Future<Uint8List> package() => createResourceArchive(resources, checkCurrent: () {
    if (_disposed) throw const ResourceCacheCancelled();
  });

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    drawable.dispose();
    resources.clear();
    position.dispose();
    super.dispose();
  }
}

class _ModelBundle extends CachingAssetBundle {
  _ModelBundle(this.resources);
  final Map<String, Uint8List> resources;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(resources[p.normalize(key)]!);
}

class NativeSpinePainter extends CustomPainter {
  NativeSpinePainter(this.model, this.background) : super(repaint: model);
  final NativeSpineModel model;
  final ui.Color? background;
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (background != null) {
      canvas.drawRect(ui.Offset.zero & size, ui.Paint()..color = background!);
    }
    final bounds = model.bounds;
    final fit =
        math.min(size.width / bounds.width, size.height / bounds.height) * .9;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(fit, fit);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    model.drawable.renderToCanvas(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(NativeSpinePainter old) =>
      old.model != model || old.background != background;
}
