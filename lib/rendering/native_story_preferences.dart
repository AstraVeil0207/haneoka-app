import 'package:shared_preferences/shared_preferences.dart';

/// User controls shared by the native story's transport and consumers.
final class NativeStoryPreferences {
  NativeStoryPreferences._(this._store);
  final SharedPreferences _store;
  static const _prefix = 'nativeStory.';

  static Future<NativeStoryPreferences> load() async =>
      NativeStoryPreferences._(await SharedPreferences.getInstance());

  bool get instantText => _store.getBool('${_prefix}instantText') ?? false;
  bool get subtitlesEnabled =>
      _store.getBool('${_prefix}subtitlesEnabled') ?? true;
  bool get bgmEnabled => _store.getBool('${_prefix}bgmEnabled') ?? true;
  bool get expanded => _store.getBool('${_prefix}expanded') ?? true;
  bool get continuous => _store.getBool('${_prefix}continuous') ?? false;
  double _number(String key, double fallback, double min, double max) {
    final value = _store.getDouble('$_prefix$key') ?? fallback;
    return value.isFinite ? value.clamp(min, max) : fallback;
  }

  double get masterVolume => _number('masterVolume', 1, 0, 1);
  double get bgmVolume => _number('bgmVolume', 1, 0, 1);
  double get autoDelay => _number('autoDelay', .5, 0, 30);
  double get textSize => _number('textSize', 1, .5, 2);
  double get speed => _number('speed', 1, .25, 4);

  Future<void> setInstantText(bool value) => _boolean('instantText', value);
  Future<void> setSubtitlesEnabled(bool value) =>
      _boolean('subtitlesEnabled', value);
  Future<void> setBgmEnabled(bool value) => _boolean('bgmEnabled', value);
  Future<void> setExpanded(bool value) => _boolean('expanded', value);
  Future<void> setContinuous(bool value) => _boolean('continuous', value);
  Future<void> _boolean(String key, bool value) async {
    await _store.setBool('$_prefix$key', value);
  }

  Future<void> setMasterVolume(double value) =>
      _setNumber('masterVolume', value, 0, 1);
  Future<void> setBgmVolume(double value) =>
      _setNumber('bgmVolume', value, 0, 1);
  Future<void> setAutoDelay(double value) =>
      _setNumber('autoDelay', value, 0, 30);
  Future<void> setTextSize(double value) =>
      _setNumber('textSize', value, .5, 2);
  Future<void> setSpeed(double value) => _setNumber('speed', value, .25, 4);
  Future<void> _setNumber(
    String key,
    double value,
    double min,
    double max,
  ) async {
    if (!value.isFinite) throw ArgumentError.value(value, key);
    await _store.setDouble('$_prefix$key', value.clamp(min, max));
  }
}
