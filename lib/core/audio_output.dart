import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:media_kit/media_kit.dart' as media;

import 'media_lifecycle.dart';
import 'media_kit_transport.dart';

/// Linux uses the bundled media backend so MP3 playback does not depend on
/// the desktop's optional GStreamer codecs. Other platforms retain their
/// native audio focus and speech content type.
class AudioOutput {
  AudioOutput({bool pollPosition = true}) {
    MediaLifecycle.requireOpen();
    if (!_usesMedia) {
      final player = _audio = AudioPlayer();
      player.positionUpdater = pollPosition
          ? FramePositionUpdater(getPosition: samplePosition)
          : null;
    }
    MediaLifecycle.register(this, dispose);
  }

  final bool _usesMedia = Platform.isLinux;

  media.Player _ensureMedia() {
    if (_media != null) return _media!;
    final player = _media = media.Player();
    _subscriptions.add(
      player.stream.playing.listen((playing) {
        if (!_disposed) {
          _states.add(playing ? PlayerState.playing : PlayerState.paused);
        }
      }, onError: _report),
    );
    _subscriptions.add(
      player.stream.completed.listen((completed) {
        if (completed && !_disposed) {
          _states.add(PlayerState.completed);
          _completed.add(null);
        }
      }, onError: _report),
    );
    _subscriptions.add(
      player.stream.position.listen((position) {
        if (_mediaReady) _lastObservedPosition = position;
        if (!_disposed) _positions.add(position);
      }, onError: _report),
    );
    _subscriptions.add(
      player.stream.duration.listen((duration) {
        if (!_disposed) _durations.add(duration);
      }, onError: _report),
    );
    _subscriptions.add(player.stream.error.listen(_report, onError: _report));
    return player;
  }

  AudioPlayer? _audio;
  media.Player? _media;
  bool _disposed = false;
  Future<void>? _disposing;
  final _work = <Future<void>>{};
  Future<T> _track<T>(Future<T> work) {
    final settled = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _work.add(settled);
    unawaited(settled.then((_) => _work.remove(settled)));
    return work;
  }

  Future<void> _run(Future<void> Function() operation) =>
      _disposed ? Future.value() : _track(operation());

  int _generation = 0;
  Completer<void>? _mediaLoadInterrupted;
  void _interruptMediaLoad() {
    final loading = _mediaLoadInterrupted;
    _mediaLoadInterrupted = null;
    if (loading != null && !loading.isCompleted) loading.complete();
  }

  /// Replacing or closing a queued source releases its metadata wait at once.
  void cancelPendingLoad() {
    ++_generation;
    _interruptMediaLoad();
  }

  String? _inputUri;
  Duration? _lastObservedPosition;
  bool get _mediaReady {
    final playlist = _media?.state.playlist;
    return !_disposed &&
        playlist != null &&
        playlist.index >= 0 &&
        playlist.index < playlist.medias.length &&
        playlist.medias[playlist.index].uri == _inputUri;
  }

  String get clockBackend => _usesMedia
      ? 'media_kit.NativePlayer.audio-pts/time-pos'
      : 'audioplayers.getCurrentPosition';
  bool get completed => _mediaReady && _media!.state.completed;

  Future<Duration?>? _positionSample;
  int _positionSampleGeneration = -1;
  Future<Duration?> samplePosition() {
    final previous = _positionSample;
    if (previous != null && _positionSampleGeneration == _generation) {
      return previous;
    }
    late final Future<Duration?> pending;
    pending = _track(_samplePosition()).whenComplete(() {
      if (identical(_positionSample, pending)) _positionSample = null;
    });
    _positionSampleGeneration = _generation;
    return _positionSample = pending;
  }

