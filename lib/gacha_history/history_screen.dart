import 'package:game_data_exporter/gacha_history_analysis.dart'
    show summarizeGachaHistoryMoney;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/detail.dart';
import '../ui/theme.dart';
import '../ui/gacha_prize_card.dart';
import 'history_view.dart';
import 'history_report.dart';
import 'history_chart.dart';

enum GachaHistoryImportSource { saved, files, adb }

class GachaHistoryScreen extends StatefulWidget {
  const GachaHistoryScreen({
    super.key,
    this.cloudSignedIn = false,
    this.cloudBusy = false,
    this.cloudLinked = false,
    this.cloudRefreshPending = false,
    this.cloudErrorCode = "",
    this.onCloudLink,
    this.onCloudSync,
    this.onCloudRefresh,
    this.accounts = const [],
    this.historyKinds = const [],
    this.selectedHistoryKind = '',
    this.onHistoryKindChanged,
    this.pools = const [],
    this.batches = const [],
    this.selectedAccountKey = '',
    this.busy = false,
    this.historyLoaded = false,
    this.catalogLoading = false,
    this.catalogError,
    this.onCatalogRetry,
    this.error,
    this.onAccountChanged,
    this.onImport,
    this.onImportSource,
    this.availableImportSources = const [
      GachaHistoryImportSource.saved,
      GachaHistoryImportSource.files,
    ],
    this.onRefresh,
    this.onExport,
    this.onOpenCard,
    this.currencyConversion,
    this.onConversionChanged,
    this.onExportImage,
  });
  final bool cloudSignedIn, cloudBusy, cloudLinked, cloudRefreshPending;
  final String? cloudErrorCode;
  final ValueChanged<bool>? onCloudLink;
  final VoidCallback? onCloudSync, onCloudRefresh;
  final List<GachaHistoryAccount> accounts;
  final List<GachaHistoryPool> pools;
  final List<GachaHistoryBatch> batches;
  final String selectedAccountKey;
  final bool busy, historyLoaded, catalogLoading;
  final String? catalogError;
  final VoidCallback? onCatalogRetry;
  final String? error;
  final ValueChanged<String>? onAccountChanged,
      onRefresh,
      onOpenCard,
      onHistoryKindChanged;
  final List<String> historyKinds;
  final String selectedHistoryKind;
  final VoidCallback? onImport;
  final ValueChanged<GachaHistoryImportSource>? onImportSource;
  final List<GachaHistoryImportSource> availableImportSources;
  final ValueChanged<GachaHistoryExport>? onExport;
  final GachaHistoryConversion? currencyConversion;
  final ValueChanged<GachaHistoryConversion>? onConversionChanged;
  final GachaHistoryImageExporter? onExportImage;

  @override
  State<GachaHistoryScreen> createState() => _GachaHistoryScreenState();
}

