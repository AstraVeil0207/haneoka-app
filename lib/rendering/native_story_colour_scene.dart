import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_playback.dart';

/// Encoded background identity and dimensions; the scene owns its blend.
final class StoryBackgroundImage {
  const StoryBackgroundImage._(
    this.source,
    this.epoch,
    this.uri,
    this.encodedSHA256,
    this.width,
    this.height,
  );
  final RenderSource source;
  final int epoch, width, height;
  final Uri uri;
  final String encodedSHA256;

  void verifyBoundEncodedBytes(Uint8List bytes) {
    if (sha256.convert(bytes).toString() != encodedSHA256) {
      throw StateError('native_story_lower_bound_pixels_changed');
    }
  }

  static Future<StoryBackgroundImage> fromActualEncodedImage({
    required RenderSource source,
    required int epoch,
    required Uri uri,
    required Uint8List bytes,
  }) async {
    if (uri.queryParameters['release'] != source.release) {
      throw StateError('native_story_lower_source_release');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        return StoryBackgroundImage._(
          source,
          epoch,
          uri,
          sha256.convert(bytes).toString(),
          descriptor.width,
          descriptor.height,
        );
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}

/// The existing source snapshot's content pass is consumed directly, without
/// flattening its blend against transparent pixels or copying a layer image.
final class NativeStoryColourLayer {
  const NativeStoryColourLayer({
    required this.sortingOrder,
    required this.contentTarget,
    required this.scene,
    required this.frame,
    required this.textures,
    this.dataTextures = const {},
    this.decodedTextureKeys = const {},
    this.replacesBackground = false,
    this.clearColor,
    this.onPresented,
  });
  final int sortingOrder;
  final String contentTarget;
  final NativeSceneResources scene;
  final NativeFrame frame;
  final Map<String, Uri> textures;
  final Map<String, NativeTextureData> dataTextures;
  final Set<String> decodedTextureKeys;
  final bool replacesBackground;
  final Float32List? clearColor;
  final void Function()? onPresented;
}

final class NativeStoryColourScene {
  const NativeStoryColourScene(
    this.scene,
    this.frame,
    this.textures,
    this.proof, {
    this.dataTextures = const {},
    this.onPresented,
  });
  final NativeSceneResources scene;
  final NativeFrame frame;
  final Map<String, Uri> textures;
  final Map<String, NativeTextureData> dataTextures;
  final Map<String, Object?> proof;
  final void Function()? onPresented;
}

NativeStoryColourScene composeStoryColour({
  required StoryBackgroundImage lower,
  required NativeStoryUpdateStamp actualStamp,
  required int width,
  required int height,
  required List<NativeStoryColourLayer> layers,
  required Float32List backgroundClearColor,
  NativeStoryColourLayer? world,
  (int, int)? worldViewport,
}) {
  if (actualStamp.sourceEpoch != lower.epoch || width <= 0 || height <= 0) {
    throw StateError('native_story_colour_actual_viewport_epoch');
  }
  bool sameSource(RenderSource source) =>
      source.server == lower.source.server &&
      source.release == lower.source.release &&
      source.document == lower.source.document;
  final meshes = <String, ProjectedMesh>{};
  final materials = <String, NativeMaterial>{};
  final lowerKey = 'colour:lower:${lower.encodedSHA256}';
  final textures = <String, Uri>{lowerKey: lower.uri};
  final dataTextures = <String, NativeTextureData>{};
  ProjectedMesh quad(double u0, double v0, double u1, double v1) =>
      ProjectedMesh(
        Float32List.fromList([
          -1,
          -1,
          0,
          1,
          u0,
          v1,
          1,
          1,
          1,
          1,
          -1,
          1,
          0,
          1,
          u0,
          v0,
          1,
          1,
          1,
          1,
          1,
          1,
          0,
          1,
          u1,
          v0,
          1,
          1,
          1,
          1,
          1,
          -1,
          0,
          1,
          u1,
          v1,
          1,
          1,
          1,
          1,
        ]),
        Uint16List.fromList([0, 1, 2, 0, 2, 3]),
      );
  final coverScale = math.max(width / lower.width, height / lower.height);
  final visibleU = width / (lower.width * coverScale);
  final visibleV = height / (lower.height * coverScale);
  meshes['colour:lower'] = quad(
    (1 - visibleU) / 2,
    (1 - visibleV) / 2,
    (1 + visibleU) / 2,
    (1 + visibleV) / 2,
  );
  materials['colour:lower'] = NativeMaterial(
    texture: lowerKey,
    textureAlpha: NativeTextureAlpha.premultiplied,
    blend: NativeBlend.premultipliedAlpha,
  );
  final draws = <NativeDraw>[
    const NativeDraw(mesh: 'colour:lower', material: 'colour:lower'),
  ];
  final worldPasses = <NativePass>[];
  final worldTargets = <String, NativeTarget>{};
  if (world != null) {
    if (worldViewport != null &&
        world.scene.targets[world.contentTarget]?.encoding !=
            NativeColorEncoding.gammaSrgb) {
      throw StateError('spatial_world_requires_postprocessed_gamma');
    }
    dataTextures.addAll(world.dataTextures);
    if (world.replacesBackground) draws.clear();
    if (world.scene.epoch != lower.epoch ||
        world.frame.epoch != lower.epoch ||
        world.frame.mediaMicroseconds != actualStamp.storyUs ||
        !sameSource(world.scene.source)) {
      throw StateError('native_story_world_source_epoch');
    }
    for (final entry in world.scene.meshes.entries) {
      if (meshes.containsKey(entry.key)) {
        throw StateError('native_world_mesh_collision');
      }
      meshes[entry.key] = entry.value;
    }
    materials.addAll(world.scene.materials);
    textures.addAll(world.textures);
    for (final entry in world.scene.targets.entries) {
      if (entry.key != world.contentTarget) {
        worldTargets[entry.key] = entry.value;
      }
    }
    for (final pass in world.frame.passes) {
      if (pass.target == world.contentTarget) {
        draws.addAll(pass.draws);
      } else {
        worldPasses.add(pass);
      }
    }
  }
  if (worldViewport != null) {
    final (worldWidth, worldHeight) = worldViewport;
    if (worldWidth <= 0 ||
        worldHeight <= 0 ||
        worldWidth > width ||
        worldHeight > height) {
      throw ArgumentError('Invalid world viewport');
    }
    // The world camera's post chain is complete here. Clamp its gamma RGB
    // through an opaque RGBA8 transfer before spatial reconstruction.
    meshes['colour:world-transfer'] = quad(0, 0, 1, 1);
    materials['colour:world-tone-transfer'] = const NativeMaterial(
      texture: 'colour:world-hdr',
      textureAlpha: NativeTextureAlpha.independent,
      recipe: NativeMaterialRecipe.opaqueColorTransfer,
      blend: NativeBlend.opaque,
    );
    worldTargets['colour:world-hdr'] = NativeTarget(
      width: worldWidth,
      height: worldHeight,
      format: NativeTargetFormat.rgba16f,
      alpha: NativeTextureAlpha.independent,
    );
    worldTargets['colour:world-input'] = NativeTarget(
      width: worldWidth,
      height: worldHeight,
      alpha: NativeTextureAlpha.independent,
    );
    worldPasses.add(
      NativePass(
        target: 'colour:world-hdr',
        draws: List.of(draws),
        clearColor: world?.clearColor ?? backgroundClearColor,
      ),
    );
    worldPasses.add(
      NativePass(
        target: 'colour:world-input',
        draws: [
          const NativeDraw(
            mesh: 'colour:world-transfer',
            material: 'colour:world-tone-transfer',
          ),
        ],
      ),
    );
    draws.clear();
  }
  var previousOrder = 300;
  for (final layer in layers) {
    if (![301, 302, 303, 304].contains(layer.sortingOrder) ||
        layer.sortingOrder <= previousOrder ||
        layer.scene.epoch != lower.epoch ||
        layer.frame.epoch != lower.epoch ||
        layer.frame.mediaMicroseconds != actualStamp.storyUs ||
        !sameSource(layer.scene.source)) {
      throw StateError('native_story_colour_source_order');
    }
    if (layer.sortingOrder == 301) {
      if (layer.contentTarget != 'video:main' ||
          layer.decodedTextureKeys.length != 1 ||
          !layer.decodedTextureKeys.single.startsWith('video:decoded:')) {
        throw const FormatException('native_colour_video_decoded_contract');
      }
    } else if (layer.decodedTextureKeys.isNotEmpty) {
      throw const FormatException('native_colour_nonvideo_decoded_contract');
    }
    previousOrder = layer.sortingOrder;
    final target = layer.scene.targets[layer.contentTarget];
    if (target == null ||
        target.width != width ||
        target.height != height ||
        target.depth ||
        target.encoding != NativeColorEncoding.gammaSrgb) {
      throw UnsupportedError('native_story_colour_target_contract');
    }
    final content = layer.frame.passes
        .where((pass) => pass.target == layer.contentTarget)
        .toList();
    if (content.length != 1) {
      throw UnsupportedError('native_story_colour_content_pass');
    }
    final prefix = 'colour:${layer.sortingOrder}:';
    final candidates = {
      for (final entry in layer.scene.targets.entries)
        if (entry.key != layer.contentTarget) entry.key: entry.value,
    };
    final internal = <String, NativeTarget>{};
    void requireMask(CoverageMask? value) {
      if (value == null || internal.containsKey(value.texture)) return;
      final target = candidates[value.texture];
      if (target == null) {
        throw const FormatException('native_story_colour_mask_target_missing');
      }
      internal[value.texture] = target;
      final writers = layer.frame.passes
          .where((pass) => pass.target == value.texture)
          .toList();
      if (writers.length != 1) {
        throw const FormatException('native_story_colour_mask_writer');
      }
      for (final draw in writers.single.draws) {
        requireMask(layer.scene.materials[draw.material]!.coverageMask);
      }
    }

    for (final draw in content.single.draws) {
      requireMask(layer.scene.materials[draw.material]?.coverageMask);
    }
    String auxiliaryTexture(String key) {
      if (layer.textures[key] case final uri?) {
        textures['$prefix$key'] = uri;
      } else if (layer.dataTextures[key] case final data?) {
        dataTextures['$prefix$key'] = data;
      } else if (!internal.containsKey(key)) {
        throw StateError('native_story_colour_mask_texture:$key');
      }
      return '$prefix$key';
    }

    CoverageMask? mask(CoverageMask? value) => value == null
        ? null
        : CoverageMask(
            texture: auxiliaryTexture(value.texture),
            clipToMaskUv: value.clipToMaskUv,
            mode: value.mode,
            threshold: value.threshold,
          );
    for (final entry in internal.entries) {
      if (entry.value.depth ||
          entry.value.width != width ||
          entry.value.height != height) {
        throw const FormatException('native_story_colour_mask_target');
      }
      worldTargets['$prefix${entry.key}'] = entry.value;
    }
    for (final pass in layer.frame.passes.where(
      (pass) => internal.containsKey(pass.target),
    )) {
      if (!internal.containsKey(pass.target)) {
        throw const FormatException('native_story_colour_mask_pass');
      }
      final auxiliary = <NativeDraw>[];
      for (final draw in pass.draws) {
        final material = layer.scene.materials[draw.material]!;
        final mesh = layer.scene.meshes[draw.mesh]!;
        if (material.recipe != NativeMaterialRecipe.coverageMask ||
            material.blend != NativeBlend.opaque ||
            material.depthTest ||
            material.depthWrite ||
            material.additionalTextures.isNotEmpty ||
            mesh.layout != NativeMeshLayout.sprite10) {
          throw const FormatException('native_story_colour_mask_recipe');
        }
        meshes['$prefix${draw.mesh}'] = mesh;
        materials['$prefix${draw.material}'] = NativeMaterial(
          texture: auxiliaryTexture(material.texture),
          recipe: material.recipe,
          coverageChannel: material.coverageChannel,
          blend: material.blend,
          textureAlpha: material.textureAlpha,
          uniformFloats: material.uniformFloats,
          coverageMask: mask(material.coverageMask),
          minFilter: material.minFilter,
          magFilter: material.magFilter,
        );
        auxiliary.add(
          NativeDraw(
            mesh: '$prefix${draw.mesh}',
            material: '$prefix${draw.material}',
          ),
        );
      }
      worldPasses.add(
        NativePass(
          target: '$prefix${pass.target}',
          draws: auxiliary,
          clear: pass.clear,
          clearColor: pass.clearColor,
        ),
      );
    }

    for (final draw in content.single.draws) {
      final material = layer.scene.materials[draw.material];
      final mesh = layer.scene.meshes[draw.mesh];
      if (material == null ||
          mesh == null ||
          material.depthTest ||
          material.depthWrite ||
          layer.scene.targets.containsKey(material.texture) ||
          material.additionalTextures.values.any(
            layer.scene.targets.containsKey,
          )) {
        throw UnsupportedError('native_story_colour_depth_or_internal_input');
      }
      final normal =
          material.blend == NativeBlend.premultipliedAlpha &&
          const {
            NativeMaterialRecipe.textured,
            NativeMaterialRecipe.solidColor,
            NativeMaterialRecipe.sdfText,
            NativeMaterialRecipe.ruleTransition,
          }.contains(material.recipe);
      final additive =
          material.blend == NativeBlend.sourceAlphaAdditive &&
          const {
            NativeMaterialRecipe.uiSourceAlphaAdditive,
            NativeMaterialRecipe.mobileHdr,
          }.contains(material.recipe);
      final sourceAlpha =
          material.blend == NativeBlend.sourceAlpha &&
          material.recipe == NativeMaterialRecipe.sourceAlphaTexture;
      if ((!normal && !additive && !sourceAlpha) ||
          mesh.layout != NativeMeshLayout.sprite10) {
        throw UnsupportedError('native_story_colour_source_alpha_recipe');
      }
      // These admitted recipes sample actual image alpha in [0,1]. Keep the
      // source vertex values; refuse out-of-domain alpha rather than clamp it.
      for (var alpha = 9; alpha < mesh.vertices.length; alpha += 10) {
        final value = mesh.vertices[alpha];
        if (!value.isFinite || value < 0 || value > 1) {
          throw UnsupportedError(
            'native_story_colour_source_vertex_alpha:${layer.sortingOrder}:${draw.mesh}:$value',
          );
        }
      }
      if (material.recipe == NativeMaterialRecipe.sdfText) {
        final settings = material.uniformFloats;
        if (settings == null ||
            settings.length != 24 ||
            settings.any((v) => !v.isFinite) ||
            [
              3,
              7,
              11,
            ].any((index) => settings[index] < 0 || settings[index] > 1)) {
          throw UnsupportedError('native_story_colour_source_sdf_alpha');
        }
      }
      if (material.recipe == NativeMaterialRecipe.ruleTransition) {
        final settings = material.uniformFloats;
        if (settings == null ||
            settings.length != 4 ||
            settings.any((v) => !v.isFinite) ||
            (settings[1] != 0 && settings[1] != 1)) {
          throw UnsupportedError('native_story_colour_rule_uniforms');
        }
      }
      String texture(String key) {
        if (layer.textures[key] case final uri?) {
          textures['$prefix$key'] = uri;
        } else if (layer.dataTextures[key] case final data?) {
          dataTextures['$prefix$key'] = data;
        } else if (layer.sortingOrder == 301 &&
            layer.decodedTextureKeys.contains(key)) {
          // The official same-context decoded image was installed by the host.
        } else if (material.recipe != NativeMaterialRecipe.solidColor) {
          throw StateError('native_story_colour_actual_texture:$key');
        }
        return '$prefix$key';
      }

      meshes['$prefix${draw.mesh}'] = mesh;
      materials['$prefix${draw.material}'] = NativeMaterial(
        texture: texture(material.texture),
        recipe: material.recipe,
        coverageChannel: material.coverageChannel,
        blend: material.blend,
        textureAlpha: material.textureAlpha,
        depthTest: material.depthTest,
        depthWrite: material.depthWrite,
        uniformFloats: material.uniformFloats,
        cull: material.cull,
        widthAddressMode: material.widthAddressMode,
        heightAddressMode: material.heightAddressMode,
        additionalTextures: {
          for (final entry in material.additionalTextures.entries)
            entry.key: texture(entry.value),
        },
        minFilter: material.minFilter,
        magFilter: material.magFilter,
        coverageMask: mask(material.coverageMask),
      );
      draws.add(
        NativeDraw(
          mesh: '$prefix${draw.mesh}',
          material: '$prefix${draw.material}',
        ),
      );
    }
  }
  meshes['colour:transfer'] = quad(0, 0, 1, 1);
  materials['colour:transfer'] = const NativeMaterial(
    texture: 'colour:main',
    textureAlpha: NativeTextureAlpha.independent,
    recipe: NativeMaterialRecipe.opaqueColorTransfer,
    blend: NativeBlend.opaque,
  );
  return NativeStoryColourScene(
    NativeSceneResources(
      epoch: lower.epoch,
      source: lower.source,
      meshes: meshes,
      materials: materials,
      targets: {
        ...worldTargets,
        'colour:main': NativeTarget(
          width: width,
          height: height,
          format: NativeTargetFormat.rgba16f,
          alpha: NativeTextureAlpha.independent,
        ),
        'colour:output': NativeTarget(
          width: width,
          height: height,
          presentable: true,
        ),
      },
    ),
    NativeFrame(
      epoch: lower.epoch,
      mediaMicroseconds: actualStamp.storyUs,
      outputTarget: 'colour:output',
      passes: [
        ...worldPasses,
        NativePass(
          target: 'colour:main',
          clear: worldViewport == null,
          draws: draws,
          clearColor: world?.clearColor ?? backgroundClearColor,
        ),
        NativePass(
          target: 'colour:output',
          draws: [
            const NativeDraw(
              mesh: 'colour:transfer',
              material: 'colour:transfer',
            ),
          ],
        ),
      ],
    ),
    textures,
    {
      'backgroundEncodedSHA256': lower.encodedSHA256,
      'backgroundPixels': [lower.width, lower.height],
      'actualPixelViewport': [width, height],
      if (worldViewport != null)
        'spatialWorldInput': [worldViewport.$1, worldViewport.$2],
      'coverUV': [
        (1 - visibleU) / 2,
        (1 - visibleV) / 2,
        (1 + visibleU) / 2,
        (1 + visibleV) / 2,
      ],
      'sortingOrders': layers.map((l) => l.sortingOrder).toList(),
      'actualUpdateIndex': actualStamp.updateIndex,
      'actualStoryUs': actualStamp.storyUs,
      'workingAlpha':
          'independent source blending; RGB acts against actuallower',
      'outputAlpha': 'opaque source camera clear permits alpha1 RGB transfer',
    },
    dataTextures: dataTextures,
    onPresented: () {
      world?.onPresented?.call();
      for (final layer in layers) {
        layer.onPresented?.call();
      }
    },
  );
}
