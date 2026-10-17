import '../core/api.dart';
import 'song_performer.dart';

/// A port of the website's `lib/playlists/library.ts` and
/// `lib/playlist-tracks.ts`: both games' songs as one library. A song in
/// Our Notes and in GBP (same title, same band) appears once, as the
/// Our Notes entry; songs are ordered by their first release.

class TrackRef {
  const TrackRef(this.provider, this.server, this.musicId);

  /// `our-notes` or `bestdori`.
  final String provider;
  final String server;
  final String musicId;

  String get key => '$provider:$server:$musicId';
  Map<String, String> toJson() => {
    'provider': provider,
    'server': server,
    'musicId': musicId,
  };

  static TrackRef? parse(Object? value) {
    if (value is! Map) return null;
    final provider = value['provider'];
    if (provider != 'our-notes' && provider != 'bestdori') return null;
    final server = '${value['server'] ?? ''}';
    final musicId = '${value['musicId'] ?? ''}';
    return server.isNotEmpty && RegExp(r'^\d+$').hasMatch(musicId)
        ? TrackRef(provider as String, server, musicId)
        : null;
  }
}

class LibrarySong {
  LibrarySong({
    required this.ref,
    required this.row,
    required this.title,
    required this.bandKey,
    required this.bandName,
    required this.jacket,
    required this.thumb,
    required this.audio,
    required this.released,
    this.performer,
    this.bgm,
  });
  final TrackRef ref;
  final Row row;
  final Object? title;
  String bandKey;
  final Object? bandName;
  final String jacket;
  final String thumb;
  final String audio;
  num released;
  final SongPerformer? performer;
  final List<String> aliases = [];

  /// Cue name of a game BGM track; such tracks have no song page.
  final String? bgm;

  String get key => ref.key;
}

class LibraryBand {
  LibraryBand(this.key, this.name);
  final String key;
  final Object? name;
  String logo = '';
  final List<LibrarySong> songs = [];
  final List<String> sources = [];
}

class SongLibrary {
  SongLibrary(this.songs, this.byKey, this.bands, this.partial, this.bgm);
  final List<LibrarySong> songs;
  final Map<String, LibrarySong> byKey;
  final List<LibraryBand> bands;
  final List<String> partial;
  final List<LibrarySong> bgm;
}

const _origin = 'https://haneoka.org';
String _absolute(String path) => path.startsWith('/') ? '$_origin$path' : path;

String _first(Object? value) {
  if (value is List) {
    return '${value.firstWhere((v) => v is String && v.isNotEmpty, orElse: () => '')}';
  }
  return value is String ? value : '';
}

String _normalize(String value) => String.fromCharCodes(
  value.runes.map((r) => r >= 0xFF01 && r <= 0xFF5E ? r - 0xFEE0 : r),
).replaceAll(RegExp(r'\s+'), '').toLowerCase();

num _releasedAt(Row song) {
  final values = [
    ...(song['publishedAt'] is List ? song['publishedAt'] as List : const []),
    song['releaseAt'],
  ].whereType<num>().where((v) => v > 0);
  return values.isEmpty
      ? double.infinity
      : values.reduce((a, b) => a < b ? a : b);
}

class _Source {
  _Source(this.provider, this.server, this.songs, this.registry);
  final String provider;
  final String server;
  final Map<String, Row> songs;
  final PerformerRegistry registry;
}

Map<String, Row> _rows(Object? document) {
  final source = document is Map && document['items'] is Map
      ? document['items'] as Map
      : document;
  return {
    if (source is Map)
      for (final MapEntry(:key, :value) in source.entries)
        if (value is Map) '$key': value.cast<String, Object?>(),
  };
}

