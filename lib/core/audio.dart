import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// A track the dock can show: what is playing and where it came from.
class Track {
  const Track({
    required this.id,
    required this.url,
    required this.title,
    this.subtitle = '',
    this.artwork,
  });
  final String id;
  final String url;
  final String title;
  final String subtitle;
  final String? artwork;
}

/// One player for the whole app, as the website's audio dock: a song's play
/// button toggles it, Play all queues the visible list.
class AudioService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  List<Track> _queue = const [];
  int _index = -1;
  bool _playing = false;

  AudioService() {
    _player.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (playing != _playing) {
        _playing = playing;
        notifyListeners();
      }
    });
    _player.onPlayerComplete.listen((_) => next());
  }

  Track? get current =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;
  bool get playing => _playing;
  bool get hasNext => _index + 1 < _queue.length;
  Stream<Duration> get position => _player.onPositionChanged;
  Stream<Duration> get duration => _player.onDurationChanged;

  bool isPlaying(String id) => _playing && current?.id == id;

  /// Plays [track], or pauses it when it is the one playing.
  Future<void> toggle(Track track) async {
    if (current?.id == track.id) {
      return _playing ? _player.pause() : _player.resume();
    }
    await playQueue([track]);
  }

  Future<void> playQueue(List<Track> tracks, [int start = 0]) async {
    if (tracks.isEmpty) return;
    _queue = List.unmodifiable(tracks);
    _index = start;
    notifyListeners();
    await _player.play(UrlSource(_queue[_index].url));
  }

  Future<void> next() async {
    if (!hasNext) {
      _playing = false;
      notifyListeners();
      return;
    }
    _index++;
    notifyListeners();
    await _player.play(UrlSource(_queue[_index].url));
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.resume();
  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> stop() async {
    await _player.stop();
    _queue = const [];
    _index = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
