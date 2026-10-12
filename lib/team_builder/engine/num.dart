/// Numeric primitives shared by the engine: binary32 rounding and the
/// int32 arithmetic the client performs (`Math.fround`, `Math.imul`, `| 0`).
library;

import 'dart:typed_data';

final _single = Float32List(1);

/// `Math.fround`.
double f(num x) {
  _single[0] = x.toDouble();
  return _single[0];
}

/// `Math.imul`.
int imul(num a, num b) =>
    (a.toInt().toSigned(32) * b.toInt().toSigned(32)).toSigned(32);

/// `x | 0`.
int i32(num x) => x.toInt().toSigned(32);

const double inf = double.infinity;

/// `Math.round`: halves round up.
int jsRound(double x) => (x + 0.5).floorToDouble().toInt();

typedef Doc = Map<String, Object?>;

Doc objectRow(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

List<Doc> dataRows(Object? value) => [
  for (final row in value is List ? value : objectRow(value).values)
    objectRow(row),
];

final _underscore = RegExp('^_');

/// Raw `_field` values under `raw`, overridden by the row's own fields.
Doc nativeRow(Object? value) {
  final row = objectRow(value);
  return {
    for (final entry in objectRow(row['raw']).entries)
      entry.key.replaceFirst(_underscore, ''): entry.value,
    for (final entry in row.entries)
      if (entry.key != 'raw') entry.key: entry.value,
  };
}

/// `num`: a finite number from a number or numeric string, else [fallback].
double numOf(Object? value, [double fallback = 0]) {
  double result;
  if (value is num) {
    result = value.toDouble();
  } else if (value is String && value.trim().isNotEmpty) {
    result = double.tryParse(value.trim()) ?? double.nan;
  } else {
    result = double.nan;
  }
  return result.isFinite ? result : fallback;
}

int intOf(Object? value, [int fallback = 0]) =>
    numOf(value, fallback.toDouble()).toInt();

List<int> idsOf(Object? value) => value is List
    ? [
        for (final item in value)
          if (numOf(item) > 0) numOf(item).toInt(),
      ]
    : <int>[];

List<double> listOf(Object? value) =>
    value is List ? [for (final item in value) numOf(item)] : <double>[];

List<int> intListOf(Object? value) =>
    value is List ? [for (final item in value) numOf(item).toInt()] : <int>[];

Map<K, List<V>> groupBy<K, V>(Iterable<V> rows, K Function(V row) key) {
  final out = <K, List<V>>{};
  for (final row in rows) {
    (out[key(row)] ??= []).add(row);
  }
  return out;
}

double maxOf(Iterable<num> values, [double start = -inf]) {
  var best = start;
  for (final value in values) {
    if (value > best) best = value.toDouble();
  }
  return best;
}
