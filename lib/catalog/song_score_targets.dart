import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../core/api.dart';
import '../ui/app_image.dart';
import '../ui/detail.dart';
import 'chart_rates.dart';
import 'deck_state.dart';
import 'song_meta.dart';
import 'song_summary.dart';

const _rankNames = ['', 'E', 'D', 'C', 'B', 'A', 'S', 'SS'];

class SongChartTargets extends StatefulWidget {
  const SongChartTargets({
    super.key,
    required this.api,
    required this.musicId,
    required this.difficulty,
    this.inlineRates,
  });
  final HaneokaApi api;
  final int musicId, difficulty;
  final Map? inlineRates;

  @override
  State<SongChartTargets> createState() => _SongChartTargetsState();
}

class _SongChartTargetsState extends State<SongChartTargets> {
  Future<ChartRateTable>? _table;
  Object? _dataKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = AppScope.of(context).publicDataKey;
    if (key != _dataKey) {
      _dataKey = key;
      _table = null;
    }
  }

  @override
  void didUpdateWidget(covariant SongChartTargets oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) _table = null;
  }

  @override
  Widget build(BuildContext context) {
    final inline = widget.inlineRates;
    final value = (inline?['charts'] as Map?)?['${widget.difficulty}'];
    if (value is Map) {
      return SongScoreTargets(
        rates: ChartRates.fromJson(value),
        greatFactor: (inline?['greatFactor'] as num?)?.toDouble() ?? .8,
        server: widget.api.server,
      );
    }
    return FutureBuilder<ChartRateTable>(
      future: _table ??= ChartRateTable.load(widget.api),
      builder: (_, snapshot) {
        final table = snapshot.data;
        final rates = table?.charts['${widget.musicId}:${widget.difficulty}'];
        return rates == null
            ? const SizedBox.shrink()
            : SongScoreTargets(
                rates: rates,
                greatFactor: table!.greatFactor,
                server: widget.api.server,
              );
      },
    );
  }
}

class SongScoreTargets extends StatefulWidget {
  const SongScoreTargets({
    super.key,
    required this.rates,
    required this.greatFactor,
    required this.server,
  });
  final String server;
  final ChartRates rates;
  final double greatFactor;

  @override
  State<SongScoreTargets> createState() => _SongScoreTargetsState();
}

class _SongScoreTargetsState extends State<SongScoreTargets> {
  final _deck = AnalysisDeckController.instance;

  @override
  void initState() {
    super.initState();
    _deck.addListener(_changed);
    _deck.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _deck.removeListener(_changed);
    super.dispose();
  }

