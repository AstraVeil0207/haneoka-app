import 'package:vega_plugin_haneoka/render_profile.dart';

final class NativeStoryUiLayoutWindow {
  NativeStoryUiLayoutWindow({
    required this.sourceHash,
    required List<StoryRetainedUiNode> nodes,
    required Map<String, String> pathToId,
    required Map<String, String> gameObjectToId,
    required Map<String, StoryLayoutGroupData> groups,
    required Map<String, List<int>> fits,
    required Map<String, List<StoryLayoutElementData>> elements,
    required Map<String, double> groupAlpha,
  }) : nodes = List.unmodifiable(nodes),
       pathToId = Map.unmodifiable(pathToId),
       gameObjectToId = Map.unmodifiable(gameObjectToId),
       groups = Map.unmodifiable(groups),
       fits = Map.unmodifiable(fits),
       elements = Map.unmodifiable(elements),
       groupAlpha = Map.unmodifiable(groupAlpha);
  final String sourceHash;
  final List<StoryRetainedUiNode> nodes;
  final Map<String, String> pathToId;
  final Map<String, String> gameObjectToId;
  final Map<String, StoryLayoutGroupData> groups;
  final Map<String, List<int>> fits;
  final Map<String, List<StoryLayoutElementData>> elements;
  final Map<String, double> groupAlpha;
}

final class NativeStoryUiLayoutSource {
  NativeStoryUiLayoutSource._(
    this.hash,
    Map<String, NativeStoryUiLayoutWindow> windows,
  ) : windows = Map.unmodifiable(windows);
  final String hash;
  final Map<String, NativeStoryUiLayoutWindow> windows;
  factory NativeStoryUiLayoutSource.fromPacket({
    required Map<String, Object?> packet,
    required String hash,
    required StorySourceIdentity source,
    required StoryUiSceneData scenes,
    required StoryUiControlBindings controls,
  }) {
    if (hash !=
            '4e37b0a097030734b443039665626b8554d718d1acabed27ba970c2833e39f56' ||
        packet['schema'] != 'haneoka-ui-layout-nodes-v1' ||
        source.server != 'intl' ||
        packet['sourceId'] != source.sourceId ||
        controls.sourceId != source.sourceId) {
      throw const FormatException('native_ui_layout_source');
    }
    List<double> vector(Map data, String name, List<String> axes) {
      final v = data[name] as Map;
      return [for (final axis in axes) (v[axis] as num).toDouble()];
    }

    final windows = <String, NativeStoryUiLayoutWindow>{};
    for (final mode in controls.windows.keys) {
      final raw = (packet['windows'] as Map)[mode] as Map;
      final scene = mode == 'Default'
          ? 'UIDefaultTalkWindow'
          : 'UICenterTalkWindow';
      final compact = <String, StoryUiLayoutNode>{};
      void collect(StoryUiLayoutNode n) {
        compact[n.path] = n;
        for (final c in n.children) {
          collect(c);
        }
      }

      for (final root in scenes.scenes[scene]!) {
        collect(root);
      }
      if (raw['sourceUiHash'] !=
          controls.windows[mode]!.visibility.sourceUiHash) {
        throw const FormatException('native_ui_layout_window_source');
      }
      final nodes = <StoryRetainedUiNode>[],
          paths = <String, String>{},
          games = <String, String>{};
      final groups = <String, StoryLayoutGroupData>{},
          fits = <String, List<int>>{};
      final elements = <String, List<StoryLayoutElementData>>{},
          alpha = <String, double>{};
      for (final entry in raw['nodes'] as List) {
        final row = entry as Map,
            tr = row['transform'] as Map,
            go = row['gameObject'] as Map;
        final data = tr['data'] as Map, gd = go['data'] as Map;
        final id = tr['pathId'] as String, path = row['path'] as String;
        final n = compact[path];
        if (n == null ||
            tr['serializedFile'] != raw['serializedFile'] ||
            (data['m_GameObject'] as Map)['m_PathID'] != go['pathId']) {
          throw const FormatException('native_ui_layout_node_binding');
        }
        final rect = [
          vector(data, 'm_AnchorMin', ['x', 'y']),
          vector(data, 'm_AnchorMax', ['x', 'y']),
          vector(data, 'm_AnchoredPosition', ['x', 'y']),
          vector(data, 'm_SizeDelta', ['x', 'y']),
          vector(data, 'm_Pivot', ['x', 'y']),
        ];
        for (var a = 0; a < 5; a++) {
          for (var b = 0; b < 2; b++) {
            if (rect[a][b] != n.rect[a][b]) {
              throw FormatException('native_ui_layout_geometry:$path');
            }
          }
        }
        var group = false, fit = false;
        for (final record in (row['components'] as List).cast<Map>()) {
          final c = record['data'] as Map;
          if (record['type'] == 'CanvasGroup' && c['m_Enabled'] == 1) {
            if (c['m_IgnoreParentGroups'] == true ||
                c['m_IgnoreParentGroups'] == 1) {
              throw UnsupportedError('native_ui_layout_ignore_groups:$path');
            }
            alpha[id] = (c['m_Alpha'] as num).toDouble();
          }
          if (record['type'] != 'MonoBehaviour') continue;
          final script = ((c['m_Script'] as Map)['reference'] as Map)['name'];
          final enabled = c['m_Enabled'] == 1 || c['m_Enabled'] == true;
          if (enabled &&
              (script == 'HorizontalLayoutGroup' ||
                  script == 'VerticalLayoutGroup')) {
            groups[path] = StoryLayoutGroupData.fromRaw(
              Map<String, Object?>.from(c),
            );
            group = true;
          } else if (enabled && script == 'ContentSizeFitter') {
            fits[path] = List.unmodifiable([
              (c['m_HorizontalFit'] as num).toInt(),
              (c['m_VerticalFit'] as num).toInt(),
            ]);
            fit = true;
          } else if (script == 'LayoutElement') {
            elements
                .putIfAbsent(path, () => [])
                .add(
                  StoryLayoutElementData.fromRaw(Map<String, Object?>.from(c)),
                );
          }
        }
        final parent = (data['m_Father'] as Map)['m_PathID'] as String;
        nodes.add(
          StoryRetainedUiNode(
            id: id,
            parentId: parent == '0' ? null : parent,
            anchorMin: rect[0],
            anchorMax: rect[1],
            anchoredPosition: rect[2],
            sizeDelta: rect[3],
            pivot: rect[4],
            localZ: (data['m_LocalPosition'] as Map)['z'] as double,
            quaternion: vector(data, 'm_LocalRotation', ['x', 'y', 'z', 'w']),
            scale: vector(data, 'm_LocalScale', ['x', 'y', 'z']),
            active: gd['m_IsActive'] == true,
            layoutGroup: group,
            contentSizeFitter: fit,
          ),
        );
        paths[path] = id;
        games[go['pathId'] as String] = id;
      }
      if (paths.length != compact.length) {
        throw const FormatException('native_ui_layout_scene_coverage');
      }
      windows[mode] = NativeStoryUiLayoutWindow(
        sourceHash: raw['sourceUiHash'] as String,
        nodes: nodes,
        pathToId: paths,
        gameObjectToId: games,
        groups: groups,
        fits: fits,
        elements: elements,
        groupAlpha: alpha,
      );
    }
    return NativeStoryUiLayoutSource._(hash, windows);
  }
}
