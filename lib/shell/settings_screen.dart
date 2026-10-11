import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../catalog/visuals.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../ui/detail.dart';
import '../ui/schemes.g.dart';
import '../ui/tile.dart';
import 'page.dart';

/// The website's settings: release server, language and appearance, then
/// what the app is and where it comes from.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _languages = {
    'ja': '日本語',
    'en': 'English',
    'zh-TW': '繁體中文',
    'zh-CN': '简体中文',
    'ko': '한국어',
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final theme = Theme.of(context);
    Widget row(String label, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          control,
        ],
      ),
    );
    return ShellPage(
      title: t('navigation.settings', 'Settings'),
      body: ListView(
        padding: pagePadding(context),
        children: [
          DetailSection(
            icon: Symbols.public_rounded,
            title: t('settings.labels.server', 'Server'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row(
                  t('settings.labels.server', 'Server'),
                  SegmentedButton<String>(
                    segments: [
                      for (final server in AppState.servers)
                        ButtonSegment(
                          value: server,
                          label: Text(
                            server == 'jp'
                                ? t('settings.labels.settingsJapan', 'Japan')
                                : t(
                                    'settings.labels.settingsGlobal',
                                    'International',
                                  ),
                          ),
                        ),
                    ],
                    selected: {state.server},
                    onSelectionChanged: (value) =>
                        state.setServer(value.single),
                  ),
                ),
                row(
                  t('settings.labels.language', 'Language'),
                  DropdownMenu<String>(
                    initialSelection: state.text.locale,
                    onSelected: (value) =>
                        value == null ? null : state.setLocale(value),
                    dropdownMenuEntries: [
                      for (final code in SiteText.locales)
                        DropdownMenuEntry(
                          value: code,
                          label: _languages[code]!,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          DetailSection(
            icon: Symbols.palette_rounded,
            title: t('settings.labels.appearance', 'Appearance'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: const Icon(Symbols.brightness_auto_rounded),
                      label: Text(t('settings.labels.themeSystem', 'System')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: const Icon(Symbols.light_mode_rounded),
                      label: Text(t('settings.labels.themeLight', 'Light')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: const Icon(Symbols.dark_mode_rounded),
                      label: Text(t('settings.labels.themeDark', 'Dark')),
                    ),
                  ],
                  selected: {state.themeMode},
                  onSelectionChanged: (value) =>
                      state.setThemeMode(value.single),
                ),
                const SizedBox(height: 16),
                Text(
                  t('settings.labels.themeColor', 'Theme colour'),
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                FutureBuilder(
                  future: CatalogVisuals.of(state.api),
                  builder: (context, snapshot) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final seed in haneokaSchemes.keys)
                        _Swatch(
                          seed: seed,
                          selected: state.seed == seed,
                          label: seed == 'haneoka'
                              ? 'haneoka'
                              : t.text(
                                  snapshot.data?.bands[int.tryParse(
                                    seed.split('-').last,
                                  )]?['bandName'],
                                ),
                          onTap: () => state.setSeed(seed),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          DetailSection(
            icon: Symbols.info_rounded,
            title: t('navigation.about', 'About'),
            child: FutureBuilder(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data;
                Widget link(IconData icon, String label, String url) =>
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(icon),
                      title: Text(label),
                      trailing: const Icon(Symbols.open_in_new_rounded),
                      onTap: () => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                    );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Image.asset(
                        'assets/brand/android-chrome-512x512.png',
                        width: 40,
                      ),
                      title: const Text('haneoka'),
                      subtitle: Text(
                        version == null
                            ? ''
                            : '${version.version} (${version.buildNumber})',
                      ),
                    ),
                    link(
                      Symbols.language_rounded,
                      'haneoka.org',
                      'https://haneoka.org/',
                    ),
                    link(
                      Symbols.code_rounded,
                      'GitHub',
                      'https://github.com/haneoka-gakuen/haneoka-app',
                    ),
                    link(
                      Symbols.policy_rounded,
                      t('legal.privacy.title', 'Privacy'),
                      'https://haneoka.org/${t.locale}/privacy/',
                    ),
                    link(
                      Symbols.gavel_rounded,
                      t('legal.terms.title', 'Terms'),
                      'https://haneoka.org/${t.locale}/terms/',
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.license_rounded),
                      title: Text(t('legal.license.title', 'Licences')),
                      trailing: const Icon(Symbols.chevron_right_rounded),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'haneoka',
                        applicationVersion: version?.version,
                        applicationIcon: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Image.asset(
                            'assets/brand/android-chrome-512x512.png',
                            width: 64,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.seed,
    required this.selected,
    required this.label,
    required this.onTap,
  });
  final String seed;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final (light, dark) = haneokaSchemes[seed]!;
    final scheme = brightness == Brightness.dark ? dark : light;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                scheme.primary,
                scheme.tertiary,
                scheme.secondary,
                scheme.primary,
              ],
            ),
            border: Border.all(
              width: selected ? 3 : 1,
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: selected
              ? Icon(Symbols.check_rounded, color: scheme.onPrimary)
              : null,
        ),
      ),
    );
  }
}
