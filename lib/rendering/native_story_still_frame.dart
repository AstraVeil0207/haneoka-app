import 'dart:typed_data';

import 'package:vega_plugin_haneoka/render_profile.dart';

final class NativeStoryStillCanvasInstance {
  const NativeStoryStillCanvasInstance({
    required this.reference,
    required this.presentation,
    required this.currentLayout,
    required this.rootAlpha,
    this.attachment,
  });
  final String reference;
  final Map<String, Object?> presentation, currentLayout;
  final double rootAlpha;
  final StoryStillAttachmentSnapshot? attachment;
}

final class NativeStoryStillCanvasFrame {
  const NativeStoryStillCanvasFrame(
    this.scene,
    this.frame,
    this.textures,
    this.unsupported,
    this.imageGeometry,
  );
  final NativeSceneResources scene;
  final NativeFrame frame;
  final Map<String, Uri> textures;
  final List<String> unsupported;
  final Map<String, Object?> imageGeometry;
}

/// Authored still sibling order is kept across commands. The background sits
/// behind every still and the overlay sits in front; root CanvasGroup alpha
/// modulates each descendant once after its own authored opacity calculation.
NativeStoryStillCanvasFrame buildNativeStoryStillCanvas({
  required List<NativeStoryStillCanvasInstance> instances,
  required double backgroundAlpha,
  required double overlayAlpha,
  required RenderSource source,
  required int epoch,
  required int actualStoryUs,
  required int width,
  required int height,
  required Uri Function(String) resolveTexture,
  required Map<String, (int, int)> textureSizes,
  StoryStillExternalLayout? externalLayout,
  bool captureGeometryProof = false,
  List<double> offset = const [0, 0, 0],
}) {
  final meshes = <String, ProjectedMesh>{},
      materials = <String, NativeMaterial>{},
      textures = <String, Uri>{},
      draws = <NativeDraw>[],
      unsupported = <String>[];
  final imageGeometry = <String, Object?>{};
  ProjectedMesh fullScreen(double alpha) => ProjectedMesh(
    Float32List.fromList([
      -1,
      -1,
      0,
      1,
      0,
      1,
      0,
      0,
      0,
      alpha,
      1,
      -1,
      0,
      1,
      1,
      1,
      0,
      0,
      0,
      alpha,
      -1,
      1,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      alpha,
      1,
      1,
      0,
      1,
      1,
      0,
      0,
      0,
      0,
      alpha,
    ]),
    Uint16List.fromList([0, 1, 2, 2, 1, 3]),
  );
  void black(String key, double alpha) {
    if (!alpha.isFinite || alpha < 0 || alpha > 1) {
      throw FormatException('native_story_still_alpha:$key');
    }
    if (alpha == 0) return;
    meshes[key] = fullScreen(alpha);
    materials[key] = const NativeMaterial(
      texture: 'native-solid-white',
      recipe: NativeMaterialRecipe.solidColor,
    );
    draws.add(NativeDraw(mesh: key, material: key));
  }

  black('story-still-background', backgroundAlpha);
  for (var i = 0; i < instances.length; i++) {
    final instance = instances[i];
    Map? authoredRoot, currentRoot;
    if (captureGeometryProof) {
      final rootOriginal =
          (instance.presentation['layout'] as Map)['nodes'] as List;
      final rootCurrent = instance.currentLayout['nodes'] as List;
      authoredRoot = rootOriginal.cast<Map>().singleWhere(
        (n) => n['parent'] == null,
      );
      currentRoot = rootCurrent.cast<Map>().singleWhere(
        (n) => n['parent'] == null,
      );
    }
    if (!instance.rootAlpha.isFinite ||
        instance.rootAlpha < 0 ||
        instance.rootAlpha > 1) {
      throw FormatException(
        'native_story_still_root_alpha:${instance.reference}',
      );
    }
    if (instance.rootAlpha == 0) continue;
    final snapshot = buildStillSnapshot(
      {...instance.presentation, 'layout': instance.currentLayout},
      source: source,
      epoch: epoch,
      width: width,
      height: height,
      resolveTexture: resolveTexture,
      textureSizes: textureSizes,
      textureAlpha: NativeTextureAlpha.premultiplied,
      captureGeometryProof: captureGeometryProof,
      externalLayout: externalLayout,
    );
    final prefix = 'story-still:$i:${instance.reference}:';
    for (final entry in snapshot.scene.meshes.entries) {
      final vertices = Float32List.fromList(entry.value.vertices);
      final parent = externalLayout?.targetParent.affine;
      final dx = parent == null
          ? offset[0]
          : parent[0] * offset[0] + parent[2] * offset[1];
      final dy = parent == null
          ? offset[1]
          : parent[1] * offset[0] + parent[3] * offset[1];
      final sx = 2 * dx / (externalLayout?.logicalWidth ?? width);
      final sy = 2 * dy / (externalLayout?.logicalHeight ?? height);
      for (var v = 0; v < vertices.length; v += entry.value.strideFloats) {
        vertices[v] += sx * vertices[v + 3];
        vertices[v + 1] += sy * vertices[v + 3];
        vertices[v + 9] *= instance.rootAlpha;
      }
      meshes['$prefix${entry.key}'] = ProjectedMesh(
        vertices,
        entry.value.indices,
        layout: entry.value.layout,
      );
    }
    for (final entry in snapshot.scene.materials.entries) {
      materials['$prefix${entry.key}'] = entry.value;
    }
    for (final entry in snapshot.textures.entries) {
      if (textures.containsKey(entry.key) &&
          textures[entry.key] != entry.value) {
        throw StateError('native_story_still_texture_identity:${entry.key}');
      }
      textures[entry.key] = entry.value;
    }
    for (final pass in snapshot.frame.passes) {
      for (final draw in pass.draws) {
        draws.add(
          NativeDraw(
            mesh: '$prefix${draw.mesh}',
            material: '$prefix${draw.material}',
          ),
        );
      }
    }
    if (captureGeometryProof) {
      for (final entry in snapshot.imageGeometry.entries) {
        imageGeometry['$prefix${entry.key}'] = {
          ...(entry.value as Map).cast<String, Object?>(),
          'stillRef': instance.reference,
          'rootAlpha': instance.rootAlpha,
          'shakeOffset': offset,
          'attachment': {
            'revision': instance.attachment?.revision,
            'consumedRevision': instance.attachment?.consumedRevision,
            'pending': instance.attachment?.pending,
            'parentId': instance.attachment?.parentId,
            'recordsSHA256': instance.attachment?.packetHash,
            'drivenAnchoredXY': instance.attachment?.drivenAnchored,
            'rootId': currentRoot!['id'],
            'rootTransformKind': currentRoot['transformKind'],
            'rootAuthoredPositionXY': authoredRoot!['position'],
            'rootCurrentPositionXY': currentRoot['position'],
            'rootCurrentLocalZ': currentRoot['positionZ'],
            'rootAuthoredAnchors': [
              authoredRoot['anchorMin'],
              authoredRoot['anchorMax'],
            ],
            'rootAuthoredPivot': authoredRoot['pivot'],
          },
        };
      }
    }
    unsupported.addAll(snapshot.unsupportedFeatures);
  }
  black('story-still-overlay', overlayAlpha);
  final copy = Float32List.fromList(fullScreen(1).vertices);
  for (var v = 6; v < copy.length; v += 10) {
    copy[v] = copy[v + 1] = copy[v + 2] = 1;
  }
  meshes['story-still-output-copy'] = ProjectedMesh(
    copy,
    Uint16List.fromList([0, 1, 2, 2, 1, 3]),
  );
  materials['story-still-output-copy'] = const NativeMaterial(
    texture: 'story-still-main',
    textureAlpha: NativeTextureAlpha.premultiplied,
    blend: NativeBlend.opaque,
  );
  final scene = NativeSceneResources(
    epoch: epoch,
    source: source,
    meshes: meshes,
    materials: materials,
    targets: {
      'story-still-main': NativeTarget(
        width: width,
        height: height,
        format: NativeTargetFormat.rgba16f,
      ),
      'story-still-output': NativeTarget(
        width: width,
        height: height,
        presentable: true,
      ),
    },
  );
  return NativeStoryStillCanvasFrame(
    scene,
    NativeFrame(
      epoch: epoch,
      mediaMicroseconds: actualStoryUs,
      outputTarget: 'story-still-output',
      passes: [
        NativePass(target: 'story-still-main', draws: draws),
        NativePass(
          target: 'story-still-output',
          draws: [
            const NativeDraw(
              mesh: 'story-still-output-copy',
              material: 'story-still-output-copy',
            ),
          ],
        ),
      ],
    ),
    textures,
    unsupported,
    Map.unmodifiable(imageGeometry),
  );
}
