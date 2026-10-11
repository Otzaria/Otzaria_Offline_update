import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/services/app_paths.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';

/// תיקיית הנתונים היא מלכודת מרכזית (AGENTS §5): היא **תמיד** צמודה לקובץ
/// ההרצה, ואם אי אפשר לכתוב בה — התוכנה מסרבת לרוץ ולא נופלת ל-%APPDATA%,
/// כי אחרת הנתונים היו נשארים על המחשב המקוון.
void main() {
  /// המקום שבו התיקייה **אמורה** לשבת בהרצה הנוכחית.
  String expectedDataDir() =>
      p.join(p.dirname(Platform.resolvedExecutable), AppPaths.dirName);

  group('AppPaths.resolve', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('app-paths-test-');
    });
    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    test('שם התיקייה קבוע ואינו ניתן להגדרה', () {
      expect(AppPaths.dirName, 'OtzariaData');
    });

    test('התיקייה נוצרת, נבדקת בכתיבה בפועל, וקובץ הבדיקה נמחק אחריה',
        () async {
      final overrides = _RedirectingIOOverrides(sandbox.path);
      final paths = await IOOverrides.runWithIOOverrides(
        AppPaths.resolve,
        overrides,
      );

      expect(paths.dataDir, expectedDataDir());
      expect(overrides.createdDirs, contains(expectedDataDir()));
      expect(overrides.createdFiles,
          [p.join(expectedDataDir(), '.write-test-$pid')]);
      expect(sandbox.listSync(), isEmpty);
    });

    test('בווינדוס: התיקייה נגזרת מתיקיית ה-exe (app-files), לא מ-%APPDATA%',
        () async {
      final paths = await IOOverrides.runWithIOOverrides(
        AppPaths.resolve,
        _RedirectingIOOverrides(sandbox.path),
      );

      expect(p.dirname(paths.dataDir), p.dirname(Platform.resolvedExecutable));
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        expect(p.isWithin(appData, paths.dataDir), isFalse);
      }
    }, skip: !Platform.isWindows);

    test('ב-macOS התיקייה יושבת ליד חבילת ה-.app ולא בתוך Contents/MacOS',
        () async {
      final paths = await IOOverrides.runWithIOOverrides(
        AppPaths.resolve,
        _RedirectingIOOverrides(sandbox.path),
      );

      expect(paths.dataDir, isNot(contains('${p.separator}Contents')));
      expect(p.basename(paths.dataDir), AppPaths.dirName);
      // אין נפילה לתיקיית התמיכה של המשתמש.
      expect(paths.dataDir, isNot(contains('Application Support')));
    }, skip: !Platform.isMacOS);

    // אותה מלכודת, בבדיקה שרצה **בכל** פלטפורמה: ב-macOS קובץ ההרצה קבור
    // בתוך החבילה, ותיקייה שנוצרת לצידו נעלמת מהמשתמש וגם נמחקת בכל עדכון
    // עצמי (שמחליף את החבילה כולה).
    group('executableRoot', () {
      // הנתיבים נבנים ב-`p.join` ולא כמחרוזת: הבדיקה רצה גם בווינדוס, ושם
      // המפריד אחר — בדיוק כמו ב-`AppPaths` עצמה.
      final driveRoot = p.join('Volumes', 'KEY');
      final bundle = p.join(driveRoot, 'Otzaria Launcher.app');

      test('macOS: מטפס אל התיקייה שמחוץ לחבילת ה-.app', () {
        expect(
          AppPaths.executableRoot(
            p.join(bundle, 'Contents', 'MacOS', 'Otzaria Launcher'),
            isMacOS: true,
          ),
          driveRoot,
        );
      });

      test('macOS: הרצה שאינה מתוך חבילה נשארת בתיקיית הקובץ', () {
        expect(
          AppPaths.executableRoot(
            p.join('tmp', 'build', 'launcher_app'),
            isMacOS: true,
          ),
          p.join('tmp', 'build'),
        );
      });

      test('ווינדוס: תיקיית ה-exe, גם כשהנתיב מזכיר .app', () {
        expect(
          AppPaths.executableRoot(
            p.join(bundle, 'app-files', 'launcher_app.exe'),
            isMacOS: false,
          ),
          p.join(bundle, 'app-files'),
        );
      });
    });

    // המקום שבו נשמרים לוג ומצב כשהכונן נעול. `XDG_DATA_HOME` הוא מוסכמה
    // של לינוקס, ו-`~/.local` ב-macOS הוא מקום שהמשתמש לא ימצא בו.
    group('machineStateDir', () {
      test('macOS: תחת Library/Application Support', () {
        expect(
          AppPaths.machineStateDir(
            const {'HOME': '/Users/x', 'XDG_DATA_HOME': '/Users/x/.local'},
            isWindows: false,
            isMacOS: true,
          ),
          p.join('/Users/x', 'Library', 'Application Support',
              AppPaths.machineDirName),
        );
      });

      test('ווינדוס: LOCALAPPDATA', () {
        expect(
          AppPaths.machineStateDir(
            const {'LOCALAPPDATA': r'C:\Users\x\AppData\Local'},
            isWindows: true,
            isMacOS: false,
          ),
          p.join(r'C:\Users\x\AppData\Local', AppPaths.machineDirName),
        );
      });

      test('בלי HOME — אין ממה לגזור', () {
        expect(
          AppPaths.machineStateDir(
            const {},
            isWindows: false,
            isMacOS: true,
          ),
          isNull,
        );
      });
    });

    test('תיקייה שאי אפשר ליצור → AppPathsException, בלי נפילה ל-%APPDATA%',
        () async {
      await expectLater(
        IOOverrides.runWithIOOverrides(
          AppPaths.resolve,
          _FailingIOOverrides(failOnDirectory: true),
        ),
        throwsA(isA<AppPathsException>()
            .having((e) => e.attemptedDir, 'attemptedDir', expectedDataDir())),
      );
    });

    test('תיקייה שנוצרת אך חוסמת כתיבה (ACL) גם היא נכשלת', () async {
      // בדיוק המקרה שבגללו נכתב קובץ בדיקה: היצירה מצליחה, הכתיבה לא.
      await expectLater(
        IOOverrides.runWithIOOverrides(
          AppPaths.resolve,
          _FailingIOOverrides(failOnDirectory: false, sandbox: sandbox.path),
        ),
        throwsA(isA<AppPathsException>()),
      );
    });

    test('קובץ בדיקה שנכתב ולא נמחק (אנטי-וירוס) → כונן כותב, לא מצב קריאה',
        () async {
      final overrides = _UndeletableProbeIOOverrides(sandbox.path);
      final paths = await IOOverrides.runWithIOOverrides(
        AppPaths.resolve,
        overrides,
      );

      expect(overrides.deleteAttempted, isTrue);
      expect(paths.readOnly, isFalse);
      expect(paths.stateDir, paths.dataDir);
    });

    test('macOS App Translocation → הודעה ייעודית, בלי לגעת בדיסק', () async {
      const executable = '/private/var/folders/ab/xyz/T/AppTranslocation/'
          '1234-ABCD/d/Otzaria Launcher.app/Contents/MacOS/Otzaria Launcher';
      final overrides = _RedirectingIOOverrides(sandbox.path);

      await expectLater(
        IOOverrides.runWithIOOverrides(
          () => AppPaths.resolve(
            resolvedExecutable: executable,
            isMacOS: true,
          ),
          overrides,
        ),
        throwsA(isA<AppPathsException>()
            .having(
              (e) => e.message,
              'message',
              AppL10n.strings.setupError.appTranslocated,
            )
            .having((e) => e.kind, 'kind', AppPathsFailure.appTranslocated)),
      );
      expect(overrides.createdDirs, isEmpty);
      expect(overrides.createdFiles, isEmpty);
    });

    test('הודעת השגיאה מגיעה מ-otzaria_l10n ולא ממחרוזת בקוד', () async {
      AppL10n.use(AppLanguage.english);
      addTearDown(() => AppL10n.use(AppLanguage.hebrew));

      final error = await IOOverrides.runWithIOOverrides(
        () async {
          try {
            await AppPaths.resolve();
            return null;
          } on AppPathsException catch (e) {
            return e;
          }
        },
        _FailingIOOverrides(failOnDirectory: true, message: 'nope'),
      );

      expect(error, isNotNull);
      expect(
        error!.message,
        AppL10n.strings.setupError.cannotWriteToDataDir('nope'),
      );
      expect(error.kind, AppPathsFailure.cannotWrite);
      expect(error.toString(), contains(error.attemptedDir));
    });
  });

  group('כונן מוגן-כתיבה (בעיה #25)', () {
    late Directory sandbox;
    late Directory drive;
    late Directory machine;

    Map<String, String> env() => {
          'LOCALAPPDATA': machine.path,
          'XDG_DATA_HOME': machine.path,
          'HOME': machine.path,
        };

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('locked-drive-');
      drive = Directory(p.join(sandbox.path, 'drive'))..createSync();
      machine = Directory(p.join(sandbox.path, 'machine'))..createSync();
    });
    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    /// מייצר manifest אחד במראה שעל הכונן — ההוכחה שיש ממה להתקין.
    void fillMirror() {
      final file = File(p.join(
        drive.path,
        'mirror',
        'library',
        'releases.json',
      ));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('[]');
    }

    test('כונן נעול שנושא מראה → מצב קריאה, והכתיבה עוברת למחשב', () async {
      fillMirror();

      final paths = await IOOverrides.runWithIOOverrides(
        () => AppPaths.resolve(environment: env()),
        _LockedDriveIOOverrides(driveRoot: drive.path),
      );

      expect(paths.readOnly, isTrue);
      expect(paths.dataDir, expectedDataDir());
      expect(
        paths.stateDir,
        AppPaths.machineStateDir(
          env(),
          isWindows: Platform.isWindows,
          isMacOS: Platform.isMacOS,
        ),
      );
      expect(p.isWithin(machine.path, paths.stateDir), isTrue);
      expect(p.isWithin(paths.dataDir, paths.stateDir), isFalse);
    });

    test('כונן נעול **בלי** מראה → אותה שגיאה כמו קודם', () async {
      // תיקייה נעולה שאין בה מה להתקין אינה "מצב קריאה" אלא התקנה במקום
      // הלא נכון — וזה מה שצריך להיאמר.
      await expectLater(
        IOOverrides.runWithIOOverrides(
          () => AppPaths.resolve(environment: env()),
          _LockedDriveIOOverrides(driveRoot: drive.path),
        ),
        throwsA(isA<AppPathsException>()),
      );
    });

    test('אין תיקיית משתמש לכתוב אליה → שגיאה, ולא מצב קריאה שקרי', () async {
      fillMirror();

      await expectLater(
        IOOverrides.runWithIOOverrides(
          () => AppPaths.resolve(environment: const {}),
          _LockedDriveIOOverrides(driveRoot: drive.path),
        ),
        throwsA(isA<AppPathsException>()),
      );
    });

    OSError noSpace() =>
        OSError('No space left on device', Platform.isWindows ? 112 : 28);

    test('כונן מלא שנושא מראה → מצב קריאה, מסומן ככונן מלא', () async {
      fillMirror();
      final environment = {...env(), 'HOME': machine.path};

      final paths = await IOOverrides.runWithIOOverrides(
        () => AppPaths.resolve(environment: environment),
        _LockedDriveIOOverrides(driveRoot: drive.path, osError: noSpace()),
      );

      expect(paths.readOnly, isTrue);
      expect(paths.driveFull, isTrue);
      expect(paths.dataDir, expectedDataDir());
      expect(
        paths.stateDir,
        AppPaths.machineStateDir(
          environment,
          isWindows: Platform.isWindows,
          isMacOS: Platform.isMacOS,
        ),
      );
    });

    test('כונן מלא בלי מראה → הודעת "כונן מלא"', () async {
      await expectLater(
        IOOverrides.runWithIOOverrides(
          () => AppPaths.resolve(environment: {...env(), 'HOME': machine.path}),
          _LockedDriveIOOverrides(driveRoot: drive.path, osError: noSpace()),
        ),
        throwsA(isA<AppPathsException>()
            .having(
              (e) => e.message,
              'message',
              AppL10n.strings.setupError.driveFull,
            )
            .having((e) => e.kind, 'kind', AppPathsFailure.driveFull)),
      );
      expect(machine.listSync(), isEmpty);
    });

    test('כונן נעול שאינו מלא אינו מסומן ככונן מלא', () async {
      fillMirror();

      final paths = await IOOverrides.runWithIOOverrides(
        () => AppPaths.resolve(environment: {...env(), 'HOME': machine.path}),
        _LockedDriveIOOverrides(driveRoot: drive.path),
      );

      expect(paths.readOnly, isTrue);
      expect(paths.driveFull, isFalse);
    });

    test('הרצה כותבת רגילה נשארת ללא stateDir נפרד', () async {
      final paths = await IOOverrides.runWithIOOverrides(
        AppPaths.resolve,
        _RedirectingIOOverrides(sandbox.path),
      );

      expect(paths.readOnly, isFalse);
      expect(paths.stateDir, paths.dataDir);
    });

    test('העדפות מועתקות למחשב, קובצי המצב לא', () async {
      // הגדרות ושפה נוסעות עם הכונן; "מה מותקן ואיפה" הוא של המחשב שכתב
      // אותו, ולכן העתקה שלו הייתה משקרת על המחשב החדש.
      File(p.join(drive.path, 'launcher_settings.json'))
          .writeAsStringSync('{"language":"english"}');
      File(p.join(drive.path, 'library_state.json'))
          .writeAsStringSync('{"customDbPath":"D:/nope"}');

      final paths = AppPaths(
        dataDir: drive.path,
        stateDir: machine.path,
        readOnly: true,
      );
      await paths.seedPreferences();

      expect(
        File(p.join(machine.path, 'launcher_settings.json')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(machine.path, 'library_state.json')).existsSync(),
        isFalse,
      );
    });

    test('העתקה אינה דורסת העדפות שכבר נשמרו במחשב', () async {
      File(p.join(drive.path, 'launcher_settings.json'))
          .writeAsStringSync('from-drive');
      final onMachine = File(p.join(machine.path, 'launcher_settings.json'))
        ..writeAsStringSync('from-machine');

      await AppPaths(
        dataDir: drive.path,
        stateDir: machine.path,
        readOnly: true,
      ).seedPreferences();

      expect(onMachine.readAsStringSync(), 'from-machine');
    });

    test('קובצי מצב עוברים מהשורש ל-logs, וקובץ שכבר שם גובר', () async {
      File(p.join(machine.path, 'otzaria_install_state.json'))
          .writeAsStringSync('old');
      File(p.join(machine.path, 'library_state.json')).writeAsStringSync('old');
      Directory(p.join(machine.path, 'logs')).createSync();
      final kept = File(p.join(machine.path, 'logs', 'library_state.json'))
        ..writeAsStringSync('new');
      File(p.join(machine.path, 'launcher_settings.json'))
          .writeAsStringSync('prefs');

      await AppPaths(dataDir: drive.path, stateDir: machine.path)
          .migrateStateFiles();

      expect(
        File(p.join(machine.path, 'logs', 'otzaria_install_state.json'))
            .readAsStringSync(),
        'old',
      );
      expect(
        File(p.join(machine.path, 'otzaria_install_state.json')).existsSync(),
        isFalse,
      );
      expect(kept.readAsStringSync(), 'new');
      // ההעדפות נשארות בשורש — הן אלה שנוסעות עם הכונן.
      expect(
        File(p.join(machine.path, 'launcher_settings.json')).existsSync(),
        isTrue,
      );
    });

    test('כל קובצי המצב עוברים, והרצה חוזרת וריקה אינן שוברות', () async {
      final paths = AppPaths(dataDir: drive.path, stateDir: machine.path);
      await paths.migrateStateFiles();
      for (final name in AppPaths.stateFileNames) {
        File(p.join(machine.path, name)).writeAsStringSync(name);
      }

      await paths.migrateStateFiles();
      await paths.migrateStateFiles();

      for (final name in AppPaths.stateFileNames) {
        expect(File(p.join(machine.path, name)).existsSync(), isFalse);
        expect(
            File(p.join(paths.stateFilesDir, name)).readAsStringSync(), name);
      }
    });

    test('בהרצה כותבת אין העתקה בכלל', () async {
      File(p.join(drive.path, 'launcher_settings.json'))
          .writeAsStringSync('from-drive');

      await AppPaths(dataDir: drive.path, stateDir: machine.path)
          .seedPreferences();

      expect(
        File(p.join(machine.path, 'launcher_settings.json')).existsSync(),
        isFalse,
      );
    });
  });

  group('תת-הנתיבים שמתחת לתיקיית הנתונים', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('app-paths-sub'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('mirror/library, mirror/app ו-mirror/plugins יושבים תחת dataDir', () {
      final library = LibraryModuleController(dataDir: tempDir.path);
      final otzaria = OtzariaModuleController(dataDir: tempDir.path);
      // הלאנצ'ר מוסר לחנות את שורש המראה, ותיקיית התוספים נגזרת ממנו.
      final plugins = PluginMirrorStore(p.join(tempDir.path, 'mirror'));

      expect(library.mirrorDir, p.join(tempDir.path, 'mirror', 'library'));
      expect(otzaria.mirrorDir, p.join(tempDir.path, 'mirror', 'app'));
      expect(plugins.pluginsDir, p.join(tempDir.path, 'mirror', 'plugins'));

      library.dispose();
      otzaria.dispose();
    });
  });
}

