import '../core/api.dart';
import '../community/community_time.dart' show formatList;
import '../core/i18n.dart';
import '../core/provider_api.dart';
import '../playlists/song_performer.dart';
import '../ui/tile.dart';
import 'visuals.dart';

const songCategoryKeys = ['', 'original', 'virtual', 'jpop', 'anime', 'game'];
const songAttributeKeys = ['', 'red', 'blue', 'green', 'yellow', 'purple'];

/// One display adapter for catalogue cards, associated songs and choosers.
/// Identity stays in the portable performer resolver; selection and playback
/// actions belong to each host.
class SongPresentation {
  SongPresentation(this.text, this.api, this.visuals, {this.registry});
  final SiteText text;
  final HaneokaApi api;
  final CatalogVisuals? visuals;
  final PerformerRegistry? registry;

  String get game => catalogGame(api);
  SongPerformer? performer(Map<String, Object?> song) {
    final source = registry ?? visuals?.songPerformers;
    return source == null ? null : resolveSongPerformer(song, source);
  }

  List<int> bandIds(Map<String, Object?> song) => [
    for (final value
        in song['bandIds'] is List ? song['bandIds'] as List : [song['bandId']])
      if (value is num && value > 0) value.toInt(),
  ];

  String artist(Map<String, Object?> song) {
    final names = [
      for (final name in performer(song)?.names ?? const []) text.text(name),
    ].where((name) => name.isNotEmpty).toList();
    if (names.isNotEmpty) return formatList(names, text.locale);
    final bands = [
      for (final id in bandIds(song))
        if (text.text(visuals?.bands[id]?['bandName']) case final name
            when name.isNotEmpty)
          name,
    ];
    return bands.isNotEmpty
        ? formatList(bands, text.locale)
        : text.text(song['artistName'] ?? song['bandName']);
  }

  /// Authored round band icons and credited character faces share one row.
  List<String> avatars(Map<String, Object?> song) {
    final value = performer(song);
    if (value == null) {
      return {for (final id in bandIds(song)) ?visuals?.bandIcon(id)}.toList();
    }
    return {
      for (final band in value.logos) api.asset(band.image).toString(),
      for (final portrait in value.portraits)
        if (portrait.image.isNotEmpty) api.asset(portrait.image).toString(),
    }.toList();
  }

  String attribute(Map<String, Object?> song) {
    final id = (song['musicType'] as num?)?.toInt() ?? 0;
    return id > 0 && id < songAttributeKeys.length
        ? text.label(songAttributeKeys[id])
        : '';
  }

  String category(Map<String, Object?> song) => [
    for (final id
        in song['musicCategories'] is List
            ? song['musicCategories'] as List
            : const [])
      if (id is num && id > 0 && id < songCategoryKeys.length)
        text.label(songCategoryKeys[id.toInt()]),
  ].join(', ');

  /// Preserve the attribute and genre; chooser difficulty occupies its own
  /// artwork corner, leaving the performer line available in every grid.
  List<TileMark> marks(
    Map<String, Object?> song, {
    String? difficulty,
    MarkAt? categoryAt,
  }) {
    final categoryLabel = category(song);
    return [
      if (visuals?.musicTypeMark(song['musicType']) case final image?)
        TileMark.image(MarkAt.start, image, label: attribute(song)),
      if (categoryLabel.isNotEmpty)
        TileMark.text(
          categoryAt ?? (difficulty == null ? MarkAt.bottomStart : MarkAt.end),
          categoryLabel,
        ),
      if (difficulty != null && difficulty.isNotEmpty)
        TileMark.text(MarkAt.bottomStart, difficulty),
    ];
  }
}
