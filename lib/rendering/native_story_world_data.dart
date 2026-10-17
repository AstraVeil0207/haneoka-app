part of 'native_story_world.dart';

extension NativeStoryWorldPortable on NativeStoryWorld {
  Map<String, Object?> snapshotData() {
    if (_scene == null || _postVolume == null || _pendingResources.isNotEmpty) {
      throw StateError('story_world_data_unsettled');
    }
    Map<String, Object?> tween(_WorldTween value) => {
      'startUs': value.startUs,
      'durationUs': value.durationUs,
      'from': value.from,
      'to': value.to,
      'ease': value.ease,
      'executionId': value.executionId,
      'commandIndex': value.commandIndex,
      'waitForCompletion': value.waitForCompletion,
      if (value.descriptor != null) 'movement': value.descriptor,
    };
    final projection = _scene!.projection;
    final motions = _motionQueue.snapshot();
    final registeredActors = _assets.values
        .expand((values) => values.values)
        .toSet();
    final savedActors = {
      for (final motion in motions)
        if (!registeredActors.contains(motion.controller)) motion.controller,
      ...registeredActors,
    };
    return {
      'version': 1,
      'source': storySourceData(document.chapter.sourceIdentity),
      'runtimeHash': document.runtimeHash,
      'stage': _stage?.ref,
      'stageProof': _stage?.proof,
      'lightEnvironment': _lightEnvironment,
      'projection': {
        'vectors': [
          for (final value in _ProjectionCheckpoint._vectors(projection))
            value.toList(),
        ],
        'scalars': [
          projection.fieldOfView,
          projection.zoomRatio,
          projection.slotScale,
          projection.backgroundScale,
        ],
      },
      'actors': [
        for (final actor in savedActors)
          {
            'name': actor.name,
            'key': actor.key,
            'assetIndex': actor.assetIndex,
            'fingerprint': actor.sourceFingerprint,
            'textures': {
              for (final e in actor.textures.entries) '${e.key}': e.value.path,
            },
            'model': actor.model.snapshotData(),
            'state': [
              actor.slot,
              actor.fadeStart,
              actor.fadeDuration,
              actor.lastUs,
              actor.opacity,
              actor.from,
              actor.to,
              actor.brightness,
              actor.sortingDepth,
              actor.headAngle,
              actor.bodyAngle,
              actor.lookEnabled,
              actor.lookIntent,
              actor.lookX,
              actor.lookY,
              actor.originalLookX,
              actor.originalLookY,
              actor.lookStopPending,
            ],
          },
      ],
      'motionWaits': [
        for (final entry in motions)
          {
            'target': entry.target,
            'name': entry.controller.name,
            'key': entry.controller.key,
            'assetIndex': entry.controller.assetIndex,
            'fingerprint': entry.controller.sourceFingerprint,
            'remainingSeconds': entry.remainingSeconds,
            'commandIndex': entry.request.commandIndex,
            'motion': entry.request.motionName,
            'expression': entry.request.expressionName,
            'fade': entry.request.fade,
            'waitSeconds': entry.request.waitSeconds,
          },
      ],
      'selectedActors': {
        for (final entry in _actors.entries) entry.key: entry.value.assetIndex,
      },
      'placements': _characterPresentation.placements.snapshotData(),
      'characterControls': _characterPresentation.controls.snapshot(),
      'order': _characterPresentation.order.slots,
      'post': _postVolume!.snapshotData(),
      'weights': Map<String, double>.of(_postWeights),
      'enabled': Map<String, bool>.of(_postEnabled),
      'focusCamera': _focusCamera.toList(),
      'baseCamera': _baseCamera?.toList(),
      'panOffset': _panOffset.toList(),
      'values': [
        _focusZoom,
        _focusDistance,
        _curvedLensRate,
        _postEnvironment,
        _backgroundBrightness,
        _backgroundBlur,
        _blurRadiusMax,
        _backgroundBlurGeneration,
      ],
      'blur': _characterBlur.values,
      'blurGenerations': {
        for (final entry in _blurGenerations.entries)
          '${entry.key}': entry.value,
      },
      'cameraTweens': {
        for (final entry in _cameraTweens.entries)
          entry.key: tween(entry.value),
      },
      'movements': [for (final value in _movementTweens) tween(value)],
      'shakes': [
        _backgroundShake.snapshotData(),
        _characterShake.snapshotData(),
        _stillShake.snapshotData(),
        _talkShake.snapshotData(),
        _cameraShake.snapshotData(),
      ],
      'shakeWaits': [
        for (final wait in _shakeWaits)
          [
            wait.untilUs,
            wait.untilIdle,
            wait.executionId,
            wait.commandIndex,
            wait.waitForCompletion,
          ],
      ],
      'sceneUs': _sceneUs,
      'shakeUs': _shakeUs,
      'shakeGeneration': _shakeGeneration,
      'randomValues': List<double>.of(_randomValues),
      'randomPosition': _randomPosition,
    };
  }