/// `Directory`/`File` אמיתיים גם מתוך override — בלי זה הבנאי היה חוזר
/// ל-override עצמו ונכנס לרקורסיה אינסופית.
Directory _realDirectory(String path) => Zone.root.run(() => Directory(path));
File _realFile(String path) => Zone.root.run(() => File(path));

/// מפנה כל יצירת קובץ/תיקייה לארגז חול זמני, כדי שהבדיקה לא תכתוב באמת
/// לצד קובץ ההרצה של סביבת הבדיקות.
final class _RedirectingIOOverrides extends IOOverrides {
  _RedirectingIOOverrides(this.sandbox);

  final String sandbox;
  final List<String> createdDirs = [];
  final List<String> createdFiles = [];

  @override
  Directory createDirectory(String path) {
    createdDirs.add(path);
    return _realDirectory(sandbox);
  }

  @override
  File createFile(String path) {
    createdFiles.add(path);
    return _realFile(p.join(sandbox, p.basename(path)));
  }
}

/// מדמה תיקייה שאי אפשר ליצור, או תיקייה שנוצרת אך חוסמת כתיבה.
final class _FailingIOOverrides extends IOOverrides {
  _FailingIOOverrides({
    required this.failOnDirectory,
    this.sandbox,
    this.message = 'denied',
  });

