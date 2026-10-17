import 'api.dart';

/// Another game's data as the website's worker projects it into catalogue
/// records (`origin: "bestdori"` / `"sekai"`): GBP through Bestdori, and
/// Project Sekai. The region follows the reading language.
class ProviderApi extends HaneokaApi {
  ProviderApi({required this.provider, required this.locale})
    : region = _regions[locale] ?? 'jp',
      super(server: '$provider-${_regions[locale] ?? 'jp'}-$locale');

  static const _regions = {
    'zh-TW': 'tw',
    'zh-CN': 'cn',
    'ko': 'kr',
    'en': 'en',
  };

  /// `bestdori` or `sekai`.
  final String provider;
  final String locale;
  final String region;

  String get base => provider == 'sekai'
      ? '/api/v1/sekai/$region'
      : '/api/v1/garupa/bestdori/$region';

  /// Provider data has no release pin; a day's copy is kept.
  @override
  Future<String> release() async =>
      DateTime.now().toUtc().toIso8601String().substring(0, 10);

  @override
  Future<Object?> catalog(String resource, [String? id]) => json(
    '$base/$resource${id == null ? '' : '/${Uri.encodeComponent(id)}'}'
    '?lang=${Uri.encodeQueryComponent(locale)}'
    '${resource == 'bands' || resource == 'songs'
        ? '&projection=round-performers-v1'
        : resource.startsWith('stories') || resource == 'cards'
        ? '&projection=v24-language-fallback'
        : ''}',
  );
}

/// Canonical game identity for a catalogue source, distinct from its provider.
String catalogGame(HaneokaApi api) => api is ProviderApi
    ? api.provider == 'sekai'
          ? 'sekai'
          : 'gbp'
    : 'our-notes';
