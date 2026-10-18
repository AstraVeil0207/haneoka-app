import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/detail.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';
import 'history_view.dart';
import 'history_report.dart';

enum GachaHistoryImportSource { saved, files, adb }

class GachaHistoryScreen extends StatefulWidget {
  const GachaHistoryScreen({
    super.key,
    this.accounts = const [],
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
  final List<GachaHistoryAccount> accounts;
  final List<GachaHistoryPool> pools;
  final List<GachaHistoryBatch> batches;
  final String selectedAccountKey;
  final bool busy, historyLoaded, catalogLoading;
  final String? catalogError;
  final VoidCallback? onCatalogRetry;
  final String? error;
  final ValueChanged<String>? onAccountChanged, onRefresh, onOpenCard;
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
  };
  final _expanded = <String>{};
  bool _expansionReady = false;
  List<GachaHistoryPool>? _indexedPools;
  Map<String, GachaHistoryPool> _poolIndex = {};
  String _query = '', _view = 'grid';
  bool _oldest = false;
  DateTime? _from, _to;
  String _t(String key, [Map<String, Object?> values = const {}]) =>
      AppScope.of(context).text('catalog.gachaHistory.$key', '', values);
  String get _locale => AppScope.of(context).text.locale;
  String _number(num value) =>
      NumberFormat.decimalPattern(_locale).format(value);
  String _day(DateTime? date) => date == null
      ? "unknown"
      : DateFormat('yyyy-MM-dd').format(date.toLocal());
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
            (batch.pulledAt != null && day.compareTo(_day(_from!)) >= 0)) &&
        (_to == null ||
            (batch.pulledAt != null && day.compareTo(_day(_to!)) <= 0));
  }).toList();
  List<GachaHistoryBatch> get _filtered {
    final result = _scoped
        .where(
          (batch) =>
              (_query.trim().isEmpty &&
                  _filters['kind']!.isEmpty &&
                  _filters['rarity']!.isEmpty) ||
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
          final value = axis == 'kind' ? prize.kind : '${prize.rarity}';
          final label = axis == 'kind' ? _t(prize.kind) : prize.rarityLabel;
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
                                  .map((batch) => batch.pulledAt?.toLocal())
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
    final prizes = filtered.expand(_prizes).toList();
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
                    label: Text('${_t('from')} · ${_day(_from!)}'),
                    onDeleted: () => setState(() => _from = null),
                  ),
                if (_to != null)
                  InputChip(
                    label: Text('${_t('to')} · ${_day(_to!)}'),
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
                          DropdownButtonFormField<String>(
                            key: ValueKey(widget.selectedAccountKey),
                            initialValue:
                                widget.accounts.any(
                                  (account) =>
                                      account.key == widget.selectedAccountKey,
                                )
                                ? widget.selectedAccountKey
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: _t('account'),
                            ),
                            hint: Text(_t('selectAccount')),
                            items: [
                              for (final account in widget.accounts)
                                DropdownMenuItem(
                                  value: account.key,
                                  child: Text(
                                    '${account.serverLabel} · ${account.label}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged:
                                widget.busy || widget.onAccountChanged == null
                                ? null
                                : (value) {
                                    if (value != null) {
                                      widget.onAccountChanged!(value);
                                    }
                                  },
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
                                child: _GachaConversionEditor(
                                  key: ValueKey(widget.selectedAccountKey),
                                  conversion: conversion,
                                  onChanged: widget.onConversionChanged,
                                  currencyLabel: _t('currency'),
                                  priceLabel: _t('unitGemPrice'),
                                  applyLabel: _t('applyPrice'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (scoped.isNotEmpty) ...[
                    DetailFold(
                      title: _t('poolBreakdown'),
                      child: _breakdown(scoped, byDate: false),
                    ),
                    DetailFold(
                      title: _t('timeBreakdown'),
                      child: _breakdown(scoped, byDate: true),
                    ),
                  ],
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
                                        '${batch.pulledAt == null ? _t("unknownTime") : DateFormat.Hm(_locale).format(batch.pulledAt!.toLocal())} · ${batch.drawCount == null ? _t("unknownCount") : _t('draws', {'count': batch.drawCount})}',
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
    (num?, bool) total(num? Function(GachaHistoryCost?) field) {
      final values = batches.map((batch) => field(batch.cost)).toList();
      return (
        values.any((value) => value != null)
            ? values.fold<num>(0, (sum, value) => sum + (value ?? 0))
            : null,
        values.any((value) => value == null),
      );
    }

    final free = total((cost) => cost?.freeGems),
        paid = total((cost) => cost?.paidGems),
        tickets = total((cost) => cost?.tickets);
    String number((num?, bool) value) =>
        value.$1 == null ? '—' : '${value.$2 ? "≥ " : ""}${_number(value.$1!)}';
    final metrics = [
      (_t('freeGems'), number(free)),
      (_t('paidGems'), number(paid)),
      (_t('tickets'), number(tickets)),
    ];
    final conversion = widget.currencyConversion;
    if (conversion != null) {
      final price = conversion.unitGemPrice;
      String money(num? value, bool partial) => value == null || price == null
          ? '—'
          : '${partial ? "≥ " : ""}${NumberFormat.simpleCurrency(locale: _locale, name: conversion.currencyCode).format(value * price)}';
      metrics.addAll([
        (
          _t('allGemValue'),
          money(
            free.$1 == null || paid.$1 == null ? null : free.$1! + paid.$1!,
            free.$2 || paid.$2,
          ),
        ),
        (_t('paidGemValue'), money(paid.$1, paid.$2)),
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
      ..._costMetrics(batches),
    ];
    if (widget.currencyConversion case final conversion?) {
      metrics.add((
        '${_t('unitGemPrice')} · ${conversion.currencyCode}',
        conversion.unitGemPrice == null
            ? '—'
            : NumberFormat(
                '0.########',
                _locale,
              ).format(conversion.unitGemPrice),
      ));
    }
    if (known.length != batches.length) {
      metrics.add((
        _t('unknownCount'),
        _t('batches', {'count': batches.length - known.length}),
      ));
    }
    final rarity = <String, int>{};
    for (final prize in prizes) {
      if (prize.rarityLabel.isNotEmpty &&
          ['member', 'support'].contains(prize.kind)) {
        rarity.update(
          prize.rarityLabel,
          (count) => count + prize.quantity,
          ifAbsent: () => prize.quantity,
        );
      }
    }
    metrics.addAll([
      for (final entry in rarity.entries) (entry.key, _number(entry.value)),
    ]);
    final groups = <GachaHistoryReportGroup>[];
    for (final label in ['SSR', 'EX', 'BD']) {
      final cards = <String, GachaHistoryReportCard>{};
      for (final prize in prizes) {
        final rarityName =
            {'4': 'SSR', '10': 'EX', '20': 'BD'}['${prize.rarity}'] ??
            prize.rarityLabel;
        if (rarityName != label ||
            !['member', 'support'].contains(prize.kind)) {
          continue;
        }
        final key = '${prize.kind}:${prize.id}';
        cards[key] = GachaHistoryReportCard(
          name: prize.name,
          kindLabel: _t(prize.kind),
          quantity: (cards[key]?.quantity ?? 0) + prize.quantity,
          imageUrl: prize.imageUrl,
        );
      }
      groups.add(
        GachaHistoryReportGroup(label: label, cards: cards.values.toList()),
      );
    }
    final dates =
        batches
            .map((batch) => batch.pulledAt?.toLocal())
            .whereType<DateTime>()
            .toList()
          ..sort();
    final scope = [
      batches
          .map((batch) => _pools[batch.poolId]?.name ?? batch.poolId)
          .toSet()
          .join(' · '),
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
    );
  }

  Widget _breakdown(List<GachaHistoryBatch> batches, {required bool byDate}) {
    final groups = <String, List<GachaHistoryBatch>>{};
    for (final batch in batches) {
      groups
          .putIfAbsent(byDate ? _day(batch.pulledAt) : batch.poolId, () => [])
          .add(batch);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text(_t(byDate ? 'timeBreakdown' : 'pool'))),
          DataColumn(label: Text(_t('total'))),
          for (final label in ['SSR', 'EX', 'BD'])
            DataColumn(label: Text(label), numeric: true),
          for (final key in ['freeGems', 'paidGems', 'tickets'])
            DataColumn(label: Text(_t(key)), numeric: true),
        ],
        rows: [
          for (final entry in groups.entries)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    byDate
                        ? (entry.key == 'unknown'
                              ? _t('unknownTime')
                              : DateFormat.yMMMd(_locale)
                                    .format(DateTime.parse(entry.key)))
                        : _pools[entry.key]?.name ?? entry.key,
                  ),
                ),
                DataCell(Text(_drawSummary(entry.value))),
                for (final rarity in ['4', '10', '20'])
                  DataCell(
                    Text(
                      _number(
                        entry.value
                            .expand((batch) => batch.prizes)
                            .where((prize) => '${prize.rarity}' == rarity)
                            .fold<int>(0, (sum, prize) => sum + prize.quantity),
                      ),
                    ),
                  ),
                for (final metric in _costMetrics(entry.value).take(3))
                  DataCell(Text(metric.$2)),
              ],
            ),
        ],
      ),
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
    ].join(' · ');
    if (_view == 'table') {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (final key in ['card', 'kind', 'rarity', 'quantity', 'pickup'])
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
        final columns = (constraints.maxWidth / 144).floor().clamp(2, 8);
        return Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [
            for (final prize in prizes)
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 8) / columns,
                child: Tile(
                  title: prize.name,
                  subtitle: _t(prize.kind),
                  images: [if (prize.imageUrl != null) prize.imageUrl!],
                  onTap: _open(prize),
                  marks: [
                    if (prize.rarityLabel.isNotEmpty)
                      TileMark.text(MarkAt.start, prize.rarityLabel),
                    TileMark.text(MarkAt.bottomEnd, '×${prize.quantity}'),
                    if (prize.pickup == true)
                      TileMark.text(
                        MarkAt.end,
                        _t('pickup'),
                        accent: Theme.of(context).colorScheme.primaryContainer,
                      ),
                  ],
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
    required this.priceLabel,
    required this.applyLabel,
  });
  final GachaHistoryConversion conversion;
  final ValueChanged<GachaHistoryConversion>? onChanged;
  final String currencyLabel, priceLabel, applyLabel;
  @override
  State<_GachaConversionEditor> createState() => _GachaConversionEditorState();
}

class _GachaConversionEditorState extends State<_GachaConversionEditor> {
  late final _price = TextEditingController(
    text: widget.conversion.unitGemPrice?.toString() ?? '',
  );
  double? get _value {
    final value = double.tryParse(_price.text.trim());
    return value != null && value.isFinite && value >= 0 ? value : null;
  }

  @override
  void didUpdateWidget(covariant _GachaConversionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversion.currencyCode != widget.conversion.currencyCode ||
        oldWidget.conversion.unitGemPrice != widget.conversion.unitGemPrice) {
      _price.text = widget.conversion.unitGemPrice?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _value;
    if (value != null) {
      widget.onChanged?.call(
        GachaHistoryConversion(
          currencyCode: widget.conversion.currencyCode,
          unitGemPrice: value,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey(widget.conversion.currencyCode),
        initialValue: widget.conversion.currencyCode,
        isExpanded: true,
        decoration: InputDecoration(labelText: widget.currencyLabel),
        items: [
          for (final code in ['JPY', 'TWD', 'HKD', 'MOP', 'USD', 'KRW', 'CNY'])
            DropdownMenuItem(value: code, child: Text(code)),
        ],
        onChanged: widget.onChanged == null
            ? null
            : (code) {
                if (code != null && code != widget.conversion.currencyCode) {
                  setState(_price.clear);
                  widget.onChanged!(
                    GachaHistoryConversion(
                      currencyCode: code,
                      unitGemPrice: null,
                    ),
                  );
                }
              },
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _price,
        enabled: widget.onChanged != null,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: '${widget.priceLabel} · ${widget.conversion.currencyCode}',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 12),
      FilledButton.tonal(
        onPressed: widget.onChanged == null || _value == null ? null : _submit,
        child: Text(widget.applyLabel),
      ),
    ],
  );
}
