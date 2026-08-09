import 'dart:io';

import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('LibraryDbLocator', () {
    late Directory tempDir;
    late LibraryStateStore stateStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db-locator-test-');
      stateStore = LibraryStateStore(p.join(tempDir.path, 'state.json'));
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    /// ברירות המחדל מוצבעות לתוך ה-tempDir בכוונה: כך הבדיקות לא תלויות
    /// בשאלה אם למפתח שמריץ אותן מותקנת אוצריא אמיתית במיקום ברירת המחדל.
    ///
    /// ה-OS הנדרס הוא macos, ולכן הנתיבים שהמאתר בונה הם POSIX — גם כשהבדיקה
    /// רצה ב-Windows. הציפיות למטה נבנות ב-[p.posix] מאותה סיבה.
    LibraryDbLocator locatorWithIsolatedDefaults() => LibraryDbLocator(
          stateStore: stateStore,
          operatingSystem: 'macos',
          environment: {'HOME': p.posix.join(tempDir.path, 'home')},
        );

    test('returns null when neither custom nor default DB exists', () async {
      expect(await locatorWithIsolatedDefaults().resolveDbPath(), isNull);
    });

    test('finds the DB in the macOS default location', () async {
      final defaultPath = p.posix.join(
        tempDir.path,
        'home',
        'Library',
        'Application Support',
        'otzaria',
        'books',
        'seforim.db',
      );
      await Directory(p.dirname(defaultPath)).create(recursive: true);
      await File(defaultPath).writeAsString('fake db');

      expect(await locatorWithIsolatedDefaults().resolveDbPath(), defaultPath);
    });

    test('prefers a saved custom path over the default when both could exist',
        () async {
      final customDbPath =
          p.posix.join(tempDir.path, 'my-library', 'seforim.db');
      await Directory(p.dirname(customDbPath)).create(recursive: true);
      await File(customDbPath).writeAsString('fake db');
      await stateStore.saveCustomDbPath(customDbPath);

      expect(await locatorWithIsolatedDefaults().resolveDbPath(), customDbPath);
    });

    test('ignores a saved custom path that no longer exists on disk', () async {
      await stateStore.saveCustomDbPath(
          p.posix.join(tempDir.path, 'missing', 'seforim.db'));

      // אין גם default — אז התוצאה הצפויה היא null, לא הנתיב הישן.
      expect(await locatorWithIsolatedDefaults().resolveDbPath(), isNull);
    });

    test('falls back to the system-wide macOS location order, not the reverse',
        () async {
      // רק המיקום הפר-משתמשי קיים → הוא זה שנבחר, לפני המערכתי.
      final userPath = p.posix.join(tempDir.path, 'home', 'Library',
          'Application Support', 'otzaria', 'books', 'seforim.db');
      await Directory(p.dirname(userPath)).create(recursive: true);
      await File(userPath).writeAsString('fake db');

      expect(await locatorWithIsolatedDefaults().resolveDbPath(), userPath);
    });
  });

  /// סדר החיפוש בווינדוס — ברירות המחדל מוצבעות לתוך ה-tempDir דרך דריסת
  /// הסביבה, כדי שהבדיקה לא תיגע ב-`%APPDATA%` האמיתי של המפתח.
  group('LibraryDbLocator.resolveDbPath (Windows)', () {
    late Directory tempDir;
    late LibraryStateStore stateStore;
    late String appDataDb;
    late String programDataDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db-locator-win-test-');
      stateStore = LibraryStateStore(p.join(tempDir.path, 'state.json'));
      appDataDb = p.windows
          .join(tempDir.path, 'Roaming', 'otzaria', 'books', 'seforim.db');
      programDataDb = p.windows
          .join(tempDir.path, 'ProgramData', 'otzaria', 'books', 'seforim.db');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    LibraryDbLocator locator() => LibraryDbLocator(
          stateStore: stateStore,
          operatingSystem: 'windows',
          environment: {
            'APPDATA': p.windows.join(tempDir.path, 'Roaming'),
            'ProgramData': p.windows.join(tempDir.path, 'ProgramData'),
          },
        );

    Future<void> createDb(String path) async {
      await Directory(p.dirname(path)).create(recursive: true);
      await File(path).writeAsString('fake db');
    }

    test('APPDATA מנצח את ProgramData כששניהם קיימים', () async {
      if (!Platform.isWindows) {
        markTestSkipped('נתיבי Windows אמיתיים נדרשים לבדיקת קיום קובץ');
        return;
      }
      await createDb(appDataDb);
      await createDb(programDataDb);

      expect(await locator().resolveDbPath(), appDataDb);
    });

    test('נופל ל-ProgramData (התקנה מערכתית) כשאין ב-APPDATA', () async {
      if (!Platform.isWindows) {
        markTestSkipped('נתיבי Windows אמיתיים נדרשים לבדיקת קיום קובץ');
        return;
      }
      await createDb(programDataDb);

      expect(await locator().resolveDbPath(), programDataDb);
    });

    test('נתיב מותאם אישית קודם לשתי ברירות המחדל', () async {
      if (!Platform.isWindows) {
        markTestSkipped('נתיבי Windows אמיתיים נדרשים לבדיקת קיום קובץ');
        return;
      }
      final custom = p.windows.join(tempDir.path, 'my', 'seforim.db');
      await createDb(custom);
      await createDb(appDataDb);
      await createDb(programDataDb);
      await stateStore.saveCustomDbPath(custom);

      expect(await locator().resolveDbPath(), custom);
    });

    test('כשאין כלום — null, כדי שה-UI יבקש מהמשתמש להצביע ידנית', () async {
      if (!Platform.isWindows) {
        markTestSkipped('נתיבי Windows אמיתיים נדרשים לבדיקת קיום קובץ');
        return;
      }
      if (File(p.windows.join(
        LibraryDbLocator.legacyFallbackLibraryPath,
        LibraryDbLocator.databaseFileName,
      )).existsSync()) {
        markTestSkipped('קיימת התקנה ישנה ב-C:\\אוצריא במכונה הזו');
        return;
      }

      expect(await locator().resolveDbPath(), isNull);
    });
  });

  group('LibraryDbLocator.defaultDbDirs', () {
    // ברירות המחדל נגזרות מ-`lib/core/app_paths.dart` של אוצריא עצמה. הבדיקה
    // הזאת היא מה שיתפוס אם מישהו ישנה אותן כאן בלי לבדוק מול הקוד שם.
    test('macOS: per-user Application Support first, then system-wide', () {
      final dirs = LibraryDbLocator.defaultDbDirs(
        operatingSystem: 'macos',
        environment: const {'HOME': '/Users/dov'},
      );

      expect(dirs, [
        '/Users/dov/Library/Application Support/otzaria/books',
        '/Library/Application Support/otzaria/books',
      ]);
    });

    test('macOS: system-wide location is still offered without HOME', () {
      final dirs = LibraryDbLocator.defaultDbDirs(
        operatingSystem: 'macos',
        environment: const {},
      );

      expect(dirs, ['/Library/Application Support/otzaria/books']);
    });

    test('Windows: APPDATA first, then ProgramData for a system-wide install',
        () {
      final dirs = LibraryDbLocator.defaultDbDirs(
        operatingSystem: 'windows',
        environment: const {
          'APPDATA': r'C:\Users\dov\AppData\Roaming',
          'ProgramData': r'C:\ProgramData',
        },
      );

      expect(dirs, [
        r'C:\Users\dov\AppData\Roaming\otzaria\books',
        r'C:\ProgramData\otzaria\books',
      ]);
    });

    test('Windows: משתני סביבה חסרים לא מייצרים נתיבים שבורים', () {
      expect(
        LibraryDbLocator.defaultDbDirs(
          operatingSystem: 'windows',
          environment: const {'APPDATA': '', 'ProgramData': ''},
        ),
        isEmpty,
      );
      expect(
        LibraryDbLocator.defaultDbDirs(
          operatingSystem: 'windows',
          environment: const {},
        ),
        isEmpty,
      );
    });

    test('הגיבוי C:\\אוצריא אינו חלק מברירות המחדל — הוא נבדק אחרון ובנפרד',
        () {
      // הוא מיקום גיבוי להתקנות ישנות בלבד; ערבובו בברירות המחדל היה מחזיר
      // אותו לפני `%APPDATA%`, שהוא המיקום האמיתי.
      expect(LibraryDbLocator.legacyFallbackLibraryPath, r'C:\אוצריא');
      expect(
        LibraryDbLocator.defaultDbDirs(
          operatingSystem: 'windows',
          environment: const {'APPDATA': r'C:\a', 'ProgramData': r'C:\b'},
        ),
        isNot(contains(LibraryDbLocator.legacyFallbackLibraryPath)),
      );
    });

    test('linux: מיקום ה-XDG, כדי שבדיקות CI לא יקבלו רשימה ריקה', () {
      expect(
        LibraryDbLocator.defaultDbDirs(
          operatingSystem: 'linux',
          environment: const {'HOME': '/home/dov'},
        ),
        ['/home/dov/.local/share/otzaria/books'],
      );
    });

    test('פלטפורמה לא מוכרת מחזירה רשימה ריקה במקום לנחש', () {
      expect(
        LibraryDbLocator.defaultDbDirs(
          operatingSystem: 'fuchsia',
          environment: const {'HOME': '/home/dov'},
        ),
        isEmpty,
      );
    });

    test('שם קובץ המסד הוא seforim.db בכל הפלטפורמות', () {
      expect(LibraryDbLocator.databaseFileName, 'seforim.db');
    });
  });
}
