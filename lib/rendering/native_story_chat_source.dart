import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_document.dart';

/// Reads verified prefab packets lazily by the master-selected asset. Source
/// selection and local component interpretation live in the game plugin.
final class NativeStoryChatSource {
  NativeStoryChatSource._(this.document, this.index, this.shared)
    : catalog = StoryChatSourceCatalog(
        identity: document.chapter.sourceIdentity,
        runtime: document.runtime,
      );
  final NativeStoryDocument document;
  final Map<String, Object?> index, shared;
  final StoryChatSourceCatalog catalog;
  final _windows = <String, Future<StoryChatWindowSource>>{};
  final _stampImages = <String, StoryChatExternalImage>{};
  Map<String, StoryChatExternalImage> get externalImages => _stampImages;
  static const base =
      '${haneokaProfileAssetRoot}story-ui/source-bindings/chat/';
  static Future<Map<String, Object?>> _read(String path, String hash) async {
    if (path.contains('..')) {
      throw const FormatException('story_chat_packet_path');
    }
    final data = await rootBundle.load('$base$path');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    return Isolate.run(() {
      if (sha256.convert(bytes).toString() != hash) {
        throw FormatException('story_chat_packet_hash:$path');
      }
      return Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
    }, debugName: 'story-chat-source');
  }

  static Future<NativeStoryChatSource> load(
    NativeStoryDocument document,
  ) async {
    final index = await _read(
      'chat-source-index.json',
      'ccfd65c0e1a76db5baebabb1f93acbee0093ec9316b9cd9deb835ec4fdb79b58',
    );
    if (index['sourceId'] != document.chapter.sourceIdentity.sourceId ||
        index['server'] != document.chapter.sourceIdentity.server ||
        index['runtimeSHA256'] != document.runtimeHash) {
      throw const FormatException('story_chat_source_identity');
    }
    final resource = index['sharedResources'] as Map;
    final shared = await _read(
      resource['path'] as String,
      resource['sha256'] as String,
    );
    return NativeStoryChatSource._(document, index, shared);
  }

  Future<StoryChatWindowSource> window(String id) =>
      _windows.putIfAbsent(id, () async {
        final selection = catalog.resolve(id);
        final entry =
            (index['windowPackets'] as Map)[selection.windowAssetName] as Map;
        final domain = await _read(
          entry['path'] as String,
          entry['sha256'] as String,
        );
        return StoryChatWindowSource(
          packet: {
            ...shared,
            'chatAssets': index['chatAssets'],
            'windows': {selection.windowAssetName: domain},
          },
          selection: selection,
        );
      });
  Future<void> prepare(Future<Uint8List> Function(Uri) fetch) async {
    final ids = {
      for (final c in document.chapter.commands)
        if (c.opcode == 36) '${c.payload['targetChatID']}',
    };
    final stamps = <String>{};
    for (final command in document.chapter.commands) {
      final asset = command.payload['targetAssetName'];
      if (command.opcode == 38 && asset is String && asset.isNotEmpty) {
        stamps.add(asset);
      }
    }
    await Future.wait(ids.map(window));
    await Future.wait(
      stamps.map((stamp) async {
        final path = catalog.stampPath(stamp);
        final uri = document.assets.pinned(
          path.startsWith('Assets/')
              ? '/assets/${document.chapter.sourceIdentity.server}/$path'
              : path,
        );
        final buffer = await ui.ImmutableBuffer.fromUint8List(await fetch(uri));
        try {
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          try {
            _stampImages[stamp] = StoryChatExternalImage(
              uri: uri,
              width: descriptor.width.toDouble(),
              height: descriptor.height.toDouble(),
            );
          } finally {
            descriptor.dispose();
          }
        } finally {
          buffer.dispose();
        }
      }),
    );
  }

  Uri resolveOutput(Map output) {
    final path = output['path'] as String;
    if (path.startsWith('generated-assets/')) {
      return Uri.parse('haneoka-asset:${base}assets/${path.split('/').last}');
    }
    final String served;
    if (path.startsWith('assets/')) {
      served =
          '/assets/${document.chapter.sourceIdentity.server}/${path.substring(7)}';
    } else if (path.startsWith('runtime/')) {
      served =
          '/runtime/${document.chapter.sourceIdentity.server}/${path.substring(8)}';
    } else {
      throw FormatException('story_chat_texture_output:$path');
    }
    return document.assets
        .assetUri(served)
        .replace(
          queryParameters: {'release': document.chapter.sourceIdentity.release},
        );
  }
}
