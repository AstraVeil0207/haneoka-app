import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/audio.dart';
import '../core/i18n.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/tile.dart';
import 'browse.dart';
import 'cross_server.dart';
import 'visuals.dart';

const _categories = ['', 'original', 'virtual', 'jpop', 'anime', 'game'];
const _attributes = ['', 'red', 'blue', 'green', 'yellow', 'purple'];

/// The song catalogue (`catalog-screen` with the song presentation): jacket
/// tiles with the live attribute and genre on the artwork, band emblems
/// before the artist, a play button, and Play all in the bar.
class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key, this.onOpen});

  /// Opens a song's page.
  final void Function(BuildContext context, Entry song)? onOpen;

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  Future<(List<Entry>, CatalogVisuals)>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<Entry>, CatalogVisuals)> _load() async {
    final state = AppScope.of(context);
    final (songs, visuals) = await (
      crossServerCollection(
        resource: 'songs',
        selected: state.server,
        apis: state.catalogApis,
        rowsPath: null,
      ),
      CatalogVisuals.of(state.api),
    ).wait;
    return (songs, visuals);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    return FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final songs = data?.$1;
        final visuals = data?.$2;
        final song = _SongText(t, visuals, state.api, state.songTitle);
        return BrowseScreen(
          title: t('navigation.songs', 'Songs'),
          items: songs,
          error: snapshot.error,
          onRetry: () => setState(() => _data = _load()),
          searchText: (item) => [
            ...?(item['musicTitle'] as List?)?.whereType<String>(),
            song.artist(item),
            '${item['musicId']}',
          ].join(' '),
          grid: const GridSpec(minWidth: 160),
          tile: (context, item) => _SongTile(
            song: item,
            text: song,
            onOpen: () => widget.onOpen?.call(context, item),
          ),
          listRow: (context, item) => _SongRow(
            song: item,
            text: song,
            onOpen: () => widget.onOpen?.call(context, item),
          ),
          columns: [
            TableColumn(
              t.label('title'),
              (item) => state.songTitle(item['musicTitle']),
            ),
            TableColumn(t.label('band'), song.artist),
            TableColumn(t.label('musicType'), song.attribute),
            TableColumn(t.label('category'), song.category),
            TableColumn(
              'EXPERT',
              (item) => '${song.level(item, 3) ?? '—'}',
              numeric: true,
            ),
            TableColumn(t.label('release'), song.release),
          ],
          facets: visuals == null
              ? const []
              : [
                  FacetSpec(
                    key: 'band',
                    label: t.label('band'),
                    values: (item) => [
                      for (final id in (item['bandIds'] as List? ?? const []))
                        '$id',
                    ],
                    option: (value) => FacetOption(
                      t.text(visuals.bands[int.parse(value)]?['bandName']),
                      image: visuals.bandIcon(int.parse(value)),
                    ),
                  ),
                  FacetSpec(
                    key: 'character',
                    label: t.label('character'),
                    values: (item) => [
                      for (final id
                          in (item['vocalCharacterIds'] as List? ?? const []))
                        '$id',
                    ],
                    option: (value) {
                      final character = visuals.characters[int.parse(value)];
                      final face = character?['faceImage'];
                      return FacetOption(
                        t.text(character?['characterName']),
                        image: face is String
                            ? state.api.asset(face).toString()
                            : null,
                      );
                    },
                  ),
                  FacetSpec(
                    key: 'type',
                    label: t.label('attribute'),
                    values: (item) => [
                      if (item['musicType'] != null) '${item['musicType']}',
                    ],
                    option: (value) => FacetOption(
                      song.attribute({'musicType': int.parse(value)}),
                      image: visuals.musicTypeMark(int.parse(value)),
                    ),
                  ),
                  FacetSpec(
                    key: 'category',
                    label: t.label('category'),
                    values: (item) => [
                      for (final id
                          in (item['musicCategories'] as List? ?? const []))
                        '$id',
                    ],
                    option: (value) => FacetOption(
                      song.category({
                        'musicCategories': [int.parse(value)],
                      }),
                    ),
                  ),
                ],
          sorts: [
            SortSpec(
              'order',
              t.label('order'),
              (item) => item['sortOrder'] as num?,
            ),
            SortSpec('id', t.label('id'), (item) => item['musicId'] as num?),
            SortSpec(
              'title',
              t.label('title'),
              (item) => state.songTitle(item['musicTitle']),
            ),
            SortSpec(
              'musicType',
              t.label('musicType'),
              (item) => item['musicType'] as num?,
            ),
            SortSpec('band', t.label('band'), song.artist),
            SortSpec('level', t.label('level'), (item) => song.level(item, 3)),
            SortSpec('release', t.label('release'), song.releasedAt),
          ],
          defaultSort: 'release',
          actions: (visible) => [
            BarAction(
              icon: Symbols.playlist_play_rounded,
              label: t.label('playAll'),
              onPressed: visible.any((s) => s['musicUrl'] is String)
                  ? () => state.audio.playQueue([
                      for (final s in visible) ?song.track(s),
                    ])
                  : null,
            ),
          ],
        );
      },
    );
  }
}