Future<_Source> _load(String provider, String server, HaneokaApi api) async {
  Future<Object?> read(String resource) => provider == 'bestdori'
      ? api.json('/api/v1/garupa/bestdori/$server/$resource')
      : api.catalog(resource);
  final [songs, bands, characters] = await Future.wait([
    read('songs'),
    read('bands'),
    read('characters'),
  ]);
  return _Source(
    provider,
    server,
    {
      for (final MapEntry(key: id, value: row) in _rows(songs).entries)
        '${row['musicId'] ?? row['id'] ?? id}': row,
    },
    PerformerRegistry(
      game: provider == 'bestdori' ? 'gbp' : 'our-notes',
      server: server,
      sourceId: provider == 'bestdori' ? null : api.sourceId,
      bands: {
        for (final MapEntry(key: id, value: row) in _rows(bands).entries)
          (row['bandId'] as num?)?.toInt() ?? int.tryParse(id) ?? 0: row,
      },
      characters: {
        for (final MapEntry(key: id, value: row) in _rows(characters).entries)
          (row['characterId'] as num?)?.toInt() ?? int.tryParse(id) ?? 0: row,
      },
    ),
  );
}

/// Display-only same-source portraits for members absent from GBP.
List<PerformerPortrait> _cryChicPortraits(_Source source) =>
    auditedCryChicPortraits(source.registry);

List<LibrarySong> _songsOf(_Source source) {
  final bestdori = source.provider == 'bestdori';
  return [
    for (final MapEntry(key: id, value: row) in source.songs.entries)
      () {
        final performer = resolveSongPerformer(row, source.registry);
        final bandIds = row['bandIds'];
        final bandId =
            performer.bandIds.firstOrNull ??
            (bandIds is List ? (bandIds.firstOrNull as num?)?.toInt() : null) ??
            (row['bandId'] as num?)?.toInt();
        final band = source.registry.bands[bandId];
        final official = band == null
            ? false
            : (bestdori ? band['official'] == true : band['official'] != false);
        final bandName = band?['bandName'] ?? row['bandName'];
        return LibrarySong(
          ref: TrackRef(
            source.provider,
            source.server,
            '${row['musicId'] ?? id}',
          ),
          row: row,
          title: row['musicTitle'] ?? row['title'],
          bandKey: official ? _normalize(_first(bandName)) : '',
          bandName: bandName,
          jacket: _absolute(
            '${row['jacketUrl'] ?? row['jacketThumbUrl'] ?? ''}',
          ),
          thumb: _absolute(
            '${row['jacketThumbUrl'] ?? row['jacketUrl'] ?? ''}',
          ),
          audio: '${row['musicUrl'] ?? ''}'.isEmpty
              ? ''
              : _absolute('${row['musicUrl']}'),
          released: _releasedAt(row),
          performer: performer,
        );
      }(),
  ];
}

/// Game screens in the order a player meets them; unlisted cues follow.
const _bgmOrder = [
  'sound_bgm_home',
  'sound_bgm_livetop',
  'sound_bgm_liveresult',
  'sound_bgm_gachatop',
  'sound_bgm_gacharesult',
  'sound_bgm_birthday',
  'sound_bgm_snapdiary_positive',
  'sound_bgm_snapdiary_neutral',
  'sound_bgm_snapdiary_negative',
  'sound_bgm_mygo_offline',
  'sound_bgm_mujica_offline',
  'sound_bgm_yumemita_offline',
  'sound_bgm_millsage_offline',
  'sound_bgm_kadan_offline',
  'spot_1_1',
  'timing_adjust',
];
const _bgmBands = {
  'mygo': 1,
  'mujica': 2,
  'yumemita': 3,
  'millsage': 4,
  'kadan': 5,
};

Future<List<LibrarySong>> _loadBgm(
  String server,
  HaneokaApi api,
  Map<int, Row> bands,
) async {
  final rows = _rows(
    await api.json('/api/v1/servers/$server/audio/views/master-bgms'),
  ).values.toList();
  int rank(String cue) =>
      (_bgmOrder.indexOf(cue) + _bgmOrder.length + 1) % (_bgmOrder.length + 1);
  rows.sort((a, b) => rank('${a['cueName']}') - rank('${b['cueName']}'));
  final seen = <String>{};
  final out = <LibrarySong>[];
  for (final row in rows) {
    final cue = '${row['cueName'] ?? ''}';
    final path = '${row['outputPath'] ?? ''}';
    if (row['missing'] != false ||
        !RegExp(r'^runtime/cri/sound/(?:bgm|ambientbgm)/').hasMatch(path) ||
        !seen.add(cue)) {
      continue;
    }
    final theme = RegExp(r'^sound_bgm_(\w+)_offline$').firstMatch(cue)?[1];
    final band = bands[_bgmBands[theme] ?? 0];
    final logo = _absolute(
      '${band?['logo'] ?? band?['icon'] ?? '/android-chrome-192x192.png'}',
    );
    out.add(
      LibrarySong(
        ref: TrackRef('our-notes', server, 'bgm-$cue'),
        row: const {},
        title: cue,
        bandKey: '',
        bandName: band?['bandName'] ?? band?['name'] ?? '',
        jacket: logo,
        thumb: logo,
        audio: _absolute('${row['playableUrl'] ?? ''}'),
        released: 0,
        bgm: cue,
      ),
    );
  }
  return out;
}

