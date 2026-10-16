import '../core/haptics.dart';

/// Device delivery coalesces the source plugin's recipes within one observation.
final class NativeChartHaptics {
  NativeChartHaptics(this.output);
  final DeviceHaptics output;
  int pulses = 0;

  void observe(
    Iterable<int> recipes, {
    required bool playing,
    required bool enabled,
  }) {
    if (!playing || !enabled || !output.supported) return;
    for (final recipe in recipes.toSet()) {
      ++pulses;
      output.emit(recipe);
    }
  }
}
