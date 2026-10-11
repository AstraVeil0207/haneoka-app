import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/detail_screen.dart';
import '../catalog/profiles.dart';
import '../catalog/visuals.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../core/relative_time.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';

CatalogProfile _profile(String resource) =>
    catalogProfiles.firstWhere((p) => p.resource == resource);

/// The website's home dashboard: banners the game is showing, the current
/// event, the latest songs and cards, and the next birthdays.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onBrowse});

  /// Opens a catalogue page from a section's View all.
  final ValueChanged<String>? onBrowse;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  _HomeData(this.documents, this.visuals);
  final Map<String, Object?> documents;
  final CatalogVisuals visuals;

  List<Entry> rows(String resource, [String? key]) {
    final value = documents[resource];
    final source = key == null ? value : (value as Map?)?[key];
    return switch (source) {
      List() => source.whereType<Entry>().toList(),
      Map() => [
        for (final MapEntry(:key, :value) in source.entries)
          if (value is Entry) {'_key': key, ...value},
      ],
      _ => const [],
    };
  }
}

class _HomeScreenState extends State<HomeScreen> {
  Future<_HomeData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_HomeData> _load() async {
    final api = AppScope.of(context).api;
    const keys = ['home-banners', 'events', 'songs', 'cards', 'support-cards'];
    final results = await Future.wait([
      for (final key in keys)
        api.catalog(key).then<Object?>((v) => v, onError: (_) => null),
    ]);
    return _HomeData({
      for (final (i, key) in keys.indexed) key: results[i],
    }, await CatalogVisuals.of(api));
  }