/// How a song reads: title, artist line, attribute, genre, level, release.
class _SongText {
  _SongText(this.t, this.visuals, this.api, this.title);
  final SiteText t;
  final CatalogVisuals? visuals;
  final HaneokaApi api;

  /// The reader's song-title choice.
  final String Function(Object?) title;

  List<int> bandIds(Entry song) => [
    for (final id in (song['bandIds'] as List? ?? [song['bandId']]))
      if (id is num && id > 0) id.toInt(),
  ];

  String artist(Entry song) {
    final names = [
      for (final id in bandIds(song))
        if (t.text(visuals?.bands[id]?['bandName']) case final name
            when name.isNotEmpty)
          name,
    ];
    return names.isNotEmpty ? names.join(', ') : t.text(song['bandName']);
  }

  /// The performing bands' logos (`songPerformerAdornment`).
  List<String> emblems(Entry song) =>
      {for (final id in bandIds(song)) ?visuals?.bandLogo(id)}.toList();

  String attribute(Entry song) {
    final id = (song['musicType'] as num?)?.toInt() ?? 0;
    return id > 0 && id < _attributes.length ? t.label(_attributes[id]) : '';
  }

  String category(Entry song) => [
    for (final id in (song['musicCategories'] as List? ?? const []))
      if (id is num && id > 0 && id < _categories.length)
        t.label(_categories[id.toInt()]),
  ].join(', ');

  num? level(Entry song, int difficulty) {
    for (final row in (song['difficulty'] as List? ?? const [])) {
      if (row is Entry && row['difficulty'] == difficulty) {
        return (row['displayLevel'] ?? row['playLevel']) as num?;
      }
    }
    return null;
  }

  num? releasedAt(Entry song) {
    final value = song['publishedAt'];
    if (value is num) return value;
    if (value is List) return value.whereType<num>().firstOrNull;
    return null;
  }

  String release(Entry song) {
    final ms = releasedAt(song);
    return ms == null
        ? '—'
        : DateFormat.yMMMd(t.locale)
              .format(DateTime.fromMillisecondsSinceEpoch(ms.toInt()));
  }

  List<String> jackets(Entry song) => [
    for (final key in ['jacketThumbUrl', 'jacketUrl'])
      if (song[key] case final String path when path.isNotEmpty)
        api.asset(path).toString(),
  ];

  Track? track(Entry song) {
    final url = song['musicUrl'];
    if (url is! String) return null;
    return Track(
      id: '${song['musicId']}',
      url: api.asset(url).toString(),
      title: title(song['musicTitle']),
      subtitle: artist(song),
      artwork: jackets(song).lastOrNull,
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({required this.song, required this.text, this.onOpen});
  final Entry song;
  final _SongText text;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final audio = AppScope.of(context).audio;
    final attribute = text.visuals?.musicTypeMark(song['musicType']);
    final category = text.category(song);
    final track = text.track(song);
    return Tile(
      title: AppScope.of(context).songTitle(song['musicTitle']),
      subtitle: text.artist(song),
      adornments: text.emblems(song),
      images: text.jackets(song),
      placeholder: Symbols.album_rounded,
      serverMark: serverMark(song, text.t.call),
      marks: [
        if (attribute != null)
          TileMark.image(MarkAt.start, attribute, label: text.attribute(song)),
        if (category.isNotEmpty) TileMark.text(MarkAt.bottomStart, category),
      ],
      onTap: onOpen,
      action: track == null
          ? null
          : ListenableBuilder(
              listenable: audio,
              builder: (context, _) {
                final playing = audio.isPlaying(track.id);
                return Material(
                  type: MaterialType.transparency,
                  elevation: 1,
                  shape: const CircleBorder(),
                  child: IconButton.filledTonal(
                    tooltip:
                        '${text.t(playing ? 'common.actions.pause' : 'common.actions.play')}: ${track.title}',
                    onPressed: () => audio.toggle(track),
                    icon: Icon(
                      playing
                          ? Symbols.pause_rounded
                          : Symbols.play_arrow_rounded,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.song, required this.text, this.onOpen});
  final Entry song;
  final _SongText text;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onOpen,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 48,
          child: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: AppImage(candidates: text.jackets(song).reversed.toList()),
          ),
        ),
      ),
      title: Text(
        AppScope.of(context).songTitle(song['musicTitle']),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          text.artist(song),
          text.category(song),
        ].where((s) => s.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('${text.level(song, 3) ?? ''}'),
    );
  }
}
