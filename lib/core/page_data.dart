import 'dart:convert';
import 'dart:isolate';

import 'net.dart';
import 'api.dart';

/// Data the website builds into a page (`serializePageData`): the calendar,
/// the skill catalogue. The app reads the same published document, so both
/// show one build of the data.
Future<Map<String, Object?>> pageData(
  String path,
  String scriptId, {
  bool attribute = false,
}) async {
  final response = await netClient
      .get(Uri.parse('https://haneoka.org$path'))
      .timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    throw StateError('HTTP ${response.statusCode}');
  }
  final bytes = response.bodyBytes;
  return Isolate.run(() {
    final html = utf8.decode(bytes);
    final selector = attribute
        ? '\\s${RegExp.escape(scriptId)}(?=[\\s=>])'
        : '\\sid=["\x27]${RegExp.escape(scriptId)}["\x27]';
    final match = RegExp(
      '<script[^>]*$selector[^>]*>([\\s\\S]*?)</script>',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) throw const FormatException('page data');
    return (jsonDecode(match[1]!) as Map).cast<String, Object?>();
  });
}

final _entityPages = <String, Future<Map<String, Object?>>>{};

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
  return cachedResource(
    _entityPages,
    path,
    () => pageData(path, 'catalog-page-$resource-$id'),
  ).then<Map<String, Object?>?>((value) => value, onError: (_) => null);
}