  void _open(BuildContext context, String resource, Entry item) {
    final profile = _profile(resource);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          profile: profile,
          id: '${firstOf(item, profile.id) ?? item['_key']}',
          summary: item,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    return ShellPage(
      title: t('home.dashboard.overview', 'Home'),
      body: FutureBuilder(
        future: _data,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return snapshot.hasError
                ? Center(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Symbols.refresh_rounded),
                      label: Text(t('common.actions.retry', 'Retry')),
                      onPressed: () => setState(() => _data = _load()),
                    ),
                  )
                : const Center(child: CircularProgressIndicator());
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          final banners =
              [
                for (final b in data.rows('home-banners', 'entries'))
                  if (b['image'] is String &&
                      ((RelativeTime.timestamp(b['endAt']) ??
                              double.infinity) >=
                          now))
                    b,
              ]..sort(
                (a, b) =>
                    (RelativeTime.timestamp(a['endAt']) ?? double.infinity)
                        .compareTo(
                          RelativeTime.timestamp(b['endAt']) ?? double.infinity,
                        ),
              );
          final events = [
            for (final e in data.rows('events', 'entries'))
              if ((RelativeTime.timestamp(e['endAt']) ?? double.infinity) >=
                  now)
                e,
          ];
          String artist(Entry song) => [
            for (final id in (song['bandIds'] as List? ?? const []))
              t.text(data.visuals.bands[(id as num).toInt()]?['bandName']),
          ].where((n) => n.isNotEmpty).join(', ');
          final songKit = CatalogKit(
            _profile('songs'),
            t,
            state.api,
            data.visuals,
            songTitles: state.songTitle,
          );
          final songs = data.rows('songs')
            ..sort(
              (a, b) => (songKit.releasedAt(b) ?? 0).compareTo(
                songKit.releasedAt(a) ?? 0,
              ),
            );
          final cardKit = CatalogKit(
            _profile('cards'),
            t,
            state.api,
            data.visuals,
          );
          final snapKit = CatalogKit(
            _profile('support-cards'),
            t,
            state.api,
            data.visuals,
          );
          final cards =
              [
                for (final c in data.rows('cards')) (c, cardKit, 'cards'),
                for (final c in data.rows('support-cards'))
                  (c, snapKit, 'support-cards'),
              ]..sort(
                (a, b) => (a.$2.releasedAt(b.$1) ?? 0).compareTo(
                  a.$2.releasedAt(a.$1) ?? 0,
                ),
              );
          final padding = pagePadding(context);
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _data = _load());
              await _data;
            },
            child: ListView(
              padding: padding.add(
                EdgeInsets.symmetric(
                  horizontal: ((MediaQuery.sizeOf(context).width - 1100) / 2)
                      .clamp(0, double.infinity),
                ),
              ),
              children: [
                if (banners.isNotEmpty)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: _Carousel(banners: banners, t: t, api: state.api),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      for (final event in events.take(2))
                        _EventCard(
                          event: event,
                          t: t,
                          api: state.api,
                          onOpen: () => _open(context, 'events', event),
                        ),
                    ];
                    final birthdays = _Birthdays(
                      visuals: data.visuals,
                      t: t,
                      api: state.api,
                    );
                    if (constraints.maxWidth < 900) {
                      return Column(children: [...cards, birthdays]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(children: cards)),
                        const SizedBox(width: 12),
                        Expanded(child: birthdays),
                      ],
                    );
                  },
                ),
                _Module(
                  icon: Symbols.library_music_rounded,
                  title: t('home.dashboard.latestSongs', 'Latest songs'),
                  viewAll: t('home.dashboard.viewAll', 'View all'),
                  onViewAll: () => widget.onBrowse?.call('/catalog/songs'),
                  child: _Rail(
                    width: 148,
                    aspectRatio: 1,
                    children: [
                      for (final song in songs.take(12))
                        Tile(
                          title: songKit.title(song),
                          subtitle: artist(song),
                          adornments: [
                            for (final id
                                in (song['bandIds'] as List? ?? const []))
                              ?data.visuals.bandLogo(id),
                          ],
                          images: songKit.images(song),
                          placeholder: Symbols.album_rounded,
                          marks: [
                            if (data.visuals.musicTypeMark(song['musicType'])
                                case final m?)
                              TileMark.image(MarkAt.start, m),
                            if (t.release(song['publishedAt']) case final r
                                when r.isNotEmpty)
                              TileMark.text(MarkAt.bottomStart, r),
                          ],
                          onTap: () => _open(context, 'songs', song),
                        ),
                    ],
                  ),
                ),
                _Module(
                  icon: Symbols.style_rounded,
                  title: t('home.dashboard.latestCards', 'Latest cards'),
                  viewAll: t('home.dashboard.viewAll', 'View all'),
                  onViewAll: () =>
                      widget.onBrowse?.call('/catalog/member-cards'),
                  child: _Rail(
                    width: 132,
                    aspectRatio: 3 / 4,
                    children: [
                      for (final (card, kit, resource) in cards.take(12))
                        Tile(
                          title: kit.title(card),
                          subtitle: kit.subtitle(card),
                          adornments: kit.adornments(card),
                          images: kit.images(card),
                          aspectRatio: 3 / 4,
                          fit: resource == 'cards'
                              ? BoxFit.contain
                              : BoxFit.cover,
                          marks: kit.marks(card),
                          onTap: () => _open(context, resource, card),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A home module: the section heading with View all, then its content.
class _Module extends StatelessWidget {
  const _Module({
    required this.icon,
    required this.title,
    required this.child,
    this.viewAll,
    this.onViewAll,
  });
  final IconData icon;
  final String title;
  final String? viewAll;
  final VoidCallback? onViewAll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Corner.extraLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(
                    icon,
                    size: 20,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
                if (onViewAll != null)
                  IconButton(
                    tooltip: viewAll,
                    onPressed: onViewAll,
                    icon: const Icon(Symbols.arrow_forward_rounded),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// A horizontal filmstrip of tiles.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.width,
    required this.aspectRatio,
    required this.children,
  });
  final double width;
  final double aspectRatio;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < ShellMetrics.compact;
    final height =
        width / aspectRatio + (compact ? 24 : 32) + 48 + (compact ? 4 : 8) + 20;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) =>
            SizedBox(width: width, child: children[index]),
      ),
    );
  }
}

