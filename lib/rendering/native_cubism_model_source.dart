import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';
import 'package:vega_plugin_haneoka/native_cubism.dart'
    show retainNativeCubismModelSourceRecord, NativeCubismUnityPrefab;

import '../core/api.dart';
import '../core/background_work.dart';
import '../core/resource_file_cache.dart';
import 'native_unity_source_archive.dart';

/// Loads the actual registered model variant from one source release. Generic
/// Cubism parsing/evaluation lives in the renderer's separate native backend.
final class NativeCubismModelSource {
  NativeCubismModelSource._({
    required this.identity,
    required this.key,
    required this.catalog,
    required this.records,
    required this.preparedPrefab,
    required this.mocBytes,
    required this.archiveHash,
    required this.mocHash,
  });
  final StorySourceIdentity identity;
  final String key, archiveHash, mocHash;
  final Map<String, Object?> catalog;
  final List<Map> records;
  final NativeCubismUnityPrefab preparedPrefab;
  final Uint8List mocBytes;

  static Future<NativeCubismModelSource> load(
    HaneokaApi api,
    StorySourceIdentity identity,
    String actualRegisteredKey,
    bool Function() ownerAlive, {
    void Function(String phase, int microseconds)? onTiming,
  }) async {
    final timer = Stopwatch()..start();
    if (actualRegisteredKey.isEmpty || api.server != identity.server) {
      throw const FormatException('native_model_source_identity');
    }
    void checkOwner() {
      if (!ownerAlive()) throw StateError('native_model_source_cancelled');
    }

    Future<Uint8List> read(String path, int limit) async {
      checkOwner();
      final uri = api
          .asset(path)
          .replace(queryParameters: {'release': identity.release});
      final bytes = await resourceFileCache.readBytes(
        uri,
        kind: ResourceFileKind.renderResource,
      );
      checkOwner();
      if (bytes.length > limit) {
        throw StateError('native_model_source_size:$path');
      }
      return bytes;
    }

    Future<Map> readJson(String path) async {
      final decoded = jsonDecode(
        utf8.decode(await read(path, 16 * 1024 * 1024)),
      );
      if (decoded is! Map) {
        throw FormatException('native_model_source_json:$path');
      }
      return decoded;
    }

    final catalog = await readJson(
      '/api/v1/servers/${identity.server}/live2d/'
      '${Uri.encodeComponent(actualRegisteredKey)}',
    );
    onTiming?.call('catalog', timer.elapsedMicroseconds);
    timer.reset();
    if (catalog['live2dKey'] != actualRegisteredKey) {
      throw const FormatException('native_model_source_variant');
    }
    final sourcePath = catalog['sourcePath'];
    if (sourcePath is! String ||
        !sourcePath.startsWith('Assets/') ||
        !sourcePath.endsWith('.prefab') ||
        sourcePath.contains('..')) {
      throw const FormatException('native_model_source_prefab');
    }
    final archive = await NativeUnitySourceArchive.load(
      api: api,
      identity: identity,
      sourcePath: sourcePath,
      current: ownerAlive,
      onTiming: (phase, us) => onTiming?.call('archive.$phase', us),
      decodeOffThread: true,
      retain: retainNativeCubismModelSourceRecord,
      prepareRecords: NativeCubismUnityPrefab.new,
    );
    onTiming?.call('archive.total', timer.elapsedMicroseconds);
    timer.reset();
    final runtime = catalog['runtime'];
    final moc = runtime is Map ? runtime['moc'] : null;
    if (moc is! String ||
        !moc.startsWith('/runtime/${identity.server}/') ||
        moc.contains('..') ||
        !moc.endsWith('.moc3')) {
      throw const FormatException('native_model_moc_reference');
    }
    final mocBytes = await read(moc, 32 * 1024 * 1024);
    onTiming?.call('moc', timer.elapsedMicroseconds);
    checkOwner();
    timer.reset();
    final mocHash = await runBackgroundWork(
      _MocHashInput(mocBytes).compute,
      checkCurrent: checkOwner,
      debugName: 'cubism-moc-hash',
    );
    onTiming?.call('mocHash', timer.elapsedMicroseconds);
    return NativeCubismModelSource._(
      identity: identity,
      key: actualRegisteredKey,
      catalog: Map.unmodifiable(catalog.cast<String, Object?>()),
      records: archive.records,
      preparedPrefab: archive.preparedRecords! as NativeCubismUnityPrefab,
      mocBytes: mocBytes,
      archiveHash: archive.archiveHash,
      mocHash: mocHash,
    );
  }
}

final class _MocHashInput {
  const _MocHashInput(this.bytes);
  final Uint8List bytes;
  String compute() => sha256.convert(bytes).toString();
}
