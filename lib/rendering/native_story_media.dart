import 'dart:async';
import 'dart:io';

import '../core/media_lifecycle.dart';
import '../core/media_kit_transport.dart';
import '../core/system_proxy.dart';

import 'package:flutter/foundation.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';
import 'package:media_kit/media_kit.dart' as media;
import 'package:media_kit_video/media_kit_video.dart';

/// A cue owns its native decoder and completion. Concurrent voices and effects
/// remain independent of the application's music dock and chart audio owner.
final class NativeStoryMediaCue {
  NativeStoryMediaCue({
    required this.id,
    required this.kind,
    required this.uri,
    required this.resourceRef,
    required this.instanceId,
    required this.sourceEpoch,
    required this.changed,
    this.commandIndex,
    this.sourceDurationUs,
    this.loopStartUs = 0,
    this.loopEndUs,
  }) : player = media.Player(
         configuration: media.PlayerConfiguration(
           protocolWhitelist: [
             ...const media.PlayerConfiguration().protocolWhitelist,
             if (Platform.isAndroid) 'httpproxy',
           ],
         ),
       ) {
    unawaited(_completion.future.catchError((Object _) {}));
    if (kind == StoryMediaKind.movie) video = VideoController(player);
    _subscriptions.addAll([
      player.stream.position.listen((_) => _publish()),
      player.stream.duration.listen((_) => _publish()),
      player.stream.playing.listen((_) => _publish()),
      player.stream.completed.listen((completed) {
        if (_ready && completed) {
          if (!_completion.isCompleted) _completion.complete();
          _publish();
        }
      }),
      player.stream.error.listen((message) {
        if (_disposed || _mediaUri == null) return;
        error = message;
        if (!_completion.isCompleted) {
          _completion.completeError(StateError('story_media:$id:$message'));
        }
        _publish();
      }),
    ]);
  }
  final String id;
  final StoryMediaKind kind;
  final Uri uri;
  final String resourceRef;
  final int instanceId;
  final int? commandIndex;
  final int? sourceDurationUs, loopEndUs;
  final int loopStartUs;
  int? get durationUs =>
      sourceDurationUs ??
      (player.state.duration > Duration.zero
          ? player.state.duration.inMicroseconds
          : null);
  bool looping = false;
  final int sourceEpoch;
  final VoidCallback changed;
  final media.Player player;
  VideoController? video;
  final _subscriptions = <StreamSubscription>[];
  final _completion = Completer<void>();
  var _generation = 0;
  int _videoRespeedOperations = 0;
  bool _accept = false, _disposed = false, _opened = false;
  String? error, _mediaUri;
  final preparationMicroseconds = <String, int>{};
  Future<void> get completed => _completion.future;
  final _io = <Future<void>>{};
  Future<void>? _disposing;
  Future<T> _track<T>(Future<T> work) {
    final settled = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _io.add(settled);
    unawaited(settled.then((_) => _io.remove(settled)));
    return work;
  }

  Future<void>? _firstVideoFrame;
  bool _videoFrameRendered = false;
  bool get videoFrameRendered => _ready && _videoFrameRendered;
  Future<void> firstVideoFrame() =>
      _firstVideoFrame ??= _waitForFirstVideoFrame();

  Future<void> _waitForFirstVideoFrame() async {
    final controller = video;
    if (controller == null) throw StateError('story_video_controller_missing');
    await Future.any<void>([
      controller.waitUntilFirstFrameRendered,
      completed.then(
        (_) => throw StateError('story_video_ended_before_first_frame'),
      ),
    ]);
    if (error != null) throw StateError('story_media:$id:$error');
    if (!_ready) throw StateError('story_video_source_closed');
    _videoFrameRendered = true;
  }

