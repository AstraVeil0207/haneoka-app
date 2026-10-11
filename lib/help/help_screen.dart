import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../shell/page.dart';
import '../ui/theme.dart';

List<Map> _values(Object? value) => switch (value) {
  Map() => value.values.whereType<Map>().toList(),
  List() => value.whereType<Map>().toList(),
  _ => <Map>[],
};

num _num(Object? value) => value is num ? value : 0;

/// The game's help (`help-workspace`): the manual by category, or the
/// loading tips; each topic opens in place.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  Future<Object?>? _data;
  String _mode = 'manual';
  int? _category;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= AppScope.of(context).api.catalog('help');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ShellPage(
      title: t('navigation.help', 'Help'),
      actions: [
        BarAction.choice(
          label: t('common.actions.view', 'View'),
          options: [
            BarChoice(
              icon: Symbols.menu_book_rounded,
              label: t('settings.labels.manual', 'Manual'),
              selected: _mode == 'manual',
              onSelected: () => setState(() => _mode = 'manual'),
            ),
            BarChoice(
              icon: Symbols.lightbulb_rounded,
              label: t('settings.labels.loadingTips', 'Loading tips'),
              selected: _mode == 'tips',
              onSelected: () => setState(() => _mode = 'tips'),
            ),
          ],
        ),
      ],
      body: FutureBuilder(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.tonal(
                onPressed: () =>
                    setState(() => _data = state.api.catalog('help')),
                child: Text(t('common.actions.retry', 'Retry')),
              ),
            );
          }
          final document = snapshot.data as Map?;
          if (document == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = _values(document['categories'])
            ..sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
          final tips = _values(document['loadingTips'])
            ..sort((a, b) => _num(a['tipId']).compareTo(_num(b['tipId'])));
          final category = categories.firstWhere(
            (c) => c['categoryId'] == _category,
            orElse: () => categories.isEmpty ? const {} : categories.first,
          );
          final entries = _mode == 'tips'
              ? tips
              : _values(category['subcategories']);
          final wide = MediaQuery.sizeOf(context).width > 760;

          Widget categoryButton(Map item) {
            final selected = identical(item, category);
            return Material(
              color: selected ? scheme.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(Corner.large),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(
                  () => _category = (item['categoryId'] as num?)?.toInt(),
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.topic_rounded,
                        size: 20,
                        color: selected ? scheme.onSecondaryContainer : null,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        fit: wide ? FlexFit.tight : FlexFit.loose,
                        child: Text(
                          t.text(item['title']).isEmpty
                              ? '—'
                              : t.text(item['title']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: selected
                                ? scheme.onSecondaryContainer
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_values(item['subcategories']).length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final list = ListView(
            key: ValueKey('$_mode:${category['categoryId']}'),
            padding: EdgeInsets.all(wide ? 16 : 12),
            children: [
              for (final (index, item) in entries.indexed)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: index == 0 && entries.length < 8,
                      shape: const Border(),
                      collapsedShape: const Border(),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        t.text(item['title']).isEmpty
                            ? '—'
                            : t.text(item['title']),
                        style: theme.textTheme.titleSmall,
                      ),
                      expandedAlignment: Alignment.centerLeft,
                      childrenPadding: EdgeInsets.fromLTRB(
                        wide ? 16 : 12,
                        0,
                        wide ? 48 : 12,
                        wide ? 20 : 16,
                      ),
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: SelectableText(
                            t.text(item['description']).replaceAll('\r', ''),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
          if (_mode == 'tips') return list;
          final rail = wide
              ? Container(
                  width: 260,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    border: Border(
                      right: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      for (final item in categories)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: categoryButton(item),
                        ),
                    ],
                  ),
                )
              : Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    border: Border(
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(8),
                    children: [
                      for (final item in categories)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: categoryButton(item),
                        ),
                    ],
                  ),
                );
          return Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              rail,
              Expanded(child: list),
            ],
          );
        },
      ),
    );
  }
}
