import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/account/haneoka_account.dart';
import 'package:haneoka/save/game_save.dart';
import 'package:haneoka/save/save_view.dart';

void main() {
  test('derives the S256 challenge of RFC 7636 appendix B', () {
    expect(
      HaneokaAccount.challengeOf('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('summarises a player with numbers only', () {
    final save = GameSave(
      profileId: '123456789012',
      name: 'Xuc',
      release: GameRelease.intlStore,
      source: 'test',
    );
    save.documents[SaveDocumentKind.cache] = SaveDocument(
      SaveDocumentKind.cache,
      {
        '_player': {
          '_profileId': '123456789012',
          '_exp': 1740600,
          '_playerRankUpData': {'_afterRank': 47},
        },
      },
      null,
    );
    final summary = HaneokaAccount.summaryOf(SaveView(save));
    expect(summary['rank'], 47);
    expect(summary['exp'], 1740600);
    expect(summary['clears'], containsPair('expert', [0, 0, 0]));
    expect(summary.values.whereType<String>(), isEmpty);
  });

  test('reads a linked player row', () {
    final player = LinkedPlayer.fromJson({
      'region': 'intl',
      'playerUid': '1',
      'visibility': 'public',
      'lastSyncedAt': 0,
    })!;
    expect(player.public, isTrue);
    expect(player.server, 'intl');
  });
}
