import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'net.dart';
import 'storage.dart';

enum ResourceFileKind { media, renderResource }

final resourceFileCache = ResourceFileCache();

final class ResourceCacheCancelled implements Exception {
  const ResourceCacheCancelled();
}

/// The original URI remains the resource identity; resource consumers use [file].
final class ResourceFileLease {
  ResourceFileLease._(this.uri, this.file, this._lease);
  final Uri uri;
  final File file;
  final StorageLease? _lease;
  Future<Uint8List> readBytes() => file.readAsBytes();
  Future<void> release() async => _lease?.release();
}

final class _ResourceDownload {
  final aborted = Completer<void>();
  late final Future<File> file;
  int users = 0;
  bool done = false;
}

/// Shared original resource files, independent of artwork and JSON documents.
/// Downloads are streamed to disk; memory is allocated only by explicit reads.
final class ResourceFileCache {
  final _downloads = <String, _ResourceDownload>{};
  int _temporaryId = 0;

  Future<ResourceFileLease> acquire(
    Uri uri, {
    required ResourceFileKind kind,
    Future<void>? cancelled,
  }) async {
    if (uri.scheme == 'file') {
      return ResourceFileLease._(uri, File.fromUri(uri), null);
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw UnsupportedError('resource_cache_uri:${uri.scheme}');
    }
    final storage = CacheStorage.instance;
    await storage.initialize();
    final category = kind == ResourceFileKind.media
        ? CacheCategory.media
        : CacheCategory.resources;
    final generation = storage.fileGeneration(category);
    final key = sha256.convert(utf8.encode(uri.toString())).toString();
    final directory = kind == ResourceFileKind.media
        ? await storage.mediaRoot
        : await storage.resourceRoot;
    final file = File(p.join(directory.path, '$generation', '$key.resource'));
    final lease = storage.lease([file.path]);
    final flightKey = '${kind.name}:$generation:$key';
    final download = _downloads.putIfAbsent(flightKey, () {
      final work = _ResourceDownload();
      work.file = _load(uri, file, category, generation, work).whenComplete(() {
        work.done = true;
        if (identical(_downloads[flightKey], work)) {
          _downloads.remove(flightKey);
        }
      });
      return work;
    });
    download.users++;
    try {
      await Future.any<File>([
        download.file,
        if (cancelled != null)
          cancelled.then<File>((_) => throw const ResourceCacheCancelled()),
      ]);
      return ResourceFileLease._(uri, file, lease);
    } catch (_) {
      await lease.release();
      rethrow;
    } finally {
      download.users--;
      if (download.users == 0 && !download.done) {
        if (identical(_downloads[flightKey], download)) {
          _downloads.remove(flightKey);
        }
        if (!download.aborted.isCompleted) download.aborted.complete();
      }
    }
  }

  Future<Uint8List> readBytes(
    Uri uri, {
    required ResourceFileKind kind,
    Future<void>? cancelled,
  }) async {
    final lease = await acquire(uri, kind: kind, cancelled: cancelled);
    try {
      return await lease.readBytes();
    } finally {
      await lease.release();
    }
  }

  Future<File> _load(
    Uri uri,
    File file,
    CacheCategory category,
    int generation,
    _ResourceDownload work,
  ) async {
    final storage = CacheStorage.instance;
    if (storage.canRead(file.path) &&
        await file.exists() &&
        await file.length() > 0) {
      try {
        await file.setLastAccessed(DateTime.now());
      } on FileSystemException {
        // A readable cached file remains usable when timestamps are read-only.
      }
      return file;
    }
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.${_temporaryId++}.tmp',
    );
    try {
      return await storage.protect([file.path, temporary.path], () async {
        if (!storage.permitFileWrite(category, generation, file.path)) {
          throw const ResourceCacheCancelled();
        }
        final request = http.AbortableRequest(
          'GET',
          uri,
          abortTrigger: work.aborted.future,
        );
        final response = await netClient.send(request);
        if (response.statusCode != HttpStatus.ok) {
          await response.stream.drain<void>();
          throw http.ClientException(
            'Resource HTTP ${response.statusCode}',
            uri,
          );
        }
        final body = StreamIterator(response.stream);
        RandomAccessFile? output;
        var length = 0;
        try {
          await file.parent.create(recursive: true);
          output = await temporary.open(mode: FileMode.write);
          while (await body.moveNext()) {
            final bytes = body.current;
            await output.writeFrom(bytes);
            length += bytes.length;
          }
          await output.flush();
        } finally {
          await body.cancel();
          await output?.close();
        }
        final encoding = response.headers['content-encoding'];
        final expected = encoding == null || encoding == 'identity'
            ? response.contentLength
            : null;
        if (length == 0 || (expected != null && length != expected)) {
          throw http.ClientException('Incomplete resource response', uri);
        }
        if (work.aborted.isCompleted ||
            !storage.permitFileWrite(category, generation, file.path)) {
          throw const ResourceCacheCancelled();
        }
        await temporary.rename(file.path);
        storage.scheduleTrim();
        return file;
      });
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Storage cleanup also recognizes interrupted .tmp files.
      }
    }
  }
}
