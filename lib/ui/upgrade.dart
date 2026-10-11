import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import 'app_image.dart';
import 'theme.dart';

/// The website's level switch (`renderLevelSwitch`): an outlined field with
/// its label and value, minus, a slider over the allowed levels, plus.
class LevelSwitch extends StatelessWidget {
  const LevelSwitch({
    super.key,
    required this.label,
    required this.levels,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final List<int> levels;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (levels.length < 2) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final index = levels.indexOf(value).clamp(0, levels.length - 1);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(Corner.small),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
                Text('${levels[index]}', style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          IconButton(
            onPressed: index > 0 ? () => onChanged(levels[index - 1]) : null,
            icon: const Icon(Symbols.remove_rounded),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context)
                  .copyWith(trackHeight: 16, year2023: false),
              child: Slider(
                value: index.toDouble(),
                max: (levels.length - 1).toDouble(),
                divisions: levels.length - 1,
                label: '${levels[index]}',
                onChanged: (v) => onChanged(levels[v.round()]),
              ),
            ),
          ),
          IconButton(
            onPressed: index < levels.length - 1
                ? () => onChanged(levels[index + 1])
                : null,
            icon: const Icon(Symbols.add_rounded),
          ),
        ],
      ),
    );
  }
}

/// One material in an upgrade (`CatalogCost`).
class CostItem {
  const CostItem(
    this.identity,
    this.name,
    this.count, {
    this.image,
    this.onTap,
  });
  final String identity;
  final String name;
  final int count;
  final String? image;
  final VoidCallback? onTap;
}

/// The materials for reaching [to] from [to] - 1 (`CatalogCostStep`).
class CostStep {
  const CostStep(this.from, this.to, this.items);
  final int from, to;
  final List<CostItem> items;
}

/// Adds the steps between two levels (`summarizeCatalogCosts`); null when a
/// step is missing, since a partial total would mislead.
List<CostItem>? summarizeCosts(List<CostStep> steps, int from, int to) {
  if (to < from) return null;
  final byTarget = <int, CostStep>{};
  for (final step in steps) {
    if (step.to > from && step.to <= to) byTarget[step.to] = step;
  }
  final totals = <String, CostItem>{};
  for (var stage = from + 1; stage <= to; stage++) {
    final step = byTarget[stage];
    if (step == null || step.from != stage - 1) return null;
    for (final item in step.items) {
      final previous = totals[item.identity];
      totals[item.identity] = CostItem(
        item.identity,
        item.name,
        (previous?.count ?? 0) + item.count,
        image: item.image,
        onTap: item.onTap,
      );
    }
  }
  return totals.values.toList();
}

/// The upgrade calculator (`catalog-upgrade-cost`): one upgrade, everything
/// from the start, or from the current level to the target.
class UpgradeCost extends StatefulWidget {
  const UpgradeCost({
    super.key,
    required this.label,
    required this.steps,
    required this.to,
    this.initial = 1,
  });
  final String label;
  final List<CostStep> steps;
  final int to;
  final int initial;
  @override
  State<UpgradeCost> createState() => _UpgradeCostState();
}

class _UpgradeCostState extends State<UpgradeCost> {
  String _mode = 'step';
  late int _current = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    String text(String key, String fallback) =>
        t('catalog.cards.costs.$key', fallback);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final number = NumberFormat.decimalPattern(t.locale);
    final current = _current.clamp(widget.initial, widget.to);
    final from = switch (_mode) {
      'cumulative' => widget.initial,
      'range' => current,
      _ => (widget.to - 1).clamp(widget.initial, widget.to),
    };
    final items = summarizeCosts(widget.steps, from, widget.to);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: 'step',
              label: Text(text('step', 'One upgrade')),
            ),
            ButtonSegment(
              value: 'cumulative',
              label: Text(text('cumulative', 'Cumulative')),
            ),
            ButtonSegment(
              value: 'range',
              label: Text(text('range', 'Current → target')),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (value) => setState(() => _mode = value.single),
        ),
        const SizedBox(height: 8),
        if (_mode == 'range')
          LevelSwitch(
            label: text('current', 'Current'),
            levels: [for (var l = widget.initial; l <= widget.to; l++) l],
            value: current,
            onChanged: (value) => setState(() => _current = value),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(Corner.medium),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '$from → ${widget.to}',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (items == null || items.isEmpty)
                Text('—', style: theme.textTheme.bodyMedium)
              else
                for (final item in items)
                  InkWell(
                    onTap: item.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 32,
                            child: item.image == null
                                ? null
                                : AppImage(candidates: [item.image!]),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.name,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            '×${number.format(item.count)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
