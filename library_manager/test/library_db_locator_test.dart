import 'dart:io';

import 'package:hive_ce/hive.dart';
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

  /// הפער שהיה כאן: אוצריא מחזיקה את נתיב הספרייה **בהגדרות שלה**, ומשתמש
  /// שהעביר את הספרייה לכונן אחר עשה זאת שם. בלי לקרוא את הקופסה עדכנו קובץ
  /// אחר לגמרי (או חשבנו שאין מסד בכלל).
  group('LibraryDbLocator — ההגדרות של אוצריא', () {
    late Directory tempDir;
    late LibraryStateStore stateStore;
    late String dataRoot;

    // הבדיקה נוגעת בקבצים אמיתיים, ולכן היא רצה בפלטפורמה של המכונה ולא
    // בדריסה — אחרת ה-context של הנתיבים לא תואם ל-`p.join` שכאן.
    final os = Platform.isWindows ? 'windows' : 'macos';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db-locator-hive-');
      stateStore = LibraryStateStore(p.join(tempDir.path, 'state.json'));
      dataRoot = Platform.isWindows
          ? p.join(tempDir.path, 'Roaming', 'otzaria')
          : p.join(tempDir.path, 'home', 'Library', 'Application Support',
              'otzaria');
      await Directory(dataRoot).create(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    /// כותב קופסת `app_preferences` אמיתית — אותה חבילה ואותו שם קופסה
    /// שאוצריא משתמשת בהם (`HiveCache.keyName`).
    Future<void> writeSettings(Map<String, String> values) async {
      Hive.init(dataRoot);
      final box = await Hive.openBox<dynamic>(
        OtzariaSettingsReader.boxName,
        path: dataRoot,
      );
      await box.putAll(values);
      await box.close();
    }

    LibraryDbLocator locator({String? launchPath}) => LibraryDbLocator(
          stateStore: stateStore,
          operatingSystem: os,
          environment: Platform.isWindows
              ? {'APPDATA': p.join(tempDir.path, 'Roaming')}
              : {'HOME': p.join(tempDir.path, 'home')},
          otzariaLaunchPath:
              launchPath == null ? null : (() async => launchPath),
        );

    Future<String> createDb(String dir) async {
      await Directory(dir).create(recursive: true);
      final path = p.join(dir, 'seforim.db');
      await File(path).writeAsString('fake db');
      return path;
    }

    test('נתיב ספרייה מההגדרות מנצח את מיקום ברירת המחדל', () async {
      final moved = await createDb(p.join(tempDir.path, 'external', 'books'));
      // גם בברירת המחדל יש מסד — ובכל זאת זה שבהגדרות הוא הנכון.
      await createDb(p.join(dataRoot, 'books'));
      await writeSettings({
        OtzariaSettingsReader.keyLibraryPath:
            p.join(tempDir.path, 'external', 'books'),
      });

      expect(await locator().resolveDbPath(), moved);
    });

    test('key-library-folder-name נוסף כתת-תיקייה, כמו _buildDbPath', () async {
      final nested = await createDb(p.join(tempDir.path, 'base', 'אוצריא'));
      await writeSettings({
        OtzariaSettingsReader.keyLibraryPath: p.join(tempDir.path, 'base'),
        OtzariaSettingsReader.keyLibraryFolderName: 'אוצריא',
      });

      expect(await locator().resolveDbPath(), nested);
    });

    test('הגדרה שמצביעה על קובץ שאינו קיים נופלת לברירת המחדל', () async {
      final fallback = await createDb(p.join(dataRoot, 'books'));
      await writeSettings({
        OtzariaSettingsReader.keyLibraryPath: p.join(tempDir.path, 'gone'),
      });

      expect(await locator().resolveDbPath(), fallback);
    });

    test('התקנה ניידת: הקופסה נקראת מתיקיית הנתונים שליד התוכנה', () async {
      // אוצריא ניידת — `portable.marker` ליד ה-executable, וההגדרות יושבות
      // ב-`otzaria_data` שלידו ולא ב-`%APPDATA%`/Application Support.
      final installDir = p.join(tempDir.path, 'drive');
      final launchPath = Platform.isWindows
          ? p.join(installDir, 'otzaria.exe')
          : p.join(installDir, 'אוצריא.app');
      final exeDir = Platform.isWindows
          ? installDir
          : p.join(launchPath, 'Contents', 'MacOS');
      await Directory(exeDir).create(recursive: true);
      await File(p.join(exeDir, LibraryDbLocator.portableMarkerFileName))
          .writeAsString('');
      dataRoot = p.join(exeDir, LibraryDbLocator.portableDataFolderName);
      await Directory(dataRoot).create(recursive: true);

      final portableDb = await createDb(p.join(dataRoot, 'books'));
      await writeSettings({
        OtzariaSettingsReader.keyLibraryPath: p.join(dataRoot, 'books'),
      });

      expect(await locator(launchPath: launchPath).resolveDbPath(), portableDb);
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

  /// לאן מותקנת ספרייה **חדשה**. ה-landmine כאן: תיקיית הלאנצ'ר עלולה לשבת
  /// על כונן נייד, ומסד שהותקן לידה נסע איתו ונעלם מהמחשב ברגע שנשלף.
  group('LibraryDbLocator.resolveInstallDbPath', () {
    late Directory tempDir;
    late LibraryStateStore stateStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db-install-test-');
      stateStore = LibraryStateStore(p.join(tempDir.path, 'state.json'));
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    LibraryDbLocator locator() => LibraryDbLocator(
          stateStore: stateStore,
          operatingSystem: 'macos',
          environment: {'HOME': p.posix.join(tempDir.path, 'home')},
        );

    String defaultDb() => p.posix.join(tempDir.path, 'home', 'Library',
        'Application Support', 'otzaria', 'books', 'seforim.db');

    test('בלי כלום — מיקום ברירת המחדל של אוצריא, שעוד לא קיים על הדיסק',
        () async {
      expect(await locator().resolveInstallDbPath(), defaultDb());
    });

    test('בחירת המשתמש מנצחת — גם כשהקובץ עוד לא נוצר', () async {
      // בשונה מ-`resolveDbPath`: בהתקנה טרייה הנתיב שנבחר הוא **היעד**, ולכן
      // אסור לו להיפסל רק בגלל שאין שם עדיין קובץ.
      final chosen = p.posix.join(tempDir.path, 'external', 'seforim.db');
      await stateStore.saveCustomDbPath(chosen);

      expect(await locator().resolveInstallDbPath(), chosen);
      expect(await locator().resolveDbPath(), isNull);
    });

    test('פלטפורמה שאין בה מיקום ידוע מחזירה null, בלי לנחש', () async {
      final unknown = LibraryDbLocator(
        stateStore: stateStore,
        operatingSystem: 'fuchsia',
        environment: const {},
      );

      expect(await unknown.resolveInstallDbPath(), isNull);
    });
  });

  group('LibraryDbLocator.isKnownToOtzaria', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db-known-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    LibraryDbLocator locator() => LibraryDbLocator(
          stateStore: LibraryStateStore(p.join(tempDir.path, 'state.json')),
          operatingSystem: 'macos',
          environment: {'HOME': p.posix.join(tempDir.path, 'home')},
        );

    test('ברירת המחדל של אוצריא מוכרת לה, ומיקום אחר לא', () async {
      final defaultDb = p.posix.join(tempDir.path, 'home', 'Library',
          'Application Support', 'otzaria', 'books', 'seforim.db');

      expect(await locator().isKnownToOtzaria(defaultDb), isTrue);
      expect(
        await locator()
            .isKnownToOtzaria(p.posix.join(tempDir.path, 'usb', 'seforim.db')),
        isFalse,
      );
    });

    test('הגיבוי הישן בווינדוס נחשב מוכר — אוצריא ישנה עדיין יושבת שם',
        () async {
      final windows = LibraryDbLocator(
        stateStore: LibraryStateStore(p.join(tempDir.path, 'state.json')),
        operatingSystem: 'windows',
        environment: const {r'APPDATA': r'C:\Users\dov\AppData\Roaming'},
      );

      expect(await windows.isKnownToOtzaria(r'C:\אוצריא\seforim.db'), isTrue);
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

  /// [LibraryDbLocator.otzariaDataRoots] ו-[LibraryDbLocator.defaultDbDirs]
  /// נגזרות מאותה טבלת נתיבים, ולכן ההבדל **המכוון** ביניהן — פלטפורמה לא
  /// מוכרת — צריך שמירה: איתור המסד מסרב לנחש, איתור ההגדרות דווקא מנסה את
  /// מיקום ה-XDG כדי שבדיקות CI בלינוקס לא יקבלו רשימה ריקה.
  group('LibraryDbLocator.otzariaDataRoots', () {
    LibraryDbLocator locatorFor(String os, Map<String, String> environment) =>
        LibraryDbLocator(
          stateStore: const LibraryStateStore('unused-state.json'),
          operatingSystem: os,
          environment: environment,
        );

    test('Windows: APPDATA לפני ProgramData, בלי סיומת books', () async {
      expect(
        await locatorFor('windows', const {
          'APPDATA': r'C:\Users\dov\AppData\Roaming',
          'ProgramData': r'C:\ProgramData',
        }).otzariaDataRoots(null),
        [r'C:\Users\dov\AppData\Roaming\otzaria', r'C:\ProgramData\otzaria'],
      );
    });

    test('אותם שורשים בדיוק כמו defaultDbDirs, פחות ה-books', () async {
      const env = {
        'APPDATA': r'C:\Users\dov\AppData\Roaming',
        'ProgramData': r'C:\ProgramData',
      };
      final roots = await locatorFor('windows', env).otzariaDataRoots(null);
      expect(
        LibraryDbLocator.defaultDbDirs(
          operatingSystem: 'windows',
          environment: env,
        ),
        [for (final root in roots) p.windows.join(root, 'books')],
      );
    });

    test('משתני סביבה חסרים לא מייצרים שורש שבור', () async {
      expect(
        await locatorFor('windows', const {'APPDATA': '', 'ProgramData': ''})
            .otzariaDataRoots(null),
        isEmpty,
      );
    });

    test('פלטפורמה לא מוכרת כן מנסה את XDG — בשונה מ-defaultDbDirs', () async {
      const env = {'HOME': '/home/dov'};
      expect(
        await locatorFor('fuchsia', env).otzariaDataRoots(null),
        ['/home/dov/.local/share/otzaria'],
      );
      expect(
        LibraryDbLocator.defaultDbDirs(
          operatingSystem: 'fuchsia',
          environment: env,
        ),
        isEmpty,
      );
    });

    test('linux: מיקום ה-XDG', () async {
      expect(
        await locatorFor('linux', const {'HOME': '/home/dov'})
            .otzariaDataRoots(null),
        ['/home/dov/.local/share/otzaria'],
      );
    });
  });
}
