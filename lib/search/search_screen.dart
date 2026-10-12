import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/cross_server.dart';
import '../catalog/profiles.dart';
import '../catalog/visuals.dart';
import '../core/app_state.dart';
import '../core/net.dart';
import '../help/help_screen.dart';
import '../shell/links.dart';
import '../shell/page.dart';
import '../shell/routes.dart';
import '../stories/stories.dart';
import '../ui/app_image.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';

/// The website's search scopes (`SEARCH_SCOPES`).
const _scopes = ['all', 'catalog', 'stories', 'help', 'community'];
const _scopeLabels = {
  'all': 'common.states.all',
  'catalog': 'navigation.catalog',
  'stories': 'navigation.stories',
  'help': 'navigation.help',
  'community': 'navigation.community',
};

/// A catalogue resource's search group (`searchCategory`).
const _groups = {
  'songs': 'navigation.songs',
  'characters': 'navigation.characters',
  'cards': 'navigation.cards',
  'support-cards': 'navigation.cards',
  'events': 'navigation.events',
  'gacha': 'navigation.gacha',
  'stamps': 'navigation.stamps',
  'stickers': 'navigation.stamps',
  'comics': 'navigation.comics',
  'items': 'navigation.items',
  'band-items': 'navigation.bandItems',
};

class _Entry {
  _Entry(
    this.group,
    this.section,
    this.title,
    this.subtitle,
    this.image,
    this.text,
    this.open,
  );
  final String group;
  final String section;
  final String title;
  final String subtitle;
  final String? image;

  /// Every language's title and the subtitle, lower-cased, for matching.
  final String text;
  final void Function(BuildContext context) open;
}

String _all(Object? value) => switch (value) {
  List() => value.whereType<String>().join(' '),
  String() => value,
  _ => '',
};

