import 'dart:convert';

import 'bestdori.dart';
import 'formats.dart';
import 'sus.dart';
import 'usc.dart';

ChartImport importChartInput(String text) {
  text = text.replaceFirst('\ufeff', '');
  if (utf8.encode(text).length > 2 * 1024 * 1024) {
    throw const FormatException('chart_size');
  }
  if (RegExp(
    r'^#(?:(?:REQUEST|TITLE|ARTIST|DESIGNER|WAVEOFFSET|MEASUREBS|BPM)\b|(?:BPM|TIL|HIS)[0-9A-Z]{2}\s*:|\d{3}[0-9A-Z]{2,3}\s*:)',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(text)) {
    return importSusChart(text);
  }
  final input = jsonDecode(text);
  if (input is List &&
      input.isNotEmpty &&
      input.every(
        (v) =>
            v is Map &&
            const {
              'BPM',
              'System',
              'Single',
              'Long',
              'Slide',
              'Directional',
            }.contains(v['type']),
      )) {
    return importBestdoriChart(input);
  }
  if (input is! Map) throw const FormatException('loadFailed');
  if (input['version'] == 1 &&
      input['resolution'] == 480 &&
      input['laneBasis'] is num &&
      input['tempos'] is List &&
      input['singles'] is List &&
      input['lines'] is List) {
    return importProjectChart(input);
  }
  if (input['usc'] is Map && (input['usc'] as Map)['objects'] is List ||
      input['objects'] is List) {
    return importUscChart(input);
  }
  if (input['score'] is Map && (input['score'] as Map)['notes'] is List ||
      input['notes'] is List &&
          (input['bpm'] is List ||
              input['sig'] is List ||
              input['events'] is Map)) {
    return importSsChart(input);
  }
  throw const FormatException('loadFailed');
}
