import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/detail_screen.dart';
import '../catalog/profiles.dart';
import '../catalog/songs.dart';
import '../core/app_state.dart';
import '../home/home_screen.dart';
import '../l10n/app_localizations.dart';
import '../ui/import_screen.dart';
import '../ui/player.dart';
import '../ui/theme.dart';
import 'page.dart';
import 'settings_screen.dart';
import 'web_sections.dart';

/// A place in the navigation: a top-level destination and, below it, one of its pages.
class NavEntry {
  const NavEntry(this.id, this.label, this.icon, this.build, {this.url});
  final String id;
  final String label;
  final IconData icon;
  final WidgetBuilder build;

  /// A website page not yet built into the app, opened in the in-app browser.
  final Uri? url;
}

class NavDestination {
  const NavDestination(this.id, this.label, this.icon, this.entries);
  final String id;
  final String label;
  final IconData icon;
  final List<NavEntry> entries;
}

List<NavDestination> _destinations(
  String Function(String, [String]) t,
  String importLabel,
  ValueChanged<String> select,
  String server,
  String locale,
) => [
  NavDestination('home', t('navigation.home', 'Home'), Symbols.home_rounded, [
    NavEntry(
      'home',
      t('navigation.home', 'Home'),
      Symbols.home_rounded,
      (_) => HomeScreen(onBrowse: select),
    ),
  ]),
  NavDestination(
    'catalog',
    t('navigation.library', 'Library'),
    Symbols.category_rounded,
    [
      for (final profile in catalogProfiles)
        NavEntry(
          'catalog/${profile.resource}',
          t(profile.label, profile.resource),
          profile.icon,
          (_) {
            void open(BuildContext context, Map<String, Object?> item) =>
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DetailScreen(
                      profile: profile,
                      id: '${firstOf(item, profile.id) ?? item['_key']}',
                      summary: item,
                    ),
                  ),
                );
            return profile.presentation == Presentation.song
                ? SongsScreen(onOpen: open)
                : CatalogScreen(profile: profile, onOpen: open);
          },
        ),
    ],
  ),
  for (final section in webSections)
    NavDestination(section.id, t(section.label), section.icon, [
      if (section.id == 'tools')
        NavEntry(
          'tools/save',
          importLabel,
          Symbols.download_rounded,
          (_) => const ImportScreen(),
        ),
      for (final page in section.pages)
        NavEntry(
          '${section.id}${page.route}',
          t(page.label),
          page.icon,
          (_) => const SizedBox.shrink(),
          url: page.url(server, locale),
        ),
    ]),
];

