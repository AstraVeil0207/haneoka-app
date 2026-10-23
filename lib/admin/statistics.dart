import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../chart_editor/project.dart';
import '../core/app_state.dart';
import '../ui/detail.dart';

class AdminStatistics extends StatelessWidget {
  const AdminStatistics({super.key, required this.document, this.onMetric});
  final ChartMap document;
  final ValueChanged<String>? onMetric;
  @override
  Widget build(BuildContext context) {
    final text = AppScope.of(context).text;
    String t(String key) => text('admin.page.$key');
    final number = NumberFormat.decimalPattern(text.locale);
    final metrics = chartMap(document['overview'] ?? const {}),
        statistics = chartMap(document['statistics'] ?? const {});
    String count(String group, String key) {
      final row = group == 'sessions'
          ? document['sessionCounts']
          : statistics[group];
      final value = row is Map ? row[key] : null;
      return value is num ? number.format(value) : '0';
    }

    String state(String key) => switch (key) {
      'total' ||
      'publicEligible' ||
      'allowedAfterFailure' ||
      'queued' => t('workspace.$key'),
      _ => t('values.$key'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailSection(
          icon: Symbols.monitoring_rounded,
          title: t('workspace.currentCounts'),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / 220).floor().clamp(1, 4);
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final entry in metrics.entries)
                    if (entry.value is num &&
                        t('metrics.${entry.key}').isNotEmpty)
                      SizedBox(
                        width: width,
                        child: Card.filled(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onMetric == null
                                ? null
                                : () => onMetric!(entry.key),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.key == 'activeUsers'
                                        ? t('workspace.activeAccounts')
                                        : t('metrics.${entry.key}'),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    number.format(entry.value),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
        DetailFold(
          title: t('workspace.statistics'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailSection(
                icon: Symbols.group_rounded,
                title: t('workspace.accounts'),
                child: SpecList(
                  facts: [
                    Fact(
                      t('workspace.verifiedAccounts'),
                      count('users', 'verified'),
                    ),
                    Fact(
                      t('workspace.activeSessions'),
                      count('sessions', 'active'),
                    ),
                  ],
                ),
              ),
              for (final group in const [
                (
                  'posts',
                  'postTotals',
                  ['total', 'publicEligible', 'archived', 'deleted'],
                ),
                ('comments', 'commentTotals', ['total', 'hidden', 'deleted']),
                ('postStatus', 'postStatus', ['draft', 'published', 'hidden']),
                (
                  'postModeration',
                  'postModeration',
                  ['pending', 'review', 'allow', 'block'],
                ),
                (
                  'attachments',
                  'attachmentStatus',
                  [
                    'reserved',
                    'scanning',
                    'review',
                    'rejected',
                    'ready',
                    'deleted',
                  ],
                ),
                (
                  'mediaJobs',
                  'mediaProcessing',
                  ['queued', 'processing', 'ready', 'failed'],
                ),
                (
                  'moderationJobs',
                  'moderationJobs',
                  ['queued', 'processing', 'succeeded', 'failed'],
                ),
                (
                  'moderationFallback',
                  'moderationFallback',
                  ['allowedAfterFailure'],
                ),
              ])
                DetailSection(
                  icon: Symbols.bar_chart_rounded,
                  title: t('workspace.${group.$2}'),
                  child: SpecList(
                    facts: [
                      for (final key in group.$3)
                        Fact(state(key), count(group.$1, key)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
