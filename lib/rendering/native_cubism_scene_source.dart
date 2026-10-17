import 'dart:typed_data';

import 'package:vega_plugin_haneoka/render_profile.dart';

import '../core/api.dart';
import 'native_unity_source_archive.dart';

/// Actual Haneoka source paths and pointer parsing stay in the App adapter.
/// The backend receives only numeric camera/field/stage geometry.
final class NativeCubismSceneSource {
  NativeCubismSceneSource._(
    this.camera,
    this.field,
    this.background,
    this.projection,
    this.cameraClearRgba,
    this.cameraClearSource,
    this.backgroundLocalPosition,
    this.backgroundLocalEuler,
  );
  final NativeUnitySourceArchive camera, field, background;
  final NativeCubismWorldProjection projection;
  final Float32List cameraClearRgba,
      backgroundLocalPosition,
      backgroundLocalEuler;
  final Map<String, Object?> cameraClearSource;

  static Future<NativeCubismSceneSource> load({
    required HaneokaApi api,
    required StorySourceIdentity identity,
    required bool Function() current,
  }) async {
    Future<NativeUnitySourceArchive> common(String path) =>
        NativeUnitySourceArchive.load(
          api: api,
          identity: identity,
          sourcePath: path,
          current: current,
          decodeOffThread: true,
          retain: _retainSceneRecord,
        );
    final [camera, field, background] = await Future.wait([
      common('Assets/AddressableResources/Common/Prefab/CameraManager.prefab'),
      common(
        'Assets/AddressableResources/Common/Adv/Prefab/AdvCharacterField.prefab',
      ),
      common(
        'Assets/AddressableResources/Common/Adv/Prefab/AdvBackgroundField.prefab',
      ),
    ]);
    final manager = camera.requireScript('CameraManager')['data'] as Map;
    final cameraId = _local(manager['_mainCamera']);
    final cameraRow = camera.requireRecord(cameraId, 'Camera');
    final lens = cameraRow['data'] as Map;
    if (lens['orthographic'] != false) {
      throw UnsupportedError('native_cubism_actual_main_orthographic');
    }
    final fieldData = field.requireScript('AdvCharacterField')['data'] as Map;
    final fieldTransform = _transform(field, _local(fieldData['_field']));
    final slots = <Float32List>[];
    for (final pointer in (fieldData['_characterStages'] as List).cast<Map>()) {
      slots.add(_position(_transform(field, _local(pointer))));
    }
    final focusPoints = <Float32List>[
      for (final pointer in (fieldData['_focusAnchors'] as List).cast<Map>())
        _position(_transform(field, _local(pointer))),
    ];
    final projection = NativeCubismWorldProjection(
      near: _number(lens['near clip plane']),
      far: _number(lens['far clip plane']),
      defaultFieldOfView: _number(lens['field of view']),
      sourceSlots: slots,
      sourceFocusPoints: focusPoints,
      sourceFieldPosition: _position(fieldTransform),
    );
    final clear = lens['m_BackGroundColor'] as Map;
    final clearRgba = Float32List.fromList([
      for (final key in ['r', 'g', 'b', 'a']) _number(clear[key]),
    ]);
    final backgroundData =
        background.requireScript('AdvBackgroundField')['data'] as Map;
    final spriteRenderer =
        background.requireRecord(
              _local(backgroundData['_renderer']),
              'SpriteRenderer',
            )['data']
            as Map;
    final game = _local(spriteRenderer['m_GameObject']);
    final transform =
        background.records.singleWhere(
              (row) =>
                  row['type'] == 'Transform' &&
                  _local((row['data'] as Map)['m_GameObject']) == game,
            )['data']
            as Map;
    final q = transform['m_LocalRotation'] as Map;
    if (_number(q['x']) != 0 ||
        _number(q['y']) != 0 ||
        _number(q['z']) != 0 ||
        _number(q['w']) != 1) {
      throw UnsupportedError('native_cubism_background_source_rotation');
    }
    return NativeCubismSceneSource._(
      camera,
      field,
      background,
      projection,
      clearRgba,
      Map.unmodifiable({
        ...camera.proof,
        'cameraRecordId': cameraId,
        'serializedFile': cameraRow['serializedFile'],
        'rgba': clearRgba.toList(),
      }),
      _position(transform),
      Float32List(3),
    );
  }

