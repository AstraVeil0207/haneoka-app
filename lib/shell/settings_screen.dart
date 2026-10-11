import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';

/// Release server and language, the website's two reading choices.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _languages = {'ja': '日本語', 'en': 'English', 'zh-TW': '繁體中文', 'zh-CN': '简体中文', 'ko': '한국어'};

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    return Scaffold(
      appBar: AppBar(title: Text(t('navigation.settings', 'Settings'))),
      body: ListView(children: [
        ListTile(
          title: Text(t('settings.labels.server', 'Server')),
          trailing: SegmentedButton<String>(
            segments: [
              for (final server in AppState.servers)
                ButtonSegment(value: server, label: Text(server == 'jp' ? t('settings.labels.settingsJapan', 'Japan') : t('settings.labels.settingsGlobal', 'International'))),
            ],
            selected: {state.server},
            onSelectionChanged: (value) => state.setServer(value.single),
          ),
        ),
        ListTile(
          title: Text(t('settings.labels.language', 'Language')),
          trailing: DropdownButton<String>(
            value: state.text.locale,
            onChanged: (value) => value == null ? null : state.setLocale(value),
            items: [for (final code in SiteText.locales) DropdownMenuItem(value: code, child: Text(_languages[code]!))],
          ),
        ),
      ]),
    );
  }
}
