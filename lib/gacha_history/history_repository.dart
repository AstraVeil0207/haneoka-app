import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../save/game_save.dart';
import 'game_history_client.dart';
import 'history_snapshot.dart';
import 'history_handoff.dart';

String historySaveKey(GameSave save) => sha256
    .convert(
      utf8.encode('${save.release?.server ?? 'unknown'}:${save.profileId}'),
    )
    .toString();

String? historyPersistKey(Object? document) {
  if (SavedGameSession.fromPersist(document) == null || document is! Map) {
    return null;
  }
  final certification = document['_certification'] as Map;
  return sha256
      .convert(utf8.encode(certification['_playerId'] as String))
      .toString();
}

class StoredHistory {
  const StoredHistory({
    required this.key,
    required this.snapshot,
    this.saveKey,
  });
  final String key;
  final String? saveKey;
  final HistorySnapshot snapshot;
}

class HistoryRepository extends ChangeNotifier {
  HistoryRepository._();
  static final instance = HistoryRepository._();
  final _client = GameHistoryClient();
  final _records = <String, StoredHistory>{};
  final _pending = <String, Future<StoredHistory>>{};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool _loaded = false;
  List<StoredHistory> get records => List.unmodifiable(_records.values);
  bool isReading(String key) => _pending.containsKey(key);
  static String accountKey(GameSave save, GameHistoryRegion region) =>
      '${historySaveKey(save)}-${region.id}';
  static String? persistAccountKey(Object? document, GameHistoryRegion region) {
    final key = historyPersistKey(document);
    return key == null ? null : '$key-${region.id}';
  }

  Future<Directory> _folder() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'accounts', 'gacha-history'))
        .create(recursive: true);
  }

  Future<void> load() async {
    if (_loaded) return;
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    final folder = await _folder();
    await for (final entry in folder.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        if (await entry.length() > historyResponseLimit * 4) continue;
        final value = jsonDecode(await entry.readAsString());
        if (value is! Map || value['key'] is! String) continue;
        final key = value['key'] as String;
        if (!RegExp(
          r'^[a-f0-9]{64}(?:-(?:jp|global-hmt|global-en|global-kr))?$',
        ).hasMatch(key)) {
          continue;
        }
        _records[key] = StoredHistory(
          key: key,
          snapshot: HistorySnapshot.fromJson(value['snapshot']),
          saveKey: value['saveKey'] as String?,
        );
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<StoredHistory> import(HistorySnapshot snapshot) async {
    await load();
    final key = sha256
        .convert(utf8.encode(jsonEncode(snapshot.toJson())))
        .toString();
    final record = StoredHistory(key: key, snapshot: snapshot);
    await _put(record);
    return record;
  }

  Future<StoredHistory> refresh(GameSave save, GameHistoryRegion region) async {
    final session = historySessionFromSave(save);
    if (session == null) {
      throw const GameHistoryException('history_missing_session');
    }
    if (save.release?.server != region.catalogServer) {
      throw const GameHistoryException('history_server_mismatch');
    }
    return _refresh(
      historySaveKey(save),
      region,
      session,
      mergeKey: persistAccountKey(
        save.documents[SaveDocumentKind.persist]?.data,
        region,
      ),
    );
  }

  Future<StoredHistory> refreshPersist(
    Object? document,
    GameHistoryRegion region, {
    GameSave? account,
  }) async {
    final session = SavedGameSession.fromPersist(document);
    final key = historyPersistKey(document);
    if (session == null || key == null) {
      throw const GameHistoryException('history_missing_session');
    }
    if (account != null &&
        (account.release?.server != region.catalogServer ||
            historyPersistKey(
                  account.documents[SaveDocumentKind.persist]?.data,
                ) !=
                key)) {
      throw const GameHistoryException('history_import_invalid');
    }
    return _refresh(
      account == null ? key : historySaveKey(account),
      region,
      session,
      mergeKey: '$key-${region.id}',
    );
  }

  Future<StoredHistory> _refresh(
    String saveKey,
    GameHistoryRegion region,
    SavedGameSession session, {
    String? mergeKey,
  }) async {
    await load();
    final key = '$saveKey-${region.id}';
    if (_pending[key] case final current?) return current;
    final pending = _read(saveKey, region, session, mergeKey: mergeKey);
    _pending[key] = pending;
    notifyListeners();
    try {
      return await pending;
    } finally {
      _pending.remove(key);
      notifyListeners();
    }
  }

  Future<StoredHistory> _read(
    String saveKey,
    GameHistoryRegion region,
    SavedGameSession session, {
    String? mergeKey,
  }) async {
    final snapshot = await _client.read(session, region);
    final record = StoredHistory(
      key: '$saveKey-${region.id}',
      saveKey: saveKey,
      snapshot: snapshot,
    );
    await _put(record, mergeKey: mergeKey);
    return _records[record.key] ?? record;
  }

  Future<void> _put(StoredHistory record, {String? mergeKey}) async {
    final write = _writes.then((_) async {
      final folder = await _folder();
      final rawSnapshot = jsonEncode(record.snapshot.toJson());
      final digest = sha256.convert(utf8.encode(rawSnapshot)).toString();
      final archives = await Directory(p.join(folder.path, 'snapshots'))
          .create(recursive: true);
      final archive = File(p.join(archives.path, '$digest.json'));
      if (!await archive.exists()) {
        await archive.writeAsString(rawSnapshot, flush: true);
      }
      final previous = _records[record.key];
      if (record.saveKey != null && previous?.saveKey == record.saveKey) {
        record = StoredHistory(
          key: record.key,
          saveKey: record.saveKey,
          snapshot: record.snapshot.withOlder(previous!.snapshot),
        );
      }
      final candidate = mergeKey == record.key ? null : _records[mergeKey];
      final collected =
          candidate != null &&
              candidate.saveKey != null &&
              mergeKey == '${candidate.saveKey}-${record.snapshot.server}' &&
              candidate.snapshot.server == record.snapshot.server
          ? candidate
          : null;
      if (collected != null) {
        record = StoredHistory(
          key: record.key,
          saveKey: record.saveKey,
          snapshot: record.snapshot.withOlder(collected.snapshot),
        );
      }
      final target = File(p.join(folder.path, '${record.key}.json'));
      final temporary = File('${target.path}.tmp');
      final bytes = utf8.encode(
        jsonEncode({
          'key': record.key,
          'saveKey': record.saveKey,
          'snapshot': record.snapshot.toJson(),
        }),
      );
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(target.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      _records[record.key] = record;
      notifyListeners();
      try {
        await writeHistoryHandoff(
          record.key,
          record.snapshot,
          replaces: collected?.key,
        );
        if (collected != null) {
          _records.remove(collected.key);
          try {
            final oldFile = File(p.join(folder.path, '${collected.key}.json'));
            if (await oldFile.exists()) await oldFile.delete();
          } on FileSystemException {
            // The merged history has already been stored under the account key.
          }
        }
      } on FileSystemException {
        // The private history remains committed; refresh retries USB sharing.
      }
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await write;
  }
}
