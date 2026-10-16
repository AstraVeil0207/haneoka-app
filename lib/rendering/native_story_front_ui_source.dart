import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_ui_layout_source.dart';

Object? _freezeFront(Object? value) => switch (value) {
  Map value => Map<String, Object?>.unmodifiable({
    for (final entry in value.entries)
      entry.key as String: _freezeFront(entry.value),
  }),
  List value => List<Object?>.unmodifiable(value.map(_freezeFront)),
  _ => value,
};

/// Source-specific identities are validated once before the Front UI is drawn.
/// Controllers refer to their exact original objects, independent of names.
final class NativeStoryFrontUiSource {
  NativeStoryFrontUiSource._(
    this.hash,
    this.records,
    this.paths,
    this.domains,
    this.widgetId, [
    this.nextBindingHash,
    this.spritePacket,
    this.locationAnimation,
  ]);
  final String hash, widgetId;
  final String? nextBindingHash;
  final Map<String, Object?>? spritePacket;
  final NativeAuthoredAnimationClip? locationAnimation;
  final Map<String, Map<String, Object?>> records;
  final Map<String, String> paths;
  final Map<String, Map<String, Object?>> domains;

  factory NativeStoryFrontUiSource.fromPacket({
    required Map<String, Object?> packet,
    required String hash,
    required StorySourceIdentity source,
  }) {
    if (hash !=
            '8a3260693d03dbee2b68a498a00b87ed61aee3ee770b4c3f9622327d0346a5eb' ||
        packet['schema'] != 'haneoka-native-front-ui-bindings-v1' ||
        source.server != 'intl' ||
        source.sourceId != packet['sourceId'] ||
        packet['sourceHash'] !=
            '4876cec383e7aab291fcb8a2ebf40a0b5a288a38ad8ee731f488db910fbf3acc') {
      throw const FormatException('native_story_front_source');
    }
    final frozen = _freezeFront(packet) as Map<String, Object?>;
    final records = <String, Map<String, Object?>>{};
    for (final raw in frozen['records'] as List) {
      final row = raw as Map<String, Object?>;
      final id = row['pathId'];
      if (id is! String ||
          row['serializedFile'] != frozen['serializedFile'] ||
          records.containsKey(id)) {
        throw const FormatException('native_story_front_record');
      }
      records[id] = row;
    }
    String id(Object? value) {
      final pointer = value as Map;
      if (pointer['m_FileID'] != 0 || pointer['m_PathID'] is! String) {
        throw const FormatException('native_story_front_local_pointer');
      }
      return pointer['m_PathID'] as String;
    }

    final paths = Map<String, String>.from(frozen['paths'] as Map);
    for (final entry in paths.entries) {
      final transform = records[entry.key]!;
      if (transform['type'] != 'Transform' &&
          transform['type'] != 'RectTransform') {
        throw const FormatException('native_story_front_transform');
      }
      final data = transform['data'] as Map;
      final go = records[id(data['m_GameObject'])];
      if (go?['type'] != 'GameObject' ||
          !((go!['data'] as Map)['m_Component'] as List).any(
            (value) => id((value as Map)['component']) == entry.key,
          )) {
        throw const FormatException('native_story_front_game_object');
      }
      final names = <String>[];
      var current = transform;
      final visited = <String>{};
      while (true) {
        if (!visited.add(current['pathId'] as String)) {
          throw const FormatException('native_story_front_parent_cycle');
        }
        final tr = current['data'] as Map;
        final parentGo = records[id(tr['m_GameObject'])]!;
        names.add((parentGo['data'] as Map)['m_Name'] as String);
        final parent = id(tr['m_Father']);
        if (parent == '0') break;
        current = records[parent]!;
      }
      if ('/${names.reversed.join('/')}' != entry.value) {
        throw const FormatException('native_story_front_parent_path');
      }
    }
    final widget = records[frozen['widgetId']]!;
    final widgetData = widget['data'] as Map;
    if ((((widgetData['m_Script'] as Map)['reference'] as Map)['name']) !=
        'UIAdvWidget') {
      throw const FormatException('native_story_front_widget');
    }
    final domains = <String, Map<String, Object?>>{};
    for (final entry in (frozen['domains'] as Map).entries) {
      final mode = entry.key as String;
      final row = entry.value as Map<String, Object?>;
      final field = switch (mode) {
        'Subtitles' => '_subtitlesView',
        'Choice' => '_choiceView',
        _ => throw const FormatException('native_story_front_domain'),
      };
      if (id(widgetData[field]) != row['controllerId'] ||
          paths[row['rootTransformId']] != row['rootPath']) {
        throw const FormatException('native_story_front_controller_binding');
      }
      final controller = records[row['controllerId']]!['data'] as Map;
      final rootField = mode == 'Subtitles' ? '_subtitles' : 'm_GameObject';
      if (id(controller[rootField]) != row['rootGameObjectId']) {
        throw const FormatException('native_story_front_root_binding');
      }
      domains[mode] = row;
    }
    return NativeStoryFrontUiSource._(
      hash,
      Map.unmodifiable(records),
      Map.unmodifiable(paths),
      Map.unmodifiable(domains),
      frozen['widgetId'] as String,
    );
  }

