import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'format.dart';
import 'profiles.dart';

/// One entity: its artwork, the profile's key facts, then every other field.
class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.profile, required this.id, required this.summary});
  final CatalogProfile profile;
  final String id;
  final Map<String, Object?> summary;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final detail = state.api.catalog(profile.resource, id).then<Map<String, Object?>>(
          (value) => {...summary, if (value is Map<String, Object?>) ...value},
          onError: (_) => summary,
        );
    return Scaffold(
      appBar: AppBar(title: Text(t.text(firstOf(summary, profile.title)))),
      body: FutureBuilder(
        future: detail,
        builder: (context, snapshot) {
          final record = snapshot.data ?? summary;
          final format = ValueFormat(t);
          final images = imagesIn(record).toSet().toList();
          final theme = Theme.of(context);
          final keys = [
            ...profile.detail.where((key) => readPath(record, key) != null),
            ...record.keys.where((key) => !key.startsWith('_') && !profile.detail.contains(key)),
          ];
          final scalars = [for (final key in keys) if (ValueFormat.isScalar(readPath(record, key))) key];
          final nested = [for (final key in keys) if (!ValueFormat.isScalar(readPath(record, key)) && readPath(record, key) != null) key];
          return ListView(children: [
            if (images.isNotEmpty)
              SizedBox(
                height: 280,
                child: PageView(children: [
                  for (final image in images)
                    CachedNetworkImage(
                      imageUrl: state.api.asset(image).toString(),
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                ]),
              ),
            if (snapshot.connectionState != ConnectionState.done) const LinearProgressIndicator(),
            for (final key in scalars)
              if (format.format(key, readPath(record, key)) case final value when value.isNotEmpty && !value.startsWith('/assets/'))
                ListTile(
                  dense: true,
                  title: Text(_label(t, key), style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  subtitle: SelectableText(value, style: theme.textTheme.bodyLarge),
                ),
            for (final key in nested)
              ExpansionTile(
                title: Text(_label(t, key)),
                children: [_Nested(value: readPath(record, key), format: format)],
              ),
          ]);
        },
      ),
    );
  }

  /// The website's field label when it has one, else the field name.
  static String _label(dynamic t, String key) {
    for (final path in ['catalog.fields.$key', 'catalog.songs.fields.$key', 'catalog.cards.fields.$key', 'catalog.characters.fields.$key', 'common.fields.$key']) {
      final label = t(path, '') as String;
      if (label.isNotEmpty) return label;
    }
    return key;
  }
}

class _Nested extends StatelessWidget {
  const _Nested({required this.value, required this.format});
  final Object? value;
  final ValueFormat format;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value is Map) {
      return Column(children: [
        for (final entry in value.entries)
          if (ValueFormat.isScalar(entry.value))
            ListTile(dense: true, title: Text('${entry.key}'), trailing: Text(format.format('${entry.key}', entry.value)))
          else if (entry.value != null)
            ExpansionTile(title: Text('${entry.key}'), children: [_Nested(value: entry.value, format: format)]),
      ]);
    }
    if (value is List) {
      return Column(children: [
        for (final (index, item) in value.take(200).indexed)
          ValueFormat.isScalar(item)
              ? ListTile(dense: true, title: Text(format.format('', item)))
              : ExpansionTile(title: Text('${index + 1}'), children: [_Nested(value: item, format: format)]),
      ]);
    }
    return ListTile(dense: true, title: Text(format.format('', value)));
  }
}
