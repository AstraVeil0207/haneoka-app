import '../l10n/app_localizations.dart';
import '../save/game_save.dart';
import '../save/save_view.dart';

extension ReleaseLabel on GameRelease {
  String label(AppLocalizations t) => switch (this) {
    GameRelease.intlOfficial => t.releaseIntlOfficial,
    GameRelease.intlStore => t.releaseIntlStore,
    GameRelease.jp => t.releaseJp,
  };
}

extension SectionLabel on SaveSection {
  String label(AppLocalizations t) => switch (this) {
    SaveSection.memberCards => t.sec_memberCards,
    SaveSection.snapshots => t.sec_snapshots,
    SaveSection.characters => t.sec_characters,
    SaveSection.friendships => t.sec_friendships,
    SaveSection.bandItems => t.sec_bandItems,
    SaveSection.items => t.sec_items,
    SaveSection.songs => t.sec_songs,
    SaveSection.ratings => t.sec_ratings,
    SaveSection.challengeSongs => t.sec_challengeSongs,
    SaveSection.events => t.sec_events,
    SaveSection.challengeLives => t.sec_challengeLives,
    SaveSection.gacha => t.sec_gacha,
    SaveSection.stories => t.sec_stories,
    SaveSection.decks => t.sec_decks,
    SaveSection.missions => t.sec_missions,
    SaveSection.limitedMissions => t.sec_limitedMissions,
    SaveSection.characterMissions => t.sec_characterMissions,
    SaveSection.seasonPass => t.sec_seasonPass,
    SaveSection.monthlyPass => t.sec_monthlyPass,
    SaveSection.loginBonuses => t.sec_loginBonuses,
    SaveSection.costumes => t.sec_costumes,
    SaveSection.currentCostumes => t.sec_currentCostumes,
    SaveSection.backgrounds => t.sec_backgrounds,
    SaveSection.stamps => t.sec_stamps,
    SaveSection.degrees => t.sec_degrees,
    SaveSection.profileCards => t.sec_profileCards,
    SaveSection.laneSkins => t.sec_laneSkins,
    SaveSection.noteSkins => t.sec_noteSkins,
    SaveSection.noteEffectSkins => t.sec_noteEffectSkins,
    SaveSection.noteSounds => t.sec_noteSounds,
    SaveSection.spots => t.sec_spots,
    SaveSection.memory => t.sec_memory,
    SaveSection.liveBoost => t.sec_liveBoost,
    SaveSection.liveSkip => t.sec_liveSkip,
    SaveSection.vip => t.sec_vip,
    SaveSection.offlineBonus => t.sec_offlineBonus,
    SaveSection.arena => t.sec_arena,
    SaveSection.songUnlocks => t.sec_songUnlocks,
    SaveSection.challengeUnlocks => t.sec_challengeUnlocks,
    SaveSection.friendshipRewards => t.sec_friendshipRewards,
    SaveSection.stampFavorites => t.sec_stampFavorites,
    SaveSection.exchange => t.sec_exchange,
    SaveSection.shop => t.sec_shop,
  };
}
