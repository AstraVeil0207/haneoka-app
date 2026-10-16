/// App.Master.MissionCategory, in the same tab order as the web catalogue.
const missionCategoryOrder = [
  1,
  2,
  4,
  5,
  15,
  16,
  6,
  11,
  12,
  8,
  3,
  7,
  10,
  13,
  14,
  9,
  0,
];

num _number(Object? value) =>
    value is num ? value : num.tryParse('$value') ?? 0;

num missionTimestamp(Object? value, int localeIndex) {
  if (value is List) {
    value = localeIndex >= 0 && localeIndex < value.length
        ? value[localeIndex] ?? value.firstOrNull
        : value.firstOrNull;
  }
  return _number(value);
}

int missionCategory(Map mission) {
  final group = _number(mission['groupCategory']);
  if (group != 0) return group.toInt();
  if (mission.containsKey('category')) {
    return _number(mission['category']).toInt();
  }
  final id = RegExp(r'^regular-mission-(\d+)$')
      .firstMatch('${mission['id']}')?[1];
  return id == null ? 0 : (int.parse(id) / 100000000).floor();
}

class MissionGroup {
  MissionGroup({
    required this.key,
    required this.category,
    required this.releaseDay,
    required this.timed,
    required this.start,
    required this.end,
    required this.rows,
  });
  final String key;
  final int category;
  final int releaseDay;
  final bool timed;
  final num start;
  final num end;
  final List<Map> rows;
}

String missionGroupStatus(MissionGroup group, num now) {
  if (group.end != 0 && group.end <= now) return 'ended';
  if (group.start > now) return 'upcoming';
  return 'ongoing';
}

String _numericKey(num value) =>
    value == value.toInt() ? '${value.toInt()}' : '$value';

// Mission ids consist of a source prefix and a numeric Master id.
int _compareIds(Object? a, Object? b) {
  final left = RegExp(r'\d+|\D+').allMatches('$a').map((m) => m[0]!).toList();
  final right = RegExp(r'\d+|\D+').allMatches('$b').map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final ln = BigInt.tryParse(left[i]), rn = BigInt.tryParse(right[i]);
    final c = ln != null && rn != null
        ? ln.compareTo(rn)
        : left[i].compareTo(right[i]);
    if (c != 0) return c;
  }
  return left.length.compareTo(right.length);
}

List<MissionGroup> groupMissions(List<Map> missions, int localeIndex) {
  final groups = <String, MissionGroup>{};
  for (final mission in missions) {
    final category = missionCategory(mission);
    final day = category == 5 ? _number(mission['releaseDay']).toInt() : 0;
    final start = missionTimestamp(mission['startAt'], localeIndex);
    final end = missionTimestamp(mission['endAt'], localeIndex);
    final timed = const [2, 3, 10, 13, 14].contains(category) || end > 0;
    final windowStart = timed ? start : 0, windowEnd = timed ? end : 0;
    final key = timed || category == 5
        ? [
            category,
            mission['kind'] ?? '',
            _numericKey(_number(mission['groupId'])),
            _numericKey(windowStart),
            _numericKey(windowEnd),
            day,
          ].join(':')
        : '$category';
    (groups[key] ??= MissionGroup(
      key: key,
      category: category,
      releaseDay: day,
      timed: timed,
      start: windowStart,
      end: windowEnd,
      rows: [],
    )).rows.add(mission);
  }
  for (final group in groups.values) {
    group.rows.sort((a, b) {
      final priority = _number(a['priority']).compareTo(_number(b['priority']));
      return priority != 0 ? priority : _compareIds(a['id'], b['id']);
    });
  }
  return groups.values.toList()..sort((a, b) {
    final category = missionCategoryOrder
        .indexOf(a.category)
        .compareTo(missionCategoryOrder.indexOf(b.category));
    if (category != 0) return category;
    final day = a.releaseDay.compareTo(b.releaseDay);
    if (day != 0) return day;
    final start = b.start.compareTo(a.start);
    return start != 0 ? start : a.key.compareTo(b.key);
  });
}
