import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'detail_screen.dart';
import 'format.dart';
import 'profiles.dart';

/// One catalogue resource as a searchable grid of tiles.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.profile});
  final CatalogProfile profile;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  Future<List<Map<String, Object?>>>? _items;
  String _query = '';
  bool _searching = false;
  late bool _newestFirst = widget.profile.newestFirst;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items ??= _load();
  }

  Future<List<Map<String, Object?>>> _load() async {
    final state = AppScope.of(context);
    final document = await state.api.catalog(widget.profile.resource);
    final source = widget.profile.document == null ? document : readPath(document, widget.profile.document!);
    return switch (source) {
      List() => source.whereType<Map<String, Object?>>().toList(),
      Map() => [
          for (final entry in source.entries)
            if (entry.value is Map<String, Object?>) {'_key': entry.key, ...entry.value as Map<String, Object?>},
        ],
      _ => <Map<String, Object?>>[],
    };
  }

  String _id(Map<String, Object?> item) => '${firstOf(item, widget.profile.id) ?? item['_key']}';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final profile = widget.profile;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: InputDecoration(hintText: t('common.actions.search', 'Search'), border: InputBorder.none),
                onChanged: (value) => setState(() => _query = value.toLowerCase()),
              )
            : Text(t(profile.label, profile.resource)),
        actions: [
          IconButton(
            tooltip: t('common.actions.search', 'Search'),
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
          ),
          IconButton(
            tooltip: t('common.actions.sort', 'Sort'),
            icon: Icon(_newestFirst ? Icons.arrow_downward : Icons.arrow_upward),
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(t('common.actions.retry', 'Retry')),
                onPressed: () => setState(() => _items = _load()),
              ),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final format = ValueFormat(t);
          var items = snapshot.data!.where((item) {
            if (_query.isEmpty) return true;
            return t.text(firstOf(item, profile.title)).toLowerCase().contains(_query) || _id(item).contains(_query);
          }).toList();
          items.sort((a, b) {
            final x = num.tryParse(_id(a)) ?? 0, y = num.tryParse(_id(b)) ?? 0;
            return _newestFirst ? y.compareTo(x) : x.compareTo(y);
          });
          final (extent, aspect) = switch (profile.layout) {
            TileLayout.wide => (360.0, 1.6),
            TileLayout.portrait => (180.0, 0.62),
            TileLayout.square => (180.0, 0.78),
          };
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: extent, childAspectRatio: aspect, mainAxisSpacing: 8, crossAxisSpacing: 8,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final image = firstOf(item, profile.image);
              final subtitle = profile.detail.map((key) => format.format(key, readPath(item, key))).firstWhere((s) => s.isNotEmpty, orElse: () => '');
              return Card.filled(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => DetailScreen(profile: profile, id: _id(item), summary: item),
                  )),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: image is String
                          ? CachedNetworkImage(
                              imageUrl: state.api.asset(image).toString(),
                              fit: profile.layout == TileLayout.wide ? BoxFit.cover : BoxFit.contain,
                              errorWidget: (_, _, _) => Icon(profile.icon),
                            )
                          : Icon(profile.icon, size: 40),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.text(firstOf(item, profile.title)), maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                        if (subtitle.isNotEmpty)
                          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
