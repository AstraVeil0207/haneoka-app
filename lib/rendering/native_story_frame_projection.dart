import 'dart:typed_data';

import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_frame_data.dart';

/// Screen-space Canvas plane mapping. All actual drawing transforms are checked
/// for exact planarity by the assembler before this normalized projection.
Float32List nativeStoryFramePlaneClip(
  NativeStoryFrameData source,
  StoryFrameCanvasMetrics metrics,
) {
  final c = source.canvas, v = source.viewTransform;
  if (c['m_RenderMode'] != 1 ||
      c['m_TargetDisplay'] != 0 ||
      c['m_PixelPerfect'] != false ||
      c['m_SortingOrder'] != 303) {
    throw UnsupportedError('native_frame_canvas_plane_contract');
  }
  void vector(String field, Map<String, num> expected) {
    final actual = v[field] as Map;
    if (expected.entries.any((entry) => actual[entry.key] != entry.value)) {
      throw UnsupportedError('native_frame_view_plane_contract:$field');
    }
  }

  vector('m_AnchorMin', const {'x': 0, 'y': 0});
  vector('m_AnchorMax', const {'x': 1, 'y': 1});
  vector('m_SizeDelta', const {'x': 0, 'y': 0});
  vector('m_Pivot', const {'x': .5, 'y': .5});
  vector('m_AnchoredPosition', const {'x': 0, 'y': 0});
  vector('m_LocalPosition', const {'x': 0, 'y': 0, 'z': 0});
  vector('m_LocalScale', const {'x': 1, 'y': 1, 'z': 1});
  vector('m_LocalRotation', const {'x': 0, 'y': 0, 'z': 0, 'w': 1});
  if (!metrics.width.isFinite ||
      !metrics.height.isFinite ||
      metrics.width <= 0 ||
      metrics.height <= 0) {
    throw StateError('native_frame_actual_viewport');
  }
  // The stretched View's origin is its center pivot. Logical coordinates x,y
  // map through actual Canvas scale to full-view pixels; canceling those two
  // factors gives (2*x/logicalWidth, 2*y/logicalHeight). Camera placement and
  // planeDistance cancel only on that plane; off-plane nodes are held.
  return Float32List.fromList([
    2 / metrics.width,
    0,
    0,
    0,
    0,
    2 / metrics.height,
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
}