  bool get ready => _ready;
  Future<({int positionUs, bool suspended, bool ended})?> videoClock() =>
      _track(_videoClock());
  Future<({int positionUs, bool suspended, bool ended})?> _videoClock() async {
    if (kind != StoryMediaKind.movie || !_ready) return null;
    final generation = _generation, backend = player.platform;
    if (backend is! media.NativePlayer) {
      throw UnsupportedError('story_native_video_clock_required');
    }
    final position = double.tryParse(await backend.getProperty('time-pos'));
    final seeking = await backend.getProperty('seeking');
    if (!_ready || generation != _generation) return null;
    if (error != null) throw StateError('story_media:$id:$error');
    if (position == null || !position.isFinite || position < 0) return null;
    return (
      positionUs: (position * 1000000).round(),
      suspended: seeking == 'yes' || !player.state.playing,
      ended: player.state.completed,
    );
  }

  Future<bool> videoPlayingOrSeekRespeeding() =>
      _track(_videoPlayingOrSeekRespeeding());
  Future<bool> _videoPlayingOrSeekRespeeding() async {
    if (kind != StoryMediaKind.movie || !_ready || player.state.completed) {
      return false;
    }
    if (player.state.playing || _videoRespeedOperations > 0) return true;
    final generation = _generation, backend = player.platform;
    if (backend is! media.NativePlayer) {
      throw UnsupportedError('story_native_video_state_required');
    }
    final seeking = await backend.getProperty('seeking');
    return _ready &&
        generation == _generation &&
        !player.state.completed &&
        (player.state.playing ||
            _videoRespeedOperations > 0 ||
            seeking == 'yes');
  }

  bool get _ready {
    final playlist = player.state.playlist;
    return !_disposed &&
        _accept &&
        playlist.index >= 0 &&
        playlist.index < playlist.medias.length &&
        playlist.medias[playlist.index].uri == _mediaUri;
  }

  void _publish() {
    if (_ready) changed();
  }

  Future<void> open({
    bool looping = false,
    double volume = 100,
    double playbackRate = 1,
    int? positionUs,
    bool play = true,
    bool Function()? shouldPlay,
  }) => _track(
    _open(
      looping: looping,
      volume: volume,
      playbackRate: playbackRate,
      positionUs: positionUs,
      play: play,
      shouldPlay: shouldPlay,
    ),
  );
  Future<void> _open({
    bool looping = false,
    double volume = 100,
    double playbackRate = 1,
    int? positionUs,
    bool play = true,
    bool Function()? shouldPlay,
  }) async {
    if (_opened || _disposed) throw StateError('story_media_cue_single_load');
    _opened = true;
    this.looping = looping;
    final generation = ++_generation;
    final source = media.Media(uri.toString());
    _mediaUri = source.uri;
    _accept = false;
    final preparation = Stopwatch()..start();
    await player.setVolume(volume.clamp(0.0, 100.0));
    if (_disposed || generation != _generation) return;
    await player.setRate(playbackRate);
    if (_disposed || generation != _generation) return;
    await player.setPlaylistMode(
      looping ? media.PlaylistMode.single : media.PlaylistMode.none,
    );
    final backend = player.platform;
    if (Platform.isAndroid && backend is media.NativePlayer) {
      final proxy = systemProxyFor(uri);
      // FFmpeg passes http_proxy through TLS to CONNECT for HTTPS media too.
      // Preserve the source URI, decoder timing and native range seeking.
      await backend.setProperty(
        'stream-lavf-o',
        proxy.httpProxy == null ? '' : 'http_proxy=${proxy.httpProxy}',
      );
    }
    if (looping && loopEndUs != null && backend is media.NativePlayer) {
      await backend.setProperty('ab-loop-a', '${loopStartUs / 1000000}');
      await backend.setProperty('ab-loop-b', '${loopEndUs! / 1000000}');
    }
    if (_disposed || generation != _generation) return;
    await player.open(source, play: false);
    preparationMicroseconds['open'] = preparation.elapsedMicroseconds;
    preparation.reset();
    if (_disposed || generation != _generation) return;
    if (error != null) throw StateError('story_media:$id:$error');
    if (positionUs != null) {
      // media_kit.open returns after assigning playlist-pos, before file-loaded.
      // Restored seeks must wait for the native decoder's media metadata.
      await waitForMediaKitMetadata(player, interrupted: completed);
      preparationMicroseconds['waitLoaded'] = preparation.elapsedMicroseconds;
      preparation.reset();
      if (_disposed || generation != _generation) return;
      await player.seek(Duration(microseconds: positionUs));
      preparationMicroseconds['seek'] = preparation.elapsedMicroseconds;
      if (_disposed || generation != _generation) return;
      if (error != null) throw StateError('story_media:$id:$error');
    }
    _accept = true;
    if (play && (shouldPlay?.call() ?? true)) await player.play();
    if (_disposed || generation != _generation) return;
    if (error != null) throw StateError('story_media:$id:$error');
    _publish();
  }

