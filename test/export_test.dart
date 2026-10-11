import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/l10n/app_localizations.dart';
import 'package:haneoka/save/export.dart';
import 'package:haneoka/save/game_save.dart';
import 'package:haneoka/ui/save_screen.dart';

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

  testWidgets('the save screen lists the sections the save holds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SaveScreen(save: _fixture()),
      ),
    );
    expect(find.text('123456789012'), findsWidgets);
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Song results'), findsOneWidget);
    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    expect(find.text('1001'), findsOneWidget);
  });
}
