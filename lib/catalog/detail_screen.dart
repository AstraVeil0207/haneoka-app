import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import '../l10n/app_localizations.dart';
import '../shell/page.dart';
import '../ui/theme.dart';
import 'format.dart';
import 'profiles.dart';

/// One entity, laid out as the website's detail: artwork on one side, the
/// profile's facts and every other field in sections on the other.
class DetailScreen extends StatelessWidget {
  const DetailScreen({
    super.key,
    required this.profile,
    required this.id,
    required this.summary,
  });
  final CatalogProfile profile;
  final String id;
  final Map<String, Object?> summary;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final detail = state.api
        .catalog(profile.resource, id)
        .then<Map<String, Object?>>(
          (value) => {...summary, if (value is Map<String, Object?>) ...value},
          onError: (_) => summary,
        );
    final title = firstOf(summary, profile.title);
    return ShellPage(
      title: t.text(title),
      body: FutureBuilder(
        future: detail,
        builder: (context, snapshot) {
          final record = snapshot.data ?? summary;
          final format = ValueFormat(t);
          final images = imagesIn(record).toSet().toList();
          final keys = [
            ...profile.detail.where((key) => readPath(record, key) != null),
            ...record.keys.where(
              (key) => !key.startsWith('_') && !profile.detail.contains(key),
            ),
          ];
          final scalars = [
            for (final key in keys)
              if (ValueFormat.isScalar(readPath(record, key)))
                if (format.format(key, readPath(record, key)) case final value
                    when value.isNotEmpty && !value.startsWith('/assets/'))
                  (key, value),
          ];
          // Facts the website names; the rest stays reachable under All fields.
          final facts = [
            for (final (key, value) in scalars)
              if (_named(t, key) != null) (_named(t, key)!, value),
          ];
          final other = [
            for (final (key, value) in scalars)
              if (_named(t, key) == null) (key, value),
          ];
          final groups = [
            for (final key in keys)
              if (!ValueFormat.isScalar(readPath(record, key)) &&
                  readPath(record, key) != null &&
                  imagesIn(readPath(record, key)).length !=
                      _size(readPath(record, key)))
                key,
          ];
          final media = images.isEmpty
              ? null
              : _Gallery(images: images, state: state);
          final sections = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(
                icon: Icons.info_outline,
                title: t('common.actions.details', 'Details'),
                child: _SpecList(facts: facts),
              ),
              for (final key in groups)
                _Section(
                  icon: Icons.list_alt,
                  title: _label(t, key),
                  folded: true,
                  child: _Nested(value: readPath(record, key), format: format),
                ),
              if (other.isNotEmpty)
                _Section(
                  icon: Icons.data_object,
                  title: AppLocalizations.of(context).allFields,
                  folded: true,
                  child: _SpecList(facts: other),
                ),
            ],
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 840;
              final gutter = constraints.maxWidth < ShellMetrics.compact
                  ? 16.0
                  : 24.0;
              final progress = snapshot.connectionState != ConnectionState.done
                  ? const LinearProgressIndicator()
                  : const SizedBox(height: 4);
              if (wide && media != null) {
                return Column(
                  children: [
                    progress,
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(gutter),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: (constraints.maxWidth * 0.36).clamp(
                                280,
                                420,
                              ),
                              child: media,
                            ),
                            SizedBox(width: gutter),
                            Expanded(child: sections),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  progress,
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.all(gutter),
                      children: [
                        if (media != null) ...[media, SizedBox(height: gutter)],
                        sections,
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static int _size(Object? value) => value is Map
      ? value.length
      : value is List
      ? value.length
      : 1;

  /// The website's label for a field, or null when it does not name it.
  static String? _named(SiteText t, String key) {
    for (final path in [
      'catalog.fields.$key',
      'catalog.songs.fields.$key',
      'catalog.cards.fields.$key',
      'catalog.characters.fields.$key',
      'common.fields.$key',
    ]) {
      final label = t(path);
      if (label.isNotEmpty) return label;
    }
    return null;
  }

  static String _label(SiteText t, String key) => _named(t, key) ?? key;
}

/// The detail's artwork in an outlined card, one image at a time.
class _Gallery extends StatefulWidget {
  const _Gallery({required this.images, required this.state});
  final List<String> images;
  final AppState state;
  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _index = 0;
  final _pages = PageController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(Corner.extraLarge),
      ),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: PageView(
              controller: _pages,
              onPageChanged: (index) => setState(() => _index = index),
              children: [
                for (final image in widget.images)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: CachedNetworkImage(
                      imageUrl: widget.state.api.asset(image).toString(),
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.images.length > 1) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Row(
              children: [
                IconButton(
                  onPressed: _index == 0
                      ? null
                      : () => _pages.previousPage(
                          duration: Durations.medium2,
                          curve: Easing.standard,
                        ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${_index + 1} / ${widget.images.length}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  onPressed: _index == widget.images.length - 1
                      ? null
                      : () => _pages.nextPage(
                          duration: Durations.medium2,
                          curve: Easing.standard,
                        ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A detail section: the website's heading (icon in a tonal circle, title)
/// over its content; long groups fold.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.folded = false,
  });
  final IconData icon;
  final String title;
  final Widget child;
  final bool folded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Row(
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
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    if (folded) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          title: heading,
          children: [child],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [heading, const SizedBox(height: 16), child],
      ),
    );
  }
}

/// Facts as the website's spec list: label above value, two columns when wide.
class _SpecList extends StatelessWidget {
  const _SpecList({required this.facts});
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 24) / columns;
        return Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            for (final (label, value) in facts)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(value, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Nested extends StatelessWidget {
  const _Nested({required this.value, required this.format});
  final Object? value;
  final ValueFormat format;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value is Map) {
      return Column(
        children: [
          for (final entry in value.entries)
            if (ValueFormat.isScalar(entry.value))
              ListTile(
                dense: true,
                title: Text('${entry.key}'),
                trailing: Text(format.format('${entry.key}', entry.value)),
              )
            else if (entry.value != null)
              ExpansionTile(
                title: Text('${entry.key}'),
                children: [_Nested(value: entry.value, format: format)],
              ),
        ],
      );
    }
    if (value is List) {
      return Column(
        children: [
          for (final (index, item) in value.take(200).indexed)
            ValueFormat.isScalar(item)
                ? ListTile(dense: true, title: Text(format.format('', item)))
                : ExpansionTile(
                    title: Text('${index + 1}'),
                    children: [_Nested(value: item, format: format)],
                  ),
        ],
      );
    }
    return ListTile(dense: true, title: Text(format.format('', value)));
  }
}
