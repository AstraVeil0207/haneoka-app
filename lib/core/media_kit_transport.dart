import 'dart:async';

import 'package:media_kit/media_kit.dart' as media;

/// Audio-only scene clocks follow MPV's audio output timestamp, which includes
/// driver latency and advances between decoded frames. Paused, seeking and
/// unavailable audio timestamps use the backend's ordinary transport position.
Future<double?> sampleMediaKitAudioPosition(media.Player player) async {
  final backend = player.platform;
  if (backend is! media.NativePlayer) return null;
  if (player.state.playing && !player.state.completed) {
    try {
      if (await backend.getProperty('seeking') != 'yes') {
        final audio = double.tryParse(await backend.getProperty('audio-pts'));
        if (audio != null && audio.isFinite && audio >= 0) return audio;
      }
    } catch (_) {
      // Some sources have no audio timestamp while opening or seeking.
    }
  }
  return double.tryParse(await backend.getProperty('time-pos'));
}

/// Opening a playlist entry precedes file-loaded in MPV. A finite-media seek
/// waits for decoder metadata; the owning player can interrupt this wait.
Future<void> waitForMediaKitMetadata(
  media.Player player, {
  Future<void>? interrupted,
}) async {
  if (player.state.duration > Duration.zero) return;
  final loaded = Completer<void>();
  final duration = player.stream.duration.listen((value) {
    if (value > Duration.zero && !loaded.isCompleted) loaded.complete();
  });
  final errors = player.stream.error.listen((message) {
    if (!loaded.isCompleted) {
      loaded.completeError(StateError('media_metadata:$message'));
    }
  });
  try {
    // Cover the interval between the initial read and stream subscription.
    if (player.state.duration > Duration.zero && !loaded.isCompleted) {
      loaded.complete();
    }
    await Future.any<void>([loaded.future, ?interrupted])
        .timeout(const Duration(seconds: 15));
  } finally {
    await duration.cancel();
    await errors.cancel();
  }
}
