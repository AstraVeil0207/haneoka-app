import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/chart/runtime_chart.dart';
import 'package:haneoka/team_builder/engine/api.dart';
import 'package:haneoka/team_builder/engine/master.dart';
import 'package:haneoka/team_builder/engine/merge.dart';

/// A search split by leader over shards and merged (`engine/client.ts`)
/// finds the same teams as the website's whole search.
void main() {
  const dir = 'test/fixtures/team_builder';
  final data = jsonDecode(
    utf8.decode(gzip.decode(File('$dir/data-intl.json.gz').readAsBytesSync())),
  ) as Map<String, Object?>;
  final master = compileTeamData(data);
  final charts = ChartCache(
    master,
    (song) async => RuntimeChart.fromBytes(
      File('$dir/chart-${song.songId}-${song.difficulty}.bin')
          .readAsBytesSync(),
    ),
  );

  Future<EngineResponse> sharded(EngineRequest request, int count) async {
    Future<EngineResponse> all(EngineRequest request) async =>
        mergeShardResponses(
          [
            for (var index = 0; index < count; index++)
              await runEngine(
                master,
                charts,
                request.copyWith(shard: (index: index, count: count)),
              ),
          ],
          request.k,
          0,
        );
    final merged = await all(request);
    return aspirationHeld(merged, request.k)
        ? merged
        : all(request.copyWith(noFloor: true));
  }

  for (final name in const [
    'power',
    'score',
    'scorePlay',
    'potential',
    'eventItems',
    'gekisoCombo',
    'gekisoMixed',
    'ptPoints',
    'ptCp',
  ]) {
    test(name, () async {
      final golden = jsonDecode(
        File('$dir/golden-$name.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final request = EngineRequest.fromJson(
        golden['request'] as Map<String, Object?>,
      );
      final want =
          ((golden['response'] as Map)['results'] as List).first as Map;
      final got = (await sharded(request, 3)).results.first;
      expect(got.proven, want['proven'], reason: 'proven');
      final wantHits = want['hits'] as List;
      expect(got.hits.length, wantHits.length, reason: 'hit count');
      for (final (index, hit) in got.hits.indexed) {
        final w = wantHits[index] as Map;
        expect(hit.key, closeTo((w['key'] as num).toDouble(), 1e-9));
        expect(
          [...hit.members]..sort(),
          [...(w['members'] as List)]..sort(),
          reason: 'members $index',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
