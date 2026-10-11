import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/catalog/skill_text.dart';

void main() {
  const template =
      '{0 < effects[0].time ? "LUCK撃奏開始から" : ""}<color=#66FF8C>'
      '{0 < effects[0].time ? effects[0].time ~ "秒間" : "LUCK撃奏中"}</color>'
      r'\n抽選ゲージ獲得量{effects[0].value/100:F1}%UP';
  final effects = [
    {
      'raw': {'_level': 1, '_activationTimeSecond': 2, '_effectValue': 5000},
    },
    {
      'raw': {'_level': 5, '_activationTimeSecond': 0, '_effectValue': 10000},
    },
  ];
  String text(int? level) => skillDescription(
    template,
    skillLevelEffects(effects, level).effects,
    (value) => '$value',
  );

  test('fills the highest level by default', () {
    expect(text(null), 'LUCK撃奏中\n抽選ゲージ獲得量100.0%UP');
  });
  test('takes the time branch when the effect has a duration', () {
    expect(text(1), 'LUCK撃奏開始から2秒間\n抽選ゲージ獲得量50.0%UP');
  });
}
