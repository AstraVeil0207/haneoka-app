import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show haneokaProfileAssetRoot, loadHaneokaProfileString;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/sound_effects.dart';

/// Original note families, same-frame coalescing and authored long waveform
/// intervals match the web host. The actual music transport supplies time.
final class NativeChartSounds {
  final bank = SoundEffectBank();
  int emittedFrames = 0;

  Future<void> load(
    int group,
    String server,
    Uri Function(String) resolve,
    Future<Uint8List> Function(Uri) fetch,
  ) async {
    final packet = jsonDecode(
      await loadHaneokaProfileString(
        '${haneokaProfileAssetRoot}note-sounds.json',
      ),
    ) as Map;
    final manifest = (packet['groups'] as Map)['$group'] as Map;
    final assets = <String, List<EffectSoundLayer>>{};
    Duration? seconds(Object? value) =>
        value is num ? Duration(microseconds: (value * 1000000).round()) : null;
    for (final key in [
      'perfect',
      'flick',
      'flickDirection',
      'trace',
      'slide',
      'just',
    ]) {
      final value = manifest[key];
      final layers = value is String
          ? [
              {'url': value, 'gain': 1},
            ]
          : (value as List).cast<Map>();
      assets[key] = [
        for (final layer in layers)
          EffectSoundLayer(
            resolve(
              (layer['url'] as String).replaceFirst(
                '/__server__/',
                '/$server/',
              ),
            ),
            gain: (layer['gain'] as num).toDouble(),
            loopStart: seconds(layer['loopStartSeconds']),
            loopEnd: seconds(layer['loopEndSeconds']),
          ),
      ];
    }
    await bank.open(assets, fetch);
  }

  void observe(
    Iterable<String> sourceCues, {
    required bool held,
    required bool playing,
    required double volume,
  }) {
    final cues = playing ? sourceCues.toSet() : const <String>{};
    if (cues.isNotEmpty) ++emittedFrames;
    for (final key in ['perfect', 'flick', 'flickDirection', 'trace', 'just']) {
      if (cues.contains(key)) bank.emit(key, volume);
    }
    bank.setLoop('slide', playing && held, volume);
  }

  Future<void> close() => bank.close();
  Map<String, Object?> get observation => {
    ...bank.observation,
    'emittedFrames': emittedFrames,
  };
}
