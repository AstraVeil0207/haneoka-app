import 'dart:io';

import 'package:path/path.dart' as p;

import '../save/game_save.dart';
import 'files.dart';
import 'plist.dart';

enum IosDirectAccess { available, restricted }

/// Reads only Our Notes Documents in an already-unsandboxed environment.
/// Ordinary iOS installations keep using Files/shared archives or backups.
class IosDirectSaveSource {
  static const roots = [
    '/var/mobile/Containers/Data/Application',
    '/private/var/mobile/Containers/Data/Application',
  ];

  static Future<IosDirectAccess> access() async {
    if (!Platform.isIOS) return IosDirectAccess.restricted;
    for (final root in roots) {
      try {
        await Directory(root).list(followLinks: false).first;
        return IosDirectAccess.available;
      } on FileSystemException {
        continue;
      } on StateError {
        return IosDirectAccess.available;
      }
    }
    return IosDirectAccess.restricted;
  }

  static Future<void> read(SaveCollector collector) async {
    if (!Platform.isIOS) throw const IosDirectAccessException();
    var readable = false;
    var inspected = false;
    final seen = <String>{};
    for (final root in roots) {
      try {
        await for (final entity in Directory(root).list(followLinks: false)) {
          readable = true;
          if (entity is! Directory ||
              !RegExp(r'^[a-fA-F0-9-]{36}$')
                  .hasMatch(p.basename(entity.path))) {
            continue;
          }
          try {
            final metadata = File(
              p.join(
                entity.path,
                '.com.apple.mobile_container_manager.metadata.plist',
              ),
            );
            if ((await metadata.length()) > 262144) continue;
            final document = parsePlist(await metadata.readAsBytes());
            if (document is Map) inspected = true;
            final identifier = document is Map
                ? document['MCMMetadataIdentifier']
                : null;
            final release = identifier is String
                ? GameRelease.fromPackage(identifier)
                : null;
            if (release == null) continue;
            final canonical = await entity.resolveSymbolicLinks();
            if (!seen.add(canonical)) continue;
            await FileSaveSource(
              collector,
              release: release,
            ).addPath(p.join(entity.path, 'Documents'));
          } on FileSystemException {
            continue;
          } on FormatException {
            continue;
          } on RangeError {
            continue;
          }
        }
        break;
      } on FileSystemException {
        continue;
      }
    }
    if (!readable || !inspected) throw const IosDirectAccessException();
  }
}

class IosDirectAccessException implements Exception {
  const IosDirectAccessException();
}
