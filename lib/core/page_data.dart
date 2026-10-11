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

final _entityPages = <String, Future<Map<String, Object?>?>>{};

/// The payload an entity page is built from (`catalog-page-{resource}-{id}`):
/// the entity, the marks and game items it shows, and `aux` with its
/// progression and resolved associations. Null when the page does not exist.
Future<Map<String, Object?>?> entityPage(
  String server,
  String locale,
  String resource,
  String id,
) {
  final kind = resource == 'cards' ? 'member-cards' : resource;
  final path = '/$server/$locale/$kind/${Uri.encodeComponent(id)}/';
  return _entityPages[path] ??= pageData(path, 'catalog-page-$resource-$id')
      .then<Map<String, Object?>?>(
        (v) => v,
        onError: (_) {
          _entityPages.remove(path);
          return null;
        },
      );
}
