import 'dart:typed_data';
import 'dart:convert';

import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_playback.dart';

import 'native_story_front_ui_source.dart';

/// Source-scoped Front state is separate from the active Talk window. Hidden
/// captions retain their original text, and choices lock the genuine Next input.
final class NativeStoryFrontUiRuntime {
  NativeStoryFrontUiRuntime({required this.source, required this.sourceEpoch});
  final NativeStoryFrontUiSource source;
  final int sourceEpoch;
  final _checkpointOwner = Object();
  String _caption = '', _location = '';
  bool locationVisible = false;
  double _locationElapsed = 0;
  int _locationGeneration = 0;
  int showLocation(String value) {
    _location = value;
    locationVisible = value.isNotEmpty;
    _locationElapsed = 0;
    ++_locationGeneration;
    _sampleLocation();
    revision++;
    return _locationGeneration;
  }

  void finishLocation(int generation) {
    if (generation != _locationGeneration) return;
    _locationElapsed = source.locationAnimation!.duration;
    _sampleLocation();
    revision++;
  }

  void _sampleLocation() {
    if (!locationVisible) return;
    for (final sample in source.locationAnimation!.sampleBindingsAt(
      _locationElapsed,
    )) {
      switch (sample.binding['attribute']) {
        case 1574349066:
          _alpha[source.locationGroupId] = sample.values.single;
        case 1460864421:
          _x[source.locationTransformId] = sample.values.single;
        case 538195251:
          _y[source.locationTransformId] = sample.values.single;
      }
    }
  }

  bool _captionActive = false, _captionsEnabled = true, _next = false;
  bool _closed = false;
  StoryChoicePresentation? _choices;
  List<String> _choiceTexts = const [];
  int revision = 0;
  bool ruleVisible = false, ruleGradient = false;
  Uri? ruleTexture;
  double ruleValue = 1, flashAlpha = 0;
  List<double> ruleColor = const [0, 0, 0, 1];

  void setRuleValue(double value) {
    ruleValue = value;
    revision++;
  }

  void setFlash(double value) {
    flashAlpha = value;
    revision++;
  }

  NativeStoryUpdateStamp? _stamp;
  bool _hiding = false;
  double _elapsed = 0;
  final _alpha = <String, double>{},
      _y = <String, double>{},
      _x = <String, double>{};
  Map<String, double> _hideStarts = const {};
  Map<String, double> get alphaOverrides => Map.unmodifiable(_alpha);
  Map<String, double> get anchoredYOverrides => Map.unmodifiable(_y);
  Map<String, double> get anchoredXOverrides => Map.unmodifiable(_x);
  final _float = Float32List(1);
  double _f(double v) {
    _float[0] = v;
    return _float[0];
  }

  String get caption => _caption;
  bool get captionVisible => !_closed && _captionActive;
  bool get captionsEnabled => _captionsEnabled;
  bool get nextVisible => !_closed && _next;
  bool get nextLocked => _choices?.nextButtonLocked ?? false;
  StoryChoicePresentation? get choices => _choices;
  List<String> get choiceTexts => _choiceTexts;

  Map<String, Object?> snapshotData() => {
    'version': 1,
    'sourceHash': source.hash,
    'nextHash': source.nextBindingHash,
    'widgetId': source.widgetId,
    'caption': _caption,
    'location': _location,
    'choiceTexts': List<String>.of(_choiceTexts),
    'choices': _choices?.snapshotData(),
    'flags': [
      locationVisible,
      _captionActive,
      _captionsEnabled,
      _next,
      _hiding,
      ruleVisible,
      ruleGradient,
    ],
    'locationElapsed': _locationElapsed,
    'locationGeneration': _locationGeneration,
    'revision': revision,
    'ruleResource': ruleTexture?.toString(),
    'ruleValue': ruleValue,
    'ruleColor': List<double>.of(ruleColor),
    'flashAlpha': flashAlpha,
    'elapsed': _elapsed,
    'alpha': Map<String, double>.of(_alpha),
    'x': Map<String, double>.of(_x),
    'y': Map<String, double>.of(_y),
    'hideStarts': Map<String, double>.of(_hideStarts),
  };

