import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../core/relative_time.dart';
import '../ui/app_image.dart';
import '../ui/tile.dart';
import 'browse.dart';
import 'profiles.dart';
import 'visuals.dart';

const _rarities = {2: 'R', 3: 'SR', 4: 'SSR', 10: 'EX', 20: 'BD'};
const _attributes = ['', 'red', 'blue', 'green', 'yellow', 'purple'];

/// A catalogue resource as the website browses it (`catalog-screen`): the
/// profile's presentation decides each tile's subhead, emblems and marks,
/// and the filters it offers.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.profile,
    this.onOpen,
    this.owned,
    this.title,
  });
  final CatalogProfile profile;

  /// Only these entries (by id), each with a mark of the player's progress:
  /// a save's own cards, items or band items.
  final Map<String, String>? owned;
  final String? title;
  final void Function(BuildContext context, Entry item)? onOpen;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  Future<(List<Entry>, CatalogVisuals)>? _data;
  String? _band;
  List<Entry>? _railSource;
  String? _railBand;
  List<Entry> _railItems = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<Entry>, CatalogVisuals)> _load() async {
    final api = AppScope.of(context).api;
    final profile = widget.profile;
    final (document, visuals) = await (
      api.catalog(profile.resource),
      CatalogVisuals.of(api),
    ).wait;
    final source = profile.document == null
        ? document
        : readPath(document, profile.document!);
    final items = switch (source) {
      List() => source.whereType<Entry>().toList(),
      Map() => [
        for (final MapEntry(:key, :value) in source.entries)
          if (value is Entry) {'_key': key, ...value},
      ],
      _ => <Entry>[],
    };
    final owned = widget.owned;
    if (owned == null) return (items, visuals);
    final kit = CatalogKit(profile, AppScope.of(context).text, api, visuals);
    return (
      [
        for (final item in items)
          if (owned.containsKey(kit.id(item))) item,
      ],
      visuals,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final profile = widget.profile;
    return FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final visuals = snapshot.data?.$2;
        final kit = CatalogKit(profile, t, state.api, visuals);
        var items = snapshot.data?.$1;
        BrowseRail? rail;
        Widget? heading;
        if (profile.presentation == Presentation.character &&
            items != null &&
            visuals != null) {
          final bands = {
            for (final item in items)
              if (item['bandId'] case final num id) id.toInt(),
          }.toList()..sort();
          final band = _band ?? '${bands.firstOrNull ?? ''}';
          if (!identical(items, _railSource) || band != _railBand) {
            _railSource = items;
            _railBand = band;
            _railItems = [
              for (final item in items)
                if ('${item['bandId']}' == band) item,
            ];
          }
          items = _railItems;
          rail = BrowseRail(
            value: band,
            onSelect: (value) => setState(() => _band = value),
            items: [
              for (final id in bands)
                RailItem(
                  '$id',
                  t.text(visuals.bands[id]?['bandName']),
                  image: visuals.bandLogo(id),
                ),
            ],
          );
          heading = _BandHeading(
            band: visuals.bands[int.tryParse(band)],
            t: t,
            api: state.api,
          );
        }
        return BrowseScreen(
          key: ValueKey(profile.resource),
          title: widget.title ?? t(profile.label, profile.resource),
          items: items,
          error: snapshot.error,
          onRetry: () => setState(() => _data = _load()),
          rail: rail,
          heading: heading,
          searchText: kit.searchText,
          grid: GridSpec(
            minWidth: profile.minWidth,
            aspectRatio: profile.aspectRatio,
            small: profile.small,
          ),
          tile: (context, item) => Tile(
            title: kit.title(item),
            subtitle: kit.subtitle(item),
            adornments: kit.adornments(item),
            images: kit.images(item),
            aspectRatio: profile.aspectRatio,
            // Portraits keep the full width and clip below the head
            // (`.tile--character` media: natural height, top anchored).
            fit: profile.presentation == Presentation.character
                ? BoxFit.fitWidth
                : profile.fit,
            accent: kit.accent(item),
            alignment: profile.presentation == Presentation.character
                ? Alignment.topCenter
                : Alignment.center,
            media: profile.resource == 'events' && item['logo'] is String
                ? EventArtwork(
                    background: kit.api
                        .asset(
                          '${item['backgroundImage'] ?? kit.images(item).firstOrNull ?? ''}',
                        )
                        .toString(),
                    logo: kit.api.asset('${item['logo']}').toString(),
                  )
                : null,
            marks: [
              ...kit.marks(item),
              if (widget.owned?[kit.id(item)] case final progress?
                  when progress.isNotEmpty)
                TileMark.text(MarkAt.bottomEnd, progress),
            ],
            placeholder: profile.icon,
            onTap: () => widget.onOpen?.call(context, item),
          ),
          listRow: (context, item) => _Row(
            kit: kit,
            item: item,
            onOpen: () => widget.onOpen?.call(context, item),
          ),
          columns: kit.columns,
          facets: visuals == null ? const [] : kit.facets,
          sorts: kit.sorts,
          defaultSort: profile.defaultSort,
          descending: profile.descending,
        );
      },
    );
  }
}

