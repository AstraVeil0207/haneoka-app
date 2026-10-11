import 'package:flutter/material.dart';

/// A save's raw fields as an expandable tree, exactly as the game wrote them.
class JsonView extends StatelessWidget {
  const JsonView({super.key, required this.value});
  final Object? value;

  @override
  Widget build(BuildContext context) =>
      ListView(children: _children(context, value));

  static List<Widget> _children(BuildContext context, Object? value) =>
      switch (value) {
        Map() => [
          for (final entry in value.entries)
            _node(context, '${entry.key}', entry.value),
        ],
        List() => [
          for (final (index, item) in value.indexed)
            _node(context, '$index', item),
        ],
        _ => [ListTile(title: Text('$value'))],
      };

  static Widget _node(BuildContext context, String key, Object? value) {
    final theme = Theme.of(context);
    if (value is Map || value is List) {
      final size = value is Map ? value.length : (value as List).length;
      return ExpansionTile(
        title: Text(key),
        trailing: Text('$size', style: theme.textTheme.labelMedium),
        childrenPadding: const EdgeInsetsDirectional.only(start: 16),
        children: size == 0 ? const [] : _children(context, value),
      );
    }
    return ListTile(
      dense: true,
      title: Text(key),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: SelectableText(
          '$value',
          textAlign: TextAlign.end,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}
