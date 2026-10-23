import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_output.dart';
import 'account_resource.dart';
import 'resource_file_cache.dart';
import 'media_lifecycle.dart';
import 'audio_track.dart';
import 'playback_focus.dart';
export 'audio_track.dart';

/// Mirrors src/lit/runtime/audio-dock.ts: enqueueTrack, playTrack and transport.
enum PlaybackMode { sequential, repeatAll, repeatOne, shuffle }

class AudioService extends ChangeNotifier {
  final AudioOutput _player = AudioOutput();
  late final _focus = PlaybackFocus(pause);
  List<Track> _queue = const [];
  int _index = -1;
  bool _playing = false;
  bool _disposed = false;
  bool _completed = false;
  String? _loadedUrl;
  int _generation = 0;
  Object? error;
  Future<void> _requests = Future.value();
  ResourceFileLease? _trackLease;
  Completer<void>? _preparation;
  String? _resourceOwner;
  Future<void>? _closing;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  /// Position and length of the current track, for the progress ring and seek row.
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);

  final SharedPreferences? _prefs;
  PlaybackMode mode = PlaybackMode.repeatAll;
  double volume = 0.82;
  bool collapsed = false;
  bool compact = false;
  List<Track> get queue => _queue;
  int get index => _index;
  Duration _restoredPosition = Duration.zero;
  AudioService([this._prefs]) {
    _restore();
    _resourceOwner = AccountResources.instance.owner;
    _subscriptions.add(
      AccountResources.instance.changes.listen((_) {
        unawaited(_ownerChanged());
      }),
    );
    MediaLifecycle.register(this, close);
    _subscriptions.add(
      _player.errors.listen((exception) {
        if (_disposed) return;
        error = exception;
        _playing = false;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.onPositionChanged.listen((value) {
        if (!_disposed) {
          position.value = value;
        }
      }),
    );
    _subscriptions.add(
      _player.onDurationChanged.listen((value) {
        if (!_disposed) {
          duration.value = value;
          if (_restoredPosition > Duration.zero && value > Duration.zero) {
            final restored = _restoredPosition;
            _restoredPosition = Duration.zero;
            unawaited(seek(restored));
          }
        }
      }),
    );
    _subscriptions.add(
      _player.onPlayerStateChanged.listen((state) {
        if (_disposed) return;
        final playing = state == PlayerState.playing;
        if (playing != _playing) {
          _playing = playing;
          _persist();
          notifyListeners();
        }
      }),
    );
    _subscriptions.add(
      _player.onPlayerComplete.listen((_) {
        if (!_disposed) {
          _completed = true;
          unawaited(next(automatic: true));
        }
      }),
    );
    if (current != null) {
      unawaited(_play(current!, reset: false, shouldPlay: false));
    }
  }

  void saveSnapshot() => _persist();
  void setExpanded(bool expanded) {
    collapsed = !expanded;
    _persist();
    notifyListeners();
  }

  Future<void> _perform(
    Future<void> Function() operation, {
    bool replace = false,
  }) {
    if (replace) {
      _player.cancelPendingLoad();
      final p = _preparation;
      _preparation = null;
      if (p != null && !p.isCompleted) p.complete();
    }
    final generation = replace ? ++_generation : _generation;
    return _requests = _requests.then((_) async {
      if (_disposed || generation != _generation) return;
      error = null;
      try {
        await operation();
      } catch (exception) {
        if (!_disposed && generation == _generation) {
          error = exception;
          _playing = false;
          notifyListeners();
        }
      }
    });
  }

  Future<void> _play(Track track, {bool reset = true, bool shouldPlay = true}) {
    if (reset) {
      _restoredPosition = Duration.zero;
      position.value = Duration.zero;
    }
    duration.value = Duration.zero;
    _completed = false;
    _loadedUrl = null;
    Future<void> start() => _perform(() async {
      final generation = _generation, uri = Uri.parse(track.url);
      ResourceFileLease? lease;
      try {
        if (isAccountResource(uri)) {
          final preparation = _preparation = Completer<void>();
          lease = await resourceFileCache.acquire(
            uri,
            kind: ResourceFileKind.media,
            cancelled: preparation.future,
          );
        }
        if (_disposed || generation != _generation) return;
        await _player.play(
          UrlSource(lease?.file.uri.toString() ?? track.url),
          shouldPlay: shouldPlay,
        );
        if (_disposed || generation != _generation) return;
        final previous = _trackLease;
        _trackLease = lease;
        lease = null;
        await previous?.release();
      } finally {
        await lease?.release();
      }
      await _player.setVolume(volume);
      _loadedUrl = track.url;
      if (_restoredPosition == Duration.zero) _persist();
    }, replace: true);
    return shouldPlay ? _focus.activate(start) : start();
  }

  Track? get current =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;
  bool get playing => _playing;
  bool get hasNext => _queue.isNotEmpty;
  bool get hasPrevious => _queue.isNotEmpty;

  String _key(Track track) {
    if (track.songKey != null) return track.songKey!;
    final uri = Uri.tryParse(track.url);
    final path = uri?.path ?? '';
    final gbp =
        path.startsWith('/api/v1/garupa/bestdori/') ||
        uri?.host == 'bestdori.com';
    final native = RegExp(r'^/(?:runtime|assets)/(?:jp|intl)(?:-cbt)?/')
        .hasMatch(path);
    final id = RegExp(r'^(\d+)(?:-\d+)?$')
        .firstMatch(track.id.split(':').last)
        ?.group(1);
    return id != null && (gbp || native)
        ? '${gbp ? "gbp" : "our-notes"}:$id'
        : '${track.id}\u0000${track.url}';
  }

  bool isPlaying(String id, [String? url]) =>
      _playing && (url == null ? current?.id == id : current?.url == url);

  /// Website catalogue entry: retain the queue, reuse a song or append it.
  Future<void> enqueueTrack(Track track) async {
    if (_disposed || track.id.isEmpty || track.url.isEmpty) return;
    final key = _key(track);
    final existing = current != null && _key(current!) == key
        ? _index
        : _queue.indexWhere((entry) => _key(entry) == key);
    if (existing >= 0) {
      final changed = _index != existing;
      _index = existing;
      notifyListeners();
      if (changed) {
        await _play(current!);
      } else {
        await resume();
      }
      return;
    }
    _queue = List.unmodifiable([..._queue, track]);
    _index = _queue.length - 1;
    notifyListeners();
    await _play(current!);
  }

  /// Website playTrack: the same current song toggles playback; otherwise
  /// replace the queue with the supplied playlist or visible collection.
  Future<void> playQueue(List<Track> tracks, [int start = 0]) async {
    if (_disposed || tracks.isEmpty) return;
    final requested = tracks[start.clamp(0, tracks.length - 1)];
    if (requested.id.isEmpty || requested.url.isEmpty) return;
    if (current?.id == requested.id && current?.url == requested.url) {
      return _playing ? pause() : resume();
    }
    final valid = tracks
        .where((track) => track.id.isNotEmpty && track.url.isNotEmpty)
        .toList();
    if (valid.isEmpty) return;
    collapsed = compact;
    _queue = List.unmodifiable(valid);
    _index = valid.indexWhere(
      (entry) => entry.id == requested.id && entry.url == requested.url,
    );
    if (_index < 0) _index = 0;
    notifyListeners();
    await _play(current!);
  }

  int _randomIndex() => _queue.length < 2
      ? _index
      : (_index + 1 + Random().nextInt(_queue.length - 1)) % _queue.length;

  Future<void> select(int index) async {
    if (_disposed || index < 0 || index >= _queue.length) return;
    _index = index;
    notifyListeners();
    await _play(current!);
  }

  Future<void> next({bool automatic = false}) async {
    if (_queue.isEmpty || _disposed) return;
    if (automatic && mode == PlaybackMode.repeatOne) return _play(current!);
    if (automatic &&
        mode == PlaybackMode.sequential &&
        _index + 1 >= _queue.length) {
      await pause();
      await seek(Duration.zero);
      return;
    }
    await select(
      mode == PlaybackMode.shuffle
          ? _randomIndex()
          : (_index + 1) % _queue.length,
    );
  }

  Future<void> previous() async {
    if (_queue.isEmpty || _disposed) return;
    if (position.value > const Duration(seconds: 3)) return seek(Duration.zero);
    await select(
      mode == PlaybackMode.shuffle
          ? _randomIndex()
          : (_index - 1 + _queue.length) % _queue.length,
    );
  }

  void cycleMode() => setMode(
    PlaybackMode.values[(mode.index + 1) % PlaybackMode.values.length],
  );

  void setMode(PlaybackMode selected) {
    mode = selected;
    _persist();
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 1);
    _persist();
    notifyListeners();
    await _perform(() => _player.setVolume(volume));
  }

  Future<void> toggleMute() => setVolume(volume > 0 ? 0 : 0.82);

  Future<void> remove(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final removingCurrent = index == _index;
    final wasPlaying = _playing;
    final next = [..._queue]..removeAt(index);
    if (next.isEmpty) return stop();
    _queue = List.unmodifiable(next);
    if (index < _index) {
      _index--;
    } else if (removingCurrent) {
      _index = _index.clamp(0, next.length - 1);
    }
    notifyListeners();
    if (removingCurrent) {
      await _play(current!, shouldPlay: wasPlaying);
    }
    _persist();
  }

  void move(int from, int to) {
    if (from < 0 ||
        to < 0 ||
        from >= _queue.length ||
        to >= _queue.length ||
        from == to) {
      return;
    }
    final next = [..._queue];
    next.insert(to, next.removeAt(from));
    if (_index == from) {
      _index = to;
    } else if (from < _index && to >= _index) {
      _index--;
    } else if (from > _index && to <= _index) {
      _index++;
    }
    _queue = List.unmodifiable(next);
    _persist();
    notifyListeners();
  }

  void _restore() {
    try {
      final raw = _prefs?.getString('audio:v2');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map;
      _queue = List.unmodifiable([
        for (final row in (data['queue'] as List))
          if (row is Map &&
              row['id'] is String &&
              row['url'] is String &&
              (row['id'] as String).isNotEmpty &&
              (row['url'] as String).isNotEmpty)
            Track(
              id: row['id'],
              url: row['url'],
              title: row['title'] as String? ?? row['id'],
              subtitle: row['subtitle'] as String? ?? '',
              artwork: row['artwork'] as String?,
              songKey: row['songKey'] as String?,
            ),
      ]);
      _index = _queue.isEmpty
          ? -1
          : (data['index'] as num? ?? 0).toInt().clamp(0, _queue.length - 1);
      collapsed = data['collapsed'] == true;
      volume = (data['volume'] as num? ?? 0.82).toDouble().clamp(0, 1);
      mode = PlaybackMode.values.firstWhere(
        (entry) => entry.name == data['mode'],
        orElse: () => PlaybackMode.repeatAll,
      );
      _restoredPosition = Duration(
        milliseconds: (data['position'] as num? ?? 0).toInt().clamp(0, 1 << 53),
      );
      position.value = _restoredPosition;
    } catch (_) {
      _queue = const [];
      _index = -1;
    }
  }

  Future<void> _ownerChanged() async {
    final owner = AccountResources.instance.owner;
    if (owner == _resourceOwner || _disposed) return;
    _resourceOwner = owner;
    final previous = current,
        private =
            previous != null && isAccountResource(Uri.parse(previous.url));
    if (!_queue.any((t) => isAccountResource(Uri.parse(t.url)))) return;
    _queue = List.unmodifiable(
      _queue.where((t) => !isAccountResource(Uri.parse(t.url))),
    );
    _index = previous == null
        ? -1
        : _queue.indexWhere((t) => _key(t) == _key(previous));
    if (_index < 0 && _queue.isNotEmpty) _index = 0;
    if (private) {
      _loadedUrl = null;
      _playing = false;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      await _perform(_player.stop, replace: true);
      await _trackLease?.release();
      _trackLease = null;
    }
    if (!_disposed) {
      _persist();
      notifyListeners();
    }
  }

  void _persist() {
    if (_prefs == null) return;
    final publicQueue = _queue
            .where((t) => !isAccountResource(Uri.parse(t.url)))
            .toList(),
        selected = current;
    final publicIndex = selected == null
        ? -1
        : publicQueue.indexWhere((t) => _key(t) == _key(selected));
    unawaited(
      _prefs.setString(
        'audio:v2',
        jsonEncode({
          'queue': [
            for (final track in publicQueue)
              {
                'id': track.id,
                'url': track.url,
                'title': track.title,
                'subtitle': track.subtitle,
                'songKey': track.songKey,
                'artwork': track.artwork,
              },
          ],
          'index': publicIndex < 0 ? 0 : publicIndex,
          'volume': volume,
          'mode': mode.name,
          'collapsed': collapsed,
          'position': publicIndex < 0
              ? 0
              : (_restoredPosition > Duration.zero
                        ? _restoredPosition
                        : position.value)
                    .inMilliseconds,
        }),
      ),
    );
  }

  Future<void> pause() => _perform(_player.pause);
  Future<void> resume() {
    if (_disposed) return Future.value();
    final track = current;
    if (track == null) return Future.value();
    return _completed || error != null || _loadedUrl != track.url
        ? _play(track)
        : _focus.activate(() => _perform(_player.resume));
  }

  Future<void> seek(Duration value) => _perform(() async {
    if (duration.value <= Duration.zero) return;
    final target = Duration(
      milliseconds: value.inMilliseconds.clamp(
        0,
        duration.value.inMilliseconds,
      ),
    );
    await _player.seek(target);
    position.value = target;
    _persist();
  });

  Future<void> stop() async {
    if (_disposed) return;
    _queue = const [];
    _index = -1;
    _loadedUrl = null;
    _restoredPosition = Duration.zero;
    _completed = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    _playing = false;
    notifyListeners();
    _persist();
    await _perform(_player.stop, replace: true);
    await _trackLease?.release();
    _trackLease = null;
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _persist();
    _disposed = true;
    _focus.close();
    _generation++;
    final preparation = _preparation;
    if (preparation != null && !preparation.isCompleted) preparation.complete();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _trackLease?.release();
    _trackLease = null;
    position.dispose();
    duration.dispose();
    MediaLifecycle.unregister(this);
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