class _GachaHistoryScreenState extends State<GachaHistoryScreen> {
  VoidCallback? get _importAction =>
      widget.onImportSource != null ? _chooseImportSource : widget.onImport;
  Future<void> _chooseImportSource() async {
    final source = await showModalBottomSheet<GachaHistoryImportSource>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _t('importSource'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final source in widget.availableImportSources)
              ListTile(
                leading: Icon(switch (source) {
                  GachaHistoryImportSource.saved =>
                    Symbols.account_circle_rounded,
                  GachaHistoryImportSource.files => Symbols.folder_open_rounded,
                  GachaHistoryImportSource.adb => Symbols.usb_rounded,
                }),
                title: Text(
                  _t(switch (source) {
                    GachaHistoryImportSource.saved => 'savedSource',
                    GachaHistoryImportSource.files => 'filesSource',
                    GachaHistoryImportSource.adb => 'adbSource',
                  }),
                ),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.pop(context, source),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (source != null && mounted) widget.onImportSource?.call(source);
  }

  final _filters = <String, Set<String>>{
    'category': {},
    'pool': {},
    'kind': {},
    'rarity': {},
    'pickup': {},
  };
  final _expanded = <String>{};
  bool _expansionReady = false;
  List<GachaHistoryPool>? _indexedPools;
  Map<String, GachaHistoryPool> _poolIndex = {};
  String _query = '', _view = 'grid', _albumKind = 'all';
  bool _oldest = false, _onlyPickup = false, _allCards = false;
  DateTime? _from, _to;
  String _t(String key, [Map<String, Object?> values = const {}]) =>
      AppScope.of(context).text('catalog.gachaHistory.$key', '', values);
  String get _locale => AppScope.of(context).text.locale;
  String _percent(num value, num total) =>
      total == 0 ? "—" : NumberFormat("0.##%", _locale).format(value / total);
  String _number(num value) =>
      NumberFormat.decimalPattern(_locale).format(value);
  int get _offsetMinutes {
    final account = widget.accounts
        .where((row) => row.key == widget.selectedAccountKey)
        .firstOrNull;
    return account?.offsetMinutes ??
        ({
              'jp': 540,
              'global-hmt': 480,
              'global-en': 0,
              'global-kr': 540,
            }[account?.server] ??
            480);
  }

  DateTime _inServerTime(DateTime date) =>
      date.toUtc().add(Duration(minutes: _offsetMinutes));
  String _filterDay(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
  Map<String, Object?> _analysisData(List<GachaHistoryBatch> batches) =>
      historyAnalysis(batches, _offsetMinutes);
  String _day(DateTime? date) => date == null
      ? "unknown"
      : DateFormat('yyyy-MM-dd').format(_inServerTime(date));
  Map<String, GachaHistoryPool> get _pools {
    if (!identical(_indexedPools, widget.pools)) {
      _indexedPools = widget.pools;
      _poolIndex = {for (final pool in widget.pools) pool.id: pool};
    }
    return _poolIndex;
  }

  List<GachaHistoryBatch> get _accountBatches => widget.batches
      .where((batch) => batch.accountKey == widget.selectedAccountKey)
      .toList();
  bool _matches(String axis, String value) =>
      _filters[axis]!.isEmpty || _filters[axis]!.contains(value);
  List<GachaHistoryPrize> _prizes(GachaHistoryBatch batch) {
    final query = _query.trim().toLowerCase();
    final poolMatches = (_pools[batch.poolId]?.name ?? '')
        .toLowerCase()
        .contains(query);
    return batch.prizes
        .where(
          (prize) =>
              _matches(
                'pickup',
                prize.pickup == null
                    ? 'unknown'
                    : prize.pickup!
                    ? 'yes'
                    : 'no',
              ) &&
              _matches('kind', prize.kind) &&
              _matches('rarity', '${prize.rarity}') &&
              (query.isEmpty ||
                  poolMatches ||
                  prize.name.toLowerCase().contains(query)),
        )
        .toList();
  }

  List<GachaHistoryBatch> get _scoped => _accountBatches.where((batch) {
    final day = _day(batch.pulledAt);
    return _matches('pool', batch.poolId) &&
        _matches('category', _pools[batch.poolId]?.category ?? '') &&
        (_from == null ||
            (batch.pulledAt != null &&
                day.compareTo(_filterDay(_from!)) >= 0)) &&
        (_to == null ||
            (batch.pulledAt != null && day.compareTo(_filterDay(_to!)) <= 0));
  }).toList();
  List<GachaHistoryBatch> get _filtered {
    final result = _scoped
        .where(
          (batch) =>
              (_query.trim().isEmpty &&
                  _filters['kind']!.isEmpty &&
                  _filters['rarity']!.isEmpty &&
                  _filters['pickup']!.isEmpty) ||
              _prizes(batch).isNotEmpty,
        )
        .toList();
    final order = {for (var i = 0; i < result.length; i++) result[i]: i};
    result.sort((a, b) {
      if (a.pulledAt == null) {
        return b.pulledAt == null ? order[a]! - order[b]! : 1;
      }
      if (b.pulledAt == null) return -1;
      final timeOrder = a.pulledAt!.compareTo(b.pulledAt!);
      return timeOrder == 0
          ? order[a]! - order[b]!
          : timeOrder * (_oldest ? 1 : -1);
    });
    return result;
  }

  int get _filterCount =>
      _filters.values.fold(0, (sum, values) => sum + values.length) +
      (_from == null ? 0 : 1) +
      (_to == null ? 0 : 1);
  void _reset() {
    for (final values in _filters.values) {
      values.clear();
    }
    _from = null;
    _to = null;
  }

  @override
  void didUpdateWidget(covariant GachaHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedAccountKey != widget.selectedAccountKey) {
      _expanded.clear();
      _expansionReady = false;
      _reset();
    }
  }

  List<(String, String, int)> _options(String axis) {
    final entries = <String, (String, int)>{};
    for (final batch in _accountBatches) {
      final pool = _pools[batch.poolId];
      if (axis == 'pool' || axis == 'category') {
        final value = axis == 'pool' ? batch.poolId : pool?.category;
        if (value != null && value.isNotEmpty) {
          entries[value] = (
            axis == 'pool' ? pool?.name ?? value : value,
            (entries[value]?.$2 ?? 0) + 1,
          );
        }
      } else {
        for (final prize in batch.prizes) {
          if (axis == 'pickup' && prize.pickup == null) continue;
          final value = axis == 'pickup'
              ? (prize.pickup == null
                    ? 'unknown'
                    : prize.pickup!
                    ? 'yes'
                    : 'no')
              : axis == 'kind'
              ? prize.kind
              : '${prize.rarity}';
          final label = axis == 'pickup'
              ? _t(prize.pickup == true ? 'pickup' : 'nonPickup')
              : axis == 'kind'
              ? _t(prize.kind)
              : prize.rarityLabel;
          if (label.isNotEmpty) {
            entries[value] = (
              label,
              (entries[value]?.$2 ?? 0) + prize.quantity,
            );
          }
        }
      }
    }
    return entries.entries
        .map((entry) => (entry.key, entry.value.$1, entry.value.$2))
        .toList();
  }

  Future<void> _showFilters() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        void change(VoidCallback action) {
          setState(action);
          update(() {});
        }

        return SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('filter'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: () => change(_reset),
                      child: Text(_t('reset')),
                    ),
                    IconButton(
                      tooltip: _t('close'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Symbols.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final axis in _filters.keys)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(axis),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final option in _options(axis))
                                  FilterChip(
                                    label: Text(
                                      '${option.$2} · ${_number(option.$3)}',
                                    ),
                                    selected: _filters[axis]!.contains(
                                      option.$1,
                                    ),
                                    onSelected: (selected) => change(() {
                                      if (selected) {
                                        _filters[axis]!.add(option.$1);
                                      } else {
                                        _filters[axis]!.remove(option.$1);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    for (final start in [true, false])
                      ListTile(
                        enabled: _accountBatches.any(
                          (batch) => batch.pulledAt != null,
                        ),
                        title: Text(_t(start ? 'from' : 'to')),
                        subtitle: Text(
                          (start ? _from : _to) == null
                              ? '—'
                              : DateFormat.yMMMd(_locale)
                                    .format((start ? _from : _to)!),
                        ),
                        trailing: const Icon(Symbols.calendar_month_rounded),
                        onTap: () async {
                          final dates =
                              _accountBatches
                                  .map(
                                    (batch) => batch.pulledAt == null
                                        ? null
                                        : _inServerTime(batch.pulledAt!),
                                  )
                                  .whereType<DateTime>()
                                  .toList()
                                ..sort();
                          final first = dates.isEmpty
                                  ? DateTime.now()
                                  : dates.first,
                              last = dates.isEmpty
                                  ? DateTime.now()
                                  : dates.last;
                          final value = await showDatePicker(
                            context: context,
                            initialDate:
                                (start ? _from : _to) ?? (start ? first : last),
                            firstDate: start ? first : _from ?? first,
                            lastDate: start ? _to ?? last : last,
                          );
                          if (value != null && mounted && context.mounted) {
                            change(() {
                              if (start) {
                                _from = value;
                              } else {
                                _to = value;
                              }
                            });
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final filtered = _filtered, scoped = _scoped;
    final prizes = scoped.expand((batch) => batch.prizes).toList();
    final groups = <String, List<GachaHistoryBatch>>{};
    for (final batch in filtered) {
      groups.putIfAbsent(_day(batch.pulledAt), () => []).add(batch);
    }
    final days = groups.keys.toList();
    if (!_expansionReady && days.isNotEmpty) {
      if (days.first != "unknown") _expanded.add(days.first);
      _expansionReady = true;
    }
    final rarity = <String, int>{};
    for (final prize in prizes) {
      if (prize.kind != 'item' && prize.rarityLabel.isNotEmpty) {
        rarity.update(
          prize.rarityLabel,
          (count) => count + prize.quantity,
          ifAbsent: () => prize.quantity,
        );
      }
    }
    int count(String kind) => prizes
        .where((prize) => prize.kind == kind)
        .fold(0, (sum, prize) => sum + prize.quantity);
    final unknownDraws = scoped
        .where((batch) => batch.drawCount == null)
        .length;
    final metrics = <(String, String)>[
      (
        _t('total'),
        scoped.any((batch) => batch.drawCount != null)
            ? _number(
                scoped.fold<int>(
                  0,
                  (sum, batch) => sum + (batch.drawCount ?? 0),
                ),
              )
            : "—",
      ),
      (_t('member'), _number(count('member'))),
      (_t('support'), _number(count('support'))),
      (
        _t('pickup'),
        (prizes.isNotEmpty && prizes.every((prize) => prize.pickup != null)) ||
                prizes.any((prize) => prize.pickup == true)
            ? _number(
                prizes
                    .where((prize) => prize.pickup == true)
                    .fold<int>(0, (sum, prize) => sum + prize.quantity),
              )
            : '—',
      ),
    ];
    return ShellPage(
      title: _t('title'),
      status: Text(_t('batches', {'count': filtered.length})),
      search: ShellSearch(
        label: _t('search'),
        onChanged: (value) => setState(() => _query = value),
      ),
      marks: _filterCount == 0
          ? null
          : Wrap(
              spacing: 4,
              children: [
                for (final axis in _filters.keys)
                  for (final value in _filters[axis]!)
                    InputChip(
                      label: Text(
                        _options(axis)
                                .where((option) => option.$1 == value)
                                .firstOrNull
                                ?.$2 ??
                            value,
                      ),
                      onDeleted: () =>
                          setState(() => _filters[axis]!.remove(value)),
                    ),
                if (_from != null)
                  InputChip(
                    label: Text('${_t('from')} · ${_filterDay(_from!)}'),
                    onDeleted: () => setState(() => _from = null),
                  ),
                if (_to != null)
                  InputChip(
                    label: Text('${_t('to')} · ${_filterDay(_to!)}'),
                    onDeleted: () => setState(() => _to = null),
                  ),
              ],
            ),
      marksExtent: _filterCount == 0 ? 0 : 160,
      actions: [
        BarAction(
          icon: Symbols.image_rounded,
          label: _t('exportImage'),
          onPressed: scoped.isEmpty
              ? null
              : () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => GachaHistoryImagePreview(
                    report: _report(scoped),
                    onExport: widget.onExportImage,
                  ),
                ),
        ),
        BarAction(
          icon: Symbols.file_upload_rounded,
          label: _t('import'),
          onPressed: widget.busy ? null : _importAction,
        ),
        BarAction(
          icon: Symbols.refresh_rounded,
          label: _t('refresh'),
          onPressed:
              widget.busy ||
                  widget.selectedAccountKey.isEmpty ||
                  widget.onRefresh == null
              ? null
              : () => widget.onRefresh!(widget.selectedAccountKey),
        ),
        BarAction(
          icon: Symbols.file_download_rounded,
          label: _t('export'),
          onPressed: filtered.isEmpty || widget.onExport == null
              ? null
              : () => widget.onExport!(
                  GachaHistoryExport(
                    accountKey: widget.selectedAccountKey,
                    historyKind: widget.selectedHistoryKind,
                    batches: filtered,
                  ),
                ),
        ),
        BarAction(
          icon: Symbols.swap_vert_rounded,
          label: _t(_oldest ? 'oldest' : 'newest'),
          selected: _oldest,
          onPressed: () => setState(() => _oldest = !_oldest),
        ),
        BarAction(
          icon: Symbols.filter_list_rounded,
          label: _t('filter'),
          badge: _filterCount,
          onPressed: _showFilters,
        ),
        BarAction.choice(
          label: AppScope.of(context).text('common.actions.view'),
          options: [
            for (final view in [
              ('grid', Symbols.grid_view_rounded),
              ('list', Symbols.table_rows_rounded),
              ('table', Symbols.view_list_rounded),
            ])
              BarChoice(
                icon: view.$2,
                label: AppScope.of(context).text('common.layout.${view.$1}'),
                selected: _view == view.$1,
                onSelected: () => setState(() => _view = view.$1),
              ),
          ],
        ),
      ],
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownMenu<String>(
                            key: ValueKey(widget.selectedAccountKey),
                            initialSelection:
                                widget.accounts.any(
                                  (account) =>
                                      account.key == widget.selectedAccountKey,
                                )
                                ? widget.selectedAccountKey
                                : null,
                            expandedInsets: EdgeInsets.zero,
                            label: Text(_t('account')),
                            hintText: _t('selectAccount'),
                            enabled:
                                !widget.busy && widget.onAccountChanged != null,
                            requestFocusOnTap: false,
                            dropdownMenuEntries: [
                              for (final account in widget.accounts)
                                DropdownMenuEntry(
                                  value: account.key,
                                  label: [account.serverLabel, account.label]
                                      .where((value) => value.isNotEmpty)
                                      .join(' · '),
                                ),
                            ],
                            onSelected: (value) {
                              if (value != null) {
                                widget.onAccountChanged?.call(value);
                              }
                            },
                          ),
                          if (widget.historyKinds.length > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: DropdownMenu<String>(
                                key: ValueKey(widget.selectedHistoryKind),
                                initialSelection: widget.selectedHistoryKind,
                                label: Text(_t('historyKind')),
                                expandedInsets: EdgeInsets.zero,
                                requestFocusOnTap: false,
                                dropdownMenuEntries: [
                                  for (final kind in widget.historyKinds)
                                    DropdownMenuEntry(
                                      value: kind,
                                      label: _t(
                                        kind == 'legacy'
                                            ? 'historyLegacy'
                                            : 'historyExecution',
                                      ),
                                    ),
                                ],
                                onSelected: (kind) {
                                  if (kind != null) {
                                    widget.onHistoryKindChanged?.call(kind);
                                  }
                                },
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _cloudControls(),
                          ),
                          if (widget.onRefresh != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: FilledButton.icon(
                                onPressed:
                                    widget.busy ||
                                        widget.selectedAccountKey.isEmpty
                                    ? null
                                    : () => widget.onRefresh!(
                                        widget.selectedAccountKey,
                                      ),
                                icon: const Icon(Symbols.history_rounded),
                                label: Text(_t('readHistory')),
                              ),
                            ),
                          if (widget.catalogLoading ||
                              widget.catalogError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Semantics(
                                liveRegion: true,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      widget.catalogLoading
                                          ? _t('catalogLoading')
                                          : widget.catalogError!,
                                    ),
                                    if (widget.catalogError != null &&
                                        widget.onCatalogRetry != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: FilledButton.tonalIcon(
                                          onPressed: widget.catalogLoading
                                              ? null
                                              : widget.onCatalogRetry,
                                          icon: const Icon(
                                            Symbols.refresh_rounded,
                                          ),
                                          label: Text(_t('retryCatalog')),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          SizedBox(
                            height: 32,
                            child: Align(
                              alignment: AlignmentDirectional.bottomStart,
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  widget.error ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 4,
                    child: widget.busy
                        ? LinearProgressIndicator(semanticsLabel: _t('loading'))
                        : null,
                  ),
                  if (scoped.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: DetailSection(
                        icon: Symbols.monitoring_rounded,
                        title: _t('overview'),
                        child: Column(
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final columns = constraints.maxWidth < 600
                                    ? 2
                                    : 4;
                                return Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    for (final metric in metrics)
                                      SizedBox(
                                        width:
                                            (constraints.maxWidth -
                                                (columns - 1) * 16) /
                                            columns,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              metric.$1,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge,
                                            ),
                                            Text(
                                              metric.$2,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineLarge,
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                            if (unknownDraws > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    _t('unknownDraws', {'count': unknownDraws}),
                                  ),
                                ),
                              ),
                            if (rarity.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    for (final entry in rarity.entries)
                                      Chip(
                                        label: Text(
                                          '${entry.key} · ${_number(entry.value)}',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (scoped.isNotEmpty) _analysis(scoped, chartsOnly: true),
                  if (widget.historyLoaded && scoped.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: DetailSection(
                        icon: Symbols.payments_rounded,
                        title: _t('cost'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final metric in _costMetrics(scoped))
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(metric.$1)),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        metric.$2,
                                        textAlign: TextAlign.end,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (widget.currencyConversion
                                case final conversion?)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: DetailFold(
                                  title: _t('conversion'),
                                  child: _GachaConversionEditor(
                                    key: ValueKey(widget.selectedAccountKey),
                                    conversion: conversion,
                                    onChanged: widget.onConversionChanged,
                                    currencyLabel: _t('currency'),
                                    freePriceLabel: _t('freeUnitGemPrice'),
                                    paidPriceLabel: _t('paidUnitGemPrice'),
                                    applyLabel: _t('applyPrice'),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (scoped.isNotEmpty) _analysis(scoped),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(
                            Symbols.history_rounded,
                            size: 40,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _t(
                              widget.selectedAccountKey.isEmpty
                                  ? 'emptyAccount'
                                  : _accountBatches.isEmpty
                                  ? (widget.historyLoaded
                                        ? 'empty'
                                        : 'historyNotLoaded')
                                  : 'noResults',
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          if (widget.accounts.isEmpty && _importAction != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: FilledButton.icon(
                                onPressed: widget.busy ? null : _importAction,
                                icon: const Icon(Symbols.file_upload_rounded),
                                label: Text(_t('import')),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (filtered.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        _t('records'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.builder(
              itemCount: days.length,
              itemBuilder: (context, index) {
                final day = days[index], batches = groups[day]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ExpansionTile(
                      key: ValueKey('${widget.selectedAccountKey}:$day'),
                      initiallyExpanded: _expanded.contains(day),
                      onExpansionChanged: (expanded) => setState(() {
                        if (expanded) {
                          _expanded.add(day);
                        } else {
                          _expanded.remove(day);
                        }
                      }),
                      title: Text(
                        day == "unknown"
                            ? _t("unknownTime")
                            : DateFormat.yMMMMd(_locale)
                                  .format(DateTime.parse(day)),
                      ),
                      subtitle: Text(_drawSummary(batches)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Corner.medium),
                      ),
                      collapsedShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Corner.medium),
                      ),
                      childrenPadding: const EdgeInsets.all(16),
                      children: _expanded.contains(day)
                          ? [
                              for (final batch in batches)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        _pools[batch.poolId]?.name ??
                                            batch.poolId,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      Text(
                                        '${batch.pulledAt == null ? _t("unknownTime") : DateFormat.Hm(_locale).format(_inServerTime(batch.pulledAt!))} · ${batch.drawCount == null ? _t("unknownCount") : _t('draws', {'count': batch.drawCount})}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      const SizedBox(height: 12),
                                      _renderPrizes(_prizes(batch)),
                                    ],
                                  ),
                                ),
                            ]
                          : const [],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _costMetrics(List<GachaHistoryBatch> batches) {
    final costs = (_analysisData(batches)['cost'] as Map)
        .cast<String, Object?>();
    String number(Map value) => value['value'] == null
        ? '—'
        : '${value['partial'] == true ? "≥ " : ""}${_number(value['value'] as num)}';
    final metrics = [
      for (final key in ['freeGems', 'paidGems', 'tickets'])
        (_t(key), number(costs[key] as Map)),
    ];
    final conversion = widget.currencyConversion;
    if (conversion != null) {
      final amounts = summarizeGachaHistoryMoney(
        costs,
        freeUnitGemPrice: conversion.freeUnitGemPrice,
        paidUnitGemPrice: conversion.paidUnitGemPrice,
      );
      String money(Map value) => value['value'] == null
          ? '—'
          : '${value['partial'] == true ? "≥ " : ""}${NumberFormat.simpleCurrency(locale: _locale, name: conversion.currencyCode).format(value['value'])}';
      metrics.addAll([
        (_t('freeValue'), money(amounts['freeGems'] as Map)),
        (_t('paidValue'), money(amounts['paidGems'] as Map)),
      ]);
    }
    return metrics;
  }

  GachaHistoryReportData _report(List<GachaHistoryBatch> batches) {
    final prizes = batches.expand((batch) => batch.prizes).toList();
    final known = batches.where((batch) => batch.drawCount != null).toList();
    final metrics = <(String, String)>[
      (
        _t('total'),
        known.isEmpty
            ? '—'
            : _number(
                known.fold<int>(0, (sum, batch) => sum + batch.drawCount!),
              ),
      ),
      for (final kind in ['member', 'support'])
        (
          _t(kind),
          _number(
            prizes
                .where((prize) => prize.kind == kind)
                .fold<int>(0, (sum, prize) => sum + prize.quantity),
          ),
        ),
      (_t('pickup'), '${_analysisData(batches)['pickup']}'),
    ];
    final stats = _analysisData(batches);
    List<Map> rows(Object? value) => (value as List).cast<Map>();
    final groups = <GachaHistoryReportGroup>[];
    for (final pool in rows(stats['pools'])) {
      final selected = batches
          .where((batch) => batch.poolId == pool['poolId'])
          .toList();
      final cardMap = {
        for (final batch in selected)
          for (final prize in batch.prizes) '${prize.kind}:${prize.id}': prize,
      };
      final poolCards = rows(_analysisData(selected)['cards']);
      for (final kind in ['member', 'support']) {
        groups.add(
          GachaHistoryReportGroup(
            label:
                '${_pools[pool['poolId']]?.name ?? pool['poolId']} · ${_t(kind)}',
            imageUrl: _pools[pool['poolId']]?.imageUrl,
            cards: [
              for (final card in poolCards.where(
                (card) =>
                    card['kind'] == kind &&
                    ([4, 10, 20].contains(
                          int.tryParse('${cardMap[card['key']]!.rarity}'),
                        ) ||
                        (card['pickup'] as num) > 0),
              ))
                GachaHistoryReportCard(
                  name: cardMap[card['key']]!.name,
                  kindLabel: _t(kind),
                  quantity: (card['count'] as num).toInt(),
                  imageUrl: cardMap[card['key']]!.imageUrl,
                  attributeImageUrl: cardMap[card['key']]!.attributeImageUrl,
                  rarityImageUrl: cardMap[card['key']]!.rarityImageUrl,
                  rarity: int.tryParse('${cardMap[card['key']]!.rarity}') ?? 0,
                  pickup: (card['pickup'] as num).toInt(),
                ),
            ],
          ),
        );
      }
    }
    final charts = [
      for (final kind in rows(
        stats['kinds'],
      ).where((kind) => kind['kind'] == 'member' || kind['kind'] == 'support'))
        GachaHistoryChart(
          title: '${_t(kind['kind'] as String)} · ${_t('rarityDistribution')}',
          caption:
              '${_t(kind['kind'] as String)} ${_number(kind['total'] as num)} · ${_t('ssrRate')} ${_percent(kind['ssr'] as num, kind['total'] as num)}',
          labels: [_t('nonPickup'), _t('pickup')],
          rows: [
            for (final row in rows(kind['distribution']).where(
              (row) =>
                  ['SSR', 'SR', 'R'].contains(row['rarity']) ||
                  ((row['count'] as num) > 0 &&
                      row['rarity'] != 'item' &&
                      row['rarity'] != 'unknown'),
            ))
              (
                '${row['rarity']} · ${_percent(row['count'] as num, kind['total'] as num)}',
                [row['nonPickup'] as num, row['pickup'] as num],
              ),
          ],
        ),
    ];
    final dates =
        batches
            .map(
              (batch) => batch.pulledAt == null
                  ? null
                  : _inServerTime(batch.pulledAt!),
            )
            .whereType<DateTime>()
            .toList()
          ..sort();
    final scope = [
      dates.isEmpty
          ? _t('unknownTime')
          : '${DateFormat.yMMMd(_locale).format(dates.first)} – ${DateFormat.yMMMd(_locale).format(dates.last)}',
      if (dates.isNotEmpty && dates.length != batches.length) _t('unknownTime'),
    ];
    return GachaHistoryReportData(
      title: _t('title'),
      scope: scope,
      metrics: metrics,
      groups: groups,
      charts: charts,
    );
  }

  Widget _analysis(List<GachaHistoryBatch> batches, {bool chartsOnly = false}) {
    final stats = _analysisData(batches);
    List<Map> rows(Object? value) => (value as List).cast<Map>();
    final progress = rows(historyProgress(batches)['pools']);
    final kinds = rows(stats['kinds']),
        pools = rows(stats['pools']),
        days = rows(stats['days']);
    final cards = {
      for (final batch in batches)
        for (final prize in batch.prizes) '${prize.kind}:${prize.id}': prize,
    };
    final charts = <Widget>[
      for (final kind in kinds.where(
        (kind) => kind['kind'] == 'member' || kind['kind'] == 'support',
      ))
        GachaHistoryChart(
          title: '${_t(kind['kind'] as String)} · ${_t('rarityDistribution')}',
          caption:
              '${_t(kind['kind'] as String)} ${_number(kind['total'] as num)} · ${_t('ssrRate')} ${_percent(kind['ssr'] as num, kind['total'] as num)}',
          labels: [_t('nonPickup'), _t('pickup')],
          rows: [
            for (final row in rows(kind['distribution']).where(
              (row) =>
                  ['SSR', 'SR', 'R'].contains(row['rarity']) ||
                  ((row['count'] as num) > 0 &&
                      row['rarity'] != 'item' &&
                      row['rarity'] != 'unknown'),
            ))
              (
                '${row['rarity']} · ${_percent(row['count'] as num, kind['total'] as num)}',
                [row['nonPickup'] as num, row['pickup'] as num],
              ),
          ],
        ),
      GachaHistoryChart(
        title: _t('dailyTrend'),
        details: [for (final day in days) '${_t('pickup')} ${day['pickup']}'],
        labels: [_t('member'), _t('support'), _t('item')],
        rows: [
          for (final day in days)
            (
              '${day['day'] ?? _t('unknownTime')}',
              [
                day['member'] as num,
                day['support'] as num,
                day['other'] as num,
              ],
            ),
        ],
      ),
      GachaHistoryChart(
        title: _t('poolComposition'),
        labels: [_t('member'), _t('support'), _t('item')],
        rows: [
          for (final pool in pools)
            (
              _pools['${pool['poolId']}']?.name ?? '${pool['poolId']}',
              [
                pool['member'] as num,
                pool['support'] as num,
                pool['other'] as num,
              ],
            ),
        ],
      ),
    ];
    if (chartsOnly) {
      return LayoutBuilder(
        builder: (context, box) => Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final chart in charts)
              SizedBox(
                width: box.maxWidth >= 720
                    ? (box.maxWidth - 16) / 2
                    : box.maxWidth,
                child: chart,
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(_t('luck'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final pool in pools)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card.filled(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _poolHeading(
                      '${pool['poolId']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        for (final value in <(String, String)>[
                          (_t('total'), '${pool['total']}'),
                          (
                            'SSR / EX / BD',
                            '${pool['high']} · ${pool['observedHighRate'] == null ? '—' : NumberFormat.percentPattern(_locale).format(pool['observedHighRate'])}',
                          ),
                          (
                            _t('expected'),
                            pool['expectedHigh'] == null
                                ? '—'
                                : NumberFormat(
                                    '0.##',
                                    _locale,
                                  ).format(pool['expectedHigh']),
                          ),
                          (
                            _t('difference'),
                            pool['delta'] == null
                                ? '—'
                                : NumberFormat(
                                    '+0.##;-0.##',
                                    _locale,
                                  ).format(pool['delta']),
                          ),
                          (_t('pickup'), '${pool['pickup']}'),
                        ])
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                value.$1,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              Text(
                                value.$2,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                      ],
                    ),
                    _exchangeProgress(_pools['${pool['poolId']}']),
                    _progressPanel(
                      progress
                          .where((row) => row['poolId'] == pool['poolId'])
                          .firstOrNull,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _t('highlights'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            FilterChip(
              label: Text(_t('allCards')),
              selected: _allCards,
              onSelected: (value) => setState(() => _allCards = value),
            ),
            FilterChip(
              label: Text(_t('onlyPickup')),
              selected: _onlyPickup,
              onSelected: (value) => setState(() => _onlyPickup = value),
            ),
          ],
        ),
        SegmentedButton<String>(
          segments: [
            for (final kind in ['all', 'member', 'support'])
              ButtonSegment(
                value: kind,
                label: Text(_t(kind == 'all' ? 'allKinds' : kind)),
              ),
          ],
          selected: {_albumKind},
          showSelectedIcon: false,
          onSelectionChanged: (values) =>
              setState(() => _albumKind = values.single),
        ),
        for (final pool in pools) ...[
          const SizedBox(height: 16),
          _poolHeading(
            '${pool['poolId']}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final kind in [
            'member',
            'support',
          ].where((kind) => _albumKind == 'all' || _albumKind == kind)) ...[
            const SizedBox(height: 16),
            Text(_t(kind), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, box) {
                final columns = (box.maxWidth / (kind == 'support' ? 148 : 84))
                    .floor()
                    .clamp(2, 10);
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final card
                        in rows(
                          _analysisData(
                            batches
                                .where(
                                  (batch) => batch.poolId == pool['poolId'],
                                )
                                .toList(),
                          )['cards'],
                        ).where(
                          (card) =>
                              card['kind'] == kind &&
                              (_allCards ||
                                  [4, 10, 20].contains(
                                    int.tryParse(
                                      '${cards[card['key']]!.rarity}',
                                    ),
                                  ) ||
                                  (card['pickup'] as num) > 0) &&
                              (!_onlyPickup || (card['pickup'] as num) > 0),
                        ))
                      SizedBox(
                        width: (box.maxWidth - (columns - 1) * 8) / columns,
                        child: GachaPrizeCard(
                          label:
                              '${cards[card['key']]!.name} · ×${card['count']} · ${_t('pickup')} ${card['pickup']}',
                          rarityValue:
                              int.tryParse('${cards[card['key']]!.rarity}') ??
                              0,
                          image: cards[card['key']]!.imageUrl,
                          attribute: cards[card['key']]!.attributeImageUrl,
                          rarity: cards[card['key']]!.rarityImageUrl,
                          aspectRatio: kind == 'member' ? 3 / 4 : 16 / 9,
                          count: (card['count'] as num).toInt(),
                          pickup: (card['pickup'] as num) > 0,
                          pickupCount: (card['pickup'] as num).toInt(),
                          onTap: _open(cards[card['key']]!),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _poolHeading(String id, {TextStyle? style}) {
    final pool = _pools[id];
    return Row(
      children: [
        if (pool?.imageUrl case final image?) ...[
          SizedBox(
            width: 96,
            height: 48,
            child: AppImage(
              candidates: [image],
              placeholder: const Icon(Symbols.photo_library_rounded),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(child: Text(pool?.name ?? id, style: style)),
      ],
    );
  }

  Widget _cloudControls() {
    final disabled =
        widget.busy || widget.cloudBusy || widget.selectedAccountKey.isEmpty;
    const errors = <String, String>{
      'authentication_required': 'cloudSignIn',
      'email_verification_required': 'cloudVerifyEmail',
      'account_restricted': 'cloudAccountRestricted',
      'history_too_large': 'cloudTooLarge',
      'history_account_limit': 'cloudAccountLimit',
      'history_account_mismatch': 'cloudAccountMismatch',
      'history_server_mismatch': 'cloudServerMismatch',
      'history_session_expired': 'errorSessionExpired',
      'history_network_error': 'cloudNetworkError',
      'history_cloud_unavailable': 'cloudUnavailable',
    };
    final error = errors[widget.cloudErrorCode];
    return DetailFold(
      title: _t('cloudTitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.cloudSignedIn ||
              [
                'authentication_required',
                'email_verification_required',
                'account_restricted',
              ].contains(widget.cloudErrorCode))
            FilledButton.tonal(
              onPressed: () => ShellScope.of(context)?.navigate('/account'),
              child: Text(
                _t(widget.cloudSignedIn ? 'cloudAccount' : 'cloudSignIn'),
              ),
            ),
          if (widget.cloudSignedIn)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: disabled || widget.onCloudLink == null
                      ? null
                      : () => widget.onCloudLink!(!widget.cloudLinked),
                  child: Text(
                    _t(widget.cloudLinked ? 'cloudUnlink' : 'cloudLink'),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: disabled || !widget.cloudLinked
                      ? null
                      : widget.onCloudSync,
                  child: Text(
                    _t(widget.cloudBusy ? 'cloudSyncing' : 'cloudSync'),
                  ),
                ),
                FilledButton.tonal(
                  onPressed:
                      disabled ||
                          !widget.cloudLinked ||
                          widget.cloudRefreshPending
                      ? null
                      : widget.onCloudRefresh,
                  child: Text(
                    _t(
                      widget.cloudRefreshPending
                          ? 'cloudRefreshPending'
                          : 'cloudRefresh',
                    ),
                  ),
                ),
              ],
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _t(error),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _exchangeProgress(GachaHistoryPool? pool) {
    final targets = pool?.exchangeTargets ?? const <Map<String, Object?>>[];
    if (targets.isEmpty) return const SizedBox.shrink();
    final groups = <String, List<Map<String, Object?>>>{};
    for (final target in targets) {
      final reward = target['reward'] as Map;
      final key = [
        reward['resourceType'],
        target['pointCost'],
        target['basePointCost'],
        target['pointBalance'],
        target['pointsNeeded'],
        target['additionalDrawsNeeded'],
        target['remainingExchangeLimit'],
        target['resetType'],
      ].join('|');
      groups.putIfAbsent(key, () => []).add(target);
    }
    return DetailFold(
      title: _t('exchangeProgress'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in groups.values)
            Builder(
              builder: (context) {
                final target = group.first;
                final reward = target['reward'] as Map;
                final cost = target['pointCost'] as num?,
                    balance = target['pointBalance'] as num?;
                final facts = <String, num>{
                  cost == null ? 'basePointCost' : 'pointCost':
                      cost ?? target['basePointCost'] as num,
                  'pointBalance': ?balance,
                  if (target['pointsNeeded'] != null)
                    'pointsNeeded': target['pointsNeeded'] as num,
                  if (target['additionalDrawsNeeded'] != null)
                    'additionalDrawsNeeded':
                        target['additionalDrawsNeeded'] as num,
                  if (target['remainingExchangeLimit'] != null)
                    'remainingExchangeLimit':
                        target['remainingExchangeLimit'] as num,
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _t(reward['resourceType'] == 2 ? 'member' : 'support'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final fact in facts.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _t(fact.key),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                              ),
                              Text(_number(fact.value)),
                            ],
                          ),
                        ),
                      if (balance != null && cost != null)
                        LinearProgressIndicator(
                          value: cost == 0
                              ? 1
                              : (balance / cost).clamp(0, 1).toDouble(),
                          semanticsLabel:
                              '${_t('pointBalance')} ${_number(balance)} / ${_t('pointCost')} ${_number(cost)}',
                        ),
                      DetailFold(
                        title:
                            '${_t('exchangeTargets')} · ${_number(group.length)}',
                        child: Column(
                          children: [
                            for (final entry in group)
                              Builder(
                                builder: (context) {
                                  final card = entry['reward'] as Map;
                                  final name =
                                      '${card['name'] ?? card['resourceId'] ?? ''}';
                                  final href = card['href'] as String?;
                                  final details = [
                                    '${_t(entry['pointCost'] == null ? 'basePointCost' : 'pointCost')} ${_number((entry['pointCost'] ?? entry['basePointCost']) as num)}',
                                    if (entry['redeemedCount'] != null)
                                      '${_t('redeemedCount')} ${_number(entry['redeemedCount'] as num)}',
                                    if (entry['remainingExchangeLimit'] != null)
                                      '${_t('remainingExchangeLimit')} ${_number(entry['remainingExchangeLimit'] as num)}',
                                    if (entry['resetType'] != null)
                                      _t(
                                        {
                                          1: 'resetNever',
                                          2: 'resetDaily',
                                          3: 'resetWeekly',
                                          4: 'resetMonthly',
                                        }[entry['resetType']]!,
                                      ),
                                  ];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    isThreeLine: details.length > 2,
                                    leading: SizedBox.square(
                                      dimension: 56,
                                      child: GachaPrizeCard(
                                        label: name,
                                        rarityValue:
                                            int.tryParse('${card['rarity']}') ??
                                            0,
                                        image: card['image'] as String?,
                                        attribute:
                                            card['attributeImageUrl']
                                                as String?,
                                        rarity:
                                            card['rarityImageUrl'] as String?,
                                        count: (card['count'] as num? ?? 1)
                                            .toInt(),
                                      ),
                                    ),
                                    title: Text(name),
                                    subtitle: Text(details.join(' · ')),
                                    onTap:
                                        href == null ||
                                            widget.onOpenCard == null
                                        ? null
                                        : () => widget.onOpenCard!(href),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _progressPanel(Map? pool) {
    if (pool == null) return const SizedBox.shrink();
    String interval(Object? value) {
      if (value == null) return '—';
      final range = value as Map;
      final format = NumberFormat('0.##', _locale);
      return range['min'] == range['max']
          ? format.format(range['min'])
          : '${format.format(range['min'])}–${format.format(range['max'])}';
    }

    String average(Map metric) => (metric['count'] as num) == 0
        ? '—'
        : NumberFormat(
            '0.##',
            _locale,
          ).format((pool['total'] as num) / (metric['count'] as num));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final kind in (pool['kinds'] as List).cast<Map>()) ...[
          const SizedBox(height: 16),
          Text(
            _t(kind['kind'] as String),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              horizontalMargin: 12,
              columnSpacing: 16,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 48,
              columns: [
                for (final key in [
                  'resultType',
                  'quantity',
                  'averageHitDraws',
                  'trailingMisses',
                ])
                  DataColumn(
                    label: Text(_t(key)),
                    numeric: key != 'resultType',
                  ),
              ],
              rows: [
                for (final target in ['high', 'pickup'])
                  DataRow(
                    cells: [
                      DataCell(
                        target == 'high'
                            ? Tooltip(
                                message: 'SSR / EX / BD',
                                child: Text(_t('highRarity')),
                              )
                            : Text(_t('pickup')),
                      ),
                      DataCell(
                        Text(_number((kind[target] as Map)['count'] as num)),
                      ),
                      DataCell(Text(average(kind[target] as Map))),
                      DataCell(
                        Text(interval((kind[target] as Map)['trailingMisses'])),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          for (final target in ['high', 'pickup'])
            DetailFold(
              title: _t(target == 'high' ? 'highHistory' : 'pickupHistory'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (key, label) in [
                    ('shortest', 'shortestMissGap'),
                    ('longest', 'longestMissGap'),
                    ('mean', 'meanMissGap'),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _t(label),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          Text(
                            interval(
                              ((kind[target] as Map)['gaps'] as Map)[key],
                            ),
                          ),
                        ],
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text(_t('poolPosition'))),
                        DataColumn(label: Text(_t('quantity')), numeric: true),
                      ],
                      rows: [
                        for (final hit
                            in ((kind[target] as Map)['hitBatches'] as List)
                                .cast<Map>())
                          DataRow(
                            cells: [
                              DataCell(Text(interval(hit['poolPosition']))),
                              DataCell(Text(_number(hit['count'] as num))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _drawSummary(List<GachaHistoryBatch> batches) {
    final known = batches.where((batch) => batch.drawCount != null).toList();
    final unknown = batches.length - known.length;
    return [
      if (known.isNotEmpty)
        _t('draws', {
          'count': known.fold<int>(0, (sum, batch) => sum + batch.drawCount!),
        }),
      if (unknown > 0) _t('unknownDraws', {'count': unknown}),
    ].join(' · ');
  }

  VoidCallback? _open(GachaHistoryPrize prize) =>
      prize.href == null || widget.onOpenCard == null
      ? null
      : () => widget.onOpenCard!(prize.href!);
  Widget _renderPrizes(List<GachaHistoryPrize> prizes) {
    String subtitle(GachaHistoryPrize prize) => [
      _t(prize.kind),
      if (prize.rarityLabel.isNotEmpty) prize.rarityLabel,
      '×${prize.quantity}',
      if (prize.pickup == true) _t('pickup'),
      if (prize.converted) _t('converted'),
    ].join(' · ');
    if (_view == 'table') {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (final key in [
              'card',
              'kind',
              'rarity',
              'quantity',
              'pickup',
              'converted',
            ])
              DataColumn(label: Text(_t(key))),
          ],
          rows: [
            for (final prize in prizes)
              DataRow(
                cells: [
                  DataCell(Text(prize.name), onTap: _open(prize)),
                  DataCell(Text(_t(prize.kind))),
                  DataCell(
                    Text(prize.rarityLabel.isEmpty ? '—' : prize.rarityLabel),
                  ),
                  DataCell(Text(_number(prize.quantity))),
                  DataCell(
                    Text(
                      prize.pickup == null
                          ? '—'
                          : _t(prize.pickup! ? 'yes' : 'no'),
                    ),
                  ),
                  DataCell(Text(_t(prize.converted ? 'yes' : 'no'))),
                ],
              ),
          ],
        ),
      );
    }
    if (_view == 'list') {
      return Column(
        children: [
          for (final prize in prizes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SizedBox.square(
                dimension: 56,
                child: AppImage(
                  candidates: [if (prize.imageUrl != null) prize.imageUrl!],
                  placeholder: const Icon(Symbols.image_rounded),
                ),
              ),
              title: Text(prize.name),
              subtitle: Text(subtitle(prize)),
              onTap: _open(prize),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 600 ? 5 : 10;
        return Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [
            for (final prize in prizes)
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 8) / columns,
                child: GachaPrizeCard(
                  label: '${prize.name} · ${subtitle(prize)}',
                  rarityValue: int.tryParse('${prize.rarity}') ?? 0,
                  image: prize.imageUrl,
                  attribute: prize.attributeImageUrl,
                  rarity: prize.rarityImageUrl,
                  pickup: prize.pickup == true,
                  count: prize.quantity,
                  onTap: _open(prize),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GachaConversionEditor extends StatefulWidget {
  const _GachaConversionEditor({
    super.key,
    required this.conversion,
    required this.onChanged,
    required this.currencyLabel,
    required this.freePriceLabel,
    required this.paidPriceLabel,
    required this.applyLabel,
  });
  final GachaHistoryConversion conversion;
  final ValueChanged<GachaHistoryConversion>? onChanged;
  final String currencyLabel, freePriceLabel, paidPriceLabel, applyLabel;
  @override
  State<_GachaConversionEditor> createState() => _GachaConversionEditorState();
}

class _GachaConversionEditorState extends State<_GachaConversionEditor> {
  final _form = GlobalKey<FormState>();
  late final _free = TextEditingController(
    text: widget.conversion.freeUnitGemPrice?.toString() ?? '',
  );
  late final _paid = TextEditingController(
    text: widget.conversion.paidUnitGemPrice?.toString() ?? '',
  );
  @override
  void didUpdateWidget(covariant _GachaConversionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversion != widget.conversion) {
      _free.text = widget.conversion.freeUnitGemPrice?.toString() ?? '';
      _paid.text = widget.conversion.paidUnitGemPrice?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _free.dispose();
    _paid.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      widget.onChanged?.call(
        GachaHistoryConversion(
          currencyCode: widget.conversion.currencyCode,
          freeUnitGemPrice: double.tryParse(_free.text),
          paidUnitGemPrice: double.tryParse(_paid.text),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownMenu<String>(
          key: ValueKey(widget.conversion.currencyCode),
          initialSelection: widget.conversion.currencyCode,
          expandedInsets: EdgeInsets.zero,
          label: Text(widget.currencyLabel),
          enabled: widget.onChanged != null,
          requestFocusOnTap: false,
          dropdownMenuEntries: [
            for (final code in [
              'JPY',
              'TWD',
              'HKD',
              'MOP',
              'USD',
              'KRW',
              'CNY',
            ])
              DropdownMenuEntry(value: code, label: code),
          ],
          onSelected: (code) {
            if (code != null && code != widget.conversion.currencyCode) {
              widget.onChanged?.call(
                GachaHistoryConversion(
                  currencyCode: code,
                  freeUnitGemPrice: 0,
                  paidUnitGemPrice: null,
                ),
              );
            }
          },
        ),
        for (final field in [
          (_free, widget.freePriceLabel),
          (_paid, widget.paidPriceLabel),
        ]) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: field.$1,
            enabled: widget.onChanged != null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '${field.$2} · ${widget.conversion.currencyCode}',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final number = double.tryParse(value);
              return number == null || !number.isFinite || number < 0
                  ? field.$2
                  : null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: widget.onChanged == null ? null : _submit,
          child: Text(widget.applyLabel),
        ),
      ],
    ),
  );
}