  Future<Duration?> _samplePosition() async {
    if (_disposed) {
      return null;
    }
    final generation = _generation;
    if (!_usesMedia) {
      final value = await _audio!.getCurrentPosition();
      return !_disposed && generation == _generation ? value : null;
    }
    if (!_mediaReady) return null;
    if (_media!.state.completed && _media!.state.duration > Duration.zero) {
      return _media!.state.duration;
    }
    final value = await sampleMediaKitAudioPosition(_media!);
    if (!_mediaReady ||
        generation != _generation ||
        (value != null && (!value.isFinite || value < 0))) {
      return null;
    }
    if (value == null) return completed ? _lastObservedPosition : null;
    final position = Duration(
      microseconds: (value * Duration.microsecondsPerSecond).round(),
    );
    _lastObservedPosition = position;
    return position;
  }

  Future<void> setRate(double value) => _run(
    () => _usesMedia
        ? _media?.setRate(value) ?? Future.value()
        : _audio!.setPlaybackRate(value),
  );
  final _states = StreamController<PlayerState>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];

  void _report(Object error) {
    if (!_disposed) _errors.add(error);
  }

  Stream<Object> get errors => _errors.stream;
  Stream<PlayerState> get onPlayerStateChanged => _usesMedia
      ? _states.stream
      : _audio!.onPlayerStateChanged.handleError(_report);
  Stream<void> get onPlayerComplete => _usesMedia
      ? _completed.stream
      : _audio!.onPlayerComplete.handleError(_report);
  Stream<Duration> get onPositionChanged => _usesMedia
      ? _positions.stream
      : _audio!.onPositionChanged.handleError(_report);
  Stream<Duration> get onDurationChanged => _usesMedia
      ? _durations.stream
      : _audio!.onDurationChanged.handleError(_report);

  Future<void> setAudioContext(AudioContext context) =>
      _run(() => _audio?.setAudioContext(context) ?? Future.value());

  Future<void> play(UrlSource source, {bool shouldPlay = true}) =>
      _run(() => _play(source, shouldPlay: shouldPlay));
  Future<void> _play(UrlSource source, {required bool shouldPlay}) async {
    _interruptMediaLoad();
    final generation = ++_generation;
    _lastObservedPosition = null;
    if (_usesMedia) {
      final item = media.Media(source.url);
      _inputUri = item.uri;
      final player = _ensureMedia();
      final interrupted = _mediaLoadInterrupted = Completer<void>();
      try {
        await player.open(item, play: false);
        if (_disposed || generation != _generation) return;
        await waitForMediaKitMetadata(player, interrupted: interrupted.future);
        if (!_disposed && generation == _generation && shouldPlay) {
          await player.play();
        }
      } finally {
        if (identical(_mediaLoadInterrupted, interrupted)) {
          _mediaLoadInterrupted = null;
        }
      }
    } else {
      await _audio!.setSource(source);
      if (!_disposed && generation == _generation && shouldPlay) {
        await _audio!.resume();
      }
    }
  }

  Future<void> setVolume(double value) => _run(
    () => _usesMedia
        ? _media?.setVolume(value * 100) ?? Future.value()
        : _audio!.setVolume(value),
  );
  Future<void> pause() => _run(
    () => _usesMedia ? _media?.pause() ?? Future.value() : _audio!.pause(),
  );
  Future<void> resume() => _run(
    () => _usesMedia ? _media?.play() ?? Future.value() : _audio!.resume(),
  );
  Future<void> seek(Duration position) => _run(() => _seek(position));
  Future<void> _seek(Duration position) {
    _interruptMediaLoad();
    ++_generation;
    return _usesMedia
        ? _media?.seek(position) ?? Future.value()
        : _audio!.seek(position);
  }

  Future<void> stop() => _run(_stop);
  Future<void> _stop() {
    _interruptMediaLoad();
    ++_generation;
    _inputUri = null;
    return _usesMedia ? _media?.stop() ?? Future.value() : _audio!.stop();
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    _interruptMediaLoad();
    ++_generation;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    while (_work.isNotEmpty) {
      await Future.wait(_work.toList());
    }
    await _audio?.dispose();
    await _media?.dispose();
    await _states.close();
    await _completed.close();
    await _errors.close();
    await _positions.close();
    await _durations.close();
    MediaLifecycle.unregister(this);
  }
}