  Future<void> restoreData(
    Map data, {
    required NativeStoryUpdateStamp stamp,
  }) async {
    requireStorySourceData(
      data['source'] as Map,
      document.chapter.sourceIdentity,
    );
    if (data['version'] != 1 ||
        data['runtimeHash'] != document.runtimeHash ||
        stamp.sourceEpoch != epoch) {
      throw const FormatException('story_world_data_source');
    }
    await prepare();
    await quiesce();
    _cameraTweens.clear();
    _movementTweens.clear();
    _shakeWaits.clear();
    _motionQueue.clear();
    for (final actor in _ownedActors) {
      actor.model.show(false);
    }
    _assets.clear();
    _actors.clear();
    _sceneUs = (data['sceneUs'] as num).toDouble();
    _lastStamp = stamp;
    final stage = data['stage'] as String?;
    if (stage != null) {
      await _selectStage(stage);
      if (jsonEncode(_stage!.proof) != jsonEncode(data['stageProof'])) {
        throw const FormatException('story_world_data_stage_hash');
      }
    } else {
      _stage = null;
      _background = null;
    }
    _lightEnvironment = data['lightEnvironment'] as int? ?? 0;
    for (final raw in data['actors'] as List) {
      final actorData = raw as Map;
      final name = actorData['name'] as String,
          key = actorData['key'] as String;
      final index = actorData['assetIndex'] as int;
      await _loadRegistered(name, key, index);
      final actor = _assets[name]![index]!;
      if (actor.sourceFingerprint != actorData['fingerprint']) {
        throw const FormatException('story_world_data_model_hash');
      }
      final textures = actorData['textures'] as Map;
      if (textures.length != actor.textures.length ||
          !actor.textures.entries.every(
            (e) => textures['${e.key}'] == e.value.path,
          )) {
        throw const FormatException('story_world_data_texture_binding');
      }
      actor.model.restoreData(actorData['model'] as Map);
      final values = actorData['state'] as List;
      double n(int i) => (values[i] as num).toDouble();
      actor.slot = values[0] as int;
      actor.fadeStart = values[1] as int;
      actor.fadeDuration = values[2] as int;
      actor.lastUs = values[3] as int?;
      actor.opacity = n(4);
      actor.from = n(5);
      actor.to = n(6);
      actor.brightness = n(7);
      actor.sortingDepth = n(8);
      actor.headAngle = n(9);
      actor.bodyAngle = n(10);
      actor.lookEnabled = values[11] as bool;
      actor.lookIntent = values[12] as int;
      actor.lookX = n(13);
      actor.lookY = n(14);
      actor.originalLookX = n(15);
      actor.originalLookY = n(16);
      actor.lookStopPending = values[17] as bool;
    }
    _actors
      ..clear()
      ..addAll({
        for (final entry in (data['selectedActors'] as Map).entries)
          entry.key as String: _assets[entry.key]![entry.value as int]!,
      });
    _motionQueue.restore([
      for (final raw in data['motionWaits'] as List? ?? const [])
        _restoreMotionWait(raw as Map),
    ]);
    Float32List vector(Object? raw) => Float32List.fromList([
      for (final v in raw as List) (v as num).toDouble(),
    ]);
    final projection = _scene!.projection,
        savedProjection = data['projection'] as Map;
    final destinations = _ProjectionCheckpoint._vectors(projection),
        vectors = savedProjection['vectors'] as List;
    if (vectors.length != destinations.length) {
      throw const FormatException('story_world_data_projection');
    }
    for (var i = 0; i < vectors.length; i++) {
      destinations[i].setAll(0, vector(vectors[i]));
    }
    final scalars = savedProjection['scalars'] as List;
    projection.fieldOfView = (scalars[0] as num).toDouble();
    projection.zoomRatio = (scalars[1] as num).toDouble();
    projection.slotScale = (scalars[2] as num).toDouble();
    projection.backgroundScale = (scalars[3] as num).toDouble();
    _characterPresentation.placements.restoreData(data['placements'] as Map);
    _characterPresentation.controls.restore(
      (data['characterControls'] as List? ?? const []).cast<String>(),
    );
    _characterPresentation.order.restore((data['order'] as List).cast<int>());
    _postVolume!.restoreData(data['post'] as Map);
    _postWeights
      ..clear()
      ..addAll({
        for (final entry in (data['weights'] as Map).entries)
          entry.key as String: (entry.value as num).toDouble(),
      });
    _postEnabled
      ..clear()
      ..addAll(Map<String, bool>.from(data['enabled'] as Map));
    _focusCamera.setAll(0, vector(data['focusCamera']));
    _baseCamera = data['baseCamera'] == null
        ? null
        : vector(data['baseCamera']);
    _panOffset.setAll(0, vector(data['panOffset']));
    final values = data['values'] as List;
    _focusZoom = (values[0] as num).toDouble();
    _focusDistance = values[1] as int;
    _curvedLensRate = (values[2] as num).toDouble();
    _postEnvironment = values[3] as int;
    _backgroundBrightness = (values[4] as num).toDouble();
    _backgroundBlur = (values[5] as num).toDouble();
    _blurRadiusMax = (values[6] as num).toDouble();
    _backgroundBlurGeneration = values[7] as int;
    final blur = data['blur'] as List;
    for (var i = 0; i < blur.length; i++) {
      _characterBlur.write(i, (blur[i] as num).toDouble());
    }
    _blurGenerations
      ..clear()
      ..addAll({
        for (final entry in (data['blurGenerations'] as Map).entries)
          int.parse(entry.key as String): entry.value as int,
      });
    _randomValues
      ..clear()
      ..addAll(
        (data['randomValues'] as List).map((v) => (v as num).toDouble()),
      );
    _randomPosition = data['randomPosition'] as int;
    final shakes = data['shakes'] as List;
    _backgroundShake.restoreData(shakes[0] as Map);
    _characterShake.restoreData(shakes[1] as Map);
    _stillShake.restoreData(shakes[2] as Map);
    _talkShake.restoreData(shakes[3] as Map);
    _cameraShake.restoreData(shakes[4] as Map, randomUnit: _randomUnit);
    _shakeUs = data['shakeUs'] as int;
    _shakeGeneration = data['shakeGeneration'] as int;
    _shakeWaits.addAll([
      for (final raw in data['shakeWaits'] as List)
        _WorldShakeWait(
          untilUs: (raw as List)[0] as int,
          untilIdle: raw[1] as bool,
          executionId: raw.length > 2 ? raw[2] as int? : null,
          commandIndex: raw.length > 3 ? raw[3] as int? : null,
          waitForCompletion: raw.length > 4 ? raw[4] as bool? : null,
        ),
    ]);
    _cameraTweens.addAll({
      for (final entry in (data['cameraTweens'] as Map).entries)
        entry.key as String: _tweenFromData(
          entry.value as Map,
          _writer(entry.key as String),
        ),
    });
    for (final raw in data['movements'] as List) {
      final value = raw as Map, movement = value['movement'] as Map;
      final slot = projection.slots[movement['slot'] as int];
      final from = vector(movement['from']), to = vector(movement['to']);
      _movementTweens.add(
        _tweenFromData(value, (progress) {
          for (var i = 0; i < 3; i++) {
            slot[i] = from[i] + (to[i] - from[i]) * progress;
          }
          if (movement['sortDepth'] == true) {
            _sortCharacterDepths(resetPriority: true);
          }
        }),
      );
    }
    _syncShakeOffsets();
    await settleResources();
  }