  Future<StoryMediaObservation?> sample() => _track(_sample());
  Future<StoryMediaObservation?> _sample() async {
    if (!_ready) return null;
    final generation = _generation;
    final backend = player.platform;
    if (backend is! media.NativePlayer) {
      throw UnsupportedError('story_native_decoder_required');
    }
    double? seconds;
    try {
      seconds = kind == StoryMediaKind.movie
          ? double.tryParse(await backend.getProperty('time-pos'))
          : await sampleMediaKitAudioPosition(player);
    } catch (_) {
      if (!_ready || generation != _generation) return null;
      rethrow;
    }
    if (!_ready ||
        generation != _generation ||
        seconds == null ||
        !seconds.isFinite ||
        seconds < 0) {
      return null;
    }
    return StoryMediaObservation(
      cueId: id,
      kind: kind,
      positionUs: (seconds * Duration.microsecondsPerSecond).round(),
      durationUs: durationUs,
      playing: player.state.playing,
      completed: player.state.completed,
      error: error,
      sourceEpoch: sourceEpoch,
    );
  }

  Future<void> pause() => _disposed ? Future.value() : _track(player.pause());
  Future<void> resume() => _disposed || player.state.completed
      ? Future.value()
      : _track(player.play());
  Future<void> seek(int atUs) =>
      _disposed ? Future.value() : _track(_seek(atUs));
  Future<void> _seek(int atUs) async {
    if (kind == StoryMediaKind.movie) _videoRespeedOperations++;
    try {
      await player.seek(Duration(microseconds: atUs));
    } finally {
      if (kind == StoryMediaKind.movie) _videoRespeedOperations--;
    }
  }

  Future<void> setVolume(double value) => _track(_setVolume(value));
  Future<void> _setVolume(double value) async {
    if (!_ready) return;
    await player.setVolume(value.clamp(0.0, 100.0));
  }

  Future<void> setRate(double value) => _track(_setRate(value));
  Future<void> _setRate(double value) async {
    if (!_ready) return;
    if (kind == StoryMediaKind.movie) _videoRespeedOperations++;
    try {
      await player.setRate(value);
    } finally {
      if (kind == StoryMediaKind.movie) _videoRespeedOperations--;
    }
  }

  Future<void> restorePaused({
    required int positionUs,
    required double volume,
    required double rate,
  }) => _track(() async {
    if (!_ready || !looping || player.state.completed || error != null) {
      throw StateError('story_media_decoder_not_reusable');
    }
    final generation = ++_generation;
    final timer = Stopwatch()..start();
    await player.pause();
    await player.setVolume(volume.clamp(0.0, 100.0));
    await player.setRate(rate);
    await player.seek(Duration(microseconds: positionUs));
    if (_disposed || generation != _generation) return;
    if (error != null) throw StateError('story_media:$id:$error');
    preparationMicroseconds
      ..clear()
      ..['restoreReused'] = timer.elapsedMicroseconds;
    _publish();
  }());

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    _accept = false;
    _generation++;
    if (!_completion.isCompleted) {
      _completion.completeError(StateError('story_media_source_closed:$id'));
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    while (_io.isNotEmpty) {
      await Future.wait(_io.toList());
    }
    await player.dispose();
  }
}

