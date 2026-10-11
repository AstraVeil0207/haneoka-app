import 'package:flutter/material.dart';

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

/// Every page: the shell's title bar above a rounded content pane, as on the
/// website. The bar carries Back or the navigation menu, the title, marks
/// after the title and the page's actions; nothing else draws a bar.
class ShellPage extends StatelessWidget {
  const ShellPage({
    super.key,
    required this.title,
    required this.body,
    this.titleLanguage,
    this.marks,
    this.actions = const [],
    this.search,
  });
  final String title;
  final String? titleLanguage;
  final Widget? marks;
  final List<Widget> actions;

  /// A search field the bar shows as a pill on wide windows and an icon on compact ones.
  final ShellSearch? search;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final compact = shell?.compact ?? false;
    final canPop = Navigator.of(context).canPop();
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: ShellMetrics.topBar,
            child: Row(
              children: [
                const SizedBox(width: 4),
                if (canPop)
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  )
                else if (compact)
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .openAppDrawerTooltip,
                    onPressed: shell!.openNavigation,
                    icon: const Icon(Icons.menu),
                  ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (marks != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: marks!,
                    ),
                  ),
                const Spacer(),
                if (search != null)
                  _SearchPill(search: search!, compact: compact),
                ...actions,
                SizedBox(width: compact ? 4 : ShellMetrics.paneGap),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                0,
                compact ? 0 : ShellMetrics.paneGap,
                compact ? 0 : ShellMetrics.paneGap,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  compact ? 0 : Corner.extraLarge,
                ),
                child: Material(color: theme.colorScheme.surface, child: body),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShellSearch {
  const ShellSearch({required this.label, required this.onChanged});
  final String label;
  final ValueChanged<String> onChanged;
}

class _SearchPill extends StatefulWidget {
  const _SearchPill({required this.search, required this.compact});
  final ShellSearch search;
  final bool compact;
  @override
  State<_SearchPill> createState() => _SearchPillState();
}

class _SearchPillState extends State<_SearchPill> {
  bool _open = false;
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    if (widget.compact && !_open) {
      return IconButton(
        tooltip: widget.search.label,
        onPressed: () => setState(() => _open = true),
        icon: const Icon(Icons.search),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        width: widget.compact ? 220 : 320,
        child: SearchBar(
          controller: _controller,
          autoFocus: widget.compact,
          hintText: widget.search.label,
          leading: const Icon(Icons.search),
          trailing: [
            if (widget.compact || _controller.text.isNotEmpty)
              IconButton(
                onPressed: () => setState(() {
                  _controller.clear();
                  widget.search.onChanged('');
                  _open = false;
                }),
                icon: const Icon(Icons.close),
              ),
          ],
          onChanged: (value) {
            setState(() {});
            widget.search.onChanged(value);
          },
        ),
      ),
    );
  }
}
