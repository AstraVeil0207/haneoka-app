import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../catalog/browse.dart';
import '../catalog/visuals.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/detail.dart';
import '../ui/tile.dart';

/// `modelTitle`: the source path's last part without `_SkeletonData`.
String spineTitle(Entry model) {
  final source = '${model['sourcePathKey'] ?? model['id'] ?? ''}'
      .split('/')
      .last;
  final title = source.replaceFirst(
    RegExp(r'_SkeletonData(?:\.asset)?$', caseSensitive: false),
    '',
  );
  return title.isEmpty ? '${model['id'] ?? model['_key']}' : title;
}

String _family(SiteText t, Object? value) => switch ('${value ?? ''}') {
  'home-spot' => t('media.spine.families.homeSpot', 'Home spot'),
  '' => '—',
  final other => other,
};

/// The release's Spine models (`spine-workspace` collection): each
/// model's rendered setup pose, its family and animations.
class SpineScreen extends StatefulWidget {
  const SpineScreen({super.key});
  @override
  State<SpineScreen> createState() => _SpineScreenState();
}

class _SpineScreenState extends State<SpineScreen> {
  Future<List<Entry>>? _models;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _models ??= _load();
  }

  Future<List<Entry>> _load() async {
    final document = await AppScope.of(context).api.catalog('spine');
    final data = (document as Map?) ?? const {};
    final models = (data['models'] as Map?) ?? const {};
    final order = [
      for (final id in data['modelOrder'] as List? ?? models.keys.toList())
        '$id',
    ];
    return [
      for (final id in order)
        if (models[id] case final Map model)
          {'_key': id, ...model.cast<String, Object?>()},
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    String? preview(Entry model) => switch ((model['preview']
        as Map?)?['url']) {
      final String url when url.isNotEmpty => state.api.asset(url).toString(),
      _ => null,
    };
    void open(Entry model) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpineModelScreen(model: model, preview: preview(model)),
      ),
    );
    return FutureBuilder(
      future: _models,
      builder: (context, snapshot) => BrowseScreen(
        title: t('navigation.spine', 'Spine'),
        items: snapshot.data,
        error: snapshot.error,
        onRetry: () => setState(() => _models = _load()),
        searchText: (m) =>
            '${m['id'] ?? m['_key']} ${m['sourcePathKey'] ?? ''} ${m['family'] ?? ''}',
        // `spine-workspace` sorts: order (the id), model, family and
        // version, ascending.
        itemId: (model) => '${model['id'] ?? ''}',
        descending: false,
        sorts: [
          SortSpec(
            'id',
            t('common.layout.order', 'Order'),
            (model) => '${model['id'] ?? ''}',
          ),
          SortSpec(
            'source',
            t('media.models.labels.model', 'Model'),
            spineTitle,
          ),
          SortSpec(
            'family',
            t('media.models.labels.family', 'Category'),
            (model) => '${model['family'] ?? ''}',
          ),
          SortSpec(
            'version',
            t('media.models.labels.version', 'Version'),
            (model) => '${model['spineVersion'] ?? ''}',
          ),
        ],
        grid: const GridSpec(minWidth: 160),
        tile: (context, model) => Tile(
          title: spineTitle(model),
          subtitle: _family(t, model['family']),
          images: [?preview(model)],
          aspectRatio: 1,
          fit: BoxFit.contain,
          placeholder: Symbols.link_rounded,
          onTap: () => open(model),
        ),
        listRow: (context, model) => ListTile(
          onTap: () => open(model),
          leading: SizedBox.square(
            dimension: 48,
            child: preview(model) == null
                ? null
                : AppImage(candidates: [preview(model)!], fit: BoxFit.contain),
          ),
          title: Text(spineTitle(model)),
          subtitle: Text(_family(t, model['family'])),
        ),
        columns: [
          TableColumn(t.label('title'), spineTitle),
          TableColumn(
            t('media.models.labels.family', 'Category'),
            (m) => _family(t, m['family']),
          ),
          TableColumn(
            t('media.models.labels.animations', 'Animations'),
            (m) =>
                '${m['animationCount'] ?? (m['animations'] as List?)?.length ?? 0}',
            numeric: true,
          ),
        ],
        facets: [
          FacetSpec(
            key: 'family',
            label: t('media.models.labels.family', 'Category'),
            values: (m) => ['${m['family'] ?? ''}'],
            option: (value) => FacetOption(_family(t, value)),
          ),
        ],
      ),
    );
  }
}

/// One Spine model: its setup-pose preview and animations.
class SpineModelScreen extends StatelessWidget {
  const SpineModelScreen({super.key, required this.model, this.preview});
  final Entry model;
  final String? preview;
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    final theme = Theme.of(context);
    final animations = [
      for (final a in model['animations'] as List? ?? const []) '$a',
    ];
    return ShellPage(
      title: spineTitle(model),
      body: DetailLayout(
        media: preview == null
            ? null
            : ImageGallery(images: [preview!], aspectRatio: 1),
        sections: [
          DetailSection(
            title: t('catalog.labels.details', 'Details'),
            icon: Symbols.info_rounded,
            child: SpecList(
              facts: [
                Fact(
                  t('media.models.labels.family', 'Category'),
                  _family(t, model['family']),
                ),
                if (model['spineVersion'] != null)
                  Fact(
                    t('media.models.labels.version', 'Version'),
                    '${model['spineVersion']}',
                  ),
                Fact(
                  t('media.models.labels.animations', 'Animations'),
                  '${animations.length}',
                ),
              ],
            ),
          ),
          if (animations.isNotEmpty)
            DetailFold(
              title: t('media.models.labels.animations', 'Animations'),
              meta: '${animations.length}',
              open: true,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in animations)
                    Chip(label: Text(name, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
