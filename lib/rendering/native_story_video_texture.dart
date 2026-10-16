import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:vega_plugin_haneoka/render_profile.dart' show StoryMediaObservation;
import 'package:vega_renderer_flutter/vega_renderer_flutter.dart';

import 'native_story_media.dart';

/// Captures a painted native video boundary as a GPU image, then wraps that
/// storage through the official Flutter GPU texture API. No PNG/CPU readback.
final class NativeStoryVideoTexture {
  NativeStoryVideoTexture({
    required this.cue,
    required this.renderer,
    required this.textureKey,
    required this.isCurrent,
    required this.boundaryKey,
    required this.pixelRatio,
  });
  final NativeStoryMediaCue cue;
  final GpuFrameRenderer renderer;
  final String textureKey;
  final bool Function() isCurrent;
  final GlobalKey boundaryKey;
  final double pixelRatio;
  bool _closed = false;
  int? lastCaptureBeganUtcUs, lastCaptureEndedUtcUs, lastMediaSampleUtcUs;
  bool _busy = false;
  int captures = 0;
  StoryMediaObservation? lastObservedMedia;
  (int, int)? pixelSize;

  Future<bool> capturePaintedFrame() async {
    if (_busy || _closed || !isCurrent()) return false;
    _busy = true;
    ui.Image? image;
    try {
      await cue.firstVideoFrame();
      if (_closed || !isCurrent()) return false;
      await SchedulerBinding.instance.endOfFrame;
      if (_closed || !isCurrent()) return false;
      final boundary = boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || boundary.debugNeedsPaint) {
        return false;
      }
      lastCaptureBeganUtcUs = DateTime.now().toUtc().microsecondsSinceEpoch;
      image = await boundary.toImage(pixelRatio: pixelRatio);
      lastCaptureEndedUtcUs = DateTime.now().toUtc().microsecondsSinceEpoch;
      if (_closed || !isCurrent()) return false;
      final actual = await cue.sample();
      lastMediaSampleUtcUs = DateTime.now().toUtc().microsecondsSinceEpoch;
      if (_closed || !isCurrent() || actual == null) return false;
      renderer.installDecodedImage(textureKey, image);
      lastObservedMedia = actual;
      pixelSize = (image.width, image.height);
      captures++;
      return true;
    } finally {
      image?.dispose();
      _busy = false;
    }
  }

  Map<String, Object?> get observation => {
    'captures': captures,
    'pixelSize': pixelSize == null ? null : [pixelSize!.$1, pixelSize!.$2],
    'captureBeganUtcUs': lastCaptureBeganUtcUs,
    'captureEndedUtcUs': lastCaptureEndedUtcUs,
    'mediaSampleUtcUs': lastMediaSampleUtcUs,
    'sampleAfterCapture': lastObservedMedia?.positionUs,
    'sampleIsPicturePTS': false,
    'sourceEpoch': cue.sourceEpoch,
    'cueUri': cue.uri.toString(),
  };
  void close() {
    _closed = true;
  }
}
