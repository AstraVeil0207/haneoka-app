import 'dart:typed_data';

import 'package:cassiopeia_plugin_our_notes/render_profile.dart';

import '../core/sound_effects.dart';

/// Decoded intro samples share the page's media focus and source clock.
final class NativeChartIntroSounds {
  NativeChartIntroSounds(this.source);
  final OurNotesIntroAudio source;
  final bank = SoundEffectBank();
  double? _volume;

  Future<void> open(
    Uri Function(String) resolve,
    Future<Uint8List> Function(Uri) fetch,
  ) async {
    final cheer = source.cheer;
    await bank.open({
      if (cheer != null)
        'cheer': [
          EffectSoundLayer(
            resolve(cheer.path),
            gain: cheer.gain,
            loopStart: cheer.loopStartSeconds == null
                ? null
                : Duration(
                    microseconds: (cheer.loopStartSeconds! * 1000000).round(),
                  ),
            loopEnd: cheer.loopEndSeconds == null
                ? null
                : Duration(
                    microseconds: (cheer.loopEndSeconds! * 1000000).round(),
                  ),
          ),
        ],
    }, fetch);
  }

  void observe(OurNotesIntroPlayback playback, double volume) {
    for (final cue in source.sample(playback)) {
      switch (cue) {
        case OurNotesIntroAudioCue.cheer:
          bank.setLoop('cheer', true, volume, retainSilent: true);
          _volume = volume;
        case OurNotesIntroAudioCue.fadeCheer:
          bank.fadeLoops(OurNotesIntroAudio.cheerFadeDuration);
      }
    }
    if (source.cheerActive && _volume != volume) {
      bank.setLoop('cheer', true, volume, retainSilent: true);
      _volume = volume;
    }
  }

  void setPaused(bool paused) => bank.setPaused(paused);
  Future<void> stop() {
    source.bypass();
    return bank.stop();
  }

  Future<void> close() => bank.close();
}
