import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:vega_plugin_haneoka/vega_plugin_haneoka.dart';

import '../core/api.dart';
import '../core/net.dart';

/// A normal selected episode, pinned before any command or media dispatch.
final class NativeStoryDocument {
  NativeStoryDocument._(
    this.chapter,
    this.assets,
    this.runtime,
    this.runtimeHash,
  );
  final StoryChapterDocument chapter;
  final NativeStoryAssets assets;
  final Map<String, Object?> runtime;
  final String runtimeHash;

  static Future<NativeStoryDocument> load(HaneokaApi api, String id) async {
    final release = await api.release();
    final sourceId = api.sourceId;
    if (release == 'offline' || sourceId == null || sourceId.isEmpty) {
      throw StateError('story_source_identity_unavailable');
    }
    final uri = api
        .asset(
          '/api/v1/servers/${api.server}/stories/'
          '${Uri.encodeComponent(id)}',
        )
        .replace(queryParameters: {'release': release});
    final response = await netClient.get(uri);
    if (response.statusCode != 200) {
      throw StateError('story_selected_entity_http:${response.statusCode}');
    }
    final bytes = response.bodyBytes;
    final entity = Map<String, Object?>.from(
      jsonDecode(utf8.decode(bytes)) as Map,
    );
    final source = StorySourceIdentity(
      namespace: api.server,
      revision: release,
      resourceScope: sourceId,
      document: id,
      contentIdentity: sha256.convert(bytes).toString(),
    );
    final chapter = HaneokaStoryCatalogDecoder.decode(entity, source);
    final runtimeUri = api
        .asset('/api/v1/servers/${api.server}/story-runtime')
        .replace(queryParameters: {'release': release});
    final runtimeResponse = await netClient.get(runtimeUri);
    if (runtimeResponse.statusCode != 200) {
      throw StateError(
        'story_actual_runtime_http:${runtimeResponse.statusCode}',
      );
    }
    final runtime = Map<String, Object?>.unmodifiable(
      jsonDecode(utf8.decode(runtimeResponse.bodyBytes)) as Map,
    );
    return NativeStoryDocument._(
      chapter,
      NativeStoryAssets(
        chapter.assets,
        api.asset,
        release,
        commands: chapter.commands,
      ),
      runtime,
      sha256.convert(runtimeResponse.bodyBytes).toString(),
    );
  }
}

/// Resolves exact native cue references through actual catalog rows.
/// Missing resources stay explicit; cue identities never become guessed URLs.
final class NativeStoryAssets {
  NativeStoryAssets(
    Map<String, Object?> assets,
    this.assetUri,
    this.release, {
    required Iterable<StoryDecodedCommand> commands,
  }) {
    final voiceReferences = {
      for (final command in commands) ...command.voiceRefs,
    };
    for (final record in (assets['sounds'] as List? ?? const []).cast<Map>()) {
      final kind = switch (record['categoryName']) {
        'Bgm' => StoryMediaKind.bgm,
        'Voice' => StoryMediaKind.voice,
        'Se' => StoryMediaKind.sfx,
        _ => null,
      };
      if (kind != null) _insert(kind, record, 'soundId');
      if (kind != StoryMediaKind.voice &&
          voiceReferences.contains(record['resourceRef'])) {
        _insert(StoryMediaKind.voice, record, 'soundId');
      }
    }
    for (final record in (assets['videos'] as List? ?? const []).cast<Map>()) {
      _insert(StoryMediaKind.movie, record, 'videoId');
    }
    for (final record in (assets['stills'] as List? ?? const []).cast<Map>()) {
      final reference = record['assetName'];
      final presentation = record['presentation'];
      if (reference is String && presentation is Map) {
        stills[reference] = Map<String, Object?>.from(presentation);
      }
    }
    for (final record
        in (assets['backgrounds'] as List? ?? const []).cast<Map>()) {
      if (record['stageRef'] is String) {
        backgrounds[record['stageRef'] as String] = Map<String, Object?>.from(
          record,
        );
      }
    }
    for (final record in (assets['frames'] as List? ?? const []).cast<Map>()) {
      if (record['assetName'] is String) {
        frames[record['assetName'] as String] = Map<String, Object?>.from(
          record,
        );
      }
    }
  }
  final Uri Function(String) assetUri;
  final String release;
  final _media = <String, Map>{};
  final _ids = <String, String>{};
  final stills = <String, Map<String, Object?>>{};
  final backgrounds = <String, Map<String, Object?>>{};
  final frames = <String, Map<String, Object?>>{};

  void _insert(StoryMediaKind kind, Map record, String idField) {
    final reference = record['resourceRef'];
    if (reference is! String || reference.isEmpty) {
      throw FormatException('story_media_catalog_ref:${record[idField]}');
    }
    final key = '${kind.name}:$reference';
    final idKey = '${kind.name}:${record[idField]}';
    if (_ids[idKey] case final String oldReference
        when oldReference != reference) {
      throw FormatException('story_conflicting_cue_id:$idKey');
    }
    final previous = _media[key];
    if (previous != null &&
        !haneokaStoryMediaBindingsEqual(previous, record, idField)) {
      throw FormatException('story_duplicate_cue:$key');
    }
    _media.putIfAbsent(key, () => record);
    _ids[idKey] = reference;
  }

  String referenceFor(StoryMediaKind kind, String actualCueId) {
    final reference = _ids['${kind.name}:$actualCueId'];
    if (reference == null) {
      throw StateError('story_cue_catalog_missing:$actualCueId');
    }
    return reference;
  }

  Map mediaRecord(String reference, StoryMediaKind kind) {
    final record = _media['${kind.name}:$reference'];
    if (record == null || record['missing'] == true) {
      throw StateError('story_actual_cue_missing:${kind.name}:$reference');
    }
    return record;
  }

  Uri resolve(String reference, StoryMediaKind kind) {
    final record = mediaRecord(reference, kind);
    final url = record['playableUrl'];
    if (url is! String || url.isEmpty) {
      throw StateError('story_cue_playable_url_missing:$reference');
    }
    return pinned(url);
  }

  Uri pinned(String sourcePath) {
    final uri = assetUri(sourcePath);
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'release': release},
    );
  }
}
