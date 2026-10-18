import 'package:flutter/material.dart';

import '../catalog/chart_rates.dart';
import 'controller.dart';
import 'engine/api.dart';
import 'settings.dart';
import 'widgets.dart';

/// Rank targets from the result's actual 120 skill-order scores.
class TeamRankTargets extends StatelessWidget {
  const TeamRankTargets({
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
    final c = controller,
        score = hit.score,
        song = c.catalog!.master.songs[hit.song?.songId];
    if (score == null || score.orders.isEmpty || song == null || hit.power <= 0) {
      return const SizedBox.shrink();
    }
    final notes =
        song.difficulties
            .where((d) => d.difficulty == hit.song?.difficulty)
            .firstOrNull
            ?.noteCount ??
        0;
    final ranks = [
      for (final row in c.catalog!.master.scoreRanks[song.rankGroup] ?? [])
        if (row.rank >= 3) row,
    ]..sort((a, b) => b.rank.compareTo(a.rank));
    if (ranks.isEmpty) return const SizedBox.shrink();
    final gekisou = settings.goal == GoalKind.gekiso;
    String t(String key, String fallback) => c.tb(key, fallback);
    String number(int n) => formatNumber(c.state.text.locale, n);
    PowerNeeded need(num target) => teamPowerNeeded(
      target,
      [for (final value in score.orders) value.toDouble()],
      hit.power,
      notes,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          horizontalMargin: 0,
          columnSpacing: 20,
          columns: [
            DataColumn(label: Text(t('powerNeeded', 'Power needed'))),
            if (gekisou)
              for (var i = 1; i <= 5; i++)
                DataColumn(
                  numeric: true,
                  label: Text(
                    (i == 1
                            ? t('roomPlayer', '1 player')
                            : t('roomPlayers', '{count} players'))
                        .replaceAll('{count}', i.toString()),
                  ),
                )
            else ...[
              DataColumn(
                numeric: true,
                label: Text(t('averageOrder', 'Average of the orders')),
              ),
              DataColumn(
                numeric: true,
                label: Text(t('everyOrder', 'Every order')),
              ),
              DataColumn(
                numeric: true,
                label: Text(t('bestOrder', 'Best order')),
              ),
            ],
          ],
          rows: [
            for (final row in ranks)
              DataRow(
                cells: [
                  DataCell(
                    Text(
                      const ['', 'E', 'D', 'C', 'B', 'A', 'S', 'SS'][row.rank],
                    ),
                  ),
                  if (gekisou)
                    for (var players = 1; players <= 5; players++)
                      DataCell(
                        Text(
                          number(
                            need(
                              (roomRequiredScore(row.battleRequired, players) /
                                      players)
                                  .ceil(),
                            ).mean,
                          ),
                        ),
                      )
                  else
                    ...() {
                      final value = need(row.required);
                      return [
                        DataCell(Text(number(value.mean))),
                        DataCell(Text(number(value.every))),
                        DataCell(Text(number(value.best))),
                      ];
                    }(),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
