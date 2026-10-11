import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/community/markup.dart';

void main() {
  // Produced by the website's communityMarkup and communityExcerpt.
  final cases = jsonDecode(
    File('test/fixtures/community_markup.json').readAsStringSync(),
  ) as List;
  for (final entry in cases.cast<Map>()) {
    test('renders ${jsonEncode(entry['source'])} as the website does', () {
      expect(communityMarkup(entry['source'] as String), entry['html']);
      expect(communityExcerpt(entry['source'] as String), entry['excerpt']);
    });
  }
}
