import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../core/app_state.dart';
import '../core/audio.dart';
import '../core/relative_time.dart';
import '../shell/page.dart';
import '../shell/routes.dart';
import '../ui/app_image.dart';
import '../ui/detail.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';
import 'profiles.dart';
import 'visuals.dart';

const _difficultyNames = ['EASY', 'NORMAL', 'HARD', 'EXPERT', 'SPECIAL'];
const _categories = ['', 'original', 'virtual', 'jpop', 'anime', 'game'];
const _attributes = ['', 'red', 'blue', 'green', 'yellow', 'purple'];
const _missions = [
  null,
  ('gekisouMissionCombo', 'COMBO', 'combo'),
  ('gekisouMissionLuck', 'LUCK', 'luck'),
  ('gekisouMissionJustCount', 'JUST', 'just'),
];

/// One chart: a song at one difficulty, with its metrics.
class _Chart {
  _Chart(this.song, this.index, this.row, this.chart, this.gekisou);
  final Entry song;
  final int index;
  final Entry row;
  final Entry chart;
  final Entry gekisou;
}

/// The website's song analysis (`song-meta`): every chart's live or gekisou
/// metrics in one sortable table, against the theoretical, current or a
/// band's reference deck.
class SongMetaScreen extends StatefulWidget {
  const SongMetaScreen({super.key});
  @override
  State<SongMetaScreen> createState() => _SongMetaScreenState();
}

