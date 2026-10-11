import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Haneoka's public API, the same one the website reads. Responses are kept
/// on disk per release, so a release's data is downloaded once and the app
/// works offline with what it has seen.
class HaneokaApi {
  HaneokaApi({this.origin = 'https://haneoka.org', required this.server});
  final String origin;

  /// `jp` or `intl`.
  final String server;
  final http.Client _client = http.Client();
  String? _releaseId;
  final Map<String, Future<Object?>> _inFlight = {};

  Uri asset(String path) =>
      path.startsWith('http') ? Uri.parse(path) : Uri.parse('$origin$path');

  /// The release identity; data is cached under it so a new release refetches.
  Future<String> release() async {
    if (_releaseId != null) return _releaseId!;
    try {
      final body = await _get(
        '/api/v1/servers/$server/release?projection=identity',
      ) as Map<String, Object?>;
      return _releaseId = body['releaseId'] as String;
    } on Exception {
      return _releaseId = 'offline';
    }
  }

  /// A catalogue resource (`songs`, `cards`, …) or one entity of it.
  Future<Object?> catalog(String resource, [String? id]) async {
    final path =
        '/api/v1/servers/$server/$resource${id == null ? '' : '/${Uri.encodeComponent(id)}'}'
        '${id == null && (resource == 'songs' || resource == 'stories') ? '?projection=4' : ''}';
    return json(path);
  }

  /// Any API path, through the per-release cache.
  Future<Object?> json(String path) =>
      _inFlight[path] ??= _cached(path).whenComplete(() {
        _inFlight.remove(path);
      });

  Future<Object?> _cached(String path) async {
    final release = await this.release();
    final dir = await getApplicationCacheDirectory();
    final file = File(
      p.join(
        dir.path,
        'api',
        server,
        release,
        '${base64Url.encode(utf8.encode(path)).replaceAll('=', '')}.json',
      ),
    );
    if (await file.exists()) return jsonDecode(await file.readAsString());
    try {
      final body = await _get(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(body));
      return body;
    } on Exception {
      final stale = await _latestStale(dir, path);
      if (stale != null) return stale;
      rethrow;
    }
  }

  /// The newest copy from an earlier release, for offline use.
  Future<Object?> _latestStale(Directory dir, String path) async {
    final root = Directory(p.join(dir.path, 'api', server));
    if (!await root.exists()) return null;
    final name =
        '${base64Url.encode(utf8.encode(path)).replaceAll('=', '')}.json';
    File? newest;
    await for (final release in root.list()) {
      final file = File(p.join(release.path, name));
      if (await file.exists() &&
          (newest == null ||
              (await file.lastModified()).isAfter(
                await newest.lastModified(),
              ))) {
        newest = file;
      }
    }
    return newest == null ? null : jsonDecode(await newest.readAsString());
  }

  Future<Object?> _get(String path) async {
    final response = await _client.get(
      Uri.parse('$origin$path'),
      headers: {'accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(path));
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}
