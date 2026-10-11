import 'dart:convert';

import 'package:flutter/services.dart';

/// The website's message catalogues, bundled so every label matches haneoka.org.
class SiteText {
  SiteText._(this.locale, this._messages);
  final String locale;
  final Map<String, Object?> _messages;

  static const locales = ['ja', 'en', 'zh-TW', 'zh-CN', 'ko'];

  static Future<SiteText> load(String locale) async {
    final raw = await rootBundle.loadString('assets/i18n/$locale.json');
    return SiteText._(locale, jsonDecode(raw) as Map<String, Object?>);
  }

  /// A dotted message path, with `{name}` values filled in.
  String call(String path, [String fallback = '', Map<String, Object?> values = const {}]) {
    Object? node = _messages;
    for (final part in path.split('.')) {
      node = node is Map<String, Object?> ? node[part] : null;
    }
    var text = node is String ? node : fallback;
    values.forEach((key, value) => text = text.replaceAll('{$key}', '$value'));
    return text;
  }

  /// The site's tuple order for localized game text.
  static const tupleOrder = ['ja', 'en', 'zh-TW', 'zh-CN', 'ko'];
  static const _fallbacks = {
    'zh-TW': ['zh-TW', 'zh-CN', 'ja', 'en'],
    'zh-CN': ['zh-CN', 'zh-TW', 'ja', 'en'],
    'ko': ['ko', 'ja', 'en'],
    'en': ['en', 'ja'],
    'ja': ['ja', 'en'],
  };

  /// Game text: a five-slot tuple, a locale map, or plain text.
  String text(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num) return '$value';
    final order = _fallbacks[locale] ?? const ['ja', 'en'];
    if (value is List) {
      for (final code in order) {
        final i = tupleOrder.indexOf(code);
        if (i < value.length && value[i] is String && (value[i] as String).trim().isNotEmpty) return value[i] as String;
      }
      return value.whereType<String>().firstWhere((s) => s.trim().isNotEmpty, orElse: () => '');
    }
    if (value is Map) {
      for (final code in order) {
        final v = value[code];
        if (v is String && v.trim().isNotEmpty) return v;
      }
      if (value['text'] != null) return text(value['text']);
    }
    return '';
  }
}
