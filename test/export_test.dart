import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/save/export.dart';
import 'package:haneoka/save/game_save.dart';
import 'package:haneoka/save/account_store.dart';

GameSave _fixture() {
  final collector = SaveCollector()
    ..offer(
      SaveCandidate(
        bytes: File('test/fixtures/vec-cache.bin').readAsBytesSync(),
        source: 'a/1',
        group: 'a',
        release: GameRelease.jp,
      ),
    )
    ..offer(
      SaveCandidate(
        bytes: File('test/fixtures/vec-persist.bin').readAsBytesSync(),
        source: 'a/2',
        group: 'a',
      ),
    );
  return collector.saves.single;
}

void main() {
  test('the full export carries progress but no identity', () {
    final document =
        jsonDecode(utf8.decode(exportSave(_fixture()))) as Map<String, Object?>;
    final player = document['player'] as Map<String, Object?>;
    expect(document['schema'], 'haneoka-game-save-v1');
    expect(document['server'], 'jp');
    expect(player.containsKey('_memberCards'), isTrue);
    expect(player.containsKey('_name'), isFalse);
    expect(player.containsKey('_accountId'), isFalse);
    expect(player.containsKey('_password'), isFalse);
    expect((document['persist'] as Map)['_latestLiveScore'], 900000);
  });

  test('the team package is ONPKG1 text', () {
    final text = exportTeamPackage(_fixture());
    expect(text, startsWith('ONPKG1:'));
    File('${Directory.systemTemp.path}/haneoka-onpkg.txt')
        .writeAsStringSync(text);
  });

  test('an imported account reads back as it was stored', () {
    final save = _fixture();
    final copy = AccountStore.decode(
      jsonDecode(jsonEncode(AccountStore.encode(save))),
    )!;
    expect(copy.profileId, save.profileId);
    expect(copy.release, GameRelease.jp);
    expect(copy.player['_memberCards'], save.player['_memberCards']);
    expect(
      copy.documents[SaveDocumentKind.persist]?.data['_latestLiveScore'],
      900000,
    );
  });
}
