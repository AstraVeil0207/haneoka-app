import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_playback.dart';
import 'native_story_ui_source.dart';

final class NativeStoryTalkIconRequests {
  const NativeStoryTalkIconRequests({
    required this.next,
    required this.autoMode,
    required this.autoIcon,
    required this.fastIcon,
  });
  final bool next, autoMode, autoIcon, fastIcon;
}

final class _Requests {
  bool next = false, autoMode = false, autoIcon = false, fastIcon = false;
  NativeStoryTalkIconRequests get frame => NativeStoryTalkIconRequests(
    next: next,
    autoMode: autoMode,
    autoIcon: autoIcon,
    fastIcon: fastIcon,
  );
  void restore(NativeStoryTalkIconRequests value) {
    next = value.next;
    autoMode = value.autoMode;
    autoIcon = value.autoIcon;
    fastIcon = value.fastIcon;
  }
}

final class NativeStoryTalkUiFrame {
  NativeStoryTalkUiFrame._(
    this.visibility,
    Map<String, StoryTalkIndicatorFrame> indicators,
    Map<String, NativeStoryTalkIconRequests> requests,
    Map<String, bool> effectiveIcons,
    this.visualRevision,
    this.layoutRevision,
    this.poseRevision,
    this.activationRevision,
  ) : indicators = Map.unmodifiable(indicators),
      requests = Map.unmodifiable(requests),
      effectiveIcons = Map.unmodifiable(effectiveIcons);
  final StoryTalkVisibilityFrame visibility;
  final Map<String, StoryTalkIndicatorFrame> indicators;
  final Map<String, NativeStoryTalkIconRequests> requests;
  final Map<String, bool> effectiveIcons;
  final int visualRevision, layoutRevision, poseRevision, activationRevision;
}

final class NativeStoryTalkUiSnapshot {
  NativeStoryTalkUiSnapshot._(
    this.identity,
    this.epoch,
    this.bindingSHA256,
    this.sceneSHA256,
    this.visibility,
    Map<String, StoryTalkIndicatorSnapshot> indicators,
    Map<String, NativeStoryTalkIconRequests> requests,
    Map<String, bool> effectiveIcons,
    this.viewAuto,
    this.viewFast,
    this.paused,
    this.visualRevision,
    this.layoutRevision,
    this.poseRevision,
    this.activationRevision,
  ) : indicators = Map.unmodifiable(indicators),
      requests = Map.unmodifiable(requests),
      effectiveIcons = Map.unmodifiable(effectiveIcons);
  final StorySourceIdentity identity;
  final int epoch;
  final String bindingSHA256, sceneSHA256;
  final StoryTalkVisibilitySnapshot visibility;
  final Map<String, StoryTalkIndicatorSnapshot> indicators;
  final Map<String, NativeStoryTalkIconRequests> requests;
  final Map<String, bool> effectiveIcons;
  final bool viewAuto, viewFast, paused;
  final int visualRevision, layoutRevision, poseRevision, activationRevision;
  Map<String, Object?> toData() => {
    'version': 1,
    'source': identity.toJson(),
    'bindingSHA256': bindingSHA256,
    'sceneSHA256': sceneSHA256,
    'visibility': visibility.toData(),
    'indicators': {for (final e in indicators.entries) e.key: e.value.toData()},
    'requests': {
      for (final e in requests.entries)
        e.key: [
          e.value.next,
          e.value.autoMode,
          e.value.autoIcon,
          e.value.fastIcon,
        ],
    },
    'effectiveIcons': effectiveIcons,
    'viewAuto': viewAuto,
    'viewFast': viewFast,
    'paused': paused,
    'revisions': [
      visualRevision,
      layoutRevision,
      poseRevision,
      activationRevision,
    ],
  };
}

