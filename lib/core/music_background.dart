import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as background;
import 'package:audio_session/audio_session.dart';

import 'audio.dart';

/// System media controls expose the music dock's queue only. Page-owned audio
/// never publishes metadata, notifications, queue entries or background work.
final class MusicBackground extends background.BaseAudioHandler
    with background.SeekHandler {
  MusicBackground(this.music) {
    music.addListener(_publish);
    music.duration.addListener(_publish);
    music.position.addListener(_positionChanged);
    _publish();
  }
  final AudioService music;
  List<Track>? _publishedQueue;
  Duration? _publishedDuration;
  Track? _publishedTrack;
  Duration _reportedPosition = Duration.zero;
  DateTime _reportedAt = DateTime.now();
  final _subscriptions = <StreamSubscription>[];
  static Future<void>? _sessionReady;
  static Future<void>? _initializing;
  static MusicBackground? _handler;

  static Future<void> prepareSession() {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return Future.value();
    }
    final current = _sessionReady;
    if (current != null) return current;
    final pending = _prepareSession();
    _sessionReady = pending;
    unawaited(
      pending.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_sessionReady, pending)) _sessionReady = null;
        },
      ),
    );
    return pending;
  }

  static Future<void> _prepareSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  static Future<void> initialize(AudioService music) {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return Future.value();
    }
    final current = _initializing;
    if (current != null) return current;
    final pending = _initialize(music);
    _initializing = pending;
    unawaited(
      pending.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_initializing, pending)) _initializing = null;
        },
      ),
    );
    return pending;
  }

  static Future<void> _initialize(AudioService music) async {
    await prepareSession();
    final session = await AudioSession.instance;
    final handler = _handler ??=
        await background.AudioService.init<MusicBackground>(
          builder: () => MusicBackground(music),
          config: const background.AudioServiceConfig(
            androidNotificationChannelId: 'org.haneoka.music',
            androidNotificationChannelName: 'Music playback',
            androidNotificationOngoing: true,
            androidStopForegroundOnPause: true,
          ),
        );
    handler._subscriptions.addAll([
      session.interruptionEventStream.listen((event) {
        if (event.begin) unawaited(music.pause());
      }),
      session.becomingNoisyEventStream.listen((_) => unawaited(music.pause())),
    ]);
  }

  background.MediaItem _item(Track track) => background.MediaItem(
    id: track.id,
    title: track.title,
    artist: track.subtitle.isEmpty ? null : track.subtitle,
    artUri: track.artwork == null ? null : Uri.tryParse(track.artwork!),
    duration:
        identical(track, music.current) && music.duration.value > Duration.zero
        ? music.duration.value
        : null,
  );

  void _positionChanged() {
    final now = DateTime.now();
    final expected =
        _reportedPosition +
        (music.playing ? now.difference(_reportedAt) : Duration.zero);
    if ((music.position.value - expected).inMilliseconds.abs() > 500) {
      _publish();
    }
  }

  void _publish() {
    if (!identical(_publishedQueue, music.queue) ||
        !identical(_publishedTrack, music.current) ||
        _publishedDuration != music.duration.value) {
      _publishedQueue = music.queue;
      _publishedTrack = music.current;
      _publishedDuration = music.duration.value;
      queue.add([for (final track in music.queue) _item(track)]);
    }
    final track = music.current;
    mediaItem.add(track == null ? null : _item(track));
    _reportedPosition = music.position.value;
    _reportedAt = DateTime.now();
    playbackState.add(
      background.PlaybackState(
        controls: [
          background.MediaControl.skipToPrevious,
          music.playing
              ? background.MediaControl.pause
              : background.MediaControl.play,
          background.MediaControl.skipToNext,
          background.MediaControl.stop,
        ],
        systemActions: const {
          background.MediaAction.seek,
          background.MediaAction.seekForward,
          background.MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: music.error != null
            ? background.AudioProcessingState.error
            : track == null
            ? background.AudioProcessingState.idle
            : background.AudioProcessingState.ready,
        playing: music.playing,
        updatePosition: _reportedPosition,
        queueIndex: music.index < 0 ? null : music.index,
        repeatMode: switch (music.mode) {
          PlaybackMode.repeatOne => background.AudioServiceRepeatMode.one,
          PlaybackMode.repeatAll => background.AudioServiceRepeatMode.all,
          _ => background.AudioServiceRepeatMode.none,
        },
        shuffleMode: music.mode == PlaybackMode.shuffle
            ? background.AudioServiceShuffleMode.all
            : background.AudioServiceShuffleMode.none,
      ),
    );
  }

  @override
  Future<void> play() => music.resume();
  @override
  Future<void> pause() => music.pause();
  @override
  Future<void> stop() => music.stop();
  @override
  Future<void> seek(Duration position) => music.seek(position);
  @override
  Future<void> skipToNext() => music.next();
  @override
  Future<void> skipToPrevious() => music.previous();
  @override
  Future<void> skipToQueueItem(int index) => music.select(index);
  @override
  Future<void> setRepeatMode(
    background.AudioServiceRepeatMode repeatMode,
  ) async {
    music.setMode(switch (repeatMode) {
      background.AudioServiceRepeatMode.one => PlaybackMode.repeatOne,
      background.AudioServiceRepeatMode.all ||
      background.AudioServiceRepeatMode.group => PlaybackMode.repeatAll,
      _ => PlaybackMode.sequential,
    });
  }

  @override
  Future<void> setShuffleMode(
    background.AudioServiceShuffleMode shuffleMode,
  ) async {
    music.setMode(
      shuffleMode == background.AudioServiceShuffleMode.none
          ? PlaybackMode.sequential
          : PlaybackMode.shuffle,
    );
  }
}
