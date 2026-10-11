import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/chart/runtime_chart.dart';

/// Each fixture pairs a chart with the notes the website's converter
/// (`runtime-chart.ts`) builds from it.
void main() {
  final fixtures = Directory('test/fixtures/charts')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.bytes'))
      .toList();
  for (final file in fixtures) {
    test('converts ${file.uri.pathSegments.last} as the website does', () {
      final chart = RuntimeChart.fromBytes(file.readAsBytesSync());
      final expected = jsonDecode(
        File(file.path.replaceFirst('.bytes', '.json')).readAsStringSync(),
      ) as Map;
      expect(chart.durationMs, expected['d']);
      expect(chart.skillTimesMs, expected['s']);
      expect([
        for (final (a, b) in chart.feverMs) [a, b],
      ], expected['f']);
      expect([
        for (final n in chart.notes)
          [n.timeMs, n.operateType, n.judgementType, n.judged ? 1 : 0],
      ], expected['n']);
      expect([
        for (final n in chart.enumeration)
          [n.timeMs, n.operateType, n.judgementType],
      ], expected['e']);
    });
  }
}
