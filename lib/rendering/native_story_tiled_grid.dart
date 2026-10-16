import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vega_plugin_haneoka/render_profile.dart';

/// Independent lower-left tile geometry for the full, unrotated Sprite domain.
/// Border order is original Vector4: left, bottom, right, top.
ProjectedMesh nativeStoryTiledGrid({
  required StoryUiRect rect,
  required double canvasWidth,
  required double canvasHeight,
  required List<double> color,
  required List<double> spriteSize,
  required List<double> border,
  required double pixelsPerUnit,
  required bool fillCenter,
}) {
  if (pixelsPerUnit <= 0 ||
      spriteSize.any((v) => !v.isFinite || v <= 0) ||
      border.any((v) => !v.isFinite || v < 0) ||
      rect.width < 0 ||
      rect.height < 0) {
    throw const FormatException('native_tiled_grid_units');
  }
  final hasBorder = border.any((v) => v > 0);
  List<double> bounds(double size, double lo, double hi) {
    final total = (lo + hi) / pixelsPerUnit;
    final factor = total > size && total > 0 ? size / total : 1.0;
    return [lo / pixelsPerUnit * factor, size - hi / pixelsPerUnit * factor];
  }

  final bx = bounds(rect.width, border[0], border[2]);
  final by = bounds(rect.height, border[1], border[3]);
  final interiorW = math.max(0.0, bx[1] - bx[0]);
  final interiorH = math.max(0.0, by[1] - by[0]);
  var periodW = (spriteSize[0] - border[0] - border[2]) / pixelsPerUnit;
  var periodH = (spriteSize[1] - border[1] - border[3]) / pixelsPerUnit;
  if (periodW <= 0) periodW = interiorW;
  if (periodH <= 0) periodH = interiorH;
  var nx = periodW > 0 ? (interiorW / periodW).ceil() : 0;
  var ny = periodH > 0 ? (interiorH / periodH).ceil() : 0;
  if (!fillCenter && !hasBorder) nx = ny = 0;
  final estimated = fillCenter
      ? (hasBorder ? (nx + 2) * (ny + 2) : nx * ny)
      : 2 * (nx + ny + 2);
  if (estimated > 16250) {
    // Preserve the source limit's axis arithmetic, including its unusual
    // ratio orientation. Enlarged periods alter visible terminal tiles.
    final ratio = fillCenter && hasBorder ? (nx + 2) / (ny + 2) : nx / ny;
    var targetX = fillCenter
        ? math.sqrt(16250 / ratio)
        : (16250 - 4) / (2 * (1 + ratio));
    var targetY = targetX * ratio;
    if (fillCenter && hasBorder) {
      targetX -= 2;
      targetY -= 2;
    }
    if (!targetX.isFinite || !targetY.isFinite || targetX < 1 || targetY < 1) {
      throw UnsupportedError('native_tiled_grid_degenerate_source_limit');
    }
    nx = targetX.floor();
    ny = targetY.floor();
    periodW = interiorW / nx;
    periodH = interiorH / ny;
  }
  final u = [
    0.0,
    border[0] / spriteSize[0],
    1 - border[2] / spriteSize[0],
    1.0,
  ];
  final v = [
    0.0,
    border[1] / spriteSize[1],
    1 - border[3] / spriteSize[1],
    1.0,
  ];
  final vertices = <double>[], indices = <int>[];
  final single = Float32List(1);
  double channel(double input) {
    single[0] = input.clamp(0.0, 1.0);
    single[0] *= 255;
    final lo = single[0].floor(), fraction = single[0] - single[0].floor();
    return (fraction < .5
            ? lo
            : fraction > .5
            ? lo + 1
            : lo.isEven
            ? lo
            : lo + 1) /
        255;
  }

  final tint = color.map(channel).toList();
  void quad(
    double x0,
    double y0,
    double x1,
    double y1,
    double u0,
    double v0,
    double u1,
    double v1,
  ) {
    if (x1 <= x0 || y1 <= y0) return;
    final base = vertices.length ~/ 10;
    if (base + 4 > 65000) {
      throw StateError('native_tiled_grid_source_vertex_limit');
    }
    for (final p in [
      [x0, y0, u0, v0],
      [x0, y1, u0, v1],
      [x1, y1, u1, v1],
      [x1, y0, u1, v0],
    ]) {
      vertices.addAll([
        2 * (rect.x + p[0]) / canvasWidth - 1,
        1 - 2 * (rect.y + rect.height - p[1]) / canvasHeight,
        0,
        1,
        p[2],
        1 - p[3],
        ...tint,
      ]);
    }
    indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }

  // Center first, then vertical sides, horizontal sides and four corners,
  // matching source lower-left tile origin and source UI draw ordering.
  if (fillCenter) {
    for (var row = 0; row < ny; row++) {
      final y0 = by[0] + row * periodH;
      final y1 = math.min(by[1], y0 + periodH);
      final vf = v[1] + (v[2] - v[1]) * (y1 - y0) / periodH;
      for (var col = 0; col < nx; col++) {
        final x0 = bx[0] + col * periodW;
        final x1 = math.min(bx[1], x0 + periodW);
        final uf = u[1] + (u[2] - u[1]) * (x1 - x0) / periodW;
        quad(x0, y0, x1, y1, u[1], v[1], uf, vf);
      }
    }
  }
  if (hasBorder) {
    for (var row = 0; row < ny; row++) {
      final y0 = by[0] + row * periodH;
      final y1 = math.min(by[1], y0 + periodH);
      final vf = v[1] + (v[2] - v[1]) * (y1 - y0) / periodH;
      quad(0, y0, bx[0], y1, u[0], v[1], u[1], vf);
      quad(bx[1], y0, rect.width, y1, u[2], v[1], u[3], vf);
    }
    for (var col = 0; col < nx; col++) {
      final x0 = bx[0] + col * periodW;
      final x1 = math.min(bx[1], x0 + periodW);
      final uf = u[1] + (u[2] - u[1]) * (x1 - x0) / periodW;
      quad(x0, 0, x1, by[0], u[1], v[0], uf, v[1]);
      quad(x0, by[1], x1, rect.height, u[1], v[2], uf, v[3]);
    }
    quad(0, 0, bx[0], by[0], u[0], v[0], u[1], v[1]);
    quad(bx[1], 0, rect.width, by[0], u[2], v[0], u[3], v[1]);
    quad(0, by[1], bx[0], rect.height, u[0], v[2], u[1], v[3]);
    quad(bx[1], by[1], rect.width, rect.height, u[2], v[2], u[3], v[3]);
  }
  return ProjectedMesh(
    Float32List.fromList(vertices),
    Uint16List.fromList(indices),
  );
}