/// Resource URIs come from the selected episode's actual asset rows.
final class NativeStoryMediaHost extends ChangeNotifier {
  NativeStoryMediaHost({
    required this.sourceEpoch,
    required this.resolve,
    this.maxRetainedLoopDecoders = 4,
  }) {
    if (maxRetainedLoopDecoders < 0) {
      throw ArgumentError('story_media_decoder_cache_budget');
    }
    MediaLifecycle.register(this, close);
  }
  final int sourceEpoch;
  final Uri Function(String reference, StoryMediaKind kind) resolve;
  final int maxRetainedLoopDecoders;
  final _retainedLoopDecoders = <NativeStoryMediaCue>[];
  int _decoderReuses = 0;
  Map<String, Object?> get decoderCacheObservation => {
    'capacity': maxRetainedLoopDecoders,
    'retained': _retainedLoopDecoders.length,
    'reuses': _decoderReuses,
  };
  final Map<String, NativeStoryMediaCue> _cues = {};
  final Set<NativeStoryMediaCue> _retiring = {};
  int? _replayAtUs;
  final _replayClocks = <NativeStoryMediaCue, _StoryMediaReplayClock>{};
  final Map<String, int> _intents = {};
  int _generation = 0, _nextIntent = 0;
  bool _disposed = false, _suspended = false;
  final _loads = <Future<NativeStoryMediaCue?>>{};
  bool get hasPendingResources => _loads.isNotEmpty;
  final _work = <Future<void>>{};
  Future<void>? _closing;
  Future<void> _track(Future<void> work) {
    final settled = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _work.add(settled);
    unawaited(settled.then((_) => _work.remove(settled)));
    return work;
  }

  Iterable<NativeStoryMediaCue> get cues => [..._cues.values, ..._retiring];

  Future<NativeStoryMediaCue?> dispatch(
    StoryMediaEvent event, {
    bool looping = false,
    double volume = 100,
    double playbackRate = 1,
    bool retainPreviousBgm = false,
    bool play = true,
    int? durationUs,
    int loopStartUs = 0,
    int? loopEndUs,
  }) async {
    final work = _dispatch(
      event,
      looping: looping,
      volume: volume,
      playbackRate: playbackRate,
      retainPreviousBgm: retainPreviousBgm,
      play: play,
      durationUs: durationUs,
      loopStartUs: loopStartUs,
      loopEndUs: loopEndUs,
    );
    _loads.add(work);
    try {
      return await work;
    } finally {
      _loads.remove(work);
    }
  }

  Future<NativeStoryMediaCue?> _dispatch(
    StoryMediaEvent event, {
    bool looping = false,
    double volume = 100,
    double playbackRate = 1,
    bool retainPreviousBgm = false,
    bool play = true,
    int? durationUs,
    int loopStartUs = 0,
    int? loopEndUs,
  }) async {
    if (_disposed) throw StateError('story_media_host_disposed');
    final generation = _generation;
    final cueKey = '${event.kind.name}:${event.cueId}';
    final scope =
        '${event.kind.name}:${event.kind == StoryMediaKind.bgm || event.kind == StoryMediaKind.movie ? 'single' : event.cueId}';
    final intent = ++_nextIntent;
    _intents[scope] = intent;
    bool current() =>
        !_disposed && generation == _generation && _intents[scope] == intent;
    final replaced = _cues.entries
        .where(
          (entry) =>
              entry.key == cueKey ||
              (entry.value.kind == event.kind &&
                  (event.cueId == '0' ||
                      event.kind == StoryMediaKind.bgm ||
                      event.kind == StoryMediaKind.movie)),
        )
        .toList();
    for (final entry in replaced) {
      _cues.remove(entry.key);
      if (retainPreviousBgm &&
          event.kind == StoryMediaKind.bgm &&
          entry.value.ready) {
        _retiring.add(entry.value);
      } else {
        await entry.value.dispose();
      }
      if (!current()) return null;
    }
    if (!current()) return null;
    if (event.stop) {
      notifyListeners();
      return null;
    }
    final reference = event.resourceRef;
    if (reference == null || reference.isEmpty) {
      throw StateError('story_actual_resource_ref_missing:${event.cueId}');
    }
    final cue = NativeStoryMediaCue(
      id: event.cueId,
      kind: event.kind,
      uri: resolve(reference, event.kind),
      resourceRef: reference,
      instanceId: intent,
      commandIndex: event.commandIndex,
      sourceEpoch: sourceEpoch,
      sourceDurationUs: durationUs,
      loopStartUs: loopStartUs,
      loopEndUs: loopEndUs,
      changed: () {
        if (!_disposed) notifyListeners();
      },
    );
    _cues[cueKey] = cue;
    try {
      await cue.open(
        looping: looping,
        volume: volume,
        playbackRate: playbackRate,
        positionUs: event.positionUs,
        play: play,
        shouldPlay: () => !_suspended && current(),
      );
      if (!current() || !identical(_cues[cueKey], cue)) {
        if (identical(_cues[cueKey], cue)) _cues.remove(cueKey);
        _retiring.remove(cue);
        await cue.dispose();
        return null;
      }
      if (_replayAtUs != null) {
        _replayClocks[cue] = _StoryMediaReplayClock(
          event.atUs,
          event.positionUs ?? 0,
          playbackRate,
        );
      }
      notifyListeners();
      return cue;
    } catch (_) {
      if (identical(_cues[cueKey], cue)) _cues.remove(cueKey);
      _retiring.remove(cue);
      await cue.dispose();
      if (!current()) return null;
      rethrow;
    }
  }

