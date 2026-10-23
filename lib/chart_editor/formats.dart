import 'dart:convert';

import 'project.dart';

class ChartImport {
  const ChartImport(this.format, this.project, this.warnings);
  final String format;
  final ChartProject project;
  final List<ChartIssue> warnings;
}

ChartMap chartSourceRecord(Map source, Map baseline) => {
  'source': cloneChartMap(source),
  'baseline': cloneChartMap(baseline),
};
ChartMap restoreChartRecord(Object? record, ChartMap current) {
  final saved =
      record is Map && record['source'] is Map && record['baseline'] is Map
      ? record
      : null;
  final source = saved == null
      ? <String, Object?>{}
      : cloneChartMap(saved['source'] as Map);
  final baseline = saved == null
      ? <String, Object?>{}
      : chartMap(saved['baseline']);
  for (final key in {...baseline.keys, ...current.keys}) {
    if (saved != null && chartEqual(current[key], baseline[key])) continue;
    if (!current.containsKey(key)) {
      source.remove(key);
    } else {
      source[key] = jsonDecode(jsonEncode(current[key]));
    }
  }
  return source;
}

ChartImport finishChartImport(
  String format,
  ChartProject project,
  List<ChartIssue> warnings,
) {
  for (final key in ['tempos', 'meters', 'timeScales']) {
    final byTick = <int, ChartMap>{};
    for (final row in chartRows(project.data[key])) {
      final tick = row['tick'] as int;
      if (byTick.containsKey(tick)) {
        warnings.add(ChartIssue('$key.duplicateTick', '\$.$key', true));
      }
      byTick[tick] = row;
    }
    project.data[key] = byTick.values.toList();
  }
  if (!project.tempos.any((row) => row['tick'] == 0)) {
    (project.data['tempos'] as List).insert(0, {
      'id': '$format-tempo-default',
      'tick': 0,
      'bpm': 120,
    });
    warnings.add(const ChartIssue('tempo.defaulted', r'$.tempos', true));
  }
  if (!project.meters.any((row) => row['tick'] == 0)) {
    (project.data['meters'] as List).insert(0, {
      'id': '$format-meter-default',
      'tick': 0,
      'numerator': 4,
      'denominator': 4,
    });
    warnings.add(const ChartIssue('meter.defaulted', r'$.meters', true));
  }
  project.sort();
  project.requireValid();
  warnings.addAll(project.validate().where((issue) => issue.warning));
  return ChartImport(format, project, warnings);
}

ChartImport importProjectChart(Object? input) {
  final project = ChartProject(chartMap(input));
  project.requireValid();
  project.sort();
  return ChartImport(
    'project',
    project,
    project.validate().where((v) => v.warning).toList(),
  );
}

String serializeChartProject(ChartProject project) {
  project.requireValid();
  final sorted = project.copy()..sort();
  return const JsonEncoder.withIndent('  ').convert(sorted.data);
}