  void restoreData(
    Map data, {
    required NativeStoryUpdateStamp stamp,
    required Uri Function(String) resolveResource,
  }) {
    _current(stamp.sourceEpoch);
    if (data['version'] != 1 ||
        data['sourceHash'] != source.hash ||
        data['nextHash'] != source.nextBindingHash ||
        data['widgetId'] != source.widgetId) {
      throw const FormatException('front_data_source');
    }
    _choices?.cancel('front_data_restore');
    _caption = data['caption'] as String;
    _location = data['location'] as String;
    _choiceTexts = List<String>.unmodifiable(
      (data['choiceTexts'] as List).cast<String>(),
    );
    _choices = data['choices'] == null
        ? null
        : StoryChoicePresentation.fromData(
            data['choices'] as Map,
            sourceEpoch: sourceEpoch,
          );
    final flags = (data['flags'] as List).cast<bool>();
    locationVisible = flags[0];
    _captionActive = flags[1];
    _captionsEnabled = flags[2];
    _next = flags[3];
    _hiding = flags[4];
    ruleVisible = flags[5];
    ruleGradient = flags[6];
    _locationElapsed = (data['locationElapsed'] as num).toDouble();
    _locationGeneration = data['locationGeneration'] as int;
    revision = data['revision'] as int;
    ruleTexture = data['ruleResource'] == null
        ? null
        : resolveResource(data['ruleResource'] as String);
    ruleValue = (data['ruleValue'] as num).toDouble();
    ruleColor = List<double>.unmodifiable(
      (data['ruleColor'] as List).map((v) => (v as num).toDouble()),
    );
    flashAlpha = (data['flashAlpha'] as num).toDouble();
    _elapsed = (data['elapsed'] as num).toDouble();
    Map<String, double> values(String key) => {
      for (final entry in (data[key] as Map).entries)
        entry.key as String: (entry.value as num).toDouble(),
    };
    _alpha
      ..clear()
      ..addAll(values('alpha'));
    _x
      ..clear()
      ..addAll(values('x'));
    _y
      ..clear()
      ..addAll(values('y'));
    _hideStarts = Map.unmodifiable(values('hideStarts'));
    _stamp = stamp;
  }

  NativeStoryFrontUiStateSnapshot snapshot() {
    _current(sourceEpoch);
    final text = (_caption, _location, List<String>.of(_choiceTexts));
    final flags = (
      locationVisible,
      _captionActive,
      _captionsEnabled,
      _next,
      _hiding,
      ruleVisible,
      ruleGradient,
    );
    final values = (
      _locationElapsed,
      _locationGeneration,
      revision,
      ruleTexture,
      ruleValue,
      flashAlpha,
      List<double>.of(ruleColor),
      _elapsed,
      _stamp,
    );
    final alpha = Map<String, double>.of(_alpha);
    final x = Map<String, double>.of(_x), y = Map<String, double>.of(_y);
    final starts = Map<String, double>.of(_hideStarts);
    final choices = _choices?.snapshot();
    return NativeStoryFrontUiStateSnapshot._(
      _checkpointOwner,
      sourceEpoch,
      source.hash,
      source.nextBindingHash,
      source.widgetId,
      snapshotData(),
      (stamp) {
        _choices?.cancel('front_snapshot_restore');
        _caption = text.$1;
        _location = text.$2;
        _choiceTexts = List.unmodifiable(text.$3);
        locationVisible = flags.$1;
        _captionActive = flags.$2;
        _captionsEnabled = flags.$3;
        _next = flags.$4;
        _hiding = flags.$5;
        ruleVisible = flags.$6;
        ruleGradient = flags.$7;
        _locationElapsed = values.$1;
        _locationGeneration = values.$2;
        revision = values.$3;
        ruleTexture = values.$4;
        ruleValue = values.$5;
        flashAlpha = values.$6;
        ruleColor = List.unmodifiable(values.$7);
        _elapsed = values.$8;
        _stamp = stamp ?? values.$9;
        _alpha
          ..clear()
          ..addAll(alpha);
        _x
          ..clear()
          ..addAll(x);
        _y
          ..clear()
          ..addAll(y);
        _hideStarts = Map.unmodifiable(starts);
        _choices = choices == null
            ? null
            : StoryChoicePresentation.fromSnapshot(choices);
      },
    );
  }

