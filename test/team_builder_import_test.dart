import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/team_builder/box.dart';
import 'package:haneoka/team_builder/box_import.dart';
import 'package:haneoka/team_builder/engine/master.dart';
import 'package:haneoka/team_builder/screenshot_import.dart';

/// The website's Box import (`box-import/preview.ts`, `merge.ts`,
/// `data/list-import.ts`) on a card list and a compact package, read into
/// an empty box on the intl release.
void main() {
  const dir = 'test/fixtures/team_builder';
  final data = jsonDecode(
    utf8.decode(gzip.decode(File('$dir/data-intl.json.gz').readAsBytesSync())),
  ) as Map<String, Object?>;
  final master = compileTeamData(data);
  final golden = jsonDecode(
    File('$dir/import-golden.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final cases = golden['cases'] as Map<String, Object?>;
  final server = '${(data['identity'] as Map)['server']}';

  Map<String, Object?> summary(BoxPreview preview) => {
    'cards': [
      for (final card in preview.cards) [card.key, card.values],
    ],
    'maps': [
      for (final map in preview.maps) [map.key, map.values],
    ],
    'issues': [
      for (final issue in preview.issues)
        [issue.kind, issue.id, issue.field, issue.code],
    ],
  };

  /// The applied writes in the website's inventory shape.
  Map<String, Object?> applied(List<(String, Object?)> writes) {
    final members = <int, List<Object?>>{};
    final snaps = <int, List<Object?>>{};
    final characterRanks = <String, Object?>{};
    final bandItems = <String, Object?>{};
    const memberSlots = ['lvl', 'awk', 'rnk', 'sk', 'gsk'];
    const snapSlots = ['lvl', 'rnk'];
    for (final (key, value) in writes) {
      final parts = key.split('.');
      switch (parts[0]) {
        case 'm':
          final row = members[int.parse(parts[1])] ??= List.filled(5, null);
          final slot = memberSlots.indexOf(parts[2]);
          if (slot >= 0) row[slot] = value;
        case 's':
          final row = snaps[int.parse(parts[1])] ??= List.filled(2, null);
          final slot = snapSlots.indexOf(parts[2]);
          if (slot >= 0) row[slot] = value;
        case 'cr':
          characterRanks[parts[1]] = value;
        case 'bi':
          bandItems[parts[1]] = value;
      }
    }
    return {
      'members': [
        for (final MapEntry(key: id, value: row) in members.entries)
          [id, ...row],
      ],
      'snapshots': [
        for (final MapEntry(key: id, value: row) in snaps.entries) [id, ...row],
      ],
      'characterRanks': characterRanks,
      'bandItems': bandItems,
    };
  }

  BoxConfirmation clean(BoxPreview preview) => BoxConfirmation(
    ExistingPolicy.keep,
    {
      for (final card in preview.cards)
        if (!preview.blocked(card)) card.key: CardChoice(include: true),
    },
    {for (final map in preview.maps) map.key: MapChoice(include: true)},
  );

  test('card list', () {
    final view = BoxView.read({});
    final preview = previewInventoryList(
      '${golden['list']}',
      view,
      master,
      data,
      server,
      true,
    );
    expect(jsonDecode(jsonEncode(summary(preview))), cases['list']);
    expect(
      jsonDecode(
        jsonEncode(
          applied(applyBoxImport(view, preview, clean(preview), master)),
        ),
      ),
      cases['listApplied'],
    );
  });

  test('compact package', () {
    final view = BoxView.read({});
    final candidate = parseBoxText('${golden['onpkg']}').single;
    final preview = previewBoxImport(candidate, view, master, data, server);
    expect(jsonDecode(jsonEncode(summary(preview))), cases['box']);
    expect(
      jsonDecode(
        jsonEncode(
          applied(applyBoxImport(view, preview, clean(preview), master)),
        ),
      ),
      cases['boxApplied'],
    );
  });

  test('screenshot recognition', () {
    final shots = jsonDecode(
      File('$dir/screenshot-golden.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final owned = shots['owned'] as Map<String, Object?>;
    final id = owned['cardId'];
    BoxEntry entry(Object? v) => BoxEntry(v, 1, 'test', 0);
    final view = BoxView.read({
      'm.$id.own': entry(true),
      'm.$id.use': entry(true),
      'm.$id.awk': entry(owned['training']),
      'm.$id.lvl': entry(owned['level']),
    });
    final job = shots['job'] as Map<String, Object?>;
    final result = normalizeRecognition(job);
    final selections = {
      for (final (index, row) in result.observations.indexed)
        (0, index): row.cardId,
    };
    final cards = previewScreenshots(
      [result],
      selections,
      view,
      master,
      server,
    );
    expect(
      jsonDecode(
        jsonEncode([
          for (final card in cards)
            [
              card.key,
              [
                for (final (image, index) in card.observations) [image, index],
              ],
              card.observedLevels,
              card.existingLevel,
            ],
        ]),
      ),
      shots['cards'],
    );
    final applied = shots['applied'] as Map<String, Object?>;
    for (final policy in ExistingPolicy.values) {
      final choices = {
        for (final card in cards)
          card.key: ScreenshotChoice()
            ..include = true
            ..level = card.observedLevels.length > 1
                ? ValueChoice(card.observedLevels[1])
                : null,
      };
      final writes = applyScreenshots(cards, choices, policy, master);
      final want = applied[policy.name] as Map<String, Object?>;
      final levels = <String, Object?>{
        for (final (key, value) in writes)
          if (key.endsWith('.lvl')) key: value,
      };
      for (final (kind, prefix) in [('members', 'm'), ('snapshots', 's')]) {
        for (final row in want[kind] as List) {
          final [cardId, level] = row as List;
          final key = '$prefix.$cardId.lvl';
          final saved = cardId == id ? owned['level'] : null;
          expect(levels[key] ?? saved, level, reason: '${policy.name} $key');
        }
      }
    }
  });
}
