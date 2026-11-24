import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/app_paths.dart';
import 'package:path/path.dart' as p;

import 'partial_lock_io_overrides.dart';

/// #305 סעיף 1: הדגל `mirrorLocked`, ותיקיית ההעדפות שנפרדת מתיקיית המצב.
void main() {
  late Directory sandbox;
  late Directory drive;
  late Directory machine;

  Map<String, String> env() => {
        'LOCALAPPDATA': machine.path,
        'XDG_DATA_HOME': machine.path,
        'HOME': machine.path,
      };

  String machineDir() => AppPaths.machineStateDir(
        env(),
        isWindows: Platform.isWindows,
        isMacOS: Platform.isMacOS,
      )!;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('mirror-locked-flags-');
    drive = Directory(p.join(sandbox.path, 'drive'))..createSync();
    machine = Directory(p.join(sandbox.path, 'machine'))..createSync();
    final manifest =
        File(p.join(drive.path, 'mirror', 'library', 'releases.json'));
    manifest.parent.createSync(recursive: true);
    manifest.writeAsStringSync('[]');
  });
  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

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

  test('שורש ו-mirror נעולים, נתונים כתיבים: mirrorLocked, העדפות במחשב',
      () async {
    createDataFolders();

    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      lockedDirs: {'', 'mirror'},
    ));

    expect(paths.readOnly, isTrue);
    expect(paths.mirrorLocked, isTrue);
    expect(paths.stateDir, paths.dataDir);
    expect(paths.prefsDir, machineDir());
  });

  test('השורש כתיב ו-mirror/ נעולה: גם כאן ההעדפות במחשב', () async {
    createDataFolders();

    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      lockedDirs: {'mirror'},
    ));

    expect(paths.mirrorLocked, isTrue);
    expect(paths.prefsDir, machineDir());
  });

  test('כונן מוגן לגמרי אינו mirrorLocked, וההעדפות עם המצב', () async {
    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      lockedDirs: {'', 'mirror'},
      uncreatable: dataFolders.toSet(),
    ));

    expect(paths.readOnly, isTrue);
    expect(paths.mirrorLocked, isFalse);
    expect(paths.prefsDir, paths.stateDir);
  });

  test('הרצה כותבת רגילה: לא mirrorLocked, ההעדפות בשורש', () async {
    final paths = await resolve(PartialLockIOOverrides(driveRoot: drive.path));

    expect(paths.readOnly, isFalse);
    expect(paths.mirrorLocked, isFalse);
    expect(paths.prefsDir, paths.dataDir);
  });

  for (final folder in dataFolders) {
    test('תיקיית נתונים נעולה ($folder): חוזרים למצב קריאה מלא', () async {
      createDataFolders();

      final paths = await resolve(PartialLockIOOverrides(
        driveRoot: drive.path,
        lockedDirs: {'', 'mirror', folder},
      ));

      expect(paths.readOnly, isTrue);
      expect(paths.mirrorLocked, isFalse);
      expect(p.isWithin(machine.path, paths.stateDir), isTrue);
    });
  }

  test('שורש נעול אבל mirror/ כתיבה: אינו mirrorLocked, כמו בכונן מוגן',
      () async {
    createDataFolders();

    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      lockedDirs: {''},
    ));

    expect(paths.readOnly, isTrue);
    expect(paths.mirrorLocked, isFalse);
    expect(p.isWithin(machine.path, paths.stateDir), isTrue);
  });

  test('כשל חולף בכתיבה ל-mirror/ בכונן כתיב אינו הופך אותו לנעול', () async {
    createDataFolders();

    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      transientFailures: {'mirror': 2},
    ));

    expect(paths.readOnly, isFalse);
    expect(paths.mirrorLocked, isFalse);
    expect(paths.prefsDir, paths.dataDir);
  });

  test('כשל בכל ניסיונות הכתיבה ל-mirror/ נחשב נעילה', () async {
    createDataFolders();

    final paths = await resolve(PartialLockIOOverrides(
      driveRoot: drive.path,
      transientFailures: {'mirror': 3},
    ));

    expect(paths.mirrorLocked, isTrue);
  });

  group('seedStateFromMachine', () {
    AppPaths locked({bool mirrorLocked = true}) => AppPaths(
          dataDir: drive.path,
          stateDir: drive.path,
          readOnly: true,
          mirrorLocked: mirrorLocked,
          prefsDir: machine.path,
        );

    File onMachine(String name) => File(p.join(machine.path, 'logs', name));
    File onDrive(String name) => File(p.join(drive.path, 'logs', name));

    test('מעתיק לכונן קובץ מצב שחסר בו, ומשאיר את המקור', () async {
      Directory(p.join(drive.path, 'logs')).createSync(recursive: true);
      onMachine('library_state.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('machine');

      await locked().seedStateFromMachine();

      expect(onDrive('library_state.json').readAsStringSync(), 'machine');
      expect(onMachine('library_state.json').existsSync(), isTrue);
    });

    test('קובץ שכבר בכונן אינו נדרס, גם אם בכונן אין מה של המחשב הזה',
        () async {
      Directory(p.join(drive.path, 'logs')).createSync(recursive: true);
      onDrive('library_state.json').writeAsStringSync('drive');
      onMachine('library_state.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('machine');

      await locked().seedStateFromMachine();

      expect(onDrive('library_state.json').readAsStringSync(), 'drive');
    });

    test('בלי mirrorLocked לא מעתיקים כלום', () async {
      Directory(p.join(drive.path, 'logs')).createSync(recursive: true);
      onMachine('library_state.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('machine');

      await locked(mirrorLocked: false).seedStateFromMachine();

      expect(onDrive('library_state.json').existsSync(), isFalse);
    });

    test('בלי קובץ במחשב לא נוצר קובץ בכונן', () async {
      Directory(p.join(drive.path, 'logs')).createSync(recursive: true);

      await locked().seedStateFromMachine();

      expect(onDrive('library_state.json').existsSync(), isFalse);
    });
  });

  group('seedPreferences במראה נעולה', () {
    AppPaths locked() => AppPaths(
          dataDir: drive.path,
          stateDir: drive.path,
          readOnly: true,
          mirrorLocked: true,
          prefsDir: machine.path,
        );

    test('מעתיק את ההעדפות מהכונן למחשב ואינו נוגע בעותק שבכונן', () async {
      final source = File(p.join(drive.path, 'launcher_settings.json'))
        ..writeAsStringSync('{"language":"english"}');

      await locked().seedPreferences();

      expect(
        File(p.join(machine.path, 'launcher_settings.json')).readAsStringSync(),
        '{"language":"english"}',
      );
      expect(source.readAsStringSync(), '{"language":"english"}');
      expect(
        File(p.join(drive.path, 'launcher_settings.json.tmp')).existsSync(),
        isFalse,
      );
    });

    test('הגדרות שכבר במחשב אינן נדרסות', () async {
      File(p.join(drive.path, 'launcher_settings.json'))
          .writeAsStringSync('from-drive');
      final local = File(p.join(machine.path, 'launcher_settings.json'))
        ..writeAsStringSync('from-machine');

      await locked().seedPreferences();

      expect(local.readAsStringSync(), 'from-machine');
    });
  });
}