  _WorldTween _tweenFromData(Map value, void Function(double) write) =>
      _WorldTween(
        value['startUs'] as int,
        value['durationUs'] as int,
        (value['from'] as num).toDouble(),
        (value['to'] as num).toDouble(),
        value['ease'] as int,
        write,
        executionId: value['executionId'] as int?,
        commandIndex: value['commandIndex'] as int?,
        waitForCompletion: value['waitForCompletion'] as bool?,
        descriptor: value['movement'] == null
            ? null
            : Map<String, Object?>.from(value['movement'] as Map),
      );

  void Function(double) _writer(String key) {
    final projection = _scene!.projection;
    if (key.startsWith('position:')) {
      return (v) =>
          projection.cameraPosition[int.parse(key.split(':').last)] = v;
    }
    if (key.startsWith('slotYaw:')) {
      return (v) => projection.slotEuler[int.parse(key.split(':').last)][1] = v;
    }
    if (key == 'yaw') return (v) => projection.cameraEuler[1] = v;
    if (key == 'pitch') return (v) => projection.cameraEuler[0] = v;
    if (key == 'roll') return (v) => projection.cameraEuler[2] = v;
    if (key == 'fieldYaw') {
      return (v) =>
          projection.fieldEuler[1] = projection.backgroundEuler[1] = v;
    }
    if (key == 'zoom') return (v) => projection.zoomRatio = v;
    if (key == 'curvedLensRate') return (v) => _curvedLensRate = v;
    if (key == 'blurRadius') return (v) => _blurRadiusMax = v;
    if (key == 'blur:background') return (v) => _backgroundBlur = v;
    if (key.startsWith('blur:slot:')) {
      return (v) => _characterBlur.write(int.parse(key.split(':').last), v);
    }
    if (key == 'brightness:background') return (v) => _backgroundBrightness = v;
    if (key.startsWith('brightness:')) {
      return (v) => _actors[key.substring(11)]!.brightness = v;
    }
    if (key.startsWith('post:')) {
      return (v) {
        final ref = key.substring(5);
        _postWeights[ref] = v;
        _postVolume!.setWeight(ref, v);
      };
    }
    final parts = key.split(':'), actor = _actors[parts[1]]!;
    if (parts[0] == 'angle' || parts[0] == 'bodyAngle') {
      return (v) {
        if (parts[0] == 'angle') {
          actor.headAngle = v;
        } else {
          actor.bodyAngle = v;
        }
        actor.model.setAngleOffsets(actor.headAngle, actor.bodyAngle);
      };
    }
    if (parts[0] == 'look') {
      return (v) {
        if (parts[2] == 'x') {
          actor.lookX = v;
        } else {
          actor.lookY = v;
        }
        actor.model.setEyeLook(actor.lookX, actor.lookY);
      };
    }
    throw FormatException('story_world_data_tween:$key');
  }

  StoryCharacterMotionEntry<_WorldActor> _restoreMotionWait(Map data) {
    final actor =
        _actorResources[(
              data['name'] as String,
              data['assetIndex'] as int,
              data['key'] as String,
            )]
            ?.actor;
    if (actor == null || actor.sourceFingerprint != data['fingerprint']) {
      throw const FormatException('story_world_data_motion_controller');
    }
    return StoryCharacterMotionEntry(
      target: data['target'] as String,
      controller: actor,
      request: StoryCharacterMotionRequest(
        commandIndex: data['commandIndex'] as int,
        motionName: data['motion'] as String,
        expressionName: data['expression'] as String,
        fade: (data['fade'] as num).toDouble(),
        waitSeconds: (data['waitSeconds'] as num).toDouble(),
      ),
      remainingSeconds: (data['remainingSeconds'] as num).toDouble(),
    );
  }
}