  Future<List<StoryMediaObservation>> sample() async {
    final generation = _generation;
    final sampled = _cues.values.toList();
    final values = await Future.wait([for (final cue in sampled) cue.sample()]);
    if (_disposed || generation != _generation) return const [];
    return [
      for (final (index, value) in values.indexed)
        if (identical(
          _cues['${sampled[index].kind.name}:${sampled[index].id}'],
          sampled[index],
        ))
          ?value,
    ];
  }

  Future<void> pause() async {
    _suspended = true;
    await Future.wait([for (final cue in cues) cue.pause()]);
  }

  Future<void> resume() async {
    _suspended = false;
    await Future.wait([
      for (final cue in cues)
        if (!cue.player.state.completed) cue.resume(),
    ]);
  }

  Future<void> settleResources() async {
    while (_loads.isNotEmpty) {
      await Future.wait(_loads.toList());
    }
  }

  /// Offline scene preparation advances cue positions without playing audio.
  /// The decoder remains the clock source during ordinary playback and saves.
  Future<void> beginReplay(int atUs) async {
    if (_replayAtUs != null) return;
    await settleResources();
    _replayAtUs = atUs;
    for (final cue in cues) {
      final observation = await cue.sample();
      if (observation == null || observation.completed) continue;
      _replayClocks[cue] = _StoryMediaReplayClock(
        atUs,
        observation.positionUs,
        cue.player.state.rate,
      );
    }
  }

  void advanceReplayTo(int atUs) {
    final previous = _replayAtUs;
    if (previous == null) return;
    if (atUs < previous) throw StateError('story_media_replay_backwards');
    _replayAtUs = atUs;
  }

  StoryMediaObservation? _projected(NativeStoryMediaCue cue) {
    final clock = _replayClocks[cue], now = _replayAtUs;
    if (clock == null || now == null) return null;
    final duration = cue.durationUs;
    final unwrapped =
        clock.positionUs + ((now - clock.atUs) * clock.rate).round();
    final loopEnd = cue.loopEndUs ?? duration;
    final loopLength = loopEnd == null ? 0 : loopEnd - cue.loopStartUs;
    final position =
        cue.looping && loopEnd != null && loopLength > 0 && unwrapped >= loopEnd
        ? cue.loopStartUs + (unwrapped - cue.loopStartUs) % loopLength
        : unwrapped;
    return StoryMediaObservation(
      cueId: cue.id,
      kind: cue.kind,
      positionUs: position,
      durationUs: duration,
      playing: false,
      completed: !cue.looping && duration != null && unwrapped >= duration,
      error: cue.error,
      sourceEpoch: sourceEpoch,
    );
  }

