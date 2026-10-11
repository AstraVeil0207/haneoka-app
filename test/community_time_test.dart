import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/community/community_time.dart';

void main() {
  // Written by the browser APIs the website uses (tool/gen_community_intl.mjs).
  final fixtures = (jsonDecode(
    File('test/fixtures/community_intl.json').readAsStringSync(),
  ) as Map).cast<String, Map>();
  for (final MapEntry(key: locale, value: data) in fixtures.entries) {
    test('formats $locale dates and relative times as the browser does', () {
      final at = DateTime.utc(2026, 9, 26, 2, 44, 9);
      expect(mediumDateTime(at, locale), data['medium']);
      expect(
        mediumDateTime(at.add(const Duration(hours: 14)), locale),
        data['pm'],
      );
      final hours = (data['hours'] as List).cast<String>();
      for (var h = 0; h < 24; h++) {
        expect(
          mediumDateTime(DateTime.utc(2026, 1, 5, h, 7, 3), locale),
          hours[h],
        );
      }
      for (final row in (data['rel'] as List).cast<List>()) {
        expect(relativeTime(row[0] as int, row[1] as String, locale), row[2]);
      }
    });
  }
  test('names countries', () {
    expect(communityLocation({'countryCode': 'fr'}, 'en'), 'France');
    expect(communityLocation({'countryCode': 'XX'}, 'en'), '');
  });
}
