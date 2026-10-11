import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/save/game_save.dart';
import 'package:haneoka/sources/ios_backup.dart';

void main() {
  // Built by a script that follows the backup format, holding one save under
  // AppDomain-com.bushiroad.sirius.
  test('reads the game save from a plain backup', () async {
    final backup = (await IosBackup.find('test/fixtures/backup-plain')).single;
    expect(backup.encrypted, isFalse);
    expect(backup.deviceName, 'Test iPhone');
    final collector = SaveCollector();
    expect(await backup.scan(collector), 1);
    expect(collector.saves.single.profileId, '123456789012');
    expect(collector.saves.single.release, GameRelease.jp);
  });

  test(
    'reads the game save from an encrypted backup with its password',
    () async {
      final backup = (await IosBackup.find('test/fixtures/backup-encrypted'))
          .single;
      expect(backup.encrypted, isTrue);
      final collector = SaveCollector();
      expect(await backup.scan(collector, password: 'hunter2'), 1);
      expect(collector.saves.single.profileId, '123456789012');
    },
  );

  test('a wrong backup password is reported as such', () async {
    final backup = (await IosBackup.find('test/fixtures/backup-encrypted'))
        .single;
    expect(
      backup.scan(SaveCollector(), password: 'wrong'),
      throwsA(isA<BackupPasswordException>()),
    );
  });
}