  Future<void> finishReplay() async {
    if (_replayAtUs == null) return;
    final positions = {for (final cue in cues) cue: _projected(cue)};
    _replayAtUs = null;
    _replayClocks.clear();
    await Future.wait([
      for (final entry in positions.entries)
        if (entry.value case final observation?)
          observation.completed
              ? releaseCue(entry.key)
              : entry.key.seek(observation.positionUs),
    ]);
  }

  Future<NativeStoryMediaSnapshot> snapshot({
    double Function(NativeStoryMediaCue)? projectedVolume,
  }) async {
    await settleResources();
    if (_suspended && _replayAtUs == null) await pause();
    final saved = <NativeStoryCueSnapshot>[];
    for (final cue in cues.toList()) {
      final observation = _projected(cue) ?? await cue.sample();
      if (observation == null || observation.completed) continue;
      saved.add(
        NativeStoryCueSnapshot(
          id: cue.id,
          kind: cue.kind,
          uri: cue.uri,
          resourceRef: cue.resourceRef,
          positionUs: observation.positionUs,
          looping: cue.looping,
          volume: _replayAtUs == null
              ? cue.player.state.volume
              : projectedVolume?.call(cue) ?? cue.player.state.volume,
          rate: cue.player.state.rate,
          retiring: _retiring.contains(cue),
          instanceId: cue.instanceId,
          commandIndex: cue.commandIndex,
          durationUs: cue.durationUs,
          loopStartUs: cue.loopStartUs,
          loopEndUs: cue.loopEndUs,
        ),
      );
    }
    return NativeStoryMediaSnapshot(sourceEpoch, List.unmodifiable(saved));
  }

  Future<Map<String, Object?>> snapshotData({
    required Future<String> Function(Uri) resourceHash,
  }) async {
    return (await snapshot()).toData(resourceHash: resourceHash);
  }

  Future<Map<int, NativeStoryMediaCue>> restoreData(
    Map data, {
    required Future<String> Function(Uri) resourceHash,
  }) async {
    if (data['version'] != 1) {
      throw const FormatException('story_media_data_version');
    }
    final saved = <NativeStoryCueSnapshot>[];
    final slots = <int>[];
    for (final raw in data['cues'] as List) {
      final value = raw as Map;
      final kind = StoryMediaKind.values.byName(value['kind'] as String);
      final reference = value['resourceRef'] as String;
      final uri = resolve(reference, kind);
      if (await resourceHash(uri) != value['resourceHash']) {
        throw const FormatException('story_media_data_resource_hash');
      }
      slots.add(value['slot'] as int);
      saved.add(
        NativeStoryCueSnapshot(
          id: value['id'] as String,
          kind: kind,
          uri: uri,
          resourceRef: reference,
          positionUs: value['positionUs'] as int,
          looping: value['looping'] as bool,
          volume: (value['volume'] as num).toDouble(),
          rate: (value['rate'] as num).toDouble(),
          retiring: value['retiring'] as bool,
          instanceId: ++_nextIntent,
          commandIndex: value['commandIndex'] as int?,
          durationUs: value['durationUs'] as int?,
          loopStartUs: value['loopStartUs'] as int? ?? 0,
          loopEndUs: value['loopEndUs'] as int?,
        ),
      );
    }
    if (slots.toSet().length != slots.length) {
      throw const FormatException('story_media_data_slots');
    }
    await restore(
      NativeStoryMediaSnapshot(sourceEpoch, List.unmodifiable(saved)),
    );
    final byId = {for (final cue in cues) cue.instanceId: cue};
    return Map.unmodifiable({
      for (var i = 0; i < slots.length; i++)
        slots[i]: byId[saved[i].instanceId]!,
    });
  }

