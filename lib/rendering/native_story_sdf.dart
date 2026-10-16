import 'dart:typed_data';
import 'dart:math' as math;

import 'package:vega_plugin_haneoka/render_profile.dart';

final class NativeStoryResolvedSdfMaterial {
  NativeStoryResolvedSdfMaterial({
    required this.material,
    required this.materialName,
    required Map<String, Object?> primaryProvenance,
    required Map<String, Object?> targetProvenance,
  }) : primaryProvenance = Map.unmodifiable(primaryProvenance),
       targetProvenance = Map.unmodifiable(targetProvenance);

  final StorySdfMaterialData material;
  final String materialName;
  final Map<String, Object?> primaryProvenance, targetProvenance;
}

/// Compose a preset with its explicitly bound fallback font's default material.
/// The caller verifies the original font, material and atlas PPtr relationships.
NativeStoryResolvedSdfMaterial nativeStoryFallbackSdfMaterial({
  required StoryFontData primaryFont,
  required StoryFontData actualFont,
  required String primaryMaterialName,
  required String fallbackAssetName,
  required String primaryMaterialKey,
  required String targetDefaultMaterialKey,
  required Map<String, Object?> primaryMaterial,
  required Map<String, Object?> targetDefaultMaterial,
  required Map<String, Object?> primaryProvenance,
  required Map<String, Object?> targetProvenance,
  required String sourcePath,
  required String sourceHash,
  required bool matchMaterialPreset,
}) {
  if (!matchMaterialPreset ||
      primaryFont.id == actualFont.id ||
      primaryMaterialName.isEmpty ||
      fallbackAssetName.isEmpty ||
      primaryProvenance.isEmpty ||
      targetProvenance.isEmpty) {
    throw const FormatException('native_story_fallback_material_binding');
  }
  final primary = StorySdfMaterialData.fromRaw(
    primaryMaterial,
    actualFont: primaryFont,
    sourceMaterialKey: primaryMaterialKey,
    sourcePath: sourcePath,
    sourceHash: sourceHash,
  );
  final target = StorySdfMaterialData.fromRaw(
    targetDefaultMaterial,
    actualFont: actualFont,
    sourceMaterialKey: targetDefaultMaterialKey,
    sourcePath: sourcePath,
    sourceHash: sourceHash,
  );
  if (!primary.usable || !target.usable) {
    throw UnsupportedError(
      'native_story_fallback_material_source:'
      '${primary.unsupported}:${target.unsupported}',
    );
  }
  final floats = Map<String, double>.from(primary.floats);
  for (final field in const [
    '_GradientScale',
    '_TextureWidth',
    '_TextureHeight',
    '_WeightNormal',
    '_WeightBold',
  ]) {
    floats[field] = target.requireFloat(field);
  }
  // The active mobile preset has no glow properties. Preserve its ratio B.
  if (floats.containsKey('_GlowOffset')) {
    throw UnsupportedError('native_story_fallback_glow_ratios');
  }
  double f(double value) => Float32List.fromList([value])[0];
  double value(String field) => f(
    floats[field] ??
        (throw UnsupportedError('native_story_fallback_float:$field')),
  );
  final gradient = value('_GradientScale');
  final weight = f(math.max(value('_WeightNormal'), value('_WeightBold')) / 4);
  final face = value('_FaceDilate');
  final extent = math.max(
    1.0,
    f(f(f(weight + face) + value('_OutlineWidth')) + value('_OutlineSoftness')),
  );
  floats['_ScaleRatioA'] = f(f(gradient - 1) / f(gradient * extent));
  final range = f(f(weight + face) * f(gradient - 1));
  final underlay = math.max(
    1.0,
    f(
      f(
            math.max(
                  value('_UnderlayOffsetX').abs(),
                  value('_UnderlayOffsetY').abs(),
                ) +
                value('_UnderlayDilate'),
          ) +
          value('_UnderlaySoftness'),
    ),
  );
  floats['_ScaleRatioC'] = f(
    math.max(0.0, f(f(gradient - 1) - range)) / f(gradient * underlay),
  );
  final materialName = '$primaryMaterialName + $fallbackAssetName';
  final material = StorySdfMaterialData.fromRaw(
    {...primaryMaterial, 'floats': floats},
    actualFont: actualFont,
    sourceMaterialKey: '${actualFont.id}:$materialName',
    sourcePath: sourcePath,
    sourceHash: sourceHash,
  );
  if (!material.usable) {
    throw UnsupportedError(
      'native_story_fallback_material:${material.unsupported}',
    );
  }
  return NativeStoryResolvedSdfMaterial(
    material: material,
    materialName: materialName,
    primaryProvenance: primaryProvenance,
    targetProvenance: targetProvenance,
  );
}