final _libraries = <HaneokaApi, Future<SongLibrary>>{};

/// Both catalogues once per Our Notes server (`loadSongLibrary`).
Future<SongLibrary> loadSongLibrary(String server, HaneokaApi api) {
  return cachedResource(_libraries, api, () => _build(server, api));
}

Future<SongLibrary> _build(String server, HaneokaApi api) async {
  _Source? native, gbp;
  final partial = <String>[];
  try {
    native = await _load('our-notes', server, api);
  } catch (_) {
    partial.add('our-notes');
  }
  try {
    gbp = await _load('bestdori', 'jp', api);
  } catch (_) {
    partial.add('bestdori');
  }
  if (native == null && gbp == null) throw StateError('library-unavailable');
  final bgm = await _loadBgm(
    server,
    api,
    native?.registry.bands ?? const {},
  ).catchError((Object _) => <LibrarySong>[]);
  if (gbp != null && native != null) {
    gbp.registry.portraitFallbacks ??= _cryChicPortraits(native);
  }
  final primary = native == null ? <LibrarySong>[] : _songsOf(native);
  final secondary = gbp == null ? <LibrarySong>[] : _songsOf(gbp);
  String identity(LibrarySong song) =>
      '${_normalize(_first(song.title))}|${_normalize(_first(song.bandName))}';
  final byIdentity = {for (final song in primary) identity(song): song};
  final byKey = <String, LibrarySong>{};
  final songs = <LibrarySong>[];
  for (final song in primary) {
    songs.add(song);
    byKey[song.key] = song;
  }
  for (final song in secondary) {
    final twin = byIdentity[identity(song)];
    if (twin != null) {
      // Same song in both games: the Our Notes entry, at its first release.
      twin.aliases.add(song.key);
      if (song.released < twin.released) twin.released = song.released;
      if (twin.bandKey.isEmpty) twin.bandKey = song.bandKey;
      byKey[song.key] = twin;
      continue;
    }
    songs.add(song);
    byKey[song.key] = song;
  }
  songs.sort((a, b) {
    final c = a.released.compareTo(b.released);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  final bands = <String, LibraryBand>{};
  for (final source in [?native, ?gbp]) {
    for (final MapEntry(key: bandId, value: band)
        in source.registry.bands.entries) {
      final official = source.provider == 'bestdori'
          ? band['official'] == true
          : band['official'] != false;
      if (!official) continue;
      final key = _normalize(_first(band['bandName'] ?? band['name']));
      if (key.isEmpty) continue;
      final entry = bands[key] ??= LibraryBand(
        key,
        band['bandName'] ?? band['name'],
      );
      if (entry.logo.isEmpty) {
        final logo = '${band['logo'] ?? band['icon'] ?? ''}';
        if (logo.isNotEmpty) entry.logo = _absolute(logo);
      }
      entry.sources.add('${source.provider}:${source.server}:$bandId');
    }
  }
  for (final song in songs) {
    bands[song.bandKey]?.songs.add(song);
  }
  for (final song in bgm) {
    byKey[song.key] = song;
  }
  return SongLibrary(
    songs,
    byKey,
    [
      for (final band in bands.values)
        if (band.songs.isNotEmpty) band,
    ],
    partial,
    bgm,
  );
}

/// The song's page in the app: Our Notes songs by server, GBP songs in the
/// GBP archive.
String songDetailPath(LibrarySong song, String locale) =>
    song.ref.provider == 'bestdori'
    ? '/$locale/community/songs-bestdori/detail/?song=${Uri.encodeComponent(song.ref.musicId)}'
    : '/${song.ref.server}/$locale/songs/${song.ref.musicId}/';

class PlaylistOwner {
  const PlaylistOwner(this.uid, this.name, this.image);
  final int uid;
  final String? name;
  final String? image;
}

class PlaylistCover {
  const PlaylistCover(
    this.kind, {
    this.song,
    this.url,
    this.attachmentId,
    this.logo,
  });

  /// `auto`, `song`, `upload` or `band`.
  final String kind;
  final TrackRef? song;
  final String? url;
  final String? attachmentId;
  final String? logo;
}

class Playlist {
  Playlist({
    required this.id,
    required this.kind,
    required this.title,
    required this.cover,
    required this.refs,
    required this.trackCount,
    required this.preview,
    required this.complete,
    this.group,
    this.description,
    this.owner,
    this.likeCount = 0,
    this.viewerLiked = false,
    this.viewerOwns = false,
    this.visibility = 'public',
    this.version = 1,
    this.updatedAt = 0,
    this.aliases = const [],
  });
  final String id;

  /// `official`, `game` or `community`.
  final String kind;
  final String? group;

  /// A localized title, or `{key: …}` for the website's own names.
  final Object? title;
  final String? description;
  final PlaylistCover cover;
  final List<TrackRef> refs;
  final int trackCount;
  final List<TrackRef> preview;
  final PlaylistOwner? owner;
  int likeCount;
  bool viewerLiked;
  final bool viewerOwns;
  final String visibility;
  final int version;
  final int updatedAt;
  final bool complete;
  final List<String> aliases;
}

/// The website's own playlists and the game's lists (`officialPlaylists`).
List<Playlist> officialPlaylists(
  SongLibrary library,
  List<Row> gamePlaylists, {
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final released = library.songs.where((s) => s.released <= at).toList();
  final latest = released.reversed.take(40).toList();
  List<TrackRef> refs(Iterable<LibrarySong> songs) => [
    for (final song in songs) song.ref,
  ];
  final lists = <Playlist>[];
  if (latest.isNotEmpty) {
    lists.add(
      Playlist(
        id: 'official:new',
        kind: 'official',
        group: 'featured',
        title: const {'key': 'playlistPage.newReleases'},
        cover: PlaylistCover('song', song: latest.first.ref),
        refs: refs(latest),
        trackCount: latest.length,
        preview: refs(latest.take(4)),
        complete: true,
      ),
    );
  }
  for (final band in library.bands) {
    final songs = band.songs;
    final newest =
        songs.reversed.where((s) => s.released <= at).firstOrNull ?? songs.last;
    lists.add(
      Playlist(
        id: 'official:band:${Uri.encodeComponent(band.key)}',
        kind: 'official',
        group: 'band',
        title: band.name,
        cover: PlaylistCover('band', song: newest.ref, logo: band.logo),
        refs: refs(songs),
        trackCount: songs.length,
        preview: refs(songs.skip(songs.length > 4 ? songs.length - 4 : 0)),
        complete: true,
        aliases: [
          for (final source in band.sources)
            ...() {
              final [provider, server, id] = source.split(':');
              return [
                '$provider:$server:band:$id',
                if (provider == 'bestdori') ...[
                  'catalog:$server:band:$id',
                  '$provider:$id',
                  id,
                ] else
                  '$provider:$id',
              ];
            }(),
        ],
      ),
    );
  }
  if (library.songs.isNotEmpty) {
    lists.add(
      Playlist(
        id: 'official:all',
        kind: 'official',
        group: 'featured',
        title: const {'key': 'playlistPage.allSongs'},
        cover: const PlaylistCover('auto'),
        refs: refs(library.songs),
        trackCount: library.songs.length,
        preview: refs(
          library.songs
              .skip(library.songs.length > 4 ? library.songs.length - 4 : 0)
              .toList()
              .reversed,
        ),
        complete: true,
      ),
    );
  }
  if (library.bgm.isNotEmpty) {
    lists.add(
      Playlist(
        id: 'official:bgm',
        kind: 'official',
        group: 'featured',
        title: const {'key': 'playlistPage.gameBgm'},
        cover: const PlaylistCover('auto'),
        refs: refs(library.bgm),
        trackCount: library.bgm.length,
        preview: refs(library.bgm.take(4)),
        complete: true,
      ),
    );
  }
  for (final item in gamePlaylists) {
    final source = '${item['source'] ?? item['type'] ?? ''}';
    if (source == 'band') continue;
    final tracks = [
      for (final track in item['tracks'] as List? ?? const [])
        ?TrackRef.parse((track as Map?)?['assetRef']),
    ];
    final stage =
        RegExp(r'(\d+)$').firstMatch('${item['assetBundleName'] ?? ''}')?[1] ??
        '${item['sourceId'] ?? ''}';
    lists.add(
      Playlist(
        id: '${item['id']}',
        kind: 'game',
        group: source == 'stage-challenge' ? 'stage-challenge' : 'other',
        title: item['title'],
        description: item['description'] as String?,
        cover: PlaylistCover(
          'auto',
          url: stage.isEmpty
              ? null
              : '$_origin/api/v1/garupa/bestdori/jp/media/stage-challenge/${Uri.encodeComponent(stage)}',
        ),
        refs: tracks,
        trackCount: tracks.length,
        preview: tracks.take(4).toList(),
        complete: true,
      ),
    );
  }
  return lists;
}

Playlist communityPlaylist(Row value, {bool complete = false}) {
  final cover = (value['cover'] as Map?)?.cast<String, Object?>() ?? const {};
  final owner = (value['owner'] as Map?)?.cast<String, Object?>();
  final refs = [
    for (final track in value['tracks'] as List? ?? const [])
      ?TrackRef.parse(track),
  ];
  return Playlist(
    id: '${value['id']}',
    kind: 'community',
    title: '${value['title'] ?? ''}',
    description: value['description'] as String?,
    cover: PlaylistCover(
      cover['kind'] == 'song' || cover['kind'] == 'upload'
          ? cover['kind'] as String
          : 'auto',
      song: TrackRef.parse(cover['song']),
      url: cover['url'] is String ? _absolute(cover['url'] as String) : null,
      attachmentId: cover['attachmentId'] as String?,
    ),
    refs: refs,
    trackCount: (value['trackCount'] as num?)?.toInt() ?? refs.length,
    preview: [
      for (final ref in value['preview'] as List? ?? const [])
        ?TrackRef.parse(ref),
    ],
    owner: owner == null
        ? null
        : PlaylistOwner(
            (owner['uid'] as num?)?.toInt() ?? 0,
            owner['name'] as String?,
            owner['image'] is String
                ? _absolute(owner['image'] as String)
                : null,
          ),
    likeCount: (value['likeCount'] as num?)?.toInt() ?? 0,
    viewerLiked: value['viewerLiked'] == true,
    viewerOwns: value['viewerOwns'] == true,
    visibility: value['visibility'] == 'private' ? 'private' : 'public',
    version: (value['version'] as num?)?.toInt() ?? 1,
    updatedAt: (value['updatedAt'] as num?)?.toInt() ?? 0,
    complete: complete,
  );
}

/// Jackets for a cover: the chosen song, else a mosaic of the first four
/// (`coverImages`).
({String? single, List<String> mosaic}) coverImages(
  Playlist playlist,
  SongLibrary? library,
) {
  if (playlist.cover.kind == 'upload' && playlist.cover.url != null) {
    return (single: playlist.cover.url, mosaic: const []);
  }
  String jacket(TrackRef? ref) =>
      (ref == null ? null : library?.byKey[ref.key]?.jacket) ?? '';
  if ((playlist.cover.kind == 'song' || playlist.cover.kind == 'band') &&
      jacket(playlist.cover.song).isNotEmpty) {
    return (single: jacket(playlist.cover.song), mosaic: const []);
  }
  final mosaic = {
    for (final ref
        in playlist.preview.isNotEmpty
            ? playlist.preview
            : playlist.refs.take(4))
      if (jacket(ref) case final j when j.isNotEmpty) j,
  }.toList();
  return mosaic.length >= 4
      ? (single: null, mosaic: mosaic.take(4).toList())
      : (single: mosaic.firstOrNull, mosaic: const []);
}