/// A card rarity's name, as the game prints it (`cardRarityName`).
String cardRarityName(Object? value) =>
    _rarities[(value as num?)?.toInt()] ?? '';

/// What a catalogue entry shows, by presentation; the website's
/// `tileDescription`, `tileAdornment`, `cardTileOptions` and facet groups.
class CatalogKit {
  CatalogKit(this.profile, this.t, this.api, this.visuals, {this.songTitles});

  /// The reader's song-title choice (`AppState.songTitle`).
  final String Function(Object?)? songTitles;
  final CatalogProfile profile;
  final SiteText t;
  final HaneokaApi api;
  final CatalogVisuals? visuals;

  Presentation get kind => profile.presentation;

  static final _markup = RegExp(r'<[^>]+>');
  String plain(Object? value) => t.text(value).replaceAll(_markup, '').trim();

  String id(Entry item) => '${firstOf(item, profile.id) ?? item['_key']}';

  String title(Entry item) {
    final raw = firstOf(item, profile.title);
    final value = kind == Presentation.song && songTitles != null
        ? songTitles!(raw)
        : plain(raw);
    return value.isEmpty ? '—' : value;
  }

  /// The character's colour behind its portrait (`--entity-accent`).
  Color? accent(Entry item) {
    if (kind != Presentation.character) return null;
    final hex = '${item['colorCode'] ?? ''}'.replaceFirst('#', '');
    final value = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
    return value == null ? null : Color(0xFF000000 | value);
  }

  List<String> images(Entry item) => [
    for (final path in profile.image)
      if (readPath(item, path) case final String value when value.isNotEmpty)
        api.asset(value).toString(),
  ];

  List<int> characterIds(Entry item) => [
    for (final value in [
      ...?(item['characterIds'] as List?),
      ...?(item['characters'] as List?),
      if (item['characterIds'] == null && item['characters'] == null)
        item['characterId'],
    ])
      if (value is num && value > 0) value.toInt(),
  ];

  String characterName(int id) =>
      t.text(visuals?.characters[id]?['characterName']);

  String bandName(Object? id) =>
      t.text(visuals?.bands[(id as num?)?.toInt()]?['bandName']);

  String names(List<int> ids) => ids.map(characterName).join(', ');

  String subtitle(Entry item) => switch (kind) {
    Presentation.member ||
    Presentation.support ||
    Presentation.comic => names(characterIds(item)),
    Presentation.stamp =>
      profile.resource == 'stickers' && plain(item['description']).isNotEmpty
          ? plain(item['description'])
          : names(characterIds(item)),
    Presentation.character => bandName(item['bandId']),
    Presentation.bandItem => bandName(item['bandId']),
    Presentation.item =>
      plain(item['description']).isNotEmpty
          ? plain(item['description'])
          : '${item['itemTypeName'] ?? ''}',
    Presentation.background || Presentation.skill => plain(item['description']),
    Presentation.system => t.window(
      item['startAt'],
      item['endAt'],
      ongoing: t.label('ongoing', 'Ongoing'),
    ),
    Presentation.song => '',
  };

  List<String> adornments(Entry item) {
    if (kind == Presentation.character || kind == Presentation.bandItem) {
      return [?visuals?.bandIcon(item['bandId'])];
    }
    if (const {
      Presentation.member,
      Presentation.support,
      Presentation.comic,
      Presentation.stamp,
    }.contains(kind)) {
      return [
        for (final id in characterIds(item).take(3))
          if (visuals?.characters[id]?['faceImage'] case final String face)
            api.asset(face).toString(),
      ];
    }
    return const [];
  }

