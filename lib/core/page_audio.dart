import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_track.dart';
import 'audio_output.dart';
import 'playback_focus.dart';

/// Page-owned transport. It has no queue, persistence or system media item.
final class PageAudio extends ChangeNotifier {
  PageAudio({this.onFocusInterrupted, bool pollPosition = true})
    : _output = AudioOutput(pollPosition: pollPosition) {
    _subscriptions.addAll([
      _output.onPlayerStateChanged.listen((state) {
        if (_disposed) return;
        playing = state == PlayerState.playing;
        notifyListeners();
      }),
      _output.onPlayerComplete.listen((_) {
        if (_disposed) return;
        completed = true;
        playing = false;
        notifyListeners();
        if (loop) unawaited(seek(Duration.zero).then((_) => resume()));
      }),
      _output.onPositionChanged.listen((value) {
        if (!_disposed) position.value = value;
      }),
      _output.onDurationChanged.listen((value) {
        if (!_disposed) duration.value = value;
      }),
      _output.errors.listen((value) {
        if (_disposed) return;
        error = value;
        playing = false;
        notifyListeners();
      }),
    ]);
  }
  final AudioOutput _output;
  final Future<void> Function()? onFocusInterrupted;
  late final _focus = PlaybackFocus(onFocusInterrupted ?? pause);
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final position = ValueNotifier(Duration.zero);
  final duration = ValueNotifier(Duration.zero);
  Track? current;
  bool playing = false, completed = false, loop = false, _disposed = false;
  double volume = 1;
  int revision = 0, _generation = 0;
  Object? error;
  String? _loadedUrl;
  bool get active =>
      !_disposed && current != null && _loadedUrl == current!.url;
  String get clockBackend => _output.clockBackend;
  Future<void> _requests = Future.value();

  Future<void> _perform(
    Future<void> Function() operation, {
    bool replace = false,
  }) {
    if (replace) _output.cancelPendingLoad();
    final generation = replace ? ++_generation : _generation;
    final request = _requests.then((_) async {
      if (_disposed || generation != _generation) return;
      error = null;
      await operation();
    });
    _requests = request.catchError((Object exception) {
      if (_disposed || generation != _generation) return;
      error = exception;
      playing = false;
      notifyListeners();
    });
    return request;
  }

  Future<void> loadPaused(Track track) => _perform(() async {
    current = track;
    _loadedUrl = null;
    completed = false;
    playing = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    ++revision;
    await _output.play(UrlSource(track.url), shouldPlay: false);
    _loadedUrl = track.url;
    notifyListeners();
  }, replace: true);

  Future<void> configure({required double rate, required double volume}) =>
      _perform(() async {
        this.volume = (volume / 100).clamp(0, 1);
        await _output.setRate(rate);
        await _output.setVolume(this.volume);
      });

  /// Holds the page's existing media ownership during a pre-music presentation.
  Future<void> activate(Future<void> Function() action) =>
      _focus.activate(action);
  Future<void> resume() => activate(() => _perform(_output.resume));
  Future<void> pause() => _perform(_output.pause);
  Future<void> seek(Duration value) => _perform(() async {
    completed = false;
    ++revision;
    await _output.seek(value);
    position.value = value;
  });
  Future<Duration?> samplePosition() async {
    if (_disposed) return null;
    if (completed && duration.value > Duration.zero) {
      position.value = duration.value;
      return duration.value;
    }
    final value = await _output.samplePosition();
    if (!_disposed && value != null) position.value = value;
    return value;
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _output.cancelPendingLoad();
    _focus.close();
    ++_generation;
    await _requests;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _output.dispose();
    position.dispose();
    duration.dispose();
    super.dispose();
  }
}
