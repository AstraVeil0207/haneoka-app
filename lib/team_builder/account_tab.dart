/// Account-wide power bonuses: character ranks, band items and the T.G.W
/// card rank (`lit/team-builder/account-tab.ts`).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../ui/app_image.dart';
import 'controller.dart';
import 'engine/num.dart';
import 'widgets.dart';

class AccountTab extends StatelessWidget {
  const AccountTab({super.key, required this.controller});
  final TeamBuilderController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final catalog = c.catalog!;
    final master = catalog.master;
    final player = c.view!.player;
    final theme = Theme.of(context);
    int order(Object? value) => value is num ? value.toInt() : 1 << 30;
    final characters =
        [
          for (final id in master.characters.keys)
            if (catalog.characterName(id).isNotEmpty) id,
        ]..sort((a, b) {
          final band = master.characters[a]! - master.characters[b]!;
          if (band != 0) return band;
          final display =
              order(
                catalog.visuals?.characters[a]?['displayOrder'] ??
                    objectRow(
                      objectRow(catalog.data['characters'])['$a'],
                    )['displayOrder'],
              ) -
              order(
                catalog.visuals?.characters[b]?['displayOrder'] ??
                    objectRow(
                      objectRow(catalog.data['characters'])['$b'],
                    )['displayOrder'],
              );
          return display != 0 ? display : a - b;
        });
    final maxRank = master.maxCharacterRank;
    // Every character counts, unranked ones at 1, exactly as the engine sums them.
    final total = master.characters.keys.fold(
      0,
      (sum, id) => sum + (player.characterRanks['$id'] ?? 1),
    );
    final bands = {
      for (final id in characters)
        if (master.characters[id]! != 0) master.characters[id]!,
    };
    final vipRanks = master.vipBonus.keys.toList()..sort();
    final maxVip = math.max(1, vipRanks.fold(1, math.max));
    final items =
        [
          for (final item in objectRow(
            catalog.data['bandItems'],
          ).values.map(objectRow))
            (
              id: intOf(item['bandItemId']),
              bandId: intOf(item['bandId']),
              order: order(item['displayOrder']),
              name: catalog.text(item['name']),
              max: dataRows(item['levels']).fold(
                0,
                (m, row) => math.max(m, intOf(nativeRow(row)['level'])),
              ),
            ),
        ]..sort((a, b) {
          if (a.bandId != b.bandId) return a.bandId - b.bandId;
          if (a.order != b.order) return a.order - b.order;
          return a.id - b.id;
        });
    final vip = master.vipBonus[player.vipRank ?? 1];
    Widget bandName(int band) => Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          if (catalog.bandIcon(band).isNotEmpty) ...[
            SizedBox.square(
              dimension: 24,
              child: AppImage(candidates: [catalog.bandIcon(band)]),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            catalog.bandName(band).isEmpty
                ? c.tb('allBands', 'All bands')
                : catalog.bandName(band),
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
    Widget grid(List<Widget> children) => LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 280).floor().clamp(1, 4);
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        ToolSection(
          icon: Symbols.trending_up_rounded,
          title: c.tb('accountTitle', 'Account bonuses'),
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.tb('totalRank', 'Total character rank'),
                      style: theme.textTheme.labelLarge,
                    ),
                    Text('$total', style: theme.textTheme.headlineMedium),
                    Text(
                      c.tb('totalRankAuto', 'Sum of the ranks below'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                ToolField(
                  label: c.tb('vipRank', 'T.G.W card rank'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RankStepper(
                        label: c.tb('vipRank', 'T.G.W card rank'),
                        value: player.vipRank,
                        min: 1,
                        max: maxVip,
                        onChanged: (value) => c.write([('p.vip', value)]),
                      ),
                      if (vip != null && vip != 0) ...[
                        const SizedBox(width: 8),
                        Text('+${(vip / 100).toStringAsFixed(2)}%'),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        ToolSection(
          icon: Symbols.face_rounded,
          title: c.tb('characterRanks', 'Character ranks'),
          trailing: Wrap(
            children: [
              TextButton.icon(
                onPressed: () =>
                    c.write([for (final id in characters) ('cr.$id', maxRank)]),
                icon: const Icon(Symbols.keyboard_double_arrow_up_rounded),
                label: Text('${c.tb('allMax', 'All max')} ($maxRank)'),
              ),
              TextButton(
                onPressed: () =>
                    c.write([for (final id in characters) ('cr.$id', null)]),
                child: Text(c.tb('clearAll', 'Clear')),
              ),
            ],
          ),
          children: [
            for (final band in bands) ...[
              bandName(band),
              grid([
                for (final id in characters)
                  if (master.characters[id] == band)
                    _Row(
                      leading: ClipOval(
                        child: SizedBox.square(
                          dimension: 32,
                          child: AppImage(
                            candidates: [catalog.characterFace(id)],
                          ),
                        ),
                      ),
                      accent: catalog.characterColor(
                        id,
                        theme.colorScheme.primary,
                      ),
                      label: catalog.characterName(id),
                      control: RankStepper(
                        label: catalog.characterName(id),
                        value: player.characterRanks['$id'],
                        min: 1,
                        max: maxRank,
                        onChanged: (value) => c.write([('cr.$id', value)]),
                      ),
                    ),
              ]),
            ],
          ],
        ),
        const SizedBox(height: 16),
        ToolSection(
          icon: Symbols.piano_rounded,
          title: c.tb('bandItems', 'Band items'),
          trailing: TextButton.icon(
            onPressed: () => c.write([
              for (final item in items) ('bi.${item.id}', item.max),
            ]),
            icon: const Icon(Symbols.keyboard_double_arrow_up_rounded),
            label: Text(c.tb('allMax', 'All max')),
          ),
          children: [
            for (final band in {for (final item in items) item.bandId}) ...[
              bandName(band),
              grid([
                for (final item in items)
                  if (item.bandId == band)
                    _Row(
                      label: item.name,
                      control: RankStepper(
                        label: item.name,
                        value: player.bandItems['${item.id}'],
                        min: 0,
                        max: item.max,
                        onChanged: (value) =>
                            c.write([('bi.${item.id}', value)]),
                      ),
                    ),
              ]),
            ],
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.control,
    this.leading,
    this.accent,
  });
  final String label;
  final Widget control;
  final Widget? leading;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: accent == null
            ? null
            : Border(left: BorderSide(color: accent!, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Expanded(
              child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            control,
          ],
        ),
      ),
    );
  }
}

/// − value + with a typed value in between (`tb-stepper`); empty is unset.
class RankStepper extends StatefulWidget {
  const RankStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int? value;
  final int min;
  final int max;
  final ValueChanged<int?> onChanged;

  @override
  State<RankStepper> createState() => _RankStepperState();
}

class _RankStepperState extends State<RankStepper> {
  late final _text = TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  String _format(int? value) => value == null ? '' : '$value';

  @override
  void didUpdateWidget(RankStepper old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _text.text != _format(widget.value)) {
      _text.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  int _clamp(int value) => value.clamp(widget.min, widget.max);

  void _commit() {
    final raw = _text.text.trim();
    widget.onChanged(
      raw.isEmpty ? null : _clamp(int.tryParse(raw) ?? widget.min),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '${widget.label} −1',
            visualDensity: VisualDensity.compact,
            onPressed: value != null && value <= widget.min
                ? null
                : () => widget.onChanged(_clamp((value ?? widget.min) - 1)),
            icon: const Icon(Symbols.remove_rounded, size: 18),
          ),
          SizedBox(
            width: 48,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                hintText: '—',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) {
                if (_focus.hasFocus) {
                  _focus.unfocus();
                  _commit();
                }
              },
            ),
          ),
          IconButton(
            tooltip: '${widget.label} +1',
            visualDensity: VisualDensity.compact,
            onPressed: value != null && value >= widget.max
                ? null
                : () => widget.onChanged(_clamp((value ?? widget.min - 1) + 1)),
            icon: const Icon(Symbols.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