/// Search (`global-search`): the catalogue, stories and help as published
/// for this release, matched in every language, and community posts.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Future<List<_Entry>>? _index;
  String _query = '';
  String _scope = 'all';
  Future<List<Map>>? _posts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _index ??= _build();
  }

  Future<List<_Entry>> _build() async {
    final state = AppScope.of(context);
    final api = state.api;
    final t = state.text;
    final visuals = await CatalogVisuals.of(api);
    final entries = <_Entry>[];
    final resources = [
      for (final profile in catalogProfiles)
        if (_groups.containsKey(profile.resource) ||
            profile.presentation == Presentation.system)
          profile,
    ];
    final documents = await Future.wait([
      for (final profile in resources)
        (crossCatalogIds.containsKey(profile.resource)
                ? crossServerCollection(
                    resource: profile.resource,
                    selected: state.server,
                    apis: state.catalogApis,
                    rowsPath: profile.document,
                  )
                : api.catalog(profile.resource))
            .then<Object?>((v) => v, onError: (_) => null),
      crossServerCollection(
        resource: 'stories',
        selected: state.server,
        apis: state.catalogApis,
        rowsPath: 'episodes',
      ).then<Object?>((v) => v, onError: (_) => null),
      api.catalog('help').then<Object?>((v) => v, onError: (_) => null),
    ]);
    for (final (index, profile) in resources.indexed) {
      final kit = CatalogKit(
        profile,
        t,
        api,
        visuals,
        songTitles: state.songTitle,
      );
      Object? rows = documents[index];
      if (profile.document != null && rows is! List) {
        rows = readPath(rows, profile.document!);
      }
      final items = switch (rows) {
        Map() => [
          for (final MapEntry(:key, :value) in rows.entries)
            if (value is Map)
              {'_key': '$key', ...value.cast<String, Object?>()},
        ],
        List() => [
          for (final value in rows)
            if (value is Map) value.cast<String, Object?>(),
        ],
        _ => <Map<String, Object?>>[],
      };
      final group = _groups[profile.resource] ?? 'navigation.catalog';
      for (final item in items) {
        final title = kit.title(item);
        final subtitle = kit.subtitle(item);
        entries.add(
          _Entry(
            group,
            'catalog',
            title,
            subtitle,
            kit.images(item).firstOrNull,
            [
              for (final field in profile.title) _all(item[field]),
              title,
              subtitle,
              kit.id(item),
            ].join(' ').toLowerCase(),
            (context) => openEntity(
              context,
              profile,
              item,
              api: state.apiFor('${item[serverKey] ?? state.server}'),
            ),
          ),
        );
      }
    }
    final stories = documents[resources.length];
    final episodes = switch (stories is Map ? stories['episodes'] : stories) {
      final Map map => map.values,
      final List list => list,
      _ => const [],
    };
    for (final episode in episodes.whereType<Map>()) {
      final title = t.text(episode['title']);
      final chapter = t.text(episode['chapterName']);
      entries.add(
        _Entry(
          'navigation.stories',
          'stories',
          title.isEmpty ? chapter : title,
          chapter,
          null,
          '${_all(episode['title'])} ${_all(episode['chapterName'])}'
              .toLowerCase(),
          (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StoryReaderScreen(
                api: state.apiFor('${episode[serverKey] ?? state.server}'),
                episode: {
                  ...episode.cast<String, Object?>(),
                  'storyKey': episode['storyKey'] ?? episode['storyId'],
                },
              ),
            ),
          ),
        ),
      );
    }
    final help = documents[resources.length + 1] as Map?;
    for (final category in switch (help?['categories']) {
      final Map map => map.values.whereType<Map>(),
      _ => const <Map>[],
    }) {
      final topics = switch (category['subcategories']) {
        final Map map => map.values,
        final List list => list,
        _ => const [],
      };
      for (final topic in topics.whereType<Map>()) {
        entries.add(
          _Entry(
            'navigation.help',
            'help',
            t.text(topic['title']),
            t.text(category['title']),
            null,
            '${_all(topic['title'])} ${_all(topic['description'])}'
                .toLowerCase(),
            (context) => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen())),
          ),
        );
      }
    }
    return entries;
  }

  Future<List<Map>> _community(String query) async {
    final uri = Uri.https('haneoka.org', '/api/v1/community/posts', {
      'q': query,
      'scope': 'latest',
      'order': 'relevance',
      'state': 'active',
      'limit': '12',
    });
    final response = await netClient
        .get(uri)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) return const [];
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    return ((body as Map?)?['posts'] as List? ?? const [])
        .whereType<Map>()
        .toList();
  }

  void _search(String value) {
    final query = value.trim();
    setState(() {
      _query = query;
      _posts = query.isEmpty || query.length > 100 ? null : _community(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget empty(String text) => Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    Widget row(
      Widget? leading,
      String title,
      String subtitle,
      VoidCallback onTap,
    ) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Corner.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Corner.small),
              child: Container(
                width: 56,
                height: 56,
                color: scheme.surfaceContainerHighest,
                child: leading,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return ShellPage(
      title: t('common.actions.search', 'Search'),
      search: ShellSearch(
        label: t('common.actions.search', 'Search'),
        onChanged: _search,
        onSubmitted: _search,
      ),
      body: ListView(
        padding: pagePadding(context),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final scope in _scopes)
                    ButtonSegment(
                      value: scope,
                      label: Text(t(_scopeLabels[scope]!, scope)),
                    ),
                ],
                selected: {_scope},
                onSelectionChanged: (value) =>
                    setState(() => _scope = value.single),
              ),
            ),
          ),
          if (_query.isNotEmpty && _scope != 'community')
            FutureBuilder(
              future: _index,
              builder: (context, snapshot) {
                final index = snapshot.data;
                if (index == null) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final terms = _query.toLowerCase().split(RegExp(r'\s+'));
                final hits = [
                  for (final entry in index)
                    if ((_scope == 'all' || entry.section == _scope) &&
                        terms.every(entry.text.contains))
                      entry,
                ];
                final groups = <String, List<_Entry>>{};
                for (final hit in hits) {
                  (groups[hit.group] ??= []).add(hit);
                }
                if (groups.isEmpty) {
                  return _scope == 'all'
                      ? const SizedBox.shrink()
                      : empty(t('common.states.empty', 'Nothing found'));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final MapEntry(:key, :value) in groups.entries) ...[
                      heading('${t(key, key)}  ${value.length}'),
                      for (final entry in value.take(24))
                        row(
                          entry.image == null
                              ? Icon(
                                  entry.section == 'help'
                                      ? Symbols.help_rounded
                                      : Symbols.auto_stories_rounded,
                                  color: scheme.onSurfaceVariant,
                                )
                              : AppImage(
                                  candidates: [entry.image!],
                                  fit: BoxFit.cover,
                                ),
                          entry.title,
                          entry.subtitle,
                          () => entry.open(context),
                        ),
                    ],
                  ],
                );
              },
            ),
          if (_query.isNotEmpty && (_scope == 'all' || _scope == 'community'))
            FutureBuilder(
              future: _posts,
              builder: (context, snapshot) {
                final posts = snapshot.data ?? const <Map>[];
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (posts.isEmpty) {
                  return _scope == 'community'
                      ? empty(t('common.states.empty', 'Nothing found'))
                      : const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading(t('navigation.community', 'Community')),
                    for (final post in posts)
                      row(
                        switch ((post['attachments'] as List? ?? const [])
                            .whereType<Map>()
                            .firstOrNull?['contentUrl']) {
                          final String url => AppImage(
                            candidates: ['https://haneoka.org$url'],
                            fit: BoxFit.cover,
                            localized: false,
                          ),
                          _ => Icon(
                            Symbols.forum_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                        },
                        '${post['title'] ?? ''}',
                        [
                          '${post['excerpt'] ?? post['body'] ?? ''}'
                              .replaceAll(RegExp(r'\s+'), ' ')
                              .trim(),
                          '${post['authorName'] ?? ''}',
                        ].where((s) => s.isNotEmpty).join(' · '),
                        () => openLink(
                          context,
                          '/${t.locale}/community/posts/${post['id']}/',
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
