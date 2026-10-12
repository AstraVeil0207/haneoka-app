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
  Future<(List<Entry>, CatalogVisuals)>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<Entry>, CatalogVisuals)> _load() async {
    final api = AppScope.of(context).api;
    final (document, visuals) = await (
      api.catalog('live2d'),
      CatalogVisuals.of(api),
    ).wait;
    final rows = document is Map ? document : const {};
    return (
      [
        for (final MapEntry(:key, :value) in rows.entries)
          if (value is Entry) {'_key': '$key', ...value},
      ],
      visuals,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final api = state.api;
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
          ? api.asset(runtime).toString()
          : null;
    }

    String? face(Entry model) => model['faceImage'] is String
        ? api.asset(model['faceImage'] as String).toString()
        : null;
    void open(Entry model) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => Live2DModelScreen(model: model)),
    );
    String type(Entry model) =>
        model['modelType'] == 'live' || model['mode'] == 'live'
        ? t('media.models.types.live2dTypeLive', 'Live')
        : t('media.models.types.live2dTypeAdv', 'ADV');
    return FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final visuals = data?.$2;
        return BrowseScreen(
          onOpen: (context, model) => open(model),
          title: t('navigation.live2d', 'Live2D'),
          items: data?.$1,
          error: snapshot.error,
          onRetry: () => setState(() => _data = _load()),
          searchText: (model) => [
            _title(t, model),
            subtitle(model),
            '${model['live2dKey'] ?? ''}',
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
          facets: visuals == null
              ? const []
              : [
                  FacetSpec(
                    key: 'character',
                    label: t.label('character'),
                    values: (m) => ['${m['characterId'] ?? ''}'],
                    option: (value) {
                      final character = visuals.characters[int.tryParse(value)];
                      final image = character?['faceImage'];
                      return FacetOption(
                        t.text(character?['characterName']).isEmpty
                            ? value
                            : t.text(character?['characterName']),
                        image: image is String
                            ? api.asset(image).toString()
                            : null,
                      );
                    },
                  ),
                  FacetSpec(
                    key: 'band',
                    label: t.label('band'),
                    values: (m) => [if (m['bandId'] != null) '${m['bandId']}'],
                    option: (value) => FacetOption(
                      t.text(visuals.bands[int.tryParse(value)]?['bandName']),
                      image: visuals.bandIcon(int.tryParse(value)),
                    ),
                  ),
                  FacetSpec(
                    key: 'type',
                    label: label('model', 'Model'),
                    values: (m) => [type(m)],
                    option: FacetOption.new,
                  ),
                ],
        );
      },
    );
  }
}

/// One model: its rendered preview, what it is, and the motions and
/// expressions it carries.
class Live2DModelScreen extends StatefulWidget {
  const Live2DModelScreen({super.key, required this.model});
  final Entry model;
  @override
  State<Live2DModelScreen> createState() => _Live2DModelScreenState();
}

class _Live2DModelScreenState extends State<Live2DModelScreen> {
  Future<Object?>? _detail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detail ??= AppScope.of(context).api.catalog(
      'live2d',
      '${widget.model['live2dKey'] ?? widget.model['_key']}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final theme = Theme.of(context);
    String label(String key, String fallback) =>
        t('media.models.labels.$key', fallback);
    return FutureBuilder(
      future: _detail,
      builder: (context, snapshot) {
        final model = {
          ...widget.model,
          if (snapshot.data case final Map data)
            ...data.cast<String, Object?>(),
        };
        final preview = (model['preview'] as Map?)?['runtime'];
        final motions = [
          for (final m in model['motions'] as List? ?? const [])
            if (m is Map) '${m['name']}',
        ];
        final expressions = [
          for (final e in model['expressions'] as List? ?? const [])
            if (e is Map) '${e['name']}',
        ];
        Widget names(List<String> values) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in values)
              Chip(label: Text(name, style: theme.textTheme.bodySmall)),
          ],
        );
        return ShellPage(
          title: _title(t, model),
          body: DetailLayout(
            media: preview is String
                ? ImageGallery(
                    images: [state.api.asset(preview).toString()],
                    aspectRatio: 1,
                  )
                : null,
            sections: [
              DetailSection(
                title: t('catalog.labels.details', 'Details'),
                icon: Symbols.info_rounded,
                child: SpecList(
                  facts: [
                    Fact(t.label('character'), t.text(model['characterName'])),
                    Fact(
                      label('model', 'Model'),
                      '${model['live2dKey'] ?? ''}',
                    ),
                    Fact(
                      label('family', 'Category'),
                      model['modelType'] == 'live'
                          ? t('media.models.types.live2dTypeLive', 'Live')
                          : t('media.models.types.live2dTypeAdv', 'ADV'),
                    ),
                    if (model['quality'] != null)
                      Fact(
                        label('quality', 'Graphics quality'),
                        '${model['quality']}',
                      ),
                  ],
                ),
              ),
              if (motions.isNotEmpty)
                DetailFold(
                  title: label('motion', 'Motion'),
                  meta: '${motions.length}',
                  child: names(motions),
                ),
              if (expressions.isNotEmpty)
                DetailFold(
                  title: label('expression', 'Expression'),
                  meta: '${expressions.length}',
                  child: names(expressions),
                ),
            ],
          ),
        );
      },
    );
  }
}
