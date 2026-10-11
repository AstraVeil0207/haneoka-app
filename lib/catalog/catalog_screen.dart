import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../shell/page.dart';
import '../ui/theme.dart';
import 'detail_screen.dart';
import 'format.dart';
import 'profiles.dart';

/// A catalogue resource as the website browses it: search in the bar, the
/// count and order beside it, tiles in the pane.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.profile});
  final CatalogProfile profile;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  Future<List<Map<String, Object?>>>? _items;
  String _query = '';
  late bool _newestFirst = widget.profile.newestFirst;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items ??= _load();
  }

  Future<List<Map<String, Object?>>> _load() async {
    final document = await AppScope.of(context).api
        .catalog(widget.profile.resource);
    final source = widget.profile.document == null
        ? document
        : readPath(document, widget.profile.document!);
    return switch (source) {
      List() => source.whereType<Map<String, Object?>>().toList(),
      Map() => [
        for (final entry in source.entries)
          if (entry.value is Map<String, Object?>)
            {'_key': entry.key, ...entry.value as Map<String, Object?>},
      ],
      _ => <Map<String, Object?>>[],
    };
  }

  String _id(Map<String, Object?> item) =>
      '${firstOf(item, widget.profile.id) ?? item['_key']}';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final profile = widget.profile;
    final theme = Theme.of(context);
    return FutureBuilder(
      future: _items,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Map<String, Object?>>[];
        final query = _query.toLowerCase();
        final items =
            all
                .where(
                  (item) =>
                      query.isEmpty ||
                      t
                          .text(firstOf(item, profile.title))
                          .toLowerCase()
                          .contains(query) ||
                      _id(item).contains(query),
                )
                .toList()
              ..sort((a, b) {
                final x = num.tryParse(_id(a)) ?? 0,
                    y = num.tryParse(_id(b)) ?? 0;
                return _newestFirst ? y.compareTo(x) : x.compareTo(y);
              });
        final number = NumberFormat.decimalPattern(t.locale);
        return ShellPage(
          title: t(profile.label, profile.resource),
          search: ShellSearch(
            label: t('common.actions.search', 'Search'),
            onChanged: (value) => setState(() => _query = value),
          ),
          status: snapshot.hasData
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      number.format(items.length),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                )
              : null,
          actions: [
            BarAction(
              icon: _newestFirst ? Icons.arrow_downward : Icons.arrow_upward,
              label: t('common.actions.sort', 'Sort'),
              onPressed: () => setState(() => _newestFirst = !_newestFirst),
            ),
          ],
          body: snapshot.hasError
              ? Center(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.refresh),
                    label: Text(t('common.actions.retry', 'Retry')),
                    onPressed: () => setState(() => _items = _load()),
                  ),
                )
              : !snapshot.hasData
              ? const Center(child: CircularProgressIndicator())
              : _grid(context, items),
        );
      },
    );
  }

  Widget _grid(BuildContext context, List<Map<String, Object?>> items) {
    final state = AppScope.of(context);
    final t = state.text;
    final profile = widget.profile;
    final format = ValueFormat(t);
    final theme = Theme.of(context);
    final (extent, ratio) = switch (profile.layout) {
      TileLayout.wide => (360.0, 16 / 9),
      TileLayout.portrait => (200.0, 3 / 4),
      TileLayout.square => (184.0, 1.0),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth < ShellMetrics.compact
            ? 12.0
            : 24.0;
        return GridView.builder(
          padding: EdgeInsets.all(gutter),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: extent,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // Artwork box plus the two-line identity below it.
            mainAxisExtent: extent / ratio * 0.92 + 72,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final image = firstOf(item, profile.image);
            final subtitle = profile.detail
                .map((key) => format.format(key, readPath(item, key)))
                .firstWhere((s) => s.isNotEmpty, orElse: () => '');
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DetailScreen(
                      profile: profile,
                      id: _id(item),
                      summary: item,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: image is String
                          ? CachedNetworkImage(
                              imageUrl: state.api.asset(image).toString(),
                              fit: profile.layout == TileLayout.wide
                                  ? BoxFit.cover
                                  : BoxFit.contain,
                              fadeInDuration: const Duration(milliseconds: 150),
                              placeholder: (_, _) => ColoredBox(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                              errorWidget: (_, _, _) => Icon(
                                profile.icon,
                                color: theme.colorScheme.outline,
                              ),
                            )
                          : ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                profile.icon,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.text(firstOf(item, profile.title)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
