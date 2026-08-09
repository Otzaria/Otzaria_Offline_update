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
      // קובץ הבדיקה נכתב **ונמחק** — תיקייה שנוצרה לבדה אינה הוכחה לכתיבה.
      expect(
          overrides.createdFiles, [p.join(expectedDataDir(), '.write-test')]);
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
      expect(error.toString(), contains(error.attemptedDir));
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
  _UnwritableFile(this.path, this._message);

  @override
  final String path;
  final String _message;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      Future.error(FileSystemException(_message, path));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
