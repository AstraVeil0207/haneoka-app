import '../core/api.dart';
import 'history_snapshot.dart';
import 'history_view.dart';

class HistoryCatalog {
  HistoryCatalog._(
    this.api,
    this.metadata,
    this.pools,
    this.cards,
    this.snapshots,
    this.items,
  );
  final HaneokaApi api;
  final Map metadata, pools, cards, snapshots, items;

  static Future<HistoryCatalog> load(HaneokaApi api) async {
    final (pools, cards, snapshots, items) = await (
      api.catalog('gacha'),
      api.catalog('cards'),
      api.catalog('support-cards'),
      api.catalog('items'),
    ).wait;
    final metadata = pools is Map ? pools['history'] : null;
    if (metadata is! Map ||
        metadata['schema'] != 'haneoka-gacha-history-data-v1' ||
        pools is! Map ||
        pools['entries'] is! Map ||
        cards is! Map ||
        snapshots is! Map ||
        items is! Map ||
        items['items'] is! Map) {
      throw const FormatException('history_catalog');
    }
    return HistoryCatalog._(
      api,
      metadata,
      pools['entries'] as Map,
      cards,
      snapshots,
      items['items'] as Map,
    );
  }

  List<GachaHistoryPool> poolViews(
    String Function(Object?) localized,
    String Function(String) categoryLabel,
  ) => [
    for (final MapEntry(:key, :value) in pools.entries)
      if (value is Map)
        GachaHistoryPool(
          id: '$key',
          name: localized(value['title']),
          category: categoryLabel('${value['category'] ?? 'other'}'),
        ),
  ];

  List<GachaHistoryBatch> batchViews(
    HistorySnapshot snapshot,
    String accountKey,
    String Function(Object?) localized,
    String unknownLabel,
  ) {
    final prizeMap = metadata['prizes'] as Map;
    final poolMap = metadata['pools'] as Map;
    return [
      for (final (index, execution) in snapshot.executions.indexed)
        GachaHistoryBatch(
          id: '${snapshot.queriedAt.toUtc().toIso8601String()}:$index',
          accountKey: accountKey,
          poolId: execution.poolId ?? '',
          pulledAt: execution.executedAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  execution.executedAt! * 1000,
                  isUtc: true,
                ),
          // Each history prize is one draw, including a currency item prize.
          // Ticket executions can be smaller than the product's bundle size.
          drawCount: execution.prizes.length,
          prizes: [
            for (final prize in execution.prizes)
              _prizeView(
                prize,
                poolMap[execution.poolId],
                prizeMap,
                localized,
                unknownLabel,
              ),
          ],
          cost: GachaHistoryCost(
            freeGems: execution.freeGems,
            paidGems: execution.paidGems,
            tickets: execution.tickets,
          ),
          source: snapshot.server,
        ),
    ];
  }

  GachaHistoryPrize _prizeView(
    HistoryPrize prize,
    Object? pool,
    Map prizeMap,
    String Function(Object?) localized,
    String unknownLabel,
  ) {
    final row = prizeMap[prize.prizeId];
    final type = row is Map ? row['resourceType'] : null;
    final id = row is Map ? '${row['resourceId']}' : '';
    final collection = type == 2
        ? cards
        : type == 3
        ? snapshots
        : type == 1
        ? items
        : const {};
    final card = collection[id];
    final images = card is Map ? card['images'] : null;
    final image = images is Map
        ? images['thumbnail']
        : card is Map
        ? card['image']
        : null;
    final rarity = card is Map ? card['rarity'] : null;
    final groups = pool is Map ? pool['prizeGroupIds'] : null;
    final knownGroup =
        row is Map && groups is List && groups.contains(row['groupId']);
    return GachaHistoryPrize(
      id: id.isEmpty ? 'prize:${prize.prizeId}' : id,
      kind: type == 2
          ? 'member'
          : type == 3
          ? 'support'
          : type == 1
          ? 'item'
          : 'unknown',
      name: card is Map
          ? localized(card['prefix'] ?? card['cardName'] ?? card['name'])
          : '$unknownLabel · ${prize.prizeId}',
      rarity: rarity is num || rarity is String ? rarity! : '',
      rarityLabel: type == 1
          ? ''
          : const {2: 'R', 3: 'SR', 4: 'SSR', 10: 'EX', 20: 'BD'}[rarity] ??
                unknownLabel,
      quantity: row is Map && row['count'] is int ? row['count'] as int : 1,
      imageUrl: image is String && image.isNotEmpty
          ? api.asset(image).toString()
          : null,
      href: type == 2
          ? '/catalog/member-cards/$id'
          : type == 3
          ? '/catalog/support-cards/$id'
          : null,
      pickup: knownGroup ? row['pickupType'] == 2 : null,
    );
  }
}
