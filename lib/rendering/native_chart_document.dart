import 'package:cassiopeia_plugin_our_notes/render_profile.dart';

import '../core/api.dart';
import '../core/audio.dart';
import '../chart/runtime_chart.dart';
import 'visual_profiles.dart';

/// An actual selected catalogue variant, pinned before any media/resource load.
final class NativeChartDocument {
  NativeChartDocument({
    required this.source,
    required this.sourceId,
    required this.scoreUri,
    required this.musicUri,
    required this.bandId,
    required this.title,
    required this.difficulty,
    required Map<String, Object?> canonicalSong,
    this.noteSkin = 'skin001',
    this.jacketUri,
    this.masterNoteCount,
    List<int>? scoreRankScores,
    List<int> gekisouMissionTypes = const [],
    this.resourceBase,
    this.audioOffsetMs = 0,
    this.timeScaleChanges = const [],
    this.chart,
    this.visualProfiles,
  }) : canonicalSong = Map.unmodifiable(canonicalSong),
       gekisouMissionTypes = List.unmodifiable(gekisouMissionTypes),
       scoreRankScores = scoreRankScores == null
           ? null
           : List.unmodifiable(scoreRankScores);
  final RenderSource source;
  final String? sourceId;
  final Uri scoreUri, musicUri;
  final Uri? resourceBase;
  final double audioOffsetMs;
  final List<({double timeMs, double scale})> timeScaleChanges;
  final RuntimeChart? chart;
  final NativeChartVisualProfiles? visualProfiles;
  final Uri? jacketUri;
  final int bandId;
  final int difficulty;
  final Map<String, Object?> canonicalSong;
  final String title, noteSkin;
  final int? masterNoteCount;
  final List<int>? scoreRankScores;
  final List<int> gekisouMissionTypes;
  NativeChartDocument withNoteSkin(String skin) => NativeChartDocument(
    source: source,
    sourceId: sourceId,
    scoreUri: scoreUri,
    musicUri: musicUri,
    bandId: bandId,
    title: title,
    difficulty: difficulty,
    canonicalSong: canonicalSong,
    noteSkin: skin,
    jacketUri: jacketUri,
    masterNoteCount: masterNoteCount,
    scoreRankScores: scoreRankScores,
    gekisouMissionTypes: gekisouMissionTypes,
    resourceBase: resourceBase,
    audioOffsetMs: audioOffsetMs,
    timeScaleChanges: timeScaleChanges,
    chart: chart,
    visualProfiles: visualProfiles,
  );
  String get key => '${source.server}:${source.release}:${source.document}';
  Track get track => Track(
    id: '${source.server}:${source.release}:${source.document.split(':').first}',
    url: musicUri.toString(),
    title: title,
  );

  static Future<NativeChartDocument> fromSong(
    Map song,
    int difficulty,
    HaneokaApi api,
    String title,
  ) async {
    final id = song['musicId'];
    final rows = song['difficulty'];
    final music = song['musicUrl'];
    final band = song['bandId'];
    if (id is! num || rows is! List || music is! String || band is! num) {
      throw UnsupportedError('native_chart_document_missing_actual_fields');
    }
    final row = rows
        .whereType<Map>()
        .where((r) => r['difficulty'] == difficulty)
        .firstOrNull;
    final score = row?['file'];
    if (score is! String || score.isEmpty || music.isEmpty) {
      throw UnsupportedError('native_chart_source_unavailable');
    }
    final masterCount = row?['noteCount'];
    if (masterCount != null && (masterCount is! int || masterCount < 0)) {
      throw const FormatException('native_chart_master_note_count');
    }
    final rankScores = song['scoreRankScores'];
    if (rankScores != null &&
        (rankScores is! List || !rankScores.every((value) => value is int))) {
      throw const FormatException('native_chart_score_rank_scores');
    }
    final missionSource = song['gekisou'];
    final rawMissions = missionSource is Map
        ? missionSource['missionPattern'] ?? missionSource['missionTypes']
        : null;
    final missions =
        rawMissions is List &&
            rawMissions.every(
              (value) => value is int && value >= 0 && value <= 3,
            )
        ? rawMissions.cast<int>()
        : const <int>[];
    final release = await api.release();
    if (release == 'offline') {
      throw UnsupportedError('native_chart_release_unavailable');
    }
    final sourceId = api.sourceId;
    Uri pin(String path) {
      final uri = api.asset(path);
      return uri.replace(
        queryParameters: {...uri.queryParameters, 'release': release},
      );
    }

    return NativeChartDocument(
      sourceId: sourceId,
      source: RenderSource(
        server: api.server,
        release: release,
        document: '${id.toInt()}:$difficulty',
      ),
      scoreUri: pin(score),
      musicUri: pin(music),
      jacketUri: song['jacketUrl'] is String
          ? pin(song['jacketUrl'] as String)
          : null,
      bandId: band.toInt(),
      title: title,
      difficulty: difficulty,
      canonicalSong: song.cast<String, Object?>(),
      masterNoteCount: masterCount as int?,
      scoreRankScores: (rankScores as List?)?.cast<int>(),
      gekisouMissionTypes: missions,
    );
  }
}
