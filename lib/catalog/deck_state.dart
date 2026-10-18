import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chart_rates.dart';

class AnalysisDeck {
  const AnalysisDeck({
    this.power = 1000000,
    this.slots = const [
      DeckSlot(),
      DeckSlot(),
      DeckSlot(),
      DeckSlot(),
      DeckSlot(),
    ],
    this.rank = 7,
    this.room = 5,
    this.great = 0,
    this.overhead = 30,
    this.event = 0,
    this.boosts = 0,
    this.pointBonus = 0,
    this.itemBonus = 0,
  });
  final int power,
      rank,
      room,
      great,
      overhead,
      event,
      boosts,
      pointBonus,
      itemBonus;
  final List<DeckSlot> slots;
  AnalysisDeck copyWith({
    int? power,
    List<DeckSlot>? slots,
    int? rank,
    int? room,
    int? great,
    int? overhead,
    int? event,
    int? boosts,
    int? pointBonus,
    int? itemBonus,
  }) => AnalysisDeck(
    power: power ?? this.power,
    slots: slots ?? this.slots,
    rank: rank ?? this.rank,
    room: room ?? this.room,
    great: great ?? this.great,
    overhead: overhead ?? this.overhead,
    event: event ?? this.event,
    boosts: boosts ?? this.boosts,
    pointBonus: pointBonus ?? this.pointBonus,
    itemBonus: itemBonus ?? this.itemBonus,
  );
  factory AnalysisDeck.parse(
    Map<String, String> query, {
    AnalysisDeck fallback = const AnalysisDeck(),
  }) {
    int number(String key, int low, int high, int old) {
      final value = double.tryParse(query[key] ?? '');
      return value != null && value.isFinite
          ? value.round().clamp(low, high)
          : old;
    }

    List<DeckSlot>? parseSlots(String? raw) {
      final parts = raw?.split(',');
      if (parts?.length != 5) return null;
      final result = <DeckSlot>[];
      for (final part in parts!) {
        final v = part.split(':').map(double.tryParse).toList();
        if (v.any((x) => x == null || !x.isFinite || x < 0)) return null;
        result.add(
          DeckSlot(
            score: v[0]!,
            perfect: v.elementAtOrNull(1) ?? 0,
            extensionMs: (v.elementAtOrNull(2) ?? 0).round(),
          ),
        );
      }
      return result;
    }

    return AnalysisDeck(
      power: number('deckPower', 1, 99999999, fallback.power),
      slots:
          parseSlots(query['deckSlots']) ??
          parseSlots(query['deckSkills']) ??
          fallback.slots,
      rank: number('deckRank', 3, 7, fallback.rank),
      room: number('deckRoom', 1, 5, fallback.room),
      great: number('deckGreat', 0, 100, fallback.great),
      overhead: number('deckOverhead', 0, 600, fallback.overhead),
      event: number('deckEvent', 0, 99999, fallback.event),
      boosts: number('deckBoosts', 0, 10, fallback.boosts),
      pointBonus: number('deckPointBonus', 0, 100000, fallback.pointBonus),
      itemBonus: number('deckItemBonus', 0, 100000, fallback.itemBonus),
    );
  }
  Map<String, String> get query => {
    'deckPower': '$power',
    'deckSlots': slots.map((s) => s.encoded).join(','),
    'deckRank': '$rank',
    'deckRoom': '$room',
    'deckGreat': '$great',
    'deckOverhead': '$overhead',
    'deckEvent': '$event',
    'deckBoosts': '$boosts',
    'deckPointBonus': '$pointBonus',
    'deckItemBonus': '$itemBonus',
  };
}

/// One remembered deck shared by song analysis, song details and result links.
class AnalysisDeckController extends ChangeNotifier {
  AnalysisDeckController._();
  static final instance = AnalysisDeckController._();
  AnalysisDeck value = const AnalysisDeck();
  Future<void>? _loading;
  Future<void> load([Map<String, String>? query]) async {
    await (_loading ??= () async {
      final prefs = await SharedPreferences.getInstance(),
          raw = prefs.getString('haneoka.deck');
      if (raw != null) value = AnalysisDeck.parse(Uri.splitQueryString(raw));
      notifyListeners();
    }());
    if (query?.keys.any((key) => key.startsWith('deck')) ?? false) {
      set(AnalysisDeck.parse(query!, fallback: value));
    }
  }

  void set(AnalysisDeck deck) {
    value = deck;
    notifyListeners();
    unawaited(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'haneoka.deck',
        Uri(queryParameters: deck.query).query,
      );
    }());
  }
}
