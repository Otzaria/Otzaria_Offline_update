import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/screens/home/home_view_model.dart'
    show whatsNewAppNotes;
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
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

  void writeAppMirror({
    String? stableTag,
    String? prereleaseTag,
    bool staleFullOnDrive = false,
    bool arm64Checked = true,
    OtzariaInstallerKind installerKind = OtzariaInstallerKind.windowsSetupExe,
  }) {
    final mirrorDir = p.join(tempDir.path, 'mirror', 'app');
    Directory(mirrorDir).createSync(recursive: true);

    Map<String, dynamic> entry(String tag, bool prerelease) {
      final relative = 'installers/$tag/otzaria-$tag.exe';
      final file = File(p.join(mirrorDir, p.joinAll(relative.split('/'))))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('installer for $tag');

      if (staleFullOnDrive && !prerelease) {
        final stale = 'installers/$tag/otzaria-$tag-windows-full.exe';
        File(p.join(mirrorDir, p.joinAll(stale.split('/'))))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('full installer bytes');
      }

      return {
        'tagName': tag,
        'name': 'אוצריא $tag',
        'isPrerelease': prerelease,
        'isDraft': false,
        'publishedAt': '2026-08-01T00:00:00.000Z',
        'installerKind': installerKind.name,
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
      if (arm64Checked)
        'platforms': {
          'windows_arm64': {
            'missingAssetTags': [
              if (stableTag != null) stableTag,
              if (prereleaseTag != null) prereleaseTag,
            ],
          },
        },
    }));
  }

  OtzariaModuleController controllerFor({
    bool preferPrerelease = false,
    RunningOtzariaLocator runningLocator = const _NeverRunningLocator(),
    OtzariaTargetPlatform platform = OtzariaTargetPlatform.windows,
  }) {
    final controller = OtzariaModuleController(
      dataDir: tempDir.path,
      preferPrerelease: preferPrerelease,
      runningLocator: runningLocator,
      platform: platform,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  final hostInstallerKind = Platform.isMacOS
      ? OtzariaInstallerKind.macAppZip
      : OtzariaInstallerKind.windowsSetupExe;
  final hostPlatform = Platform.isMacOS
      ? OtzariaTargetPlatform.macos
      : OtzariaTargetPlatform.windows;

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

    test('ensureChecked מצטרפת לבדיקה שכבר רצה, ולא מריצה שנייה', () async {
      writeAppMirror(stableTag: '99.9.9+1');
      final c = controllerFor();

      // בעלייה שתי הקריאות יוצאות יחד: המקומית מ-`checkAll`, וההצצה ברשת
      // דרך `ensureChecked`. השנייה חייבת לחכות לראשונה ולא לפתוח סריקה
      // מקבילה על אותו כונן.
      final both = Future.wait([c.checkForUpdate(), c.ensureChecked()]);
      expect(c.stableVersion, isNull);
      await both;

      expect(c.stableVersion, '99.9.9+1');

      // ומשיש תשובה, ההמתנה הבאה חוזרת מיד בלי לגעת בדיסק.
      c.stableVersion = null;
      await c.ensureChecked();
      expect(c.stableVersion, isNull);
    });

    test(
        'checkForUpdate שיוצאת בזמן ש-ensureChecked כבר רצה מצטרפת אליה, '
        'ולא פותחת סריקה מקבילה', () async {
      writeAppMirror(stableTag: '99.9.9+1');
      final c = controllerFor();

      // סדר הפוך מהבדיקה הקודמת — וזה בדיוק סדר הקריאות שקרס בפועל
      // בעלייה: `ensureChecked` (מ-`PluginsModuleController`) יוצאת ראשונה,
      // ו-`checkForUpdate` (מ-`checkAll`) מגיעה בזמן שהיא כבר באוויר. שתי
      // בדיקות מקבילות היו כותבות בו-זמנית לאותו `.tmp` ב-state store,
      // וה-rename של אחת מהן נופל עם `PathNotFoundException`.
      final both = Future.wait([c.ensureChecked(), c.checkForUpdate()]);
      await both;

      expect(c.status, isNot(OtzariaModuleStatus.error));
      expect(c.errorMessage, isNull);
      expect(c.stableVersion, '99.9.9+1');
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

    test('החלפת ערוץ בזמן שבדיקה רצה מריצה אותה שוב בערוץ החדש', () async {
      writeAppMirror(
        stableTag: '1.0.0',
        prereleaseTag: '1.1.0-beta',
        installerKind: hostInstallerKind,
      );
      final locator = _GatedLocator();
      final c = controllerFor(runningLocator: locator, platform: hostPlatform);

      final check = c.checkForUpdate();
      final firstProbe = await locator.next();
      c.preferPrerelease = true;
      firstProbe.complete(false);
      (await locator.next()).complete(false);
      await check;

      expect(c.latestVersion, '1.1.0-beta');
      expect(c.status, OtzariaModuleStatus.updateAvailable);
      expect(locator.requested, 2);
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

    // החלטת המשתמש: מעבר ליציבה לא מתקין גרסה ישנה — מחכים ליציבה חדשה.
    test('מותקנת ניסיונית חדשה ובוחרים יציבה — אין עדכון, ממתינים', () async {
      writeAppMirror(stableTag: '1.0.0', prereleaseTag: '1.1.0-beta');
      final install = Directory(p.join(tempDir.path, 'Otzaria'))
        ..createSync(recursive: true);
      final exe = File(p.join(install.path, 'otzaria.exe'))
        ..writeAsStringSync('exe');
      File(p.join(tempDir.path, 'otzaria_install_state.json'))
          .writeAsStringSync(jsonEncode(OtzariaInstallState(
        installedTagName: '1.1.0-beta',
        installDir: install.path,
        launchPath: exe.path,
      ).toJson()));
      final c = controllerFor();

      await c.checkForUpdate();

      expect(c.currentVersion, '1.1.0-beta');
      expect(c.latestVersion, '1.0.0');
      expect(c.status, OtzariaModuleStatus.installedIsNewer);
      expect(c.awaitsNewerInSelectedChannel, isTrue);
    });
  });

  group('"מה חדש" בבית', () {
    void installed(String tag) {
      final install = Directory(p.join(tempDir.path, 'Otzaria'))
        ..createSync(recursive: true);
      final exe = File(p.join(install.path, 'otzaria.exe'))
        ..writeAsStringSync('exe');
      File(p.join(tempDir.path, 'otzaria_install_state.json'))
          .writeAsStringSync(jsonEncode(OtzariaInstallState(
        installedTagName: tag,
        installDir: install.path,
        launchPath: exe.path,
      ).toJson()));
    }

    test('אין עדכון — ההערות של הגרסה המותקנת, גם מהערוץ השני', () async {
      writeAppMirror(stableTag: '1.0.0', prereleaseTag: '1.1.0-beta');
      installed('1.1.0-beta');
      final c = controllerFor();
      await c.checkForUpdate();

      expect(c.status, OtzariaModuleStatus.installedIsNewer);
      expect(c.installedReleaseNotes, 'מה התחדש ב-1.1.0-beta');
      final notes = whatsNewAppNotes(c)!;
      expect(notes.installed, isTrue);
      expect(notes.version, '1.1.0-beta');
    });

    test('יש עדכון בכונן — ההערות שלו, לא של המותקנת', () async {
      writeAppMirror(stableTag: '1.1.0');
      installed('1.0.0');
      final c = controllerFor();
      await c.checkForUpdate();

      expect(c.status, OtzariaModuleStatus.updateAvailable);
      expect(c.installedReleaseNotes, isNull);
      final notes = whatsNewAppNotes(c)!;
      expect(notes.installed, isFalse);
      expect(notes.version, '1.1.0');
      expect(notes.notes, 'מה התחדש ב-1.1.0');
    });

    test('גרסה מותקנת שאינה בכונן — אין הערות', () async {
      writeAppMirror(stableTag: '1.0.0');
      installed('0.9.0');
      final c = controllerFor();
      await c.checkForUpdate();
      c.status = OtzariaModuleStatus.upToDate;

      expect(c.installedReleaseNotes, isNull);
      expect(whatsNewAppNotes(c), isNull);
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

    test(
      'בדיקה והחלפת ערוץ באמצע התקנה אינן דורסות את מצב ההתקנה, '
      'והתקנה שנייה אינה יוצאת',
      () async {
        writeAppMirror(
          stableTag: '1.0.0',
          prereleaseTag: '1.1.0-beta',
          installerKind: OtzariaInstallerKind.macAppZip,
        );
        final locator = _GatedLocator();
        final c = controllerFor(
          runningLocator: locator,
          platform: OtzariaTargetPlatform.macos,
        );
        final initial = c.checkForUpdate();
        (await locator.next()).complete(false);
        await initial;
        expect(c.status, OtzariaModuleStatus.updateAvailable);

        final install = c.install(useWizard: false);
        final installProbe = await locator.next();
        expect(c.status, OtzariaModuleStatus.installing);

        unawaited(c.checkForUpdate());
        c.preferPrerelease = true;
        unawaited(c.install(useWizard: false));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(c.status, OtzariaModuleStatus.installing);
        expect(locator.requested, 2);

        installProbe.complete(true);
        await install;
        expect(c.status, OtzariaModuleStatus.error);
        expect(c.errorMessage, isNotNull);

        final retry = c.checkForUpdate();
        (await locator.next()).complete(false);
        await retry;

        expect(c.status, OtzariaModuleStatus.updateAvailable);
        expect(c.errorMessage, isNull);
        expect(c.latestVersion, '1.1.0-beta');
      },
      testOn: 'mac-os',
    );

    test(
      'התקנה שנפתחת בזמן בדיקה ממתינה לה, ושגיאת ההתקנה נשארת',
      () async {
        writeAppMirror(
          stableTag: '1.0.0',
          installerKind: OtzariaInstallerKind.macAppZip,
        );
        final locator = _GatedLocator();
        final c = controllerFor(
          runningLocator: locator,
          platform: OtzariaTargetPlatform.macos,
        );
        final initial = c.checkForUpdate();
        (await locator.next()).complete(false);
        await initial;
        expect(c.status, OtzariaModuleStatus.updateAvailable);

        final check = c.checkForUpdate();
        final checkProbe = await locator.next();
        final install = c.install(useWizard: false);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(c.status, OtzariaModuleStatus.checking);
        expect(locator.requested, 2);

        checkProbe.complete(false);
        await check;
        (await locator.next()).complete(true);
        await install;
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(c.status, OtzariaModuleStatus.error);
        expect(c.errorMessage, isNotNull);
        expect(locator.requested, 3);
      },
      testOn: 'mac-os',
    );

    test('התקנה שהסתיימה ואוצריא לא נמצאה — הבית יציע בחירת תיקייה', () async {
      writeAppMirror(stableTag: '1.0.0', installerKind: hostInstallerKind);
      final c = OtzariaModuleController(
        dataDir: tempDir.path,
        runningLocator: const _NeverRunningLocator(),
        manager: _NotDetectedManager(tempDir.path),
      );
      addTearDown(c.dispose);
      await c.checkForUpdate();
      expect(c.status, OtzariaModuleStatus.updateAvailable);

      await c.install(useWizard: false);

      expect(c.status, OtzariaModuleStatus.error);
      expect(c.installNotDetected, isTrue);
      expect(c.errorMessage, 'not detected');

      // בדיקה חוזרת מוחקת את הסימן — שגיאה אחרת אינה מציעה את התיקייה.
      await c.checkForUpdate();
      expect(c.installNotDetected, isFalse);
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

  /// בקשת עדכון האינדקס (`otzaria://library/reindex`) נוסעת עם ההפעלה
  /// הרגילה של אוצריא, ונמחקת **רק** אחרי שנמסרה בפועל.
  ///
  /// כל הבדיקות כאן מזריקות `OtzariaLauncher` מדומה: בלעדיו הן מפעילות את
  /// אוצריא האמיתית של מי שמריץ אותן, ואף מבקשות ממנה אינדוקס.
  group('קישור עומק שממתין להפעלה', () {
    /// התקנה שהזיהוי האוטומטי ימצא: התיקייה המנוהלת של הלאנצ'ר נבדקת
    /// **ראשונה**, לפני ברירות המחדל והרג׳יסטרי, ולכן היא מנצחת גם על מכונה
    /// שאוצריא אמיתית מותקנת בה.
    /// התקנה מנוהלת מזויפת בתיקייה שהלאנצ'ר מחפש בה ראשונה.
    ///
    /// חייב להיות exe עם version resource אמיתי: `detectExistingInstall`
    /// מחזיר null כשהוא לא מצליח לקרוא גרסה, ואז `launch()` נופל על "לא
    /// נמצאה התקנה" — מה שקרה ב-CI, בזמן שאצל מפתח עם אוצריא אמיתית במכונה
    /// הזיהוי הצליח דרכה והבדיקה עברה מהסיבה הלא נכונה. `notepad.exe` הוא
    /// אותו תחליף שכבר משמש ב-`otzaria_manager/test/installed_version_reader_test.dart`.
    bool writeManagedInstall() {
      final source = File(r'C:\Windows\System32\notepad.exe');
      if (!source.existsSync()) {
        markTestSkipped('אין notepad.exe במכונה הזאת');
        return false;
      }
      final dir = Directory(p.join(tempDir.path, 'otzaria-app'))
        ..createSync(recursive: true);
      source.copySync(p.join(dir.path, 'otzaria.exe'));
      return true;
    }

    ({
      OtzariaModuleController controller,
      _RecordingLauncher launcher,
      List<bool> delivered,
    }) controllerWith({
      String? uri = OtzariaDeepLinks.libraryReindex,
      bool launchFails = false,
      bool libraryApplying = false,
    }) {
      final launcher = _RecordingLauncher(fails: launchFails);
      final delivered = <bool>[];
      final controller = OtzariaModuleController(
        dataDir: tempDir.path,
        runningLocator: const _NeverRunningLocator(),
        launcher: launcher,
        pendingLaunchUri: () async => uri,
        onLaunchUriDelivered: () async => delivered.add(true),
        isLibraryApplying: () => libraryApplying,
      );
      addTearDown(controller.dispose);
      return (controller: controller, launcher: launcher, delivered: delivered);
    }

    test(
      'הפעלה רגילה מוסרת את הבקשה הממתינה ומסמנת אותה כנמסרה',
      () async {
        if (!writeManagedInstall()) return;
        final t = controllerWith();

        await t.controller.launch();

        expect(t.launcher.uris, [OtzariaDeepLinks.libraryReindex]);
        expect(t.delivered, [true]);
        expect(t.controller.errorMessage, isNull);
      },
      testOn: 'windows',
    );

    test(
      'בזמן עדכון ספרייה אין הפעלה, והבקשה הממתינה אינה נמחקת',
      () async {
        if (!writeManagedInstall()) return;
        final t = controllerWith(libraryApplying: true);
        await t.controller.checkForUpdate();

        expect(t.controller.canLaunch, isFalse);
        await t.controller.launch();
        expect(await t.controller.requestLibraryReindex(), isFalse);

        expect(t.launcher.uris, isEmpty);
        expect(t.delivered, isEmpty);
        expect(
          t.controller.noticeMessage,
          AppL10n.strings.home.libraryApplyActive,
        );
      },
      testOn: 'windows',
    );

    test(
      'בזמן עדכון ספרייה אין גם התקנה של אוצריא',
      () async {
        if (!writeManagedInstall()) return;
        final t = controllerWith(libraryApplying: true);
        await t.controller.checkForUpdate();

        await t.controller.install();

        expect(t.controller.status, isNot(OtzariaModuleStatus.installing));
        expect(
          t.controller.noticeMessage,
          AppL10n.strings.home.libraryApplyActive,
        );
      },
      testOn: 'windows',
    );

    test(
      'בלי בקשה ממתינה ההפעלה נשארת הפעלה רגילה',
      () async {
        if (!writeManagedInstall()) return;
        final t = controllerWith(uri: null);

        await t.controller.launch();

        expect(t.launcher.uris, [null]);
        expect(t.delivered, isEmpty);
      },
      testOn: 'windows',
    );

    // הרגרסיה שהבדיקה הזאת שומרת עליה: סימון "נמסר" על הפעלה שנכשלה היה
    // מוחק את הבקשה, והאינדקס היה נשאר על התוכן הישן בלי שאיש יידע.
    test(
      'הפעלה שנכשלה אינה מסמנת את הבקשה כנמסרה',
      () async {
        if (!writeManagedInstall()) return;
        final t = controllerWith(launchFails: true);

        final error = await t.controller.launch();

        expect(t.delivered, isEmpty);
        expect(t.controller.errorMessage, isNotNull);
        expect(error, t.controller.errorMessage);
        expect(error, 'הפעלה מדומה שנכשלה');
      },
      testOn: 'windows',
    );

    test(
      'requestLibraryReindex מוסר את הקישור גם בלי לחכות להפעלה הבאה',
      () async {
        if (!writeManagedInstall()) return;
        final t = controllerWith();

        expect(await t.controller.requestLibraryReindex(), isTrue);

        expect(t.launcher.uris, [OtzariaDeepLinks.libraryReindex]);
        // הסימון עצמו נמחק ב-`AppSession`, אחרי ה-true הזה.
        expect(t.delivered, isEmpty);
      },
      testOn: 'windows',
    );

    test('requestLibraryReindex מחזיר false ומנסח סיבה כשהמסירה נכשלה',
        () async {
      final t = controllerWith(launchFails: true);

      expect(await t.controller.requestLibraryReindex(), isFalse);
      expect(t.controller.errorMessage, isNotNull);
    });

    test('בדיקה שהצליחה מנקה שגיאה קודמת', () async {
      final t = controllerWith(launchFails: true);
      await t.controller.launch();
      expect(t.controller.errorMessage, isNotNull);

      await t.controller.checkForUpdate();

      expect(t.controller.status, isNot(OtzariaModuleStatus.error));
      expect(t.controller.errorMessage, isNull);
    });
  });

  group('refreshRunningState — סגירה של אוצריא מזוהה בלי בדיקה מלאה', () {
    test('הרענון מעדכן את isRunning, מודיע, ומחזיר את הערך הטרי', () async {
      final locator = _ScriptedLocator([true, false]);
      final c = OtzariaModuleController(
        dataDir: tempDir.path,
        runningLocator: locator,
      );
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);

      expect(await c.refreshRunningState(), isTrue);
      expect(c.isRunning, isTrue);

      // בדיוק המסלול שנשבר: אוצריא נסגרה, והלאנצ'ר ממשיך לרוץ.
      expect(await c.refreshRunningState(), isFalse);
      expect(c.isRunning, isFalse);
      expect(notifications, 2);
    });

    test('בדיקה חוזרת ללא שינוי אינה מודיעה — הרענון חוזר כל 3 שניות',
        () async {
      final locator = _ScriptedLocator([true, true, true]);
      final c = OtzariaModuleController(
        dataDir: tempDir.path,
        runningLocator: locator,
      );
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);

      for (var i = 0; i < 3; i++) {
        expect(await c.refreshRunningState(), isTrue);
      }

      // רק המעבר false→true מודיע; שתי הדגימות הבאות זהות לו.
      expect(notifications, 1);
    });

    test('שני קוראים בו-זמנית = בדיקת תהליך אחת, ושניהם מקבלים את שלה',
        () async {
      // התשובה `true` שונה מ-`isRunning` ההתחלתי, ולכן מימוש שמחזיר למצטרף
      // את הערך הלכוד במקום את תוצאת הבדיקה — נופל כאן.
      final locator = _ScriptedLocator([true]);
      final c = OtzariaModuleController(
        dataDir: tempDir.path,
        runningLocator: locator,
      );
      addTearDown(c.dispose);

      final both = await Future.wait([
        c.refreshRunningState(),
        c.refreshRunningState(),
      ]);

      expect(locator.probes, 1);
      expect(both, [true, true]);
    });

    test('force מקבל בדיקה חדשה, ולא את זו שהייתה באוויר', () async {
      // המסלול שלפני פעולה חוסמת: אוצריא נפתחה אחרי שהדגימה המחזורית יצאה,
      // והצטרפות אליה הייתה מאשרת עדכון מסד תחת אוצריא פתוחה.
      final locator = _ScriptedLocator([false, true]);
      final c = OtzariaModuleController(
        dataDir: tempDir.path,
        runningLocator: locator,
      );
      addTearDown(c.dispose);

      final joined = c.refreshRunningState();
      final forced = c.refreshRunningState(force: true);

      expect(await joined, isFalse);
      expect(await forced, isTrue);
      expect(locator.probes, 2);
    });

    test('שחרור באמצע בדיקה אינו זורק', () async {
      final c = OtzariaModuleController(
        dataDir: tempDir.path,
        runningLocator: _ScriptedLocator([true]),
      );

      final probe = c.refreshRunningState();
      c.dispose();

      // `notifyListeners` אחרי dispose זורק — הבדיקה המחזורית יכולה בקלות
      // להסתיים אחרי סגירת החלון.
      await expectLater(probe, completes);
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

    // ניקוי בתחילה הפך כשל ל"מחובר, מעודכן" בבית עד שהבדיקה חזרה.
    test('בדיקה חוזרת שומרת את הכשל הקודם עד שהתשובה החדשה מגיעה', () async {
      final c = controllerFor();
      await c.checkOnline();
      expect(c.onlineCheckError, isNotNull);

      final errors = <String?>[];
      c.addListener(() => errors.add(c.onlineCheckError));
      await c.checkOnline();

      expect(errors, isNotEmpty);
      expect(errors, everyElement(isNotNull));
    });
  });

  group('onlineDownloadBytes — מה ההורדה צפויה להביא', () {
    OtzariaRelease release(String tag, int size, {bool pre = false}) =>
        OtzariaRelease(
          tagName: tag,
          name: tag,
          isPrerelease: pre,
          isDraft: false,
          publishedAt: null,
          installerKind: OtzariaInstallerKind.windowsSetupExe,
          installerAssetName: 'otzaria-$tag.exe',
          installerDownloadUrl: 'https://example.invalid/$tag',
          installerSizeBytes: size,
        );

    test('רק מתקינים שהתג שלהם אינו בכונן; בלי בדיקה — לא ידוע', () async {
      writeAppMirror(stableTag: '1.0.0');
      final c = controllerFor();
      await c.checkForUpdate();
      expect(c.onlineDownloadBytes, isNull);

      c.onlineChannels = OtzariaChannelReleases(
        stable: release('1.0.0', 100),
        prerelease: release('1.1.0', 250, pre: true),
      );
      expect(c.onlineDownloadBytes, 250);

      c.onlineChannels = OtzariaChannelReleases(stable: release('1.0.0', 100));
      expect(c.onlineDownloadBytes, isNull, reason: 'הכול כבר בכונן');
    });
  });

  group('download — משתמשת בתוצאת הבדיקה הקלה כשהיא טרייה', () {
    OtzariaChannelReleases cachedOnline(String tag) {
      const bytes = 'installer bytes';
      final assetName = 'otzaria-$tag.exe';
      File(p.join(tempDir.path, 'mirror', 'app', 'installers', tag, assetName))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(bytes);
      return OtzariaChannelReleases(
        stable: OtzariaRelease(
          tagName: tag,
          name: 'אוצריא $tag',
          isPrerelease: false,
          isDraft: false,
          publishedAt: DateTime.utc(2026, 8, 1),
          installerKind: OtzariaInstallerKind.windowsSetupExe,
          installerAssetName: assetName,
          installerDownloadUrl: 'https://example.invalid/$assetName',
          installerSizeBytes: bytes.length,
        ),
      );
    }

    test('בדיקה טרייה: ההורדה אינה שולפת שוב את רשימת ה-releases', () async {
      final c = controllerFor();
      c.onlineChannels = cachedOnline('1.0.0');
      c.onlineCheckedAt = DateTime.now();

      await c.download();

      expect(c.downloadError, isNull);
      expect(c.downloadStatus, OtzariaDownloadStatus.done);
    });

    test('בדיקה ישנה אינה משמשת: ההורדה פונה לרשת מחדש', () async {
      final c = controllerFor();
      c.onlineChannels = cachedOnline('1.0.0');
      c.onlineCheckedAt = DateTime.now().subtract(const Duration(minutes: 11));

      await c.download();

      expect(c.downloadStatus, OtzariaDownloadStatus.error);
    });
  });

  test('מראה שלא נבדקה בה ARM64 מחייבת את מודול התוכנה לרוץ', () async {
    writeAppMirror(stableTag: '0.9.96', arm64Checked: false);
    final c = controllerFor();
    await c.checkForUpdate();

    expect(c.hasStaleFullPackage, isTrue);
  }, testOn: 'windows');

  group('חבילת FULL שנשארה מגרסה ישנה', () {
    test('מראה רגילה — אין מה לנקות', () async {
      writeAppMirror(stableTag: '0.9.96');
      final c = controllerFor();
      await c.checkForUpdate();

      expect(c.hasStaleFullPackage, isFalse);
    });

    test('קובץ FULL על הכונן מדליק את הדגל', () async {
      writeAppMirror(stableTag: '0.9.96', staleFullOnDrive: true);
      final c = controllerFor();
      await c.checkForUpdate();

      // זה מה שמבטל את הדילוג על מודול התוכנה ב-`DownloadPlan.shouldSkipApp`,
      // ולכן מה שגורם ל-2GB באמת להימחק.
      expect(c.hasStaleFullPackage, isTrue);
    });
  });
}

/// קולט מה נמסר להפעלה במקום להריץ תהליך אמיתי — ובעיקר: במקום להפעיל את
/// אוצריא של מי שמריץ את הבדיקות ולבקש ממנה אינדוקס.
class _RecordingLauncher extends OtzariaLauncher {
  _RecordingLauncher({this.fails = false});

  final bool fails;
  final List<String?> uris = [];

  @override
  Future<void> launch(String launchPath, {String? withUri}) async {
    uris.add(withUri);
    if (fails) throw OtzariaUserError('הפעלה מדומה שנכשלה');
  }
}

/// "אוצריא סגורה", בלי לגעת בתהליכים של המכונה — ראו [controllerFor].
class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}

/// מחזיר תשובה שונה בכל בדיקה, לפי התסריט — כך אפשר לדמות "אוצריא הייתה
/// פתוחה ואז נסגרה" בלי תהליך אמיתי.
class _ScriptedLocator extends RunningOtzariaLocator {
  _ScriptedLocator(this._answers);

  final List<bool> _answers;
  int probes = 0;

  @override
  Future<RunningOtzariaProbe> probe() async {
    // בכוונה בלי clamp: שכפול שקט של התשובה האחרונה היה מסתיר בדיקה שהתחילה
    // לדגום יותר פעמים מכפי שהתסריט מתאר.
    final answer = _answers[probes];
    probes++;
    return (isRunning: answer, launchPath: null);
  }
}

class _GatedLocator extends RunningOtzariaLocator {
  final List<Completer<bool>> _probes = [];
  int _handedOut = 0;

  int get requested => _probes.length;

  @override
  Future<RunningOtzariaProbe> probe() async {
    final answer = Completer<bool>();
    _probes.add(answer);
    return (isRunning: await answer.future, launchPath: null);
  }

  Future<Completer<bool>> next() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (_probes.length <= _handedOut) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('no probe #${_handedOut + 1} was requested');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return _probes[_handedOut++];
  }
}

/// מנהל שההתקנה שלו "הסתיימה" בלי שאוצריא נמצאה — בלי מתקין אמיתי.
class _NotDetectedManager extends OtzariaManager {
  _NotDetectedManager(String dataDir)
      : super(dataDir: dataDir, runningLocator: const _NeverRunningLocator());

  @override
  Future<OtzariaInstallState> update(
    OtzariaUpdateCheckResult check, {
    bool useWizard = false,
    void Function()? onSetupContinuesElsewhere,
    bool Function()? isWaitCancelled,
  }) async =>
      throw OtzariaInstallNotDetected('not detected');
}
