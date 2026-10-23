import 'dart:convert';

import 'formats.dart';
import 'project.dart';

ChartImport importUscChart(Object? input, {double laneBasis = 24}) {
  final root = chartMap(input), wrapped = root['usc'] is Map;
  final usc = wrapped ? chartMap(root['usc']) : root;
  if (usc['objects'] is! List) throw const FormatException('usc.objects');
  final warnings = <ChartIssue>[];
  final project = ChartProject.empty({
    'source': 'usc',
    if (wrapped && root['version'] is num)
      'extra': {'uscVersion': root['version']},
  });
  project.data['laneBasis'] = laneBasis;
  project.meters.first['id'] = 'usc-meter-0';
  final tempos = <ChartMap>[],
      scales = <ChartMap>[],
      singles = <ChartMap>[],
      lines = <ChartMap>[];
  final order = <String>[];
  int tick(Object? value, String path) {
    if (value is! num || !value.isFinite) {
      throw FormatException('usc.beat', path);
    }
    final tick = (value * 480 + .5).floor();
    if ((tick / 480 - value).abs() > 1e-7) {
      warnings.add(ChartIssue('usc.beat.rounded', path, true));
    }
    return tick;
  }

  bool spatial(Map value) =>
      value['lane'] is num &&
      value['size'] is num &&
      (value['lane'] as num).isFinite &&
      (value['size'] as num).isFinite;
  (double, double) shape(Map value) {
    final width = (value['size'] as num) * laneBasis / 6;
    return (((value['lane'] as num) + 6) * laneBasis / 12 - width / 2, width);
  }

  ChartMap note(Map raw, String id, String path, (double, double) position) {
    final direction = const {'left', 'up', 'right'}.contains(raw['direction'])
        ? '${raw['direction']}'
        : 'none';
    final type = raw['trace'] == true
        ? 'trace'
        : direction == 'none'
        ? 'tap'
        : 'flick';
    return {
      'id': id,
      'tick': tick(raw['beat'], '$path.beat'),
      'lane': position.$1,
      'size': position.$2,
      'type': type,
      'critical': raw['critical'] == true,
      'direction': direction,
      'visible': true,
    };
  }

  for (final (i, raw) in (usc['objects'] as List).indexed) {
    final path = '\$.objects[$i]';
    if (raw is! Map) {
      warnings.add(ChartIssue('usc.object.skipped', path, true));
      continue;
    }
    switch (raw['type']) {
      case 'bpm':
        final id = 'usc-tempo-$i';
        tempos.add({
          'id': id,
          'tick': tick(raw['beat'], '$path.beat'),
          'bpm': chartNumber(raw['bpm']),
        });
        order.add(id);
      case 'timeScale':
        final id = 'usc-timeScale-$i';
        scales.add({
          'id': id,
          'tick': tick(raw['beat'], '$path.beat'),
          'scale': chartNumber(raw['timeScale']),
        });
        order.add(id);
      case 'single':
        if (!spatial(raw)) throw FormatException('usc.shape', path);
        final id = 'usc-single-$i';
        singles.add(note(raw, id, path, shape(raw)));
        order.add(id);
      case 'slide':
        final connections = raw['connections'];
        if (connections is! List) {
          throw FormatException('usc.connections', path);
        }
        final points = <ChartMap>[];
        for (final (j, connection) in connections.indexed) {
          final pointPath = '$path.connections[$j]';
          if (connection is! Map ||
              !const {
                'start',
                'tick',
                'end',
                'ignore',
                'hidden',
                'attach',
              }.contains(connection['type'])) {
            warnings.add(ChartIssue('usc.connection.skipped', pointPath, true));
            continue;
          }
          (double, double)? position;
          if (spatial(connection)) {
            position = shape(connection);
          } else {
            Map? left, right;
            for (var l = j - 1; l >= 0; l--) {
              if (connections[l] is Map && spatial(connections[l] as Map)) {
                left = connections[l] as Map;
                break;
              }
            }
            for (var r = j + 1; r < connections.length; r++) {
              if (connections[r] is Map && spatial(connections[r] as Map)) {
                right = connections[r] as Map;
                break;
              }
            }
            if (left == null && right != null) {
              position = shape(right);
            } else if (right == null && left != null) {
              position = shape(left);
            } else if (left != null && right != null) {
              final beat = chartNumber(connection['beat']);
              final a = chartNumber(left['beat'], beat),
                  b = chartNumber(right['beat'], beat);
              final t = b == a ? 0.0 : ((beat - a) / (b - a)).clamp(0.0, 1.0);
              position = shape({
                'lane':
                    (left['lane'] as num) +
                    ((right['lane'] as num) - (left['lane'] as num)) * t,
                'size':
                    (left['size'] as num) +
                    ((right['size'] as num) - (left['size'] as num)) * t,
              });
            }
            warnings.add(
              ChartIssue('usc.${connection['type']}.degraded', pointPath, true),
            );
          }
          if (position == null) {
            warnings.add(ChartIssue('usc.connection.noShape', pointPath, true));
            continue;
          }
          String ease(Object? value) =>
              const {'in', 'out'}.contains(value) ? '$value' : 'linear';
          final point = note(
            connection,
            'usc-line-$i-point-$j',
            pointPath,
            position,
          );
          point.addAll({
            'visible': !const {
              'ignore',
              'hidden',
              'attach',
            }.contains(connection['type']),
            'ease': {
              'left': ease(connection['easeL'] ?? connection['ease']),
              'right': ease(connection['easeR'] ?? connection['ease']),
            },
          });
          points.add(point);
        }
        if (points.length < 2) {
          warnings.add(ChartIssue('usc.slide.skipped', path, true));
          continue;
        }
        final id = 'usc-line-$i';
        lines.add({
          'id': id,
          'kind': raw['active'] == false ? 'guide' : 'long',
          'critical': raw['critical'] == true,
          'points': stableChartSort(
            points,
            (a, b) => (a['tick'] as int).compareTo(b['tick'] as int),
          ),
        });
        order.add(id);
      default:
        warnings.add(ChartIssue('usc.object.unknown', path, true));
    }
  }
  project.data.addAll({
    'audioOffset': chartNumber(usc['offset']),
    'tempos': tempos,
    'timeScales': scales,
    'singles': singles,
    'lines': lines,
    'sourceOrder': order,
  });
  return finishChartImport('usc', project, warnings);
}

