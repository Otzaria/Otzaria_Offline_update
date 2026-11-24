import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/app_paths.dart';
import 'package:path/path.dart' as p;

import 'partial_lock_io_overrides.dart';

/// #305 סעיף 1: בדיקת הכתיבה לפי תיקייה. כונן שה-mirror/ שלו נעול והנתונים
/// פתוחים אינו "כונן מוגן" — הדוחות והלוגים נשארים עליו.
void main() {
  late Directory sandbox;
  late Directory drive;
  late Directory machine;

  Map<String, String> env() => {
        'LOCALAPPDATA': machine.path,
        'XDG_DATA_HOME': machine.path,
        'HOME': machine.path,
      };

  String expectedDataDir() =>
      p.join(p.dirname(Platform.resolvedExecutable), AppPaths.dirName);

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('mirror-locked-');
    drive = Directory(p.join(sandbox.path, 'drive'))..createSync();
    machine = Directory(p.join(sandbox.path, 'machine'))..createSync();
  });
  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  void fillMirror() {
    final file = File(p.join(drive.path, 'mirror', 'library', 'releases.json'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('[]');
  }

  void createDataFolders() {
    for (final name in dataFolders) {
      Directory(p.join(drive.path, name)).createSync(recursive: true);
    }
  }

  Future<AppPaths> resolve(PartialLockIOOverrides io) =>
      IOOverrides.runWithIOOverrides(
        () => AppPaths.resolve(environment: env()),
        io,
      );

  test('שורש ו-mirror נעולים, תיקיות הנתונים כתיבות: המצב נשאר בכונן',
      () async {
    fillMirror();
    createDataFolders();

    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      lockedDirs: {'', 'mirror'},
    ));

    expect(paths.readOnly, isTrue);
    expect(paths.driveFull, isFalse);
    expect(paths.dataDir, expectedDataDir());
    expect(paths.stateDir, paths.dataDir);
    expect(paths.stateFilesDir, p.join(paths.dataDir, 'logs'));
  });

  test('השורש כתיב אבל mirror/ נעולה: אין הורדות, והמצב נשאר בכונן', () async {
    fillMirror();
    createDataFolders();

    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      lockedDirs: {'mirror'},
    ));

    expect(paths.readOnly, isTrue);
    expect(paths.stateDir, paths.dataDir);
  });

  test('mirror/ נעולה ותיקיית נתונים נעולה: חוזרים למצב קריאה מלא', () async {
    fillMirror();
    createDataFolders();

    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      lockedDirs: {'', 'mirror', p.join('reports', 'outbox')},
    ));

    expect(paths.readOnly, isTrue);
    expect(p.isWithin(machine.path, paths.stateDir), isTrue);
  });

  test('שורש נעול ותיקיות הנתונים חסרות ואי אפשר ליצור אותן: מצב קריאה מלא',
      () async {
    fillMirror();

    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      lockedDirs: {'', 'mirror'},
      uncreatable: dataFolders.toSet(),
    ));

    expect(paths.readOnly, isTrue);
    expect(p.isWithin(machine.path, paths.stateDir), isTrue);
  });

  test('mirror/ כתיבה: הרצה רגילה, וקובץ הבדיקה לא נשאר בה', () async {
    fillMirror();

    final paths = await resolve(PartialLockIOOverrides(driveRoot: drive.path));

    expect(paths.readOnly, isFalse);
    expect(paths.stateDir, paths.dataDir);
    final left = Directory(p.join(drive.path, 'mirror'))
        .listSync(recursive: true)
        .map((e) => p.basename(e.path))
        .where((name) => name.startsWith('.write-test'));
    expect(left, isEmpty);
  });

  test('אין mirror/ והשורש כתיב: הרצה רגילה, בלי בדיקה ובלי ליצור אותה',
      () async {
    final io = PartialLockIOOverrides(driveRoot: drive.path);
    final paths = await resolve(io);

    expect(paths.readOnly, isFalse);
    expect(paths.stateDir, paths.dataDir);
    expect(io.probed, ['']);
    expect(Directory(p.join(drive.path, 'mirror')).existsSync(), isFalse);
  });

  test('כתיבת הבדיקה שנכשלה באמצע אינה משאירה קובץ ב-mirror/', () async {
    fillMirror();
    createDataFolders();

    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      lockedDirs: {'mirror'},
      partialWrite: true,
    ));

    expect(paths.readOnly, isTrue);
    final left = Directory(p.join(drive.path, 'mirror'))
        .listSync(recursive: true)
        .map((e) => p.basename(e.path))
        .where((name) => name.startsWith('.write-test'));
    expect(left, isEmpty);
  });
}
