import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../core/audio.dart';
import '../core/i18n.dart';
import '../core/page_data.dart';
import '../core/relative_time.dart';
import '../l10n/app_localizations.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/detail.dart';
import 'card_growth.dart';
import 'catalog_screen.dart';
import 'format.dart';
import 'labels.g.dart';
import 'profiles.dart';
import 'system_detail.dart';
import 'visuals.dart';

const _difficultyNames = ['EASY', 'NORMAL', 'HARD', 'EXPERT', 'SPECIAL'];
const _rankNames = ['', 'E', 'D', 'C', 'B', 'A', 'S', 'SS'];

/// One entity as the website's entity page: artwork in the gallery beside
/// the presentation's own sections, every remaining field folded under All
/// fields.
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.profile,
    required this.id,
    required this.summary,
  });
  final CatalogProfile profile;
  final String id;
  final Entry summary;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Future<(Entry, CatalogVisuals, Entry?)>? _data;
  int? _difficulty;

  void refresh(VoidCallback change) => setState(change);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(Entry, CatalogVisuals, Entry?)> _load() async {
    final state = AppScope.of(context);
    final api = state.api;
    final resource = widget.profile.resource;
    final (record, visuals, page) = await (
      api
          .catalog(resource, widget.id)
          .then<Entry>(
            (value) => {...widget.summary, if (value is Entry) ...value},
            onError: (_) => widget.summary,
          ),
      CatalogVisuals.of(api),
      entityPage(api.server, state.text.locale, resource, widget.id),
    ).wait;
    final item = page?['item'];
    return (
      item is Map ? {...record, ...item.cast<String, Object?>()} : record,
      visuals,
      page,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    return FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final record = snapshot.data?.$1 ?? widget.summary;
        final visuals = snapshot.data?.$2;
        final page = snapshot.data?.$3;
        final kit = CatalogKit(
          widget.profile,
          t,
          state.api,
          visuals,
          songTitles: state.songTitle,
        );
        final view = _Page(kit, record, this, page, ready: snapshot.hasData);
        return ShellPage(
          title: kit.title(record),
          marks: view.marks(),
          actions: view.actions(),
          body: DetailLayout(media: view.media(), sections: view.sections()),
        );
      },
    );
  }
}

/// The sections of one entity, by presentation.
class _Page {
  _Page(this.kit, this.record, this.host, this.page, {this.ready = true});
  final bool ready;
  final CatalogKit kit;
  final Entry record;
  final _DetailScreenState host;

  /// The website's payload for this page, when it was published.
  final Entry? page;

  SiteText get t => kit.t;
  BuildContext get context => host.context;
  Presentation get kind => kit.kind;
  AudioService get audio => AppScope.of(context).audio;

