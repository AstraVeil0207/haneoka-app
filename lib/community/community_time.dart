import 'package:intl/intl.dart';

import 'intl.g.dart';

/// The website's community times and places (`lib/community-time.ts`,
/// `lib/community-comment-metadata.ts`), with the browser's ICU wording.

/// API timestamps in milliseconds; seconds are scaled up.
int? communityTimestamp(Object? value) {
  num? number = switch (value) {
    final num n => n,
    final String s when s.trim().isNotEmpty => num.tryParse(s.trim()),
    _ => null,
  };
  if (number == null && value is String) {
    return DateTime.tryParse(value.trim())?.millisecondsSinceEpoch;
  }
  if (number == null || !number.isFinite) return null;
  return (number.abs() < 1e12 ? number * 1000 : number).round();
}

bool isEdited(Object? createdAt, Object? lastEditedAt) {
  final created = communityTimestamp(createdAt);
  final edited = communityTimestamp(lastEditedAt);
  return created != null && edited != null && edited > created;
}

String _two(int n) => n.toString().padLeft(2, '0');
const _enMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Intl.DateTimeFormat(locale, { dateStyle: "medium", timeStyle: "medium" })`.
String mediumDateTime(DateTime at, String locale) {
  final h12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final time = '$h12:${_two(at.minute)}:${_two(at.second)}';
  final (y, m, d) = (at.year, at.month, at.day);
  return switch (locale) {
    'ja' =>
      '$y/${_two(m)}/${_two(d)} ${at.hour}:${_two(at.minute)}:${_two(at.second)}',
    'ko' => '$y. $m. $d. ${at.hour < 12 ? '오전' : '오후'} $time',
    'zh-CN' =>
      '$y年$m月$d日 ${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}',
    'zh-TW' => '$y年$m月$d日 ${zhTwDayPeriods[at.hour]}$time',
    _ => '${_enMonths[m - 1]} $d, $y, $time ${at.hour < 12 ? 'AM' : 'PM'}',
  };
}

/// `Intl.RelativeTimeFormat(locale, { numeric: "auto" }).format(value, unit)`.
String relativeTime(int value, String unit, String locale) {
  final table = (relativeTimes[locale] ?? relativeTimes['en']!)[unit]!;
  if (table['$value'] case final exact?) return exact;
  final sign = value < 0 ? 'past' : 'future';
  final n = value.abs();
  final one = locale == 'en' && n == 1;
  final template = table['$sign.${one ? 'one' : 'other'}'] ?? '';
  return template.replaceFirst(
    '{n}',
    NumberFormat.decimalPattern(locale).format(n),
  );
}

/// Within a week: relative; otherwise the exact date and time
/// (`formatCommunityTime`). [title] is always exact.
({String text, String title})? formatCommunityTime(
  Object? value,
  String locale, {
  DateTime? now,
}) {
  final timestamp = communityTimestamp(value);
  if (timestamp == null) return null;
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final exact = mediumDateTime(date, locale);
  final delta = timestamp - (now ?? DateTime.now()).millisecondsSinceEpoch;
  if (delta.abs() >= 7 * 86400000) return (text: exact, title: exact);
  final seconds = delta / 1000;
  final (int amount, String unit) = switch (seconds.abs()) {
    >= 86400 => ((seconds / 86400).round(), 'day'),
    >= 3600 => ((seconds / 3600).round(), 'hour'),
    >= 60 => ((seconds / 60).round(), 'minute'),
    _ => (seconds.round(), 'second'),
  };
  return (text: relativeTime(amount, unit, locale), title: exact);
}

/// The country a post or comment was written from, in [locale]
/// (`communityCommentLocation`).
String communityLocation(Object? value, String locale) {
  if (value is! Map) return '';
  final code = '${value['countryCode'] ?? ''}'.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code) || code == 'XX') return '';
  return (regionNames[locale] ?? regionNames['en']!)[code] ?? '';
}

/// `Intl.ListFormat(locale, { style: "long", type: "conjunction" })`.
String formatList(List<String> values, String locale) {
  final items = values.where((v) => v.isNotEmpty).toList();
  final [two, start, middle, end] =
      listSeparators[locale] ?? listSeparators['en']!;
  return switch (items.length) {
    0 => '',
    1 => items.single,
    2 => '${items[0]}$two${items[1]}',
    _ => () {
      final buffer = StringBuffer('${items[0]}$start${items[1]}');
      for (var i = 2; i < items.length - 1; i++) {
        buffer.write('$middle${items[i]}');
      }
      return '$buffer$end${items.last}';
    }(),
  };
}
