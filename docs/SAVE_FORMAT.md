# The Our Notes save

The game keeps a few small files per account in its data folder, under `files/<account hash>/` (Android `Android/data/<package>/files`, iOS the app's `Documents`). Each file is

    magic[32] ‖ iv[32] ‖ Rijndael-256-CBC(key, iv, PKCS#7(UTF-8 JSON))

with a 256-bit block (not AES). The magic and key are constants of the game, the same on every release and platform. File names are content hashes that change between versions, so a reader tries every small file and keeps the ones that decrypt.

Three documents come out:

| Document | Recognised by | Holds |
| --- | --- | --- |
| `LocalCacheData` | `_player` | the account's progress (below) and the game's settings |
| `LocalPersistData` | `_tutorialPhase`, `_latestLiveResult` | the latest live and its rewards, story resume points, last selections |
| `LocalPermanentData` | `_isTutorialCompleted` | device flags |

Field names are the game's own. The entry fields listed are those of the game's classes; the ones that point at master data (`_character`, `_band`, `_currentMemberCardLevel` and the like) are rebuilt when the game loads and may not appear in the file. Numbers that can exceed 2^53 (experience) should be read as 64-bit integers or decimal strings.

## `_player`

| Field | Contents | Fields of each entry |
| --- | --- | --- |
| `_profileId` | Player ID |  |
| `_name` | Display name (never exported) |  |
| `_exp` | Player experience |  |
| `_memberCards` | Member cards | `_masterId`, `_exp`, `_awakeCount`, `_rank`, `_liveSkillLevel`, `_performanceSkillLevel`, `_gainAtUtc`, `_character`, `_band`, `_liveSkill`, `_gekisouSkill`, `_currentMemberCardLevel`, `_bestMusicTags` |
| `_supportCards` | Snapshots | `_masterId`, `_exp`, `_rank`, `_gainAtUtc`, `_duplicateCount`, `_bandIds`, `_bands`, `_currentSupportCardLevel` |
| `_characters` | Character ranks | `_masterId`, `_exp`, `_isMaxRank` |
| `_characterFriendships` | Character friendships | `_pair`, `_exp`, `_characterA`, `_characterB`, `_isMaxRank` |
| `_characterFriendshipRankRewards` | Friendship rewards received | `_characterFriendshipId`, `_characterFriendshipRankRewardId` |
| `_bandItems` | Band items | `_masterId`, `_level` |
| `_items` | Items and currencies | `_masterItemId`, `_amount` |
| `_decks` | Teams | `_id`, `_name`, `_memberCardIDs`, `_supportCardIDs`, `_performanceOrderIndexes` |
| `_lastLiveDeck` | Last team used |  |
| `_favoriteMemberCardId` | Favourite member card |  |
| `_liveMusics` | Songs unlocked and favourites | `_masterId`, `_favorites`, `_unlockedStatus` |
| `_liveMusicResults` | Song results: high scores, clear status and combo rewards per difficulty | `_mLiveMusicId`, `_highScore`, `_highScoreOnEasy`, `_highScoreOnNormal`, `_highScoreOnHard`, `_highScoreOnExpert`, `_easyClearedStatus`, `_normalClearedStatus`, `_hardClearedStatus`, `_expertClearedStatus`, `_receivedScoreSsReward`, `_receivedScoreSReward`, `_receivedScoreAReward`, `_receivedScoreBReward`, `_receivedScoreCReward`, `_receivedEasyQuarterComboReward`, `_receivedEasyHalfComboReward`, `_receivedEasyThreeQuarterComboReward`, `_receivedEasyFullComboReward`, `_receivedNormalQuarterComboReward`, `_receivedNormalHalfComboReward`, `_receivedNormalThreeQuarterComboReward`, `_receivedNormalFullComboReward`, `_receivedHardQuarterComboReward`, `_receivedHardHalfComboReward`, `_receivedHardThreeQuarterComboReward`, `_receivedHardFullComboReward`, `_receivedExpertQuarterComboReward`, `_receivedExpertHalfComboReward`, `_receivedExpertThreeQuarterComboReward`, `_receivedExpertFullComboReward` |
| `_topHighScoreRatings` | Songs counted in the high score rating |  |
| `_challengeMusics` | Challenge songs | `_masterId`, `_myRank`, `_rankingItemDataList` |
| `_challengeMusicResults` | Challenge song results | `_mChallengeMusicId`, `_highScore`, `_highScoreOnEasy`, `_highScoreOnNormal`, `_highScoreOnHard`, `_highScoreOnExpert`, `_liveMusicId` |
| `_events` | Events: points and ranking | `_masterId`, `_eventPointCount`, `_rankingCount`, `_challengePointConsumptionType`, `_eventItem`, `_challengeLive`, `_rankingItemDataList`, `_unviewedAchievementRewards`, `_isRankingListLoaded` |
| `_challengeLives` | Challenge lives | `_eventId`, `_challengePointCount`, `_isChallengeMusicHighScoreRestored` |
| `_gachaRecords` | Gacha: points and pulls | `_id`, `_gachaPoint`, `_productRecords`, `_selectedPickUpItems` |
| `_storyEpisodeRecords` | Stories read | `_type`, `_id`, `_dateTime`, `_skipped` |
| `_normalMissions` | Missions |  |
| `_limitedMissions` | Limited missions | `_groupId`, `_startAtUnixTime` |
| `_characterMissions` | Character missions | `_characterId`, `_missions` |
| `_missionCounters` | Mission counters |  |
| `_playerSeasonPass` | Season pass | `_id`, `_point`, `_enablePremium`, `_levels`, `_missions`, `_pendingAutoGrantedPoint` |
| `_monthlyPass` | Monthly pass | `_monthlyPassId`, `_purchasedAt`, `_expireAt`, `_lastDailyRewardDayNumber`, `_groupPurchaseCount`, `_freeGachaUsedAt`, `_isExtensionPurchased` |
| `_receivedLoginBonuses` | Login bonuses | `_masterLoginBonusId`, `_receiveCount`, `_sheetNo`, `_slotNo` |
| `_vip` | T.G.W CARD | `_currentPoint`, `_currentConsecutiveCount`, `_canReceiveDailyReward`, `_lastLoginCount`, `_lastDailyRewardDayNumber`, `_canReceiveDailyPoint`, `_rank`, `_gainedRewardRank` |
| `_liveBoost` | Live boost | `_liveBoostCount`, `_lastRecoveredAt`, `_liveBoostConsumeCount`, `_useConsumeAll`, `_consumeAllCounter`, `_dailyAdViewCount`, `_trustedUtcNow`, `_baseRecoveryIntervalSeconds`, `_maxConsumeAllUsageCount`, `_snapshotConsumeLiveBoostCount`, `_recoverySpeedBonus`, `_limitBonus`, `_consumeAllBonus`, `_selectableConsumeCounts` |
| `_liveSkip` | Live skip | `_lastUpdateAt`, `_dailyCounter`, `_maxSkipUsageCount`, `_skipCountBonus` |
| `_offlineBonus` | Offline bonus | `_status`, `_units`, `_efficiencyTimeBonus` |
| `_memory` | Memories | `_musicGroups`, `_members`, `_supports`, `_currentMemberLevel`, `_nextMemberLevel`, `_currentSupportLevel`, `_nextSupportLevel` |
| `_unlockedCostumes` | Costumes owned | `_costumeGroupId`, `_acquiredAtUtc` |
| `_currentCostumes` | Costumes worn | `_characterId`, `_costumeGroupId` |
| `_backgrounds` | Backgrounds | `_masterBackgroundId`, `_acquiredAtUtc` |
| `_stamps` | Stamps | `_masterStampId`, `_acquiredAtUtc` |
| `_stampFavorites` | Favourite stamps | `_favoriteId`, `_name`, `_favoriteStampIds`, `_isSyncing`, `_needsResync` |
| `_degrees` | Titles | `_masterDegreeId`, `_count`, `_acquiredAtUtc` |
| `_playerProfileCards` | Profile cards | `_slot`, `_name`, `_profileObjectsByIndex`, `_isSetting` |
| `_liveLaneSkins` | Lane skins | `_masterId`, `_unlocked` |
| `_liveNoteSkins` | Note skins | `_masterId`, `_unlocked` |
| `_liveNoteEffectSkins` | Note effects | `_masterId`, `_unlocked` |
| `_liveNoteSeGroups` | Note sounds | `_masterId`, `_unlocked` |
| `_spots` | Spots visited | `_spotId`, `_viewed` |
| `_shop` | Shop counters | `_freePriceProductCounters`, `_newBadgeIds`, `_triggerReleases` |
| `_exchange` | Exchange | `_products`, `_canGetResource`, `_getResourceAmount` |
| `_arenaLeagues` | Arena |  |
| `_dreamPoint` | Dream points |  |
| `_chatSettings` | Chat themes and frames | `_unlockedThemeIds`, `_unlockedFrameIds`, `_unlockedBubbleIds`, `_selectedThemeId`, `_selectedFrameId`, `_selectedBubbleId`, `_specialFocusAccountIds`, `_unlockedThemeIdSet`, `_unlockedFrameIdSet`, `_unlockedBubbleIdSet`, `_specialFocusAccountIdSet` |
| `_optionDataBytes` | In-game options |  |

## Settings (`LocalCacheData` beside `_player`)

`_readAnnouncementIdList`, `_isAutoAdv`, `_isAutoEnabledByPlayer`, `_isRandomChoice`, `_isAdvFullScreen`, `_isAdvMenuOpen`, `_isAdvContinuousPlayback`, `_isAdvSubtitlesEnabled`, `_advPlaybackSpeed`, `_selectedMasterAdvId`, `_nextSceneNameAfterAdv`, `_characterCostumeNewFlag`, `_characterVoiceNewFlag`, `_liveBgmSoundVolume`, `_liveSeSoundVolume`, `_liveVoiceSoundVolume`, `_liveNotesSeSoundVolume`, `_bluetoothLiveBgmSoundVolume`, `_bluetoothLiveSeSoundVolume`, `_bluetoothLiveVoiceSoundVolume`, `_bluetoothLiveNotesSeSoundVolume`, `_exchangeProductNoResetNewFlag`, `_exchangeProductDailyNewFlag`, `_exchangeProductWeeklyNewFlag`, `_exchangeProductMonthlyNewFlag`, `_lastSelectedFormationId`, `_lastSelectedArenaFormationId`, `_listViewFormationIndexes`, `_friendInvitationNewFlag`, `_transitionHomeDisplay`, `_isAutoLive`, `_autoJudgement`, `_isAutoOverrideJudgementDiffTimeMs`, `_autoOverrideJudgementDiffTimeMs`, `_isOverrideJustNoteSeGroupId`, `_justNoteSeGroupId`, `_flickDistance`, `_overrideJudgementTiming`, `_judgementTimingUnits`, `_judgementAreaOffsets`, `_playLiveMode`, `_isTutorial`, `_showBattleLiveInMovie`, `_playSoloLiveMode`, `_enabledHapticFeedback`, `_npcSettings`, `_groovePercent`, `_isShowTapPointMarker`, `_isShowNoteTimeText`, `_isShowComboNote`, `_detailInputLog`, `_useiOSPromotionInputOffset`, `_iOSPromotionInputOffsetMs`, `_isLightweightMode`, `_isSoloGekisouLive`, `_currentAssistLevel`, `_currentAssistPoint`, `_isShowEaseNote`, `_isFixAssistLevel`, `_fixedAssistLevel`, `_overrideLiveQuality`, `_liveBackgroundResolutionScale`, `_live2DFPS`, `_backgroundCameraFPS`, `_comboCameraFPS`, `_effectRenderingScale`, `_comboCameraRenderingScale`, `_isEnableTimingDebug`, `_timingDebugJusgement`, `_isEnableOffsetDebug`, `_isAlwaysShowFastSlow`, `_forceEnableJustJudgement`, `_isPlayMusicVideoInMonitor`, `_isFixedRandomSeed`, `_randomSeed`, `_isFixedSendScore`, `_fixedSendSoloScore`, `_fixedSendBattleScore`, `_isOverrideBloom`, `_bloomActive`, `_bloomThreshold`, `_bloomIntensity`, `_bloomScatter`, `_bloomClamp`, `_bloomHighQualityFiltering`, `_bloomDownscale`, `_bloomMaxIterations`, `_isOverrideEffectBloom`, `_effectBloomActive`, `_effectBloomThreshold`, `_effectBloomIntensity`, `_effectBloomScatter`, `_effectBloomClamp`, `_effectBloomHighQualityFiltering`, `_effectBloomDownscale`, `_effectBloomMaxIterations`, `_tutorialLivePhase`, `_tutorialNoteTimingItemType`, `_isTutorialLiveReview`, `_isBeginnerGuideReopenReserved`, `_selectedMusicCategory`, `_selectedBandFilterIndex`, `_selectedLiveMusicSelectSortOrder`, `_selectedLiveMusicSelectSortType`, `_filterFavoriteMusic`, `_filterMinScoreLevel`, `_filterMaxScoreLevel`, `_filterMusicPlayStatus`, `_filterAllMusicTag`, `_filterMusicTagIds`, `_filterLiveEffect`, `_sortFilterSettings`, `_pendingGachaAnimationInput`, `_pendingGachaResultDisplay`, `_favoriteLiveMusicIdsOnGroup1`, `_favoriteLiveMusicIdsOnGroup2`, `_favoriteLiveMusicIdsOnGroup3`

## `LocalPersistData`

`_advResumePoints`, `_announcementLandingShownAt`, `_seenAnnouncementHash`, `_arenaUnlockedDialogShownAtTicks`, `_certification`, `_exchangeEndNoticeFlags`, `_friendNewFlag`, `_gachaScreenVisitedAtUtcTicks`, `_gachaTicketEndNoticeNextTimeUtcTicks`, `_liveMusicListType`, `_selectedLiveMusicID`, `_liveDifficulty`, `_freeLiveSelectedLiveMusicID`, `_freeLiveDifficulty`, `_battleLiveSelectedLiveMusicID`, `_battleLiveDifficulty`, `_rankMatchLiveSelectedLiveMusicID`, `_rankMatchLiveDifficulty`, `_rankMatchLiveUseSupportItemIds`, `_arenaLiveLastSeasonId`, `_arenaLiveLastLeagueId`, `_arenaLiveStartPlayerCount`, `_arenaLivePlaying`, `_challengeLiveSelectedLiveMusicID`, `_challengeLiveDifficulty`, `_playedLiveMusicReleaseEffectIds`, `_playedLiveMusicIds`, `_latestLiveMode`, `_latestSoloLiveMode`, `_latestLiveScore`, `_latestLiveResult`, `_liveRewardResult`, `_tempRewardIds`, `_latestLiveResultPlayers`, `_latestLiveScreenMode`, `_latestArenaLiveResult`, `_liveResultAttemptCount`, `_pendingMonthlyPassDailyRewards`, `_hasPendingMonthlyPassDailyRewardOverflow`, `_monthlyPassEndNoticeFlags`, `_optionDataBytes`, `_playedPromoVideoLandingIds`, `_shownPromoImageLandingIds`, `_viewedRecommendContentIds`, `_playedResultSimpleAdvIds`, `_purchaseAlertConfirmedMonth`, `_grantedIapTransactions`, `_shownLandingShopIds`, `_shownAppealShopIds`, `_pendingStoryEpisodeCompletions`, `_playedStoryLoginLandingIds`, `_agreementTermsVersion`, `_tutorialPhase`

## What Haneoka exports

`haneoka-game-save-v1` keeps all of the above except fields that identify the person or let someone act as them: the display name, account and profile identifiers of friends, passwords, invitation codes, linked accounts, purchase receipts and chat state. The full list is `identityFields` in `lib/save/export.dart`.
