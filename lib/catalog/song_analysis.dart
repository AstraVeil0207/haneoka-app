import 'chart_rates.dart';
import 'deck_state.dart';

const liveAnalysisMetrics = {
  'deckScore': 'metaDeckScore',
  'deckPower': 'metaDeckPower',
  'deckPowerEvery': 'metaDeckPowerEvery',
  'deckReach': 'metaDeckReach',
  'deckPerMinute': 'metaDeckPerMinute',
  'deckSkip': 'metaDeckSkip',
  'eventPoints': 'metaEventPoints',
  'eventPointsHour': 'metaEventPointsHour',
  'eventItemsHour': 'metaEventItemsHour',
};
const rankAnalysisMetrics = {
  'rankC': 3,
  'rankB': 4,
  'rankA': 5,
  'rankS': 6,
  'rankSS': 7,
};

/// A chart's view of the shared deck and release-produced score weights.
class SongAnalysis {
  SongAnalysis({
    required this.table,
    required this.rates,
    required this.deck,
    required this.seconds,
  });
  final ChartRateTable table;
  final ChartRates rates;
  final AnalysisDeck deck;
  final double seconds;
  late final orders = slotOrderRates(
    rates,
    deck.slots,
    great: deck.great / 100,
    greatFactor: table.greatFactor,
  );
  RateEvent? get event {
    if (deck.event != 0) {
      return table.events.where((e) => e.id == deck.event).firstOrNull;
    }
    final started = table.events
        .where(
          (e) =>
              e.startAt != null &&
              e.startAt! <= DateTime.now().millisecondsSinceEpoch,
        )
        .toList();
    final rows = started.isEmpty ? [...table.events] : started;
    rows.sort((a, b) => (b.startAt ?? 0).compareTo(a.startAt ?? 0));
    return rows.firstOrNull;
  }

  double _mean(num Function(double) value) =>
      orders.fold<double>(0, (sum, rate) => sum + value(rate)) / orders.length;
  num? value(String key, {bool gekisou = false}) {
    final rank = rankAnalysisMetrics[key] ?? deck.rank,
        row = rates.ranks.where((r) => r.rank == rank).firstOrNull;
    if (rankAnalysisMetrics.containsKey(key)) {
      return row == null
          ? null
          : gekisou
          ? roomRequiredScore(row.battleRequired, deck.room)
          : row.required;
    }
    if (gekisou) return null;
    if (key == 'deckScore') return _mean((r) => deck.power * r).floor();
    if (key == 'deckSkip') return (deck.power * rates.skip).floor();
    if (key == 'deckPerMinute') {
      return seconds > 0
          ? (_mean((r) => deck.power * r) * 60 / (seconds + deck.overhead))
                .floor()
          : null;
    }
    if (key.startsWith('event')) {
      final selected = event;
      if (selected == null) return null;
      final boost = table.boosts.where((b) => b[0] == deck.boosts).firstOrNull;
      final pointRate = deck.boosts > 0 && boost != null ? boost[1] : 1,
          itemRate = deck.boosts > 0 && boost != null ? boost[2] : 1;
      final perPlay = _mean((rate) {
        final rank = soloRank(
          rates.ranks,
          certainScore(deck.power, rate, rates.notes),
        );
        return key == 'eventItemsHour'
            ? eventLiveItems(selected.items, rank, deck.itemBonus, itemRate)
            : eventLivePoints(
                selected.points
                        .where((r) => r[0] == rank)
                        .firstOrNull
                        ?.elementAtOrNull(1) ??
                    0,
                deck.pointBonus,
                pointRate,
              );
      });
      return key == 'eventPoints'
          ? perPlay
          : seconds > 0
          ? perPlay * 3600 / (seconds + deck.overhead)
          : null;
    }
    if (row == null) return null;
    if (key == 'deckReach') {
      return slotReach(row.required, deck.power, orders, rates.notes);
    }
    final needed = slotPowerNeeded(row.required, orders, rates.notes);
    return key == 'deckPower' ? needed.mean : needed.every;
  }
}