  NativeStoryFrontUiSource withNext(Map<String, Object?> packet, String hash) {
    if (hash !=
            '4ddf7f2c9a1a80c4229f3383ad7205247e3106c87e5016c24cfac7f58d63dec6' ||
        packet['schema'] != 'haneoka-native-front-next-bindings-v1' ||
        packet['sourceId'] != 'v25-c0b6a1541e45-3a5d2eec9935-n653c6392' ||
        packet['sourceHash'] !=
            '4876cec383e7aab291fcb8a2ebf40a0b5a288a38ad8ee731f488db910fbf3acc' ||
        packet['controllerId'] != '7465943666252534048') {
      throw const FormatException('native_front_next_source');
    }
    bool same(Object? a, Object? b) {
      if (a is Map && b is Map) {
        return a.length == b.length &&
            a.entries.every(
              (e) => b.containsKey(e.key) && same(e.value, b[e.key]),
            );
      }
      if (a is List && b is List) {
        return a.length == b.length &&
            List.generate(a.length, (i) => i).every((i) => same(a[i], b[i]));
      }
      return a == b;
    }

    final frozen = _freezeFront(packet) as Map<String, Object?>;
    final combined = <String, Map<String, Object?>>{...records};
    for (final item in frozen['records'] as List) {
      final row = item as Map<String, Object?>, id = row['pathId'] as String;
      if (row['serializedFile'] != frozen['serializedFile'] ||
          (combined.containsKey(id) && !same(combined[id], row))) {
        throw const FormatException('native_front_next_record_identity');
      }
      combined[id] = row;
    }
    final newPaths = Map<String, String>.from(frozen['paths'] as Map);
    for (final e in newPaths.entries) {
      if (paths.containsKey(e.key) && paths[e.key] != e.value) {
        throw const FormatException('native_front_next_path_identity');
      }
    }
    return NativeStoryFrontUiSource._(
      this.hash,
      Map.unmodifiable(combined),
      Map.unmodifiable({...paths, ...newPaths}),
      domains,
      widgetId,
      hash,
    );
  }

  NativeStoryFrontUiSource withSprites(
    Map<String, Object?> packet,
    String hash,
  ) {
    if (hash !=
            'edb018fa821123a7e3e369bd5916cfd0d8288bcc424aac2fed399c24546bf64d' ||
        packet['schema'] != 'haneoka-native-front-sprites-v1' ||
        packet['sourceId'] != 'v25-c0b6a1541e45-3a5d2eec9935-n653c6392' ||
        packet['sourceHash'] !=
            '861349f84167e051dee02c74a9541bdad156d8e35c07f6e532a6be5b723c17d6') {
      throw const FormatException('native_front_sprites_source');
    }
    final frozen = _freezeFront(packet) as Map<String, Object?>;
    final records = frozen['records'] as List;
    if (records.length != 1) {
      throw const FormatException('native_front_sprites_count');
    }
    final sprite = records.single as Map;
    if (sprite['type'] != 'Sprite' ||
        sprite['serializedFile'] != 'CAB-b544f1ad112c62ed238fd605337161ec' ||
        sprite['pathId'] != '9049908415399983707') {
      throw const FormatException('native_front_sprite_identity');
    }
    return NativeStoryFrontUiSource._(
      this.hash,
      this.records,
      paths,
      domains,
      widgetId,
      nextBindingHash,
      frozen,
    );
  }

