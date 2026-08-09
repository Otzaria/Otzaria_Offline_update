import 'dart:convert';
import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// exe של מערכת עם version resource — התחליף ל-otzaria.exe אמיתי בבדיקות
/// הזיהוי האוטומטי (בלי version resource הזיהוי מחזיר null בכוונה).
const String _systemExe = r'C:\Windows\System32\notepad.exe';

const String _installerBytes = 'installer';

/// \u200EC:\אוצריא היא נתיב קשיח בקוד (התקנות ישנות של אוצריא). במכונה שיש בה
/// כזו, הזיהוי האוטומטי ימצא אותה — ולכן אי אפשר לצפות שם ל"לא זוהה כלום".
final bool _legacyInstallExists = Directory(r'C:\אוצריא').existsSync();

OtzariaRelease _release(String tag, {required bool isPrerelease}) =>
    OtzariaRelease(
      tagName: tag,
      name: 'Otzaria $tag',
      isPrerelease: isPrerelease,
      isDraft: false,
      publishedAt: DateTime.utc(2026, 1, 1),
      installerKind: OtzariaInstallerKind.windowsSetupExe,
      installerAssetName: 'otzaria-$tag-windows.exe',
      installerDownloadUrl: 'https://example.invalid/$tag',
      installerSizeBytes: _installerBytes.length,
    );

