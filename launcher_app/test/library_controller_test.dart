import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'test_support.dart';

/// בדיקות ל-[LibraryModuleController], תחת חסימת רשת מלאה: מסלול הבדיקה
/// חייב לעבוד מהתיקייה המקומית בלבד, ו"אין מראה" הוא מצב תקין ולא שגיאה.
void main() {
  late Directory tempDir;
  late LibraryModuleController controller;

  /// קובץ DB מדומה שמוצבים עליו במפורש, כדי שהבדיקה לא תיגע ב-`seforim.db`
  /// האמיתי של מי שמריץ אותה.
  late File fakeDb;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library-ctrl-');
    fakeDb = File(p.join(tempDir.path, 'library', 'seforim.db'))
      ..parent.createSync(recursive: true)
      ..createSync();
    HttpOverrides.global = NoNetworkHttpOverrides();
    AppLogger.resetForTest();
    await AppLogger.init(tempDir.path);
    controller = LibraryModuleController(dataDir: tempDir.path);
  });

  tearDown(() async {
    controller.dispose();
    HttpOverrides.global = null;
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  group('checkForUpdate בלי מראה מקומית', () {
    test('אין מראה = needsDownload, לא שגיאה', () async {
      await controller.setCustomDbPath(fakeDb.path);

      expect(controller.status, LibraryModuleStatus.needsDownload);
      expect(controller.errorMessage, isNull);
      expect(controller.localVersion, isNull);
      expect(controller.targetVersion, isNull);
    });

    test('מסד אמיתי שנבחר ידנית — הגרסה מוצגת גם לפני שהורדה מראה', () async {
      // הדיווח שהוליד את הבדיקה: אחרי בחירה ידנית המסך הראה "לא ידוע",
      // כי הבדיקה קראה את הגרסה ואז נפלה על היעדר מראה.
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'picked', 18));

      expect(controller.status, LibraryModuleStatus.needsDownload);
      expect(controller.localVersion, 18);
    });

    test('נתיב ה-DB מתגלה ונשמר — לא מונח מראש', () async {
      await controller.setCustomDbPath(fakeDb.path);

      expect(controller.dbPath, fakeDb.path);
    });

    // מצב "עדכון אישי": נקודת המוצא נרשמת אך ורק בלחיצה, ולכן בדיקה שגרתית
    // חייבת להשאיר אותה ריקה — אחרת אוצריא שעל המחשב המקוון הייתה נקבעת
    // במקום זו של המחשב שבשבילו מורידים.
    test('בדיקה שגרתית אינה רושמת גרסה לעדכון אישי', () async {
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'auto', 18));

      expect(controller.localVersion, 18);
      expect(controller.personalFromVersion, isNull);
    });

    test('לחיצה על "זהה את גרסת המסד שלי" רושמת, ובדיקה חוזרת קוראת', () async {
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'picked', 18));

      expect(await controller.capturePersonalVersion(), isTrue);
      expect(controller.personalFromVersion, 18);

      // הרשומה יושבת בקובץ ה-state שנוסע על הכונן — ולכן שורדת בדיקה חדשה.
      await controller.checkForUpdate();
      expect(controller.personalFromVersion, 18);
    });

    test('לחיצה על מסד בלי db_version מדווחת כשל, ולא רושמת', () async {
      await controller.setCustomDbPath(fakeDb.path);

      expect(await controller.capturePersonalVersion(), isFalse);
      expect(controller.personalFromVersion, isNull);
    });

    test('update לפני בדיקה אינו עושה דבר', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.update();

      expect(notifications, 0);
      expect(controller.status, LibraryModuleStatus.idle);
    });
  });

  group('checkOnline — כשל רשת נבלע', () {
    test('אין חיבור: נשמר ב-onlineCheckError ואינו הופך לשגיאת מודול',
        () async {
      await controller.checkOnline();

      expect(controller.onlineLatestVersion, isNull);
      expect(controller.onlineCheckError, isNotNull);
      expect(controller.onlineCheckedAt, isNotNull);
      expect(controller.status, LibraryModuleStatus.idle);
      expect(controller.errorMessage, isNull);
      expect(controller.hasOnlineUpdate, isFalse);
    });

    test('hasOnlineUpdate כבוי כל עוד לא נבדק ברשת', () {
      controller.targetVersion = 5;

      expect(controller.hasOnlineUpdate, isFalse);
    });
  });

  group('downloadProgress — חישוב המד', () {
    test('בלי שום דיווח אין אחוז', () {
      expect(controller.downloadProgress, isNull);
    });

    test('בייטים בלבד (נכס אחד גדול) = היחס בתוך הנכס', () {
      controller.downloadReceivedBytes = 250;
      controller.downloadTotalBytes = 1000;

      expect(controller.downloadProgress, 0.25);
    });

    test('נכסים ובייטים יחד — הנכסים שהושלמו ועוד החלק היחסי', () {
      controller.downloadDoneAssets = 1;
      controller.downloadTotalAssets = 4;
      controller.downloadReceivedBytes = 500;
      controller.downloadTotalBytes = 1000;

      expect(controller.downloadProgress, closeTo(0.375, 1e-9));
    });

    test('סה"כ בייטים לא ידוע — מתקדם לפי ספירת הנכסים בלבד', () {
      controller.downloadDoneAssets = 2;
      controller.downloadTotalAssets = 4;

      expect(controller.downloadProgress, 0.5);
    });

    test('ערכים חריגים נחתכים ל-0..1 ואינם מפילים את המד', () {
      controller.downloadReceivedBytes = 5000;
      controller.downloadTotalBytes = 1000;
      expect(controller.downloadProgress, 1.0);

      controller.downloadTotalBytes = 0;
      expect(controller.downloadProgress, isNull);

      controller.downloadDoneAssets = 9;
      controller.downloadTotalAssets = 4;
      expect(controller.downloadProgress, 1.0);
    });
  });

  group('hasOnlineUpdate נמדד מול המראה', () {
    test('גרסה גבוהה יותר ברשת מדליקה, שווה/נמוכה מכבה', () {
      controller.onlineLatestVersion = 20;
      controller.targetVersion = 19;
      expect(controller.hasOnlineUpdate, isTrue);

      controller.targetVersion = 20;
      expect(controller.hasOnlineUpdate, isFalse);

      controller.targetVersion = 21;
      expect(controller.hasOnlineUpdate, isFalse);
    });

    test('בלי מראה בכלל, ההשוואה נופלת לגרסת המסד החי', () {
      controller.onlineLatestVersion = 20;
      controller.targetVersion = null;
      controller.localVersion = 20;

      expect(controller.hasOnlineUpdate, isFalse);
    });
  });

  /// עדכון מסד שנעשה כאן משאיר את אינדקס החיפוש של אוצריא על התוכן הישן,
  /// והסימון שלצד המסד הוא מה שמזכיר לנו לבקש ממנה לתקן. ראו AGENTS §5.
  group('בקשת עדכון האינדקס שממתינה', () {
    /// כותב סימון "אמיתי" — דרך אותו שירות שכותב אותו ב-`applyUpdate`.
    Future<void> writeNotice(
            {String route = ExternalUpdateNotice.routeDelta}) =>
        const ExternalUpdateNotice().write(
          dbPath: fakeDb.path,
          route: route,
          booksTouched: {4, 11},
          dbVersion: 30,
        );

    test('בלי סימון אין בקשה ממתינה', () async {
      await controller.setCustomDbPath(fakeDb.path);

      expect(controller.hasPendingReindex, isFalse);
      expect(controller.pendingReindex, isNull);
    });

    // הסימון יושב לצד המסד ולכן שורד הפעלה מחדש של הלאנצ'ר: בדיקה בעלייה
    // חייבת למצוא בקשה שנכתבה בהרצה קודמת ולא נמסרה.
    test('סימון מהרצה קודמת נקרא בבדיקה, ולא רק אחרי עדכון', () async {
      await writeNotice();

      await controller.setCustomDbPath(fakeDb.path);

      expect(controller.hasPendingReindex, isTrue);
      expect(controller.pendingReindex!.booksTouched, {4, 11});
      expect(controller.pendingReindex!.dbVersion, 30);
    });

    test('מסירה מוצלחת מוחקת את הסימון מהדיסק', () async {
      await writeNotice(route: ExternalUpdateNotice.routeFull);
      await controller.setCustomDbPath(fakeDb.path);
      expect(controller.hasPendingReindex, isTrue);

      await controller.markReindexRequestDelivered();

      expect(controller.hasPendingReindex, isFalse);
      expect(
        File(p.join(fakeDb.parent.path, ExternalUpdateNotice.fileName))
            .existsSync(),
        isFalse,
      );
      // ובדיקה חוזרת אינה מחזירה אותה לחיים.
      await controller.checkForUpdate();
      expect(controller.hasPendingReindex, isFalse);
    });

    test('סימון שלא נמסר נשאר גם אחרי בדיקה חוזרת', () async {
      await writeNotice();
      await controller.setCustomDbPath(fakeDb.path);

      await controller.checkForUpdate();

      expect(controller.hasPendingReindex, isTrue);
    });

    test('markReindexRequestDelivered בלי בקשה ממתינה אינו עושה דבר', () async {
      await controller.setCustomDbPath(fakeDb.path);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.markReindexRequestDelivered();

      expect(notifications, 0);
    });
  });
}

/// מסד sqlite אמיתי עם `db_version` — הקורא (`LocalDbVersionReader`) פותח
/// את הקובץ בפועל, ולכן קובץ ריק אינו מספיק.
String _dbWithVersion(Directory tempDir, String folder, int version) {
  final file = File(p.join(tempDir.path, folder, 'seforim.db'))
    ..parent.createSync(recursive: true);
  final db = sqlite3.sqlite3.open(file.path);
  db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
  db.execute("INSERT INTO schema_meta VALUES ('db_version', '$version')");
  db.close();
  return file.path;
}
