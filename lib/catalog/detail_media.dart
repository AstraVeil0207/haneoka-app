import '../core/i18n.dart';
import '../ui/detail.dart';
import 'character_art.g.dart';
import 'profiles.dart';

const _languageTags = {
  'ja': 'ja',
  'en': 'en',
  'ko': 'ko',
  'zh-CN': 'zh-Hans',
  'zh-TW': 'zh-Hant',
};
const _languageNames = {
  'ja': ['日本語', 'Japanese', '日文', '日语', '일본어'],
  'en': ['英語', 'English', '英文', '英语', '영어'],
  'zh-Hant': ['繁体字中国語', 'Traditional Chinese', '繁體中文', '繁体中文', '중국어(번체)'],
  'zh-Hans': ['簡体字中国語', 'Simplified Chinese', '簡體中文', '简体中文', '중국어(간체)'],
  'ko': ['韓国語', 'Korean', '韓文', '韩语', '한국어'],
};

/// A detail page's gallery (`detailMediaItems`): each kind's own entries,
/// and, where the release ships them, one entry per language variant with
/// the reading locale's first. Returns the entries and the one shown first.
(List<GalleryImage>, int) detailMedia({
  required SiteText t,
  required String resource,
  required Presentation kind,
  required Map<String, Object?> item,
  required String Function(String) asset,
  required String? tileImage,
}) {
  String? str(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
  if (kind == Presentation.character) {
    final portraits = characterArt[(item['characterId'] as num?)?.toInt()];
    if (portraits != null && portraits.isNotEmpty) {
      return (
        [
          for (final (index, path) in portraits.indexed)
            GalleryImage(
              asset(path),
              '${t('media.images.fields.portrait', 'Portrait')} ${(index + 1).toString().padLeft(2, '0')}',
              localized: false,
            ),
        ],
        0,
      );
    }
  }
  final images = (item['images'] as Map?) ?? const {};
  String? detailImage() {
    if (resource == 'events' && str(item['backgroundImage']) != null) {
      return str(item['backgroundImage']);
    }
    final preferred = switch (kind) {
      Presentation.member || Presentation.support => str(images['full']),
      Presentation.song => str(item['jacketUrl']),
      Presentation.background || Presentation.comic => str(item['image']),
      _ => null,
    };
    return preferred ?? tileImage;
  }

  final entries = <(String id, String label, String? source)>[
    ...switch (kind) {
      Presentation.member => [
        (
          'full',
          t.label('details', 'Full'),
          str(images['full']) ?? str(images['thumbnail']),
        ),
        (
          'character',
          t.label('character', 'Character'),
          str(images['character']),
        ),
        (
          'background',
          t.label('stage', 'Background'),
          str(images['background']),
        ),
        ('skill', t.label('skills', 'Skill'), str(images['skill'])),
      ],
      Presentation.character => [
        (
          'sprite',
          t.label('character', 'Character'),
          str(item['spriteImage']) ?? str(item['profileImage']),
        ),
        ('profile', t.label('profile', 'Profile'), str(item['profileImage'])),
        ('face', t.label('visual', 'Visual'), str(item['faceImage'])),
      ],
      Presentation.support => [
        (
          'full',
          t.label('details', 'Full'),
          str(images['full']) ?? str(images['thumbnail']),
        ),
        ('skill', t.label('skills', 'Skill'), str(images['skill'])),
      ],
      _ => [
        ('full', t.label('details', 'Preview'), detailImage()),
        if (resource == 'events' && str(item['logo']) != null)
          ('logo', t.label('eventLogo', 'Event logo'), str(item['logo'])),
        if (resource == 'events' && str(item['image']) != null)
          (
            'banner',
            t.label('eventBanner', 'Event banner'),
            str(item['image']),
          ),
      ],
    },
  ];
  final variants = (item['imageVariants'] as Map?) ?? const {};
  final localeTag = _languageTags[t.locale] ?? t.locale;
  final languages = ['ja', 'en', 'zh-Hant', 'zh-Hans', 'ko']
    ..sort((a, b) => (b == localeTag ? 1 : 0) - (a == localeTag ? 1 : 0));
  final seen = <String>{};
  final out = <(String, GalleryImage)>[];
  for (final (id, label, source) in entries) {
    if (source == null || !seen.add(source)) continue;
    final byLanguage = variants[source] ?? variants[source.split('?').first];
    if (byLanguage is Map) {
      for (final language in languages) {
        if (str(byLanguage[language]) case final variant?) {
          final name =
              _languageNames[language]?[SiteText.tupleOrder
                  .indexOf(t.locale)
                  .clamp(0, 4)] ??
              language;
          out.add((
            '$id:$language',
            GalleryImage(asset(variant), '$label · $name', localized: false),
          ));
        }
      }
    } else {
      out.add((id, GalleryImage(asset(source), label)));
    }
  }
  // The full art leads in the reading locale, else in Japanese.
  var active = out.indexWhere((e) => e.$1 == 'full:$localeTag');
  if (active < 0) active = out.indexWhere((e) => e.$1 == 'full:ja');
  if (active < 0) active = 0;
  return ([for (final (_, image) in out) image], active);
}
