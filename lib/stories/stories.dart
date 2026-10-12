import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../catalog/visuals.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/audio.dart';
import '../core/i18n.dart';
import '../core/provider_api.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/detail.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';

/// The website's story sections (`StoryMode`).
const storyModes = [
  'event',
  'band',
  'link',
  'birthday',
  'home',
  'afterlive',
  'tutorial',
];

/// Which section an episode belongs to (`modeOf`): event-owned chapters,
/// then birthdays, then numbered band chapters, then by chapter key.
String? storyModeOf(
  Entry episode,
  Set<String> eventChapters, [
  Set<String> birthdayChapters = const {},
]) {
  final chapter = '${episode['chapterId'] ?? ''}';
  if (eventChapters.contains(chapter)) return 'event';
  if (episode['storyCategory'] == 'birthday' ||
      birthdayChapters.contains(chapter)) {
    return 'birthday';
  }
  if (((episode['chapterId'] as num?) ?? 0) < 900000) return 'band';
  return switch (episode['chapterKey']) {
    'asset_linkstory' => 'link',
    'asset_home' => 'home',
    'asset_afterlive' => 'afterlive',
    'asset_tutorial' => 'tutorial',
    _ => null,
  };
}

String _duration(Object? seconds) {
  if (seconds is! num || seconds <= 0) return '';
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _StoryData {
  _StoryData(this.document, this.visuals, {this.providerMode});
  final Map document;
  final CatalogVisuals visuals;

  /// Another game's section: every episode is in it.
  final String? providerMode;

  late final Set<String> eventChapters = {
    for (final e
        in (document['storyEvents'] as List? ?? const []).whereType<Map>())
      '${e['chapterId']}',
  };
  late final List<Entry> episodes = [
    for (final MapEntry(:key, :value)
        in ((document['episodes'] as Map?) ?? const {}).entries)
      if (value is Entry) {'_key': key, ...value},
  ];

  /// The game's birthday stories: their chapters, and whose birthday each is.
  late final Map<String, int> birthdayCharacter = {
    for (final rows
        in ((document['birthdayStories'] as Map?) ?? const {}).values)
      for (final row in (rows as List? ?? const []).whereType<Map>())
        '${row['storyKey']}': (row['characterId'] as num).toInt(),
  };
  late final Set<String> birthdayChapters = {
    for (final rows
        in ((document['birthdayStories'] as Map?) ?? const {}).values)
      for (final row in (rows as List? ?? const []).whereType<Map>())
        '${row['chapterId']}',
  };

  /// Home talks by their spot (`homeSpots[].talks`).
  late final Map<String, Map> spotOfStory = {
    for (final spot in spots.values.whereType<Map>())
      for (final talk in (spot['talks'] as List? ?? const []).whereType<Map>())
        '${talk['storyKey']}': spot,
  };

  String? mode(Entry e) =>
      providerMode ?? storyModeOf(e, eventChapters, birthdayChapters);

  Map get chapters => (document['chapters'] as Map?) ?? const {};
  Map get spots => (document['homeSpots'] as Map?) ?? const {};
}

/// One story section (`story-workspace` for the release): the axis it is
/// organised by in the rail, the chosen group's heading, and its episodes in
/// the game's order, each opening its transcript.
class StoriesScreen extends StatefulWidget {
  const StoriesScreen({super.key, required this.mode, this.api, this.title});
  final String mode;

  /// GBP or Project Sekai stories (`origin`); this release's when null.
  final HaneokaApi? api;
  final String? title;
  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  Future<_StoryData>? _data;
  String? _rail;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_StoryData> _load() async {
    if (widget.api case final api?) return _loadProvider(api);
    final api = AppScope.of(context).api;
    final (document, visuals) = await (
      api.catalog('stories'),
      CatalogVisuals.of(api),
    ).wait;
    return _StoryData((document as Map?) ?? const {}, visuals);
  }

  /// A provider's section, read as this release's document: episodes by id
  /// and their chapters with the event logo or band banner
  /// (`loadBestdori`).
  Future<_StoryData> _loadProvider(HaneokaApi api) async {
    if (widget.mode == 'card' &&
        api is ProviderApi &&
        api.provider == 'bestdori') {
      return _loadCards(api);
    }
    final (rows, visuals) = await (
      api.catalog('stories/${widget.mode}'),
      CatalogVisuals.of(api),
    ).wait;
    final records = switch (rows) {
      List() => rows.whereType<Entry>(),
      Map() => rows.values.whereType<Entry>(),
      _ => const <Entry>[],
    };
    final episodes = <String, Entry>{};
    final chapters = <String, Entry>{};
    for (final e in records) {
      final id = '${e['storyId'] ?? e['storyKey']}';
      episodes[id] = {
        ...e,
        'storyKey': e['storyKey'] ?? e['storyId'],
        'image': e['episodeImage'] ?? e['image'],
      };
      final chapter = '${e['chapterId'] ?? ''}';
      chapters.putIfAbsent(
        chapter,
        () => {
          'chapterName': e['chapterName'] ?? e['eventName'],
          'banner': e['thumbnail'] ?? e['image'],
          'chapterSort': e['chapterSort'],
        },
      );
    }
    return _StoryData(
      {'episodes': episodes, 'chapters': chapters},
      visuals,
      providerMode: widget.mode,
    );
  }

  /// GBP card stories are a card collection by character; a card opens
  /// its own episodes (`isCardSection`).
  Future<_StoryData> _loadCards(HaneokaApi api) async {
    final (rows, visuals) = await (
      api.catalog('cards'),
      CatalogVisuals.of(api),
    ).wait;
    final cards = switch (rows) {
      List() => rows.whereType<Entry>(),
      Map() => rows.values.whereType<Entry>(),
      _ => const <Entry>[],
    }.where((card) => card['hasStory'] != false);
    final episodes = <String, Entry>{};
    final chapters = <String, Entry>{};
    for (final card in cards) {
      final character = (card['characterId'] as num?)?.toInt();
      final thumbnails = card['cardThumbnails'];
      episodes['card:${card['cardId']}'] = {
        'storyKey': 'card:${card['cardId']}',
        'chapterId': character,
        'title': card['prefix'],
        'image':
            (thumbnails is Map ? thumbnails['normal'] : null) ??
            card['cardImage'],
        'storySort': card['releaseAt'],
        'cardId': card['cardId'],
      };
      chapters.putIfAbsent(
        '$character',
        () => {
          'chapterName': visuals.characters[character]?['characterName'],
          'banner': visuals.characters[character]?['faceImage'],
          'chapterSort': character,
        },
      );
    }
    return _StoryData(
      {'episodes': episodes, 'chapters': chapters},
      visuals,
      providerMode: widget.mode,
    );
  }

  String _label(SiteText t) => widget.title != null
      ? widget.title!
      : widget.mode == 'birthday'
      ? t('story.labels.birthdayStory', 'Birthday stories')
      : t('story.navigation.${widget.mode}', widget.mode);

  /// The rail key of an episode: its chapter, pair, character or band.
  String _railKey(Entry e, _StoryData data) => switch (widget.mode) {
    'link' => ([
      ...((e['characterIds'] as List?) ?? const []),
    ]..sort((a, b) => '$a'.compareTo('$b'))).join('-'),
    'afterlive' => 'all',
    'home' => '${data.spotOfStory['${e['storyKey']}']?['spotId'] ?? ''}',
    _ => '${e['chapterId']}',
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    return FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final episodes = data == null
            ? const <Entry>[]
            : [
                for (final e in data.episodes)
                  if (data.mode(e) == widget.mode) e,
              ];
        final keys = <String>{for (final e in episodes) _railKey(e, data!)}
            .toList();
        if (data != null && data.providerMode != null) {
          // Another game's chapters by first release, newest events first.
          num sortOf(String key) =>
              (data.chapters[key] as Map?)?['chapterSort'] as num? ?? 0;
          keys.sort(
            (a, b) => widget.mode == 'event'
                ? sortOf(b).compareTo(sortOf(a))
                : sortOf(a).compareTo(sortOf(b)),
          );
        } else if (widget.mode == 'event') {
          keys.sort(
            (a, b) => (int.tryParse(b) ?? 0).compareTo(int.tryParse(a) ?? 0),
          );
        } else {
          keys.sort(
            (a, b) => (int.tryParse(a.split('-').first) ?? 0).compareTo(
              int.tryParse(b.split('-').first) ?? 0,
            ),
          );
        }
        final rail = keys.contains(_rail) ? _rail! : keys.firstOrNull;
        // A search reads every episode of the section, not just the rail's.
        final query = _query.trim().toLowerCase();
        bool matches(Entry e) =>
            '${t.text(e['title'])} ${t.text(e['description'])} ${t.text(e['chapterName'])} ${e['episodeNumber'] ?? ''}'
                .toLowerCase()
                .contains(query);
        final chosen =
            [
              for (final e in episodes)
                if (query.isNotEmpty ? matches(e) : _railKey(e, data!) == rail)
                  e,
            ]..sort((a, b) {
              final order = ((a['storySort'] ?? a['episodeNumber'] ?? 0) as num)
                  .compareTo(
                    (b['storySort'] ?? b['episodeNumber'] ?? 0) as num,
                  );
              return widget.mode == 'afterlive' ? -order : order;
            });
        final groups = <(String, List<Entry>)>[
          (
            widget.mode == 'band'
                ? t('story.labels.bandStory', 'Band story')
                : t('story.labels.eventStory', 'Story'),
            [
              for (final e in chosen)
                if (e['isAnotherEpisode'] != true &&
                    e['isExtraEpisode'] != true)
                  e,
            ],
          ),
          (
            t('story.labels.perspectiveStory', 'Perspective story'),
            [
              for (final e in chosen)
                if (e['isAnotherEpisode'] == true) e,
            ],
          ),
          (
            t('story.labels.extraStory', 'Extra story'),
            [
              for (final e in chosen)
                if (e['isExtraEpisode'] == true) e,
            ],
          ),
        ].where((g) => g.$2.isNotEmpty).toList();
        return ShellPage(
          title: _label(t),
          search: ShellSearch(
            label: t('common.actions.search', 'Search'),
            onChanged: (value) => setState(() => _query = value),
          ),
          status: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                data == null ? '' : '${chosen.length}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          body: snapshot.hasError
              ? Center(
                  child: FilledButton.tonal(
                    onPressed: () => setState(() => _data = _load()),
                    child: Text(t('common.actions.retry', 'Retry')),
                  ),
                )
              : data == null
              ? const Center(child: CircularProgressIndicator())
              : _body(
                  context,
                  data,
                  query.isEmpty ? keys : const [],
                  query.isEmpty ? rail : null,
                  chosen,
                  groups,
                ),
        );
      },
    );
  }

  ({String title, String? image, String? description}) _railInfo(
    _StoryData data,
    String key,
    SiteText t,
    HaneokaApi api,
  ) {
    String? asset(Object? path) =>
        path is String && path.isNotEmpty ? api.asset(path).toString() : null;
    switch (widget.mode) {
      case 'link':
        final ids = key.split('-').map(int.tryParse).whereType<int>();
        return (
          title: ids
              .map(
                (id) => t.text(data.visuals.characters[id]?['characterName']),
              )
              .join(' × '),
          image: asset(data.visuals.characters[ids.firstOrNull]?['faceImage']),
          description: null,
        );
      case 'afterlive':
        return (title: '', image: null, description: null);
      case 'home':
        final spot = data.spots[key] as Map?;
        return (
          title: t.text(spot?['name']),
          image: asset(spot?['thumbnail']),
          description: t.text(spot?['bandName']),
        );
      default:
        final chapter = data.chapters[key] as Map?;
        final event = (data.document['storyEvents'] as List? ?? const [])
            .whereType<Map>()
            .where((e) => '${e['chapterId']}' == key)
            .firstOrNull;
        return (
          title: t.text(
            chapter?['chapterName'] ?? event?['chapterName'] ?? event?['title'],
          ),
          image: asset(chapter?['banner'] ?? event?['banner']),
          description: t
              .text(chapter?['description'] ?? event?['description'])
              .trim()
              .replaceAll(
                RegExp(r'\s*\r?\n\s*'),
                t.locale.startsWith('ja') || t.locale.startsWith('zh')
                    ? ''
                    : ' ',
              ),
        );
    }
  }

  Widget _body(
    BuildContext context,
    _StoryData data,
    List<String> keys,
    String? rail,
    List<Entry> chosen,
    List<(String, List<Entry>)> groups,
  ) {
    final state = AppScope.of(context);
    final t = state.text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final padding = pagePadding(context);
    final api = widget.api ?? state.api;
    final info = rail == null ? null : _railInfo(data, rail, t, api);
    return CustomScrollView(
      slivers: [
        if (keys.length > 1 ||
            (keys.isNotEmpty &&
                const {'event', 'birthday'}.contains(widget.mode)))
          SliverToBoxAdapter(
            child: SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, 0),
                itemCount: keys.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final key = keys[index];
                  final item = _railInfo(data, key, t, api);
                  final count = data.episodes
                      .where(
                        (e) =>
                            data.mode(e) == widget.mode &&
                            _railKey(e, data) == key,
                      )
                      .length;
                  final selected = key == rail;
                  return SizedBox(
                    width: 148,
                    child: Material(
                      color: selected
                          ? scheme.secondaryContainer
                          : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(Corner.medium),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => setState(() => _rail = key),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 44,
                                width: double.infinity,
                                child: item.image == null
                                    ? null
                                    : AppImage(candidates: [item.image!]),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge,
                              ),
                              Text(
                                '$count ${t('story.labels.episodes', 'episodes')}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        if (info != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding.left, 16, padding.right, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (info.image != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: SizedBox(
                        width: 72,
                        height: 48,
                        child: AppImage(candidates: [info.image!]),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(info.title, style: theme.textTheme.headlineSmall),
                        if ((info.description ?? '').isNotEmpty)
                          Text(
                            info.description!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (final (title, list) in groups) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding.left, 16, padding.right, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${list.length}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: padding.left),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) => SliverGrid.builder(
                gridDelegate: collectionGrid(
                  context,
                  constraints.crossAxisExtent,
                  minWidth: 260,
                  aspectRatio: 16 / 9,
                ),
                itemCount: list.length,
                itemBuilder: (context, index) => _EpisodeTile(
                  episode: list[index],
                  data: data,
                  mode: widget.mode,
                  api: widget.api,
                ),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: padding.bottom)),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.data,
    required this.mode,
    this.api,
  });
  final Entry episode;
  final _StoryData data;
  final String mode;
  final HaneokaApi? api;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final api = this.api ?? state.api;
    final number = episode['episodeNumber'];
    final duration = _duration(episode['playTime']);
    String subtitle;
    if (mode == 'link' || mode == 'afterlive') {
      final level =
          episode['unlockCharacterFriendshipLevel'] ??
          episode['friendshipLevel'];
      subtitle = level == null
          ? ''
          : '${t('catalog.characters.fields.friendship', '')} Lv.$level';
    } else if (mode == 'birthday') {
      subtitle = t.text(
        data.visuals.characters[data
            .birthdayCharacter['${episode['storyKey']}']]?['characterName'],
      );
    } else if (mode == 'home') {
      subtitle = [
        for (final id in (episode['characterIds'] as List? ?? const []))
          t.text(
            data.visuals.characters[(id as num).toInt()]?['characterName'],
          ),
      ].join(', ');
    } else {
      subtitle = t
          .text(episode['description'])
          .replaceAll('\r', '')
          .replaceAll('\n', ' ')
          .trim();
    }
    return Tile(
      title: t.text(episode['title']).isEmpty
          ? '#$number'
          : t.text(episode['title']),
      subtitle: subtitle,
      adornments: mode == 'birthday'
          ? [
              if (data.visuals.characters[data
                      .birthdayCharacter['${episode['storyKey']}']]?['faceImage']
                  case final String face)
                api.asset(face).toString(),
            ]
          : [?data.visuals.bandIcon(episode['bandId'])],
      images: [
        for (final key in ['image', 'banner'])
          if (episode[key] case final String path when path.isNotEmpty)
            api.asset(path).toString(),
        if (mode == 'home')
          if (data.spotOfStory['${episode['storyKey']}']?['thumbnail']
              case final String path)
            api.asset(path).toString(),
      ],
      media: mode == 'afterlive' || mode == 'link' && episode['image'] == null
          ? StoryFaces(
              faces: [
                for (final id
                    in (episode['characterIds'] as List? ?? const []).take(2))
                  if (data.visuals.characters[(id as num).toInt()]?['faceImage']
                      case final String face)
                    api.asset(face).toString(),
              ],
            )
          : null,
      aspectRatio: 16 / 9,
      fit: BoxFit.cover,
      placeholder: Symbols.auto_stories_rounded,
      marks: [
        if (number is num)
          TileMark.text(
            MarkAt.start,
            '#${number.toInt().toString().padLeft(2, '0')}',
          ),
        if (duration.isNotEmpty) TileMark.text(MarkAt.bottomEnd, duration),
      ],
      onTap: () => episode['cardId'] != null
          ? _openCard(context, api)
          : Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    StoryReaderScreen(episode: episode, api: this.api),
              ),
            ),
    );
  }

  /// A GBP card's episodes, each opening in the reader.
  Future<void> _openCard(BuildContext context, HaneokaApi api) async {
    final t = AppScope.of(context).text;
    final card = await api
        .catalog('cards', '${episode['cardId']}')
        .then<Map?>((v) => v as Map?, onError: (_) => null);
    if (card == null || !context.mounted) return;
    final episodes = (card['episodes'] as List? ?? const []).whereType<Map>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          for (final e in episodes)
            ListTile(
              leading: const Icon(Symbols.auto_stories_rounded),
              title: Text(t.text(e['title'])),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StoryReaderScreen(
                      api: api,
                      episode: {
                        'storyKey':
                            'card.${e['resourceSetName'] ?? card['resourceSetName']}.${e['scenarioId']}',
                        'title': e['title'],
                      },
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// One episode as text (`projectHaneokaTranscript`): places, speakers with
/// their faces, lines and each line's voice, in order. The 3D stage player
/// is the website's alone for now.
class StoryReaderScreen extends StatefulWidget {
  const StoryReaderScreen({super.key, required this.episode, this.api});
  final Entry episode;
  final HaneokaApi? api;
  @override
  State<StoryReaderScreen> createState() => _StoryReaderScreenState();
}

/// A provider scenario as this release's transcript: grouped commands are
/// flattened and talk (`command: 2`) becomes a talk line; sounds are keyed
/// by their reference.
Map _transcript(Map detail) {
  final commands = detail['commands'] as List? ?? const [];
  if (!commands.any((c) => c is Map && c['command'] == 101)) return detail;
  final flat = <Map>[];
  void add(Map command) {
    if (command['command'] == 2) {
      flat.add({...command, 'type': 'talk'});
    }
  }

  for (final command in commands.whereType<Map>()) {
    final group = command['commandGroup'];
    if (group is Map) {
      for (final action
          in (group['actions'] as List? ?? const []).whereType<Map>()) {
        if (action['command'] case final Map inner) add(inner);
      }
    } else {
      add(command);
    }
  }
  final sounds = (detail['assets'] as Map?)?['sounds'];
  return {
    ...detail,
    'commands': flat,
    'assets': {
      ...((detail['assets'] as Map?) ?? const {}),
      'sounds': [
        if (sounds is Map)
          for (final MapEntry(:key, :value) in sounds.entries)
            if (value is Map) {'ref': key, ...value},
      ],
    },
  };
}

class _StoryReaderScreenState extends State<StoryReaderScreen> {
  Future<(Map, CatalogVisuals)>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = widget.api ?? AppScope.of(context).api;
    _data ??= (
      api
          .catalog(
            'stories',
            '${widget.episode['storyKey'] ?? widget.episode['_key']}',
          )
          .then((v) => {...widget.episode, ..._transcript(v as Map)}),
      CatalogVisuals.of(api),
    ).wait;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final api = widget.api ?? state.api;
    final t = state.text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final detail = data?.$1 ?? widget.episode;
        final visuals = data?.$2;
        final sounds = <String, String>{
          for (final s
              in ((detail['assets'] as Map?)?['sounds'] as List? ?? const [])
                  .whereType<Map>())
            if (s['playableUrl'] is String)
              '${s['ref'] ?? '${s['cueSheetName']}/${s['cueName']}'}': api
                  .asset(s['playableUrl'] as String)
                  .toString(),
        };
        final lines = <Widget>[];
        final voices = <Track>[];
        for (final command
            in (detail['commands'] as List? ?? const []).whereType<Map>()) {
          final type = command['type'];
          if (type == 'location' || type == 'subtitle') {
            final text = t.text(command['text']);
            if (text.isNotEmpty) {
              lines.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.location_on_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          text,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          }
          if (type != 'talk') continue;
          final target = (command['targets'] as List? ?? const [])
              .whereType<Map>()
              .firstOrNull;
          final character =
              visuals?.characters[(target?['characterId'] as num?)?.toInt()];
          final face = character?['faceImage'] ?? target?['faceImage'];
          final name = t.text(
            target?['name'] ??
                (command['targetTextNames'] as List?)?.firstOrNull,
          );
          final text = t.text(command['text']).replaceAll(r'\n', '\n');
          final ref = (command['voiceRefs'] as List?)
              ?.whereType<String>()
              .firstOrNull;
          final url = ref == null ? null : sounds[ref];
          final track = url == null
              ? null
              : Track(
                  id: url,
                  url: url,
                  title: name,
                  subtitle: text,
                  artwork: face is String ? api.asset(face).toString() : null,
                );
          if (track != null) voices.add(track);
          lines.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipOval(
                    child: Container(
                      width: 40,
                      height: 40,
                      color: scheme.surfaceContainerHighest,
                      child: face is String
                          ? AppImage(candidates: [api.asset(face).toString()])
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (name.isNotEmpty)
                          Text(
                            name,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(text, style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  ),
                  if (track != null)
                    ListenableBuilder(
                      listenable: state.audio,
                      builder: (context, _) => IconButton(
                        tooltip: t('story.labels.playVoice', 'Play voice'),
                        onPressed: () => state.audio.toggle(track),
                        icon: Icon(
                          state.audio.isPlaying(track.id)
                              ? Symbols.pause_rounded
                              : Symbols.volume_up_rounded,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        final title = t.text(detail['title']);
        return ShellPage(
          title: title.isEmpty ? '#${detail['episodeNumber'] ?? ''}' : title,
          actions: [
            if (voices.isNotEmpty)
              BarAction(
                icon: Symbols.playlist_play_rounded,
                label: t.label('playAll', 'Play all'),
                onPressed: () => state.audio.playQueue(voices),
              ),
          ],
          body: snapshot.hasError
              ? Center(
                  child: Text(t('common.states.unavailable', 'Unavailable')),
                )
              : data == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: pagePadding(context),
                  children: [
                    if (detail['image'] is String)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Corner.extraLarge),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: AppImage(
                            candidates: [
                              state.api
                                  .asset(detail['image'] as String)
                                  .toString(),
                            ],
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (t.text(detail['description']).isNotEmpty)
                      Text(
                        t.text(detail['description']).replaceAll('\r', ''),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    DetailSection(
                      icon: Symbols.chat_rounded,
                      title: t('story.labels.conversation', 'Conversation'),
                      count: voices.length,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: lines,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Two characters' faces side by side: an after-live talk's media.
class StoryFaces extends StatelessWidget {
  const StoryFaces({super.key, required this.faces});
  final List<String> faces;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final face in faces)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ClipOval(
                    child: SizedBox.square(
                      dimension: 64,
                      child: AppImage(candidates: [face], fit: BoxFit.cover),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