/// The website's shell: an expanded navigation drawer on wide windows, a rail
/// on medium ones, a modal drawer on phones; the page's bar and pane beside it.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  String _selected = 'home';
  bool _settings = false;

  Map<String, NavEntry> _entries = const {};

  void _select(String id) {
    final url = _entries[id]?.url;
    if (url != null) {
      _scaffold.currentState?.closeDrawer();
      launchUrl(url, mode: LaunchMode.inAppBrowserView);
      return;
    }
    setState(() {
      _selected = id;
      _settings = false;
    });
    _scaffold.currentState?.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final destinations = _destinations(
      (path, [fallback = '']) => t(path, fallback),
      AppLocalizations.of(context).importTitle,
      _select,
      state.server,
      state.text.locale,
    );
    final entries = {
      for (final d in destinations)
        for (final e in d.entries) e.id: e,
    };
    _entries = entries;
    final entry = entries[_selected] ?? destinations.first.entries.first;
    final page = Navigator(
      key: ValueKey(_settings ? 'settings' : entry.id),
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: _settings ? (_) => const SettingsScreen() : entry.build,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < ShellMetrics.compact;
        final drawer = _NavTree(
          destinations: destinations,
          selected: _settings ? 'settings' : entry.id,
          onSelect: _select,
          onSettings: () => setState(() {
            _settings = true;
            _scaffold.currentState?.closeDrawer();
          }),
          settingsLabel: t('navigation.settings', 'Settings'),
        );
        final body = ShellScope(
          compact: compact,
          openNavigation: () => _scaffold.currentState?.openDrawer(),
          child: page,
        );
        if (compact) {
          return Scaffold(
            key: _scaffold,
            drawer: Drawer(child: drawer),
            body: SafeArea(child: body),
          );
        }
        if (width < ShellMetrics.expanded) {
          final current = destinations.indexWhere(
            (d) => d.entries.any((e) => e.id == entry.id),
          );
          return Scaffold(
            key: _scaffold,
            drawer: Drawer(child: drawer),
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _settings ? null : current,
                  labelType: NavigationRailLabelType.all,
                  leading: Column(
                    children: [
                      const SizedBox(height: 8),
                      IconButton(
                        onPressed: () => _scaffold.currentState?.openDrawer(),
                        icon: const Icon(Symbols.menu_rounded),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: t('navigation.settings', 'Settings'),
                    onPressed: () => setState(() => _settings = true),
                    icon: const Icon(Symbols.settings_rounded),
                  ),
                  onDestinationSelected: (index) {
                    final first = destinations[index].entries.first;
                    if (first.url != null) {
                      _scaffold.currentState?.openDrawer();
                    } else {
                      _select(first.id);
                    }
                  },
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.icon, fill: 1),
                        label: Text(d.label),
                      ),
                  ],
                ),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          key: _scaffold,
          body: Row(
            children: [
              SizedBox(width: ShellMetrics.drawer, child: drawer),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}

/// The drawer's tree: brand, destinations, the open destination's pages, settings.
class _NavTree extends StatefulWidget {
  const _NavTree({
    required this.destinations,
    required this.selected,
    required this.onSelect,
    required this.onSettings,
    required this.settingsLabel,
  });
  final List<NavDestination> destinations;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onSettings;
  final String settingsLabel;

  @override
  State<_NavTree> createState() => _NavTreeState();
}

/// Sections fold as on the website: the one holding the current page starts
/// open, a section's heading opens or closes it.
class _NavTreeState extends State<_NavTree> {
  late final Set<String> _open = {
    for (final d in widget.destinations)
      if (d.entries.any((e) => e.id == widget.selected)) d.id,
  };

  @override
  Widget build(BuildContext context) {
    final destinations = widget.destinations;
    final selected = widget.selected;
    final onSelect = widget.onSelect;
    final theme = Theme.of(context);
    Widget item(
      String label,
      IconData icon,
      bool active,
      VoidCallback onTap, {
      double indent = 0,
      Widget? trailing,
    }) => Padding(
      padding: EdgeInsets.fromLTRB(12 + indent, 1, 12, 1),
      child: Material(
        color: active
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: indent > 0 ? 44 : 56,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(
                  icon,
                  fill: active ? 1 : 0,
                  size: indent > 0 ? 20 : 24,
                  color: active
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: active
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    child: trailing,
                  ),
                  const SizedBox(width: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: ShellMetrics.topBar,
              child: Row(
                children: [
                  const SizedBox(width: 28),
                  Image.asset(
                    'assets/brand/android-chrome-512x512.png',
                    width: 28,
                    height: 28,
                  ),
                  const SizedBox(width: 12),
                  Text('haneoka', style: theme.textTheme.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final destination in destinations) ...[
                    item(
                      destination.label,
                      destination.icon,
                      destination.entries.length == 1 &&
                          destination.entries.first.id == selected,
                      () => destination.entries.length == 1
                          ? onSelect(destination.entries.first.id)
                          : setState(() {
                              if (!_open.remove(destination.id)) {
                                _open.add(destination.id);
                              }
                            }),
                      trailing: destination.entries.length == 1
                          ? null
                          : Icon(
                              _open.contains(destination.id)
                                  ? Symbols.expand_less_rounded
                                  : Symbols.expand_more_rounded,
                              size: 20,
                            ),
                    ),
                    if (destination.entries.length > 1 &&
                        _open.contains(destination.id))
                      for (final entry in destination.entries)
                        item(
                          entry.label,
                          entry.icon,
                          entry.id == selected,
                          () => onSelect(entry.id),
                          indent: 16,
                          trailing: entry.url == null
                              ? null
                              : const Icon(
                                  Symbols.open_in_new_rounded,
                                  size: 16,
                                ),
                        ),
                  ],
                ],
              ),
            ),
            const NowPlaying(expanded: true),
            item(
              widget.settingsLabel,
              Symbols.settings_rounded,
              selected == 'settings',
              widget.onSettings,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
