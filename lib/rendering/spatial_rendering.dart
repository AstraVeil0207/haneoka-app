import 'package:render_kernel_flutter/render_kernel_flutter.dart';

/// World-only reconstruction; native UI retains its full viewport.
(int, int)? spatialWorldViewport(int width, int height, double factor) =>
    factor > 1 ? SpatialUpscaler.inputSize(width, height, factor) : null;