  void _slot(int index, DeckSlot slot) => _deck.set(
    _deck.value.copyWith(
      slots: [
        for (var i = 0; i < _deck.value.slots.length; i++)
          if (i == index) slot else _deck.value.slots[i],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    String label(String key) => t('catalog.analysis.fields.$key');
    final number = NumberFormat.decimalPattern(t.locale);
    final percent = NumberFormat.percentPattern(t.locale)
      ..maximumFractionDigits = 1;
    final deck = _deck.value;
    final rates = widget.rates;
    final orders = slotOrderRates(
      rates,
      deck.slots,
      great: deck.great / 100,
      greatFactor: widget.greatFactor,
    );
    final ranks = rates.ranks.where((row) => row.rank >= 3).toList().reversed;
    Widget fields(List<Widget> children) => LayoutBuilder(
      builder: (_, constraints) {
        final count = constraints.maxWidth >= 700 ? children.length : 2;
        final width = (constraints.maxWidth - 12 * (count - 1)) / count;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
    return DetailSection(
      icon: Symbols.monitoring_rounded,
      title: label('powerNeeded'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              horizontalMargin: 12,
              columns: [
                DataColumn(label: Text(label('deckRank'))),
                for (final key in [
                  'rankScore',
                  'averageOrder',
                  'everyOrder',
                  'bestOrder',
                  'metaDeckReach',
                ])
                  DataColumn(label: Text(label(key)), numeric: true),
              ],
              rows: [
                for (final row in ranks)
                  () {
                    final need = slotPowerNeeded(
                      row.required,
                      orders,
                      rates.notes,
                    );
                    return DataRow(
                      cells: [
                        DataCell(Text(_rankNames[row.rank.clamp(0, 7)])),
                        DataCell(Text(number.format(row.required))),
                        DataCell(Text(number.format(need.mean))),
                        DataCell(Text(number.format(need.every))),
                        DataCell(Text(number.format(need.best))),
                        DataCell(
                          Text(
                            percent.format(
                              slotReach(
                                row.required,
                                deck.power,
                                orders,
                                rates.notes,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }(),
              ],
            ),
          ),
          heading(label('deck')),
          fields([
            _AnalysisNumber(
              label: label('deckPower'),
              value: deck.power.toDouble(),
              min: 1,
              max: 99999999,
              onChanged: (value) =>
                  _deck.set(deck.copyWith(power: value.round())),
            ),
            _AnalysisNumber(
              label: label('deckGreat'),
              value: deck.great.toDouble(),
              max: 100,
              onChanged: (value) =>
                  _deck.set(deck.copyWith(great: value.round())),
            ),
          ]),
          heading(label('deckSkills')),
          fields([
            for (var i = 0; i < deck.slots.length; i++)
              _AnalysisNumber(
                label: '${i + 1}',
                value: deck.slots[i].score + deck.slots[i].perfect,
                max: 1000,
                decimal: true,
                onChanged: (value) => _slot(
                  i,
                  deck.slots[i].perfect > 0 && deck.slots[i].score == 0
                      ? deck.slots[i].copyWith(perfect: value)
                      : deck.slots[i].copyWith(score: value, perfect: 0),
                ),
              ),
          ]),
          heading(label('deckExtension')),
          fields([
            for (var i = 0; i < deck.slots.length; i++)
              _AnalysisNumber(
                label: '${i + 1}',
                value: deck.slots[i].extensionMs / 1000,
                max: 6,
                decimal: true,
                onChanged: (value) => _slot(
                  i,
                  deck.slots[i].copyWith(
                    extensionMs: (value * 4).round() * 250,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: RouteSettings(
                    name: Uri(
                      path: '/catalog/song-meta',
                      queryParameters: {...deck.query, 'server': widget.server},
                    ).toString(),
                  ),
                  builder: (_) => SongMetaScreen(
                    server: widget.server,
                    initialQuery: deck.query,
                  ),
                ),
              ),
              child: Text(label('allCharts')),
            ),
          ),
        ],
      ),
    );
  }
}

class SongRoomScores extends StatefulWidget {
  const SongRoomScores({super.key, required this.ranks, required this.api});
  final List<ScoreRank> ranks;
  final HaneokaApi api;

  @override
  State<SongRoomScores> createState() => _SongRoomScoresState();
}

class _SongRoomScoresState extends State<SongRoomScores> {
  final _scores = List<int?>.filled(5, null);

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    String label(String key) => t('catalog.analysis.fields.$key');
    final number = NumberFormat.decimalPattern(t.locale);
    final played = _scores.whereType<int>().toList();
    final total = played.fold(0, (a, b) => a + b);
    final result = played.isEmpty
        ? null
        : roomRank(widget.ranks, total, played.length);
    return DetailSection(
      icon: Symbols.groups_rounded,
      title: label('gekisouRoomScores'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              horizontalMargin: 12,
              columns: [
                DataColumn(label: Text(label('deckRank'))),
                for (var count = 1; count <= 5; count++)
                  DataColumn(
                    label: Text(
                      count == 1
                          ? label('roomPlayer')
                          : label('roomPlayers')
                                .replaceAll('{count}', '$count'),
                    ),
                    numeric: true,
                  ),
              ],
              rows: [
                for (final row in widget.ranks)
                  DataRow(
                    cells: [
                      DataCell(
                        Semantics(
                          label: _rankNames[row.rank.clamp(0, 7)],
                          image: true,
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: AppImage(
                              candidates: [
                                widget.api
                                    .asset(
                                      '/assets/${widget.api.server}/Assets/AddressableResources/UI/Texture/BandRank/ImgScorerank_${_rankNames[row.rank.clamp(0, 7)]}.png',
                                    )
                                    .toString(),
                              ],
                              localized: false,
                            ),
                          ),
                        ),
                      ),
                      for (var count = 1; count <= 5; count++)
                        DataCell(
                          Text(
                            number.format(
                              roomRequiredScore(row.battleRequired, count),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 12),
            child: Text(
              label('roomScores'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          LayoutBuilder(
            builder: (_, constraints) {
              final count = constraints.maxWidth >= 700 ? 5 : 2;
              final width = (constraints.maxWidth - 12 * (count - 1)) / count;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < 5; i++)
                    SizedBox(
                      width: width,
                      child: TextFormField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: '${i + 1}'),
                        onChanged: (raw) {
                          final value = double.tryParse(raw);
                          setState(
                            () => _scores[i] =
                                value != null && value.isFinite && value >= 0
                                ? value.round()
                                : null,
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          DataGrid(
            cells: [
              (label('roomTotal'), played.isEmpty ? '—' : number.format(total)),
              (
                label('roomRank'),
                result == null ? '—' : _rankNames[result.rank.clamp(0, 7)],
              ),
              (
                label('roomNext'),
                result?.next == null
                    ? '—'
                    : '${_rankNames[result!.next!.rank.clamp(0, 7)]} +${number.format(result.next!.required - total)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalysisNumber extends StatefulWidget {
  const _AnalysisNumber({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.min = 0,
    this.decimal = false,
  });
  final String label;
  final double value, min, max;
  final bool decimal;
  final ValueChanged<double> onChanged;

  @override
  State<_AnalysisNumber> createState() => _AnalysisNumberState();
}

class _AnalysisNumberState extends State<_AnalysisNumber> {
  late final _text = TextEditingController(text: _formatted());
  final _focus = FocusNode();
  String _formatted() => widget.value == widget.value.roundToDouble()
      ? '${widget.value.round()}'
      : '${widget.value}';

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _text.text = _formatted();
  }

  @override
  void didUpdateWidget(covariant _AnalysisNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.value != widget.value) {
      _text.text = _formatted();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    focusNode: _focus,
    keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
    decoration: InputDecoration(labelText: widget.label),
    onChanged: (raw) {
      final value = double.tryParse(raw);
      if (value != null &&
          value.isFinite &&
          value >= widget.min &&
          value <= widget.max) {
        widget.onChanged(value);
      }
    },
  );
}
