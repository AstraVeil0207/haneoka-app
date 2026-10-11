// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Haneoka';

  @override
  String get importTitle => 'セーブを読み込む';

  @override
  String get sourceShizuku => 'この端末 · Shizuku';

  @override
  String get sourceGrantFolder => 'この端末 · ゲームフォルダ';

  @override
  String get sourceFiles => 'ファイルまたはフォルダ';

  @override
  String get sourceAdb => 'Android 端末 · USB または Wi-Fi';

  @override
  String get sourceIosBackup => 'iPhone / iPad のバックアップ';

  @override
  String get releaseIntlOfficial => 'グローバル · 公式';

  @override
  String get releaseIntlStore => 'グローバル · Google Play';

  @override
  String get releaseJp => '日本';

  @override
  String get release => 'リリース';

  @override
  String get shizukuNotRunning => 'Shizuku が起動していません';

  @override
  String get shizukuUnsupported => 'Shizuku の更新が必要です';

  @override
  String get openShizuku => 'Shizuku を開く';

  @override
  String get read => '読み込む';

  @override
  String get reading => '読み込み中';

  @override
  String get noSaves => 'セーブが見つかりません';

  @override
  String get noGameInBackup => 'このバックアップにアワーノーツのデータはありません';

  @override
  String get backupPassword => 'バックアップのパスワード';

  @override
  String get wrongPassword => 'バックアップのパスワードが違います';

  @override
  String get noBackups => 'バックアップがありません';

  @override
  String get chooseBackupFolder => 'バックアップフォルダを選ぶ';

  @override
  String get encrypted => '暗号化';

  @override
  String get devices => '端末';

  @override
  String get noDevices => '端末が接続されていません';

  @override
  String get deviceUnauthorized => '端末で USB デバッグを許可してください';

  @override
  String get adbMissing => 'adb が見つかりません';

  @override
  String get chooseAdb => 'adb を選ぶ';

  @override
  String get getPlatformTools => 'Platform Tools を入手';

  @override
  String get pairWireless => 'Wi-Fi でペア設定';

  @override
  String get pairAddress => 'IP アドレスとポート';

  @override
  String get pairCode => 'ペア設定コード';

  @override
  String get connectAddress => '接続アドレス';

  @override
  String get pairFailed => 'ペア設定に失敗しました';

  @override
  String get refresh => '更新';

  @override
  String get gameNotInstalled => 'アワーノーツがインストールされていません';

  @override
  String get accounts => 'アカウント';

  @override
  String get playerId => 'プレイヤー ID';

  @override
  String get savedAt => '保存日時';

  @override
  String get source => '読み込み元';

  @override
  String get playerExp => 'プレイヤー経験値';

  @override
  String get vipRank => 'T.G.W CARD';

  @override
  String get highScoreRating => 'ハイスコアレーティング';

  @override
  String get clears => 'クリア楽曲';

  @override
  String get exportTeam => '編成ツール用にコピー';

  @override
  String get exportSave => 'ファイルに保存';

  @override
  String get copied => 'コピーしました';

  @override
  String get saved => '保存しました';

  @override
  String get settings => 'ゲーム設定';

  @override
  String get latestLive => '最新のライブ';

  @override
  String get allFields => 'すべての項目';

  @override
  String entries(int count) {
    return '$count 件';
  }

  @override
  String get sec_memberCards => 'メンバー';

  @override
  String get sec_snapshots => 'スナップ';

  @override
  String get sec_characters => 'キャラクターランク';

  @override
  String get sec_friendships => '親密度';

  @override
  String get sec_bandItems => 'バンドアイテム';

  @override
  String get sec_items => 'アイテム';

  @override
  String get sec_songs => '楽曲記録';

  @override
  String get sec_ratings => 'レーティング対象曲';

  @override
  String get sec_challengeSongs => 'チャレンジ楽曲';

  @override
  String get sec_events => 'イベント';

  @override
  String get sec_challengeLives => 'チャレンジライブ';

  @override
  String get sec_gacha => 'ガチャ';

  @override
  String get sec_stories => '既読ストーリー';

  @override
  String get sec_decks => '編成';

  @override
  String get sec_missions => 'ミッション';

  @override
  String get sec_limitedMissions => '期間限定ミッション';

  @override
  String get sec_characterMissions => 'キャラクターミッション';

  @override
  String get sec_seasonPass => 'シーズンパス';

  @override
  String get sec_monthlyPass => 'マンスリーパス';

  @override
  String get sec_loginBonuses => 'ログインボーナス';

  @override
  String get sec_costumes => '衣装';

  @override
  String get sec_currentCostumes => '着用中の衣装';

  @override
  String get sec_backgrounds => '背景';

  @override
  String get sec_stamps => 'スタンプ';

  @override
  String get sec_degrees => '称号';

  @override
  String get sec_profileCards => 'プロフィールカード';

  @override
  String get sec_laneSkins => 'レーンスキン';

  @override
  String get sec_noteSkins => 'ノーツスキン';

  @override
  String get sec_noteEffectSkins => 'ノーツエフェクト';

  @override
  String get sec_noteSounds => 'ノーツ SE';

  @override
  String get sec_spots => 'スポット';

  @override
  String get sec_memory => 'メモリー';

  @override
  String get sec_liveBoost => 'ライブブースト';

  @override
  String get sec_liveSkip => 'ライブスキップ';

  @override
  String get sec_vip => 'T.G.W CARD';

  @override
  String get sec_offlineBonus => 'オフラインボーナス';

  @override
  String get sec_arena => 'アリーナ';

  @override
  String get playerRank => 'プレイヤーランク';

  @override
  String get sec_songUnlocks => '楽曲解放';

  @override
  String get sec_challengeUnlocks => 'チャレンジ楽曲解放';

  @override
  String get sec_friendshipRewards => '絆報酬';

  @override
  String get sec_stampFavorites => 'お気に入りスタンプ';

  @override
  String get sec_exchange => '交換所';

  @override
  String get sec_shop => 'ショップ';
}