  NativeStoryFrontUiSource withLocation(
    Map<String, Object?> packet,
    String packetHash,
  ) {
    if (packetHash !=
            '80a23a1909b45f8811bfe98f9637c046cdca183d7eab30ab380bd2da713eecaf' ||
        packet['schema'] != 'haneoka-native-location-ui-source-v1') {
      throw const FormatException('native_location_source');
    }
    final combined = <String, Map<String, Object?>>{...records};
    final frozen = _freezeFront(packet) as Map<String, Object?>;
    for (final raw in frozen['records'] as List) {
      final row = raw as Map<String, Object?>;
      combined[row['pathId'] as String] = row;
    }
    final morePaths = Map<String, String>.from(frozen['paths'] as Map);
    final controller = combined[packet['controllerId']]!['data'] as Map;
    final widget = records[widgetId]!['data'] as Map;
    if ((widget['_locationView'] as Map)['m_PathID'] !=
            packet['controllerId'] ||
        (controller['m_GameObject'] as Map)['m_PathID'] !=
            packet['rootGameObjectId']) {
      throw const FormatException('native_location_controller');
    }
    return NativeStoryFrontUiSource._(
      hash,
      Map.unmodifiable(combined),
      Map.unmodifiable({...paths, ...morePaths}),
      Map.unmodifiable({
        ...domains,
        'Location': Map<String, Object?>.unmodifiable({
          'controllerId': packet['controllerId'],
          'rootGameObjectId': packet['rootGameObjectId'],
          'rootTransformId': packet['rootTransformId'],
        }),
      }),
      widgetId,
      nextBindingHash,
      spritePacket,
    );
  }

  String get locationRubyId =>
      (controller('Location')['_locationText'] as Map)['m_PathID'] as String;

  String get locationTransformId =>
      domains['Location']!['rootTransformId'] as String;
  String get locationGroupId =>
      records.values.singleWhere(
            (r) =>
                r['type'] == 'CanvasGroup' &&
                ((r['data'] as Map)['m_GameObject'] as Map)['m_PathID'] ==
                    domains['Location']!['rootGameObjectId'],
          )['pathId']
          as String;
  double get locationDuration {
    final sequenceId =
        (controller('Location')['_doTweenSequence'] as Map)['m_PathID'];
    final sequence = records[sequenceId]!['data'] as Map;
    return (sequence['_list'] as List).fold<double>(
      0,
      (duration, row) =>
          duration + ((row as Map)['_duration'] as num).toDouble(),
    );
  }

  NativeStoryFrontUiSource withLocationAnimation(Map<String, Object?> packet) {
    final record = packet['record'] as Map,
        controllerRecord = packet['controller'] as Map;
    final animatorId = (controller('Location')['_animator'] as Map)['m_PathID'];
    final animator = records[animatorId]!['data'] as Map;
    if (packet['schema'] != 'haneoka-native-ui-clip-v1' ||
        controllerRecord['pathId'] !=
            (animator['m_Controller'] as Map)['m_PathID'] ||
        !(controllerRecord['data']['m_AnimationClips'] as List).any(
          (p) =>
              p['m_PathID'].toString() == record['pathId'].toString() &&
              p['reference']['serializedFile'] == record['serializedFile'],
        )) {
      throw const FormatException('native_location_animation_binding');
    }
    final clip = NativeAuthoredAnimationClip(record['data'] as Map);
    if (clip.bindings.any(
      (b) =>
          b['path'] != 0 ||
          !(b['typeID'] == 225 && b['attribute'] == 1574349066 ||
              b['typeID'] == 224 &&
                  const {1460864421, 538195251}.contains(b['attribute'])),
    )) {
      throw const FormatException('native_location_animation_channels');
    }
    return NativeStoryFrontUiSource._(
      hash,
      records,
      paths,
      domains,
      widgetId,
      nextBindingHash,
      spritePacket,
      clip,
    );
  }

  Map<String, Object?> controller(String domain) =>
      records[domains[domain]!['controllerId']]!['data']
          as Map<String, Object?>;

  /// UIRubyText is the controller endpoint; its TMP is a separate component.
  Map<String, Object?> textComponent(String rubyId) {
    final ruby = records[rubyId]!['data'] as Map;
    final pointer = ruby['_targetText'] as Map;
    if (pointer['m_FileID'] != 0) {
      throw const FormatException('native_story_front_text_pointer');
    }
    final target = records[pointer['m_PathID']]!;
    if ((((target['data'] as Map)['m_Script'] as Map)['reference']
            as Map)['name'] !=
        'RubyTextMeshProUGUI') {
      throw const FormatException('native_story_front_text_component');
    }
    return target;
  }