  void restore(
    NativeStoryFrontUiStateSnapshot snapshot, {
    NativeStoryUpdateStamp? stamp,
  }) {
    _current(snapshot.sourceEpoch);
    if (!identical(snapshot._owner, _checkpointOwner) ||
        snapshot.sourceHash != source.hash ||
        snapshot.nextBindingHash != source.nextBindingHash ||
        snapshot.widgetId != source.widgetId ||
        (stamp != null && stamp.sourceEpoch != sourceEpoch)) {
      throw const FormatException('front_snapshot_source');
    }
    snapshot._restore(stamp);
  }

  void quiesce() {
    _current(sourceEpoch);
    final state = snapshot();
    restore(state);
  }

  void _current(int epoch) {
    if (_closed || epoch != sourceEpoch) {
      throw const StoryPresentationCancelled('front_source_epoch');
    }
  }

  void showCaption(String value, int epoch) {
    _current(epoch);
    _caption = value;
    _captionActive = _captionsEnabled && value.isNotEmpty;
    revision++;
  }

  void clearCaption(int epoch) {
    _current(epoch);
    _caption = '';
    _captionActive = false;
    _next = false;
    revision++;
  }

  void hideCaption(int epoch) {
    _current(epoch);
    _captionActive = false;
    revision++;
  }

  void setCaptionsEnabled(bool enabled, int epoch) {
    _current(epoch);
    _captionsEnabled = enabled;
    _captionActive = enabled && _caption.isNotEmpty;
    revision++;
  }

  void setNext(bool visible, int epoch) {
    _current(epoch);
    if (_next == visible) return;
    _next = visible;
    revision++;
  }

  void showChoices(
    StoryChoicePresentation presentation,
    List<String> actualLocalizedTexts,
    int epoch,
  ) {
    _current(epoch);
    if (presentation.sourceEpoch != epoch ||
        presentation.choices.length != actualLocalizedTexts.length ||
        presentation.choices.length > source.choiceItemIds.length) {
      throw const FormatException('front_actual_choices');
    }
    _choices?.cancel('choice_replaced');
    _choices = presentation;
    _choiceTexts = List.unmodifiable(actualLocalizedTexts);
    _next = false;
    _hiding = false;
    _elapsed = 0;
    for (final itemId in source.choiceItemIds) {
      final item = source.records[itemId]!['data'] as Map;
      _alpha[(item['_canvasGroup'] as Map)['m_PathID'] as String] = 0;
    }
    revision++;
  }

  bool select(int value, int epoch) {
    _current(epoch);
    final selected = _choices?.select(value, epoch) ?? false;
    if (selected) {
      _hideStarts = Map.unmodifiable(_alpha);
      _hiding = true;
      _elapsed = 0;
      revision++;
    }
    return selected;
  }

  /// Called after the actual source Out sequences have finished on the one
  /// captured UI update stream, before the command's destination is returned.
  bool actualChoiceHideCompleted(int epoch) {
    _current(epoch);
    final completed = _choices?.actualHideCompleted(epoch) ?? false;
    if (completed) {
      _choiceTexts = const [];
      revision++;
    }
    return completed;
  }

  Map<String, String> get textByRubyId => Map.unmodifiable({
    source.subtitlesRubyId: _caption,
    source.locationRubyId: _location,
    if (_choices case final presentation?)
      for (var i = 0; i < presentation.choices.length; i++)
        ((source.records[source.choiceItemIds[i]]!['data'] as Map)['_text']
                as Map)['m_PathID']
            as String: _choiceTexts.isEmpty
            ? ''
            : _choiceTexts[i],
  });