  Widget _emblem(String? url, {double size = 24}) => url == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(right: 6),
          child: SizedBox(
            height: size,
            width: size,
            child: AppImage(candidates: [url]),
          ),
        );

  Widget? marks() {
    final visuals = kit.visuals;
    if (visuals == null) return null;
    final children = <Widget>[
      if (kind == Presentation.song) ...[
        for (final id in (record['bandIds'] as List? ?? const []))
          if (visuals.bandLogo(id) case final logo?)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                height: 24,
                width: 40,
                child: AppImage(candidates: [logo]),
              ),
            ),
        _emblem(visuals.musicTypeMark(record['musicType'])),
      ],
      if (kind == Presentation.member || kind == Presentation.support) ...[
        for (final id in kit.characterIds(record).take(3))
          if (visuals.characters[id]?['faceImage'] case final String face)
            _emblem(kit.api.asset(face).toString()),
        for (final mark in kit.marks(record)) _emblem(mark.image),
      ],
    ];
    return children.isEmpty
        ? null
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  List<BarAction> actions() {
    if (kind != Presentation.song || record['musicUrl'] is! String) {
      return const [];
    }
    final track = Track(
      id: kit.id(record),
      url: kit.api.asset(record['musicUrl'] as String).toString(),
      title: kit.title(record),
      artwork: kit.images(record).firstOrNull,
    );
    final playing = audio.isPlaying(track.id);
    return [
      BarAction(
        icon: playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
        label: t(playing ? 'common.actions.pause' : 'common.actions.play'),
        tonal: true,
        onPressed: () async {
          await audio.toggle(track);
          host.refresh(() {});
        },
      ),
    ];
  }

  Widget? media() {
    final images = switch (kind) {
      Presentation.member => _paths([
        'images.thumbnail',
        'images.full',
        'images.character',
      ]),
      Presentation.support => _paths(['images.thumbnail', 'images.full']),
      Presentation.character => _paths([
        'profileImage',
        'thumbnailImage',
        'spriteImage',
        'faceImage',
      ]),
      _ => kit.images(record),
    };
    final all = images.isNotEmpty
        ? images
        : imagesIn(record).map((p) => kit.api.asset(p).toString()).toList();
    if (all.isEmpty) return null;
    return ImageGallery(
      images: all.toSet().toList(),
      aspectRatio:
          kind == Presentation.support ||
              kind == Presentation.system ||
              kind == Presentation.background
          ? 16 / 9
          : 1,
    );
  }

  List<String> _paths(List<String> paths) => [
    for (final path in paths)
      if (readPath(record, path) case final String value when value.isNotEmpty)
        kit.api.asset(value).toString(),
  ];

  String _date(Object? value) {
    final ms = RelativeTime.timestamp(value);
    return ms == null
        ? ''
        : DateFormat.yMMMd(t.locale)
              .add_Hm()
              .format(DateTime.fromMillisecondsSinceEpoch(ms.toInt()));
  }

  List<Widget> sections() => [
    ...switch (kind) {
      Presentation.song => _song(),
      Presentation.member || Presentation.support => _card(),
      _ => _generic(),
    },
    ..._rest(),
  ];

  // ---------- Songs ----------

  List<Entry> get _charts => [
    for (final row in (record['difficulty'] as List? ?? const []))
      if (row is Entry) row,
  ];

  List<Widget> _song() {
    final charts = _charts;
    final chosen =
        host._difficulty ??
        (charts.any((c) => c['difficulty'] == 3)
            ? 3
            : charts.lastOrNull?['difficulty'] as int?);
    final chart = charts.where((c) => c['difficulty'] == chosen).firstOrNull;
    String list(Object? value) => switch (value) {
      List() =>
        value.whereType<String>().where((s) => s.isNotEmpty).take(1).join(),
      _ => t.text(value),
    };
    final facts = [
      if (chart != null) ...[
        Fact(
          t.label('level'),
          '${chart['displayLevel'] ?? chart['playLevel'] ?? '—'}',
        ),
        Fact(
          t.label('n'),
          NumberFormat.decimalPattern(t.locale).format(chart['noteCount'] ?? 0),
        ),
      ],
      for (final key in ['composer', 'lyricist', 'arranger'])
        if (list(record[key]).isNotEmpty)
          Fact(
            t.label(
              key == 'lyricist'
                  ? 'lyrics'
                  : key == 'arranger'
                  ? 'arrangement'
                  : key,
            ),
            list(record[key]),
          ),
      if (_date(record['publishedAt']).isNotEmpty)
        Fact(t.label('release'), _date(record['publishedAt'])),
    ];
    return [
      DetailSection(
        icon: Symbols.info_rounded,
        title: t('common.actions.details', 'Details'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DifficultyChips(
              captions: {
                if (AppScope.of(context).difficultyEstimates)
                  for (final c in charts)
                    if (readPath(c, 'difficultyEstimate.estimatedConstant')
                        case final num value)
                      (c['difficulty'] as num).toInt(): value.toStringAsFixed(
                        1,
                      ),
              },
              selected: chosen,
              onSelected: (index) =>
                  host.refresh(() => host._difficulty = index),
              levels: [
                for (final c in charts)
                  (
                    (c['difficulty'] as num).toInt(),
                    _difficultyNames[(c['difficulty'] as num).toInt().clamp(
                      0,
                      4,
                    )],
                    '${c['displayLevel'] ?? c['playLevel'] ?? ''}'.replaceAll(
                      RegExp(r'\.0$'),
                      '',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SpecList(facts: facts),
          ],
        ),
      ),
      ?_rewards(chart),
    ];
  }

  Widget? _rewards(Entry? chart) {
    final ranks = [
      for (final r in (record['scoreRanks'] as List? ?? const []))
        if (r is Entry && ((r['scoreRank'] as num?) ?? 0) >= 3) r,
    ];
    final scoreRewards = [
      for (final r in (record['scoreRewards'] as List? ?? const []))
        if (r is Entry) r,
    ];
    final name = '${chart?['difficultyName'] ?? ''}'.toLowerCase();
    final combo = [
      for (final r
          in ((record['comboRewards'] as Map?)?[name] as List? ?? const []))
        if (r is Entry) r,
    ];
    if (ranks.isEmpty && scoreRewards.isEmpty && combo.isEmpty) return null;
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern(t.locale);
    final server = kit.api.server;
    Widget reward(Entry r) {
      final resolved = (r['resolved'] as Map?) ?? const {};
      final image = resolved['image'];
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 26,
              child: image is String
                  ? AppImage(candidates: [kit.api.asset(image).toString()])
                  : const Icon(Symbols.redeem_rounded, size: 18),
            ),
            const SizedBox(width: 6),
            Text(t.text(resolved['name']), style: theme.textTheme.bodyMedium),
            Text(
              ' ×${number.format(r['resourceCount'] ?? 0)}',
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      );
    }

    Widget row(
      Widget? leading,
      String value,
      String caption,
      List<Entry> rewards,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 12)],
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: theme.textTheme.titleSmall),
                Text(
                  caption,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              runSpacing: 4,
              children: [for (final r in rewards) reward(r)],
            ),
          ),
        ],
      ),
    );
    final rankIds = {
      for (final r in ranks) (r['scoreRank'] as num).toInt(),
      for (final r in scoreRewards) (r['liveScoreRank'] as num).toInt(),
    }.toList()..sort();
    final notes = (chart?['noteCount'] as num?) ?? 0;
    const percentages = [25, 50, 75, 100];
    return DetailSection(
      icon: Symbols.emoji_events_rounded,
      title: t.label('rewards', 'Rewards'),
      count: ranks.length + scoreRewards.length + combo.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.label('score', 'Score'), style: theme.textTheme.titleSmall),
          for (final id in rankIds)
            row(
              SizedBox.square(
                dimension: 28,
                child: AppImage(
                  candidates: [
                    kit.api
                        .asset(
                          '/assets/$server/Assets/AddressableResources/UI/Texture/BandRank/ImgScorerank_${_rankNames[id.clamp(0, 7)]}.png',
                        )
                        .toString(),
                  ],
                ),
              ),
              number.format(
                ranks
                        .where((r) => r['scoreRank'] == id)
                        .firstOrNull?['requiredScore'] ??
                    0,
              ),
              t.label('score', 'Score'),
              [
                for (final r in scoreRewards)
                  if (r['liveScoreRank'] == id) r,
              ],
            ),
          if (combo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(t.label('combo', 'Combo'), style: theme.textTheme.titleSmall),
            for (final r in combo)
              Builder(
                builder: (context) {
                  final percent =
                      percentages[((r['comboRateType'] as num?) ?? 0)
                          .toInt()
                          .clamp(0, 3)];
                  return row(
                    null,
                    percent == 100 ? 'FULL COMBO' : '$percent%',
                    '${number.format((notes * percent / 100).ceil())} ${t.label('notes', 'notes')}',
                    [r],
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  // ---------- Member cards and snapshots ----------

  List<Widget> _card() {
    final visuals = kit.visuals;
    final marks = kit.marks(record);
    final ids = kit.characterIds(record);
    return [
      DetailSection(
        icon: Symbols.info_rounded,
        title: t('common.actions.details', 'Details'),
        child: SpecList(
          facts: [
            for (final mark in marks.reversed)
              Fact(
                mark.at.name == 'end'
                    ? t.label('rarity')
                    : t.label('attribute'),
                mark.label ?? '',
                widget: SizedBox(
                  height: 28,
                  width: 28,
                  child: AppImage(candidates: [mark.image!]),
                ),
              ),
            if (_date(record['releasedAt']).isNotEmpty)
              Fact(t.label('release'), _date(record['releasedAt'])),
          ],
        ),
      ),
      CardGrowthView(
        record: record,
        visuals: visuals,
        characterIds: ids,
        characterName: kit.characterName,
        support: kind == Presentation.support,
        page: page,
        ready: ready,
      ),
    ];
  }

  // ---------- Everything else ----------

  List<Widget> _generic() {
    final format = ValueFormat(t);
    final facts = [
      for (final key in kit.profile.detail)
        if (readPath(record, key) case final value?)
          if (format.format(key, value) case final text
              when text.isNotEmpty && !text.startsWith('/assets/'))
            Fact(_named(key) ?? key, text),
      if (kind == Presentation.system) ...[
        if (_date(record['startAt']).isNotEmpty)
          Fact(t.label('starts', 'Starts'), _date(record['startAt'])),
        if (_date(record['endAt']).isNotEmpty)
          Fact(t.label('ends', 'Ends'), _date(record['endAt'])),
      ],
    ];
    final description = kit.plain(record['description']);
    final resource = kit.profile.resource;
    final rotating = resource == 'events' || resource == 'gacha';
    final titled = kind == Presentation.item || kind == Presentation.bandItem;
    final details = facts.isEmpty || rotating
        ? null
        : DetailSection(
            icon: Symbols.info_rounded,
            title: t('common.actions.details', 'Details'),
            child: SpecList(facts: facts),
          );
    return [
      if (description.isNotEmpty && !titled && !rotating)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: SelectableText(
            description,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ?details,
      if (description.isNotEmpty && titled)
        DetailSection(
          icon: Symbols.notes_rounded,
          title: t.label('content', 'Content'),
          child: SelectableText(
            description,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      if (kind == Presentation.system)
        SystemDetail(
          key: ValueKey('$resource:${kit.id(record)}'),
          resource: resource,
          item: record,
          visuals: kit.visuals,
        ),
    ];
  }

  /// Every remaining scalar under All fields, as the website's fold.
  List<Widget> _rest() {
    final format = ValueFormat(t);
    final shown = {...kit.profile.detail, 'description', 'raw', 'evidence'};
    final facts = [
      for (final MapEntry(:key, :value) in record.entries)
        if (!key.startsWith('_') &&
            !shown.contains(key) &&
            ValueFormat.isScalar(value))
          if (format.format(key, value) case final text
              when text.isNotEmpty && !text.startsWith('/'))
            Fact(_named(key) ?? key, text),
    ];
    if (facts.isEmpty) return const [];
    return [
      DetailSection(
        icon: Symbols.data_object_rounded,
        title: AppLocalizations.of(context).allFields,
        folded: true,
        child: SpecList(facts: facts),
      ),
    ];
  }

  /// The website's label for a field, or null when it does not name it.
  String? _named(String key) {
    for (final path in [
      ?catalogLabelPaths[key],
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
}
