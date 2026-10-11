import 'package:flutter/material.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/profiles.dart';
import '../core/app_state.dart';
import '../ui/import_screen.dart';
import 'settings_screen.dart';

/// The website's top-level destinations: a bottom bar on phones, a rail on
/// tablets and desktops.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  final _navigators = List.generate(3, (_) => GlobalKey<NavigatorState>());

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    final destinations = [
      (Icons.category_outlined, Icons.category, t('navigation.catalog', 'Catalog')),
      (Icons.build_outlined, Icons.build, t('navigation.tools', 'Tools')),
      (Icons.settings_outlined, Icons.settings, t('navigation.settings', 'Settings')),
    ];
    final pages = [
      const _CatalogIndex(),
      const ImportScreen(),
      const SettingsScreen(),
    ];
    final body = IndexedStack(
      index: _index,
      children: [
        for (final (i, page) in pages.indexed)
          Navigator(key: _navigators[i], onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => page)),
      ],
    );
    void select(int index) {
      if (index == _index) {
        _navigators[index].currentState?.popUntil((route) => route.isFirst);
      } else {
        setState(() => _index = index);
      }
    }

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: select,
            destinations: [for (final (icon, selected, label) in destinations) NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label)],
          ),
        );
      }
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: select,
            labelType: NavigationRailLabelType.all,
            destinations: [for (final (icon, selected, label) in destinations) NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label))],
          ),
          Expanded(child: body),
        ]),
      );
    });
  }
}

/// The catalogue's sections, as the website's drawer lists them.
class _CatalogIndex extends StatelessWidget {
  const _CatalogIndex();

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    return Scaffold(
      appBar: AppBar(title: Text(t('navigation.catalog', 'Catalog'))),
      body: ListView(children: [
        for (final profile in catalogProfiles)
          ListTile(
            leading: Icon(profile.icon),
            title: Text(t(profile.label, profile.resource)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CatalogScreen(profile: profile))),
          ),
      ]),
    );
  }
}
