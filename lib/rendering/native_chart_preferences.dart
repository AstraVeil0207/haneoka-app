import 'package:shared_preferences/shared_preferences.dart';
import 'package:cassiopeia_plugin_our_notes/chart_ui_profile.dart';

/// Local renderer choices persist independently of accounts and song data.
final class NativeChartPreferences {
  const NativeChartPreferences({
    this.noteSkin = 'skin001',
    this.noteEffectSkin = 'effect001',
    this.noteSeGroup = 1,
    this.noteSpeed = 5,
    this.mirror = false,
    this.continuation = true,
    this.playbackRate = 1,
    this.musicVolume = 100,
    this.effectQuality = 1,
    this.showCombo = true,
    this.vibration = true,
    this.noteSize = 1,
    this.longAlpha = .6,
    this.guideAlpha = .6,
    this.effects = true,
    this.showSimultaneousLine = true,
    this.showJudgementLine = false,
    this.backgroundBrightness = .7,
    this.laneOpacity = .8,
    this.guidelineOpacity = .25,
    this.guidelineCount = OurNotesChartUiProfile.guidelineCountDefault,
    this.stageBackground = 'auto',
  });
  static const noteSkins = ['skin001', 'skin002', 'skin003'];
  static const noteEffectSkins = ['effect001', 'effect001Simple'];
  static const stageBackgrounds = [
    'auto',
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    'none',
  ];
  static const stageNames = {
    '0': {
      'ja': 'ステージ',
      'en': 'Stage',
      'zh-TW': '舞台',
      'zh-CN': '舞台',
      'ko': '스테이지',
    },
    '1': {
      'ja': 'MyGO!!!!!',
      'en': 'MyGO!!!!!',
      'zh-TW': 'MyGO!!!!!',
      'zh-CN': 'MyGO!!!!!',
      'ko': 'MyGO!!!!!',
    },
    '2': {
      'ja': 'Ave Mujica',
      'en': 'Ave Mujica',
      'zh-TW': 'Ave Mujica',
      'zh-CN': 'Ave Mujica',
      'ko': 'Ave Mujica',
    },
    '3': {
      'ja': '夢限大みゅーたいぷ',
      'en': 'Mugendai MewType',
      'zh-TW': '夢限大MewType',
      'zh-CN': '梦限大MewType',
      'ko': '무겐다이 뮤타입',
    },
    '4': {
      'ja': 'millsage',
      'en': 'millsage',
      'zh-TW': 'millsage',
      'zh-CN': 'millsage',
      'ko': 'millsage',
    },
    '5': {
      'ja': '一家Dumb Rock!',
      'en': 'Ikka Dumb Rock!',
      'zh-TW': '一家Dumb Rock!',
      'zh-CN': '一家Dumb Rock!',
      'ko': '일가 Dumb Rock!',
    },
  };
  static const noteEffectSkinNames = {
    'effect001': {
      'ja': 'スタンダード',
      'en': 'Standard',
      'zh-TW': '標準',
      'zh-CN': '标准',
      'ko': '스탠다드',
    },
    'effect001Simple': {
      'ja': 'シンプル',
      'en': 'Simple',
      'zh-TW': '簡約',
      'zh-CN': '简洁',
      'ko': '심플',
    },
  };
  static const noteSkinNames = {
    'skin001': {
      'ja': 'アワーノーツ',
      'en': 'Our Notes',
      'zh-TW': '交織的樂章',
      'zh-CN': '交织的乐章',
      'ko': '아워 노트',
    },
    'skin002': {
      'ja': 'ガルパ',
      'en': 'Garupa',
      'zh-TW': '邦邦',
      'zh-CN': '少女乐团派对',
      'ko': '걸파',
    },
    'skin003': {
      'ja': 'ハニカム',
      'en': 'Honeycomb',
      'zh-TW': 'Honeycomb',
      'zh-CN': '蜂巢',
      'ko': '허니콤',
    },
  };
  final String noteSkin, noteEffectSkin, stageBackground;
  int? backgroundBand(int songBand) => stageBackground == 'auto'
      ? songBand
      : stageBackground == 'none'
      ? null
      : int.parse(stageBackground);
  final int noteSeGroup;
  final double noteSpeed;
  final bool mirror, continuation;
  final bool showCombo, vibration;
  final double playbackRate, musicVolume;
  final double noteSize, longAlpha, guideAlpha;
  final bool effects, showSimultaneousLine, showJudgementLine;
  final double backgroundBrightness, laneOpacity, guidelineOpacity;
  final int guidelineCount;
  String get effectTier => noteEffectSkin == 'effect001Simple'
      ? 'simple'
      : effectQuality == 2
      ? 'light'
      : 'full';

