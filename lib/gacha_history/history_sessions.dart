import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../save/game_save.dart';
import 'history_identity.dart';

class HistorySession {
  HistorySession._(
    this.document,
    this.release,
    this.sessionKey,
    this.modifiedAt,
  );
  final Map<String, Object?> document;
  final GameRelease release;
  final String sessionKey;
  final DateTime? modifiedAt;
  String get key => '$sessionKey-${release.server}';

  static HistorySession? fromDocument(
    Object? document,
    GameRelease release,
    DateTime? modifiedAt,
  ) {
    final sessionKey = historyPersistKey(document);
    if (sessionKey == null || document is! Map) return null;
    final source = document['_certification'] as Map;
    return HistorySession._(
      {
        '_certification': {
          '_playerId': source['_playerId'],
          '_authorizationKey': source['_authorizationKey'],
          if (source['_deviceId'] is String) '_deviceId': source['_deviceId'],
        },
      },
      release,
      sessionKey,
      modifiedAt,
    );
  }
}

class HistorySessionStore {
  HistorySessionStore._();
  static final instance = HistorySessionStore._();
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'haneoka.gacha-history.sessions.v1';
  final _records = <String, HistorySession>{};
  Map<String, HistorySession> get records => Map.unmodifiable(_records);
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      final text = await _storage.read(key: _storageKey);
      if (text != null) {
        final rows = jsonDecode(text);
        if (rows is List) {
          for (final row in rows) {
            if (row is! Map) continue;
            final release = GameRelease.values
                .where((value) => value.name == row['release'])
                .firstOrNull;
            if (release == null) continue;
            final session = HistorySession.fromDocument(
              row['document'],
              release,
              DateTime.tryParse('${row['modifiedAt'] ?? ''}'),
            );
            if (session != null) _records[session.key] = session;
          }
        }
      }
    } on Exception {
      // A platform without a keyring keeps the imported session in memory.
    }
    _loaded = true;
  }

  Future<void> putAll(Iterable<HistorySession> sessions) async {
    await load();
    for (final session in sessions) {
      final previous = _records[session.key];
      if (previous?.modifiedAt != null &&
          session.modifiedAt != null &&
          session.modifiedAt!.isBefore(previous!.modifiedAt!)) {
        continue;
      }
      _records[session.key] = session;
    }
    final write = _writes.then((_) async {
      try {
        await _storage.write(
          key: _storageKey,
          value: jsonEncode([
            for (final session in _records.values)
              {
                'release': session.release.name,
                'modifiedAt': session.modifiedAt?.toUtc().toIso8601String(),
                'document': session.document,
              },
          ]),
        );
      } on Exception {
        // The active session remains usable if the platform keyring is locked.
      }
    });
    _writes = write;
    await write;
  }
}
