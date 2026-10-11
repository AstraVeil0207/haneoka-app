import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../save/codec.dart';
import '../save/game_save.dart';

/// The game's asset caches sit next to the account directories and hold
/// gigabytes of bundles and no saves; a folder walk never enters them.
const skippedDirectories = {
  'EncryptedBundles',
  'Addressables',
  'Master',
  'RemoteCatalog',
  'il2cpp',
  'Unity',
  'UnityCache',
  'cache',
  'tmp',
  'com.unity3d.player',
};

/// Files, folders and ZIP archives the user picked: a copied account folder,
/// single save files, or an archive such as a desktop tool's account package.
class FileSaveSource {
  FileSaveSource(this.collector, {this.release});
  final SaveCollector collector;

  /// The release the user named; a picked file does not say which it came from.
  final GameRelease? release;
  static const _maxDepth = 6;

  Future<void> addPath(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      await _walk(Directory(path), 0);
    } else if (type == FileSystemEntityType.file) {
      await _file(File(path));
    }
  }

  void addBytes(Uint8List bytes, String name, {DateTime? modifiedAt}) {
    if (_isZip(bytes)) {
      _zip(bytes, name);
    } else {
      collector.offer(
        SaveCandidate(
          bytes: bytes,
          source: name,
          modifiedAt: modifiedAt,
          release: release,
          group: p.dirname(name),
        ),
      );
    }
  }

  Future<void> _walk(Directory directory, int depth) async {
    if (depth > _maxDepth) return;
    await for (final entity in directory.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (!skippedDirectories.contains(name)) await _walk(entity, depth + 1);
      } else if (entity is File) {
        await _file(entity);
      }
    }
  }

  Future<void> _file(File file) async {
    final stat = await file.stat();
    if (stat.size == 0 || stat.size > SaveCodec.maxFileBytes * 2) return;
    final bytes = await file.readAsBytes();
    if (_isZip(bytes)) {
      _zip(bytes, file.path);
    } else {
      collector.offer(
        SaveCandidate(
          bytes: bytes,
          source: file.path,
          modifiedAt: stat.modified,
          release: release,
          group: p.dirname(file.path),
        ),
      );
    }
  }

  void _zip(Uint8List bytes, String name) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive.files) {
      if (!entry.isFile ||
          entry.size == 0 ||
          entry.size > SaveCodec.maxFileBytes) {
        continue;
      }
      if (p.split(entry.name).any(skippedDirectories.contains)) continue;
      final modified = DateTime.fromMillisecondsSinceEpoch(
        entry.lastModTime * 1000,
      );
      collector.offer(
        SaveCandidate(
          bytes: entry.content,
          source: '$name!${entry.name}',
          modifiedAt: modified,
          release: release,
          group: '$name!${p.dirname(entry.name)}',
        ),
      );
    }
  }

  static bool _isZip(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      bytes[2] == 3 &&
      bytes[3] == 4;
}
