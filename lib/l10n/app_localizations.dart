import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Haneoka'**
  String get appTitle;

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Import save'**
  String get importTitle;

  /// No description provided for @sourceShizuku.
  ///
  /// In en, this message translates to:
  /// **'This phone · Shizuku'**
  String get sourceShizuku;

  /// No description provided for @sourceGrantFolder.
  ///
  /// In en, this message translates to:
  /// **'This phone · game folder'**
  String get sourceGrantFolder;

  /// No description provided for @sourceFiles.
  ///
  /// In en, this message translates to:
  /// **'Files or folder'**
  String get sourceFiles;

  /// No description provided for @sourceAdb.
  ///
  /// In en, this message translates to:
  /// **'Android phone · USB or Wi-Fi'**
  String get sourceAdb;

  /// No description provided for @sourceIosBackup.
  ///
  /// In en, this message translates to:
  /// **'iPhone or iPad backup'**
  String get sourceIosBackup;

  /// No description provided for @releaseIntlOfficial.
  ///
  /// In en, this message translates to:
  /// **'Global · official'**
  String get releaseIntlOfficial;

  /// No description provided for @releaseIntlStore.
  ///
  /// In en, this message translates to:
  /// **'Global · Google Play'**
  String get releaseIntlStore;

  /// No description provided for @releaseJp.
  ///
  /// In en, this message translates to:
  /// **'Japan'**
  String get releaseJp;

  /// No description provided for @release.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get release;

  /// No description provided for @shizukuNotRunning.
  ///
  /// In en, this message translates to:
  /// **'Shizuku is not running'**
  String get shizukuNotRunning;

  /// No description provided for @shizukuUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Shizuku needs updating'**
  String get shizukuUnsupported;

  /// No description provided for @openShizuku.
  ///
  /// In en, this message translates to:
  /// **'Open Shizuku'**
  String get openShizuku;

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @reading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get reading;

  /// No description provided for @noSaves.
  ///
  /// In en, this message translates to:
  /// **'No save found'**
  String get noSaves;

  /// No description provided for @noGameInBackup.
  ///
  /// In en, this message translates to:
  /// **'This backup has no Our Notes data'**
  String get noGameInBackup;

  /// No description provided for @backupPassword.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get backupPassword;

  /// No description provided for @wrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong backup password'**
  String get wrongPassword;

  /// No description provided for @noBackups.
  ///
  /// In en, this message translates to:
  /// **'No backups'**
  String get noBackups;

  /// No description provided for @chooseBackupFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose backup folder'**
  String get chooseBackupFolder;

  /// No description provided for @encrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypted'**
  String get encrypted;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @noDevices.
  ///
  /// In en, this message translates to:
  /// **'No phone connected'**
  String get noDevices;

  /// No description provided for @deviceUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Allow USB debugging on the phone'**
  String get deviceUnauthorized;

  /// No description provided for @adbMissing.
  ///
  /// In en, this message translates to:
  /// **'adb not found'**
  String get adbMissing;

  /// No description provided for @chooseAdb.
  ///
  /// In en, this message translates to:
  /// **'Choose adb'**
  String get chooseAdb;

  /// No description provided for @getPlatformTools.
  ///
  /// In en, this message translates to:
  /// **'Get platform tools'**
  String get getPlatformTools;

  /// No description provided for @pairWireless.
  ///
  /// In en, this message translates to:
  /// **'Pair over Wi-Fi'**
  String get pairWireless;

  /// No description provided for @pairAddress.
  ///
  /// In en, this message translates to:
  /// **'IP address and port'**
  String get pairAddress;

  /// No description provided for @pairCode.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get pairCode;

  /// No description provided for @connectAddress.
  ///
  /// In en, this message translates to:
  /// **'Connect address'**
  String get connectAddress;

  /// No description provided for @pairFailed.
  ///
  /// In en, this message translates to:
  /// **'Pairing failed'**
  String get pairFailed;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @gameNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Our Notes is not installed'**
  String get gameNotInstalled;

  /// No description provided for @accounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accounts;

  /// No description provided for @playerId.
  ///
  /// In en, this message translates to:
  /// **'Player ID'**
  String get playerId;

  /// No description provided for @savedAt.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedAt;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @playerExp.
  ///
  /// In en, this message translates to:
  /// **'Player EXP'**
  String get playerExp;

  /// No description provided for @vipRank.
  ///
  /// In en, this message translates to:
  /// **'T.G.W CARD'**
  String get vipRank;

  /// No description provided for @highScoreRating.
  ///
  /// In en, this message translates to:
  /// **'High score rating'**
  String get highScoreRating;

  /// No description provided for @clears.
  ///
  /// In en, this message translates to:
  /// **'Cleared songs'**
  String get clears;

  /// No description provided for @exportTeam.
  ///
  /// In en, this message translates to:
  /// **'Copy for team builder'**
  String get exportTeam;

  /// No description provided for @exportSave.
  ///
  /// In en, this message translates to:
  /// **'Save as file'**
  String get exportSave;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Game settings'**
  String get settings;

  /// No description provided for @latestLive.
  ///
  /// In en, this message translates to:
  /// **'Latest live'**
  String get latestLive;

  /// No description provided for @allFields.
  ///
  /// In en, this message translates to:
  /// **'All fields'**
  String get allFields;

  /// No description provided for @entries.
  ///
  /// In en, this message translates to:
  /// **'{count} entries'**
  String entries(int count);

  /// No description provided for @sec_memberCards.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get sec_memberCards;

  /// No description provided for @sec_snapshots.
  ///
  /// In en, this message translates to:
  /// **'Snapshots'**
  String get sec_snapshots;

  /// No description provided for @sec_characters.
  ///
  /// In en, this message translates to:
  /// **'Character ranks'**
  String get sec_characters;

  /// No description provided for @sec_friendships.
  ///
  /// In en, this message translates to:
  /// **'Friendships'**
  String get sec_friendships;

  /// No description provided for @sec_bandItems.
  ///
  /// In en, this message translates to:
  /// **'Band items'**
  String get sec_bandItems;

  /// No description provided for @sec_items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get sec_items;

  /// No description provided for @sec_songs.
  ///
  /// In en, this message translates to:
  /// **'Song results'**
  String get sec_songs;

  /// No description provided for @sec_ratings.
  ///
  /// In en, this message translates to:
  /// **'Rating songs'**
  String get sec_ratings;

  /// No description provided for @sec_challengeSongs.
  ///
  /// In en, this message translates to:
  /// **'Challenge songs'**
  String get sec_challengeSongs;

  /// No description provided for @sec_events.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get sec_events;

  /// No description provided for @sec_challengeLives.
  ///
  /// In en, this message translates to:
  /// **'Challenge lives'**
  String get sec_challengeLives;

  /// No description provided for @sec_gacha.
  ///
  /// In en, this message translates to:
  /// **'Gacha'**
  String get sec_gacha;

  /// No description provided for @sec_stories.
  ///
  /// In en, this message translates to:
  /// **'Stories read'**
  String get sec_stories;

  /// No description provided for @sec_decks.
  ///
  /// In en, this message translates to:
  /// **'Teams'**
  String get sec_decks;

  /// No description provided for @sec_missions.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get sec_missions;

  /// No description provided for @sec_limitedMissions.
  ///
  /// In en, this message translates to:
  /// **'Limited missions'**
  String get sec_limitedMissions;

  /// No description provided for @sec_characterMissions.
  ///
  /// In en, this message translates to:
  /// **'Character missions'**
  String get sec_characterMissions;

  /// No description provided for @sec_seasonPass.
  ///
  /// In en, this message translates to:
  /// **'Season pass'**
  String get sec_seasonPass;

  /// No description provided for @sec_monthlyPass.
  ///
  /// In en, this message translates to:
  /// **'Monthly pass'**
  String get sec_monthlyPass;

  /// No description provided for @sec_loginBonuses.
  ///
  /// In en, this message translates to:
  /// **'Login bonuses'**
  String get sec_loginBonuses;

  /// No description provided for @sec_costumes.
  ///
  /// In en, this message translates to:
  /// **'Costumes'**
  String get sec_costumes;

  /// No description provided for @sec_currentCostumes.
  ///
  /// In en, this message translates to:
  /// **'Worn costumes'**
  String get sec_currentCostumes;

  /// No description provided for @sec_backgrounds.
  ///
  /// In en, this message translates to:
  /// **'Backgrounds'**
  String get sec_backgrounds;

  /// No description provided for @sec_stamps.
  ///
  /// In en, this message translates to:
  /// **'Stamps'**
  String get sec_stamps;

  /// No description provided for @sec_degrees.
  ///
  /// In en, this message translates to:
  /// **'Titles'**
  String get sec_degrees;

  /// No description provided for @sec_profileCards.
  ///
  /// In en, this message translates to:
  /// **'Profile cards'**
  String get sec_profileCards;

  /// No description provided for @sec_laneSkins.
  ///
  /// In en, this message translates to:
  /// **'Lane skins'**
  String get sec_laneSkins;

  /// No description provided for @sec_noteSkins.
  ///
  /// In en, this message translates to:
  /// **'Note skins'**
  String get sec_noteSkins;

  /// No description provided for @sec_noteEffectSkins.
  ///
  /// In en, this message translates to:
  /// **'Note effects'**
  String get sec_noteEffectSkins;

  /// No description provided for @sec_noteSounds.
  ///
  /// In en, this message translates to:
  /// **'Note sounds'**
  String get sec_noteSounds;

  /// No description provided for @sec_spots.
  ///
  /// In en, this message translates to:
  /// **'Spots'**
  String get sec_spots;

  /// No description provided for @sec_memory.
  ///
  /// In en, this message translates to:
  /// **'Memories'**
  String get sec_memory;

  /// No description provided for @sec_liveBoost.
  ///
  /// In en, this message translates to:
  /// **'Live boost'**
  String get sec_liveBoost;

  /// No description provided for @sec_liveSkip.
  ///
  /// In en, this message translates to:
  /// **'Live skip'**
  String get sec_liveSkip;

  /// No description provided for @sec_vip.
  ///
  /// In en, this message translates to:
  /// **'T.G.W CARD'**
  String get sec_vip;

  /// No description provided for @sec_offlineBonus.
  ///
  /// In en, this message translates to:
  /// **'Offline bonus'**
  String get sec_offlineBonus;

  /// No description provided for @sec_arena.
  ///
  /// In en, this message translates to:
  /// **'Arena'**
  String get sec_arena;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