ChartImport importSsChart(Object? input) {
  final root = chartMap(input), rawScore = root['score'];
  final score = rawScore is Map ? chartMap(rawScore) : root;
  final events = score['events'] is Map ? chartMap(score['events']) : score;
  final rawNotes = score['notes'] ?? root['notes'];
  if (rawNotes is! List) throw const FormatException('ss.notes');
  final warnings = <ChartIssue>[], singles = <ChartMap>[], lines = <ChartMap>[];
  final order = <String>[], records = <String, Object?>{};
  int tick(Object? v, String path) {
    final n = chartNumber(v), result = (n + .5).floor();
    if (n != result) warnings.add(ChartIssue('ss.tick.rounded', path, true));
    return result;
  }

  ChartMap parseNote(
    Map raw,
    String id,
    String path, {
    Object? parentEase,
    bool point = false,
  }) {
    final auto = point && raw['pos'] == 'auto';
    if (!auto && raw['pos'] is! num) {
      warnings.add(
        ChartIssue(
          point ? 'ss.point.defaultLane' : 'ss.note.defaultLane',
          '$path.pos',
          true,
        ),
      );
    }
    final type = const {'flick', 'trace'}.contains(raw['type'])
        ? raw['type']
        : 'tap';
    final dir = const {'left', 'up', 'right'}.contains(raw['dir'])
        ? raw['dir']
        : 'none';
    final note = <String, Object?>{
      'id': id,
      'tick': tick(raw['t'], '$path.t'),
      'lane': auto ? 'auto' : chartNumber(raw['pos']),
      'size': chartNumber(raw['size'], 6),
      if (auto && raw['size'] is! num) 'autoSize': true,
      'type': type,
      'critical': raw['crit'] == true,
      'direction': type == 'flick'
          ? dir == 'none'
                ? 'up'
                : dir
          : 'none',
      'visible': raw['visible'] != false,
    };
    if (point) {
      final source = raw['ease'] ?? parentEase;
      String ease(Object? value) =>
          const {'in', 'out'}.contains(value) ? '$value' : 'linear';
      note['ease'] = source is List
          ? {
              'left': ease(source.elementAtOrNull(0)),
              'right': ease(
                source.elementAtOrNull(1) ?? source.elementAtOrNull(0),
              ),
            }
          : {'left': ease(source), 'right': ease(source)};
    }
    records[id] = chartSourceRecord(raw, _encodeSsNote(note, 1, point: point));
    return note;
  }

  for (final (index, raw) in rawNotes.indexed) {
    final path = '\$.score.notes[$index]';
    if (raw is! Map) {
      warnings.add(ChartIssue('ss.note.skipped', path, true));
      continue;
    }
    if (const {'long', 'guide'}.contains(raw['type'])) {
      if (raw['node'] is! List) {
        warnings.add(ChartIssue('ss.line.skipped', path, true));
        continue;
      }
      final id = 'ss-line-$index', points = <ChartMap>[];
      for (final (at, point) in (raw['node'] as List).indexed) {
        if (point is! Map) {
          warnings.add(ChartIssue('ss.point.skipped', '$path.node[$at]', true));
          continue;
        }
        points.add(
          parseNote(
            point,
            '$id-point-$at',
            '$path.node[$at]',
            parentEase: raw['ease'],
            point: true,
          ),
        );
      }
      final sorted = stableChartSort(
        points,
        (a, b) => (a['tick'] as int).compareTo(b['tick'] as int),
      );
      final shapes = resolveChartPoints(sorted);
      for (final (at, point) in sorted.indexed) {
        if (point['lane'] == 'auto') {
          final shape = shapes[at];
          point.addAll({'resolvedLane': shape.$1, 'resolvedSize': shape.$2});
        }
      }
      final line = <String, Object?>{
        'id': id,
        'kind': raw['type'],
        if (raw['crit'] is bool) 'critical': raw['crit'],
        'points': sorted,
      };
      lines.add(line);
      order.add(id);
      records[id] = chartSourceRecord({...raw}..remove('node'), {
        'type': line['kind'],
        if (line.containsKey('critical')) 'crit': line['critical'],
      });
    } else {
      final id = 'ss-single-$index';
      singles.add(parseNote(raw, id, path));
      order.add(id);
    }
  }
  final tempos = <ChartMap>[], meters = <ChartMap>[];
  final rawBpms = events['bpm'] is List ? events['bpm'] as List : const [];
  for (final (index, raw) in rawBpms.indexed) {
    if (raw is! Map || raw['bpm'] is! num || !(raw['bpm'] as num).isFinite) {
      warnings.add(
        ChartIssue('ss.tempo.skipped', '\$.score.events.bpm[$index]', true),
      );
      continue;
    }
    final row = <String, Object?>{
      'id': 'ss-tempo-$index',
      'tick': tick(raw['t'], '\$.score.events.bpm[$index].t'),
      'bpm': raw['bpm'],
    };
    tempos.add(row);
    records['${row['id']}'] = chartSourceRecord(raw, {
      't': row['tick'],
      'bpm': row['bpm'],
    });
  }
  final rawMeters = events['sig'] is List ? events['sig'] as List : const [];
  for (final (index, raw) in rawMeters.indexed) {
    if (raw is! Map || raw['sig'] is! List || (raw['sig'] as List).length < 2) {
      warnings.add(
        ChartIssue('ss.meter.skipped', '\$.score.events.sig[$index]', true),
      );
      continue;
    }
    final sig = raw['sig'] as List;
    final row = <String, Object?>{
      'id': 'ss-meter-$index',
      'tick': tick(raw['t'], '\$.score.events.sig[$index].t'),
      'numerator': (chartNumber(sig[0], 4) + .5).floor(),
      'denominator': (chartNumber(sig[1], 4) + .5).floor(),
    };
    meters.add(row);
    records['${row['id']}'] = chartSourceRecord(raw, {
      't': row['tick'],
      'sig': [row['numerator'], row['denominator']],
    });
  }
  List<num> numbers(Object? value) => value is List
      ? value.whereType<num>().where((v) => v.isFinite).toList()
      : [];
  final meta = root['meta'] is Map
      ? chartMap(root['meta'])
      : <String, Object?>{};
  final version = chartNumber(meta['version'] ?? root['version'], 1);
  final project = ChartProject.empty({
    'source': 'ss',
    'extra': {'ssVersion': version},
  });
  project.data.addAll({
    'tempos': tempos,
    'meters': meters,
    'singles': singles,
    'lines': lines,
    'sourceOrder': order,
    'markers': {
      'skill': numbers(events['skill'] ?? root['skill'])
          .map((v) => (v + .5).floor())
          .toList(),
      'fever': [
        if (events['fever'] is List)
          for (final v in events['fever'] as List)
            if (v is List && v.length >= 2)
              [
                (chartNumber(v[0]) + .5).floor(),
                (chartNumber(v[1]) + .5).floor(),
              ],
      ],
      'call': [
        if (events['call'] is List)
          for (final v in events['call'] as List)
            if (v is Map)
              {
                'tick': (chartNumber(v['t']) + .5).floor(),
                'timing': numbers(v['timing']),
              },
      ],
    },
  });
  final result = finishChartImport('ss', project, warnings);
  result.project.extensions['ssSource'] = {
    'schema': 'haneoka-ss-source-v1',
    'root': {...root}
      ..remove('score')
      ..remove('meta'),
    'score': {...score}
      ..remove('notes')
      ..remove('events'),
    'meta': chartSourceRecord(meta, {'version': version}),
    'records': records,
    'events': chartSourceRecord(events, _ssEvents(result.project, records)),
  };
  result.project.requireValid();
  return result;
}