  String rarityName(Object? value) => cardRarityName(value);

  String attributeName(Object? value) {
    final id = (value as num?)?.toInt() ?? 0;
    return id > 0 && id < _attributes.length ? t.label(_attributes[id]) : '';
  }

  List<TileMark> marks(Entry item) {
    if (kind == Presentation.system) {
      final end = RelativeTime.timestamp(item['endAt']) ?? 0;
      final start = RelativeTime.timestamp(item['startAt']) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      return [
        if (!(start > now) && end > 0 && end < now)
          TileMark.text(
            MarkAt.bottomEnd,
            t.label('ended', 'Ended'),
            alert: true,
          ),
      ];
    }
    if (profile.resource == 'stickers') {
      final closed = RelativeTime.timestamp(item['closedAt']) ?? 0;
      return [
        if (closed > 0 && closed < DateTime.now().millisecondsSinceEpoch)
          TileMark.text(
            MarkAt.bottomEnd,
            t.label('retired', 'Retired'),
            alert: true,
          ),
      ];
    }
    if (kind != Presentation.member && kind != Presentation.support) {
      return const [];
    }
    final attribute = visuals?.cardTypeMark(item['cardType']);
    final rarity = visuals?.mark(
      'RarityIconCenter_${rarityName(item['rarity'])}.png',
    );
    return [
      if (attribute != null)
        TileMark.image(
          MarkAt.start,
          attribute,
          label: attributeName(item['cardType']),
        ),
      if (rarity != null)
        TileMark.image(MarkAt.end, rarity, label: rarityName(item['rarity'])),
    ];
  }

  num? releasedAt(Entry item) => RelativeTime.timestamp(
    item['releasedAt'] ?? item['publishedAt'] ?? item['publicStartAt'],
  );

  String date(num? ms) => ms == null
      ? '—'
      : DateFormat.yMMMd(t.locale)
            .format(DateTime.fromMillisecondsSinceEpoch(ms.toInt()));

  String searchText(Entry item) => [
    id(item),
    title(item),
    subtitle(item),
    ...?(firstOf(item, profile.title) as List?)?.whereType<String>(),
  ].join(' ');

  int total(Entry item) => ['performance', 'technique', 'visual'].fold(
    0,
    (sum, key) => sum + ((readPath(item, 'stat.$key') as num?)?.toInt() ?? 0),
  );

  List<TableColumn> get columns => [
    TableColumn(t.label('title'), title),
    TableColumn('', subtitle),
    if (kind == Presentation.member || kind == Presentation.support) ...[
      TableColumn(t.label('rarity'), (item) => rarityName(item['rarity'])),
      TableColumn(
        t.label('attribute'),
        (item) => attributeName(item['cardType']),
      ),
      TableColumn(t.label('total'), (item) => '${total(item)}', numeric: true),
    ],
    if (kind == Presentation.system) ...[
      TableColumn(
        t.label('start'),
        (item) => date(RelativeTime.timestamp(item['startAt'])),
      ),
      TableColumn(
        t.label('end'),
        (item) => date(RelativeTime.timestamp(item['endAt'])),
      ),
    ] else
      TableColumn(t.label('release'), (item) => date(releasedAt(item))),
    TableColumn(t.label('id'), id, numeric: true),
  ];

  List<SortSpec> get sorts => [
    if (kind == Presentation.character ||
        kind == Presentation.item ||
        kind == Presentation.bandItem)
      SortSpec(
        'order',
        t.label('order'),
        (item) =>
            (item['displayOrder'] ?? item['order'] ?? item['sortOrder'])
                as num?,
      ),
    SortSpec('id', t.label('id'), (item) => num.tryParse(id(item)) ?? id(item)),
    SortSpec('title', t.label('title'), title),
    if (kind == Presentation.system)
      SortSpec(
        'start',
        t.label('start'),
        (item) => RelativeTime.timestamp(item['startAt']),
      )
    else if (kind != Presentation.character &&
        kind != Presentation.item &&
        kind != Presentation.bandItem &&
        kind != Presentation.skill)
      SortSpec('release', t.label('release'), releasedAt),
    if (kind == Presentation.member || kind == Presentation.support) ...[
      SortSpec('rarity', t.label('rarity'), (item) => item['rarity'] as num?),
      SortSpec(
        'cardType',
        t.label('attribute'),
        (item) => item['cardType'] as num?,
      ),
      for (final stat in ['performance', 'technique', 'visual'])
        SortSpec(
          stat,
          t.label(stat),
          (item) => readPath(item, 'stat.$stat') as num?,
        ),
      SortSpec('total', t.label('total'), total),
    ],
  ];

