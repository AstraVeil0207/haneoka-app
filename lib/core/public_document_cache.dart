import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// The complete public-document identity. Decoders share these HTTP bytes.
final class PublicDocumentKey {
  const PublicDocumentKey({
    required this.uri,
    required this.server,
    this.releaseId,
    this.sourceId,
  });

  final Uri uri;
  final String server;
  final String? releaseId, sourceId;
  String get origin => uri.origin;
  String get identity =>
      '$origin\u0000$server\u0000${releaseId ?? ''}'
      '\u0000${sourceId ?? ''}\u0000$uri';

  @override
  bool operator ==(Object other) =>
      other is PublicDocumentKey && identity == other.identity;
  @override
  int get hashCode => identity.hashCode;
}

final class StoredPublicDocument {
  const StoredPublicDocument({
    required this.bytes,
    required this.digest,
    required this.validatedAt,
    this.etag,
    this.lastModified,
  });

  final Uint8List bytes;
  final String digest;
  final DateTime validatedAt;
  final String? etag, lastModified;

  StoredPublicDocument validatedNow() => StoredPublicDocument(
    bytes: bytes,
    digest: digest,
    validatedAt: DateTime.now(),
    etag: etag,
    lastModified: lastModified,
  );
}

/// Platform storage owns atomic writes, cache eviction and clear generations.
abstract interface class PublicDocumentStorage {
  int get generation;
  Future<StoredPublicDocument?> read(PublicDocumentKey key);
  Future<void> write(
    PublicDocumentKey key,
    StoredPublicDocument document,
    int generation,
  );
}

final class PublicDocumentChange {
  const PublicDocumentChange(this.key, this.revision);
  final PublicDocumentKey key;
  final int revision;
}

final class _MemoryDocument {
  _MemoryDocument(this.document);
  StoredPublicDocument document;
  final decoded = <String, Object?>{};
  final decoders = <String, FutureOr<Object?> Function(Uint8List)>{};
  int get weight => document.bytes.length * (1 + decoded.length * 3);
}

/// Public, unauthenticated HTTP documents with shared bytes and per-codec data.
/// A cached result is returned before conditional background revalidation.
final class PublicDocumentCache {
  PublicDocumentCache({
    required this.client,
    required PublicDocumentStorage storage,
    this.memoryBudget = 32 << 20,
  }) : _storage = storage,
       _generation = storage.generation;

  final http.Client client;
  final PublicDocumentStorage _storage;
  final int memoryBudget;
  int _generation, _revision = 0, _epoch = 0;
  final _memory = <PublicDocumentKey, _MemoryDocument>{};
  final _opening = <PublicDocumentKey, Future<StoredPublicDocument?>>{};
  final _refreshing = <PublicDocumentKey, Future<StoredPublicDocument>>{};
  final _downloads = <Uri, Future<http.Response>>{};
  final _decoding = <String, Future<Object?>>{};
  final _queued = <PublicDocumentKey, Timer>{};
  final _retryAt = <PublicDocumentKey, DateTime>{};
  final _changes = StreamController<PublicDocumentChange>.broadcast();
  Stream<PublicDocumentChange> get changes => _changes.stream;

  void _syncGeneration() {
    if (_generation != _storage.generation) invalidate();
  }

  /// Clearing disk data must also clear retained decoded values and old jobs.
  void invalidate() {
    _epoch++;
    _generation = _storage.generation;
    _memory.clear();
    _opening.clear();
    _refreshing.clear();
    _downloads.clear();
    _decoding.clear();
    for (final timer in _queued.values) {
      timer.cancel();
    }
    _queued.clear();
    _retryAt.clear();
  }

  T? peek<T>(PublicDocumentKey key, String decodeVariant) {
    _syncGeneration();
    final entry = _touch(key);
    if (entry == null || !entry.decoded.containsKey(decodeVariant)) return null;
    return entry.decoded[decodeVariant] as T;
  }

  _MemoryDocument? _touch(PublicDocumentKey key) {
    final entry = _memory.remove(key);
    if (entry != null) _memory[key] = entry;
    return entry;
  }

  void _retain(PublicDocumentKey key, _MemoryDocument entry) {
    _memory.remove(key);
    _memory[key] = entry;
    var weight = _memory.values.fold<int>(
      0,
      (sum, value) => sum + value.weight,
    );
    while (_memory.isNotEmpty && weight > memoryBudget) {
      final first = _memory.keys.first;
      weight -= _memory.remove(first)!.weight;
    }
  }

  /// Read existing bytes without starting a network request (release startup).
  Future<StoredPublicDocument?> lookup(PublicDocumentKey key) {
    _syncGeneration();
    if (_touch(key) case final cached?) {
      return Future.value(cached.document);
    }
    if (_opening[key] case final existing?) return existing;
    late final Future<StoredPublicDocument?> pending;
    pending = _open(key).whenComplete(() {
      if (identical(_opening[key], pending)) _opening.remove(key);
    });
    return _opening[key] = pending;
  }

  Future<StoredPublicDocument?> _open(PublicDocumentKey key) async {
    final generation = _generation;
    final epoch = _epoch;
    final StoredPublicDocument? document;
    try {
      document = await _storage.read(key);
    } on Exception {
      return null;
    }
    if (document != null &&
        generation == _storage.generation &&
        epoch == _epoch) {
      _retain(key, _MemoryDocument(document));
    }
    return document;
  }

