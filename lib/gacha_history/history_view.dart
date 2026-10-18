class GachaHistoryAccount {
  const GachaHistoryAccount({
    required this.key,
    required this.server,
    required this.serverLabel,
    required this.label,
  });
  final String key, server, serverLabel, label;
}

class GachaHistoryPool {
  const GachaHistoryPool({
    required this.id,
    required this.name,
    required this.category,
  });
  final String id, name, category;
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
  });
  final String id, kind, name, rarityLabel;
  final Object rarity;
  final int quantity;
  final String? imageUrl, href;
  final bool? pickup;
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
    this.cost,
  });
  final String id, accountKey, poolId;
  final DateTime? pulledAt;
  final int? drawCount;
  final List<GachaHistoryPrize> prizes;
  final String? source;
  final GachaHistoryCost? cost;
}

class GachaHistoryExport {
  const GachaHistoryExport({required this.accountKey, required this.batches});
  final String accountKey;
  final List<GachaHistoryBatch> batches;
}

class GachaHistoryCost {
  const GachaHistoryCost({this.freeGems, this.paidGems, this.tickets});
  final num? freeGems, paidGems, tickets;
}

class GachaHistoryConversion {
  const GachaHistoryConversion({
    required this.currencyCode,
    required this.unitGemPrice,
  });
  final String currencyCode;
  final double? unitGemPrice;
}
