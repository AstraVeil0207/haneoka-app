import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'media_lifecycle.dart';

final class EffectSoundLayer {
  const EffectSoundLayer(
    this.uri, {
    this.gain = 1,
    this.loopStart,
    this.loopEnd,
  });
  final Uri uri;
  final double gain;
  final Duration? loopStart, loopEnd;
}

/// Short predecoded samples and looping layers. Hosts supply assets and cues;
/// this backend has no song queue, media notification or advancing game clock.
final class SoundEffectBank {
  SoundEffectBank() {
    MediaLifecycle.requireOpen();
    MediaLifecycle.register(this, close);
  }

  static Future<void>? _initialization;
  static int _users = 0, _nextOwner = 0;
  final _engine = SoLoud.instance;
  final _owner = _nextOwner++;
  final _sources = <Uri, AudioSource>{};
  final _layers = <String, List<(AudioSource, EffectSoundLayer)>>{};
  final _oneShots = <SoundHandle>{};
  final _loops = <(SoundHandle, double)>[];
  bool _ready = false, _closed = false;
  Future<void>? _opening, _closing;

  Future<void> open(
    Map<String, List<EffectSoundLayer>> assets,
    Future<Uint8List> Function(Uri) fetch,
  ) => _opening ??= _open(assets, fetch);

  Future<void> _open(
    Map<String, List<EffectSoundLayer>> assets,
    Future<Uint8List> Function(Uri) fetch,
  ) async {
    try {
      await (_initialization ??= _engine.init());
    } catch (_) {
      _initialization = null;
      rethrow;
    }
    if (_closed) return;
    ++_users;
    _ready = true;
    try {
      for (final entry in assets.entries) {
        final layers = <(AudioSource, EffectSoundLayer)>[];
        for (final layer in entry.value) {
          if (_closed) return;
          var source = _sources[layer.uri];
          if (source == null) {
            final bytes = await fetch(layer.uri);
            if (_closed) return;
            source = await _engine.loadMem(
              'effect:$_owner:${layer.uri}',
              bytes,
            );
            _sources[layer.uri] = source;
          }
          layers.add((source, layer));
        }
        _layers[entry.key] = layers;
      }
    } catch (_) {
      await _closeResources();
      rethrow;
    }
  }

  void emit(String key, double volume) {
    if (!_ready || _closed || volume <= 0) return;
    _oneShots.removeWhere((handle) => !_engine.getIsValidVoiceHandle(handle));
    for (final (source, layer)
        in _layers[key] ?? const <(AudioSource, EffectSoundLayer)>[]) {
      _oneShots.add(_engine.play(source, volume: volume * layer.gain));
    }
  }

  void setLoop(
    String key,
    bool active,
    double volume, {
    bool retainSilent = false,
  }) {
    if (!_ready || _closed) return;
    if (!active || (volume <= 0 && !retainSilent)) {
      stopLoop();
      return;
    }
    if (_loops.isNotEmpty) {
      for (final (handle, gain) in _loops) {
        _engine.setVolume(handle, volume * gain);
      }
      return;
    }
    for (final (source, layer)
        in _layers[key] ?? const <(AudioSource, EffectSoundLayer)>[]) {
      final handle = _engine.play(
        source,
        volume: volume * layer.gain,
        looping: true,
        loopingStartAt: layer.loopStart ?? Duration.zero,
        loopingEndAt: layer.loopEnd,
      );
      _loops.add((handle, layer.gain));
    }
  }

  void stopLoop() {
    if (!_ready) return;
    for (final (handle, _) in _loops) {
      unawaited(_engine.stop(handle));
    }
    _loops.clear();
  }

  void setPaused(bool paused) {
    if (!_ready || _closed) return;
    _oneShots.removeWhere((handle) => !_engine.getIsValidVoiceHandle(handle));
    for (final handle in [
      ..._oneShots,
      for (final (handle, _) in _loops) handle,
    ]) {
      _engine.setPause(handle, paused);
    }
  }

  void fadeLoops(Duration duration) {
    if (!_ready || _closed) return;
    if (duration <= Duration.zero) {
      stopLoop();
      return;
    }
    for (final (handle, _) in _loops) {
      _engine.fadeVolume(handle, 0, duration);
      _engine.scheduleStop(handle, duration);
      _oneShots.add(handle);
    }
    _loops.clear();
  }

  Future<void> stop() async {
    if (!_ready) return;
    final handles = [..._oneShots, for (final (handle, _) in _loops) handle];
    _oneShots.clear();
    _loops.clear();
    await Future.wait([for (final handle in handles) _engine.stop(handle)]);
  }

  Future<void> close() => _closing ??= _closeAfterOpen();

  Future<void> _closeAfterOpen() async {
    try {
      await _opening;
    } catch (_) {
      // The failed open already retires any successfully decoded sources.
    }
    try {
      await _closeResources();
    } finally {
      MediaLifecycle.unregister(this);
    }
  }

  Future<void> _closeResources() async {
    if (_closed) return;
    _closed = true;
    if (!_ready) return;
    await stop();
    for (final source in _sources.values) {
      await _engine.disposeSource(source);
    }
    _sources.clear();
    _layers.clear();
    _ready = false;
    if (--_users == 0) {
      _engine.deinit();
      _initialization = null;
    }
  }

  Map<String, Object?> get observation => {
    'decodedSources': _sources.length,
    'loopVoices': _loops.length,
    'oneShotVoices': _oneShots.where(_engine.getIsValidVoiceHandle).length,
    'backend': 'SoLoud predecoded samples',
  };
}