  /// Original render tiers: High 0, Middle 1, Low 2.
  final int effectQuality;

  NativeChartPreferences copyWith({
    String? noteSkin,
    String? noteEffectSkin,
    int? noteSeGroup,
    double? noteSpeed,
    bool? mirror,
    bool? continuation,
    double? playbackRate,
    double? musicVolume,
    int? effectQuality,
    bool? showCombo,
    bool? vibration,
    double? noteSize,
    double? longAlpha,
    double? guideAlpha,
    bool? effects,
    bool? showSimultaneousLine,
    bool? showJudgementLine,
    double? backgroundBrightness,
    double? laneOpacity,
    double? guidelineOpacity,
    int? guidelineCount,
    String? stageBackground,
  }) => NativeChartPreferences(
    noteSkin: noteSkin ?? this.noteSkin,
    noteEffectSkin: noteEffectSkin ?? this.noteEffectSkin,
    noteSeGroup: noteSeGroup ?? this.noteSeGroup,
    noteSpeed: noteSpeed ?? this.noteSpeed,
    mirror: mirror ?? this.mirror,
    continuation: continuation ?? this.continuation,
    playbackRate: playbackRate ?? this.playbackRate,
    musicVolume: musicVolume ?? this.musicVolume,
    effectQuality: effectQuality ?? this.effectQuality,
    showCombo: showCombo ?? this.showCombo,
    vibration: vibration ?? this.vibration,
    noteSize: noteSize ?? this.noteSize,
    longAlpha: longAlpha ?? this.longAlpha,
    guideAlpha: guideAlpha ?? this.guideAlpha,
    effects: effects ?? this.effects,
    showSimultaneousLine: showSimultaneousLine ?? this.showSimultaneousLine,
    showJudgementLine: showJudgementLine ?? this.showJudgementLine,
    backgroundBrightness: backgroundBrightness ?? this.backgroundBrightness,
    laneOpacity: laneOpacity ?? this.laneOpacity,
    guidelineOpacity: guidelineOpacity ?? this.guidelineOpacity,
    guidelineCount: guidelineCount ?? this.guidelineCount,
    stageBackground: stageBackground ?? this.stageBackground,
  );

