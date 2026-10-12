import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import '../shell/links.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/detail.dart';
import '../ui/tile.dart';

typedef Announcement = Map<String, Object?>;

String _date(SiteText t, Object? seconds, {bool full = false}) {
  if (seconds is! num) return '';
  final at = DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
  final format = DateFormat.yMMMd(t.locale);
  return (full ? format.add_Hm() : format).format(at);
}

String _category(SiteText t, Object? category) => t(
  'home.announcements.categories.$category',
  t('home.announcements.title', 'Announcements'),
);

/// The game's announcements for the release server, newest first
/// (`fetchAnnouncements`, `sortAnnouncements`).
Future<List<Announcement>> fetchAnnouncements(AppState state) async {
  final value = await state.api.live(
    '/api/v1/announcements?server=${state.server}&locale=${state.text.locale}',
  );
  final list = [
    for (final entry
        in ((value as Map?)?['announcements'] as List? ?? const []))
      if (entry is Announcement) entry,
  ];
  list.sort((a, b) {
    final pinned =
        (b['pinned'] == true ? 1 : 0) - (a['pinned'] == true ? 1 : 0);
    if (pinned != 0) return pinned;
    return ((b['startAt'] as num?) ?? 0).compareTo((a['startAt'] as num?) ?? 0);
  });
  return list;
}

/// One announcement in a list (`announcementRow`): banner, date and
/// category, then the title over three lines.
class AnnouncementRow extends StatelessWidget {
  const AnnouncementRow({super.key, required this.entry, this.compact = false});
  final Announcement entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final banner = entry['banner'];
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AnnouncementScreen(entry: entry),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 16,
          vertical: compact ? 6 : 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: compact ? 56 : 112,
                height: compact ? 32 : 64,
                color: scheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: banner is String
                    ? AppImage(
                        candidates: [banner],
                        fit: BoxFit.cover,
                        placeholder: Icon(
                          Symbols.campaign_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(
                        Symbols.campaign_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _date(t, entry['startAt']),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _category(t, entry['category']),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (entry['pinned'] == true)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Symbols.push_pin_rounded,
                              size: 16,
                              color: scheme.primary,
                            ),
                            Text(
                              t('home.announcements.pinned', 'Pinned'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry['title'] ?? ''}',
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: compact
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The announcements page (`announcement-feed`): every announcement for the
/// release server in a divided list.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  Future<List<Announcement>>? _entries;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entries ??= fetchAnnouncements(AppScope.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    return ShellPage(
      title: t('home.announcements.title', 'Announcements'),
      body: FutureBuilder(
        future: _entries,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.tonalIcon(
                icon: const Icon(Symbols.refresh_rounded),
                label: Text(t('home.announcements.retry', 'Retry')),
                onPressed: () => setState(
                  () => _entries = fetchAnnouncements(AppScope.of(context)),
                ),
              ),
            );
          }
          final entries = snapshot.data;
          if (entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (entries.isEmpty) {
            return Center(
              child: Text(
                t('home.announcements.empty', 'No announcements yet.'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              final next = fetchAnnouncements(AppScope.of(context));
              setState(() => _entries = next);
              await next;
            },
            child: ListView.separated(
              padding: pagePadding(context).copyWith(left: 0, right: 0),
              itemCount: entries.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) =>
                  AnnouncementRow(entry: entries[index]),
            ),
          );
        },
      ),
    );
  }
}

final _drop = [
  RegExp(r'<head[\s\S]*?</head>', caseSensitive: false),
  RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
  RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
];
final _colour = RegExp(r'\s(?:color|bgcolor)="[^"]*"', caseSensitive: false);

/// The announcement body without the game's own stylesheet, so its text
/// takes the app's colours (`announcementBodyFragment`).
String _body(String html) {
  var body = html;
  for (final pattern in _drop) {
    body = body.replaceAll(pattern, '');
  }
  return body.replaceAll(_colour, '');
}

/// One announcement (`announcement-detail`): category and date, then the
/// game's own body.
class AnnouncementScreen extends StatefulWidget {
  const AnnouncementScreen({super.key, required this.entry});
  final Announcement entry;
  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  Future<Object?>? _detail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    _detail ??= state.api.live(
      '/api/v1/announcements/${widget.entry['id']}?server=${state.server}&locale=${state.text.locale}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ShellPage(
      title: '${widget.entry['title'] ?? ''}',
      body: FutureBuilder(
        future: _detail,
        builder: (context, snapshot) {
          final entry = {
            ...widget.entry,
            ...?(snapshot.data as Map<String, Object?>?),
          };
          final html = entry['html'];
          final image = entry['bodyImage'];
          final body = html is String ? _body(html) : '';
          return ListView(
            padding: pagePadding(context),
            children: [
              DetailSection(
                icon: Symbols.info_rounded,
                title: t(
                  'home.announcements.information',
                  'Announcement information',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(label: Text(_category(t, entry['category']))),
                        if (entry['pinned'] == true)
                          Chip(
                            label: Text(
                              t('home.announcements.pinned', 'Pinned'),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SpecList(
                      facts: [
                        Fact(
                          t('home.announcements.published', 'Published'),
                          _date(t, entry['startAt'], full: true),
                        ),
                        if (entry['updatedAt'] is num &&
                            entry['updatedAt'] != entry['startAt'])
                          Fact(
                            t('home.announcements.updated', 'Updated'),
                            _date(t, entry['updatedAt'], full: true),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (image is String && !body.contains(image))
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio:
                          ((entry['bodyImageWidth'] as num?) ?? 420) /
                          ((entry['bodyImageHeight'] as num?) ?? 180),
                      child: AppImage(candidates: [image], fit: BoxFit.contain),
                    ),
                  ),
                ),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (body.trim().isEmpty)
                Text(
                  t(
                    'home.announcements.bodyUnavailable',
                    'The announcement content is unavailable.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                HtmlWidget(
                  body,
                  textStyle: theme.textTheme.bodyLarge,
                  // haneoka.org addresses open their native page.
                  onTapUrl: (url) => openLink(context, url),
                ),
            ],
          );
        },
      ),
    );
  }
}
