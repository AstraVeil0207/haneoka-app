import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Matches the website's Roboto and locally hosted Noto Sans families.
const appFont = 'Roboto';

/// Regional Han glyphs follow the interface locale. Every family is bundled so
/// original game names and community text remain available while offline.
List<String> appFontFallback(Locale locale) {
  const sc = 'Noto Sans SC',
      tc = 'Noto Sans TC',
      jp = 'Noto Sans JP',
      kr = 'Noto Sans KR';
  final traditional =
      locale.scriptCode == 'Hant' ||
      const {'TW', 'HK', 'MO'}.contains(locale.countryCode);
  return switch (locale.languageCode) {
    'zh' when traditional => const [tc, jp, sc, kr, 'sans-serif'],
    'zh' => const [sc, jp, tc, kr, 'sans-serif'],
    'ko' => const [kr, jp, sc, tc, 'sans-serif'],
    _ => const [jp, sc, tc, kr, 'sans-serif'],
  };
}

void registerAppFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Noto Sans SC',
      'Noto Sans TC',
      'Noto Sans JP',
      'Noto Sans KR',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
}