class _SongMetaScreenState extends State<SongMetaScreen> {
  Future<(List<_Chart>, CatalogVisuals, Map<String, String>)>? _data;
  bool _gekisou = false;
  String _tier = 'theory';
  String _sort = 'score';
  bool _descending = true;
  String _query = '';
  final Set<int> _difficulties = {};
  final Set<int> _bands = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<_Chart>, CatalogVisuals, Map<String, String>)> _load() async {
    final api = AppScope.of(context).api;
    final (songs, meta, visuals, atlas) = await (
      api.catalog('songs'),
      api.catalog('song-meta'),
      CatalogVisuals.of(api),
      api
          .json(
            '/api/v1/servers/${api.server}/sources/Assets/AddressableResources/Live/Images/Atlas/LiveAtlas.spriteatlasv2',
          )
          .then<Object?>((v) => v, onError: (_) => null),
    ).wait;
    final pattern = RegExp(r'Icon_gekisou_(combo|luck|just)--');
    final icons = <String, String>{};
    for (final output in ((atlas as Map?)?['outputs'] as List? ?? const [])) {
      final path = output is Map ? '${output['path']}' : '';
      final match = pattern.firstMatch(path);
      if (match != null) {
        icons[match[1]!] = api
            .asset('/runtime/${api.server}/${path.substring(8)}')
            .toString();
      }
    }
    final charts = <_Chart>[];
    for (final MapEntry(:key, :value) in ((meta as Map?) ?? const {}).entries) {
      final song = (songs as Map?)?[key];
      if (song is! Entry || value is! Map) continue;
      final rows = (song['difficulty'] as List? ?? const []).cast<Entry>();
      for (final MapEntry(key: index, value: difficulty) in value.entries) {
        final i = int.tryParse('$index');
        if (i == null || difficulty is! Map || difficulty['chart'] is! Entry) {
          continue;
        }
        charts.add(
          _Chart(
            song,
            i,
            rows.where((r) => r['difficulty'] == i).firstOrNull ??
                (i < rows.length ? rows[i] : const {}),
            difficulty['chart'] as Entry,
            (difficulty['gekisou'] as Entry?) ?? const {},
          ),
        );
      }
    }
    return (charts, visuals, icons);
  }

  num? _value(_Chart c, String key) {
    num? read(Object? v) => v is num ? v : null;
    if (key == 'bpm') {
      return read(
        c.chart['firstBpm'] ?? c.chart['minBpm'] ?? c.chart['maxBpm'],
      );
    }
    if (key == 'n') return read(c.chart['n'] ?? c.chart['canonicalNoteCount']);
    if (key == 'level') {
      return read(
        c.row['displayLevel'] ?? c.row['playLevel'] ?? c.chart['displayLevel'],
      );
    }
    if (key == 'release') return RelativeTime.timestamp(c.song['publishedAt']);
    if (_gekisou) {
      switch (key) {
        case 'score':
          return read(c.gekisou['score']);
        case 'eff':
          return read(c.gekisou['eff']);
        case 'justable':
          return read(c.gekisou['justableTotal']);
        case 'justableRate':
          return read(c.gekisou['justableRate']);
        case 'luck':
          final total = (c.gekisou['segments'] as List? ?? const [])
              .whereType<Map>()
              .fold<num>(
                0,
                (sum, s) => sum + ((s['luckExpected'] as num?) ?? 0),
              );
          return total == 0 ? null : total;
      }
    }
    if (_tier != 'theory' && const {'score', 'eff', 'sr'}.contains(key)) {
      final profile = (c.chart['profiles'] as Map?)?[_tier];
      return profile is Map ? read(profile[key]) : null;
    }
    return read(c.chart[key]);
  }

  String _format(_Chart c, String key, String unavailable) {
    final value = _value(c, key);
    final locale = AppScope.of(context).text.locale;
    if (value == null) {
      return _tier != 'theory' && const {'score', 'eff', 'sr'}.contains(key)
          ? unavailable
          : '—';
    }
    if (key == 'time') {
      final s = value.round();
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    if (const {'score', 'eff', 'sr', 'justableRate'}.contains(key)) {
      return '${NumberFormat.decimalPattern(locale).format((value * 100).round())}%';
    }
    if (key == 'nps') return value.toStringAsFixed(2);
    return NumberFormat.decimalPattern(locale).format(value.round());
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    String label(String key, [String? fallback]) => t.label(key, fallback);
    return FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final visuals = data?.$2;
        var rows = data?.$1 ?? const <_Chart>[];
        final query = _query.toLowerCase();
        rows = [
          for (final c in rows)
            if ((_difficulties.isEmpty || _difficulties.contains(c.index)) &&
                (_bands.isEmpty || _bands.contains(c.song['bandId'])) &&
                (_tier.startsWith('band:')
                    ? '${c.song['bandId']}' == _tier.substring(5)
                    : true) &&
                (query.isEmpty ||
                    [
                      ...?(c.song['musicTitle'] as List?)?.whereType<String>(),
                      '${c.song['musicId']}',
                    ].join(' ').toLowerCase().contains(query)))
              c,
        ];
        rows.sort((a, b) {
          if (_sort == 'title') {
            final x = state.songTitle(a.song['musicTitle']),
                y = state.songTitle(b.song['musicTitle']);
            return _descending ? y.compareTo(x) : x.compareTo(y);
          }
          if (_sort == 'musicType' || _sort == 'band') {
            final key = _sort == 'band' ? 'bandId' : 'musicType';
            final x = (a.song[key] as num?) ?? 0,
                y = (b.song[key] as num?) ?? 0;
            return _descending ? y.compareTo(x) : x.compareTo(y);
          }
          final x = _value(a, _sort), y = _value(b, _sort);
          if (x == null && y == null) return 0;
          if (x == null) return 1;
          if (y == null) return -1;
          return _descending ? y.compareTo(x) : x.compareTo(y);
        });
        return ShellPage(
          title: t('catalog.songs.fields.songMeta', 'Song analysis'),
          search: ShellSearch(
            label: t('common.actions.search', 'Search'),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          status: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                data == null
                    ? ''
                    : NumberFormat.decimalPattern(t.locale).format(rows.length),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          actions: [
            BarAction(
              icon: Symbols.playlist_play_rounded,
              label: label('playAll', 'Play all'),
              onPressed: rows.isEmpty
                  ? null
                  : () => state.audio.playQueue([
                      for (final c in {
                        for (final c in rows) c.song['musicId']: c,
                      }.values)
                        if (c.song['musicUrl'] case final String url)
                          Track(
                            id: '${c.song['musicId']}',
                            url: state.api.asset(url).toString(),
                            title: state.songTitle(c.song['musicTitle']),
                            subtitle: t.text(
                              visuals?.bands[c.song['bandId']]?['bandName'],
                            ),
                            artwork: c.song['jacketUrl'] is String
                                ? state.api
                                      .asset(c.song['jacketUrl'] as String)
                                      .toString()
                                : null,
                          ),
                    ]),
            ),
            BarAction(
              icon: Symbols.filter_alt_rounded,
              label: t('common.actions.filter', 'Filter'),
              badge: _difficulties.length + _bands.length,
              onPressed: visuals == null
                  ? null
                  : () => _filters(context, visuals),
            ),
            BarAction.choice(
              label: label('metaMode', 'Mode'),
              options: [
                BarChoice(
                  icon: Symbols.music_note_rounded,
                  label: label('metaModeLive', 'Live'),
                  selected: !_gekisou,
                  onSelected: () => setState(() => _gekisou = false),
                ),
                BarChoice(
                  icon: Symbols.bolt_rounded,
                  label: label('metaModeGekisou', 'Gekisou'),
                  selected: _gekisou,
                  onSelected: () => setState(() {
                    _gekisou = true;
                    _tier = 'theory';
                  }),
                ),
              ],
            ),
          ],
          body: snapshot.hasError
              ? Center(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Symbols.refresh_rounded),
                    label: Text(t('common.actions.retry', 'Retry')),
                    onPressed: () => setState(() => _data = _load()),
                  ),
                )
              : data == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (!_gekisou) _tiers(context, data.$2, data.$1),
                    Expanded(
                      child: _table(context, rows, data.$2, data.$3, label),
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// The reference tiers (`character-pair__bands`): All, Current, each band's logo.
  Widget _tiers(
    BuildContext context,
    CatalogVisuals visuals,
    List<_Chart> all,
  ) {
    final t = AppScope.of(context).text;
    final scheme = Theme.of(context).colorScheme;
    final bands = {
      for (final c in all) (c.song['bandId'] as num?)?.toInt(),
    }.whereType<int>().toList()..sort();
    final options = [
      ('theory', t.label('all', 'All'), null as String?),
      ('current', t.label('current', 'Current'), null),
      for (final id in bands)
        (
          'band:$id',
          t.text(visuals.bands[id]?['bandName']),
          visuals.bandLogo(id),
        ),
    ];
    final padding = pagePadding(context);
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(padding.left, 12, padding.right, 4),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (key, label, image) = options[index];
          final selected = key == _tier;
          return Tooltip(
            message: label,
            child: Material(
              color: selected
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                onTap: () => setState(() => _tier = key),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 64,
                    minHeight: 48,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Center(
                      child: image == null
                          ? Text(
                              label,
                              style: Theme.of(context).textTheme.labelLarge,
                            )
                          : SizedBox(
                              width: 96,
                              height: 32,
                              child: AppImage(candidates: [image]),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _table(
    BuildContext context,
    List<_Chart> rows,
    CatalogVisuals visuals,
    Map<String, String> icons,
    String Function(String, [String?]) label,
  ) {
    final state = AppScope.of(context);
    final t = state.text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final columns = <(String, String, double, bool)>[
      ('title', label('title'), compact ? 200 : 280, false),
      ('musicType', label('attribute'), 72, false),
      ('band', label('band'), 168, false),
      ('level', label('level'), 96, true),
      ('time', label('metaTime', 'Song Duration'), 96, true),
      ('score', label('metaScoreFactor', 'Factor'), 96, true),
      ('eff', label('metaEff', 'Efficiency'), 104, true),
      if (_gekisou) ...[
        ('justableRate', label('justableRate'), 104, true),
        ('justable', label('justable'), 104, true),
        ('luck', label('luck'), 104, true),
      ],
      ('bpm', label('metaBpm', 'BPM'), 96, true),
      ('n', label('metaN', 'Notes'), 96, true),
      ('nps', label('metaNps', 'NPS'), 104, true),
      if (!_gekisou) ('sr', label('metaSr', 'Skill Coverage Rate'), 112, true),
      ('phase1', '${label('gekisouPhase', 'Phase')} 1', 120, false),
      ('phase2', '${label('gekisouPhase', 'Phase')} 2', 120, false),
      ('phase3', '${label('gekisouPhase', 'Phase')} 3', 120, false),
      ('category', label('category'), 120, false),
      ('release', label('release'), 128, true),
      ('play', '', 56, false),
    ];
    final unavailable = label('unavailable', 'Unavailable');
    final sortable = {
      'title',
      'musicType',
      'band',
      'level',
      'time',
      'score',
      'eff',
      'bpm',
      'n',
      'nps',
      'sr',
      'justableRate',
      'justable',
      'luck',
      'release',
    };

    Widget header(int column) {
      final (key, text, _, numeric) = columns[column];
      final active = key == _sort;
      return InkWell(
        onTap: sortable.contains(key)
            ? () => setState(() {
                if (active) {
                  _descending = !_descending;
                } else {
                  _sort = key;
                  _descending = numeric;
                }
              })
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: numeric
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (sortable.contains(key))
                Icon(
                  active && !_descending
                      ? Symbols.arrow_upward_rounded
                      : Symbols.arrow_downward_rounded,
                  size: 16,
                  color: active ? scheme.primary : scheme.outline,
                ),
            ],
          ),
        ),
      );
    }

    Widget cell(_Chart c, int column) {
      final (key, _, _, numeric) = columns[column];
      Widget text(String value) => Align(
        alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
      final band = (c.song['bandId'] as num?)?.toInt();
      switch (key) {
        case 'title':
          final jacket = c.song['jacketThumbUrl'] ?? c.song['jacketUrl'];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox.square(
                    dimension: 44,
                    child: jacket is String
                        ? AppImage(
                            candidates: [state.api.asset(jacket).toString()],
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.songTitle(c.song['musicTitle']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        t.text(visuals.bands[band]?['bandName']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        case 'musicType':
          final mark = visuals.musicTypeMark(c.song['musicType']);
          final id = (c.song['musicType'] as num?)?.toInt() ?? 0;
          return Center(
            child: mark == null
                ? Text(
                    id > 0 && id < _attributes.length
                        ? t.label(_attributes[id])
                        : '—',
                  )
                : SizedBox.square(
                    dimension: 24,
                    child: AppImage(candidates: [mark]),
                  ),
          );
        case 'band':
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (visuals.bandLogo(band) case final logo?)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 48,
                      height: 24,
                      child: AppImage(candidates: [logo]),
                    ),
                  ),
                Expanded(
                  child: Text(
                    t.text(visuals.bands[band]?['bandName']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        case 'level':
          final level = '${c.row['displayLevel'] ?? c.row['playLevel'] ?? '—'}'
              .replaceAll(RegExp(r'\.0$'), '');
          return Center(
            child: DifficultyChips(
              levels: [(c.index, _difficultyNames[c.index.clamp(0, 4)], level)],
              captions: {
                if (state.difficultyEstimates)
                  if ((c.row['difficultyEstimate']
                          as Map?)?['estimatedConstant']
                      case final num v)
                    c.index: v.toStringAsFixed(1),
              },
            ),
          );
        case 'phase1' || 'phase2' || 'phase3':
          final types =
              ((c.song['gekisou'] as Map?)?['missionTypes'] as List?) ??
              const [];
          final phase = int.parse(key.substring(5)) - 1;
          final type = phase < types.length
              ? (types[phase] as num?)?.toInt() ?? 0
              : 0;
          final mission = type > 0 && type < _missions.length
              ? _missions[type]
              : null;
          if (mission == null) return text('—');
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (icons[mission.$3] case final icon?)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SizedBox.square(
                      dimension: 24,
                      child: AppImage(candidates: [icon]),
                    ),
                  ),
                Flexible(
                  child: Text(
                    t.label(mission.$1, mission.$2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        case 'category':
          return text(
            [
              for (final id in (c.song['musicCategories'] as List? ?? const []))
                if (id is num && id > 0 && id < _categories.length)
                  t.label(_categories[id.toInt()]),
            ].join(', ').ifEmpty('—'),
          );
        case 'release':
          final at = RelativeTime.timestamp(c.song['publishedAt']);
          return text(
            at == null
                ? '—'
                : DateFormat.yMMMd(t.locale)
                      .format(DateTime.fromMillisecondsSinceEpoch(at.toInt())),
          );
        case 'play':
          final url = c.song['musicUrl'];
          if (url is! String) return const SizedBox.shrink();
          final track = Track(
            id: '${c.song['musicId']}',
            url: state.api.asset(url).toString(),
            title: state.songTitle(c.song['musicTitle']),
            artwork: c.song['jacketUrl'] is String
                ? state.api.asset(c.song['jacketUrl'] as String).toString()
                : null,
          );
          return ListenableBuilder(
            listenable: state.audio,
            builder: (context, _) => IconButton(
              tooltip: t('common.actions.play', 'Play'),
              onPressed: () => state.audio.toggle(track),
              icon: Icon(
                state.audio.isPlaying(track.id)
                    ? Symbols.pause_rounded
                    : Symbols.play_arrow_rounded,
              ),
            ),
          );
        default:
          return text(_format(c, key, unavailable));
      }
    }

    final songsProfile = catalogProfiles.firstWhere(
      (p) => p.resource == 'songs',
    );
    final padding = pagePadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Corner.large),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Corner.large),
          ),
          child: TableView.builder(
            pinnedRowCount: 1,
            pinnedColumnCount: 1,
            columnCount: columns.length,
            rowCount: rows.length + 1,
            columnBuilder: (index) => TableSpan(
              extent: FixedTableSpanExtent(columns[index].$3),
              foregroundDecoration: index == 0
                  ? TableSpanDecoration(
                      border: TableSpanBorder(
                        trailing: BorderSide(color: scheme.outlineVariant),
                      ),
                    )
                  : null,
            ),
            rowBuilder: (index) => TableSpan(
              extent: FixedTableSpanExtent(index == 0 ? 56 : 72),
              backgroundDecoration: TableSpanDecoration(
                color: index == 0 ? scheme.surfaceContainer : scheme.surface,
                border: TableSpanBorder(
                  trailing: BorderSide(
                    color: scheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
              recognizerFactories: index == 0
                  ? const {}
                  : {
                      TapGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            TapGestureRecognizer
                          >(
                            () => TapGestureRecognizer(),
                            (recognizer) => recognizer.onTap = () => openEntity(
                              context,
                              songsProfile,
                              rows[index - 1].song,
                            ),
                          ),
                    },
            ),
            cellBuilder: (context, vicinity) => TableViewCell(
              child: vicinity.row == 0
                  ? header(vicinity.column)
                  : cell(rows[vicinity.row - 1], vicinity.column),
            ),
          ),
        ),
      ),
    );
  }

  void _filters(BuildContext context, CatalogVisuals visuals) {
    final t = AppScope.of(context).text;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void toggle(Set<int> set, int value) {
            setState(
              () => set.contains(value) ? set.remove(value) : set.add(value),
            );
            setSheet(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('common.actions.filter', 'Filter'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _difficulties.clear();
                            _bands.clear();
                          });
                          setSheet(() {});
                        },
                        child: Text(t('common.actions.reset', 'Reset')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.label('difficulty', 'Difficulty'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  DifficultyChips(
                    levels: [
                      for (var i = 0; i < 5; i++) (i, _difficultyNames[i], ''),
                    ],
                    selected: _difficulties.length == 1
                        ? _difficulties.first
                        : null,
                    onSelected: (i) => toggle(_difficulties, i),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.label('band'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final MapEntry(:key, :value)
                          in visuals.bands.entries)
                        FilterChip(
                          avatar: visuals.bandIcon(key) == null
                              ? null
                              : AppImage(candidates: [visuals.bandIcon(key)!]),
                          label: Text(t.text(value['bandName'])),
                          selected: _bands.contains(key),
                          onSelected: (_) => toggle(_bands, key),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
