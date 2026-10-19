import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

import 'history_snapshot.dart';

/// USB import reads this explicit, credential-free companion export.
Future<void> writeHistoryHandoff(
  String key,
  HistorySnapshot snapshot, {
  Iterable<HistorySnapshot> histories = const [],
  Iterable<String> replaces = const [],
}) async {
  if (!Platform.isAndroid) return;
  final external = await getExternalStorageDirectory();
  if (external == null) return;
  final folder = await Directory(p.join(external.path, 'HaneokaGachaHistory'))
      .create(recursive: true);
  Future<void> write(String filename, HistorySnapshot value) async {
    final target = File(p.join(folder.path, filename));
    final temporary = File('${target.path}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  await write('$key.json', snapshot);
  for (final history in histories.where(
    (value) => value.historyKind != snapshot.historyKind,
  )) {
    final suffix = sha256
        .convert(utf8.encode(history.historyKind))
        .toString()
        .substring(0, 16);
    await write('$key-kind-$suffix.json', history);
  }
  final previousKeys = replaces.where((value) => value != key).toSet();
  await for (final entry in folder.list()) {
    if (entry is! File) continue;
    final name = p.basename(entry.path);
    if (previousKeys.any(
      (oldKey) =>
          name == '$oldKey.json' ||
          RegExp('^$oldKey-kind-[a-f0-9]{16}\\.json\$').hasMatch(name),
    )) {
      await entry.delete();
    }
  }
}
