// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Haneoka';

  @override
  String get importTitle => '세이브 가져오기';

  @override
  String get sourceShizuku => '이 휴대폰 · Shizuku';

  @override
  String get sourceGrantFolder => '이 휴대폰 · 게임 폴더';

  @override
  String get sourceFiles => '파일 또는 폴더';

  @override
  String get sourceAdb => 'Android 휴대폰 · USB 또는 Wi-Fi';

  @override
  String get sourceIosBackup => 'iPhone 또는 iPad 백업';

  @override
  String get releaseIntlOfficial => '글로벌 · 공식';

  @override
  String get releaseIntlStore => '글로벌 · Google Play';

  @override
  String get releaseJp => '일본';

  @override
  String get release => '버전';

  @override
  String get shizukuNotRunning => 'Shizuku가 실행 중이 아닙니다';

  @override
  String get shizukuUnsupported => 'Shizuku 업데이트가 필요합니다';

  @override
  String get openShizuku => 'Shizuku 열기';

  @override
  String get read => '읽기';

  @override
  String get reading => '읽는 중';

  @override
  String get noSaves => '세이브를 찾지 못했습니다';

  @override
  String get noGameInBackup => '이 백업에는 아워 노츠 데이터가 없습니다';

  @override
  String get backupPassword => '백업 비밀번호';

  @override
  String get wrongPassword => '백업 비밀번호가 틀렸습니다';

  @override
  String get noBackups => '백업이 없습니다';

  @override
  String get chooseBackupFolder => '백업 폴더 선택';

  @override
  String get encrypted => '암호화됨';

  @override
  String get devices => '기기';

  @override
  String get noDevices => '연결된 휴대폰이 없습니다';

  @override
  String get deviceUnauthorized => '휴대폰에서 USB 디버깅을 허용하세요';

  @override
  String get adbMissing => 'adb를 찾을 수 없습니다';

  @override
  String get chooseAdb => 'adb 선택';

  @override
  String get getPlatformTools => 'Platform Tools 받기';

  @override
  String get pairWireless => 'Wi-Fi로 페어링';

  @override
  String get pairAddress => 'IP 주소와 포트';

  @override
  String get pairCode => '페어링 코드';

  @override
  String get connectAddress => '연결 주소';

  @override
  String get pairFailed => '페어링 실패';

  @override
  String get refresh => '새로고침';

  @override
  String get gameNotInstalled => '아워 노츠가 설치되어 있지 않습니다';

  @override
  String get accounts => '계정';

  @override
  String get playerId => '플레이어 ID';

  @override
  String get savedAt => '저장 시각';

  @override
  String get source => '가져온 곳';

  @override
  String get playerExp => '플레이어 경험치';

  @override
  String get vipRank => 'T.G.W CARD';

  @override
  String get highScoreRating => '하이스코어 레이팅';

  @override
  String get clears => '클리어 악곡';

  @override
  String get exportTeam => '팀 빌더용 복사';

  @override
  String get exportSave => '파일로 저장';

  @override
  String get copied => '복사했습니다';

  @override
  String get saved => '저장했습니다';

  @override
  String get settings => '게임 설정';

  @override
  String get latestLive => '최근 라이브';

  @override
  String get allFields => '전체 항목';

  @override
  String entries(int count) {
    return '$count개';
  }

  @override
  String get sec_memberCards => '멤버';

  @override
  String get sec_snapshots => '스냅';

  @override
  String get sec_characters => '캐릭터 랭크';

  @override
  String get sec_friendships => '친밀도';

  @override
  String get sec_bandItems => '밴드 아이템';

  @override
  String get sec_items => '아이템';

  @override
  String get sec_songs => '악곡 기록';

  @override
  String get sec_ratings => '레이팅 대상곡';

  @override
  String get sec_challengeSongs => '챌린지 악곡';

  @override
  String get sec_events => '이벤트';

  @override
  String get sec_challengeLives => '챌린지 라이브';

  @override
  String get sec_gacha => '가챠';

  @override
  String get sec_stories => '읽은 스토리';

  @override
  String get sec_decks => '편성';

  @override
  String get sec_missions => '미션';

  @override
  String get sec_limitedMissions => '기간 한정 미션';

  @override
  String get sec_characterMissions => '캐릭터 미션';

  @override
  String get sec_seasonPass => '시즌 패스';

  @override
  String get sec_monthlyPass => '먼슬리 패스';

  @override
  String get sec_loginBonuses => '로그인 보너스';

  @override
  String get sec_costumes => '의상';

  @override
  String get sec_currentCostumes => '착용 중인 의상';

  @override
  String get sec_backgrounds => '배경';

  @override
  String get sec_stamps => '스탬프';

  @override
  String get sec_degrees => '칭호';

  @override
  String get sec_profileCards => '프로필 카드';

  @override
  String get sec_laneSkins => '레인 스킨';

  @override
  String get sec_noteSkins => '노트 스킨';

  @override
  String get sec_noteEffectSkins => '노트 이펙트';

  @override
  String get sec_noteSounds => '노트 효과음';

  @override
  String get sec_spots => '스폿';

  @override
  String get sec_memory => '메모리';

  @override
  String get sec_liveBoost => '라이브 부스트';

  @override
  String get sec_liveSkip => '라이브 스킵';

  @override
  String get sec_vip => 'T.G.W CARD';

  @override
  String get sec_offlineBonus => '오프라인 보너스';

  @override
  String get sec_arena => '아레나';
}