  /// Build the selected original Front tree once. The Canvas owns its logical
  /// rect; its serialized zero scale is not the drawn Canvas transform.
  StoryUiSceneData scene(
    StoryUiSceneData compact, {
    List<Map> graphicSprites = const [],
  }) {
    final sprites = <String, Map<String, Object?>>{};
    void spriteNodes(StoryUiLayoutNode n) {
      if (n.raw['image'] case final Map image) {
        final key = image['asset'] as String;
        sprites.putIfAbsent(key, () => Map<String, Object?>.from(image));
      }
      for (final c in n.children) {
        spriteNodes(c);
      }
    }

    for (final roots in compact.scenes.values) {
      for (final root in roots) {
        spriteNodes(root);
      }
    }
    final transforms = <String, Map<String, Object?>>{
      for (final r in records.values)
        if (r['type'] == 'RectTransform') r['pathId'] as String: r,
    };
    final widget = records[widgetId]!['data'] as Map;
    final canvasRecord = records[(widget['_frontCanvas'] as Map)['m_PathID']]!;
    if (canvasRecord['type'] != 'Canvas') {
      throw const FormatException('native_front_canvas_pointer');
    }
    final canvasGo = (canvasRecord['data'] as Map)['m_GameObject'] as Map;
    final canvas = transforms.values.singleWhere(
      (record) =>
          ((record['data'] as Map)['m_GameObject'] as Map)['m_PathID'] ==
          canvasGo['m_PathID'],
    );
    List<double> vector(Map d, String key, List<String> axes) => [
      for (final axis in axes) ((d[key] as Map)[axis] as num).toDouble(),
    ];
    Map<String, Object?> node(Map<String, Object?> transform, bool root) {
      final tr = transform['data'] as Map;
      final go =
          records[(tr['m_GameObject'] as Map)['m_PathID']]!['data'] as Map;
      final output = <String, Object?>{
        'name': go['m_Name'],
        'active': go['m_IsActive'],
        'rect': root
            ? [
                [0.0, 0.0],
                [1.0, 1.0],
                [0.0, 0.0],
                [0.0, 0.0],
                [0.5, 0.5],
              ]
            : [
                vector(tr, 'm_AnchorMin', ['x', 'y']),
                vector(tr, 'm_AnchorMax', ['x', 'y']),
                vector(tr, 'm_AnchoredPosition', ['x', 'y']),
                vector(tr, 'm_SizeDelta', ['x', 'y']),
                vector(tr, 'm_Pivot', ['x', 'y']),
              ],
        'scale': root ? [1.0, 1.0] : vector(tr, 'm_LocalScale', ['x', 'y']),
      };
      for (final component in go['m_Component'] as List) {
        final record = records[(component['component'] as Map)['m_PathID']];
        if (record == null || record['type'] != 'MonoBehaviour') continue;
        final d = record['data'] as Map;
        final script = ((d['m_Script'] as Map)['reference'] as Map)['name'];
        if (script == 'UIGradientImage' &&
            d['m_Enabled'] != 0 &&
            d['m_Enabled'] != false) {
          output['gradient'] = {
            'angle': d['_angleDeg'],
            'blendMode': d['_blendMode'],
            'splitAtKeysWhenAxisAligned': d['_splitAtKeysWhenAxisAligned'] == 1,
            'keys': d['_gradient'],
          };
        }
        if (script == 'Image') {
          final pointer = d['m_Sprite'] as Map;
          if (pointer['m_PathID'] == '0') continue;
          final ref = pointer['reference'] as Map;
          final key = '${ref['name']}_${pointer['m_PathID']}';
          final sprite = sprites[key];
          if (ref['status'] != 'resolved' || sprite == null) {
            throw UnsupportedError('native_front_sprite_source:$key');
          }
          final originals = [
            ...graphicSprites,
            ...(spritePacket?['records'] as List? ?? const []).cast<Map>(),
          ];
          final original = originals
              .where(
                (r) =>
                    r['pathId'].toString() == pointer['m_PathID'].toString() &&
                    r['serializedFile'] == ref['serializedFile'],
              )
              .firstOrNull;
          if (original == null) {
            throw UnsupportedError('native_front_sprite_metadata:$key');
          }
          final sd = original['data'] as Map,
              sr = sd['m_Rect'] as Map,
              b = sd['m_Border'] as Map;
          final rd = sd['m_RD'] as Map,
              trim = rd['textureRect'] as Map,
              offset = rd['textureRectOffset'] as Map;
          final color = d['m_Color'] as Map;
          output['image'] = {
            ...sprite,
            'size': [sr['width'], sr['height']],
            'border': [b['x'], b['y'], b['z'], b['w']],
            'trim': [offset['x'], offset['y'], trim['width'], trim['height']],
            'pixelsPerUnit': sd['m_PixelsToUnits'],
            'pixelsPerUnitMultiplier': d['m_PixelsPerUnitMultiplier'],
            'sourceComponentId': record['pathId'],
            'color': [
              for (final c in ['r', 'g', 'b', 'a']) color[c],
            ],
            'mode': d['m_Type'],
            'preserveAspect': d['m_PreserveAspect'] == 1,
            'fillCenter': d['m_FillCenter'] == 1,
          };
        } else if (script == 'RubyTextMeshProUGUI') {
          final color = d['m_fontColor'] as Map;
          output['text'] = {
            'value': '',
            'size': d['m_fontSize'],
            'autoSize': d['m_enableAutoSizing'] == 1,
            'minSize': d['m_fontSizeMin'],
            'maxSize': d['m_fontSizeMax'],
            'style': d['m_fontStyle'],
            'color': [
              for (final c in ['r', 'g', 'b', 'a']) color[c],
            ],
            'characterSpacing': d['m_characterSpacing'],
            'lineSpacing': d['m_lineSpacing'],
            'horizontal': d['m_HorizontalAlignment'],
            'vertical': d['m_VerticalAlignment'],
            'font': ((d['m_fontAsset'] as Map)['reference'] as Map)['name'],
            'material':
                ((d['m_sharedMaterial'] as Map)['reference'] as Map)['name'],
          };
        }
      }
      output['children'] = [
        for (final p in tr['m_Children'] as List)
          if (transforms[(p as Map)['m_PathID']] case final child?)
            node(child, false),
      ];
      return output;
    }

    return StoryUiSceneData.fromJson({
      'Front': [node(canvas, true)],
    }, hash);
  }

