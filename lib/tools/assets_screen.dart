import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/audio.dart';
import '../core/net.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/tile.dart';

/// A port of the website's `lib/source-tree-search.ts`: the release's
/// source tree, where a file can exist once per language
/// (`kadan(zh-Hans).png`).
const _variantMarks = {'en', 'ko', 'zh-Hans', 'zh-Hant', 'zh-CN', 'zh-TW'};

({String base, String mark, String ext})? _variant(String file) {
  final match = RegExp(r'\(([^)]+)\)(\.[^.]+)$').firstMatch(file);
  final mark = match?[1] ?? '';
  return match != null && _variantMarks.contains(mark)
      ? (base: file.substring(0, match.start), mark: mark, ext: match[2] ?? '')
      : null;
}

/// `localizedFallbacks`: the reading language first, then ja, en, zh, ko.
List<String> _languages(String locale) => switch (locale) {
  'zh-CN' => ['zh-CN', 'zh-Hans', 'zh-TW', 'zh-Hant', 'ja', 'en', 'ko'],
  'zh-TW' => ['zh-TW', 'zh-Hant', 'ja', 'en', 'zh-CN', 'ko'],
  _ => {locale, 'ja', 'en', 'zh-TW', 'zh-CN', 'ko'}.toList(),
};

typedef _Entry = ({String name, String label, Object? value});

/// One entry per logical file: a source with variants lists once under its
/// own name; a file only in variants lists under the plain name
/// (`sourceEntries`).
List<_Entry> _entries(Map node, List<String> languages) {
  final names = node.keys.map((k) => '$k').toList();
  final plain = {
    for (final n in names)
      if (_variant(n) == null) n,
  };
  final orphans = <String, List<String>>{};
  for (final name in names) {
    final v = _variant(name);
    if (v == null) continue;
    final base = '${v.base}${v.ext}';
    if (plain.contains(base)) continue;
    (orphans[base] ??= []).add(name);
  }
  final entries = <_Entry>[
    for (final name in plain) (name: name, label: name, value: node[name]),
  ];
  for (final MapEntry(key: base, value: group) in orphans.entries) {
    final selected =
        languages
            .map((l) => group.where((n) => _variant(n)?.mark == l).firstOrNull)
            .whereType<String>()
            .firstOrNull ??
        group.first;
    entries.add((name: selected, label: base, value: node[selected]));
  }
  int natural(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  return entries..sort((a, b) => natural(a.label, b.label));
}

/// The release's source files (`asset-explorer`): folders, a file's
/// decoded outputs, and each output's preview.
class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key, this.path = const []});
  final List<String> path;
  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

Future<Map>? _tree;

class _AssetsScreenState extends State<AssetsScreen> {
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tree ??= AppScope.of(context).api
        .catalog('sources/tree')
        .then((v) => v as Map);
  }

  Object? _node(Map tree, List<String> parts) {
    Object? current = tree;
    for (final part in parts) {
      if (current is! Map) return null;
      current = current[part];
    }
    return current;
  }

  void _open(List<String> parts, Object? value) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => value is Map
          ? AssetsScreen(path: parts)
          : _SourceScreen(parts: parts),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final languages = _languages(t.locale);
    final theme = Theme.of(context);
    return ShellPage(
      title: widget.path.isEmpty
          ? t('navigation.assets', 'Assets')
          : widget.path.last,
      search: ShellSearch(
        label: t('common.actions.search', 'Search'),
        onChanged: (value) =>
            setState(() => _query = value.trim().toLowerCase()),
      ),
      body: FutureBuilder(
        future: _tree,
        builder: (context, snapshot) {
          final tree = snapshot.data;
          if (tree == null) {
            return Center(
              child: snapshot.hasError
                  ? FilledButton.tonal(
                      onPressed: () => setState(() => _tree = null),
                      child: Text(t('common.actions.retry', 'Retry')),
                    )
                  : const CircularProgressIndicator(),
            );
          }
          final node = _node(tree, widget.path);
          if (node is! Map) return const SizedBox.shrink();
          // Search: every source below this folder whose path matches.
          if (_query.isNotEmpty) {
            final hits = <(List<String>, String)>[];
            void walk(Map folder, List<String> parts) {
              for (final entry in _entries(folder, languages)) {
                if (hits.length >= 300) return;
                final next = [...parts, entry.name];
                if (entry.value is Map) {
                  walk(entry.value! as Map, next);
                } else {
                  final label = [...parts, entry.label].join('/');
                  if (label.toLowerCase().contains(_query))
                    hits.add((next, label));
                }
              }
            }

            walk(node, widget.path);
            return ListView.builder(
              padding: pagePadding(context),
              itemCount: hits.length,
              itemBuilder: (context, index) {
                final (parts, label) = hits[index];
                return ListTile(
                  leading: const Icon(Symbols.description_rounded),
                  title: Text(label.split('/').last),
                  subtitle: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _open(parts, 1),
                );
              },
            );
          }
          final entries = _entries(node, languages);
          return ListView.separated(
            padding: pagePadding(context),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final folder = entry.value is Map;
              return ListTile(
                leading: Icon(
                  folder ? Symbols.folder_rounded : Symbols.description_rounded,
                ),
                title: Text(entry.label),
                trailing: folder
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(entry.value! as Map).length}',
                            style: theme.textTheme.labelSmall,
                          ),
                          const Icon(Symbols.chevron_right_rounded),
                        ],
                      )
                    : null,
                onTap: () => _open([...widget.path, entry.name], entry.value),
              );
            },
          );
        },
      ),
    );
  }
}

