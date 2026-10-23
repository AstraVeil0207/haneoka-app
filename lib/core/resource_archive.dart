import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'background_work.dart';

Future<Uint8List> createResourceArchive(
  Map<String, Uint8List> files, {
  required void Function() checkCurrent,
}) => runBackgroundWork(
  _ResourceArchive(Map.of(files)).encode,
  checkCurrent: checkCurrent,
  debugName: 'model-resource-archive',
);

class _ResourceArchive {
  const _ResourceArchive(this.files);
  final Map<String, Uint8List> files;
  Uint8List encode() {
    final archive = Archive();
    for (final entry in files.entries) {
      final file = ArchiveFile(entry.key, entry.value.length, entry.value);
      if (!entry.key.endsWith('.json') && !entry.key.endsWith('.atlas')) {
        file.compression = CompressionType.none;
      }
      archive.addFile(file);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