/// The banners the game is showing now, advancing on their own.
class _Carousel extends StatefulWidget {
  const _Carousel({required this.banners, required this.t, required this.api});
  final List<Entry> banners;
  final SiteText t;
  final HaneokaApi api;
  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  final _pages = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_pages.hasClients || widget.banners.length < 2) return;
      _pages.animateToPage(
        (_index + 1) % widget.banners.length,
        duration: Durations.long2,
        curve: Easing.emphasizedDecelerate,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Corner.extraLarge),
          child: AspectRatio(
            aspectRatio: 1200 / 520,
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.banners.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) {
                final banner = widget.banners[index];
                final window = widget.t.window(
                  banner['startAt'],
                  banner['endAt'],
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AppImage(
                      candidates: [
                        widget.api.asset(banner['image'] as String).toString(),
                      ],
                      fit: BoxFit.cover,
                    ),
                    if (window.isNotEmpty)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(Corner.small),
                          ),
                          child: Text(
                            window,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        if (widget.banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.banners.length; i++)
                  AnimatedContainer(
                    duration: Durations.medium2,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The current event (`homeEventDisplay`): square artwork carrying the kind
/// and the time left, the title and how much of the event has passed.
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.t,
    required this.api,
    this.onOpen,
  });
  final Entry event;
  final SiteText t;
  final HaneokaApi api;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final image = event['image'];
    final window = t.window(event['startAt'], event['endAt']);
    final start = RelativeTime.timestamp(event['startAt']);
    final end = RelativeTime.timestamp(event['endAt']);
    final now = DateTime.now().millisecondsSinceEpoch;
    final progress = start != null && end != null && end > start
        ? ((now - start) / (end - start)).clamp(0.0, 1.0)
        : null;
    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(Corner.small),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Corner.extraLarge),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Corner.large),
                  child: SizedBox.square(
                    dimension: 144,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (image is String)
                          AppImage(
                            candidates: [api.asset(image).toString()],
                            fit: BoxFit.cover,
                          ),
                        Positioned(
                          left: 8,
                          top: 8,
                          child: chip(t.label('game-event', 'Event')),
                        ),
                        if (window.isNotEmpty)
                          Positioned(left: 8, bottom: 8, child: chip(window)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        t.text(event['title']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (progress != null)
                        LinearProgressIndicator(
                          value: progress,
                          borderRadius: BorderRadius.circular(Corner.full),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The next birthdays, nearest first.
class _Birthdays extends StatelessWidget {
  const _Birthdays({required this.visuals, required this.t, required this.api});
  final CatalogVisuals visuals;
  final SiteText t;
  final HaneokaApi api;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    int daysUntil(Map birthday) {
      var next = DateTime(
        today.year,
        birthday['month'] as int,
        birthday['day'] as int,
      );
      if (next.isBefore(start)) {
        next = DateTime(
          today.year + 1,
          birthday['month'] as int,
          birthday['day'] as int,
        );
      }
      return next.difference(start).inDays;
    }

    final upcoming = [
      for (final c in visuals.characters.values)
        if (c['birthday'] case final Map b
            when b['month'] is int && b['day'] is int)
          (c, daysUntil(b)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final (first, days) = upcoming.first;
    final face = first['faceImage'];
    return _Module(
      icon: Symbols.cake_rounded,
      title: t('home.dashboard.birthdaysTitle', 'Birthdays'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (face is String)
                ClipRRect(
                  borderRadius: BorderRadius.circular(Corner.large),
                  child: SizedBox.square(
                    dimension: 72,
                    child: AppImage(candidates: [api.asset(face).toString()]),
                  ),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.text(first['characterName']),
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      days == 0
                          ? t(
                              'home.dashboard.birthdayGreeting',
                              'Happy birthday',
                            )
                          : t('home.dashboard.daysAway', '{count}', {
                              'count': days,
                            }),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: upcoming.length.clamp(0, 12) - 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final (character, days) = upcoming[index + 1];
                final face = character['faceImage'];
                return Column(
                  children: [
                    ClipOval(
                      child: SizedBox.square(
                        dimension: 36,
                        child: face is String
                            ? AppImage(candidates: [api.asset(face).toString()])
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('home.dashboard.daysAwayOne', '{count}', {
                        'count': days,
                      }),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