  NativeStoryUiLayoutWindow retainedWindow(StoryUiSceneData frontScene) {
    final compact = <String, StoryUiLayoutNode>{};
    void collect(StoryUiLayoutNode n) {
      compact[n.path] = n;
      for (final c in n.children) {
        collect(c);
      }
    }

    for (final root in frontScene.scenes['Front']!) {
      collect(root);
    }
    final widget = records[widgetId]!['data'] as Map;
    final canvas =
        records[(widget['_frontCanvas'] as Map)['m_PathID']]!['data'] as Map;
    final canvasGo = (canvas['m_GameObject'] as Map)['m_PathID'];
    final canvasTransform = records.values.singleWhere(
      (r) =>
          r['type'] == 'RectTransform' &&
          ((r['data'] as Map)['m_GameObject'] as Map)['m_PathID'] == canvasGo,
    );
    final canvasId = canvasTransform['pathId'] as String;
    final prefix = paths[canvasId]!;
    final rootName = ((records[canvasGo]!['data'] as Map)['m_Name']) as String;
    final nodes = <StoryRetainedUiNode>[];
    final pathIds = <String, String>{}, gameIds = <String, String>{};
    final groups = <String, StoryLayoutGroupData>{};
    final fits = <String, List<int>>{};
    final elements = <String, List<StoryLayoutElementData>>{};
    final alpha = <String, double>{};
    List<double> vec(Map d, String key, List<String> axes) => [
      for (final a in axes) ((d[key] as Map)[a] as num).toDouble(),
    ];
    for (final entry in paths.entries) {
      if (entry.value != prefix && !entry.value.startsWith('$prefix/')) {
        continue;
      }
      final path = '/$rootName${entry.value.substring(prefix.length)}';
      final tr = records[entry.key]!['data'] as Map;
      final goId = (tr['m_GameObject'] as Map)['m_PathID'] as String;
      final go = records[goId]!['data'] as Map;
      final n = compact[path];
      if (n == null) throw const FormatException('native_front_retained_node');
      var group = false, fit = false;
      for (final pointer in go['m_Component'] as List) {
        final row = records[(pointer['component'] as Map)['m_PathID']];
        if (row == null) continue;
        final d = row['data'] as Map;
        final enabled = d['m_Enabled'] == 1 || d['m_Enabled'] == true;
        if (row['type'] == 'CanvasGroup' && enabled) {
          if (d['m_IgnoreParentGroups'] == true ||
              d['m_IgnoreParentGroups'] == 1) {
            throw UnsupportedError('native_front_ignore_parent_groups:$path');
          }
          alpha[entry.key] = (d['m_Alpha'] as num).toDouble();
        }
        if (row['type'] != 'MonoBehaviour') continue;
        final script = ((d['m_Script'] as Map)['reference'] as Map)['name'];
        if (enabled &&
            (script == 'HorizontalLayoutGroup' ||
                script == 'VerticalLayoutGroup')) {
          groups[path] = StoryLayoutGroupData.fromRaw(
            Map<String, Object?>.from(d),
          );
          group = true;
        } else if (enabled && script == 'ContentSizeFitter') {
          fits[path] = List.unmodifiable([
            (d['m_HorizontalFit'] as num).toInt(),
            (d['m_VerticalFit'] as num).toInt(),
          ]);
          fit = true;
        } else if (script == 'LayoutElement') {
          elements
              .putIfAbsent(path, () => [])
              .add(
                StoryLayoutElementData.fromRaw(Map<String, Object?>.from(d)),
              );
        }
      }
      nodes.add(
        StoryRetainedUiNode(
          id: entry.key,
          parentId: entry.key == canvasId
              ? null
              : (tr['m_Father'] as Map)['m_PathID'] as String,
          anchorMin: n.rect[0],
          anchorMax: n.rect[1],
          anchoredPosition: n.rect[2],
          sizeDelta: n.rect[3],
          pivot: n.rect[4],
          localZ: entry.key == canvasId
              ? 0
              : (tr['m_LocalPosition'] as Map)['z'] as double,
          quaternion: entry.key == canvasId
              ? const [0, 0, 0, 1]
              : vec(tr, 'm_LocalRotation', ['x', 'y', 'z', 'w']),
          scale: entry.key == canvasId
              ? const [1, 1, 1]
              : vec(tr, 'm_LocalScale', ['x', 'y', 'z']),
          active: go['m_IsActive'] == true,
          layoutGroup: group,
          contentSizeFitter: fit,
        ),
      );
      pathIds[path] = entry.key;
      gameIds[goId] = entry.key;
    }
    return NativeStoryUiLayoutWindow(
      sourceHash: hash,
      nodes: nodes,
      pathToId: pathIds,
      gameObjectToId: gameIds,
      groups: groups,
      fits: fits,
      elements: {
        for (final e in elements.entries) e.key: List.unmodifiable(e.value),
      },
      groupAlpha: alpha,
    );
  }

