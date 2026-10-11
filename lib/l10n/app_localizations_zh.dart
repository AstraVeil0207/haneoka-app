// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Haneoka';

  @override
  String get importTitle => '导入存档';

  @override
  String get sourceShizuku => '本机 · Shizuku';

  @override
  String get sourceGrantFolder => '本机 · 游戏文件夹';

  @override
  String get sourceFiles => '文件或文件夹';

  @override
  String get sourceAdb => '安卓手机 · USB 或无线';

  @override
  String get sourceIosBackup => 'iPhone 或 iPad 备份';

  @override
  String get releaseIntlOfficial => '国际服 · 官网';

  @override
  String get releaseIntlStore => '国际服 · Google Play';

  @override
  String get releaseJp => '日服';

  @override
  String get release => '版本';

  @override
  String get shizukuNotRunning => 'Shizuku 未运行';

  @override
  String get shizukuUnsupported => '需要更新 Shizuku';

  @override
  String get openShizuku => '打开 Shizuku';

  @override
  String get read => '读取';

  @override
  String get reading => '正在读取';

  @override
  String get noSaves => '没有找到存档';

  @override
  String get noGameInBackup => '这个备份里没有 Our Notes 的数据';

  @override
  String get backupPassword => '备份密码';

  @override
  String get wrongPassword => '备份密码不正确';

  @override
  String get noBackups => '没有备份';

  @override
  String get chooseBackupFolder => '选择备份文件夹';

  @override
  String get encrypted => '已加密';

  @override
  String get devices => '设备';

  @override
  String get noDevices => '没有连接手机';

  @override
  String get deviceUnauthorized => '在手机上允许 USB 调试';

  @override
  String get adbMissing => '找不到 adb';

  @override
  String get chooseAdb => '选择 adb';

  @override
  String get getPlatformTools => '获取 Platform Tools';

  @override
  String get pairWireless => '无线配对';

  @override
  String get pairAddress => 'IP 地址和端口';

  @override
  String get pairCode => '配对码';

  @override
  String get connectAddress => '连接地址';

  @override
  String get pairFailed => '配对失败';

  @override
  String get refresh => '刷新';

  @override
  String get gameNotInstalled => '没有安装 Our Notes';

  @override
  String get accounts => '账号';

  @override
  String get playerId => '玩家 ID';

  @override
  String get savedAt => '保存时间';

  @override
  String get source => '来源';

  @override
  String get playerExp => '玩家经验';

  @override
  String get vipRank => 'T.G.W CARD';

  @override
  String get highScoreRating => '高分评级';

  @override
  String get clears => '通关歌曲';

  @override
  String get exportTeam => '复制到配队工具';

  @override
  String get exportSave => '保存为文件';

  @override
  String get copied => '已复制';

  @override
  String get saved => '已保存';

  @override
  String get settings => '游戏设置';

  @override
  String get latestLive => '最近一次演出';

  @override
  String get allFields => '全部字段';

  @override
  String entries(int count) {
    return '$count 条';
  }

  @override
  String get sec_memberCards => '成员';

  @override
  String get sec_snapshots => '留影';

  @override
  String get sec_characters => '角色等级';

  @override
  String get sec_friendships => '羁绊';

  @override
  String get sec_bandItems => '乐队道具';

  @override
  String get sec_items => '道具';

  @override
  String get sec_songs => '歌曲成绩';

  @override
  String get sec_ratings => '评级歌曲';

  @override
  String get sec_challengeSongs => '挑战歌曲';

  @override
  String get sec_events => '活动';

  @override
  String get sec_challengeLives => '挑战演出';

  @override
  String get sec_gacha => '招募';

  @override
  String get sec_stories => '已读故事';

  @override
  String get sec_decks => '编队';

  @override
  String get sec_missions => '任务';

  @override
  String get sec_limitedMissions => '限时任务';

  @override
  String get sec_characterMissions => '角色任务';

  @override
  String get sec_seasonPass => '季票';

  @override
  String get sec_monthlyPass => '月卡';

  @override
  String get sec_loginBonuses => '登录奖励';

  @override
  String get sec_costumes => '服装';

  @override
  String get sec_currentCostumes => '当前服装';

  @override
  String get sec_backgrounds => '背景';

  @override
  String get sec_stamps => '贴纸';

  @override
  String get sec_degrees => '称号';

  @override
  String get sec_profileCards => '名片';

  @override
  String get sec_laneSkins => '轨道皮肤';

  @override
  String get sec_noteSkins => '音符皮肤';

  @override
  String get sec_noteEffectSkins => '音符特效';

  @override
  String get sec_noteSounds => '打击音效';

  @override
  String get sec_spots => '地点';

  @override
  String get sec_memory => '回忆';

  @override
  String get sec_liveBoost => '演出加成';

  @override
  String get sec_liveSkip => '演出跳过';

  @override
  String get sec_vip => 'T.G.W CARD';

  @override
  String get sec_offlineBonus => '离线奖励';

  @override
  String get sec_arena => '竞技场';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appTitle => 'Haneoka';

  @override
  String get importTitle => '匯入存檔';

  @override
  String get sourceShizuku => '本機 · Shizuku';

  @override
  String get sourceGrantFolder => '本機 · 遊戲資料夾';

  @override
  String get sourceFiles => '檔案或資料夾';

  @override
  String get sourceAdb => 'Android 手機 · USB 或無線';

  @override
  String get sourceIosBackup => 'iPhone 或 iPad 備份';

  @override
  String get releaseIntlOfficial => '國際服 · 官網';

  @override
  String get releaseIntlStore => '國際服 · Google Play';

  @override
  String get releaseJp => '日服';

  @override
  String get release => '版本';

  @override
  String get shizukuNotRunning => 'Shizuku 未執行';

  @override
  String get shizukuUnsupported => '需要更新 Shizuku';

  @override
  String get openShizuku => '開啟 Shizuku';

  @override
  String get read => '讀取';

  @override
  String get reading => '正在讀取';

  @override
  String get noSaves => '沒有找到存檔';

  @override
  String get noGameInBackup => '這個備份裡沒有 Our Notes 的資料';

  @override
  String get backupPassword => '備份密碼';

  @override
  String get wrongPassword => '備份密碼不正確';

  @override
  String get noBackups => '沒有備份';

  @override
  String get chooseBackupFolder => '選擇備份資料夾';

  @override
  String get encrypted => '已加密';

  @override
  String get devices => '裝置';

  @override
  String get noDevices => '沒有連接手機';

  @override
  String get deviceUnauthorized => '在手機上允許 USB 偵錯';

  @override
  String get adbMissing => '找不到 adb';

  @override
  String get chooseAdb => '選擇 adb';

  @override
  String get getPlatformTools => '取得 Platform Tools';

  @override
  String get pairWireless => '無線配對';

  @override
  String get pairAddress => 'IP 位址和連接埠';

  @override
  String get pairCode => '配對碼';

  @override
  String get connectAddress => '連線位址';

  @override
  String get pairFailed => '配對失敗';

  @override
  String get refresh => '重新整理';

  @override
  String get gameNotInstalled => '沒有安裝 Our Notes';

  @override
  String get accounts => '帳號';

  @override
  String get playerId => '玩家 ID';

  @override
  String get savedAt => '儲存時間';

  @override
  String get source => '來源';

  @override
  String get playerExp => '玩家經驗';

  @override
  String get vipRank => 'T.G.W CARD';

  @override
  String get highScoreRating => '高分評級';

  @override
  String get clears => '通關歌曲';

  @override
  String get exportTeam => '複製到配隊工具';

  @override
  String get exportSave => '儲存為檔案';

  @override
  String get copied => '已複製';

  @override
  String get saved => '已儲存';

  @override
  String get settings => '遊戲設定';

  @override
  String get latestLive => '最近一次演出';

  @override
  String get allFields => '全部欄位';

  @override
  String entries(int count) {
    return '$count 筆';
  }

  @override
  String get sec_memberCards => '成員';

  @override
  String get sec_snapshots => '留影';

  @override
  String get sec_characters => '角色等級';

  @override
  String get sec_friendships => '羈絆';

  @override
  String get sec_bandItems => '樂團道具';

  @override
  String get sec_items => '道具';

  @override
  String get sec_songs => '歌曲成績';

  @override
  String get sec_ratings => '評級歌曲';

  @override
  String get sec_challengeSongs => '挑戰歌曲';

  @override
  String get sec_events => '活動';

  @override
  String get sec_challengeLives => '挑戰演出';

  @override
  String get sec_gacha => '招募';

  @override
  String get sec_stories => '已讀故事';

  @override
  String get sec_decks => '編隊';

  @override
  String get sec_missions => '任務';

  @override
  String get sec_limitedMissions => '限時任務';

  @override
  String get sec_characterMissions => '角色任務';

  @override
  String get sec_seasonPass => '季票';

  @override
  String get sec_monthlyPass => '月卡';

  @override
  String get sec_loginBonuses => '登入獎勵';

  @override
  String get sec_costumes => '服裝';

  @override
  String get sec_currentCostumes => '目前服裝';

  @override
  String get sec_backgrounds => '背景';

  @override
  String get sec_stamps => '貼圖';

  @override
  String get sec_degrees => '稱號';

  @override
  String get sec_profileCards => '名片';

  @override
  String get sec_laneSkins => '軌道外觀';

  @override
  String get sec_noteSkins => '音符外觀';

  @override
  String get sec_noteEffectSkins => '音符特效';

  @override
  String get sec_noteSounds => '打擊音效';

  @override
  String get sec_spots => '地點';

  @override
  String get sec_memory => '回憶';

  @override
  String get sec_liveBoost => '演出加成';

  @override
  String get sec_liveSkip => '演出跳過';

  @override
  String get sec_vip => 'T.G.W CARD';

  @override
  String get sec_offlineBonus => '離線獎勵';

  @override
  String get sec_arena => '競技場';
}
