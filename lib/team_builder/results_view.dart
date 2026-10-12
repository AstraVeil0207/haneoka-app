/// Search results: ranked team cards, per-song rankings, the plan summary,
/// skill orders and comparison (`lit/team-builder/results.ts`).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../catalog/catalog_screen.dart' show cardRarityName;

import '../ui/app_image.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';
import 'box.dart';
import 'build_tab.dart';
import 'controller.dart';
import 'engine/api.dart';
import 'engine/live.dart' show orders;
import 'engine_client.dart';
import 'result_image.dart';
import 'settings.dart';
import 'widgets.dart';

const rankNames = {1: 'E', 2: 'D', 3: 'C', 4: 'B', 5: 'A', 6: 'S', 7: 'SS'};

String hitKey(EngineHit hit) =>
    '${hit.song?.key ?? '-'}|${hit.members.join(',')}|${hit.snaps.join(',')}';

class ResultsView extends StatefulWidget {
  const ResultsView({super.key, required this.controller});
  final TeamBuilderController controller;

  @override
  State<ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<ResultsView> {
  String _tab = 'overall';
  final _compare = <String>[];
  EngineResponse? _shown;

  TeamBuilderController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final results = c.results;
    final theme = Theme.of(context);
    final locale = c.state.text.locale;
    if (!identical(results, _shown)) {
      _shown = results;
      _tab = 'overall';
      _compare.clear();
    }
    if (results == null) {
      return ToolSection(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(
                  Symbols.groups_rounded,
                  size: 40,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  c.tb('resultsEmpty', 'Results appear here'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      );
    }
    final settings = c.resultSettings ?? c.settings;
    final catalog = c.catalog!;
    final multi = results.results.length > 1 && settings.goal != GoalKind.plan;
    final tab = multi ? _tab : 'all';
    final shown = tab == 'overall' || !multi
        ? (multi ? results.overall : results.results.firstOrNull?.hits ?? [])
        : results.results.where((r) => r.song?.key == tab).firstOrNull?.hits ??
              [];
    final groups = multi && tab != 'overall'
        ? [
            for (final r in results.results)
              if (r.song?.key == tab) r,
          ]
        : results.results;
    final proven = groups.isNotEmpty && groups.every((r) => r.proven);
    final exact = results.results.fold(0, (sum, r) => sum + r.stats.exact);
    final criterion = scoreGoals[settings.criterion] ?? scoreGoals['mean']!;
    final proof =
        settings.goal == GoalKind.score || settings.goal == GoalKind.gekiso
        ? c.tb(
            proven ? criterion.proven.$1 : criterion.unproven.$1,
            proven ? criterion.proven.$2 : criterion.unproven.$2,
          )
        : proven
        ? c.tb('proven', 'Proven optimal')
        : c.tb('unproven', 'Time limit reached: best found so far');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  proven
                      ? Symbols.verified_rounded
                      : Symbols.hourglass_bottom_rounded,
                  size: 18,
                  color: proven
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(child: Text(proof, style: theme.textTheme.labelLarge)),
              ],
            ),
            if (c.stale)
              FilledButton.tonalIcon(
                onPressed: c.run,
                icon: const Icon(Symbols.refresh_rounded),
                label: Text(c.tb('rerun', 'Search again')),
              )
            else
              Text(
                c.tb(
                  'resultMeta',
                  '{ms} ms · {exact} teams simulated exactly',
                  {
                    'ms': formatNumber(locale, results.elapsedMs),
                    'exact': exact,
                  },
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (results.unknownCards.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            c.tb(
              'unknownCards',
              '{count} saved cards are not in this data release and were skipped.',
              {'count': results.unknownCards.length},
            ),
          ),
        ],
        if (results.plan case final plan?) ...[
          const SizedBox(height: 12),
          ToolSection(
            title: c.tb('planTotal', 'Total event points'),
            children: [
              Text(
                formatNumber(locale, plan.eventPoints),
                style: theme.textTheme.headlineMedium,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ValueChip(
                    label: c.tb('normalLives', 'Normal lives'),
                    value: '${plan.normalLives}',
                  ),
                  ValueChip(
                    label: c.tb('challengeLives', 'Challenge lives'),
                    value: '${plan.challengeLives}',
                  ),
                  ValueChip(
                    label: c.tb('cpEarned', 'Challenge points earned'),
                    value: formatNumber(locale, plan.challengePointsEarned),
                  ),
                  ValueChip(
                    label: c.tb('cpLeft', 'Left over'),
                    value: formatNumber(locale, plan.leftoverChallengePoints),
                  ),
                  ValueChip(
                    label: c.tb('perBoost', 'Per boost'),
                    value: formatNumber(locale, plan.perBoost, 1),
                  ),
                ],
              ),
            ],
          ),
        ],
        if (multi) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (id, label) in [
                  ('overall', c.tb('overall', 'Overall')),
                  for (final r in results.results)
                    (
                      r.song!.key,
                      '${catalog.songTitle(r.song!.songId)} ${catalog.difficultyLabel(r.song!.songId, r.song!.difficulty)}',
                    ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Text(label),
                      selected: tab == id,
                      onSelected: (_) => setState(() => _tab = id),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_compareTable(context, shown) case final table?) ...[
          const SizedBox(height: 12),
          table,
        ],
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(c.tb('noTeams', 'No team meets these conditions')),
            ),
          )
        else
          for (final (index, hit) in shown.indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            _HitCard(
              key: ValueKey(hitKey(hit)),
              controller: c,
              hit: hit,
              index: index,
              settings: settings,
              compared: _compare.contains(hitKey(hit)),
              onCompare: () => setState(() {
                final key = hitKey(hit);
                if (!_compare.remove(key)) {
                  _compare.add(key);
                  if (_compare.length > 3) _compare.removeAt(0);
                }
              }),
            ),
          ],
      ],
    );
  }

  Widget? _compareTable(BuildContext context, List<EngineHit> hits) {
    final picked = [
      for (final key in _compare)
        ?hits.where((hit) => hitKey(hit) == key).firstOrNull,
    ];
    if (picked.length < 2) return null;
    final locale = c.state.text.locale;
    final catalog = c.catalog!;
    final rows = <(String, String Function(EngineHit))>[
      (c.tb('power', 'Power'), (hit) => formatNumber(locale, hit.power)),
      if (picked.any((hit) => hit.score != null)) ...[
        (
          c.tb('expectedScore', 'Expected score'),
          (hit) =>
              hit.score == null ? '—' : formatNumber(locale, hit.score!.mean),
        ),
        (
          c.tb('worstScore', 'Worst-order score'),
          (hit) =>
              hit.score == null ? '—' : formatNumber(locale, hit.score!.min),
        ),
        (
          c.tb('bestScore', 'Best-order score'),
          (hit) =>
              hit.score == null ? '—' : formatNumber(locale, hit.score!.max),
        ),
      ],
      if (picked.any((hit) => hit.event != null)) ...[
        (
          c.tb('pointsPerPlay', 'Event points per play'),
          (hit) => hit.event == null
              ? '—'
              : formatNumber(locale, hit.event!.mean, 1),
        ),
        (
          c.tb('eventBonus', 'Event bonus'),
          (hit) => hit.event == null
              ? '—'
              : '+${formatNumber(locale, hit.event!.bonusPercent)}%',
        ),
      ],
      (
        c.tb('leader', 'Leader'),
        (hit) => catalog.characterName(
          catalog.characterIds(true, cardIdOf(hit.members.first)).firstOrNull ??
              0,
        ),
      ),
    ];
    return ToolSection(
      title: c.tb('comparison', 'Comparison'),
      trailing: TextButton(
        onPressed: () => setState(_compare.clear),
        child: Text(catalog.t('common.actions.clear', 'Clear')),
      ),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: SizedBox()),
              for (final hit in picked)
                DataColumn(
                  label: Text('#${hits.indexOf(hit) + 1}'),
                  numeric: true,
                ),
            ],
            rows: [
              for (final (label, value) in rows)
                DataRow(
                  cells: [
                    DataCell(Text(label)),
                    for (final hit in picked) DataCell(Text(value(hit))),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HitCard extends StatefulWidget {
  const _HitCard({
    super.key,
    required this.controller,
    required this.hit,
    required this.index,
    required this.settings,
    required this.compared,
    required this.onCompare,
  });
  final TeamBuilderController controller;
  final EngineHit hit;
  final int index;
  final BuildSettings settings;
  final bool compared;
  final VoidCallback onCompare;

  @override
  State<_HitCard> createState() => _HitCardState();
}

class _HitCardState extends State<_HitCard> {
  bool _expanded = false;

  TeamBuilderController get c => widget.controller;
  EngineHit get hit => widget.hit;

  ({String label, String value}) _primary() {
    final s = widget.settings;
    final locale = c.state.text.locale;
    if (s.goal == GoalKind.power) {
      return (
        label: c.tb('power', 'Power'),
        value: formatNumber(locale, hit.power),
      );
    }
    if (s.goal == GoalKind.potential && hit.potential != null) {
      return (
        label: c.tb('potential', 'Potential'),
        value: formatNumber(locale, hit.potential!.potential),
      );
    }
    if ((s.goal == GoalKind.event || s.goal == GoalKind.plan) &&
        hit.event != null) {
      final cp = s.measure == 'challenge-points' && s.goal == GoalKind.event;
      final label = s.measure == 'items' && s.goal == GoalKind.event
          ? c.tb('itemsPerPlay', 'Items per play')
          : cp
          ? c.tb('cpPerPlay', 'Challenge points per play')
          : c.tb('pointsPerPlay', 'Event points per play');
      return (
        label: label,
        value: formatNumber(
          locale,
          cp ? hit.event!.challengePoints : hit.event!.mean,
          1,
        ),
      );
    }
    if (hit.score case final score?) {
      final goal = scoreGoals[s.criterion] ?? scoreGoals['mean']!;
      final value = switch (s.criterion) {
        'min' => score.min,
        'max' => score.max,
        _ => score.mean,
      };
      return (
        label: c.tb(goal.metric.$1, goal.metric.$2),
        value: formatNumber(locale, value),
      );
    }
    return (
      label: c.tb('power', 'Power'),
      value: formatNumber(locale, hit.power),
    );
  }

  List<Widget> _chips() {
    final s = widget.settings;
    final locale = c.state.text.locale;
    return [
      if (s.goal != GoalKind.power)
        ValueChip(
          icon: Symbols.bolt_rounded,
          label: c.tb('power', 'Power'),
          value: formatNumber(locale, hit.power),
        ),
      if (hit.score case final score?) ...[
        if ((s.goal != GoalKind.score && s.goal != GoalKind.gekiso) ||
            s.criterion != 'mean')
          ValueChip(
            label: c.tb('expectedScore', 'Average score'),
            value: formatNumber(locale, score.mean),
          ),
        ValueChip(
          label: c.tb('scoreRange', 'Range'),
          value:
              '${formatNumber(locale, score.min)} – ${formatNumber(locale, score.max)}',
        ),
        if ((score.ranks.entries.toList()..sort((a, b) => b.key - a.key))
                .firstOrNull
            case final top?)
          ValueChip(
            icon: Symbols.workspace_premium_rounded,
            label: rankNames[top.key] ?? '${top.key}',
            value:
                '${formatNumber(locale, top.value / 120 * 100, top.value == 120 ? 0 : 1)}%',
          ),
      ],
      if (hit.event case final event?) ...[
        ValueChip(
          icon: Symbols.trending_up_rounded,
          label: c.tb('eventBonus', 'Event bonus'),
          value: '+${formatNumber(locale, event.bonusPercent)}%',
        ),
        if (event.challengePoints != 0 && s.measure != 'challenge-points')
          ValueChip(
            label: c.tb('cpPerPlay', 'Challenge points per play'),
            value: formatNumber(locale, event.challengePoints, 1),
          ),
      ],
      if (hit.skipScore case final skip?)
        ValueChip(
          icon: Symbols.fast_forward_rounded,
          label: c.tb('skipScore', 'Skip score'),
          value: formatNumber(locale, skip),
        ),
      if (hit.potential case final potential?)
        ValueChip(
          label: c.tb('skillCoverage', 'Skill coverage'),
          value: '${formatNumber(locale, potential.area * 100)}%·s',
        ),
    ];
  }

  void _copy() {
    final catalog = c.catalog!;
    final main = _primary();
    final lines = [
      if (hit.song case final song?)
        '${catalog.songTitle(song.songId)} ${catalog.difficultyLabel(song.songId, song.difficulty)}',
      '${main.label}: ${main.value} · ${c.tb('power', 'Power')}: ${formatNumber(c.state.text.locale, hit.power)}',
      for (final (index, key) in hit.members.indexed)
        '${index == 0 ? '[${c.tb('leader', 'Leader')}] ' : ''}'
            '${catalog.cardName(true, cardIdOf(key))} (${catalog.cardSubtitle(true, cardIdOf(key))}) + '
            '${hit.snaps[index] == null ? '—' : catalog.cardName(false, cardIdOf(hit.snaps[index]!))}',
    ];
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(c.tb('copied', 'Copied'))));
  }

  bool _rendering = false;

  /// `exportImage`.
  Future<void> _saveImage() async {
    setState(() => _rendering = true);
    try {
      await saveResultImage(
        await renderHitImage(c, hit, _primary(), Theme.of(context).colorScheme),
      );
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = c.catalog!;
    final main = _primary();
    final best = widget.index == 0;
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corner.large),
        side: BorderSide(
          color: best
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: best ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: best
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: best
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  child: Text('${widget.index + 1}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          main.label,
                          if (hit.song case final song?
                              when widget.settings.songs.length > 1)
                            '${catalog.songTitle(song.songId)} ${catalog.difficultyLabel(song.songId, song.difficulty)}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        main.value,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: c.tb('saveTeam', 'Save team'),
                  onPressed: () {
                    c.saveTeam(
                      [for (final key in hit.members) cardIdOf(key)],
                      [
                        for (final key in hit.snaps)
                          key == null ? null : cardIdOf(key),
                      ],
                      hit.song,
                    );
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(
                        content: Text(c.tb('savedTeam', 'Saved to Teams')),
                      ),
                    );
                  },
                  icon: const Icon(Symbols.bookmark_add_rounded),
                ),
                IconButton(
                  tooltip: c.tb('compare', 'Compare'),
                  isSelected: widget.compared,
                  onPressed: widget.onCompare,
                  icon: const Icon(Symbols.compare_arrows_rounded),
                ),
                IconButton(
                  tooltip: c.tb('copyTeam', 'Copy as text'),
                  onPressed: _copy,
                  icon: const Icon(Symbols.content_copy_rounded),
                ),
                IconButton(
                  tooltip: c.tb('saveImage', 'Save image'),
                  onPressed: _rendering ? null : _saveImage,
                  icon: const Icon(Symbols.image_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: _chips()),
            const SizedBox(height: 12),
            Formation(controller: c, hit: hit, settings: widget.settings),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Symbols.expand_less_rounded
                      : Symbols.expand_more_rounded,
                ),
                label: Text(
                  _expanded
                      ? c.tb('lessDetail', 'Less')
                      : c.tb('moreDetail', 'Details'),
                ),
              ),
            ),
            if (_expanded) ...[
              if (hit.score != null) _Distribution(controller: c, hit: hit),
              if (hit.song != null &&
                  (hit.score?.orders.isNotEmpty ?? false)) ...[
                const SizedBox(height: 16),
                _SkillOrders(controller: c, hit: hit),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The five slots, leader in the centre as on the game's formation screen.
class Formation extends StatelessWidget {
  const Formation({
    super.key,
    required this.controller,
    required this.hit,
    required this.settings,
  });
  final TeamBuilderController controller;
  final EngineHit hit;
  final BuildSettings settings;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final catalog = c.catalog!;
    final theme = Theme.of(context);
    final order = [1, 2, 0, 3, 4].where((i) => i < hit.members.length);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final index in order)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: () {
                final member = cardIdOf(hit.members[index]);
                final snapKey = hit.snaps.elementAtOrNull(index);
                final owned = c.view?.members[member];
                return Tooltip(
                  message:
                      '${catalog.cardSubtitle(true, member)} · ${c.tb('slotPower', 'Slot power')} '
                      '${formatNumber(c.state.text.locale, hit.slotPowers.elementAtOrNull(index) ?? 0)}',
                  child: Column(
                    children: [
                      CardArt(
                        catalog: catalog,
                        members: true,
                        id: member,
                        extra: [
                          if (index == 0)
                            TileMark.text(
                              MarkAt.bottomStart,
                              c.tb('leader', 'Leader'),
                              accent: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (snapKey != null)
                        CardArt(
                          catalog: catalog,
                          members: false,
                          id: cardIdOf(snapKey),
                        )
                      else
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(Corner.small),
                            ),
                            child: Icon(
                              Symbols.hide_image_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (owned == null && settings.theoretical)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            c.tb('notOwned', 'Not owned'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }(),
            ),
          ),
      ],
    );
  }
}

class _Distribution extends StatelessWidget {
  const _Distribution({required this.controller, required this.hit});
  final TeamBuilderController controller;
  final EngineHit hit;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final score = hit.score!;
    final locale = c.state.text.locale;
    final theme = Theme.of(context);
    final master = c.catalog!.master;
    final thresholds = hit.song == null
        ? const []
        : master.scoreRanks[master.songs[hit.song!.songId]?.rankGroup] ??
              const [];
    var low = score.min, high = score.max;
    for (final row in thresholds) {
      if (row.required >= score.min * 0.9 && row.required <= score.max * 1.05) {
        low = math.min(low, row.required.toDouble());
      }
      if (row.required <= score.max * 1.1 && row.required >= score.min) {
        high = math.max(high, row.required.toDouble());
      }
    }
    final span = math.max(1.0, high - low);
    double at(num value) => (value - low) / span;
    final ranks = score.ranks.entries.toList()..sort((a, b) => b.key - a.key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 14,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: width * at(score.min),
                    width: math.max(2, width * (at(score.max) - at(score.min))),
                    top: 14,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  for (final (value, color) in [
                    (score.median, theme.colorScheme.tertiary),
                    (score.mean, theme.colorScheme.onSurface),
                  ])
                    Positioned(
                      left: width * at(value) - 1,
                      top: 10,
                      width: 2,
                      height: 16,
                      child: ColoredBox(color: color),
                    ),
                  for (final row in thresholds)
                    if (row.required > low && row.required < high)
                      Positioned(
                        left: width * at(row.required) - 10,
                        top: 0,
                        width: 20,
                        child: Column(
                          children: [
                            Text(
                              rankNames[row.rank] ?? '',
                              style: theme.textTheme.labelSmall,
                            ),
                            Container(
                              width: 1,
                              height: 20,
                              color: theme.colorScheme.outline,
                            ),
                          ],
                        ),
                      ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        DefaultTextStyle.merge(
          style: theme.textTheme.labelMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatNumber(locale, score.min)),
              Text(
                '${c.tb('median', 'median')} ${formatNumber(locale, score.median)}',
              ),
              Text(formatNumber(locale, score.max)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final rank in ranks)
              ValueChip(
                label: rankNames[rank.key] ?? '${rank.key}',
                value:
                    '${formatNumber(locale, rank.value / 120 * 100, rank.value == 120 ? 0 : 1)}%',
              ),
          ],
        ),
      ],
    );
  }
}

/// The skill-order editor: pick two positions to swap, the order's timeline,
/// the best order by first skill and the top orders.
class _SkillOrders extends StatefulWidget {
  const _SkillOrders({required this.controller, required this.hit});
  final TeamBuilderController controller;
  final EngineHit hit;

  @override
  State<_SkillOrders> createState() => _SkillOrdersState();
}

class _SkillOrdersState extends State<_SkillOrders> {
  int? _current;
  int? _picked;
  bool _top = false;
  final _timelines = <int, Future<Timeline>>{};
  List<int>? _firing;

  TeamBuilderController get c => widget.controller;
  EngineHit get hit => widget.hit;

  Future<Timeline> _timeline(int index) => _timelines[index] ??= () {
    final request = c.request();
    final engine = c.engine;
    if (request == null || engine == null) {
      return Future<Timeline>.error(StateError('no-request'));
    }
    return engine.timeline(
      TimelineRequest(
        members: request.members,
        snaps: request.snaps,
        unknownPolicy: request.unknownPolicy,
        memberKeys: hit.members,
        snapKeys: hit.snaps,
        song: hit.song!,
        order: orders[index],
      ),
    );
  }();

  ({int character, String name, String face, String card, Color color}) _face(
    int slot,
  ) {
    final catalog = c.catalog!;
    final card = cardIdOf(hit.members[slot]);
    final character = catalog.characterIds(true, card).firstOrNull ?? 0;
    return (
      character: character,
      name: catalog.characterName(character),
      face: catalog.characterFace(character),
      card: catalog.cardImage(true, card),
      color: catalog.characterColor(
        character,
        Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _faces(int index, List<int> firing) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final event in firing)
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Tooltip(
            message: _face(orders[index][event]).name,
            child: ClipOval(
              child: SizedBox.square(
                dimension: 28,
                child: AppImage(candidates: [_face(orders[index][event]).face]),
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = c.state.text.locale;
    final score = hit.score!;
    final ranked =
        [
          for (final (index, value) in score.orders.indexed)
            (value: value, index: index),
        ]..sort(
          (a, b) => b.value != a.value ? b.value - a.value : a.index - b.index,
        );
    final best = ranked.first;
    final current = _current ?? best.index;
    final firing = _firing ?? const [0, 1, 2, 3, 4];
    final value = score.orders[current];
    final rank = score.orders.where((other) => other > value).length + 1;
    String gap(int other) => other == best.value
        ? '±0'
        : '−${formatNumber(locale, best.value - other)}';
    void choose(int index) => setState(() {
      _current = index;
      _picked = null;
    });
    void pick(int position) {
      if (_picked == null) {
        setState(() => _picked = position);
      } else if (_picked == position) {
        setState(() => _picked = null);
      } else {
        final order = [...orders[current]];
        final a = firing[_picked!], b = firing[position];
        final swap = order[a];
        order[a] = order[b];
        order[b] = swap;
        choose(orders.indexWhere((o) => o.join(',') == order.join(',')));
      }
    }

    final first = firing.first;
    final byFirst = [
      for (var slot = 0; slot < hit.members.length; slot++)
        ranked.firstWhere((entry) => orders[entry.index][first] == slot),
    ]..sort((a, b) => b.value - a.value);
    int rankOf(int other) => score.orders.where((e) => e > other).length + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                c.tb('skillOrder', 'Skill order'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: current == best.index
                  ? null
                  : () => choose(best.index),
              child: Text(c.tb('bestOrder', 'Best order')),
            ),
            TextButton(
              onPressed: current == ranked.last.index
                  ? null
                  : () => choose(ranked.last.index),
              child: Text(c.tb('worstOrder', 'Worst order')),
            ),
          ],
        ),
        Row(
          children: [
            for (final (position, event) in firing.indexed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: () {
                    final member = _face(orders[current][event]);
                    final selected = _picked == position;
                    return Material(
                      color: selected
                          ? theme.colorScheme.secondaryContainer
                          : theme.colorScheme.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Corner.small),
                        side: BorderSide(color: member.color, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => pick(position),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '${position + 1}',
                                style: theme.textTheme.labelMedium,
                              ),
                            ),
                            AspectRatio(
                              aspectRatio: 3 / 4,
                              child: AppImage(
                                candidates: [member.card],
                                fit: BoxFit.cover,
                              ),
                            ),
                            if (_picked != null && !selected)
                              const Icon(Symbols.swap_horiz_rounded, size: 18),
                          ],
                        ),
                      ),
                    );
                  }(),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ValueChip(
              label: c.tb('score', 'Score'),
              value: formatNumber(locale, value),
            ),
            ValueChip(
              label: c.tb('orderRank', 'Rank'),
              value: '$rank / ${score.orders.length}',
            ),
            ValueChip(label: c.tb('orderGap', 'From best'), value: gap(value)),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<Timeline>(
          future: _timeline(current),
          builder: (context, snapshot) {
            final timeline = snapshot.data;
            if (timeline != null && _firing == null) {
              final windows = [...timeline.windows]
                ..sort(
                  (a, b) => a.startMs != b.startMs
                      ? a.startMs - b.startMs
                      : a.event - b.event,
                );
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => setState(
                  () => _firing = [for (final w in windows) w.event],
                ),
              );
            }
            if (snapshot.hasError) {
              return Text(
                c.tb('timelineFailed', 'The timeline could not be drawn.'),
              );
            }
            return SizedBox(
              height: 112,
              child: timeline == null
                  ? const Center(child: LinearProgressIndicator())
                  : _TimelinePlot(
                      timeline: timeline,
                      colorOf: (key) => _face(hit.members.indexOf(key)).color,
                      faceOf: (key) => _face(hit.members.indexOf(key)).face,
                    ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          c.tb('firstSkill', 'Best order by first skill'),
          style: theme.textTheme.titleSmall,
        ),
        for (final entry in byFirst)
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => choose(entry.index),
            selected: entry.index == current,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(Corner.small),
              child: SizedBox(
                width: 36,
                height: 48,
                child: AppImage(
                  candidates: [_face(orders[entry.index][first]).card],
                  fit: BoxFit.cover,
                ),
              ),
            ),
            title: Text(_face(orders[entry.index][first]).name),
            subtitle: Text(gap(entry.value)),
            trailing: _faces(entry.index, firing),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(c.tb('topOrders', 'Top orders')),
          trailing: Text('10', style: theme.textTheme.labelLarge),
          initiallyExpanded: _top,
          onExpansionChanged: (open) => _top = open,
          children: [
            for (final entry in ranked.take(10))
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => choose(entry.index),
                selected: entry.index == current,
                leading: SizedBox(
                  width: 28,
                  child: Center(child: Text('${rankOf(entry.value)}')),
                ),
                title: _faces(entry.index, firing),
                subtitle: Text(
                  '${formatNumber(locale, entry.value)} · ${gap(entry.value)}',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Note density, fevers and each member's skill window (`skillTimeline`).
class _TimelinePlot extends StatelessWidget {
  const _TimelinePlot({
    required this.timeline,
    required this.colorOf,
    required this.faceOf,
  });
  final Timeline timeline;
  final Color Function(String member) colorOf;
  final String Function(String member) faceOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final duration = math.max(1, timeline.durationMs);
        double x(int ms) => ms / duration * width;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DensityPainter(
                  timeline,
                  theme.colorScheme.surfaceContainerHighest,
                  theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
                ),
              ),
            ),
            for (final (index, window) in timeline.windows.indexed)
              Positioned(
                left: x(window.startMs),
                width: math.max(4, x(window.endMs) - x(window.startMs)),
                top: 8.0 + (index % 3) * 32,
                height: 26,
                child: Tooltip(
                  message:
                      '+${(window.percent + window.perfectPercent).round()}%',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorOf(window.member).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: ClipOval(
                          child: SizedBox.square(
                            dimension: 22,
                            child: AppImage(
                              candidates: [faceOf(window.member)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DensityPainter extends CustomPainter {
  _DensityPainter(this.timeline, this.color, this.fever);
  final Timeline timeline;
  final Color color;
  final Color fever;

  @override
  void paint(Canvas canvas, Size size) {
    final duration = math.max(1, timeline.durationMs);
    for (final (start, end) in timeline.fever) {
      canvas.drawRect(
        Rect.fromLTRB(
          start / duration * size.width,
          0,
          end / duration * size.width,
          size.height,
        ),
        Paint()..color = fever,
      );
    }
    final peak = timeline.density.fold(1, math.max);
    final step = size.width / math.max(1, timeline.density.length);
    final paint = Paint()..color = color;
    for (final (index, count) in timeline.density.indexed) {
      final h = count / peak * size.height;
      canvas.drawRect(
        Rect.fromLTWH(index * step, size.height - h, step, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DensityPainter old) => old.timeline != timeline;
}

/// A result as the website's shareable image (`exportImage`).
Future<List<int>> renderHitImage(
  TeamBuilderController c,
  EngineHit hit,
  ({String label, String value}) main,
  ColorScheme scheme,
) {
  final catalog = c.catalog!;
  final locale = c.state.text.locale;
  ResultImageCard card(bool members, int id, bool leader) {
    final characters = catalog.characterIds(members, id);
    return ResultImageCard(
      title: catalog.cardName(members, id),
      character: [
        for (final character in characters) catalog.characterName(character),
      ].join(' · '),
      image: catalog.cardImage(members, id),
      avatars: [
        for (final character in characters)
          if (catalog.characterFace(character).isNotEmpty)
            catalog.characterFace(character),
      ],
      attribute: catalog.attributeIcon(catalog.attribute(members, id)),
      rarity: catalog.rarityIcon(catalog.rarity(members, id)),
      attributeLabel: catalog.attributeName(catalog.attribute(members, id)),
      rarityLabel: cardRarityName(catalog.rarity(members, id)),
      leader: leader,
    );
  }

  return renderTeamResultImage(
    TeamResultImage(
      title: c.tb('title', 'Team builder'),
      subtitle: hit.song == null
          ? main.label
          : '${catalog.songTitle(hit.song!.songId)} · ${catalog.difficultyLabel(hit.song!.songId, hit.song!.difficulty)}',
      membersLabel: c.tb('members', 'Members'),
      snapshotsLabel: c.tb('snapshots', 'Snaps'),
      leaderLabel: c.tb('leader', 'Leader'),
      emptyLabel: c.tb('noSnap', 'No snap'),
      imageUnavailableLabel: c.tb('imageUnavailable', 'Image unavailable'),
      members: [
        for (final (index, key) in hit.members.indexed)
          card(true, cardIdOf(key), index == 0),
      ],
      snapshots: [
        for (final key in hit.snaps)
          key == null ? null : card(false, cardIdOf(key), false),
      ],
      metrics: [
        (main.label, main.value),
        (c.tb('power', 'Power'), formatNumber(locale, hit.power)),
        if (hit.score case final score?)
          (
            c.tb('scoreRange', 'Range'),
            '${formatNumber(locale, score.min)} – ${formatNumber(locale, score.max)}',
          ),
      ],
      footer: const ['haneoka.org'],
      theme: ResultImageTheme(
        surface: scheme.surface,
        container: scheme.surfaceContainer,
        text: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        primary: scheme.primary,
        outline: scheme.outlineVariant,
      ),
    ),
  );
}
