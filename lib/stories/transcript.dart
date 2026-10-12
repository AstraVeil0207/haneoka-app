import '../catalog/visuals.dart';
import '../core/i18n.dart';

class TranscriptEntry {
  const TranscriptEntry(
    this.kind,
    this.command,
    this.index,
    this.voices, {
    this.source,
    this.mediaKind,
  });
  final String kind;
  final Entry command;
  final int index;
  final List<Entry> voices;
  final String? source;
  final String? mediaKind;
  bool get dialogue => const {'dialogue', 'message', 'subtitle'}.contains(kind);
}

List<Entry> _records(Object? value) => [
  for (final row
      in value is Map
          ? value.values
          : value is List
          ? value
          : const [])
    if (row is Map) row.cast<String, Object?>(),
];
String _url(Map value) =>
    [
      value['playableUrl'],
      value['url'],
      value['src'],
      value['thumbnail'],
    ].whereType<String>().where((url) => url.isNotEmpty).firstOrNull ??
    '';

/// Dart projection of the website's projectHaneokaTranscript, including timed
/// command groups and timeline signals. Speaker identity never gates text.
List<TranscriptEntry> projectTranscript(Map payload) {
  final assets = payload['assets'] as Map? ?? const {};
  Map<String, Entry> registry(String collection) => {
    for (final entry
        in assets[collection] is Map
            ? [
                for (final row in (assets[collection] as Map).entries)
                  if (row.value is Map)
                    {
                      'ref': row.key,
                      ...(row.value as Map).cast<String, Object?>(),
                    },
              ]
            : _records(assets[collection]))
      for (final ref in [
        entry['ref'],
        entry['resourceRef'],
        entry['id'],
        entry['assetId'],
        entry['assetName'],
        entry['stageRef'],
        entry['soundId'],
        entry['originalId'],
        entry['videoId'],
        entry['cueName'],
        entry['cueSheetName'],
        entry['runtimePath'],
        entry['sourcePath'],
        entry['url'],
        if (entry['cueSheetName'] != null && entry['cueName'] != null)
          '${entry['cueSheetName']}/${entry['cueName']}',
      ])
        if (ref != null && '$ref'.isNotEmpty) '$ref': entry,
  };
  final sounds = registry('sounds');
  final media = {
    'background': registry('backgrounds'),
    'still': registry('stills'),
    'video': registry('videos'),
    'stamp': registry('stamps'),
  };
  final entries = <TranscriptEntry>[];
  final stills = <String>{};
  String conversation = '';
  bool hasText(Object? value) => value is String
      ? value.trim().isNotEmpty
      : value is Iterable
      ? value.any(hasText)
      : value is Map
      ? value.values.any(hasText)
      : false;
  void append(Entry command, int index, int depth) {
    if (depth > 64) {
      throw const FormatException('Story command nesting is too deep');
    }
    final opcode = command['command'];
    if (opcode == 101 || command['type'] == 'commandGroup') {
      final group = command['commandGroup'] as Map? ?? const {};
      final actions = _records(group['actions']).indexed.toList()
        ..sort((a, b) {
          final order = ((a.$2['atSeconds'] as num?) ?? 0).compareTo(
            (b.$2['atSeconds'] as num?) ?? 0,
          );
          return order == 0 ? a.$1.compareTo(b.$1) : order;
        });
      for (final action in actions) {
        if (action.$2['command'] case final Map inner) {
          append(inner.cast<String, Object?>(), index, depth + 1);
        }
      }
      return;
    }
    if (opcode == 45 || command['type'] == 'timeline') {
      for (final signal in _records(
        (command['timeline'] as Map?)?['signals'],
      )) {
        if (signal['episode'] case final Map inner) {
          append(inner.cast<String, Object?>(), index, depth + 1);
        }
      }
      return;
    }
    final voices = _records(command['voices']);
    if (voices.isEmpty) {
      for (final ref in command['voiceRefs'] as List? ?? const []) {
        if (sounds['$ref'] case final voice?) voices.add(voice);
      }
    }
    final kind = switch (opcode) {
      2 => 'dialogue',
      20 => 'location',
      25 => 'image',
      26 || 27 => 'video',
      28 => 'subtitle',
      30 => 'image',
      36 => 'conversation',
      37 => 'message',
      38 => 'stamp',
      41 => 'choices',
      52 => 'voice',
      _ => switch (command['type']) {
        'talk' => 'dialogue',
        'chatTalk' => 'message',
        'background' || 'still' => 'image',
        'movie' || 'clip' => 'video',
        'chatWindow' => 'conversation',
        'chatStamp' => 'stamp',
        'choiceShow' => 'choices',
        'location' || 'subtitle' || 'voice' => '${command['type']}',
        _ => '',
      },
    };
    if (kind.isEmpty) return;
    if (const {'dialogue', 'message', 'location', 'subtitle'}.contains(kind) &&
        !hasText(command['text'])) {
      return;
    }
    if (kind == 'voice' && voices.isEmpty) return;
    if (kind == 'choices' &&
        (command['choices'] as List? ?? const []).isEmpty) {
      return;
    }
    if (kind == 'conversation') {
      final params = command['params'] as List? ?? const [];
      final key =
          '${command['targetAssetName'] ?? command['targetName'] ?? command['chatWindowAssetName'] ?? command['targetChatID'] ?? ''}';
      final memory =
          '${command['chatMemoryId'] ?? params.elementAtOrNull(2) ?? command['targetChatID'] ?? command['targetName'] ?? key}';
      final identity = '$key:$memory:${params.elementAtOrNull(1) ?? 0}';
      if (conversation == identity) {
        conversation = '';
        return;
      }
      conversation = identity;
    }
    String? source;
    String? mediaKind;
    if (const {'image', 'video', 'stamp'}.contains(kind)) {
      final field = kind == 'image'
          ? (opcode == 30 || command['type'] == 'still'
                ? 'still'
                : 'background')
          : kind;
      mediaKind = field == 'background' || field == 'still' ? field : null;
      final direct = command[field] as Map? ?? const {};
      final entry = _url(direct).isNotEmpty
          ? direct
          : media[field]?['${command['${field}Ref'] ?? command['targetAssetName'] ?? ''}'] ??
                direct;
      source = _url(entry);
      if (source.isEmpty && kind != 'stamp') return;
      if (field == 'still') {
        if (!stills.add(source)) {
          stills.remove(source);
          return;
        }
      }
    }
    entries.add(
      TranscriptEntry(
        kind,
        command,
        index,
        voices,
        source: source,
        mediaKind: mediaKind,
      ),
    );
  }

  final commands = _records(payload['commands']);
  for (final (index, command) in commands.indexed) {
    append(command, index, 0);
  }
  return entries;
}

