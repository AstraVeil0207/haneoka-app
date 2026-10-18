import 'dart:math' as math;

import '../core/api.dart';

typedef ScoreRank = ({int rank, int required, int battleRequired});
typedef PowerNeeded = ({int mean, int every, int best});

class DeckSlot {
  const DeckSlot({this.score = 100, this.perfect = 0, this.extensionMs = 0});
  final double score, perfect;
  final int extensionMs;
  DeckSlot copyWith({double? score, double? perfect, int? extensionMs}) =>
      DeckSlot(
        score: score ?? this.score,
        perfect: perfect ?? this.perfect,
        extensionMs: extensionMs ?? this.extensionMs,
      );
  String get encoded => '$score:$perfect:$extensionMs';
}

class ChartRates {
  ChartRates.fromJson(Map value)
    : base = (value['base'] as num).toDouble(),
      windows = [
        for (final row in value['windows'] as List)
          [for (final v in row as List) (v as num).toDouble()],
      ],
      skip = (value['skip'] as num).toDouble(),
      notes = (value['notes'] as num).toInt(),
      ranks = [
        for (final row in value['ranks'] as List)
          (
            rank: (row[0] as num).toInt(),
            required: (row[1] as num).toInt(),
            battleRequired: (row[2] as num).toInt(),
          ),
      ];
  final double base, skip;
  final int notes;
  final List<List<double>> windows;
  final List<ScoreRank> ranks;
}

class RateEvent {
  RateEvent.fromJson(Map value)
    : id = (value['id'] as num).toInt(),
      title = value['title'],
      startAt = (value['startAt'] as num?)?.toInt(),
      endAt = (value['endAt'] as num?)?.toInt(),
      points = [
        for (final row in value['points'] as List)
          [for (final v in row as List) (v as num).toInt()],
      ],
      items = [
        for (final row in value['items'] as List)
          [for (final v in row as List) (v as num).toInt()],
      ];
  final int id;
  final Object? title;
  final int? startAt, endAt;
  final List<List<int>> points, items;
}

class ChartRateTable {
  ChartRateTable.fromJson(Map value)
    : releaseId = '${value['releaseId']}',
      greatFactor = (value['greatFactor'] as num).toDouble(),
      boosts = [
        for (final row in value['boosts'] as List)
          [for (final v in row as List) (v as num).toInt()],
      ],
      events = [
        for (final row in value['events'] as List)
          RateEvent.fromJson(row as Map),
      ],
      charts = {
        for (final e in (value['charts'] as Map).entries)
          '${e.key}': ChartRates.fromJson(e.value as Map),
      };
  final String releaseId;
  final double greatFactor;
  final List<List<int>> boosts;
  final List<RateEvent> events;
  final Map<String, ChartRates> charts;
  static Future<ChartRateTable> load(HaneokaApi api) async =>
      ChartRateTable.fromJson(
        await api.json('/data/chart-rates/${api.server}.json') as Map,
      );
}

final skillOrders = (() {
  final result = <List<int>>[];
  void walk(List<int> prefix) {
    if (prefix.length == 5) {
      result.add(prefix);
      return;
    }
    for (var i = 0; i < 5; i++) {
      if (!prefix.contains(i)) walk([...prefix, i]);
    }
  }

  walk([]);
  return result;
})();

int roomRequiredScore(int battleRequired, int players) {
  if (players < 1) return 2147483647;
  final value = (math.sqrt(5 / players) * battleRequired * players).truncate();
  return value > 2147483647 ? -2147483648 : value;
}

({int rank, ({int rank, int required})? next}) roomRank(
  List<ScoreRank> ranks,
  int total,
  int players,
) {
  var rank = 2;
  for (final row in ranks) {
    final required = roomRequiredScore(row.battleRequired, players);
    if (required > total) {
      return (rank: rank, next: (rank: row.rank, required: required));
    }
    rank = row.rank;
  }
  return (rank: math.max(2, rank), next: null);
}

List<double> slotOrderRates(
  ChartRates rates,
  List<DeckSlot> slots, {
  double great = 0,
  double greatFactor = .8,
}) {
  final general = 1 - great * (1 - greatFactor);
  return [
    for (final order in skillOrders)
      () {
        var score = rates.base * general;
        for (var event = 0; event < rates.windows.first.length; event++) {
          final slot = slots[order[event]];
          final w = (slot.extensionMs / 250).round().clamp(
            0,
            rates.windows.length - 1,
          );
          score +=
              slot.score / 100 * (rates.windows[w][event] * general) +
              slot.perfect / 100 * (rates.windows[w][event] * (1 - great));
        }
        return score;
      }(),
  ];
}

double certainScore(num power, double rate, int notes) =>
    power * rate * (1 - 2e-6) - notes;

PowerNeeded slotPowerNeeded(num target, List<double> orderRates, int notes) {
  if (target <= 0) return (mean: 0, every: 0, best: 0);
  int power(double rate) => ((target + notes) / (rate * (1 - 2e-6))).ceil();
  return (
    mean: power(orderRates.reduce((a, b) => a + b) / orderRates.length),
    every: power(orderRates.reduce(math.min)),
    best: power(orderRates.reduce(math.max)),
  );
}

double slotReach(num target, num power, List<double> orderRates, int notes) =>
    orderRates
        .where((rate) => certainScore(power, rate, notes) >= target)
        .length /
    orderRates.length;

PowerNeeded teamPowerNeeded(
  num target,
  List<double> scores,
  num power,
  int notes,
) =>
    slotPowerNeeded(target, [for (final score in scores) score / power], notes);

int soloRank(List<ScoreRank> ranks, num score) {
  var rank = 2;
  for (final row in ranks) {
    if (row.required <= score) rank = math.max(rank, row.rank);
  }
  return rank;
}

int _imul(int a, int b) => (a * b).toSigned(32);
int eventLivePoints(int points, num bonusPercent, int rate) =>
    (_imul(_imul((bonusPercent * 100).round() + 10000, rate), points) / 10000)
        .truncate();
double eventLiveItems(
  List<List<int>> items,
  int rank,
  num bonusPercent,
  int rate,
) {
  var total = 0.0;
  for (final row in items) {
    if (row[0] == rank) {
      total +=
          (_imul(_imul(row[1], (bonusPercent * 100).round() + 10000), rate) /
                  10000)
              .truncate() *
          row[2] /
          10000;
    }
  }
  return total;
}
