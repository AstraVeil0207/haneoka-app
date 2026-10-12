/// Released artwork families from the website's image-dimensions.ts.
/// Reserve their intrinsic ratio before loading, keeping the layout stable.
double? familyImageRatio(String source) {
  final path = Uri.tryParse(source)?.path ?? source;
  for (final (pattern, ratio) in _families) {
    if (pattern.hasMatch(path)) return ratio;
  }
  return null;
}

final _families = <(RegExp, double)>[
  (RegExp(r'/Gacha/Banner/gacha_banner_'), 420 / 180),
  (RegExp(r'/Gacha/Logo/gacha_logo_'), 460 / 240),
  (RegExp(r'/Image/Event/[^/]+/Top/event_top_'), 1920 / 1440),
  (RegExp(r'/Image/Event/[^/]+/Logo/event_logo_'), 460 / 240),
  (RegExp(r'/Story/Banner/Chapter/ui_banner_chapter_'), 420 / 180),
  (RegExp(r'/Story/Banner/Episode/ui_banner_storyfriend_'), 370 / 160),
  (RegExp(r'/Story/Banner/Episode/ui_banner_chapter_'), 490 / 160),
  (RegExp(r'/Story/Image/Episode/ui_image_chapter_'), 1024 / 768),
  (RegExp(r'/Story/Image/Chapter/ui_image_chapter_'), 1564 / 1268),
  (RegExp(r'/Story/Icon/ui_icon_chapter_event_'), 460 / 240),
  (RegExp(r'/Story/Icon/ui_icon_chapter_'), 750 / 290),
  (RegExp(r'/Adv/Still/[^/]+/adv_still_'), 1920 / 1080),
  (RegExp(r'/Character/Image/[^/]+/character_thumbnail'), 270 / 740),
  (RegExp(r'/Character/Image/[^/]+/character_face_icon'), 1),
];
