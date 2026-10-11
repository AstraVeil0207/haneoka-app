import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/save/codec.dart';
import 'package:haneoka/save/game_save.dart';

void main() {
  // Encrypted with the website importer's Rijndael implementation.
  final cache = File('test/fixtures/vec-cache.bin').readAsBytesSync();
  final persist = File('test/fixtures/vec-persist.bin').readAsBytesSync();

  test('decrypts a save written by the reference cipher', () {
    final data = SaveCodec.decode(cache)!;
    final player = data['_player'] as Map<String, Object?>;
    expect(player['_profileId'], '123456789012');
    expect(
      (player['_memberCards'] as List).single,
      containsPair('_exp', '123456789012'),
    );
  });

  test('rejects files that are not saves', () {
    expect(SaveCodec.decode(cache.sublist(0, 95)), isNull);
    expect(SaveCodec.decode(Uint8List.fromList(List.filled(128, 0))), isNull);
  });

  test('groups an account directory into one save', () {
    final collector = SaveCollector()
      ..offer(SaveCandidate(bytes: persist, source: 'a/2', group: 'a'))
      ..offer(
        SaveCandidate(
          bytes: cache,
          source: 'a/1',
          group: 'a',
          release: GameRelease.jp,
        ),
      );
    final save = collector.saves.single;
    expect(save.profileId, '123456789012');
    expect(save.release, GameRelease.jp);
    expect(
      save.documents.keys,
      containsAll([SaveDocumentKind.cache, SaveDocumentKind.persist]),
    );
  });
}
