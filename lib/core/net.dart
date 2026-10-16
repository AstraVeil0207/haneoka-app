import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// The platform's own HTTP stack, as a browser uses it: Cronet on Android and
/// NSURLSession on Apple platforms speak HTTP/2 and HTTP/3 with Brotli, so
/// the dozens of artwork requests on a page share one connection instead of
/// each opening its own.
final http.Client netClient = _client();

http.Client _client() {
  if (Platform.isAndroid) {
    final engine = CronetEngine.build(
      cacheMode: CacheMode.memory,
      cacheMaxSize: 8 << 20,
      enableBrotli: true,
      enableHttp2: true,
      enableQuic: true,
      userAgent: 'haneoka-app',
    );
    return CronetClient.fromCronetEngine(engine, closeEngine: true);
  }
  if (Platform.isIOS || Platform.isMacOS) {
    final config = URLSessionConfiguration.defaultSessionConfiguration()
      ..httpMaximumConnectionsPerHost = 8
      ..waitsForConnectivity = true;
    return CupertinoClient.fromSessionConfiguration(config);
  }
  return IOClient(
    HttpClient()
      ..maxConnectionsPerHost = 12
      ..idleTimeout = const Duration(seconds: 30)
      ..userAgent = 'haneoka-app',
  );
}

/// Artwork on disk for a month, fetched through [netClient].
final CacheManager artworkCache = CacheManager(
  Config(
    'haneoka-artwork',
    // Disk capacity is managed by CacheStorage. Keep the library's own
    // count/age cleanup from imposing a hidden limit on unlimited mode.
    stalePeriod: const Duration(days: 3650),
    maxNrOfCacheObjects: 1 << 30,
    fileService: _ArtworkFileService(httpClient: netClient),
  ),
);

final class _ArtworkFileService extends HttpFileService {
  _ArtworkFileService({required super.httpClient});

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await super.get(url, headers: headers);
    // CacheManager skips the body on errors and 304. Drain it so shared
    // connections remain available for catalogue and playback requests.
    if (response.statusCode != 200 && response.statusCode != 202) {
      await response.content.drain<void>();
    }
    return response;
  }
}
