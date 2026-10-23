import 'dart:math' as math;

class NativeChartVisualProfiles {
  NativeChartVisualProfiles({
    required Map<int, double> notes,
    required Map<int, double> lines,
  }) : notes = Map.unmodifiable(notes),
       lines = Map.unmodifiable(lines) {
    final speeds = {...notes.values, ...lines.values};
    _views = {for (final speed in speeds) speed: profileViewTimeMs(speed)};
    _maximum = _views.values.fold(0, math.max);
  }
  final Map<int, double> notes, lines;
  late final Map<double, double> _views;
  late final double _maximum;
  double maximumViewTime(double global) => math.max(global, _maximum);
  double noteViewTime(int id, double global) => _views[notes[id]] ?? global;
  double lineViewTime(int id, double global) => _views[lines[id]] ?? global;
}

/// Above 12, continue the native 11-to-12 view-time ratio as Web does.
double profileViewTimeMs(double speed) {
  double native(double value) {
    if (value >= 12) return 350;
    final normalized = (value - 1) / 11;
    final eased = 1 - math.pow(1 - normalized, 1.30999994);
    return (1000 * (4 + (.35 - 4) * eased)).ceilToDouble();
  }

  if (speed <= 12) return native(speed);
  final ratio = 350 / native(11);
  return (350 * math.pow(ratio, speed - 12)).ceilToDouble();
}
