import 'dart:convert';

/// A port of the website's `lib/song-performer.ts`: who performs a song, as
/// bands (with logos) and characters (with portraits), resolved from the
/// song's band ids, credited names and vocalists against one game's
/// registry.

typedef Row = Map<String, Object?>;

class PerformerPortrait {
  const PerformerPortrait({
    required this.key,
    required this.provider,
    required this.server,
    required this.id,
    required this.name,
    required this.image,
    this.sourceId,
  });
  final String key;
  final String provider;
  final String server;
  final String? sourceId;
  final int id;
  final Object? name;
  final String image;
}

class PerformerRegistry {
  PerformerRegistry({
    required this.game,
    required this.server,
    required this.bands,
    required this.characters,
    this.sourceId,
    this.portraitFallbacks,
  });

  /// `our-notes` or `gbp`.
  final String game;
  final String server;
  final String? sourceId;
  final Map<int, Row> bands;
  final Map<int, Row> characters;
  List<PerformerPortrait>? portraitFallbacks;
  final _cache = Expando<SongPerformer>();
}

class SongPerformer {
  const SongPerformer({
    required this.bandIds,
    required this.participantCharacterIds,
    required this.explicitCharacterIds,
    required this.portraits,
    required this.names,
    required this.logos,
    required this.unresolvedNames,
  });
  final List<int> bandIds;
  final List<int> participantCharacterIds;
  final List<int> explicitCharacterIds;
  final List<PerformerPortrait> portraits;
  final List<Object?> names;
  final List<({int id, Object? name, String image})> logos;
  final List<String> unresolvedNames;
}

List<int> _ids(Object? value) {
  final list = value is List ? value : (value == null ? const [] : [value]);
  final out = <int>[];
  for (final entry in list) {
    final n = entry is num ? entry : num.tryParse('$entry');
    if (n != null && n == n.truncate() && n > 0 && !out.contains(n.toInt())) {
      out.add(n.toInt());
    }
  }
  return out;
}

List<String> _texts(Object? value) => [
  for (final v in value is List ? value : [value])
    if (v is String && v.trim().isNotEmpty) v,
];

/// NFKC is approximated by folding full-width ASCII, which is what the
/// catalogue's names differ by.
String _nfkc(String value) => String.fromCharCodes(
  value.runes.map(
    (r) => r >= 0xFF01 && r <= 0xFF5E ? r - 0xFEE0 : (r == 0x3000 ? 0x20 : r),
  ),
);

String _key(String name) =>
    _nfkc(name).replaceAll(RegExp(r'\s+'), '').toLowerCase();

List<String> _split(Object? value) => [
  for (final name in _texts(value))
    for (final part in name.split(
      RegExp(
        r'\s*[×＋+&＆]|\s+x\s+|\s+(?:feat\.?|with)\s+',
        caseSensitive: false,
      ),
    ))
      if (part.trim().isNotEmpty) part.trim(),
];

// Official BanG Dream news2067 identifies these five CRYCHIC members.
const _crychic = ['高松燈', '長崎そよ', '椎名立希', '若葉睦', '豊川祥子'];

