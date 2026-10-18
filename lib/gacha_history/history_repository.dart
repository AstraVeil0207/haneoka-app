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
    await load();
    final key = accountKey(save, region);
    if (_pending[key] case final current?) return current;
    final session = SavedGameSession.fromSave(save);
    if (session == null) {
      throw const GameHistoryException('history_missing_session');
    }
    if (save.release?.server != region.catalogServer) {
      throw const GameHistoryException('history_server_mismatch');
    }
    final pending = _read(save, region, session);
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
    GameSave save,
    GameHistoryRegion region,
    SavedGameSession session,
  ) async {
    final snapshot = await _client.read(session, region);
    final record = StoredHistory(
      key: accountKey(save, region),
      saveKey: historySaveKey(save),
      snapshot: snapshot,
    );
    await _put(record);
    return record;
  }

  Future<void> _put(StoredHistory record) async {
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
        await writeHistoryHandoff(record.key, record.snapshot);
      } on FileSystemException {
        // The private history remains committed; refresh retries USB sharing.
      }
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await write;
  }
}
