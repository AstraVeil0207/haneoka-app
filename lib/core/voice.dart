import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import 'audio_output.dart';
import 'playback_focus.dart';

class VoiceClip {
  const VoiceClip({required this.id, required this.url});
  final String id;
  final String url;
}

/// Page-owned speech playback. It never enters the music dock or song queue.
class VoicePlayback extends ChangeNotifier {
  final _player = AudioOutput();
  late final _focus = PlaybackFocus(stop);
  final _subscriptions = <StreamSubscription<dynamic>>[];
  List<VoiceClip> _clips = const [];
  int _index = -1;
  bool _playing = false;
  bool _disposed = false;
  int _generation = 0;
  late final Future<void> _ready;
  Object? error;
  static final _instances = <VoicePlayback>{};
  static Future<void> stopAll() =>
      Future.wait([for (final voice in _instances) voice.stop()]);

  VoicePlayback() {
    _instances.add(this);
    _subscriptions.add(
      _player.errors.listen((exception) {
        if (_disposed) return;
        error = exception;
        _playing = false;
        notifyListeners();
      }),
    );
    _ready = _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.speech,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
      ),
    );
    _subscriptions.add(
      _player.onPlayerStateChanged.listen((state) {
        _playing = state == PlayerState.playing;
        if (!_disposed) notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.onPlayerComplete.listen((_) {
        if (_index + 1 < _clips.length) {
          _index++;
          unawaited(_play());
        } else {
          _playing = false;
          if (!_disposed) notifyListeners();
        }
      }),
    );
  }
  bool isPlaying(String id) =>
      _playing &&
      _index >= 0 &&
      _index < _clips.length &&
      _clips[_index].id == id;
  Future<void> toggle(VoiceClip clip) async {
    if (isPlaying(clip.id)) {
      await stop();
      return;
    }
    await playAll([clip]);
  }

  Future<void> playAll(List<VoiceClip> clips) async {
    if (clips.isEmpty || _disposed) return;
    final generation = ++_generation;
    await _focus.activate(() async {
      if (_disposed || generation != _generation) return;
      _clips = List.unmodifiable(clips);
      _index = 0;
      await _play();
    });
  }

  Future<void> _play() async {
    if (_disposed || _index < 0 || _index >= _clips.length) return;
    final generation = _generation;
    final url = _clips[_index].url;
    error = null;
    try {
      await _ready;
      if (_disposed || generation != _generation) return;
      await _player.play(UrlSource(url));
    } catch (e) {
      error = e;
      _playing = false;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> stop() async {
    if (_disposed) return;
    _generation++;
    _clips = const [];
    _index = -1;
    _playing = false;
    try {
      await _player.stop();
    } catch (e) {
      error = e;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _focus.close();
    _generation++;
    _instances.remove(this);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