ChartMap projectToUsc(ChartProject project) {
  project.requireValid();
  final byId = <String, ChartMap>{};
  ChartMap position(double lane, double width) => {
    'lane': (lane + width / 2) * 12 / project.laneBasis - 6,
    'size': width * 6 / project.laneBasis,
  };
  ChartMap direction(ChartMap note) => {
    if (note['direction'] != 'none')
      'direction': note['direction']
    else if (note['type'] == 'flick')
      'direction': 'up',
  };
  for (final tempo in project.tempos) {
    byId['${tempo['id']}'] = {
      'type': 'bpm',
      'beat': (tempo['tick'] as int) / 480,
      'bpm': tempo['bpm'],
    };
  }
  for (final scale in project.timeScales) {
    byId['${scale['id']}'] = {
      'type': 'timeScale',
      'beat': (scale['tick'] as int) / 480,
      'timeScale': scale['scale'],
    };
  }
  for (final note in project.singles) {
    byId['${note['id']}'] = {
      'type': 'single',
      'beat': (note['tick'] as int) / 480,
      ...position(
        (note['lane'] as num).toDouble(),
        (note['size'] as num).toDouble(),
      ),
      'trace': note['type'] == 'trace',
      'critical': note['critical'],
      ...direction(note),
    };
  }
  for (final line in project.lines) {
    final points = stableChartSort(
      chartRows(line['points']),
      (a, b) => (a['tick'] as int).compareTo(b['tick'] as int),
    );
    final shapes = resolveChartPoints(points);
    final connections = <ChartMap>[];
    for (final (i, note) in points.indexed) {
      final shape = shapes[i], ease = chartMap(note['ease']);
      final common = <String, Object?>{
        'beat': (note['tick'] as int) / 480,
        ...position(shape.$1, shape.$2),
      };
      final easing = {
        'ease': ease['right'],
        'easeL': ease['left'],
        'easeR': ease['right'],
      };
      if (line['kind'] == 'guide' || note['visible'] == false) {
        connections.add({'type': 'ignore', ...common, ...easing});
      } else if (i == points.length - 1) {
        connections.add({
          'type': 'end',
          ...common,
          'trace': note['type'] == 'trace',
          'critical': note['critical'],
          ...direction(note),
        });
      } else {
        connections.add({
          'type': i == 0 ? 'start' : 'tick',
          ...common,
          'trace': note['type'] == 'trace',
          'critical': note['critical'],
          ...easing,
        });
      }
    }
    byId['${line['id']}'] = {
      'type': 'slide',
      'active': line['kind'] == 'long',
      'critical': line['critical'] ?? points.any((p) => p['critical'] == true),
      'connections': connections,
    };
  }
  final objects = <Object?>[];
  for (final id in project.data['sourceOrder'] as List? ?? const []) {
    if (byId.containsKey(id)) objects.add(byId.remove(id));
  }
  objects.addAll(byId.values);
  return {'offset': project.audioOffset, 'objects': objects};
}

String serializeUscChart(ChartProject project, {bool wrapped = false}) =>
    const JsonEncoder.withIndent('  ').convert(
      wrapped
          ? {'version': 2, 'usc': projectToUsc(project)}
          : projectToUsc(project),
    );
