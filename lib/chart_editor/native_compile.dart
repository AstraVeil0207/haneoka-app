import '../chart/runtime_chart.dart';
import '../rendering/visual_profiles.dart';
import 'editing.dart';
import 'formats.dart';
import 'project.dart';

typedef NativeEditorCompilation = ({
  RuntimeChart chart,
  NativeChartVisualProfiles? profiles,
});

NativeEditorCompilation compileNativeEditorChart(ChartProject project) {
  final root = projectToSs(project),
      rows = ((root['score'] as Map)['notes'] as List).cast<Map>();
  final collections = chartCollections(project),
      groups = chartRows(collections['groups']);
  if (!groups.any((g) => g['forceNoteSpeed'] != null)) {
    return (
      chart: RuntimeChart.fromJson(root, includeVisualSource: true),
      profiles: null,
    );
  }
  final entities = <String, ChartMap>{
    for (final note in project.singles) '${note['id']}': note,
    for (final line in project.lines) '${line['id']}': line,
  };
  final ordered = <String>[];
  for (final id in project.data['sourceOrder'] as List? ?? const []) {
    if (entities.remove(id) != null) ordered.add('$id');
  }
  ordered.addAll(entities.keys);
  final all = {
    for (final row in [...project.singles, ...project.lines])
      '${row['id']}': row,
  };
  final raw = Map<Map, String>.identity(), parents = <String, String>{};
  if (ordered.length != rows.length) {
    throw const FormatException('invalid_edit');
  }
  for (final (index, id) in ordered.indexed) {
    final row = rows[index], source = all[id]!;
    raw[row] = id;
    if (source['points'] is! List) continue;
    final points = stableChartSort(
      chartRows(source['points']),
      (a, b) => (a['tick'] as int).compareTo(b['tick'] as int),
    );
    final children = (row['node'] as List).cast<Map>();
    if (children.length != points.length) {
      throw const FormatException('invalid_edit');
    }
    for (final (point, child) in points.indexed) {
      final pointId = '${child['id']}';
      raw[children[point]] = pointId;
      parents[pointId] = id;
    }
  }
  final noteSources = <int, Set<String>>{},
      lineSources = <int, Set<String>>{},
      visited = Set<Map>.identity();
  void record(Map source, int id, Map<int, Set<String>> target) {
    final canonical = raw[source];
    if (canonical == null) {
      throw const FormatException('invalid_edit');
    }
    (target[id] ??= {}).add(canonical);
    visited.add(source);
  }

  final chart = RuntimeChart.fromJson(
    root,
    includeVisualSource: true,
    sourceObserver: RuntimeChartSourceObserver(
      onNote: (source, id) => record(source, id, noteSources),
      onLine: (source, id) => record(source, id, lineSources),
    ),
  );
  if (visited.length != raw.length) {
    throw const FormatException('invalid_edit');
  }
  final members = chartMap(collections['members']),
      groupById = {for (final group in groups) group['id']: group};
  double? speed(String id) {
    final own = members[id] as Map?, parent = members[parents[id]] as Map?;
    final group = own?['groupId'] ?? parent?['groupId'];
    final value = groupById[group]?['forceNoteSpeed'];
    if (value == null) return null;
    if (value is! num || !value.isFinite || value < 1 || value > 14) {
      throw const FormatException('profile_conflict');
    }
    return value.toDouble();
  }

  double? same(Iterable<double?> values) {
    final rows = values.toList();
    if (rows.any((v) => v != rows.first)) {
      throw const FormatException('profile_conflict');
    }
    return rows.first;
  }

  final lineSpeeds = <String, double?>{};
  for (final line in project.lines) {
    final id = '${line['id']}';
    lineSpeeds[id] = same([
      speed(id),
      for (final p in chartRows(line['points'])) speed('${p['id']}'),
    ]);
  }
  final nativeLines = <int, double>{}, nativeNotes = <int, double>{};
  for (final line in chart.visualLines) {
    final sources = lineSources[line.nativeLineId];
    if (sources == null || sources.isEmpty) {
      throw const FormatException('invalid_edit');
    }
    final value = same(sources.map((id) => lineSpeeds[id]));
    if (value != null) nativeLines[line.nativeLineId] = value;
  }
  for (final note in chart.visualNotes) {
    final sources = noteSources[note.id];
    if (sources == null || sources.isEmpty) {
      throw const FormatException('invalid_edit');
    }
    final value = same(sources.map(speed));
    if (value != null) nativeNotes[note.id] = value;
  }
  return (
    chart: chart,
    profiles: NativeChartVisualProfiles(notes: nativeNotes, lines: nativeLines),
  );
}