/// One source file: its decoded outputs, each previewed in place.
class _SourceScreen extends StatefulWidget {
  const _SourceScreen({required this.parts});
  final List<String> parts;
  @override
  State<_SourceScreen> createState() => _SourceScreenState();
}

class _SourceScreenState extends State<_SourceScreen> {
  Future<List<String>>? _files;
  String? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _files ??= AppScope.of(context).api
        .catalog('sources/${widget.parts.join('/')}')
        .then((value) {
          final descriptor = (value as Map?) ?? const {};
          return [
            for (final output in descriptor['outputs'] as List? ?? const [])
              if (output is Map && '${output['path'] ?? ''}'.isNotEmpty)
                '${output['path']}',
            if ((descriptor['objectArchive'] as Map?)?['path']
                case final String path)
              path,
          ];
        });
  }

  String _url(String file) {
    final server = AppScope.of(context).server;
    final [root, ...parts] = file
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList();
    return const {'assets', 'runtime', 'objects'}.contains(root)
        ? 'https://haneoka.org/$root/$server/${parts.map(Uri.encodeComponent).join('/')}'
        : '';
  }

  static String _kind(String file) {
    final ext = file.split('.').last.toLowerCase();
    if (const {'png', 'jpg', 'jpeg', 'webp', 'gif', 'svg'}.contains(ext))
      return 'image';
    if (const {'mp3', 'wav', 'ogg', 'm4a'}.contains(ext)) return 'audio';
    if (const {'mp4', 'webm'}.contains(ext)) return 'video';
    if (const {'json', 'txt', 'xml', 'csv', 'md', 'atlas'}.contains(ext))
      return 'text';
    return 'binary';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    return ShellPage(
      title: widget.parts.last,
      body: FutureBuilder(
        future: _files,
        builder: (context, snapshot) {
          final files = snapshot.data;
          if (files == null) {
            return Center(
              child: snapshot.hasError
                  ? Text(t('common.states.unavailable', 'Unavailable'))
                  : const CircularProgressIndicator(),
            );
          }
          final selected = _selected ?? files.firstOrNull;
          return ListView(
            padding: pagePadding(context),
            children: [
              if (selected != null)
                _Preview(
                  url: _url(selected),
                  kind: _kind(selected),
                  name: selected.split('/').last,
                ),
              const SizedBox(height: 16),
              for (final file in files)
                ListTile(
                  selected: file == selected,
                  leading: Icon(switch (_kind(file)) {
                    'image' => Symbols.image_rounded,
                    'audio' => Symbols.music_note_rounded,
                    'video' => Symbols.movie_rounded,
                    'text' => Symbols.article_rounded,
                    _ => Symbols.draft_rounded,
                  }),
                  title: Text(file.split('/').last),
                  subtitle: Text(
                    file,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: t('common.actions.download', 'Download'),
                    onPressed: _url(file).isEmpty
                        ? null
                        : () => launchUrl(
                            Uri.parse(_url(file)),
                            mode: LaunchMode.externalApplication,
                          ),
                    icon: const Icon(Symbols.download_rounded),
                  ),
                  onTap: () => setState(() => _selected = file),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.url, required this.kind, required this.name});
  final String url;
  final String kind;
  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final audio = AppScope.of(context).audio;
    if (url.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minHeight: 160, maxHeight: 420),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: switch (kind) {
        'image' => AppImage(
          candidates: [url],
          fit: BoxFit.contain,
          localized: false,
        ),
        'audio' || 'video' => ListenableBuilder(
          listenable: audio,
          builder: (context, _) {
            final track = Track(id: url, url: url, title: name);
            final playing = audio.isPlaying(url);
            return IconButton.filledTonal(
              iconSize: 40,
              onPressed: () => audio.toggle(track),
              icon: Icon(
                playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
              ),
            );
          },
        ),
        'text' => FutureBuilder(
          future: netClient.get(Uri.parse(url)),
          builder: (context, snapshot) => SingleChildScrollView(
            child: SelectableText(
              snapshot.data == null
                  ? ''
                  : utf8
                        .decode(snapshot.data!.bodyBytes, allowMalformed: true)
                        .characters
                        .take(200000)
                        .toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        _ => Icon(
          Symbols.draft_rounded,
          size: 48,
          color: scheme.onSurfaceVariant,
        ),
      },
    );
  }
}
