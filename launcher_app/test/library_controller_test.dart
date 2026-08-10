import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:path/path.dart' as p;

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

    test('נתיב ה-DB מתגלה ונשמר — לא מונח מראש', () async {
      await controller.setCustomDbPath(fakeDb.path);

      expect(controller.dbPath, fakeDb.path);
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
}
