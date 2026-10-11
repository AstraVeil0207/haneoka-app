import 'dart:convert';
import 'dart:isolate';

import 'net.dart';

/// Data the website builds into a page (`serializePageData`): the calendar,
/// the skill catalogue. The app reads the same published document, so both
/// show one build of the data.
Future<Map<String, Object?>> pageData(String path, String scriptId) async {
  final response = await netClient.get(Uri.parse('https://haneoka.org$path'));
  if (response.statusCode != 200) {
    throw StateError('HTTP ${response.statusCode}');
  }
  final bytes = response.bodyBytes;
  return Isolate.run(() {
    final html = utf8.decode(bytes);
    final match = RegExp(
      '<script[^>]*id="$scriptId"[^>]*>([\\s\\S]*?)</script>',
    ).firstMatch(html);
    if (match == null) throw const FormatException('page data');
    return (jsonDecode(match[1]!) as Map).cast<String, Object?>();
  });
}