  Future<void> restore(NativeStoryMediaSnapshot snapshot) =>
      _track(_restore(snapshot));
  Future<void> _restore(NativeStoryMediaSnapshot snapshot) async {
    if (_disposed) {
      throw StateError('story_media_host_disposed');
    }
    if (snapshot.sourceEpoch != sourceEpoch) {
      throw const FormatException('story_media_snapshot_epoch');
    }
    for (final saved in snapshot.cues) {
      if (resolve(saved.resourceRef, saved.kind) != saved.uri) {
        throw const FormatException('story_media_snapshot_resource');
      }
    }
    final generation = ++_generation;
    _replayAtUs = null;
    _replayClocks.clear();
    void checkCurrent() {
      if (_disposed || generation != _generation) {
        throw StateError('story_media_restore_cancelled');
      }
    }

    _intents.clear();
    final old = cues.toList();
    final reused = <NativeStoryCueSnapshot, NativeStoryMediaCue>{};
    for (final saved in snapshot.cues) {
      bool matches(NativeStoryMediaCue cue) =>
          cue.looping &&
          saved.looping &&
          cue.kind != StoryMediaKind.movie &&
          cue.kind != StoryMediaKind.voice &&
          cue.ready &&
          !cue.player.state.completed &&
          cue.error == null &&
          cue.instanceId == saved.instanceId &&
          cue.commandIndex == saved.commandIndex &&
          cue.kind == saved.kind &&
          cue.id == saved.id &&
          cue.uri == saved.uri &&
          cue.resourceRef == saved.resourceRef &&
          cue.sourceDurationUs == saved.durationUs &&
          cue.loopStartUs == saved.loopStartUs &&
          cue.loopEndUs == saved.loopEndUs;
      final available = [...old, ..._retainedLoopDecoders];
      final index = available.indexWhere(matches);
      if (index >= 0) {
        final cue = available[index];
        reused[saved] = cue;
        old.remove(cue);
        _retainedLoopDecoders.remove(cue);
      }
    }
    final unclaimed = {...old, ...reused.values};
    _cues.clear();
    _retiring.clear();
    try {
      for (final cue in old) {
        if (maxRetainedLoopDecoders > 0 &&
            cue.looping &&
            cue.kind != StoryMediaKind.movie &&
            cue.kind != StoryMediaKind.voice &&
            cue.ready &&
            !cue.player.state.completed &&
            cue.error == null) {
          await cue.pause();
          checkCurrent();
          _retainedLoopDecoders.add(cue);
        } else {
          await cue.dispose();
        }
        unclaimed.remove(cue);
        checkCurrent();
      }
      while (_retainedLoopDecoders.length > maxRetainedLoopDecoders) {
        await _retainedLoopDecoders.removeAt(0).dispose();
        checkCurrent();
      }
      for (final saved in snapshot.cues) {
        checkCurrent();
        final uri = resolve(saved.resourceRef, saved.kind);
        if (uri != saved.uri) {
          throw const FormatException('story_media_snapshot_resource');
        }
        final retained = reused[saved];
        final cue =
            retained ??
            NativeStoryMediaCue(
              id: saved.id,
              kind: saved.kind,
              uri: uri,
              resourceRef: saved.resourceRef,
              instanceId: saved.instanceId,
              commandIndex: saved.commandIndex,
              sourceEpoch: sourceEpoch,
              sourceDurationUs: saved.durationUs,
              loopStartUs: saved.loopStartUs,
              loopEndUs: saved.loopEndUs,
              changed: () {
                if (!_disposed) notifyListeners();
              },
            );
        if (saved.instanceId > _nextIntent) _nextIntent = saved.instanceId;
        if (saved.retiring) {
          _retiring.add(cue);
        } else {
          _cues['${saved.kind.name}:${saved.id}'] = cue;
        }
        unclaimed.remove(cue);
        if (retained == null) {
          await cue.open(
            looping: saved.looping,
            volume: saved.volume,
            playbackRate: saved.rate,
            positionUs: saved.positionUs,
            play: false,
          );
        } else {
          await cue.restorePaused(
            positionUs: saved.positionUs,
            volume: saved.volume,
            rate: saved.rate,
          );
          _decoderReuses++;
        }
        checkCurrent();
      }
      if (!_disposed) notifyListeners();
    } finally {
      await Future.wait([for (final cue in unclaimed) cue.dispose()]);
    }
  }