/// Events and one real captured UI Update pair connect the admitted pure
/// controllers. No layout, drawing, asynchronous scheduling or clock is owned
/// here; the future host chooses the command-before-animation UI phase.
final class NativeStoryTalkUiRuntime {
  NativeStoryTalkUiRuntime({
    required NativeStoryUiSource ui,
    required this.sourceIdentity,
    required NativeStoryUpdateStamp initialStamp,
  }) : controls = ui.controls,
       sourceEpoch = initialStamp.sourceEpoch {
    if (controls.sourceId != sourceIdentity.sourceId ||
        sourceIdentity.server != 'intl' ||
        initialStamp.sourceEpoch < 0 ||
        initialStamp.storyUs < 0 ||
        initialStamp.updateIndex < 0) {
      throw const FormatException('native_talk_ui_source');
    }
    _paused = initialStamp.paused;
    _visibility = StoryTalkWindowVisibility(
      sourceIdentity: sourceIdentity,
      sourceEpoch: sourceEpoch,
      actualSources: {
        for (final entry in controls.windows.entries)
          entry.key: entry.value.visibility,
      },
      actualDefaultFadeSeconds: 0.2,
      actualFadeEase: controls.defaultEase,
      actualBackdropSource: controls.backdrop,
      actualStoryUs: initialStamp.storyUs,
      actualUpdateIndex: initialStamp.updateIndex,
    );
    for (final mode in controls.windows.keys) {
      _requests[mode] = _Requests();
      for (final field in _fields) {
        _effectiveIcons['$mode:$field'] = false;
      }
    }
    for (final entry in controls.indicators.entries) {
      _indicators[entry.key] = StoryTalkIndicatorAnimator(
        source: entry.value,
        sourceIdentity: sourceIdentity,
        sourceEpoch: sourceEpoch,
        actualUIUpdateUs: initialStamp.storyUs,
        actualUpdateIndex: initialStamp.updateIndex,
      );
    }
  }
  static const _fields = ['_talkNextIndicator', '_autoIcon', '_fastIcon'];
  final StorySourceIdentity sourceIdentity;
  final int sourceEpoch;
  final StoryUiControlBindings controls;
  late final StoryTalkWindowVisibility _visibility;
  final _indicators = <String, StoryTalkIndicatorAnimator>{};
  final _requests = <String, _Requests>{};
  final _effectiveIcons = <String, bool>{};
  bool _viewAuto = false, _viewFast = false, _paused = false, _closed = false;
  int _visualRevision = 0,
      _layoutRevision = 0,
      _poseRevision = 0,
      _activationRevision = 0;

  void _open() {
    if (_closed) throw StateError('native_talk_ui_closed');
  }

  NativeStoryTalkUiFrame get frame {
    _open();
    return NativeStoryTalkUiFrame._(
      _visibility.frame,
      {for (final entry in _indicators.entries) entry.key: entry.value.frame},
      {for (final entry in _requests.entries) entry.key: entry.value.frame},
      _effectiveIcons,
      _visualRevision,
      _layoutRevision,
      _poseRevision,
      _activationRevision,
    );
  }

  bool _effective(String mode, String field) {
    final window = controls.windows[mode]!;
    final state = _visibility.frame.windows[mode]!;
    final endpoint = window.endpoints[field];
    if (endpoint == null || !state.rootActive || !state.talkAreaActive) {
      return false;
    }
    final requests = _requests[mode]!;
    final flag = switch (field) {
      '_talkNextIndicator' => requests.next && !requests.autoMode,
      '_autoIcon' => requests.autoIcon,
      '_fastIcon' => requests.fastIcon,
      _ => throw const FormatException('native_talk_ui_icon_field'),
    };
    if (!flag) return false;
    String? id = endpoint.transformId;
    final seen = <String>{};
    while (id != null) {
      if (!seen.add(id)) {
        throw const FormatException('native_talk_ui_parent_cycle');
      }
      final node = window.transforms[id];
      if (node == null) {
        throw const FormatException('native_talk_ui_parent_missing');
      }
      // These three actual objects have runtime-driven active flags. Other
      // original ancestors retain their authored activation.
      final driven =
          node.gameObjectId == window.visibility.rootGameObjectId ||
          node.gameObjectId == window.visibility.talkAreaGameObjectId ||
          id == endpoint.transformId;
      if (!driven && !node.active) return false;
      id = node.parentId;
    }
    return true;
  }

  void _edge(String key, bool active) {
    if (_effectiveIcons[key] == active) return;
    _effectiveIcons[key] = active;
    _indicators[key]?.setHierarchyActive(active);
    _activationRevision++;
    _visualRevision++;
    _layoutRevision++;
  }

  void _refreshEdges() {
    for (final mode in controls.windows.keys) {
      for (final field in _fields) {
        _edge('$mode:$field', _effective(mode, field));
      }
    }
  }

  void _visibilityChanged(StoryTalkVisibilityFrame before) {
    final after = _visibility.frame;
    for (final mode in controls.windows.keys) {
      final old = before.windows[mode]!, value = after.windows[mode]!;
      if (old.rootActive != value.rootActive ||
          old.talkAreaActive != value.talkAreaActive) {
        _visualRevision++;
        _layoutRevision++;
      }
      if (old.backgroundAlpha != value.backgroundAlpha) _visualRevision++;
    }
    if (before.backdropAlpha != after.backdropAlpha) _visualRevision++;
  }

