import 'game_save.dart';

/// The parts of a save the app presents, each with its own rows. Field names
/// are the game's own (`App.Local.Player` and the local data documents).
enum SaveSection {
  memberCards('_memberCards'),
  snapshots('_supportCards'),
  characters('_characters'),
  friendships('_characterFriendships'),
  bandItems('_bandItems'),
  items('_items'),
  songs('_liveMusicResults'),
  ratings('_topHighScoreRatings'),
  challengeSongs('_challengeMusicResults'),
  events('_events'),
  challengeLives('_challengeLives'),
  gacha('_gachaRecords'),
  stories('_storyEpisodeRecords'),
  decks('_decks'),
  missions('_normalMissions'),
  limitedMissions('_limitedMissions'),
  characterMissions('_characterMissions'),
  seasonPass('_playerSeasonPass'),
  monthlyPass('_monthlyPass'),
  loginBonuses('_receivedLoginBonuses'),
  costumes('_unlockedCostumes'),
  currentCostumes('_currentCostumes'),
  backgrounds('_backgrounds'),
  stamps('_stamps'),
  degrees('_degrees'),
  profileCards('_playerProfileCards'),
  laneSkins('_liveLaneSkins'),
  noteSkins('_liveNoteSkins'),
  noteEffectSkins('_liveNoteEffectSkins'),
  noteSounds('_liveNoteSeGroups'),
  spots('_spots'),
  memory('_memory'),
  liveBoost('_liveBoost'),
  liveSkip('_liveSkip'),
  vip('_vip'),
  offlineBonus('_offlineBonus'),
  arena('_arenaLeagues');

  const SaveSection(this.field);

  /// The key in `_player`.
  final String field;
}

/// A read-only view over one save.
class SaveView {
  SaveView(this.save);
  final GameSave save;

  Map<String, Object?> get player => save.player;
  Map<String, Object?> get settings {
    final cache = save.documents[SaveDocumentKind.cache]?.data ?? const {};
    return {for (final entry in cache.entries) if (entry.key != '_player') entry.key: entry.value};
  }

  Map<String, Object?> get persist => save.documents[SaveDocumentKind.persist]?.data ?? const {};

  /// Sections the save actually holds, with their number of entries (1 for
  /// a single object such as `_vip`).
  Map<SaveSection, int> get present => {
        for (final section in SaveSection.values)
          if (_count(player[section.field]) case final count? when count > 0) section: count,
      };

  static int? _count(Object? value) => switch (value) {
        List() => value.length,
        Map() => value.isEmpty ? null : (value.values.whereType<List>().firstOrNull?.length ?? 1),
        null => null,
        _ => 1,
      };

  List<Map<String, Object?>> rows(SaveSection section) {
    final value = player[section.field];
    if (value is List) return value.whereType<Map<String, Object?>>().toList();
    if (value is Map<String, Object?>) {
      final list = value.values.whereType<List>().firstOrNull;
      return list == null ? [value] : list.whereType<Map<String, Object?>>().toList();
    }
    return const [];
  }

  int? get exp => _int(player['_exp']);
  int? get vipRank => _int((player['_vip'] as Map<String, Object?>?)?['_rank']);
  int? get favoriteMemberCardId => _int(player['_favoriteMemberCardId'] ?? player['_lastLiveDeckLeaderMemberCardId']);

  /// Sum of the best high-score ratings the game counts.
  int get highScoreRating =>
      rows(SaveSection.ratings).fold(0, (sum, row) => sum + (_int(row['_highScoreRating']) ?? 0));

  /// Songs with a cleared chart on each difficulty (status above zero).
  Map<String, int> get clearsByDifficulty => {
        for (final difficulty in const ['easy', 'normal', 'hard', 'expert'])
          difficulty: rows(SaveSection.songs).where((row) => (_int(row['_${difficulty}ClearedStatus']) ?? 0) > 0).length,
      };

  /// An item's amount, e.g. a currency.
  int amountOf(int itemId) =>
      _int(rows(SaveSection.items).firstWhere((row) => _int(row['_masterItemId']) == itemId, orElse: () => const {})['_amount']) ?? 0;

  static int? _int(Object? value) => value is int ? value : value is String ? int.tryParse(value) : null;
}
