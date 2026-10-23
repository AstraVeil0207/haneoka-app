import 'browse.dart' show naturalCompare;

const voiceGroups = [
  'normal',
  'realLive',
  'feature',
  'seasonal',
  'birthday',
  'growth',
  'gacha',
  'liveStart',
  'gekisouStart',
  'gekisouEnd',
  'liveEnd',
  'liveDialogue',
  'livePairDialogue',
  'liveResult',
  'liveBattleResult',
  'location',
  'title',
  'other',
];
const voiceTabs = [
  'comment',
  'growth',
  'gacha',
  'live',
  'location',
  'title',
  'other',
];
const voiceKinds = [
  'normal',
  'login',
  'characterRankUp',
  'exchange',
  'realLiveBefore',
  'realLiveDay',
  'feature',
  'spring',
  'summer',
  'autumn',
  'winter',
  'christmas',
  'newYear',
  'valentine',
  'seasonal',
  'birthday',
  'levelUp',
  'awaken',
  'skillUp',
  'rankUp',
  'gacha',
  'start',
  'gekisouCombo',
  'gekisouJust',
  'gekisouLuck',
  'gekisouTop',
  'clear',
  'fullCombo',
  'allPerfect',
  'combo',
  'skill',
  'result',
  'resultSolo',
  'resultPair',
  'battleFirst',
  'battleHigh',
  'battleLow',
  'spotEnter',
  'spotConversation',
  'spotTap',
  'spotAfter',
  'locationConversation',
  'titleBushiroad',
  'titleBushimo',
  'titleBushiroadGames',
  'titleFromTokyo',
  'titleBilibili',
  'titleApp',
  'titleOtherCompany',
  'other',
];
const _talkKinds = [
  'normal',
  'characterRankUp',
  'seasonal',
  'birthday',
  'login',
  'exchange',
  'realLiveDay',
  'levelUp',
  'realLiveBefore',
];
const _characterKinds = [
  'levelUp',
  'awaken',
  'skillUp',
  'rankUp',
  'clear',
  'fullCombo',
  'allPerfect',
  'result',
  'battleFirst',
  'battleHigh',
  'battleLow',
];

int voiceNumber(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String voiceKind(Map entry) {
  if (entry['voiceKind'] is String) return entry['voiceKind'] as String;
  String at(List<String> values, Object? index, String fallback) =>
      values.elementAtOrNull(voiceNumber(index)) ?? fallback;
  switch (voiceNumber(entry['masterType'])) {
    case 0:
      if (voiceNumber(entry['birthdayCharacterId']) > 0) return 'birthday';
      if (entry['seasonStartAt'] != null || entry['seasonEndAt'] != null) {
        return const {
              '4/1': 'spring',
              '7/1': 'summer',
              '9/1': 'autumn',
              '12/1': 'winter',
              '12/24': 'christmas',
              '1/1': 'newYear',
              '2/14': 'valentine',
            }['${entry['seasonStartAt']}'] ??
            'seasonal';
      }
      return at(_talkKinds, entry['talkCategory'], 'feature');
    case 1:
      return at(_characterKinds, entry['characterVoiceType'], 'other');
    case 2:
      return 'gacha';
    case 3:
      return 'skill';
    case 4:
      return at(
        const ['gekisouCombo', 'gekisouJust', 'gekisouLuck', 'gekisouTop'],
        entry['gekisouVoiceType'],
        'other',
      );
    case 5:
    case 6:
      return entry['dialogueType'] == 2 ? 'skill' : 'combo';
    case 7:
      return 'start';
    default:
      return 'other';
  }
}

String voiceGroup(Map entry) {
  if (voiceGroups.contains(entry['voiceGroup'])) {
    return entry['voiceGroup'] as String;
  }
  final kind = voiceKind(entry);
  if (entry['masterType'] == 0 &&
      const [1, 4, 5, 7].contains(entry['talkCategory'])) {
    return 'feature';
  }
  if (const ['normal', 'login', 'exchange'].contains(kind)) return 'normal';
  if (kind.startsWith('realLive')) return 'realLive';
  if (const [
    'spring',
    'summer',
    'autumn',
    'winter',
    'christmas',
    'newYear',
    'valentine',
    'seasonal',
  ].contains(kind)) {
    return 'seasonal';
  }
  if (kind == 'birthday') return 'birthday';
  if (const [
    'characterRankUp',
    'levelUp',
    'awaken',
    'skillUp',
    'rankUp',
  ].contains(kind)) {
    return 'growth';
  }
  if (kind == 'gacha') return 'gacha';
  if (kind == 'start') return 'liveStart';
  if (kind == 'gekisouTop') return 'gekisouEnd';
  if (kind.startsWith('gekisou')) return 'gekisouStart';
  if (const ['clear', 'fullCombo', 'allPerfect'].contains(kind)) {
    return 'liveEnd';
  }
  if (entry['masterType'] == 6) return 'livePairDialogue';
  if (const ['combo', 'skill'].contains(kind)) return 'liveDialogue';
  if (kind == 'result') return 'liveResult';
  if (kind.startsWith('battle')) return 'liveBattleResult';
  return kind == 'feature' ? 'feature' : 'other';
}

String voiceTab(Map entry) {
  if (entry['collectionTab'] != null) {
    return voiceTabs.elementAtOrNull(voiceNumber(entry['collectionTab'])) ??
        'other';
  }
  final group = voiceGroup(entry);
  if (const [
    'normal',
    'realLive',
    'feature',
    'seasonal',
    'birthday',
  ].contains(group)) {
    return 'comment';
  }
  return const ['growth', 'gacha', 'location', 'title', 'other'].contains(group)
      ? group
      : 'live';
}

Map preferredVoiceRecording(Map entry) {
  final recordings = entry['recordings'];
  if (recordings is! List || recordings.isEmpty) return entry;
  return {...entry}
    ..remove('recordings')
    ..addAll(recordings.first as Map);
}

int compareVoices(Map a, Map b, int character) {
  int birthday(Map entry) => entry['birthdayCharacterId'] == character
      ? -1
      : voiceNumber(entry['birthdayCharacterId']);
  for (final order in [
    voiceGroups
        .indexOf(voiceGroup(a))
        .compareTo(voiceGroups.indexOf(voiceGroup(b))),
    voiceKinds
        .indexOf(voiceKind(a))
        .compareTo(voiceKinds.indexOf(voiceKind(b))),
    birthday(a).compareTo(birthday(b)),
    voiceNumber(a['spotId']).compareTo(voiceNumber(b['spotId'])),
    voiceNumber(a['unlockCharacterRank'] ?? a['unlockFriendshipRank'])
        .compareTo(
          voiceNumber(b['unlockCharacterRank'] ?? b['unlockFriendshipRank']),
        ),
    voiceNumber(b['scoreRank']).compareTo(voiceNumber(a['scoreRank'])),
    naturalCompare(
      (a['characterIds'] as List? ?? []).join(','),
      (b['characterIds'] as List? ?? []).join(','),
    ),
    voiceNumber(a['masterId']).compareTo(voiceNumber(b['masterId'])),
    voiceNumber(a['variantNumber']).compareTo(voiceNumber(b['variantNumber'])),
    naturalCompare('${a['voiceKey']}', '${b['voiceKey']}'),
  ]) {
    if (order != 0) return order;
  }
  return 0;
}