  final bool failOnDirectory;

  /// לאן מפנים יצירת תיקייה שאמורה להצליח — לעולם לא לצד קובץ ההרצה.
  final String? sandbox;
  final String message;

  @override
  Directory createDirectory(String path) => failOnDirectory
      ? _UnwritableDirectory(path, message)
      : _realDirectory(sandbox ?? path);

  @override
  File createFile(String path) => _UnwritableFile(path, message);
}

/// מדמה כונן USB עם מפתח נעילה: התיקיות **קיימות ונקראות**, וכל כתיבה
/// אליהן נכשלת. מה שמחוץ לכונן (תיקיית המשתמש שבמחשב) אמיתי וכותב — זה
/// בדיוק מה שמצב הקריאה אמור למצוא.
final class _LockedDriveIOOverrides extends IOOverrides {
  _LockedDriveIOOverrides({required this.driveRoot, this.osError});

  final String driveRoot;
  final OSError? osError;

  String get _dataDir =>
      p.join(p.dirname(Platform.resolvedExecutable), AppPaths.dirName);

  bool _onDrive(String path) => path == _dataDir || p.isWithin(_dataDir, path);

  String _mapped(String path) => path == _dataDir
      ? driveRoot
      : p.join(driveRoot, p.relative(path, from: _dataDir));

