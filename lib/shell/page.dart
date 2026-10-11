import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../ui/player.dart';
import '../ui/theme.dart';

/// Lets a page open the shell's navigation on compact windows.
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.openNavigation,
    required this.compact,
    required super.child,
  });
  final VoidCallback openNavigation;
  final bool compact;
  static ShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();
  @override
  bool updateShouldNotify(ShellScope old) => old.compact != compact;
}

/// One control in the title bar. It draws as an icon button while it fits and
/// as a menu entry behind ⋮ when it does not (`app-bar-overflow.ts`).
class BarAction {
  const BarAction({
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected,
    this.badge = 0,
    this.tonal = false,
  }) : options = const [];

  /// A segmented choice (view switch): one checkable menu entry per option.
  const BarAction.choice({required this.label, required this.options})
    : icon = Symbols.tune_rounded,
      onPressed = null,
      selected = null,
      badge = 0,
      tonal = false;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// A toggle's state; null for a plain action.
  final bool? selected;
  final int badge;
  final bool tonal;
  final List<BarChoice> options;

  int get slots => options.isEmpty ? 1 : options.length;
}

class BarChoice {
  const BarChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onSelected;
}

/// Every page: the shell's title bar above the content pane, as on the
/// website. The bar carries Back or the navigation menu, the title, marks
/// after the title, the search and the page's actions; nothing else draws a
/// bar. On compact windows bar and page are one surface, and the bar takes
/// surface-container once the page scrolls under it.
class ShellPage extends StatefulWidget {
  const ShellPage({
    super.key,
    required this.title,
    required this.body,
    this.titleLanguage,
    this.marks,
    this.status,
    this.actions = const [],
    this.search,
  });
  final String title;
  final Locale? titleLanguage;

  /// Identity after the title: rarity, band, applied-filter chips.
  final Widget? marks;

