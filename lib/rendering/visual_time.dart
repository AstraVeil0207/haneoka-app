class ChartVisualTimeMap {
  ChartVisualTimeMap(List<({double timeMs, double scale})> changes) {
    final rows =
        changes
            .where(
              (v) =>
                  v.timeMs.isFinite &&
                  v.timeMs >= 0 &&
                  v.scale.isFinite &&
                  v.scale > 0,
            )
            .toList()
          ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    _segments.add((timeMs: 0, scaled: 0, scale: 1));
    for (final row in rows) {
      final previous = _segments.last;
      if (row.timeMs == previous.timeMs) {
        _segments[_segments.length - 1] = (
          timeMs: row.timeMs,
          scaled: previous.scaled,
          scale: row.scale,
        );
      } else {
        _segments.add((
          timeMs: row.timeMs,
          scaled:
              previous.scaled + (row.timeMs - previous.timeMs) * previous.scale,
          scale: row.scale,
        ));
      }
    }
  }
  final _segments = <({double timeMs, double scaled, double scale})>[];
  double scaled(double timeMs) {
    if (!timeMs.isFinite) return 0;
    if (timeMs < 0) return timeMs;
    var low = 0, high = _segments.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_segments[mid].timeMs <= timeMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final row = _segments[low == 0 ? 0 : low - 1];
    return row.scaled + (timeMs - row.timeMs) * row.scale;
  }

  double time(double value) {
    if (!value.isFinite) return 0;
    if (value < 0) return value;
    var low = 0, high = _segments.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_segments[mid].scaled <= value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final row = _segments[low == 0 ? 0 : low - 1];
    return row.timeMs + (value - row.scaled) / row.scale;
  }
}
