/// A read save's cards, character ranks and band items as box changes, as
/// the website's Box import reads them (`box-import/preview.ts`,
/// `merge.ts`): levels from experience against the release's tables,
/// values outside the current ranges left for review.
library;

import '../save/game_save.dart';
import 'box.dart';
import 'catalog.dart';
import 'engine/num.dart';

enum ExistingPolicy { keep, updates, overwrite }

class SaveImport {
  SaveImport(
    this.members,
    this.snaps,
    this.characterRanks,
    this.bandItems,
    this.issues,
  );

  /// card id → field (`lvl`, `awk`, `rnk`, `sk`, `gsk`) → value.
  final Map<int, Map<String, int>> members;
  final Map<int, Map<String, int>> snaps;
  final Map<int, int> characterRanks;
  final Map<int, int> bandItems;

  /// Entries whose value is outside this release's range.
  final int issues;

  /// The box writes for [policy]: an import never removes a card.
  List<(String, Object?)> changes(BoxView view, ExistingPolicy policy) {
    final out = <(String, Object?)>[];
    void card(String prefix, int id, Map<String, int> fields, Object? owned) {
      out.add(('$prefix.$id.own', true));
      if (owned == null) out.add(('$prefix.$id.use', true));
      for (final MapEntry(key: field, :value) in fields.entries) {
        final before = switch ((owned, field)) {
          (OwnedMember m, 'lvl') => m.level,
          (OwnedMember m, 'awk') => m.awake,
          (OwnedMember m, 'rnk') => m.rank,
          (OwnedMember m, 'sk') => m.skill,
          (OwnedMember m, 'gsk') => m.gekisoSkill,
          (OwnedSnap s, 'lvl') => s.level,
          (OwnedSnap s, 'rnk') => s.rank,
          _ => null,
        };
        final write =
            owned == null ||
            policy == ExistingPolicy.overwrite ||
            (policy == ExistingPolicy.updates &&
                (before == null || value > before));
        if (write) out.add(('$prefix.$id.$field', value));
      }
    }

    for (final MapEntry(key: id, value: fields) in members.entries) {
      card('m', id, fields, view.members[id]);
    }
    for (final MapEntry(key: id, value: fields) in snaps.entries) {
      card('s', id, fields, view.snaps[id]);
    }
    void map(String prefix, Map<int, int> values, Map<String, int?> current) {
      for (final MapEntry(key: id, :value) in values.entries) {
        final before = current['$id'];
        final exists = current.containsKey('$id');
        if (exists && policy == ExistingPolicy.keep) continue;
        if (exists &&
            policy == ExistingPolicy.updates &&
            before != null &&
            value <= before) {
          continue;
        }
        out.add(('$prefix.$id', value));
      }
    }

    map('cr', characterRanks, view.player.characterRanks);
    map('bi', bandItems, view.player.bandItems);
    return out;
  }
}

/// The highest value whose experience threshold the save's experience reaches.
int? _fromExp(List<Doc> rows, Object? exp, int? group, String key) {
  final have = BigInt.tryParse('${exp ?? ''}');
  if (have == null) return null;
  int? best;
  for (final raw in rows) {
    final row = nativeRow(raw);
    final threshold = BigInt.tryParse('${row['exp'] ?? ''}'.split('.').first);
    final value = row[key];
    if ((group != null && intOf(row['group']) != group) ||
        threshold == null ||
        value is! num) {
      continue;
    }
    if (threshold <= have && (best == null || value > best)) {
      best = value.toInt();
    }
  }
  return best;
}

SaveImport readSave(GameSave save, TeamCatalog catalog) {
  final player = save.player;
  final progression = objectRow(catalog.data['progression']);
  final master = catalog.master;
  List<Doc> rows(String key) => [
    for (final row in player[key] as List? ?? const [])
      if (row is Map) row.cast<String, Object?>(),
  ];
  var issues = 0;
  final members = <int, Map<String, int>>{};
  for (final row in rows('_memberCards')) {
    final id = intOf(row['_masterId']);
    final card = master.members[id];
    if (card == null) {
      issues++;
      continue;
    }
    final fields = <String, int>{};
    final awake = row['_awakeCount'];
    if (awake is num) {
      if (master.memberAwake[card.awakeGroup]?.containsKey(awake.toInt()) ??
          awake <= 1) {
        fields['awk'] = awake.toInt();
      } else {
        issues++;
      }
    }
    final level = _fromExp(
      dataRows(progression['memberCardLevels']),
      row['_exp'],
      card.levelGroup,
      'level',
    );
    final limits = catalog.memberLimits(id, fields['awk']);
    if (level != null) {
      if (limits != null && level >= 1 && level <= limits.levelCap) {
        fields['lvl'] = level;
      } else {
        issues++;
      }
    }
    for (final (source, field, max) in [
      ('_rank', 'rnk', limits?.rank),
      ('_liveSkillLevel', 'sk', limits?.liveSkillLevel),
      ('_performanceSkillLevel', 'gsk', limits?.gekisoSkillLevel),
    ]) {
      final value = row[source];
      if (value is! num) continue;
      if (max != null && value >= 1 && value <= max) {
        fields[field] = value.toInt();
      } else {
        issues++;
      }
    }
    members[id] = fields;
  }
  final snaps = <int, Map<String, int>>{};
  for (final row in rows('_supportCards')) {
    final id = intOf(row['_masterId']);
    final card = master.snaps[id];
    if (card == null) {
      issues++;
      continue;
    }
    final fields = <String, int>{};
    final rank = row['_rank'];
    final limits = catalog.snapLimits(id, null);
    if (rank is num) {
      if (limits != null && rank >= 1 && rank <= limits.rank) {
        fields['rnk'] = rank.toInt();
      } else {
        issues++;
      }
    }
    final level = _fromExp(
      dataRows(progression['supportCardLevels']),
      row['_exp'],
      card.levelGroup,
      'level',
    );
    final cap = catalog.snapLimits(id, fields['rnk'])?.levelCap;
    if (level != null) {
      if (cap != null && level >= 1 && level <= cap) {
        fields['lvl'] = level;
      } else {
        issues++;
      }
    }
    snaps[id] = fields;
  }
  final characterRanks = <int, int>{};
  for (final row in rows('_characters')) {
    final id = intOf(row['_masterId']);
    if (!master.characters.containsKey(id)) {
      issues++;
      continue;
    }
    final rank = _fromExp(
      dataRows(progression['characterRanks']),
      row['_exp'],
      null,
      'rank',
    );
    if (rank != null && rank >= 1 && rank <= master.maxCharacterRank) {
      characterRanks[id] = rank;
    }
  }
  final bandItems = <int, int>{};
  for (final row in rows('_bandItems')) {
    final id = intOf(row['_masterId']);
    final item = objectRow(objectRow(catalog.data['bandItems'])['$id']);
    final level = row['_level'];
    if (item.isEmpty || level is! num) {
      issues++;
      continue;
    }
    final levels = {
      0,
      for (final entry in dataRows(item['levels']))
        intOf(nativeRow(entry)['level']),
    };
    if (levels.contains(level.toInt())) {
      bandItems[id] = level.toInt();
    } else {
      issues++;
    }
  }
  return SaveImport(members, snaps, characterRanks, bandItems, issues);
}
