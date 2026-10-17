import 'package:cassiopeia_plugin_our_notes/render_profile.dart';

import '../core/haptics.dart';

/// Device delivery coalesces the source plugin's recipes within one observation.
final class NativeChartHaptics {
  NativeChartHaptics(this.output);
  final DeviceHaptics output;
  final _cues = OurNotesWatchHapticCues();
  final _clock = Stopwatch()..start();
  int? _lastPulseMicros;
  int pulses = 0;

  void observe(
    Iterable<int> recipes, {
    required bool playing,
    required bool enabled,
    required bool held,
    required bool historical,
  }) {
    final cues = _cues.observe(
      recipes,
      held: held,
      live: playing && enabled && !historical,
    );
    if (!playing || !enabled || historical || !output.supported) return;
    for (final recipe in cues.toSet()) {
      if (recipe == OurNotesHapticFeedbackProfile.noneRecipeId) continue;
      final now = _clock.elapsedMicroseconds;
      final previous = _lastPulseMicros;
      if (previous != null &&
          now - previous <=
              OurNotesHapticFeedbackProfile.minimumIntervalMicros) {
        return;
      }
      _lastPulseMicros = now;
      ++pulses;
      output.emit(recipe);
    }
  }
}
