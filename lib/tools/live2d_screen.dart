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
import 'live2d_viewer.dart';
import 'model_catalog.dart';

/// `modelTitle`: the model's title, its Live2D name, then its key.
String _title(SiteText t, Entry model) {
  for (final value in [
    model['title'],
    model['live2dName'],
    model['characterName'],
    model['live2dKey'],
  ]) {
    final text = t.text(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// `subCharacterLabel`: `sub_lab_staff` → `Lab Staff`.
String _subCharacter(String key) => key
    .replaceFirst(RegExp('^sub_'), '')
    .split('_')
    .where((p) => p.isNotEmpty)
    .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
    .join(' ');

/// The release's Live2D models (`live2d-workspace` collection): each
/// model's rendered preview, by character, band and type.
class Live2DScreen extends StatefulWidget {
  const Live2DScreen({super.key});
  @override
  State<Live2DScreen> createState() => _Live2DScreenState();
}

class _Live2DScreenState extends State<Live2DScreen> {
  Future<(List<Entry>, List<CatalogVisuals>)>? _data;
  Object? _dataKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = CatalogSourceScope.keyOf(context);
    if (_dataKey != key) { _dataKey = key; _data = _load(); }
  }

  Future<(List<Entry>, List<CatalogVisuals>)> _load() async {
    final apis = CatalogSourceScope.apisOf(context), selected = CatalogSourceScope.serverOf(context);
    final visuals = <CatalogVisuals>[];
    final (models, _) = await (crossServerCollection(resource: 'live2d', selected: selected, apis: apis, rowsPath: null),
      Future.wait([for (final api in apis.values) () async {
        try { visuals.add(await CatalogVisuals.of(api)); } catch (_) {}
      }()])).wait;
    visuals.sort((a, b) => (a.api.server == selected ? 0 : 1).compareTo(b.api.server == selected ? 0 : 1));
    return (models, visuals);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final apis = CatalogSourceScope.apisOf(context), current = CatalogSourceScope.serverOf(context);
    apiFor(Entry row) => apis['${row[serverKey] ?? current}']!;
    String label(String key, String fallback) =>
        t('media.models.labels.$key', fallback);
    String subtitle(Entry model) {
      final name = t.text(model['characterName']);
      if (name.isNotEmpty) return name;
      final sub = _subCharacter('${model['characterKey'] ?? ''}');
      return sub.isNotEmpty ? sub : '${model['live2dKey'] ?? ''}';
    }

    String? preview(Entry model) {
      final runtime =
          (model['preview'] as Map?)?['runtime'] ?? model['thumbnailImage'];
      return runtime is String && runtime.isNotEmpty
          ? apiFor(model).asset(runtime).toString()
          : null;
    }

    String? face(Entry model) => model['faceImage'] is String
        ? apiFor(model).asset(model['faceImage'] as String).toString()
        : null;
    void open(Entry model) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogSourceScope(
          api: apiFor(model),
          child: Live2DModelScreen(model: model),
        ),
      ),
    );
    String type(Entry model) =>
        model['modelType'] == 'live' || model['mode'] == 'live'
        ? t('media.models.types.live2dTypeLive', 'Live')
        : t('media.models.types.live2dTypeAdv', 'ADV');
    return FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final sources = data?.$2 ?? const <CatalogVisuals>[];
        Entry? character(int? id) => sources.map((v) => v.characters[id]).whereType<Entry>().firstOrNull;
        Entry? band(int? id) => sources.map((v) => v.bands[id]).whereType<Entry>().firstOrNull;
        String? bandIcon(int? id) => sources.where((v) => v.bands.containsKey(id)).firstOrNull?.bandIcon(id);
        return BrowseScreen(
          sourcePath: '/catalog/live2d',
          onOpen: (context, model) => open(model),
          title: t('navigation.live2d', 'Live2D'),
          items: data?.$1,
          error: snapshot.error,
          onRetry: () => setState(() => _data = _load()),
          searchText: (model) => [
            _title(t, model),
            subtitle(model),
            '${model['live2dKey'] ?? ''}',
            t.text(band((model['bandId'] as num?)?.toInt())?['bandName']),
          ].join(' '),
          // `live2d-workspace` sorts: order (the model key), title, type,
          // character and band, ascending.
          itemId: (model) => '${model['live2dKey'] ?? model['assetId'] ?? ''}',
          descending: false,
          sorts: [
            SortSpec(
              'id',
              t('common.layout.order', 'Order'),
              (model) => '${model['live2dKey'] ?? model['assetId'] ?? ''}',
            ),
            SortSpec(
              'title',
              t('common.fields.title', 'Title'),
              (model) => _title(t, model),
            ),
            SortSpec(
              'type',
              t('catalog.fields.type', 'Type'),
              (model) => '${model['modelType'] ?? ''}',
            ),
            SortSpec(
              'character',
              t('catalog.fields.character', 'Character'),
              (model) => model['characterId'] ?? 0,
            ),
            SortSpec(
              'band',
              t('catalog.fields.band', 'Band'),
              (model) => model['bandId'] ?? 0,
            ),
          ],
          grid: const GridSpec(minWidth: 160),
          tile: (context, model) => Tile(
            title: _title(t, model),
            subtitle: subtitle(model),
            adornments: [?face(model)],
            images: [?preview(model)],
            aspectRatio: 1,
            // `.tile--model`: cover, anchored at the top (the face).
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            placeholder: Symbols.animation_rounded,
            serverMark: serverMark(model, (key, fallback) => t(key, fallback)),
            onTap: () => open(model),
          ),
          listRow: (context, model) => ListTile(
            onTap: () => open(model),
            leading: SizedBox.square(
              dimension: 48,
              child: preview(model) == null
                  ? null
                  : AppImage(candidates: [preview(model)!], fit: BoxFit.cover),
            ),
            title: Text(_title(t, model)),
            subtitle: Text(subtitle(model)),
          ),
          columns: [
            TableColumn(t.label('title'), (m) => _title(t, m)),
            TableColumn(t.label('character'), subtitle),
            TableColumn(label('model', 'Model'), type),
          ],
          facets: [
                  FacetSpec(
                    key: 'character',
                    label: t.label('character'),
                    values: (m) => ['${m['characterId'] ?? ''}'],
                    option: (value) {
                      final person = character(int.tryParse(value));
                      final image = person?['faceImage'];
                      return FacetOption(
                        t.text(person?['characterName']).isEmpty
                            ? value
                            : t.text(person?['characterName']),
                        image: image is String
                            ? CatalogSourceScope.apiOf(context).asset(image).toString()
                            : null,
                      );
                    },
                  ),
                  FacetSpec(
                    key: 'band',
                    label: t.label('band'),
                    values: (m) => [if (m['bandId'] != null) '${m['bandId']}'],
                    option: (value) => FacetOption(
                      t.text(band(int.tryParse(value))?['bandName']),
                      image: bandIcon(int.tryParse(value)),
                    ),
                  ),
                  FacetSpec(
                    key: 'type',
                    label: label('model', 'Model'),
                    values: (m) => [type(m)],
                    option: FacetOption.new,
                  ),
                  ...modelMetadataFacets(data?.$1 ?? const [], t),
                ],
        );
      },
    );
  }
}

class Live2DModelScreen extends StatelessWidget {
  const Live2DModelScreen({super.key, required this.model});
  final Entry model;
  @override
  Widget build(BuildContext context) => NativeLive2DViewer(
    id: '${model['live2dKey'] ?? model['_key']}',
    title: _title(AppScope.of(context).text, model),
  );
}
