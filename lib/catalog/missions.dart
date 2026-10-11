import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import '../core/relative_time.dart';
import '../shell/links.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/shapes.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';

const _categoryIcons = {
  'limited': Symbols.schedule_rounded,
  'daily': Symbols.event_repeat_rounded,
  'unlocks': Symbols.lock_open_rounded,
  'story': Symbols.menu_book_rounded,
  'performance': Symbols.mic_rounded,
  'growth': Symbols.trending_up_rounded,
  'hidden': Symbols.visibility_off_rounded,
};
const _categoryLabels = {
  'daily': ('missionDaily', 'Daily missions'),
  'unlocks': ('missionUnlocks', 'Song & scene unlocks'),
  'story': ('missionStory', 'Story reading'),
  'performance': ('missionPerformance', 'Performance challenges'),
  'growth': ('missionGrowth', 'Growth'),
  'hidden': ('missionHidden', 'Hidden missions'),
};
const _categoryOrder = [
  'limited',
  'daily',
  'unlocks',
  'story',
  'performance',
  'growth',
  'hidden',
];

num _time(Object? value) => RelativeTime.timestamp(value) ?? 0;

/// Standing missions carry their MasterMission category in the id
/// (`regular-mission-<category><sequence>`): 10 daily, 15/16 song and scene
/// unlocks, 90/95 hidden; the rest split by mission type.
String _category(Map mission) {
  if (mission['kind'] == 'limited-mission') return 'limited';
  final digits = RegExp(r'(\d+)$').firstMatch('${mission['id']}')?[1] ?? '';
  final prefix = int.tryParse(digits.length >= 2 ? digits.substring(0, 2) : '');
  if (prefix == 10) return 'daily';
  if (prefix == 15 || prefix == 16) return 'unlocks';
  if (prefix == 90 || prefix == 95) return 'hidden';
  final type = mission['missionType'];
  if (type == 104 || type == 105) return 'story';
  if (type == 122 || type == 124) return 'performance';
  return 'growth';
}

class _Group {
  _Group(this.key, this.title, this.category, this.rows);
  final String key;
  final String title;
  final String category;
  List<Map> rows;
  num start = 0, end = 0;
}

String _label(
  SiteText t,
  String key,
  String fallback, [
  Map<String, Object?> values = const {},
]) => t.system(key, fallback, values);

String _date(SiteText t, num value) => value <= 0
    ? ''
    : DateFormat.yMMMd(t.locale)
          .format(DateTime.fromMillisecondsSinceEpoch(value.toInt()));

String _window(SiteText t, _Group group) {
  if (group.category == 'daily') {
    return _label(t, 'missionDailyReset', 'Resets daily');
  }
  if (group.start == 0 && group.end == 0) {
    return _label(t, 'missionNoEnd', 'No end date');
  }
  return group.start > 0 && group.end > 0
      ? '${_date(t, group.start)} – ${_date(t, group.end)}'
      : _date(t, group.start > 0 ? group.start : group.end);
}

/// One reward as the website's `.mission-chip`: emblem, name, quantity.
class _RewardChip extends StatelessWidget {
  const _RewardChip(this.reward, {this.color});
  final Map reward;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = t.text(reward['name']);
    if (title.isEmpty) return const SizedBox.shrink();
    final count = (reward['count'] as num?) ?? 0;
    final image = reward['image'];
    final href = reward['href'];
    return Material(
      color: color ?? scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(Corner.small),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: href is String && href.isNotEmpty
            ? () => openLink(context, href)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 24,
                child: image is String && image.isNotEmpty
                    ? AppImage(candidates: [state.api.asset(image).toString()])
                    : Icon(
                        Symbols.redeem_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (count > 1)
                Text(
                  ' ×${NumberFormat.decimalPattern(t.locale).format(count)}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Missions (`mission-workspace`): an overview of mission groups — limited
/// windows first, then the standing categories — each opening its list of
/// one-line conditions with rewards.
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});
  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  Future<Object?>? _data;
  String _mode = 'all';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= AppScope.of(context).api.catalog('missions');
  }