  @override
  Directory createDirectory(String path) =>
      _realDirectory(_onDrive(path) ? _mapped(path) : path);

  @override
  File createFile(String path) {
    if (!_onDrive(path)) return _realFile(path);
    if (p.basename(path).startsWith('.write-test')) {
      return _UnwritableFile(path, 'The media is write protected', osError);

    }
    return _realFile(_mapped(path));
  }
}

class _UnwritableDirectory implements Directory {
  _UnwritableDirectory(this.path, this._message);

  @override
  final String path;
  final String _message;

  @override
  Future<Directory> create({bool recursive = false}) =>
      Future.error(FileSystemException(_message, path));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnwritableFile implements File {
  _UnwritableFile(this.path, this._message, [this._osError]);

  @override
  final String path;
  final String _message;
  final OSError? _osError;

  @override
  Future<bool> exists() async => false;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      Future.error(FileSystemException(_message, path, _osError));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UndeletableProbeIOOverrides extends IOOverrides {
  _UndeletableProbeIOOverrides(this.sandbox);

  final String sandbox;
  bool deleteAttempted = false;

  @override
  Directory createDirectory(String path) => _realDirectory(sandbox);

  @override
  File createFile(String path) => _UndeletableFile(
        _realFile(p.join(sandbox, p.basename(path))),
        () => deleteAttempted = true,
      );
}

class _UndeletableFile implements File {
  _UndeletableFile(this._inner, this._onDelete);

  final File _inner;
  final void Function() _onDelete;

  @override
  String get path => _inner.path;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    await _inner.writeAsString(contents, flush: flush);
    return this;
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) {
    _onDelete();
    return Future.error(
      FileSystemException('The process cannot access the file', path),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
