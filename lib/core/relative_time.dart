import 'package:intl/intl.dart';

import 'i18n.dart';

/// The website's relative times (`src/lib/relative-time.ts`).
extension RelativeTime on SiteText {
  /// Only authored epoch milliseconds; absent values never become 1970.
  static num? timestamp(Object? value) {
    if (value is List) {
      for (final entry in value) {
        if (timestamp(entry) case final at?) return at;
      }
      return null;
    }
    final at = value is num ? value : num.tryParse('${value ?? ''}');
    return at != null && at > 0 && at <= 8640000000000000 ? at : null;
  }

  String _time(String key, Map<String, Object?> values) =>
      call('common.time.$key', key, values);

  /// Days and hours, or hours, or minutes, as the home card rounds them.
  String span(num milliseconds) {
    final minutes = (milliseconds / 60000).round().clamp(1, 1 << 40);
    final days = minutes ~/ 1440, hours = (minutes % 1440) ~/ 60;
    final number = NumberFormat.decimalPattern(locale);
    String unit(String key, int value) =>
        _time(key, {'count': number.format(value)});
    if (days >= 1) {
      return hours > 0
          ? '${unit('spanDays', days)} ${unit('spanHours', hours)}'
          : unit('spanDays', days);
    }
    if (hours >= 1) return unit('spanHours', hours);
    return unit('spanMinutes', minutes);
  }

  /// "Starts in …", "ends in …", "ended … ago", or [ongoing].
  String window(Object? start, Object? end, {String ongoing = ''}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final from = timestamp(start), to = timestamp(end);
    if (from != null && to != null && to < from) return '';
    if (from != null && from > now) {
      return _time('startsIn', {'time': span(from - now)});
    }
    if (to != null) {
      return _time(to < now ? 'endedAgo' : 'endsIn', {
        'time': span((to - now).abs()),
      });
    }
    return from != null ? ongoing : '';
  }

  /// "Added 3 days ago", "added in 6 days" (`relativeRelease`).
  String release(Object? value) {
    final at = timestamp(value);
    if (at == null) return '';
    final remaining = at - DateTime.now().millisecondsSinceEpoch;
    final days = (remaining / 86400000).round();
    if (days == 0) {
      return remaining > 0
          ? _time('releasesIn', {'time': span(remaining)})
          : _time('releasedToday', const {});
    }
    final time = _time('spanDays', {
      'count': NumberFormat.decimalPattern(locale).format(days.abs()),
    });
    return _time(days < 0 ? 'releasedAgo' : 'releasesIn', {'time': time});
  }
}

/// A game-side instant in the viewer's timezone (`gameDateTime`): the
/// numeric date and a 24-hour time, as `Intl.DateTimeFormat` writes it.
String gameDateTime(String locale, num? ms) {
  if (ms == null || ms <= 0) return '';
  final at = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  String two(int n) => n.toString().padLeft(2, '0');
  final date = (y: at.year, m: two(at.month), d: two(at.day));
  final time = '${two(at.hour)}:${two(at.minute)}';
  return switch (locale) {
    'en' => '${date.m}/${date.d}/${date.y}, $time',
    'ko' => '${date.y}. ${date.m}. ${date.d}. $time',
    _ => '${date.y}/${date.m}/${date.d} $time',
  };
}