  void _windowStatus(String mode) {
    final requests = _requests[mode]!;
    requests.autoIcon = _viewAuto;
    requests.autoMode = _viewAuto;
    requests.fastIcon = _viewFast;
    if (_viewAuto &&
        controls.windows[mode]!.endpoints['_talkNextIndicator'] != null) {
      requests.next = false;
    }
  }

  void attachWindow(String mode) {
    _open();
    if (!controls.windows.containsKey(mode)) {
      throw UnsupportedError('native_talk_ui_window:$mode');
    }
    final before = _visibility.frame;
    final old = before.currentMode;
    if (old != null) {
      // Preserve the real off/on edge even when old and selected mode coincide.
      for (final field in _fields) {
        _edge('$old:$field', false);
      }
    }
    _visibility.attachWindow(mode);
    _windowStatus(mode);
    _refreshEdges();
    _visibilityChanged(before);
  }

  /// The host invokes this before voice resolution for genuine Talk2 only.
  /// It decides the invalid-text return; this module owns no voice operation.
  bool beginTalk(StoryDecodedCommand command) {
    _open();
    if (command.opcode != 2) {
      throw const FormatException('native_talk_ui_talk_opcode');
    }
    hideNext();
    final id = command.payload['advTextId'];
    if (id != null && id is! String) {
      throw const FormatException('native_talk_ui_text_id');
    }
    final valid = id is String && id.isNotEmpty && id != '0';
    if (!valid) hideTalk();
    return valid;
  }

  void showTalk() {
    _open();
    final before = _visibility.frame;
    _visibility.showTalk();
    _refreshEdges();
    _visibilityChanged(before);
  }

  void hideTalk() {
    _open();
    final before = _visibility.frame;
    _visibility.hideTalk();
    _refreshEdges();
    _visibilityChanged(before);
  }

  void hideNext() {
    _open();
    final mode = _visibility.frame.currentMode;
    if (mode == null ||
        controls.windows[mode]!.endpoints['_talkNextIndicator'] == null) {
      return;
    }
    _requests[mode]!.next = false;
    _refreshEdges();
  }

  void requestNext() {
    _open();
    final mode = _visibility.frame.currentMode;
    if (mode == null ||
        controls.windows[mode]!.endpoints['_talkNextIndicator'] == null) {
      return;
    }
    _requests[mode]!.next = true;
    _refreshEdges();
  }

  void setAutoMode(bool on) {
    _open();
    _viewAuto = on;
    final mode = _visibility.frame.currentMode;
    if (mode != null) _windowStatus(mode);
    _refreshEdges();
  }

  void setFastIcon(bool on) {
    _open();
    _viewFast = on;
    final mode = _visibility.frame.currentMode;
    if (mode != null) _windowStatus(mode);
    _refreshEdges();
  }

  NativeStoryTalkUiFrame actualUiPhase(NativeStoryUpdateStamp stamp) {
    _open();
    if (stamp.sourceEpoch != sourceEpoch) {
      close();
      throw StateError('native_talk_ui_epoch');
    }
    final before = _visibility.frame;
    final poses = {
      for (final entry in _indicators.entries)
        entry.key: entry.value.frame.pose,
    };
    _paused = stamp.paused;
    _visibility.update(
      stamp.storyUs,
      actualUpdateIndex: stamp.updateIndex,
      paused: stamp.paused,
      epoch: stamp.sourceEpoch,
    );
    _refreshEdges();
    for (final entry in _indicators.entries) {
      final current = entry.value
          .update(
            stamp.storyUs,
            actualUpdateIndex: stamp.updateIndex,
            paused: stamp.paused,
            epoch: stamp.sourceEpoch,
          )
          .pose;
      final previous = poses[entry.key]!;
      bool same(List<double>? a, List<double>? b) => a == null || b == null
          ? a == b
          : a.length == b.length &&
                [for (var i = 0; i < a.length; i++) a[i] == b[i]]
                    .every((v) => v);
      if (previous.anchoredY != current.anchoredY ||
          !same(
            previous.localRotationQuaternion,
            current.localRotationQuaternion,
          )) {
        _poseRevision++;
        _visualRevision++;
      }
    }
    _visibilityChanged(before);
    return frame;
  }

