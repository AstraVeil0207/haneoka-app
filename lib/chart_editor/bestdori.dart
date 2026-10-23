import 'dart:math' as math;

import 'formats.dart';
import 'project.dart';

/// Port of packages/bestdori/src/chart.ts, including published-viewer repair.
ChartMap bestdoriChartToSs(List input) {
  final repaired = <ChartMap>[];
  bool truthy(Object? value) =>
      value != null && value != false && value != 0 && value != '';
  for (final raw in input) {
    if (raw is! Map) continue;
    if (raw['type'] != 'Long' && raw['type'] != 'Slide') {
      repaired.add(chartMap(raw));
      continue;
    }
    final connections = raw['connections'] is List
        ? chartRows(raw['connections'])
        : <ChartMap>[];
    final visible = connections
        .where((point) => !truthy(point['hidden']))
        .toList();
    if (visible.isEmpty) continue;
    if (visible.length == 1) {
      final point = visible.single;
      repaired.add({
        'type': 'Single',
        for (final key in ['lane', 'beat', 'flick'])
          if (point.containsKey(key)) key: point[key],
      });
      continue;
    }
    final sorted = stableChartSort(
      connections,
      (a, b) => a['beat'] is num && b['beat'] is num
          ? (a['beat'] as num).compareTo(b['beat'] as num)
          : 0,
    );
    while (sorted.isNotEmpty && truthy(sorted.first['hidden'])) {
      sorted.removeAt(0);
    }
    while (sorted.isNotEmpty && truthy(sorted.last['hidden'])) {
      sorted.removeLast();
    }
    repaired.add({'type': 'Slide', 'connections': sorted});
  }
  int tick(Object? beat) => (chartNumber(beat) * 480 + .5).floor();
  final bpm = <ChartMap>[],
      notes = <ChartMap>[],
      skills = <int>[],
      fevers = <List<int>>[];
  final slides = <(List<ChartMap>, List<ChartMap>)>[];
  for (final raw in repaired) {
    switch (raw['type']) {
      case 'BPM':
        final value = chartNumber(raw['bpm']);
        if (value > 0) bpm.add({'t': tick(raw['beat']), 'bpm': value});
      case 'System':
        if (raw['data'] == 'cmd_fever_start.wav') {
          fevers.add([tick(raw['beat'])]);
        } else if (raw['data'] == 'cmd_fever_end.wav' && fevers.isNotEmpty) {
          final last = fevers.last;
          if (last.length == 1) {
            last.add(tick(raw['beat']));
          } else {
            last[1] = tick(raw['beat']);
          }
        }
      case 'Single':
        final t = tick(raw['beat']);
        if (truthy(raw['skill'])) skills.add(t);
        notes.add({
          't': t,
          'pos': chartNumber(raw['lane']) * 3,
          'size': 6,
          if (truthy(raw['flick'])) 'type': 'flick',
          if (truthy(raw['hidden'])) 'visible': false,
        });
      case 'Long' || 'Slide':
        final connections = raw['connections'] is List
            ? chartRows(raw['connections'])
            : <ChartMap>[];
        if (connections.isEmpty) continue;
        final nodes = <ChartMap>[];
        for (final point in connections) {
          final t = tick(point['beat']);
          if (!truthy(point['hidden']) && truthy(point['skill'])) skills.add(t);
          nodes.add({
            't': t,
            'pos': chartNumber(point['lane']) * 3,
            'size': 6,
            if (truthy(point['flick'])) 'type': 'flick',
            if (truthy(point['hidden'])) 'visible': false,
          });
        }
        slides.add((connections, nodes));
        notes.add({'type': 'long', 'node': nodes});
      case 'Directional':
        final t = tick(raw['beat']);
        if (truthy(raw['skill'])) skills.add(t);
        final anchor = chartNumber(raw['lane']),
            width = math.max(1, chartNumber(raw['width'])),
            left = raw['direction'] == 'Left' ? anchor - width + 1 : anchor;
        notes.add({
          'type': 'flick',
          't': t,
          'pos': left * 3,
          'size': (left + width - 1) * 3 + 6 - left * 3,
          'dir': raw['direction'] == 'Left'
              ? 'left'
              : raw['direction'] == 'Right'
              ? 'right'
              : 'up',
        });
    }
  }
  for (final (connections, nodes) in slides) {
    var begin = 0;
    for (var end = 1; end < connections.length; end++) {
      if (truthy(connections[end]['hidden'])) continue;
      final points = connections.sublist(begin, end + 1);
      var turns = 0;
      for (var i = 2; i < points.length - 1; i++) {
        final a = points[i - 1],
            b = points[i],
            c = points[i + 1],
            left = chartNumber(b['lane']) - chartNumber(a['lane']),
            right = chartNumber(c['lane']) - chartNumber(b['lane']);
        if (left * right < 0 &&
            left.abs() >= 1 &&
            right.abs() >= 1 &&
            chartNumber(b['beat']) - chartNumber(a['beat']) <= 1 / 8 &&
            chartNumber(c['beat']) - chartNumber(b['beat']) <= 1 / 8) {
          turns++;
        }
      }
      if (turns >= 6) {
        final head = connections[begin],
            tail = connections[end],
            firstBeat = chartNumber(head['beat']),
            span = chartNumber(tail['beat']) - firstBeat;
        final headNode = nodes.firstWhere((n) => n['t'] == tick(firstBeat)),
            tailNode = nodes.firstWhere((n) => n['t'] == tick(tail['beat'])),
            corridorWidth = math.min(
              chartNumber(headNode['size'], 6),
              chartNumber(tailNode['size'], 6),
            );
        if (span > 0) {
          for (final node in nodes) {
            final t = chartNumber(node['t']);
            if (t <= tick(firstBeat) || t >= tick(tail['beat'])) continue;
            final ratio = (t / 480 - firstBeat) / span,
                center =
                    chartNumber(head['lane']) +
                    (chartNumber(tail['lane']) - chartNumber(head['lane'])) *
                        ratio;
            final corridorLeft = center * 3 + (6 - corridorWidth) / 2,
                original = chartNumber(node['pos']),
                edge = original + chartNumber(node['size'], 6);
            node['pos'] = math.min(original, corridorLeft);
            node['size'] =
                math.max(edge, corridorLeft + corridorWidth) -
                (node['pos'] as num);
          }
        }
      }
      begin = end;
    }
  }
  if (!bpm.any((v) => v['t'] == 0)) bpm.insert(0, {'t': 0, 'bpm': 120});
  final sortedBpm = stableChartSort(
    bpm,
    (a, b) => (a['t'] as int).compareTo(b['t'] as int),
  );
  skills.sort();
  final fever = fevers.where((v) => v.length == 2).toList()
    ..sort((a, b) => a[0].compareTo(b[0]));
  return {
    'meta': {'version': 1},
    'score': {
      'events': {
        'bpm': sortedBpm,
        'sig': [
          {
            't': 0,
            'sig': [4, 4],
          },
        ],
        'skill': skills,
        'fever': fever,
        'call': <Object?>[],
      },
      'notes': notes,
    },
  };
}

ChartImport importBestdoriChart(
  List input, {
  double audioOffset = 0,
  ChartMap? provenance,
}) {
  final imported = importSsChart(bestdoriChartToSs(input)),
      project = imported.project;
  project.data['audioOffset'] = audioOffset;
  project.meta['source'] = 'bestdori';
  project.extensions['bestdoriSource'] = {
    'schema': 'haneoka-bestdori-source-v1',
    'bridgeLaneBasis': 24,
    'chart': input,
    'provenance': ?provenance,
  };
  project.requireValid();
  return ChartImport('bestdori', project, [
    ...imported.warnings,
    const ChartIssue('bestdori.ssBridge', r'$.extensions.bestdoriSource', true),
  ]);
}
