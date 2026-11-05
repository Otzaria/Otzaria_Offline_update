import 'dart:convert';
import 'dart:io';

import 'package:library_manager/src/services/companion_file_operations.dart';
import 'package:test/test.dart';

void main() {
  test('every interrupted companion swap and rollback restores the old state', () {
    final root = Directory.systemTemp.createTempSync(
      'companion-recovery-matrix-',
    );
    addTearDown(() => root.delete(recursive: true));
    var cases = 0;

    for (final directoryContent in [false, true]) {
      for (var mask = 0; mask < 4; mask++) {
        for (var phase = 0; phase <= 4; phase++) {
          for (
            var recoveredSuffix = 0;
            recoveredSuffix <= 2;
            recoveredSuffix++
          ) {
            final dir = Directory('${root.path}/case-${cases++}')..createSync();
            final paths = ['${dir.path}/content', '${dir.path}/marker'];
            final existed = [mask & 1 != 0, mask & 2 != 0];
            final backup = Directory(companionBackupPath(paths[0]))
              ..createSync();
            File(
              '${backup.path}/state.json',
            ).writeAsStringSync(jsonEncode(existed));

            void put(String path, String value, int index) {
              if (directoryContent && index == 0) {
                Directory(path).createSync();
                File('$path/payload').writeAsStringSync(value);
              } else {
                File(path).writeAsStringSync(value);
              }
            }

            FileSystemEntity entity(String path, int index) =>
                directoryContent && index == 0 ? Directory(path) : File(path);

            bool exists(String path) =>
                FileSystemEntity.typeSync(path, followLinks: false) !=
                FileSystemEntityType.notFound;

            for (var i = 0; i < 2; i++) {
              if (existed[i]) put(paths[i], 'old-$i', i);
            }

            // Stop before/after each backup rename, then after each publication.
            for (var i = 0; i < 2 && i < phase; i++) {
              if (existed[i]) {
                entity(paths[i], i).renameSync('${backup.path}/$i');
              }
            }
            if (phase >= 2) {
              for (var i = 0; i < phase - 2; i++) {
                put(paths[i], 'new-$i', i);
              }
            }

            // Recovery itself may have been interrupted after restoring a suffix.
            for (var j = 0; j < recoveredSuffix; j++) {
              final i = 1 - j;
              final saved = '${backup.path}/$i';
              if (exists(saved)) {
                if (exists(paths[i])) {
                  entity(paths[i], i).deleteSync(recursive: true);
                }
                entity(saved, i).renameSync(paths[i]);
              } else if (!existed[i] && exists(paths[i])) {
                entity(paths[i], i).deleteSync(recursive: true);
              }
            }

            recoverCompanionInstall(paths[0], paths);
            recoverCompanionInstall(paths[0], paths);
            final scenario =
                'directory=$directoryContent, existed=$existed, '
                'phase=$phase, recoveredSuffix=$recoveredSuffix';
            for (var i = 0; i < 2; i++) {
              expect(exists(paths[i]), existed[i], reason: scenario);
              if (existed[i]) {
                final file = File(
                  directoryContent && i == 0 ? '${paths[i]}/payload' : paths[i],
                );
                expect(file.readAsStringSync(), 'old-$i', reason: scenario);
              }
            }
            expect(backup.existsSync(), isFalse, reason: scenario);
          }
        }
      }
    }
    expect(cases, 120);
  });
}
