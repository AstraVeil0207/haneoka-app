import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'audio.dart';
import 'i18n.dart';

/// The reader's choices and what follows from them: release server, language,
/// the API client and the site's text for that language.
class AppState extends ChangeNotifier {
  AppState._(this._prefs, this.server, this.text)
    : api = HaneokaApi(server: server),
      themeMode = ThemeMode.values.byName(
        _prefs.getString('themeMode') ?? ThemeMode.system.name,
      ),
      seed = _prefs.getString('seed') ?? 'haneoka';
  final SharedPreferences _prefs;
  String server;
  SiteText text;
  HaneokaApi api;
  final AudioService audio = AudioService();

  /// The website's appearance: light, dark or the system's, and the theme colour.
  ThemeMode themeMode;
  String seed;

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    await _prefs.setString('themeMode', value.name);
    notifyListeners();
  }

  Future<void> setSeed(String value) async {
    seed = value;
    await _prefs.setString('seed', value);
    notifyListeners();
  }

  static const servers = ['intl', 'jp'];

  static Future<AppState> load(Locale systemLocale) async {
    final prefs = await SharedPreferences.getInstance();
    final locale = prefs.getString('locale') ?? _siteLocale(systemLocale);
    return AppState._(
      prefs,
      prefs.getString('server') ?? 'intl',
      await SiteText.load(locale),
    );
  }

  static String _siteLocale(Locale locale) {
    if (locale.languageCode == 'zh') {
      return locale.scriptCode == 'Hant' ||
              ['TW', 'HK', 'MO'].contains(locale.countryCode)
          ? 'zh-TW'
          : 'zh-CN';
    }
    return SiteText.locales.contains(locale.languageCode)
        ? locale.languageCode
        : 'en';
  }

  Locale get locale {
    final parts = text.locale.split('-');
    return Locale(parts.first, parts.length > 1 ? parts[1] : null);
  }

  Future<void> setServer(String value) async {
    server = value;
    api = HaneokaApi(server: value);
    await _prefs.setString('server', value);
    notifyListeners();
  }

  Future<void> setLocale(String value) async {
    text = await SiteText.load(value);
    await _prefs.setString('locale', value);
    notifyListeners();
  }
}

/// Makes the [AppState] reachable from any widget.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);
  static AppState of(BuildContext context) => maybeOf(context)!;

  static AppState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;
}