  static Future<NativeChartPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    const startupSkin = String.fromEnvironment('HANEOKA_NATIVE_NOTE_SKIN');
    final skin = startupSkin.isEmpty
        ? preferences.getString('nativeChart.noteSkin')
        : startupSkin;
    return NativeChartPreferences(
      noteSkin: noteSkins.contains(skin) ? skin! : 'skin001',
      noteEffectSkin:
          noteEffectSkins.contains(
            preferences.getString('nativeChart.noteEffectSkin'),
          )
          ? preferences.getString('nativeChart.noteEffectSkin')!
          : 'effect001',
      noteSeGroup: (preferences.getInt('nativeChart.noteSeGroup') ?? 1).clamp(
        1,
        4,
      ),
      noteSpeed: (preferences.getDouble('nativeChart.noteSpeed') ?? 5).clamp(
        1.0,
        12.0,
      ),
      mirror: preferences.getBool('nativeChart.mirror') ?? false,
      continuation: preferences.getBool('nativeChart.continuation') ?? true,
      playbackRate: (preferences.getDouble('nativeChart.playbackRate') ?? 1)
          .clamp(.5, 2.0),
      musicVolume: (preferences.getDouble('nativeChart.musicVolume') ?? 100)
          .clamp(0.0, 100.0),
      effectQuality: (preferences.getInt('nativeChart.effectQuality') ?? 1)
          .clamp(0, 2),
      showCombo: preferences.getBool('nativeChart.showCombo') ?? true,
      vibration: preferences.getBool('nativeChart.vibration') ?? true,
      noteSize: (preferences.getDouble('nativeChart.noteSize') ?? 1).clamp(
        .5,
        1.5,
      ),
      longAlpha: (preferences.getDouble('nativeChart.longAlpha') ?? .6).clamp(
        .1,
        1,
      ),
      guideAlpha: (preferences.getDouble('nativeChart.guideAlpha') ?? .6).clamp(
        .1,
        1,
      ),
      effects: preferences.getBool('nativeChart.effects') ?? true,
      showSimultaneousLine:
          preferences.getBool('nativeChart.showSimultaneousLine') ?? true,
      showJudgementLine:
          preferences.getBool('nativeChart.showJudgementLine') ?? false,
      backgroundBrightness:
          (preferences.getDouble('nativeChart.backgroundBrightness') ?? .7)
              .clamp(0, 1),
      laneOpacity: (preferences.getDouble('nativeChart.laneOpacity') ?? .8)
          .clamp(0, 1),
      guidelineOpacity:
          (preferences.getDouble('nativeChart.guidelineOpacity') ?? .25).clamp(
            0,
            1,
          ),
      guidelineCount:
          OurNotesChartUiProfile.guidelineCounts.contains(
            preferences.getInt('nativeChart.guidelineCount'),
          )
          ? preferences.getInt('nativeChart.guidelineCount')!
          : OurNotesChartUiProfile.guidelineCountDefault,
      stageBackground:
          stageBackgrounds.contains(
            preferences.getString('nativeChart.stageBackground'),
          )
          ? preferences.getString('nativeChart.stageBackground')!
          : 'auto',
    );
  }

  void validate() {
    if (noteSeGroup < 1 ||
        noteSeGroup > 4 ||
        !noteSkins.contains(noteSkin) ||
        !noteEffectSkins.contains(noteEffectSkin) ||
        !OurNotesChartUiProfile.guidelineCounts.contains(guidelineCount) ||
        !stageBackgrounds.contains(stageBackground) ||
        !noteSize.isFinite ||
        noteSize < .5 ||
        noteSize > 1.5 ||
        !longAlpha.isFinite ||
        longAlpha < .1 ||
        longAlpha > 1 ||
        !guideAlpha.isFinite ||
        guideAlpha < .1 ||
        guideAlpha > 1 ||
        !backgroundBrightness.isFinite ||
        backgroundBrightness < 0 ||
        backgroundBrightness > 1 ||
        !laneOpacity.isFinite ||
        laneOpacity < 0 ||
        laneOpacity > 1 ||
        !guidelineOpacity.isFinite ||
        guidelineOpacity < 0 ||
        guidelineOpacity > 1 ||
        !noteSpeed.isFinite ||
        noteSpeed < 1 ||
        noteSpeed > 12 ||
        !playbackRate.isFinite ||
        playbackRate < .5 ||
        playbackRate > 2 ||
        !musicVolume.isFinite ||
        musicVolume < 0 ||
        musicVolume > 100 ||
        effectQuality < 0 ||
        effectQuality > 2) {
      throw ArgumentError('native_chart_preferences');
    }
  }

  Future<void> save() async {
    validate();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('nativeChart.noteSkin', noteSkin);
    await preferences.setString('nativeChart.noteEffectSkin', noteEffectSkin);
    await preferences.setInt('nativeChart.noteSeGroup', noteSeGroup);
    await preferences.setDouble('nativeChart.noteSpeed', noteSpeed);
    await preferences.setBool('nativeChart.mirror', mirror);
    await preferences.setBool('nativeChart.continuation', continuation);
    await preferences.setDouble('nativeChart.playbackRate', playbackRate);
    await preferences.setDouble('nativeChart.musicVolume', musicVolume);
    await preferences.setInt('nativeChart.effectQuality', effectQuality);
    await preferences.setBool('nativeChart.showCombo', showCombo);
    await preferences.setBool('nativeChart.vibration', vibration);
    await preferences.setDouble('nativeChart.noteSize', noteSize);
    await preferences.setDouble('nativeChart.longAlpha', longAlpha);
    await preferences.setDouble('nativeChart.guideAlpha', guideAlpha);
    await preferences.setBool('nativeChart.effects', effects);
    await preferences.setBool(
      'nativeChart.showSimultaneousLine',
      showSimultaneousLine,
    );
    await preferences.setBool(
      'nativeChart.showJudgementLine',
      showJudgementLine,
    );
    await preferences.setDouble(
      'nativeChart.backgroundBrightness',
      backgroundBrightness,
    );
    await preferences.setDouble('nativeChart.laneOpacity', laneOpacity);
    await preferences.setDouble(
      'nativeChart.guidelineOpacity',
      guidelineOpacity,
    );
    await preferences.setInt('nativeChart.guidelineCount', guidelineCount);
    await preferences.setString('nativeChart.stageBackground', stageBackground);
  }
}
