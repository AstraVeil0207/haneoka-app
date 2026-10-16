import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vega_protocol/save.dart';
import 'package:vega_plugin_haneoka/render_profile.dart'
    show StorySourceIdentity;

/// The application owns durable files; the engine owns the portable envelope.
final class StorySaveStore {
  StorySaveStore(
    this.source, {
    required this.runtimeHash,
    required this.hostCodec,
  });
  final StorySourceIdentity source;
  final String runtimeHash, hostCodec;
  Object? lastReadError;

  Future<File> _quickFile() async {
    final directory = await getApplicationSupportDirectory();
    final key = sha256
        .convert(utf8.encode(jsonEncode([source.namespace, source.document])))
        .toString();
    return File(p.join(directory.path, 'vega-saves', key, 'quick.json'));
  }

  Future<VegaSaveEnvelope?> readQuick() async {
    lastReadError = null;
    try {
      final file = await _quickFile();
      if (!await file.exists()) return null;
      final envelope = VegaSaveEnvelope.decode(await file.readAsString());
      _validate(envelope);
      return envelope;
    } catch (error) {
      lastReadError = error;
      return null;
    }
  }

  void _validate(VegaSaveEnvelope envelope) {
    if (envelope.sourceIdentity != source ||
        envelope.hostCodec != hostCodec ||
        envelope.hostData['runtimeHash'] != runtimeHash) {
      throw const FormatException('story_save_store_incompatible_source');
    }
    for (final key in ['world', 'playback', 'ui', 'decisions']) {
      if (envelope.hostData[key] is! Map) {
        throw const FormatException('story_save_store_format');
      }
    }
    final ui = envelope.hostData['ui'] as Map;
    if (ui['version'] != 2 ||
        ui['source'] is! Map ||
        StorySourceIdentity.fromJson(ui['source'] as Map) != source ||
        ui['runtimeHash'] != runtimeHash) {
      throw const FormatException('story_save_store_incompatible_ui');
    }
  }

  Future<void> writeQuick(VegaSaveEnvelope envelope) async {
    _validate(envelope);
    final file = await _quickFile();
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(envelope.encode(), flush: true);
    await pending.rename(file.path);
  }
}
