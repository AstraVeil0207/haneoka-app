import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/chart/runtime_chart.dart';
import 'package:haneoka/team_builder/engine/api.dart';
import 'package:haneoka/team_builder/engine/master.dart';

/// Golden requests and responses of the website's engine
/// (`team-builder/engine/api.ts`) on the intl release, with a theoretical box.
void main() {
  const dir = 'test/fixtures/team_builder';
  final data =
      jsonDecode(
            utf8.decode(gzip.decode(File('$dir/data-intl.json.gz').readAsBytesSync())),
          )
          as Map<String, Object?>;
  final master = compileTeamData(data);
  final charts = ChartCache(
    master,
    (song) async => RuntimeChart.fromBytes(
      File('$dir/chart-${song.songId}-${song.difficulty}.bin').readAsBytesSync(),
    ),
  );

  final goldens = [
    for (final file in Directory(dir).listSync().whereType<File>())
      if (file.path.contains('golden-')) file,
  ]..sort((a, b) => a.path.compareTo(b.path));

  for (final file in goldens) {
    final name = file.uri.pathSegments.last;
    test(name, () async {
      final golden = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final request = EngineRequest.fromJson(
        golden['request'] as Map<String, Object?>,
      );
      final expected = golden['response'] as Map<String, Object?>;
      final response = await runEngine(master, charts, request);
      final actual = jsonDecode(jsonEncode(response.toJson())) as Map<String, Object?>;
      final expectedResults = expected['results'] as List;
      final actualResults = actual['results'] as List;
      expect(actualResults.length, expectedResults.length);
      for (var r = 0; r < expectedResults.length; r++) {
        final want = expectedResults[r] as Map<String, Object?>;
        final got = actualResults[r] as Map<String, Object?>;
        expect(got['proven'], want['proven'], reason: 'proven');
        expect(
          got['excludedBelow'],
          want['excludedBelow'],
          reason: 'excludedBelow',
        );
        final wantHits = want['hits'] as List;
        final gotHits = got['hits'] as List;
        expect(gotHits.length, wantHits.length, reason: 'hit count');
        for (var h = 0; h < wantHits.length; h++) {
          final w = wantHits[h] as Map<String, Object?>;
          final g = gotHits[h] as Map<String, Object?>;
          final at = '$name hit $h';
          expect(g['members'], w['members'], reason: '$at members');
          expect(g['snaps'], w['snaps'], reason: '$at snaps');
          expect(g['power'], w['power'], reason: '$at power');
          expect(g['slotPowers'], w['slotPowers'], reason: '$at slot powers');
          expect(g['key'], w['key'], reason: '$at key');
          expect(g['skipScore'], w['skipScore'], reason: '$at skip');
          final ws = w['score'] as Map<String, Object?>?;
          final gs = g['score'] as Map<String, Object?>?;
          expect(gs == null, ws == null, reason: '$at score');
          if (ws != null) {
            for (final field in [
              'mean',
              'min',
              'max',
              'median',
              'orders',
              'ranks',
              'worstOrder',
              'bestOrder',
            ]) {
              expect(gs![field], ws[field], reason: '$at score.$field');
            }
          }
          final we = w['event'] as Map<String, Object?>?;
          final ge = g['event'] as Map<String, Object?>?;
          expect(ge == null, we == null, reason: '$at event');
          if (we != null) {
            for (final field in [
              'mean',
              'bonusPercent',
              'challengePoints',
              'perPlayMin',
              'perPlayMax',
              for (final extra in [
                'rewardSum',
                'comparisonSum',
                'orders',
                'directMean',
                'convertedMean',
              ])
                if (we.containsKey(extra)) extra,
            ]) {
              expect(ge![field], we[field], reason: '$at event.$field');
            }
          }
          expect(g['potential'], w['potential'], reason: '$at potential');
        }
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
