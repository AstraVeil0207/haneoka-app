import 'package:game_data_exporter/gacha_history_analysis.dart' as analysis;

class GachaHistoryAccount {
  const GachaHistoryAccount({
    required this.key,
    required this.server,
    required this.serverLabel,
    required this.label,
    this.offsetMinutes = 480,
  });
  final String key, server, serverLabel, label;
  final int offsetMinutes;
}

class GachaHistoryPool {
  const GachaHistoryPool({
    required this.id,
    required this.name,
    required this.category,
    this.imageUrl,
    this.exchangeTargets = const [],
  });
  final String id, name, category;
  final String? imageUrl;
  final List<Map<String, Object?>> exchangeTargets;
}

class GachaHistoryPrize {
  const GachaHistoryPrize({
    required this.id,
    required this.kind,
    required this.name,
    required this.rarity,
    required this.rarityLabel,
    required this.quantity,
    this.imageUrl,
    this.href,
    this.pickup,
    this.converted = false,
    this.attributeImageUrl,
    this.rarityImageUrl,
  });
  final String id, kind, name, rarityLabel;
  final Object rarity;
  final int quantity;
  final String? imageUrl, href;
  final bool? pickup;
  final bool converted;
  final String? attributeImageUrl, rarityImageUrl;
}

class GachaHistoryBatch {
  const GachaHistoryBatch({
    required this.id,
    required this.accountKey,
    required this.poolId,
    required this.pulledAt,
    required this.drawCount,
    required this.prizes,
    this.source,
    this.productId,
    this.expected,
    this.cost,
  });
  final String id, accountKey, poolId;
  final DateTime? pulledAt;
  final int? drawCount;
  final List<GachaHistoryPrize> prizes;
  final String? source;
  final String? productId;
  final GachaHistoryCost? cost;
  final Map<String, num>? expected;
}

Map<String, Object?> historyAnalysis(
  List<GachaHistoryBatch> batches, [
  int offsetMinutes = 480,
]) => analysis.analyzeGachaHistory(_historyInput(batches), offsetMinutes);

Map<String, Object?> historyProgress(List<GachaHistoryBatch> batches) =>
    analysis.gachaHistoryProgress(_historyInput(batches));

List<Map<String, Object?>> _historyInput(List<GachaHistoryBatch> batches) => [
  for (final batch in batches)
    <String, Object?>{
      'id': batch.id,
      'poolId': batch.poolId,
      'pulledAt': batch.pulledAt?.toUtc().toIso8601String(),
      'expected': batch.expected,
      'cost': <String, Object?>{
        'freeGems': batch.cost?.freeGems,
        'paidGems': batch.cost?.paidGems,
        'tickets': batch.cost?.tickets,
      },
      'prizes': [
        for (final prize in batch.prizes)
          <String, Object?>{
            'id': prize.id,
            'kind': prize.kind,
            'rarity': prize.rarity,
            'quantity': prize.quantity,
            'pickup': prize.pickup,
            'converted': prize.converted,
          },
      ],
    },
];

class GachaHistoryExport {
  const GachaHistoryExport({
    required this.accountKey,
    required this.batches,
    this.historyKind,
  });
  final String accountKey;
  final String? historyKind;
  final List<GachaHistoryBatch> batches;
}

class GachaHistoryCost {
  const GachaHistoryCost({this.freeGems, this.paidGems, this.tickets});
  final num? freeGems, paidGems, tickets;
}

class GachaHistoryConversion {
  const GachaHistoryConversion({
    required this.currencyCode,
    this.freeUnitGemPrice = 0,
    this.paidUnitGemPrice,
  });
  final String currencyCode;
  final double? freeUnitGemPrice, paidUnitGemPrice;
}