  NativeStoryTalkUiSnapshot snapshot() {
    _open();
    return NativeStoryTalkUiSnapshot._(
      sourceIdentity,
      sourceEpoch,
      controls.packetSHA256,
      controls.sceneSHA256,
      _visibility.snapshot(),
      {
        for (final entry in _indicators.entries)
          entry.key: entry.value.snapshot(),
      },
      {for (final entry in _requests.entries) entry.key: entry.value.frame},
      _effectiveIcons,
      _viewAuto,
      _viewFast,
      _paused,
      _visualRevision,
      _layoutRevision,
      _poseRevision,
      _activationRevision,
    );
  }

  Map<String, Object?> snapshotData() => snapshot().toData();
  void restoreData(Map data, {required NativeStoryUpdateStamp stamp}) {
    _open();
    final requests = data['requests'] as Map,
        indicators = data['indicators'] as Map,
        effective = Map<String, bool>.from(data['effectiveIcons'] as Map);
    if (data['version'] != 1 ||
        StorySourceIdentity.fromJson(data['source'] as Map) != sourceIdentity ||
        stamp.sourceEpoch != sourceEpoch ||
        data['bindingSHA256'] != controls.packetSHA256 ||
        data['sceneSHA256'] != controls.sceneSHA256 ||
        requests.length != _requests.length ||
        !_requests.keys.every(requests.containsKey) ||
        indicators.length != _indicators.length ||
        !_indicators.keys.every(indicators.containsKey) ||
        effective.length != _effectiveIcons.length ||
        !_effectiveIcons.keys.every(effective.containsKey)) {
      throw const FormatException('native_talk_ui_data_source');
    }
    _visibility.restoreData(
      data['visibility'] as Map,
      actualStoryUs: stamp.storyUs,
      actualUpdateIndex: stamp.updateIndex,
      paused: stamp.paused,
    );
    for (final e in _indicators.entries) {
      e.value.restoreData(
        indicators[e.key] as Map,
        actualUIUpdateUs: stamp.storyUs,
        actualUpdateIndex: stamp.updateIndex,
      );
    }
    for (final e in _requests.entries) {
      final value = (requests[e.key] as List).cast<bool>();
      if (value.length != 4) {
        throw const FormatException('native_talk_ui_data_requests');
      }
      e.value.restore(
        NativeStoryTalkIconRequests(
          next: value[0],
          autoMode: value[1],
          autoIcon: value[2],
          fastIcon: value[3],
        ),
      );
    }
    _effectiveIcons
      ..clear()
      ..addAll(effective);
    _viewAuto = data['viewAuto'] as bool;
    _viewFast = data['viewFast'] as bool;
    _paused = stamp.paused;
    final revisions = (data['revisions'] as List).cast<int>();
    _visualRevision = revisions[0];
    _layoutRevision = revisions[1];
    _poseRevision = revisions[2];
    _activationRevision = revisions[3];
  }

  void restore(NativeStoryTalkUiSnapshot snapshot) {
    _open();
    if (snapshot.identity != sourceIdentity ||
        snapshot.epoch != sourceEpoch ||
        snapshot.bindingSHA256 != controls.packetSHA256 ||
        snapshot.sceneSHA256 != controls.sceneSHA256 ||
        snapshot.requests.length != _requests.length ||
        snapshot.indicators.length != _indicators.length ||
        snapshot.effectiveIcons.length != _effectiveIcons.length ||
        !_requests.keys.every(snapshot.requests.containsKey) ||
        !_indicators.keys.every(snapshot.indicators.containsKey) ||
        !_effectiveIcons.keys.every(snapshot.effectiveIcons.containsKey)) {
      throw const FormatException('native_talk_ui_snapshot_source');
    }
    _visibility.restore(snapshot.visibility);
    for (final entry in _indicators.entries) {
      entry.value.restore(snapshot.indicators[entry.key]!);
    }
    for (final entry in _requests.entries) {
      entry.value.restore(snapshot.requests[entry.key]!);
    }
    _effectiveIcons
      ..clear()
      ..addAll(snapshot.effectiveIcons);
    _viewAuto = snapshot.viewAuto;
    _viewFast = snapshot.viewFast;
    _paused = snapshot.paused;
    _visualRevision = snapshot.visualRevision;
    _layoutRevision = snapshot.layoutRevision;
    _poseRevision = snapshot.poseRevision;
    _activationRevision = snapshot.activationRevision;
    // No attach/status/OnEnable replay: controller clocks and held poses are
    // restored directly with their existing source identity validation.
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _visibility.close();
    for (final indicator in _indicators.values) {
      indicator.close();
    }
  }
}