  List<FacetSpec> get facets {
    final visuals = this.visuals!;
    final characters = FacetSpec(
      key: 'character',
      label: t.label('character'),
      values: (item) => characterIds(item).map((id) => '$id'),
      option: (value) {
        final face = visuals.characters[int.parse(value)]?['faceImage'];
        return FacetOption(
          characterName(int.parse(value)),
          image: face is String ? api.asset(face).toString() : null,
        );
      },
    );
    final bands = FacetSpec(
      key: 'band',
      label: t.label('band'),
      values: (item) => {
        for (final id in characterIds(item))
          if (visuals.characters[id]?['bandId'] case final num band) '$band',
        if (item['bandId'] case final num band) '$band',
      },
      option: (value) => FacetOption(
        bandName(int.parse(value)),
        image: visuals.bandIcon(int.parse(value)),
      ),
    );
    const cardKinds = {Presentation.member, Presentation.support};
    const characterKinds = {
      Presentation.member,
      Presentation.support,
      Presentation.comic,
      Presentation.stamp,
    };
    return [
      if (characterKinds.contains(kind) || kind == Presentation.bandItem) bands,
      if (characterKinds.contains(kind)) characters,
      if (cardKinds.contains(kind)) ...[
        FacetSpec(
          key: 'rarity',
          label: t.label('rarity'),
          values: (item) => [if (item['rarity'] != null) '${item['rarity']}'],
          option: (value) => FacetOption(
            rarityName(int.parse(value)),
            image: visuals.mark(
              'RarityIconCenter_${rarityName(int.parse(value))}.png',
            ),
            imageOnly: true,
          ),
        ),
        FacetSpec(
          key: 'type',
          label: t.label('attribute'),
          values: (item) => [
            if (item['cardType'] != null) '${item['cardType']}',
          ],
          option: (value) => FacetOption(
            attributeName(int.parse(value)),
            image: visuals.cardTypeMark(int.parse(value)),
          ),
        ),
      ],
      if (kind == Presentation.item)
        FacetSpec(
          key: 'type',
          label: t.label('type'),
          values: (item) => [
            if (item['itemTypeName'] != null) '${item['itemTypeName']}',
          ],
          option: FacetOption.new,
        ),
      if (kind == Presentation.system)
        FacetSpec(
          key: 'kind',
          label: t.label('category'),
          values: (item) => [
            if (plain(item['category']).isNotEmpty)
              plain(item['category'])
            else if (item['kind'] != null)
              '${item['kind']}',
          ],
          option: (value) => FacetOption(t.label(value, value)),
        ),
    ];
  }
}

/// The band the character rail has selected, named: icon, name and its own
/// description (`BrowseHeading`).
class _BandHeading extends StatelessWidget {
  const _BandHeading({required this.band, required this.t, required this.api});
  final Entry? band;
  final SiteText t;
  final HaneokaApi api;

  @override
  Widget build(BuildContext context) {
    final band = this.band;
    if (band == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final icon = band['icon'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon is String)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox.square(
              dimension: 40,
              child: AppImage(candidates: [api.asset(icon).toString()]),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.text(band['bandName']), style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                t.text(band['description']).replaceAll('\n', ''),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.kit, required this.item, this.onOpen});
  final CatalogKit kit;
  final Entry item;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = kit.subtitle(item);
    return ListTile(
      onTap: onOpen,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: kit.profile.aspectRatio > 1.2 ? 85 : 48,
          height: 48,
          child: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: AppImage(candidates: kit.images(item), fit: kit.profile.fit),
          ),
        ),
      ),
      title: Text(
        kit.title(item),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
