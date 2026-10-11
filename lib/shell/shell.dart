import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../ui/player.dart';
import '../ui/theme.dart';
import 'navigation.dart';
import 'page.dart';
import 'routes.dart';

/// The website's shell: an expanded drawer on wide windows, a rail on medium
/// ones, a modal drawer on phones; the page's bar and pane beside it.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  String _route = const String.fromEnvironment(
    'HANEOKA_ROUTE',
    defaultValue: '/',
  );

  void _navigate(String route) {
    setState(() => _route = route);
    _scaffold.currentState?.closeDrawer();
  }

  NavDestination? get _destination {
    bool contains(List<NavItem> items) =>
        items.any((item) => item.route == _route || contains(item.children));
    for (final destination in navDestinations) {
      if (destination.route == _route) return destination;
      if (destination.sections.any((s) => contains(s.items))) {
        return destination;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    final label = allNavItems
        .where((item) => item.route == _route)
        .map((item) => item.label)
        .firstOrNull;
    final page = Navigator(
      key: ValueKey(_route),
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) =>
            screenFor(_route, navigate: _navigate) ??
            PendingScreen(label: label ?? _route),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < ShellMetrics.compact;
        final destination = _destination;
        Widget drawer(bool modal) => _Drawer(
          route: _route,
          current: destination,
          modal: modal,
          onNavigate: _navigate,
          onClose: () => _scaffold.currentState?.closeDrawer(),
        );
        final body = ShellScope(
          compact: compact,
          openNavigation: () => _scaffold.currentState?.openDrawer(),
          navigate: _navigate,
          child: page,
        );
        if (compact) {
          return Scaffold(
            key: _scaffold,
            drawer: Drawer(
              width: ShellMetrics.drawer + 40,
              child: drawer(true),
            ),
            body: SafeArea(child: body),
          );
        }
        if (width < ShellMetrics.expanded) {
          return Scaffold(
            key: _scaffold,
            drawer: Drawer(
              width: ShellMetrics.drawer + 40,
              child: drawer(true),
            ),
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: destination == null
                      ? null
                      : navDestinations.indexOf(destination),
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .openAppDrawerTooltip,
                      onPressed: () => _scaffold.currentState?.openDrawer(),
                      icon: const Icon(Symbols.menu_rounded),
                    ),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const NowPlaying(),
                            for (final item in utilityItems)
                              IconButton(
                                tooltip: t(item.label),
                                isSelected: _route == item.route,
                                onPressed: () => _navigate(item.route),
                                icon: Icon(item.icon),
                                selectedIcon: Icon(item.icon, fill: 1),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  onDestinationSelected: (index) =>
                      _navigate(navDestinations[index].route),
                  destinations: [
                    for (final d in navDestinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.icon, fill: 1),
                        label: Text(t(d.label)),
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
              SizedBox(width: ShellMetrics.drawer, child: drawer(false)),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}

/// The website's drawer (`.nav`): brand, then each destination as a header
/// that opens its page and its tree, the current one open; Account,
/// Settings and About at the foot.
class _Drawer extends StatefulWidget {
  const _Drawer({
    required this.route,
    required this.current,
    required this.modal,
    required this.onNavigate,
    required this.onClose,
  });
  final String route;
  final NavDestination? current;
  final bool modal;
  final ValueChanged<String> onNavigate;
  final VoidCallback onClose;

  @override
  State<_Drawer> createState() => _DrawerState();
}

class _DrawerState extends State<_Drawer> {
  late final Set<String> _open = {?widget.current?.id};

  /// Collapsible sections (the archive mirrors) the reader opened.
  final Set<String> _expanded = {};

  @override
  void didUpdateWidget(_Drawer old) {
    super.didUpdateWidget(old);
    if (widget.current != null) _open.add(widget.current!.id);
  }

  void _toggle(Set<String> set, String id) =>
      setState(() => set.contains(id) ? set.remove(id) : set.add(id));

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget row({
      required String label,
      IconData? icon,
      required bool active,
      required VoidCallback onTap,
      double indent = 0,
      double height = 56,
      Widget? trailing,
      TextStyle? style,
    }) => Padding(
      padding: EdgeInsets.fromLTRB(16 + indent, 0, 12, 0),
      child: Material(
        color: active ? scheme.secondaryContainer : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                const SizedBox(width: 16),
                if (icon != null) ...[
                  Icon(
                    icon,
                    fill: active ? 1 : 0,
                    color: active
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (style ?? theme.textTheme.labelLarge)?.copyWith(
                      color: active
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ?trailing,
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );

    List<Widget> items(List<NavItem> list, double indent) => [
      for (final item in list) ...[
        row(
          label: t(item.label),
          icon: item.icon,
          active: item.route == widget.route,
          onTap: () => widget.onNavigate(item.route),
          indent: indent,
          height: 50,
        ),
        ...items(item.children, indent + 16),
      ],
    ];

    Icon chevron(bool open) => Icon(
      open
          ? Symbols.keyboard_arrow_up_rounded
          : Symbols.keyboard_arrow_down_rounded,
      color: scheme.onSurfaceVariant,
    );

    return ColoredBox(
      color: scheme.surfaceContainer,
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: ShellMetrics.topBar,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  if (widget.modal)
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: widget.onClose,
                      icon: const Icon(Symbols.menu_open_rounded),
                    )
                  else
                    const SizedBox(width: 8),
                  const SizedBox(width: 4),
                  Image.asset(
                    'assets/brand/android-chrome-512x512.png',
                    width: 32,
                    height: 32,
                  ),
                  const SizedBox(width: 12),
                  Text('haneoka', style: theme.textTheme.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final destination in navDestinations) ...[
                    row(
                      label: t(destination.label),
                      icon: destination.icon,
                      active: widget.current?.id == destination.id,
                      onTap: () {
                        setState(() => _open.add(destination.id));
                        widget.onNavigate(destination.route);
                      },
                      trailing: destination.sections.isEmpty
                          ? null
                          : InkResponse(
                              onTap: () => _toggle(_open, destination.id),
                              child: chevron(_open.contains(destination.id)),
                            ),
                    ),
                    if (_open.contains(destination.id))
                      for (final section in destination.sections) ...[
                        if (section.collapsible)
                          row(
                            label: t(section.label),
                            active: false,
                            onTap: () => _toggle(_expanded, section.id),
                            indent: 16,
                            height: 48,
                            style: theme.textTheme.titleSmall,
                            trailing: chevron(_expanded.contains(section.id)),
                          )
                        else if (destination.sections.length > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(48, 12, 12, 8),
                            child: Text(
                              t(section.label),
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        if (!section.collapsible ||
                            _expanded.contains(section.id))
                          ...items(section.items, 16),
                      ],
                  ],
                ],
              ),
            ),
            const NowPlaying(expanded: true),
            for (final item in utilityItems)
              row(
                label: t(item.label),
                icon: item.icon,
                active: widget.route == item.route,
                onTap: () => widget.onNavigate(item.route),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