  /// A live count or state before the actions; never overflows.
  final Widget? status;
  final List<BarAction> actions;
  final ShellSearch? search;
  final Widget body;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  bool _scrolled = false;
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      final scrolled = notification.metrics.pixels > 2;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final compact = shell?.compact ?? false;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final barColor = compact
        ? (_scrolled ? scheme.surfaceContainer : scheme.surface)
        : scheme.surfaceContainer;
    final pane = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Material(color: scheme.surface, child: widget.body),
    );
    return Material(
      color: compact ? scheme.surface : scheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: barColor,
            height: ShellMetrics.topBar,
            padding: EdgeInsets.only(
              left: 4,
              right: compact ? 4 : ShellMetrics.paneGap,
            ),
            child: Stack(
              children: [
                ListenableBuilder(
                  listenable:
                      AppScope.maybeOf(context)?.audio ?? const _Silent(),
                  builder: (context, _) => _bar(context, compact),
                ),
                if (compact && _searching && widget.search != null)
                  Positioned.fill(child: _compactSearch(context)),
              ],
            ),
          ),
          Expanded(
            child: compact
                ? pane
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                      0,
                      0,
                      ShellMetrics.paneGap,
                      ShellMetrics.paneGap,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Corner.extraLarge),
                      child: pane,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, bool compact) {
    final shell = ShellScope.of(context);
    final theme = Theme.of(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final leading = canPop
        ? const BackButton()
        : compact && shell != null
        ? IconButton(
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            onPressed: shell.openNavigation,
            icon: const Icon(Symbols.menu_rounded),
          )
        : null;
    // The title keeps up to 160 dp before actions start to overflow
    // (`TITLE_MAX_RESERVED`); everything else belongs to the actions.
    return LayoutBuilder(
      builder: (context, constraints) {
        final lead = leading == null ? 12.0 : 52.0;
        final title = (TextPainter(
          text: TextSpan(text: widget.title, style: theme.textTheme.titleLarge),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout()).width;
        final budget = (constraints.maxWidth - lead - title.clamp(0, 160))
            .clamp(48.0, constraints.maxWidth);
        return Row(
          children: [
            ?leading,
            SizedBox(width: leading == null ? 12 : 4),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.title,
                      locale: widget.titleLanguage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  if (widget.marks != null)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: widget.marks!,
                      ),
                    ),
                ],
              ),
            ),
            _trailing(context, compact, budget),
          ],
        );
      },
    );
  }

  /// Search, status, then as many actions as fit; the rest behind ⋮.
  Widget _trailing(BuildContext context, bool compact, double width) {
    final search = widget.search;
    final children = <Widget>[];
    var room = width;
    if (compact && AppScope.maybeOf(context)?.audio.current != null) {
      children.add(const NowPlaying());
      room -= 48;
    }
    if (search != null) {
      if (compact) {
        children.add(
          IconButton(
            tooltip: search.label,
            onPressed: () => setState(() => _searching = true),
            icon: const Icon(Symbols.search_rounded),
          ),
        );
        room -= 48;
      } else {
        final pill = (room * 0.5).clamp(160.0, 360.0);
        children.add(
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(width: pill, child: _searchBar(search, false)),
          ),
        );
        room -= pill + 8;
      }
    }
    if (widget.status != null) {
      children.add(widget.status!);
      room -= 56;
    }
    final actions = widget.actions;
    var shown = actions.length;
    int slots(int n) => actions.take(n).fold(0, (sum, a) => sum + a.slots);
    while (shown > 0 &&
        slots(shown) * 48 > room - (shown < actions.length ? 48 : 0)) {
      shown--;
    }
    if (slots(shown) * 48 > room) shown = 0;
    for (final action in actions.take(shown)) {
      children.addAll(_buttons(action));
    }
    if (shown < actions.length) {
      children.add(_overflow(context, actions.skip(shown).toList()));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  List<Widget> _buttons(BarAction action) {
    if (action.options.isNotEmpty) {
      return [
        for (final option in action.options)
          IconButton(
            tooltip: option.label,
            isSelected: option.selected,
            onPressed: option.onSelected,
            icon: Icon(option.icon),
          ),
      ];
    }
    Widget icon = Icon(action.icon);
    if (action.badge > 0) {
      icon = Badge.count(count: action.badge, child: icon);
    }
    return [
      if (action.tonal)
        IconButton.filledTonal(
          tooltip: action.label,
          onPressed: action.onPressed,
          icon: icon,
        )
      else
        IconButton(
          tooltip: action.label,
          isSelected: action.selected,
          onPressed: action.onPressed,
          icon: icon,
        ),
    ];
  }

  Widget _overflow(BuildContext context, List<BarAction> hidden) {
    return MenuAnchor(
      menuChildren: [
        for (final action in hidden)
          if (action.options.isEmpty)
            MenuItemButton(
              leadingIcon: Icon(action.icon),
              trailingIcon: action.selected == true
                  ? const Icon(Symbols.check_rounded, size: 20)
                  : null,
              onPressed: action.onPressed,
              child: Text(action.label),
            )
          else
            for (final option in action.options)
              MenuItemButton(
                leadingIcon: Icon(option.icon),
                trailingIcon: option.selected
                    ? const Icon(Symbols.check_rounded, size: 20)
                    : null,
                onPressed: option.onSelected,
                child: Text(option.label),
              ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: MaterialLocalizations.of(context).showMenuTooltip,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Symbols.more_vert_rounded),
      ),
    );
  }

  Widget _searchBar(ShellSearch search, bool compact) => SearchBar(
    controller: _searchController,
    autoFocus: compact,
    hintText: search.label,
    leading: const Icon(Symbols.search_rounded),
    trailing: [
      if (compact || _searchController.text.isNotEmpty)
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => setState(() {
            _searchController.clear();
            search.onChanged('');
            _searching = false;
          }),
          icon: const Icon(Symbols.close_rounded),
        ),
    ],
    onChanged: (value) {
      setState(() {});
      search.onChanged(value);
    },
  );

  /// On compact windows the field grows out of the search icon it replaces.
  Widget _compactSearch(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOutCubic,
    builder: (context, t, child) =>
        ClipPath(clipper: _RevealFromEnd(t), child: child),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _searchBar(widget.search!, true),
    ),
  );
}

class _RevealFromEnd extends CustomClipper<Path> {
  _RevealFromEnd(this.t);
  final double t;
  @override
  Path getClip(Size size) {
    final left = (size.width - 48) * (1 - t);
    return Path()..addRRect(
      RRect.fromLTRBR(
        left,
        0,
        size.width,
        size.height,
        const Radius.circular(28),
      ),
    );
  }

  @override
  bool shouldReclip(_RevealFromEnd old) => old.t != t;
}

class ShellSearch {
  const ShellSearch({required this.label, required this.onChanged});
  final String label;
  final ValueChanged<String> onChanged;
}

/// A listenable that never changes, for pages shown without the app's state.
class _Silent implements Listenable {
  const _Silent();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