  /// Limited groups first (newest window first), then the standing
  /// categories in game order.
  List<_Group> _groups(SiteText t, List<Map> missions) {
    final buckets = <String, _Group>{};
    for (final mission in missions) {
      final limited = mission['kind'] == 'limited-mission';
      if (_mode == 'limited' && !limited || _mode == 'regular' && limited) {
        continue;
      }
      final category = _category(mission);
      final title = category == 'limited'
          ? (t.text(mission['group']).isEmpty
                ? _label(t, 'limitedMission', 'Limited mission')
                : t.text(mission['group']))
          : _label(
              t,
              _categoryLabels[category]!.$1,
              _categoryLabels[category]!.$2,
            );
      final key = category == 'limited'
          ? 'limited-${t.textIn(mission['group'], 'ja').isEmpty ? title : t.textIn(mission['group'], 'ja')}'
          : category;
      (buckets[key] ??= _Group(key, title, category, [])).rows.add(mission);
    }
    for (final group in buckets.values) {
      if (group.category != 'limited') continue;
      group.start = group.rows
          .map((row) => _time(row['startAt']))
          .fold(0, (a, b) => a > b ? a : b);
      group.end = group.rows
          .map((row) => _time(row['endAt']))
          .fold(0, (a, b) => a > b ? a : b);
      final indexed = [for (final (i, row) in group.rows.indexed) (i, row)]
        ..sort((a, b) {
          final order = _time(b.$2['startAt'])
              .compareTo(_time(a.$2['startAt']));
          return order != 0 ? order : a.$1 - b.$1;
        });
      group.rows = [for (final (_, row) in indexed) row];
    }
    final ordered =
        [for (final (i, group) in buckets.values.indexed) (i, group)]
          ..sort((a, b) {
            final category = _categoryOrder
                .indexOf(a.$2.category)
                .compareTo(_categoryOrder.indexOf(b.$2.category));
            if (category != 0) return category;
            final start = b.$2.start.compareTo(a.$2.start);
            return start != 0 ? start : a.$1 - b.$1;
          });
    return [for (final (_, group) in ordered) group];
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    return ShellPage(
      title: t('navigation.missions', 'Missions'),
      body: FutureBuilder(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.tonal(
                onPressed: () =>
                    setState(() => _data = state.api.catalog('missions')),
                child: Text(t('common.actions.retry', 'Retry')),
              ),
            );
          }
          final document = snapshot.data;
          if (document == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = document is Map ? document['entries'] : null;
          final missions = switch (entries) {
            Map() => entries.values.whereType<Map>().toList(),
            List() => entries.whereType<Map>().toList(),
            _ => <Map>[],
          };
          final groups = _groups(t, missions);
          return LayoutBuilder(
            builder: (context, constraints) {
              final padding = pagePadding(context);
              final width = constraints.maxWidth - padding.horizontal;
              final columns = ((width + 12) / 332).floor().clamp(1, 6);
              final card = (width - 12 * (columns - 1)) / columns;
              return ListView(
                padding: padding,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: 'all',
                            icon: const Icon(Symbols.apps_rounded),
                            label: Text(t('common.states.all', 'All')),
                          ),
                          ButtonSegment(
                            value: 'regular',
                            icon: const Icon(Symbols.fact_check_rounded),
                            label: Text(_label(t, 'regularMission', 'Mission')),
                          ),
                          ButtonSegment(
                            value: 'limited',
                            icon: const Icon(Symbols.schedule_rounded),
                            label: Text(
                              _label(t, 'limitedMission', 'Limited mission'),
                            ),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (value) =>
                            setState(() => _mode = value.single),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final group in groups)
                        SizedBox(width: card, child: _GroupCard(group)),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Rewards summed across a group's missions, in first-seen order.
List<Map> _rewardTotals(SiteText t, List<Map> rows) {
  final totals = <String, Map>{};
  for (final mission in rows) {
    for (final reward
        in (mission['rewards'] as List? ?? const []).whereType<Map>()) {
      final name = t.text(reward['name']);
      if (name.isEmpty) continue;
      final key =
          '${reward['kind'] ?? ''}:${reward['resourceType'] ?? ''}:${reward['resourceId'] ?? name}';
      final count = (reward['count'] as num?) ?? 1;
      final entry = totals[key];
      if (entry != null) {
        entry['count'] = (entry['count'] as num) + count;
      } else {
        totals[key] = {...reward, 'count': count, 'href': ''};
      }
    }
  }
  return totals.values.toList();
}

class _GroupCard extends StatelessWidget {
  const _GroupCard(this.group);
  final _Group group;

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = _rewardTotals(t, group.rows);
    final limited = group.category == 'limited';
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Corner.extraLarge),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => _GroupScreen(group))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShapedIcon(
                    shape: MaterialShapes.cookie9Sided,
                    size: 48,
                    color: limited ? scheme.tertiaryContainer : null,
                    foreground: limited ? scheme.onTertiaryContainer : null,
                    child: Icon(_categoryIcons[group.category], size: 24),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(Corner.full),
                    ),
                    child: Text(
                      _label(t, 'missionCount', '{count} missions', {
                        'count': NumberFormat.decimalPattern(t.locale)
                            .format(group.rows.length),
                      }),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                group.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Symbols.schedule_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _window(t, group),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (totals.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final reward in totals.take(4))
                        _RewardChip(reward, color: scheme.surfaceContainerHigh),
                      if (totals.length > 4)
                        Text(
                          '+${totals.length - 4}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One group's missions: each condition on a line with its rewards.
class _GroupScreen extends StatelessWidget {
  const _GroupScreen(this.group);
  final _Group group;

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ShellPage(
      title: group.title,
      status: Text('${group.rows.length}'),
      body: ListView(
        padding: pagePadding(context),
        children: [
          Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(Corner.extraLarge),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Row(
                      children: [
                        ShapedIcon(
                          shape: MaterialShapes.cookie9Sided,
                          size: 40,
                          child: Icon(_categoryIcons[group.category], size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _window(t, group),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final (index, mission) in group.rows.indexed) ...[
                    if (index > 0)
                      Divider(height: 1, color: scheme.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 40),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            Text(
                              t.text(mission['title']).isEmpty
                                  ? '—'
                                  : t.text(mission['title']),
                              style: theme.textTheme.bodyLarge,
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final reward
                                    in (mission['rewards'] as List? ?? const [])
                                        .whereType<Map>())
                                  _RewardChip(reward),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
