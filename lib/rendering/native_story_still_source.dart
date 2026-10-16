import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show haneokaProfileAssetRoot;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';

/// The selected source's original serialized DOTween settings and StillView
/// Image color supply constructor values independently of chapter commands.
final class NativeStoryStillSource {
  const NativeStoryStillSource._(
    this.fadeEase,
    this.initialOverlayAlpha,
    this.sourceHash,
  );
  final int fadeEase;
  final double initialOverlayAlpha;
  final String sourceHash;

  /// The release-pinned formal presentation carries its original external UI
  /// records. recordsSHA256 is producer canonical provenance, not a Dart rehash.
  static StoryStillExternalLayoutSource? externalLayout(
    StorySourceIdentity source,
    Map<String, Map<String, Object?>> presentations,
  ) {
    var formal = 0;
    for (final presentation in presentations.values) {
      final layout = presentation['layout'] as Map;
      if (layout.containsKey('stillExternalLayout')) formal++;
    }
    // Unmigrated documents retain their previous normal presentation path.
    if (formal == 0) return null;
    if (formal != presentations.length) {
      throw const FormatException(
        'native_still_external_layout_incomplete_boundary',
      );
    }
    StoryStillExternalLayoutSource? bound;
    String? boundSourcePath, boundSourceHash;
    for (final presentation in presentations.values) {
      final layout = presentation['layout'] as Map;
      final value = layout['stillExternalLayout'];
      if (value is! Map) {
        throw const FormatException(
          'native_still_formal_external_layout_missing',
        );
      }
      final parsed = StoryStillExternalLayoutSource.fromPacket(
        Map<String, Object?>.from(value),
        expectedSourceId: source.sourceId,
      );
      if (bound != null &&
          (bound.packetSHA256 != parsed.packetSHA256 ||
              bound.serializedFile != parsed.serializedFile ||
              bound.canvasRectId != parsed.canvasRectId ||
              bound.scalerId != parsed.scalerId ||
              bound.viewComponentId != parsed.viewComponentId ||
              bound.targetId != parsed.targetId ||
              boundSourcePath != value['sourcePath'] ||
              boundSourceHash != value['sourceHash'])) {
        throw const FormatException('native_still_external_binding_mismatch');
      }
      bound ??= parsed;
      boundSourcePath ??= value['sourcePath'] as String;
      boundSourceHash ??= value['sourceHash'] as String;
    }
    return bound;
  }

  static Future<NativeStoryStillSource> load(StorySourceIdentity source) async {
    if (source.server != 'intl' ||
        source.sourceId != 'v25-c0b6a1541e45-3a5d2eec9935-n653c6392') {
      throw UnsupportedError('native_story_still_source:${source.sourceId}');
    }
    final data = await rootBundle.load(
      '${haneokaProfileAssetRoot}story-ui/source-bindings/still-constructor.json',
    );
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final hash = sha256.convert(bytes).toString();
    if (hash !=
        '92051478a477cd45e3eb6494d69a7538eb62bc17a5102fe58549da173cd04366') {
      throw const FormatException('native_story_still_constructor_identity');
    }
    final raw = jsonDecode(utf8.decode(bytes)) as Map;
    if (raw['sourceId'] != source.sourceId ||
        raw['defaultUpdateType'] != 0 ||
        raw['timeScale'] != 1 ||
        raw['defaultTimeScaleIndependent'] != false ||
        raw['backgroundAwakeAlpha'] != 0) {
      throw const FormatException('native_story_still_clock_contract');
    }
    return NativeStoryStillSource._(
      raw['actualFadeEase'] as int,
      (raw['actualInitialOverlayAlpha'] as num).toDouble(),
      hash,
    );
  }
}
