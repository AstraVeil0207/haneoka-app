// Decodes every save document in a folder and summarises it.
// Usage: dart run tool/inspect_save.dart <folder> [<json-out-dir>]
import 'dart:convert';
import 'dart:io';

import 'package:haneoka/save/codec.dart';
import 'package:haneoka/save/game_save.dart';
import 'package:haneoka/save/save_view.dart';

void main(List<String> args) {
  final root = Directory(args.first);
  final out = args.length > 1 ? Directory(args[1]) : null;
  final collector = SaveCollector();
  for (final file in root.listSync(recursive: true).whereType<File>()) {
    final bytes = file.readAsBytesSync();
    if (!SaveCodec.looksLikeSave(bytes)) continue;
    final data = SaveCodec.decode(bytes);
    stdout.writeln('${file.path.split('/').last.substring(0, 12)}… '
        '${bytes.length} B → ${data == null ? 'undecodable' : '${data.length} keys: ${data.keys.take(12).join(', ')}'}');
    if (data != null && out != null) {
      out.createSync(recursive: true);
      File('${out.path}/${file.path.split('/').last.substring(0, 12)}.json')
          .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(data));
    }
    collector.offer(SaveCandidate(
      bytes: bytes,
      source: file.path,
      group: file.parent.path,
      modifiedAt: file.lastModifiedSync(),
    ));
  }
  stdout.writeln('unreadable: ${collector.unreadable}');
  for (final save in collector.saves) {
    final view = SaveView(save);
    stdout.writeln('profile ${save.profileId} documents ${save.documents.keys.map((k) => k.name).join(',')}');
    stdout.writeln('player fields ${view.player.length}; exp ${view.exp}; vip ${view.vipRank}; rating ${view.highScoreRating}; clears ${view.clearsByDifficulty}');
    for (final MapEntry(:key, :value) in view.present.entries) {
      stdout.writeln('  ${key.name} ${key.field} $value');
    }
    final known = SaveSection.values.map((s) => s.field).toSet();
    final unknown = view.player.keys.where((k) => !known.contains(k)).toList();
    stdout.writeln('fields not mapped to a section (${unknown.length}): ${unknown.join(' ')}');
  }
}