  /// Only the host's actual captured update pair advances the source tweens.
  void actualUiPhase(NativeStoryUpdateStamp stamp) {
    _current(stamp.sourceEpoch);
    final old = _stamp;
    if (old != null &&
        (stamp.updateIndex < old.updateIndex || stamp.storyUs < old.storyUs)) {
      throw const FormatException('front_update_order');
    }
    if (old != null && stamp.updateIndex == old.updateIndex) {
      if (stamp.storyUs != old.storyUs) {
        throw const FormatException('front_update_pair');
      }
      return;
    }
    _stamp = stamp;
    if (locationVisible &&
        old != null &&
        !stamp.paused &&
        _locationElapsed < source.locationAnimation!.duration) {
      _locationElapsed = _f(
        _locationElapsed +
            _f((stamp.storyUs - old.storyUs) / 1000000 * stamp.speed),
      );
      _sampleLocation();
      revision++;
    }
    if (_choices == null ||
        !_choices!.nextButtonLocked ||
        old == null ||
        stamp.paused) {
      return;
    }
    final dt = _f(_f((stamp.storyUs - old.storyUs) / 1000000) * stamp.speed);
    _elapsed = _f(_elapsed + dt);
    final view = source.controller('Choice');
    if (view['_showIsAscendingOrder'] != 1 ||
        view['_hideIsAscendingOrder'] != 1) {
      throw UnsupportedError('front_choice_order_subset');
    }
    final interval =
        (view[_hiding ? '_animationIntervalOut' : '_animationIntervalIn']
                as num)
            .toDouble();
    final count = _choices!.choices.length;
    var allDone = true;
    for (var i = 0; i < count; i++) {
      final item = source.records[source.choiceItemIds[i]]!['data'] as Map;
      final sequenceId =
          (item[_hiding ? '_outAnimation' : '_inAnimation'] as Map)['m_PathID'];
      final sequence = source.records[sequenceId]!['data'] as Map;
      final time = _f(_elapsed - _f(interval * i));
      for (final raw in sequence['_list'] as List) {
        final command = raw as Map;
        if (command['_commandType'] != 0 || command['_duration'] != 0) {
          throw UnsupportedError('front_choice_sequence_subset');
        }
        final animation =
            source.records[(command['_tweenAnimation']
                    as Map)['m_PathID']]!['data']
                as Map;
        if (animation['easeType'] != 6 ||
            animation['loops'] != 1 ||
            animation['isRelative'] != 0 ||
            animation['delay'] != 0) {
          throw UnsupportedError('front_choice_animation_subset');
        }
        final duration = (animation['duration'] as num).toDouble();
        final t = _f((time / duration).clamp(0, 1));
        final eased = _f(-_f(t * _f(t - 2)));
        final target = (animation['target'] as Map)['m_PathID'] as String;
        if (time < duration) allDone = false;
        if (animation['animationType'] == 7) {
          final targetAlpha = (animation['endValueFloat'] as num).toDouble();
          final start = _hiding ? (_hideStarts[target] ?? 0.0) : 0.0;
          _alpha[target] = _f(start + _f(_f(targetAlpha - start) * eased));
        } else if (animation['animationType'] == 2 &&
            animation['isFrom'] == 1) {
          final tr = source.records[target]!['data'] as Map;
          final start = ((animation['endValueV3'] as Map)['y'] as num)
              .toDouble();
          final end = ((tr['m_AnchoredPosition'] as Map)['y'] as num)
              .toDouble();
          _y[target] = _f(start + _f(_f(end - start) * eased));
        } else {
          throw UnsupportedError('front_choice_animation_type');
        }
      }
    }
    revision++;
    if (_hiding && allDone) actualChoiceHideCompleted(sourceEpoch);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _choices?.cancel('front_source_closed');
    _captionActive = false;
    _next = false;
  }
}

final class NativeStoryFrontUiStateSnapshot {
  NativeStoryFrontUiStateSnapshot._(
    this._owner,
    this.sourceEpoch,
    this.sourceHash,
    this.nextBindingHash,
    this.widgetId,
    this._data,
    this._restore,
  );
  final int sourceEpoch;
  final Object _owner;
  final String sourceHash, widgetId;
  final String? nextBindingHash;
  final Map<String, Object?> _data;
  Map<String, Object?> toData() =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(_data)) as Map);
  final void Function(NativeStoryUpdateStamp?) _restore;
}