  Future<NativeCubismStageSource> loadStage({
    required HaneokaApi api,
    required String exactStageRef,
    required bool Function() current,
  }) async {
    if (!RegExp(r'^adv_bkg_stage_[0-9]+$').hasMatch(exactStageRef)) {
      throw const FormatException('native_cubism_stage_reference');
    }
    final source = await NativeUnitySourceArchive.load(
      api: api,
      identity: camera.identity,
      sourcePath:
          'Assets/AddressableResources/Adv/Stage/$exactStageRef/$exactStageRef.prefab',
      current: current,
      decodeOffThread: true,
      retain: _retainStageRecord,
    );
    final stageRow = source.requireScript('AdvStage');
    final data = stageRow['data'] as Map;
    final sourceSprite = source.requireRecord(
      _local(data['_backgroundSprite']),
      'Sprite',
    );
    final points = ((data['_focusPointsCollection'] as Map)['_entries'] as List)
        .cast<Map>();
    final geometry = NativeCubismStageGeometry(
      fieldPosition: _vec(data['_characterFieldPosition'] as Map),
      fieldScale: _number(data['_characterFieldScale']),
      focusSets: [
        for (final set in points)
          [
            for (final p in (set['_focusPointPositions'] as List).cast<Map>())
              _vec(p),
          ],
      ],
      fieldOfView: _number(data['_fov']),
      initialCameraPosition: _vec(data['_initialCameraPosition'] as Map),
      initialCameraEuler: _vec(data['_initialCameraRotation'] as Map),
      backgroundPosition: _vec(data['_backgroundFieldPosition'] as Map),
      backgroundScale: _number(data['_backgroundFieldScale']),
    );
    return NativeCubismStageSource._(
      exactStageRef,
      source,
      geometry,
      sourceSprite,
      Map.unmodifiable({
        ...source.proof,
        'stageRecordId': stageRow['pathId'],
        'stageSerializedFile': stageRow['serializedFile'],
      }),
      data,
      HaneokaStageLighting.fromUnityRecords(
        source.records,
        stageRecord: stageRow,
      ),
    );
  }
}

final class NativeCubismStageSource {
  NativeCubismStageSource._(
    this.ref,
    this.archive,
    this.geometry,
    this.backgroundSprite,
    this.proof,
    this.component,
    this.lighting,
  );
  final String ref;
  final NativeUnitySourceArchive archive;
  final NativeCubismStageGeometry geometry;
  final Map backgroundSprite, component;
  final HaneokaStageLighting lighting;
  final Map<String, Object?> proof;
}

String _local(Object? value) {
  if (value is! Map || value['m_FileID'] != 0 || value['m_PathID'] is! String) {
    throw const FormatException('native_cubism_scene_pointer');
  }
  return value['m_PathID'] as String;
}

Map _transform(NativeUnitySourceArchive source, String id) =>
    source.requireRecord(id, 'Transform')['data'] as Map;
Float32List _position(Map transform) =>
    _vec(transform['m_LocalPosition'] as Map);
Float32List _vec(Map value) => Float32List.fromList([
  for (final key in ['x', 'y', 'z']) _number(value[key]),
]);
double _number(Object? value) {
  if (value is! num || !value.isFinite) {
    throw const FormatException('native_cubism_scene_number');
  }
  return value.toDouble();
}

bool _retainSceneRecord(Map row) => const {
  'GameObject',
  'Transform',
  'Camera',
  'MonoBehaviour',
  'SpriteRenderer',
}.contains(row['type']);

bool _retainStageRecord(Map row) => const {
  'GameObject',
  'Transform',
  'MonoBehaviour',
  'Sprite',
  'Light',
  'RectTransform',
}.contains(row['type']);
