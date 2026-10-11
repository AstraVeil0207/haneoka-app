import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'game_save.dart';

/// The accounts imported on this device, kept in the app's private storage
/// so they are still there next time. Nothing leaves the device.
class AccountStore extends ChangeNotifier {
  AccountStore._();
  static final AccountStore instance = AccountStore._();

  final List<GameSave> _saves = [];
  bool _loaded = false;
  List<GameSave> get saves => List.unmodifiable(_saves);

  static String _key(GameSave save) =>
      '${save.release?.server ?? 'save'}-${save.profileId}';

  Future<Directory> _folder() async {
    final root = await getApplicationSupportDirectory();
    final folder = Directory(p.join(root.path, 'accounts'));
    await folder.create(recursive: true);
    return folder;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final folder = await _folder();
    final files = await folder
        .list()
        .where((f) => f is File && f.path.endsWith('.json'))
        .cast<File>()
        .toList();
    for (final file in files) {
      try {
        final text = await file.readAsString();
        final json = await Isolate.run(() => jsonDecode(text));
        if (decode(json) case final save?) _saves.add(save);
      } catch (_) {
        // A damaged file is skipped; importing again replaces it.
      }
    }
    _sort();
    notifyListeners();
  }

  Future<void> put(GameSave save) async {
    _saves.removeWhere((s) => _key(s) == _key(save));
    _saves.add(save);
    _sort();
    notifyListeners();
    final folder = await _folder();
    final json = encode(save);
    final text = await Isolate.run(() => jsonEncode(json));
    await File(p.join(folder.path, '${_key(save)}.json')).writeAsString(text);
  }

  Future<void> remove(GameSave save) async {
    _saves.removeWhere((s) => _key(s) == _key(save));
    notifyListeners();
    final file = File(p.join((await _folder()).path, '${_key(save)}.json'));
    if (await file.exists()) await file.delete();
  }

  void _sort() => _saves.sort(
    (a, b) =>
        (b.modifiedAt ?? DateTime(0)).compareTo(a.modifiedAt ?? DateTime(0)),
  );

  /// One account as stored (`haneoka-account-v1`).
  static Map<String, Object?> encode(GameSave save) => {
    'schema': 'haneoka-account-v1',
    'profileId': save.profileId,
    'name': save.name,
    'release': save.release?.name,
    'source': save.source,
    'documents': {
      for (final MapEntry(:key, :value) in save.documents.entries)
        key.name: {
          'modifiedAt': value.modifiedAt?.toUtc().toIso8601String(),
          'data': value.data,
        },
    },
  };

  /// An account read back from [encode]; null for anything else.
  static GameSave? decode(Object? json) {
    if (json is! Map || json['schema'] != 'haneoka-account-v1') return null;
    final save = GameSave(
      profileId: '${json['profileId']}',
      name: json['name'] as String?,
      release: GameRelease.values
          .where((r) => r.name == json['release'])
          .firstOrNull,
      source: '${json['source'] ?? ''}',
    );
    for (final MapEntry(:key, :value)
        in ((json['documents'] as Map?) ?? const {}).entries) {
      final kind = SaveDocumentKind.values
          .where((k) => k.name == key)
          .firstOrNull;
      if (kind == null || value is! Map) continue;
      save.documents[kind] = SaveDocument(
        kind,
        ((value['data'] as Map?) ?? const {}).cast<String, Object?>(),
        DateTime.tryParse('${value['modifiedAt'] ?? ''}')?.toLocal(),
      );
    }
    return save;
  }
}