void main() {
  late Directory dataDir;

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('otzaria-manager-test-');
  });

  tearDown(() async {
    if (await dataDir.exists()) await dataDir.delete(recursive: true);
  });

  String mirrorDir() => p.join(dataDir.path, 'mirror', 'app');

  /// כותב מראה מוכנה בדיוק במבנה ש-`sync()` מייצר: מטא־דאטה בשורש
  /// וקובצי ההתקנה תחת `installers/<tag>/`.
  Future<void> writeMirror({
    OtzariaRelease? stable,
    OtzariaRelease? prerelease,
  }) async {
    Future<Map<String, dynamic>> entry(OtzariaRelease release) async {
      final dir = Directory(p.join(mirrorDir(), 'installers', release.tagName));
      await dir.create(recursive: true);
      await File(p.join(dir.path, release.installerAssetName))
          .writeAsString(_installerBytes);
      return release.toJson()
        ..['installerPath'] =
            'installers/${release.tagName}/${release.installerAssetName}';
    }

    final json = <String, dynamic>{
      'schemaVersion': 2,
      if (stable != null) 'stable': await entry(stable),
      if (prerelease != null) 'prerelease': await entry(prerelease),
    };
    await Directory(mirrorDir()).create(recursive: true);
    await File(p.join(mirrorDir(), 'latest-release.json'))
        .writeAsString(jsonEncode(json));
  }

  OtzariaManager managerFor({
    bool preferPrerelease = false,
    Map<String, String> environment = const {},
  }) {
    final manager = OtzariaManager(
      dataDir: dataDir.path,
      platform: OtzariaTargetPlatform.windows,
      environment: environment,
      preferPrerelease: preferPrerelease,
    );
    addTearDown(manager.close);
    return manager;
  }

  group('checkForUpdate — מהמראה בלבד', () {
    test('מראה ריקה: צריך להוריד, ואין קריסה ואין המתנה לרשת', () async {
      final check = await managerFor().checkForUpdate();

      expect(check.needsDownload, isTrue);
      expect(check.latestRelease, isNull);
      expect(check.updateAvailable, isFalse);
      expect(check.hasChannelChoice, isFalse);
      expect(check.selectedChannel, isNull);
      if (!_legacyInstallExists) expect(check.currentState, isNull);
    });

    test('מחזיר בדיוק את מה שיושב במראה', () async {
      await writeMirror(stable: _release('0.9.90', isPrerelease: false));

      final check = await managerFor().checkForUpdate();

      expect(check.needsDownload, isFalse);
      expect(check.latestRelease!.tagName, '0.9.90');
      expect(check.selectedChannel, OtzariaReleaseChannel.stable);
      expect(check.updateAvailable, isTrue); // אין עדיין התקנה מוכרת
    });

    // הלב של המצב האופליין: החלפת ערוץ בוחרת את קובץ ההתקנה השני שכבר
    // יושב על הכונן — בלי שום פנייה לרשת.
    test('preferPrerelease מחליף בין שתי הגרסאות שבמראה, בלי רשת', () async {
      await writeMirror(
        stable: _release('0.9.90', isPrerelease: false),
        prerelease: _release('0.9.97', isPrerelease: true),
      );
      final manager = managerFor();

      final onStable = await manager.checkForUpdate();
      manager.preferPrerelease = true;
      final onPrerelease = await manager.checkForUpdate();

      expect(onStable.hasChannelChoice, isTrue);
      expect(onStable.latestRelease!.tagName, '0.9.90');
      expect(onPrerelease.hasChannelChoice, isTrue);
      expect(onPrerelease.latestRelease!.tagName, '0.9.97');
      expect(onPrerelease.selectedChannel, OtzariaReleaseChannel.prerelease);
    });

    // כשאין release יציב כלל — ה-pre-release הוא הגרסה היחידה, והתווית
    // אומרת בדיוק את זה (לא נפילה שקטה).
    test('מראה עם pre-release בלבד מוצעת, ומתויגת כלא-יציבה', () async {
      await writeMirror(prerelease: _release('0.9.97', isPrerelease: true));

      final check = await managerFor().checkForUpdate();

      expect(check.hasChannelChoice, isFalse);
      expect(check.latestRelease!.tagName, '0.9.97');
      expect(check.selectedChannel, OtzariaReleaseChannel.prerelease);
    });

    test('מצב שמור מחובר לתוצאה, ותג זהה אינו עדכון', () async {
      await writeMirror(stable: _release('0.9.96+736', isPrerelease: false));
      final manager = managerFor();
      const detected = OtzariaInstallState(
        installedTagName: '0.9.96',
        installDir: r'C:\Otzaria',
        launchPath: r'C:\Otzaria\otzaria.exe',
      );

      await manager.adoptExistingInstall(detected);
      final check = await manager.checkForUpdate();

      expect(check.currentState, detected);
      // 0.9.96 מול 0.9.96+736 — הנרמול מונע את העדכון הפנטומי.
      expect(check.updateAvailable, isFalse);
    });
  });

  group('update / launch ללא מראה או ללא התקנה', () {
    test('update זורק את הודעת ה-l10n כשאין מה להתקין', () async {
      final manager = managerFor();
      final check = await manager.checkForUpdate();

      expect(
        () => manager.update(check),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message',
              AppL10n.strings.appDomain.mirrorEmptyRunDownload),
        ),
      );
    });

    test('launch זורק כשעדיין לא הותקן/אומץ כלום', () async {
      expect(
        managerFor().launch,
        throwsA(
          isA<StateError>().having((e) => e.message, 'message',
              AppL10n.strings.appDomain.notInstalledByThisLauncher),
        ),
      );
    });
  });

  group('detectExistingInstall', () {
    test('null בתיקייה שאינה קיימת ובתיקייה ריקה', () async {
      final manager = managerFor();

      expect(
        await manager.detectExistingInstall(
            customDir: p.join(dataDir.path, 'nope')),
        isNull,
      );
      expect(
        await manager.detectExistingInstall(customDir: dataDir.path),
        isNull,
      );
    });

    test(
      'exe בלי version resource אינו נחשב התקנה של אוצריא',
      () async {
        final dir = Directory(p.join(dataDir.path, 'fake'))
          ..createSync(recursive: true);
        File(p.join(dir.path, 'otzaria.exe')).writeAsStringSync('לא exe');

        expect(
          await managerFor().detectExistingInstall(customDir: dir.path),
          isNull,
        );
      },
      testOn: 'windows',
    );

    test(
      'קורא את הגרסה מתוך ההתקנה עצמה, ולא ממה שהלאנצ׳ר זוכר',
      () async {
        if (!File(_systemExe).existsSync()) {
          markTestSkipped('אין $_systemExe במכונה הזאת');
          return;
        }
        final dir = Directory(p.join(dataDir.path, 'real'))
          ..createSync(recursive: true);
        final exe = p.join(dir.path, 'otzaria.exe');
        await File(_systemExe).copy(exe);

        final detected =
            await managerFor().detectExistingInstall(customDir: dir.path);

        expect(detected, isNotNull);
        expect(detected!.installDir, dir.path);
        expect(detected.launchPath, exe);
        expect(detected.installedTagName, isNotEmpty);
      },
      testOn: 'windows',
    );
  });

  // סדר החיפוש מ-AGENTS.md §5: התיקייה המנוהלת קודם, ואחריה מיקומי
  // ברירת המחדל האמיתיים של ה-installer של אוצריא.
  group('זיהוי אוטומטי — סדר תיקיות ברירת המחדל בווינדוס', () {
    late String localAppData;
    late String programFiles;

    Future<void> installFakeOtzaria(String dir) async {
      await Directory(dir).create(recursive: true);
      await File(_systemExe).copy(p.join(dir, 'otzaria.exe'));
    }

    setUp(() async {
      localAppData = p.join(dataDir.path, 'env', 'LocalAppData');
      programFiles = p.join(dataDir.path, 'env', 'ProgramFiles');
    });

    test(
      'התיקייה המנוהלת מנצחת, ואחריה LocalAppData, ProgramFiles\\Otzaria '
      'ו-ProgramFiles\\אוצריא',
      () async {
        if (!File(_systemExe).existsSync()) {
          markTestSkipped('אין $_systemExe במכונה הזאת');
          return;
        }

        // מסודר לפי העדיפות הצפויה; בכל סבב מוחקים את הזוכה הקודם ובודקים
        // מי תופס את מקומו.
        final byPriority = [
          p.join(dataDir.path, 'otzaria-app'),
          p.join(localAppData, 'Programs', 'Otzaria'),
          p.join(programFiles, 'Otzaria'),
          p.join(programFiles, 'אוצריא'),
        ];
        for (final dir in byPriority) {
          await installFakeOtzaria(dir);
        }

        final manager = managerFor(environment: {
          'LOCALAPPDATA': localAppData,
          'ProgramFiles': programFiles,
        });

        for (final expected in byPriority) {
          final check = await manager.checkForUpdate();
          expect(check.currentState, isNotNull, reason: expected);
          expect(check.currentState!.installDir, expected);
          await Directory(expected).delete(recursive: true);
        }

        // כלום לא נשאר — ואין מה לזהות. (\u200EC:\אוצריא ההיסטורית היא האחרונה
        // ברשימה; אי אפשר ליצור אותה בבדיקה, ולכן היא לא נבדקת כאן.)
        if (!_legacyInstallExists) {
          expect((await manager.checkForUpdate()).currentState, isNull);
        }
      },
      testOn: 'windows',
    );

    test(
      'משתני סביבה חסרים/ריקים אינם מייצרים נתיבים שבורים',
      () async {
        final manager = managerFor(
            environment: const {'LOCALAPPDATA': '', 'ProgramFiles': ''});

        await expectLater(manager.checkForUpdate(), completes);
      },
      testOn: 'windows',
    );
  });

  // הלנדמיין: אין נפילה חזרה ל-GitHub במסלול הבדיקה. אין דרך להזריק
  // ללקוח ה-HTTP של המנהל, ולכן נאכף גם על גוף המתודה עצמו.
  test('checkForUpdate קוראת רק מהמראה — בלי לקוח הרשת', () {
    final source =
        File(p.join('lib', 'src', 'otzaria_manager.dart')).readAsStringSync();
    final body = source.substring(
      source.indexOf('Future<OtzariaUpdateCheckResult> checkForUpdate()'),
      source.indexOf('Future<OtzariaInstallState> update('),
    );

    expect(body, contains('_mirror.load()'));
    expect(body, isNot(contains('_releaseClient')));
    expect(body, isNot(contains('fetchChannelReleases')));
  });
}
