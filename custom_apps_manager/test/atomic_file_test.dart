import 'dart:io';

import 'package:custom_apps_manager/src/services/atomic_file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late String root;

  setUp(() => root = tempMirrorRoot());

  test('כל כתיבה מקבלת קובץ זמני משלה', () {
    final target = p.join(root, 'state.json');
    final names = {for (var i = 0; i < 100; i++) uniqueTempPath(target)};

    expect(names, hasLength(100));
    for (final name in names) {
      expect(isAtomicTempNameOf(p.basename(name), 'state.json'), isTrue);
    }
  });

  test('כתיבות מקבילות לאותו קובץ כולן מצליחות ואינן משאירות זבל', () async {
    final target = p.join(root, 'state.json');

    await Future.wait([
      for (var i = 0; i < 20; i++) writeStringAtomically(target, 'v$i'),
    ]);

    expect(File(target).readAsStringSync(), matches(RegExp(r'^v\d+$')));
    expect(
      Directory(root).listSync().map((e) => p.basename(e.path)),
      ['state.json'],
    );
  });

  test('כשל אינו נוגע בקובץ זמני של כתיבה אחרת', () async {
    final target = p.join(root, 'state.json');
    final foreign = File('$target.tmp')..writeAsStringSync('other');
    writeFile(p.join(target, 'occupied'));

    await expectLater(
      writeStringAtomically(target, 'new'),
      throwsA(isA<FileSystemException>()),
    );

    expect(foreign.readAsStringSync(), 'other');
    expect(
      Directory(root).listSync().map((e) => p.basename(e.path)).toSet(),
      {'state.json', 'state.json.tmp'},
    );
    expect(Directory(target).existsSync(), isTrue);
  });

  test('שם זמני של קובץ אחר אינו מזוהה כשלו', () {
    expect(isAtomicTempNameOf('installer.json.tmp', 'installer.json'), isTrue);
    expect(isAtomicTempNameOf('Installer.JSON.1-2-3.TMP', 'installer.json'),
        isTrue);
    expect(isAtomicTempNameOf('installer.json', 'installer.json'), isFalse);
    expect(
        isAtomicTempNameOf('installer.jsonx.tmp', 'installer.json'), isFalse);
    expect(isAtomicTempNameOf('setup.exe.tmp', 'installer.json'), isFalse);
  });
}