ChartMap _encodeSsNote(ChartMap note, double scale, {bool point = false}) {
  final direction = note['direction'], type = note['type'];
  return {
    if (type != 'tap') 'type': type,
    't': note['tick'],
    'pos': note['lane'] == 'auto' ? 'auto' : (note['lane'] as num) * scale,
    if (note['autoSize'] != true) 'size': (note['size'] as num) * scale,
    if (note['critical'] == true) 'crit': true,
    if (direction == 'left' ||
        direction == 'right' ||
        direction == 'up' && type == 'trace')
      'dir': direction,
    if (note['visible'] == false) 'visible': false,
    if (point)
      'ease': (() {
        final ease = chartMap(note['ease']);
        return ease['left'] == ease['right']
            ? ease['left']
            : [ease['left'], ease['right']];
      })(),
  };
}

ChartMap _restoreSsNote(Object? record, ChartMap current) {
  final result = restoreChartRecord(record, current);
  if (record is Map && record['baseline'] is Map) {
    final baseline = chartMap(record['baseline']);
    if (baseline['type'] != current['type'] ||
        baseline['dir'] != current['dir']) {
      if (!current.containsKey('dir')) {
        result.remove('dir');
      } else {
        result['dir'] = current['dir'];
      }
    }
  }
  return result;
}

ChartMap _ssEvents(ChartProject project, Map records) => {
  'bpm': [
    for (final tempo in project.tempos)
      restoreChartRecord(records[tempo['id']], {
        't': tempo['tick'],
        'bpm': tempo['bpm'],
      }),
  ],
  'sig': [
    for (final meter in project.meters)
      restoreChartRecord(records[meter['id']], {
        't': meter['tick'],
        'sig': [meter['numerator'], meter['denominator']],
      }),
  ],
  'skill': project.markers['skill'],
  'fever': project.markers['fever'],
  'call': [
    for (final call in chartRows(project.markers['call']))
      {'t': call['tick'], 'timing': call['timing']},
  ],
};
ChartMap projectToSs(ChartProject project) {
  project.requireValid();
  final source = project.extensions['ssSource'];
  final snapshot = source is Map && source['schema'] == 'haneoka-ss-source-v1'
      ? chartMap(source)
      : <String, Object?>{};
  final records = snapshot['records'] is Map
      ? chartMap(snapshot['records'])
      : <String, Object?>{};
  final byId = <String, Object?>{};
  final scale = 24 / project.laneBasis;
  for (final note in project.singles) {
    byId['${note['id']}'] = _restoreSsNote(
      records[note['id']],
      _encodeSsNote(note, scale),
    );
  }
  for (final line in project.lines) {
    final points = stableChartSort(
      chartRows(line['points']),
      (a, b) => (a['tick'] as int).compareTo(b['tick'] as int),
    );
    byId['${line['id']}'] = {
      ...restoreChartRecord(records[line['id']], {
        'type': line['kind'],
        if (line.containsKey('critical')) 'crit': line['critical'],
      }),
      'node': [
        for (final point in points)
          _restoreSsNote(
            records[point['id']],
            _encodeSsNote(point, scale, point: true),
          ),
      ],
    };
  }
  final notes = <Object?>[];
  for (final id in project.data['sourceOrder'] as List? ?? const []) {
    if (byId.containsKey(id)) notes.add(byId.remove(id));
  }
  notes.addAll(byId.values);
  return {
    if (snapshot['root'] is Map) ...chartMap(snapshot['root']),
    'meta': restoreChartRecord(snapshot['meta'], {
      'version': chartNumber(
        project.meta['extra'] is Map
            ? (project.meta['extra'] as Map)['ssVersion']
            : null,
        1,
      ),
    }),
    'score': {
      if (snapshot['score'] is Map) ...chartMap(snapshot['score']),
      'events': restoreChartRecord(
        snapshot['events'],
        _ssEvents(project, records),
      ),
      'notes': notes,
    },
  };
}

String serializeSsChart(ChartProject project) =>
    const JsonEncoder.withIndent('  ').convert(projectToSs(project));