  Future<T> read<T>({
    required PublicDocumentKey key,
    required String decodeVariant,
    required FutureOr<T> Function(Uint8List bytes) decode,
    Duration? revalidateAfter = const Duration(minutes: 5),
  }) async {
    _syncGeneration();
    final generation = _generation;
    final epoch = _epoch;
    final cached = await lookup(key);
    final document = cached ?? await _refresh(key);
    if (cached != null &&
        revalidateAfter != null &&
        DateTime.now().difference(cached.validatedAt) >= revalidateAfter) {
      _schedule(key);
    }
    final retained = _touch(key);
    if (retained != null &&
        retained.document.digest == document.digest &&
        retained.decoded.containsKey(decodeVariant)) {
      return retained.decoded[decodeVariant] as T;
    }
    final id = '${key.identity}\u0000$decodeVariant\u0000${document.digest}';
    late final Future<Object?> pending;
    pending = _decoding[id] ??= Future<T>.sync(() => decode(document.bytes))
        .then<Object?>((value) {
          if (generation == _storage.generation && epoch == _epoch) {
            final entry = _touch(key);
            if (entry != null && entry.document.digest == document.digest) {
              entry.decoded[decodeVariant] = value;
              entry.decoders[decodeVariant] = decode;
              _retain(key, entry);
            }
          }
          return value;
        })
        .whenComplete(() {
          if (identical(_decoding[id], pending)) _decoding.remove(id);
        });
    try {
      return await pending as T;
    } on FormatException {
      _schedule(key);
      rethrow;
    }
  }

  void _schedule(PublicDocumentKey key) {
    if (_queued.containsKey(key) ||
        _refreshing.containsKey(key) ||
        (_retryAt[key]?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    _queued[key] = Timer(const Duration(milliseconds: 250), () {
      _queued.remove(key);
      unawaited(refresh(key).catchError((Object _) {}));
    });
  }

  Future<void> refresh(PublicDocumentKey key) async {
    _syncGeneration();
    _queued.remove(key)?.cancel();
    await _refresh(key);
  }

  Future<StoredPublicDocument> _refresh(PublicDocumentKey key) {
    if (_refreshing[key] case final existing?) return existing;
    late final Future<StoredPublicDocument> pending;
    pending = _fetch(key).whenComplete(() {
      if (identical(_refreshing[key], pending)) _refreshing.remove(key);
    });
    return _refreshing[key] = pending;
  }

  Future<http.Response> _download(Uri uri, StoredPublicDocument? previous) {
    if (_downloads[uri] case final existing?) return existing;
    final headers = <String, String>{'accept': '*/*'};
    if (previous?.etag != null) {
      headers['if-none-match'] = previous!.etag!;
    } else if (previous?.lastModified != null) {
      headers['if-modified-since'] = previous!.lastModified!;
    }
    late final Future<http.Response> pending;
    pending = client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 30))
        .whenComplete(() {
          if (identical(_downloads[uri], pending)) _downloads.remove(uri);
        });
    return _downloads[uri] = pending;
  }

  Future<StoredPublicDocument> _fetch(PublicDocumentKey key) async {
    final generation = _generation;
    final epoch = _epoch;
    final previous = await lookup(key);
    try {
      var response = await _download(key.uri, previous);
      // Another scope can share this URI's conditional request but lack its body.
      if (response.statusCode == 304 && previous == null) {
        response = await _download(key.uri, null);
      }
      final StoredPublicDocument document;
      if (response.statusCode == 304 && previous != null) {
        document = previous.validatedNow();
      } else if (response.statusCode == 200) {
        final servedRelease = response.headers['x-haneoka-release-id'];
        if (key.releaseId != null &&
            servedRelease != null &&
            servedRelease != key.releaseId) {
          throw http.ClientException('Release snapshot changed', key.uri);
        }
        final bytes = response.bodyBytes;
        document = StoredPublicDocument(
          bytes: bytes,
          digest: sha256.convert(bytes).toString(),
          validatedAt: DateTime.now(),
          etag: response.headers['etag'],
          lastModified: response.headers['last-modified'],
        );
      } else {
        throw http.ClientException('HTTP ${response.statusCode}', key.uri);
      }
      if (generation == _storage.generation && epoch == _epoch) {
        final oldEntry = _touch(key);
        final entry = oldEntry?.document.digest == document.digest
            ? oldEntry!
            : _MemoryDocument(document);
        if (!identical(entry, oldEntry) && oldEntry != null) {
          // Validate all consumed variants before replacing a working page.
          // Failed parsing keeps both the old raw body and decoded values.
          for (final decoder in oldEntry.decoders.entries) {
            entry.decoded[decoder.key] = await decoder.value(document.bytes);
            entry.decoders[decoder.key] = decoder.value;
          }
        }
        if (generation != _storage.generation || epoch != _epoch) {
          return document;
        }
        entry.document = document;
        _retain(key, entry);
        try {
          await _storage.write(key, document, generation);
        } on Exception {
          // Disk pressure does not discard a successful public response.
        }
        _retryAt.remove(key);
        if (previous != null && previous.digest != document.digest) {
          _changes.add(PublicDocumentChange(key, ++_revision));
        }
      }
      return document;
    } catch (_) {
      _retryAt[key] = DateTime.now().add(const Duration(minutes: 1));
      rethrow;
    }
  }
}
