import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/online_check.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/progress_notifier.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

/// בדיקות לשתי תשתיות שהתנהגותן אינה נראית במסך: דילול דיווחי ההתקדמות,
/// וסדר/גודל הכתיבה ליומן הפעילות.
void main() {
  group('ProgressNotifier', () {
    test('סופר דיווחים רבים לכדי מעט הודעות, ומוסר את האחרון', () async {
      final notifier = _Counter();
      var notifications = 0;
      notifier.addListener(() => notifications++);

      // 1000 דיווחים באותו tick — כמו הורדה של 1GB בצ׳אנקים.
      for (var i = 1; i <= 1000; i++) {
        notifier.value = i;
      }

      // הראשון יוצא מיד; השאר מתקבצים.
      expect(notifications, 1);
      expect(notifier.lastSeen, 1);

      // אחרי חלון הדילול הערך האחרון נמסר — המד לא נשאר תקוע.
      await Future<void>.delayed(ProgressNotifier.interval * 2);
      expect(notifications, 2);
      expect(notifier.lastSeen, 1000);

      notifier.dispose();
    });

    test('דיווח אחרי dispose אינו מודיע ואינו זורק', () async {
      final notifier = _Counter();
      notifier.value = 1;
      notifier.value = 2; // משאיר טיימר תלוי
      notifier.dispose();

      await Future<void>.delayed(ProgressNotifier.interval * 2);
      // אין דרך "לתפוס" notifyListeners אחרי dispose חוץ מזה שהוא זורק —
      // הגעה לכאן בלי חריגה היא הבדיקה.
      expect(() => notifier.value = 3, returnsNormally);
    });
  });

  group('AppLogger', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('logger-test-');
      AppLogger.resetForTest();
    });
    tearDown(() async {
      // קודם flush: בווינדוס כתיבה שעוד באוויר נועלת את הקובץ, והמחיקה
      // נכשלת אחרי בדיקה שכבר עברה.
      await AppLogger.maybeInstance?.flush();
      AppLogger.resetForTest();
      await deleteTempDir(tmp);
    });

    File logFile() => File('${tmp.path}/logs/launcher.log');

    test('שורות שנרשמו באותו tick נכתבות בשלמותן ובסדר', () async {
      final logger = await AppLogger.init(tmp.path);
      for (var i = 0; i < 200; i++) {
        logger.info('שורה $i');
      }
      await logger.flush();

      final lines = logFile()
          .readAsLinesSync()
          .where((l) => l.contains('שורה '))
          .toList();
      expect(lines, hasLength(200));
      for (var i = 0; i < 200; i++) {
        expect(lines[i], endsWith('שורה $i'));
      }
    });

    test('maybeInstance הוא null לפני init ואינו זורק', () {
      expect(AppLogger.maybeInstance, isNull);
      expect(() => AppLogger.instance, throwsStateError);
    });

    test('קובץ שחרג מ-maxBytes מתגלגל ל-.1 ומתחיל מחדש', () async {
      final logger = await AppLogger.init(tmp.path);
      await logger.flush();

      // מנפחים את הקובץ ישירות ולא דרך הלוגר — כתיבת 2MB דרכו הייתה מציפה
      // את פלט הבדיקות (ב-debug כל שורה גם מודפסת) בלי להוסיף כיסוי.
      logFile().writeAsStringSync(
        'x' * (AppLogger.maxBytes + 1),
        mode: FileMode.append,
      );

      logger.info('אחרי הגלגול');
      await logger.flush();

      expect(File('${logFile().path}.1').existsSync(), isTrue);
      expect(logFile().lengthSync(), lessThan(AppLogger.maxBytes));
      expect(logFile().readAsStringSync(), contains('אחרי הגלגול'));
    });

    test('גלגול שני דורס את הקובץ הישן — לא נצברים קבצים בלי גבול', () async {
      final logger = await AppLogger.init(tmp.path);
      File('${logFile().path}.1').writeAsStringSync('גלגול קודם');

      logFile().writeAsStringSync(
        'y' * (AppLogger.maxBytes + 1),
        mode: FileMode.append,
      );
      logger.info('אחרי הגלגול השני');
      await logger.flush();

      final rolled = File('${logFile().path}.1').readAsStringSync();
      expect(rolled, isNot(contains('גלגול קודם')));
      expect(Directory(p.dirname(logFile().path)).listSync(), hasLength(2));
    });

    test('error רושם רמה, חריג ו-stack trace מלא', () async {
      final logger = await AppLogger.init(tmp.path);

      logger.error('נכשל', StateError('הסיבה'), StackTrace.current);
      logger.warn('אזהרה');
      await logger.flush();

      final content = logFile().readAsStringSync();
      expect(content, contains('[ERROR] נכשל'));
      expect(content, contains('error: Bad state: הסיבה'));
      expect(content, contains('infra_test.dart'));
      expect(content, contains('[WARN] אזהרה'));
    });

    test('filePath ו-logDir מצביעים על <dataDir>/logs', () async {
      final logger = await AppLogger.init(tmp.path);

      expect(logger.logDir, p.join(tmp.path, 'logs'));
      expect(logger.filePath, p.join(logger.logDir, 'launcher.log'));
    });
  });

  group('hasOnlineUpdate נמדד מול המראה, לא מול המותקן', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('otzaria-'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('אוצריא: הורדה מכבה את ההודעה גם כשההתקנה עוד ישנה', () {
      final c = OtzariaModuleController(dataDir: tempDir.path);
      c.onlineLatestRelease = const OtzariaRelease(
        tagName: '0.9.96+736',
        name: 'אוצריא 0.9.96',
        isPrerelease: false,
        isDraft: false,
        publishedAt: null,
        installerKind: OtzariaInstallerKind.windowsSetupExe,
        installerAssetName: 'setup.exe',
        installerDownloadUrl: 'https://example.invalid/setup.exe',
        installerSizeBytes: 1,
      );

      // לפני ההורדה אין במראה כלום — יש מה להביא מהרשת.
      expect(c.hasOnlineUpdate, isTrue);

      // אחרי ההורדה המראה מחזיקה את הגרסה שברשת, וההתקנה עדיין ישנה:
      // אין מה להוריד יותר, גם אם יש עוד מה להתקין.
      c.latestVersion = '0.9.96+736';
      c.currentVersion = '0.9.90';
      expect(c.hasOnlineUpdate, isFalse);

      // גרסה חדשה יותר ברשת מדליקה את ההודעה מחדש.
      c.latestVersion = '0.9.95';
      expect(c.hasOnlineUpdate, isTrue);

      c.dispose();
    });

    test('ספרייה: ההשוואה היא מול גרסת המראה ולא מול המסד החי', () {
      final c = LibraryModuleController(dataDir: tempDir.path);
      c.onlineLatestVersion = 20;

      expect(c.hasOnlineUpdate, isTrue);

      // המראה עודכנה ל-20 בעוד המסד החי נשאר על 17.
      c.targetVersion = 20;
      c.localVersion = 17;
      expect(c.hasOnlineUpdate, isFalse);

      c.dispose();
    });
  });

  group('provenUpToDateOnline — מתי מותר לדלג על הורדה', () {
    final checkedAt = DateTime(2026, 8, 13);

    test('נבדק בהצלחה ואין חדש — מדלגים', () {
      expect(
        provenUpToDateOnline(
          checkedAt: checkedAt,
          error: null,
          hasUpdate: false,
        ),
        isTrue,
      );
    });

    test('יש עדכון — לא מדלגים', () {
      expect(
        provenUpToDateOnline(
          checkedAt: checkedAt,
          error: null,
          hasUpdate: true,
        ),
        isFalse,
      );
    });

    test('הבדיקה לא רצה — אין הוכחה, ולכן מורידים', () {
      expect(
        provenUpToDateOnline(checkedAt: null, error: null, hasUpdate: false),
        isFalse,
      );
    });

    test('הבדיקה נכשלה — "אין רשת" אינו "אין עדכון"', () {
      expect(
        provenUpToDateOnline(
          checkedAt: checkedAt,
          error: 'אין חיבור',
          hasUpdate: false,
        ),
        isFalse,
      );
    });
  });
}

/// ChangeNotifier מינימלי שמדווח דרך [ProgressNotifier.notifyProgress].
class _Counter extends ChangeNotifier with ProgressNotifier {
  int _value = 0;
  int lastSeen = 0;

  set value(int next) {
    _value = next;
    notifyProgress();
  }

  _Counter() {
    addListener(() => lastSeen = _value);
  }
}
