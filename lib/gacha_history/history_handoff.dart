import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'history_snapshot.dart';

/// USB import reads this explicit, credential-free companion export.
Future<void> writeHistoryHandoff(
  String key,
  HistorySnapshot snapshot, {
  String? replaces,
}) async {
  if (!Platform.isAndroid) return;
  final external = await getExternalStorageDirectory();
  if (external == null) return;
  final folder = await Directory(p.join(external.path, 'HaneokaGachaHistory'))
      .create(recursive: true);
  final target = File(p.join(folder.path, '$key.json'));
  final temporary = File('${target.path}.tmp');
  try {
    await temporary.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    await temporary.rename(target.path);
    if (replaces != null && replaces != key) {
      final previous = File(p.join(folder.path, '$replaces.json'));
      if (await previous.exists()) await previous.delete();
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