StoryGlyphPadding nativeStorySdfGlyphPadding(
  StorySdfMaterialData material,
  StoryFontData font, {
  required bool bold,
  required bool extraPadding,
}) {
  if (!material.usable || material.fontSourceHash != font.sourceHash) {
    throw const FormatException('native_story_sdf_padding_binding');
  }
  final a = material.scaleRatioA;
  final faceDilate = material.faceDilate;
  final outlineWidth = material.requireFloat('_OutlineWidth');
  final outlineSoftness = material.requireFloat('_OutlineSoftness');
  final underlay = material.underlayEnabled
      ? StorySdfUnderlayParameters(
          scaleRatio: material.requireFloat('_ScaleRatioC'),
          offsetX: material.requireFloat('_UnderlayOffsetX'),
          offsetY: material.requireFloat('_UnderlayOffsetY'),
          dilate: material.requireFloat('_UnderlayDilate'),
          softness: material.requireFloat('_UnderlaySoftness'),
        )
      : null;
  final gradient = material.gradientScale;
  final padding = computeStorySdfPadding(
    StorySdfPaddingParameters(
      scaleRatioA: a,
      faceDilate: faceDilate,
      outlineWidth: outlineWidth,
      outlineSoftness: outlineSoftness,
      gradientScale: gradient,
      style: bold ? font.boldWeight : font.normalWeight,
      extraPadding: extraPadding,
      underlay: underlay,
    ),
  );
  return StoryGlyphPadding(padding.materialPadding, padding.stylePadding);
}

/// Independent distance-ramp integration. Source material values describe the
/// glyph boundary, stroke and shadow; one screen pixel spans the normalized
/// alpha distance range divided by twice its authored gradient scale.
Float32List nativeStorySdfUniforms(
  StorySdfMaterialData source, {
  required double glyphScale,
  required double screenScale,
  required bool bold,
}) {
  if (!source.usable ||
      !glyphScale.isFinite ||
      glyphScale <= 0 ||
      !screenScale.isFinite ||
      screenScale <= 0 ||
      source.sharpness <= -1) {
    throw UnsupportedError('native_story_sdf_parameters:${source.unsupported}');
  }
  final weight = bold ? source.weightBold : source.weightNormal;
  final boundary =
      .5 - (weight * .25 + source.faceDilate) * source.scaleRatioA * .5;
  final radius = source.outlineEnabled
      ? source.outlineWidth! * source.scaleRatioA * .5
      : 0.0;
  final softness = source.outlineEnabled
      ? source.outlineSoftness! * source.scaleRatioA * .5
      : 0.0;
  final pixelWidth =
      1 /
      (2 *
          source.gradientScale *
          glyphScale *
          screenScale *
          (1 + source.sharpness));
  final shadowRatio = source.underlayEnabled ? source.scaleRatioC! : 0.0;
  return Float32List.fromList([
    ...source.faceColor,
    ...source.outlineEnabled
        ? source.outlineColor!
        : const [0.0, 0.0, 0.0, 0.0],
    ...source.underlayEnabled
        ? source.underlayColor!
        : const [0.0, 0.0, 0.0, 0.0],
    boundary,
    radius,
    softness,
    pixelWidth,
    source.underlayEnabled
        ? -source.underlayOffsetX! *
              shadowRatio *
              source.gradientScale /
              source.textureWidth
        : 0,
    source.underlayEnabled
        ? source.underlayOffsetY! *
              shadowRatio *
              source.gradientScale /
              source.textureHeight
        : 0,
    boundary -
        (source.underlayEnabled
            ? source.underlayDilate! * shadowRatio * .5
            : 0),
    source.underlayEnabled ? source.underlaySoftness! * shadowRatio * .5 : 0,
    source.outlineEnabled ? 1 : 0,
    source.underlayEnabled ? 1 : 0,
    source.scaleX,
    source.scaleY,
  ]);
}

/// Actual measured glyph rectangles, in the source canvas's top-down units.
/// Projection preserves their original atlas UV rectangle and color.
ProjectedMesh nativeStoryGlyphMesh(
  Iterable<StoryGlyphQuad> glyphs, {
  required double originX,
  required double originY,
  required double canvasWidth,
  required double canvasHeight,
}) {
  final vertices = <double>[], indices = <int>[];
  for (final glyph in glyphs) {
    if (vertices.length ~/ 10 > 65531) {
      throw StateError('native_story_glyph_u16_batch_limit');
    }
    final r = glyph.rect, uv = glyph.uvTopLeft, start = vertices.length ~/ 10;
    for (final point in const [
      (0.0, 0.0),
      (1.0, 0.0),
      (0.0, 1.0),
      (1.0, 1.0),
    ]) {
      vertices.addAll([
        2 * (originX + r[0] + r[2] * point.$1) / canvasWidth - 1,
        1 - 2 * (originY + r[1] + r[3] * point.$2) / canvasHeight,
        0,
        1,
        uv[0] + uv[2] * point.$1,
        uv[1] + uv[3] * point.$2,
        ...glyph.color,
      ]);
    }
    indices.addAll([
      start,
      start + 2,
      start + 1,
      start + 1,
      start + 2,
      start + 3,
    ]);
  }
  return ProjectedMesh(
    Float32List.fromList(vertices),
    Uint16List.fromList(indices),
  );
}