class TranscriptSpeaker {
  const TranscriptSpeaker(this.names, this.locale, this.faces, this.status);
  final List<String> names;
  final String locale;
  final List<String> faces;
  final int status;
  String text(String separator) => status == 1
      ? '???'
      : status == 2
      ? ''
      : names.join(separator);
  List<String> get keys => status == 1
      ? ['anonymous']
      : status == 2 || names.isEmpty
      ? ['unnamed']
      : names.map((name) => 'name:$name').toList();
}

TranscriptSpeaker transcriptSpeaker(
  Entry command,
  CatalogVisuals? visuals,
  SiteText t, {
  bool provider = false,
}) {
  final locale = provider ? t.locale : t.textLocale(command['text']);
  String resolve(Object? value) => t.textIn(value, locale);
  final authored = command['targetTextNames'] as List? ?? const [];
  final targets = _records(command['targets']);
  final targetNames = [
    for (final target in targets)
      resolve(target['name']).isNotEmpty
          ? target['name']
          : visuals?.characters[(target['characterId'] as num?)
                ?.toInt()]?['characterName'],
  ];
  final names = authored.any((n) => resolve(n).isNotEmpty)
      ? authored
      : targetNames.any((n) => resolve(n).isNotEmpty)
      ? targetNames
      : [command['targetName']];
  final status = (command['targetStatus'] as num?)?.toInt() ?? 0;
  final faces = <String>{
    if (status == 0)
      for (final target in targets)
        if ((target['faceImage'] ??
                visuals?.characters[(target['characterId'] as num?)
                    ?.toInt()]?['faceImage'])
            case final String face when face.isNotEmpty)
          face,
  }.toList();
  return TranscriptSpeaker(
    [
      for (final name in names)
        if (resolve(name).isNotEmpty) resolve(name),
    ],
    locale,
    faces,
    status,
  );
}