  Future<void> releaseCue(NativeStoryMediaCue cue) => _track(_releaseCue(cue));
  Future<void> _releaseCue(NativeStoryMediaCue cue) async {
    _replayClocks.remove(cue);
    _retainedLoopDecoders.remove(cue);
    final key = '${cue.kind.name}:${cue.id}';
    if (identical(_cues[key], cue)) _cues.remove(key);
    _retiring.remove(cue);
    await cue.dispose();
    if (!_disposed) notifyListeners();
  }

  Future<void> stopKind(StoryMediaKind kind, {Set<String>? cueIds}) =>
      _track(_stopKind(kind, cueIds: cueIds));
  Future<void> _stopKind(StoryMediaKind kind, {Set<String>? cueIds}) async {
    if (_disposed) return;
    final scopes = _intents.keys
        .where(
          (scope) =>
              scope.startsWith('${kind.name}:') &&
              (cueIds == null ||
                  cueIds.contains(scope.substring(kind.name.length + 1))),
        )
        .toList();
    for (final scope in scopes) {
      _intents[scope] = ++_nextIntent;
    }
    final removed = _cues.entries
        .where(
          (entry) =>
              entry.value.kind == kind &&
              (cueIds == null || cueIds.contains(entry.value.id)),
        )
        .toList();
    for (final entry in removed) {
      if (!identical(_cues[entry.key], entry.value)) continue;
      _cues.remove(entry.key);
      await entry.value.dispose();
    }
    final retiring = _retiring
        .where(
          (cue) =>
              cue.kind == kind && (cueIds == null || cueIds.contains(cue.id)),
        )
        .toList();
    for (final cue in retiring) {
      await releaseCue(cue);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _disposed = true;
    _generation++;
    _intents.clear();
    _replayAtUs = null;
    _replayClocks.clear();
    final old = {...cues, ..._retainedLoopDecoders};
    _cues.clear();
    _retiring.clear();
    _retainedLoopDecoders.clear();
    await Future.wait([for (final cue in old) cue.dispose()]);
    while (_loads.isNotEmpty || _work.isNotEmpty) {
      await Future.wait([
        ..._work,
        for (final load in _loads)
          load.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ]);
    }
    MediaLifecycle.unregister(this);
    super.dispose();
  }
}

final class NativeStoryMediaSnapshot {
  const NativeStoryMediaSnapshot(this.sourceEpoch, this.cues);
  final int sourceEpoch;
  final List<NativeStoryCueSnapshot> cues;
  Future<Map<String, Object?>> toData({
    required Future<String> Function(Uri) resourceHash,
  }) async => {
    'version': 1,
    'cues': [
      for (final (slot, cue) in cues.indexed)
        {
          'slot': slot,
          'id': cue.id,
          'kind': cue.kind.name,
          'resourceRef': cue.resourceRef,
          'resourceHash': await resourceHash(cue.uri),
          'positionUs': cue.positionUs,
          'looping': cue.looping,
          'volume': cue.volume,
          'rate': cue.rate,
          'retiring': cue.retiring,
          if (cue.commandIndex != null) 'commandIndex': cue.commandIndex,
          if (cue.durationUs != null) 'durationUs': cue.durationUs,
          'loopStartUs': cue.loopStartUs,
          if (cue.loopEndUs != null) 'loopEndUs': cue.loopEndUs,
        },
    ],
  };
}

final class NativeStoryCueSnapshot {
  const NativeStoryCueSnapshot({
    required this.id,
    required this.kind,
    required this.uri,
    required this.resourceRef,
    required this.positionUs,
    required this.looping,
    required this.volume,
    required this.rate,
    required this.retiring,
    required this.instanceId,
    this.commandIndex,
    this.durationUs,
    this.loopStartUs = 0,
    this.loopEndUs,
  });
  final String id, resourceRef;
  final StoryMediaKind kind;
  final Uri uri;
  final int positionUs, instanceId;
  final int? commandIndex;
  final int? durationUs, loopEndUs;
  final int loopStartUs;
  final bool looping, retiring;
  final double volume, rate;
}

final class _StoryMediaReplayClock {
  const _StoryMediaReplayClock(this.atUs, this.positionUs, this.rate);
  final int atUs, positionUs;
  final double rate;
}
