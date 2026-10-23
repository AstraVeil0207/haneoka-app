import '../core/catalog_source.dart';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../catalog/browse.dart';
import '../catalog/cross_server.dart';
import '../catalog/visuals.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../ui/app_image.dart';
import '../ui/tile.dart';
import 'spine_viewer.dart';
import 'model_catalog.dart';

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
  Object? _dataKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = CatalogSourceScope.keyOf(context);
    if (_dataKey != key) { _dataKey = key; _models = _load(); }
  }

  Future<List<Entry>> _load() async {
    return crossServerCollection(resource: 'spine', selected: CatalogSourceScope.serverOf(context),
      apis: CatalogSourceScope.apisOf(context), rowsPath: 'models');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    String? preview(Entry model) =>
        switch ((model['preview'] as Map?)?['url']) {
          final String url when url.isNotEmpty => CatalogSourceScope.apiOf(
            context,
          ).asset(url).toString(),
          _ => null,
        };
    final apis = CatalogSourceScope.apisOf(context), current = CatalogSourceScope.serverOf(context);
    apiFor(Entry row) => apis['${row[serverKey] ?? current}']!;
    void open(Entry model) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogSourceScope(
          api: apiFor(model),
          child: SpineModelScreen(model: model, preview: preview(model)),
        ),
      ),
    );
    return FutureBuilder(
      future: _models,
      builder: (context, snapshot) => BrowseScreen(
        sourcePath: '/catalog/spine',
        onOpen: (context, model) => open(model),
        title: t('navigation.spine', 'Spine'),
        items: snapshot.data,
        error: snapshot.error,
        onRetry: () => setState(() => _models = _load()),
        searchText: (m) =>
            '${m['id'] ?? m['_key']} ${m['sourcePathKey'] ?? ''} ${m['family'] ?? ''} ${m['animations'] ?? ''}',
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
          serverMark: serverMark(model, (key, fallback) => t(key, fallback)),
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
          TableColumn(t('media.models.labels.version'), (model) => '${model['spineVersion'] ?? ''}'),
        ],
        facets: [
          FacetSpec(
            key: 'family',
            label: t('media.models.labels.family', 'Category'),
            values: (m) => ['${m['family'] ?? ''}'],
            option: (value) => FacetOption(_family(t, value)),
          ),
          FacetSpec(key: 'version', label: t('media.models.labels.version'),
            values: (model) => ['${model['spineVersion'] ?? ''}'], option: (value) => FacetOption(value)),
          ...modelMetadataFacets(snapshot.data ?? const [], t),
        ],
      ),
    );
  }
}

/// The native model viewer also accepts direct entity routes.
class SpineModelScreen extends StatelessWidget {
  const SpineModelScreen({super.key, required this.model, this.preview});
  final Entry model;
  final String? preview;
  @override
  Widget build(BuildContext context) {
    return NativeSpineViewer(
      id: '${model['id'] ?? model['_key']}',
      title: spineTitle(model),
    );
  }
}
