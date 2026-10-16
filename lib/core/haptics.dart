import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Device output stays outside chart conversion and rendering. No timers or
/// queued pulses survive a playback discontinuity.
final class DeviceHaptics {
  static const _channel = MethodChannel('org.haneoka/haptics');
  bool supported = false;
  bool _busy = false;
  int _epoch = 0;
  final Map<int, Map<String, Object?>> _recipes = {};

  Future<void> initialize(Iterable<Map<String, Object?>> recipes) async {
    for (final recipe in recipes) {
      _recipes[recipe['_id'] as int] = recipe;
    }
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      supported = await _channel.invokeMethod<bool>('supported') ?? false;
    } on MissingPluginException {
      supported = false;
    } on PlatformException {
      supported = false;
    }
  }

  Future<void> emit(int recipeId) async {
    final recipe = _recipes[recipeId];
    if (!supported || _busy || recipe == null || recipeId == 1) return;
    _busy = true;
    final epoch = _epoch;
    try {
      if (epoch == _epoch) await _channel.invokeMethod<void>('emit', recipe);
    } on PlatformException catch (error) {
      debugPrint('HANEOKA_HAPTIC_ERROR ${error.code}');
    } on MissingPluginException {
      supported = false;
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    ++_epoch;
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (error) {
      debugPrint('HANEOKA_HAPTIC_ERROR ${error.code}');
    } on MissingPluginException {
      supported = false;
    }
  }
}
