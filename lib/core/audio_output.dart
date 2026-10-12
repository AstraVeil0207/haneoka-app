import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:media_kit/media_kit.dart' as media;

/// Linux uses the bundled media backend so MP3 playback does not depend on
/// the desktop's optional GStreamer codecs. Other platforms retain their
/// native audio focus and speech content type.
class AudioOutput {
  AudioOutput() {
    if (!_usesMedia) _audio = AudioPlayer();
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

  Future<void> setAudioContext(AudioContext context) async {
    await _audio?.setAudioContext(context);
  }

  Future<void> play(UrlSource source, {bool shouldPlay = true}) async {
    if (_usesMedia) {
      await _ensureMedia().open(media.Media(source.url), play: shouldPlay);
    } else {
      await _audio!.setSource(source);
      if (shouldPlay) await _audio!.resume();
    }
  }

  Future<void> setVolume(double value) => _usesMedia
      ? _media?.setVolume(value * 100) ?? Future.value()
      : _audio!.setVolume(value);
  Future<void> pause() =>
      _usesMedia ? _media?.pause() ?? Future.value() : _audio!.pause();
  Future<void> resume() =>
      _usesMedia ? _media?.play() ?? Future.value() : _audio!.resume();
  Future<void> seek(Duration position) => _usesMedia
      ? _media?.seek(position) ?? Future.value()
      : _audio!.seek(position);
  Future<void> stop() =>
      _usesMedia ? _media?.stop() ?? Future.value() : _audio!.stop();

  Future<void> dispose() async {
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _audio?.dispose();
    await _media?.dispose();
    await _states.close();
    await _completed.close();
    await _errors.close();
    await _positions.close();
    await _durations.close();
  }
}
