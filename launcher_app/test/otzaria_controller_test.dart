import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

/// בדיקות ל-[OtzariaModuleController]. **כל** הבדיקות רצות תחת חסימת רשת
/// מלאה ([NoNetworkHttpOverrides]) — כך שכל מסלול בדיקה/התקנה שמצליח כאן
/// הוכיח בפועל שהוא קורא מהתיקייה המקומית בלבד (AGENTS §5).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-ctrl-');
    HttpOverrides.global = NoNetworkHttpOverrides();
    AppLogger.resetForTest();
    await AppLogger.init(tempDir.path);
  });

  tearDown(() async {
    HttpOverrides.global = null;
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  /// כותב מראה מקומית של תוכנת אוצריא: מטא-דאטה + קובצי התקנה בגודל תואם.
  void writeAppMirror({String? stableTag, String? prereleaseTag}) {
    final mirrorDir = p.join(tempDir.path, 'mirror', 'app');
    Directory(mirrorDir).createSync(recursive: true);

    Map<String, dynamic> entry(String tag, bool prerelease) {
      final relative = 'installers/$tag/otzaria-$tag.exe';
      final file = File(p.join(mirrorDir, p.joinAll(relative.split('/'))))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('installer for $tag');

      return {
        'tagName': tag,
        'name': 'אוצריא $tag',
        'isPrerelease': prerelease,
        'isDraft': false,
        'publishedAt': '2026-08-01T00:00:00.000Z',
        'installerKind': OtzariaInstallerKind.windowsSetupExe.name,
        'installerAssetName': 'otzaria-$tag.exe',
        'installerDownloadUrl': 'https://example.invalid/otzaria-$tag.exe',
        'installerSizeBytes': file.lengthSync(),
        'releaseNotes': 'מה התחדש ב-$tag',
        'installerPath': relative,
      };
    }

    File(p.join(mirrorDir, 'latest-release.json'))
        .writeAsStringSync(jsonEncode({
      'schemaVersion': 2,
      'syncedAt': '2026-08-01T00:00:00.000Z',
      if (stableTag != null) 'stable': entry(stableTag, false),
      if (prereleaseTag != null) 'prerelease': entry(prereleaseTag, true),
    }));
  }

  OtzariaModuleController controllerFor({bool preferPrerelease = false}) {
    final controller = OtzariaModuleController(
      dataDir: tempDir.path,
      preferPrerelease: preferPrerelease,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('checkForUpdate — מהתיקייה המקומית בלבד', () {
    test('מראה ריקה = needsDownload, וזה לא מצב שגיאה', () async {
      final c = controllerFor();

      await c.checkForUpdate();

      expect(c.status, OtzariaModuleStatus.needsDownload);
      expect(c.errorMessage, isNull);
      expect(c.latestVersion, isNull);
      expect(c.stableVersion, isNull);
      expect(c.prereleaseVersion, isNull);
      expect(c.hasChannelChoice, isFalse);
    });

    test('גרסה יציבה בתיקייה = יש מה להתקין, בלי רשת', () async {
      writeAppMirror(stableTag: '99.9.9+1');
      final c = controllerFor();

      await c.checkForUpdate();

      expect(c.status, OtzariaModuleStatus.updateAvailable);
      expect(c.latestVersion, '99.9.9+1');
      expect(c.stableVersion, '99.9.9+1');
      expect(c.prereleaseVersion, isNull);
      expect(c.hasChannelChoice, isFalse);
      // "מה התחדש" נקרא מהמטא-דאטה שנשמרה לצד קובץ ההתקנה.
      expect(c.latestReleaseNotes, 'מה התחדש ב-99.9.9+1');
    });

    test('קובץ התקנה חסר → המראה נחשבת ריקה, לא שגיאה', () async {
      writeAppMirror(stableTag: '99.9.9+1');
      File(p.join(tempDir.path, 'mirror', 'app', 'installers', '99.9.9+1',
              'otzaria-99.9.9+1.exe'))
          .deleteSync();
      final c = controllerFor();

      await c.checkForUpdate();

      expect(c.status, OtzariaModuleStatus.needsDownload);
      expect(c.errorMessage, isNull);
    });

    test('מטא-דאטה פגומה אינה מפילה את המסך', () async {
      Directory(p.join(tempDir.path, 'mirror', 'app'))
          .createSync(recursive: true);
      File(p.join(tempDir.path, 'mirror', 'app', 'latest-release.json'))
          .writeAsStringSync('{ לא JSON');
      final c = controllerFor();

      await c.checkForUpdate();

      expect(c.status, OtzariaModuleStatus.needsDownload);
      expect(c.errorMessage, isNull);
    });
  });

  group('שני ערוצים בתיקייה — הבחירה נעשית במחשב המנותק', () {
    test('שתי גרסאות = יש בחירה, וברירת המחדל היא היציבה', () async {
      writeAppMirror(stableTag: '1.0.0', prereleaseTag: '1.1.0-beta');
      final c = controllerFor();

      await c.checkForUpdate();

      expect(c.hasChannelChoice, isTrue);
      expect(c.stableVersion, '1.0.0');
      expect(c.prereleaseVersion, '1.1.0-beta');
      expect(c.latestVersion, '1.0.0');
    });

    test('החלפת ערוץ קוראת מהדיסק ואינה דורשת רשת', () async {
      writeAppMirror(stableTag: '1.0.0', prereleaseTag: '1.1.0-beta');
      final c = controllerFor();
      await c.checkForUpdate();

      // ה-setter מריץ בדיקה מחדש בעצמו (fire-and-forget), ולכן ממתינים
      // להודעה שבה היא הסתיימה במקום לקרוא לה שוב.
      final done = Completer<void>();
      void listener() {
        if (c.status != OtzariaModuleStatus.checking && !done.isCompleted) {
          done.complete();
        }
      }

      c.addListener(listener);
      c.preferPrerelease = true;
      await done.future;
      c.removeListener(listener);

      expect(c.preferPrerelease, isTrue);
      expect(c.latestVersion, '1.1.0-beta');
      expect(c.status, OtzariaModuleStatus.updateAvailable);
    });

    test('הצבת אותו ערך אינה משנה דבר', () async {
      final c = controllerFor();
      c.preferPrerelease = false;

      expect(c.preferPrerelease, isFalse);
    });

    test('רק pre-release בתיקייה = הוא הגרסה היחידה, בלי בחירה', () async {
      writeAppMirror(prereleaseTag: '2.0.0-rc1');
      final c = controllerFor();

      await c.checkForUpdate();

      expect(c.hasChannelChoice, isFalse);
      expect(c.latestVersion, '2.0.0-rc1');
      expect(c.stableVersion, isNull);
      expect(c.status, OtzariaModuleStatus.updateAvailable);
    });
  });

  group('התקנה ואימוץ', () {
    test('install לפני בדיקה אינו עושה דבר ואינו זורק', () async {
      final c = controllerFor();
      var notifications = 0;
      c.addListener(() => notifications++);

      await c.install();

      expect(c.status, OtzariaModuleStatus.idle);
      expect(notifications, 0);
    });

    test('adoptInstallDir על תיקייה בלי אוצריא מחזיר false בלי לזרוק',
        () async {
      final c = controllerFor();
      final empty = Directory(p.join(tempDir.path, 'not-otzaria'))
        ..createSync(recursive: true);

      expect(await c.adoptInstallDir(empty.path), isFalse);
      expect(c.errorMessage, isNull);
    });

    test('adoptInstallDir על נתיב שאינו קיים גם הוא מחזיר false', () async {
      final c = controllerFor();

      expect(
        await c.adoptInstallDir(p.join(tempDir.path, 'אין-כזו-תיקייה')),
        isFalse,
      );
    });

    test('canLaunch כבוי כל עוד לא זוהתה התקנה', () async {
      final c = controllerFor();
      await c.checkForUpdate();

      // אם על המכונה המריצה מותקנת אוצריא אמיתית, הזיהוי האוטומטי ימצא
      // אותה — ואז canLaunch דלוק בצדק. שני המצבים עקביים זה עם זה.
      expect(c.canLaunch, c.currentVersion != null);
    });
  });

  group('checkOnline — כשל רשת הוא מצב תקין', () {
    test('אין רשת: הכשל נבלע, נשמר, ואינו נוגע במצב המודול', () async {
      writeAppMirror(stableTag: '1.0.0');
      final c = controllerFor();
      await c.checkForUpdate();
      final statusBefore = c.status;

      await c.checkOnline();

      expect(c.onlineLatestRelease, isNull);
      expect(c.onlineCheckError, isNotNull);
      expect(c.onlineCheckedAt, isNotNull);
      expect(c.status, statusBefore);
      expect(c.errorMessage, isNull);
      // בלי גרסה מהרשת אין על מה להתריע.
      expect(c.hasOnlineUpdate, isFalse);
    });

    test('בדיקה חוזרת מנקה את השגיאה הקודמת לפני שהיא מנסה שוב', () async {
      final c = controllerFor();
      await c.checkOnline();
      expect(c.onlineCheckError, isNotNull);

      final errors = <String?>[];
      c.addListener(() => errors.add(c.onlineCheckError));
      await c.checkOnline();

      expect(errors.first, isNull, reason: 'ההודעה הראשונה היא איפוס');
      expect(errors.last, isNotNull);
    });
  });
}