SongPerformer resolveSongPerformer(Row song, PerformerRegistry registry) {
  if (registry._cache[song] case final cached?) return cached;
  final bandSet = <int>[];
  final explicit = <int>[];
  final participants = <int>[];
  final portraits = <String, PerformerPortrait>{};
  final names = <Object?>[];
  final authoredNames = <Object?>[];
  final unresolved = <String>[];
  final logos = <({int id, Object? name, String image})>[];
  bool official(Row band) => registry.game == 'our-notes'
      ? band['official'] != false
      : band['official'] == true;

  List<int> nameIds(String name, String kind) {
    final records = kind == 'band' ? registry.bands : registry.characters;
    final primary = [
      for (final MapEntry(key: id, value: row) in records.entries)
        if (_texts(
              kind == 'band'
                  ? (row['bandName'] ?? row['name'])
                  : (row['characterName'] ?? row['name']),
            )
            .expand((v) => kind == 'character' ? v.split(RegExp('[／/]')) : [v])
            .any((v) => _key(v) == _key(name)))
          id,
    ];
    if (primary.isNotEmpty || kind == 'band') return primary;
    return [
      for (final MapEntry(key: id, value: row) in registry.characters.entries)
        if ([
          ..._texts(row['firstName']),
          ..._texts(row['nickname']),
        ].any((v) => _key(v) == _key(name)))
          id,
    ];
  }

  void addCharacter(int id, [bool display = true, bool? isExplicit]) {
    isExplicit ??= display;
    final row = registry.characters[id];
    if (row == null) return;
    if (isExplicit && !participants.contains(id)) {
      names.add(row['characterName'] ?? row['name']);
    }
    if (!participants.contains(id)) participants.add(id);
    if (display) {
      if (isExplicit && !explicit.contains(id)) explicit.add(id);
      final key =
          '${registry.game}:${registry.server}:${registry.sourceId ?? ''}:$id';
      portraits[key] = PerformerPortrait(
        key: key,
        provider: registry.game,
        server: registry.server,
        sourceId: registry.sourceId,
        id: id,
        name: row['characterName'] ?? row['name'],
        image: '${row['faceImage'] ?? row['thumbnailImage'] ?? ''}',
      );
    }
  }

  void addBand(int id) {
    if (bandSet.contains(id)) return;
    final row = registry.bands[id];
    if (row == null || !official(row)) return;
    bandSet.add(id);
    names.add(row['bandName'] ?? row['name']);
    final roster = _ids(row['memberCharacterIds']);
    for (final MapEntry(key: characterId, value: character)
        in registry.characters.entries) {
      if ((character['bandId'] as num?)?.toInt() == id) roster.add(characterId);
    }
    final image = '${row['logo'] ?? row['icon'] ?? ''}';
    if (image.isNotEmpty) {
      logos.add((id: id, name: row['bandName'] ?? row['name'], image: image));
    }
    for (final characterId in roster.toSet()) {
      addCharacter(characterId, image.isEmpty, false);
    }
  }

  void resolveName(String name, [bool retainUnknown = true]) {
    if (_key(name) == 'crychic') {
      names.add('CRYCHIC');
      for (final member in _crychic) {
        final candidates = nameIds(member, 'character');
        if (candidates.length == 1) {
          addCharacter(candidates.single, true, false);
        } else {
          final fallback = registry.portraitFallbacks
              ?.where((p) => _texts(p.name).any((v) => _key(v) == _key(member)))
              .toList();
          if (fallback?.length == 1) {
            portraits[fallback!.single.key] = fallback.single;
          } else if (!unresolved.contains(member)) {
            unresolved.add(member);
          }
        }
      }
      return;
    }
    final bands = nameIds(
      name,
      'band',
    ).where((id) => official(registry.bands[id]!)).toList();
    if (bands.length == 1) {
      addBand(bands.single);
      return;
    }
    final chars = nameIds(name, 'character');
    if (chars.length == 1) {
      addCharacter(chars.single);
      return;
    }
    if (retainUnknown && !unresolved.contains(name)) unresolved.add(name);
  }

  final direct = _ids(song['bandIds'] ?? song['bandId']);
  for (final id in direct) {
    final band = registry.bands[id];
    if (band == null) continue;
    if (official(band)) {
      addBand(id);
      continue;
    }
    if ((band['bandName'] ?? band['name']) case final name?) {
      authoredNames.add(name);
    }
    for (final member in _ids(band['memberBandIds'])) {
      addBand(member);
    }
    for (final member in _ids(band['memberCharacterIds'])) {
      addCharacter(member);
    }
    for (final name in _texts(band['memberNames'])) {
      resolveName(name);
    }
    for (final name in _split(band['bandName'])) {
      resolveName(name, false);
    }
  }
  if (direct.isEmpty) {
    for (final name in _split(song['artistName'] ?? song['bandName'])) {
      resolveName(name);
    }
  }
  final stated = _ids(
    song['characterIds'] ?? song['characters'] ?? song['characterId'],
  );
  final vocals = _ids(song['vocalCharacterIds']);
  for (final id in [...stated, ...vocals]) {
    if (!participants.contains(id)) addCharacter(id);
  }
  final shown = unresolved.isNotEmpty && authoredNames.isNotEmpty
      ? authoredNames
      : [...names, ...unresolved];
  final seen = <String>{};
  final result = SongPerformer(
    bandIds: bandSet,
    participantCharacterIds: participants,
    explicitCharacterIds: explicit,
    portraits: portraits.values.toList(),
    names: [
      for (final name in shown)
        if (seen.add(jsonEncode(name))) name,
    ],
    logos: logos,
    unresolvedNames: unresolved,
  );
  registry._cache[song] = result;
  return result;
}