  StoryTextSourceBinding textBinding(String rubyId) =>
      StoryTextSourceBinding.fromRaw(
        sourceHash:
            '4876cec383e7aab291fcb8a2ebf40a0b5a288a38ad8ee731f488db910fbf3acc',
        component: textComponent(rubyId)['data'] as Map<String, Object?>,
        uiRubyComponent: records[rubyId]!['data'] as Map<String, Object?>,
      );

  String materialName(String rubyId) {
    final component = textComponent(rubyId)['data'] as Map;
    final pointer = component['m_sharedMaterial'] as Map;
    final reference = pointer['reference'] as Map;
    if (reference['status'] != 'resolved' ||
        reference['type'] != 'Material' ||
        pointer['m_PathID'] != reference['pathId']) {
      throw const FormatException('native_story_front_text_material');
    }
    return reference['name'] as String;
  }

  List<String> get choiceItemIds => List.unmodifiable([
    for (final pointer in controller('Choice')['_choiceItems'] as List)
      (pointer as Map)['m_PathID'] as String,
  ]);

  String get subtitlesRubyId =>
      (controller('Subtitles')['_subtitlesText'] as Map)['m_PathID'] as String;

  bool textExtraPadding(String rubyId) {
    final value =
        (textComponent(rubyId)['data'] as Map)['m_enableExtraPadding'];
    return switch (value) {
      true || 1 => true,
      false || 0 => false,
      _ => throw const FormatException('native_story_front_extra_padding'),
    };
  }
}
