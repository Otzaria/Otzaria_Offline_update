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

  /// [runningOtzariaPath] מדמה "אוצריא רצה כרגע מהנתיב הזה". ברירת המחדל
  /// null היא גם מה שמנטרל את הזיהוי האמיתי לפי תהליך — אחרת הבדיקות היו
  /// תלויות בשאלה אם אוצריא פתוחה במכונת המפתח.
  OtzariaManager managerFor({
    bool preferPrerelease = false,
    Map<String, String> environment = const {},
    String? runningOtzariaPath,
    List<String> registeredInstallDirs = const [],
    OtzariaTargetPlatform platform = OtzariaTargetPlatform.windows,
  }) {
    final manager = OtzariaManager(
      dataDir: dataDir.path,
      platform: platform,
      environment: environment,
      runningLocator: _FakeRunningLocator(runningOtzariaPath),
      installRegistry: _FakeInstallRegistry(registeredInstallDirs),
      preferPrerelease: preferPrerelease,
    );
    addTearDown(manager.dispose);
    return manager;
  }

  // הלאנצ'ר רץ מכונן נייד, ולכן `dataDir` יושבת על הכונן. התקנה לשם
  // פירושה שכל אוצריא נוסעת עם הכונן ונעלמת מהמחשב ברגע שהוא נשלף.
  group('לאן מתקינים כשאין עדיין התקנה', () {
    test('ווינדוס: ברירת המחדל של המתקין עצמו, לא תיקיית הלאנצ׳ר', () async {
      final localAppData = p.join(dataDir.path, 'env', 'LocalAppData');

      final target = await managerFor(
        environment: {'LOCALAPPDATA': localAppData},
      ).resolveDefaultInstallDir();

      expect(target, p.join(localAppData, 'Programs', 'Otzaria'));
    });

    test('ווינדוס: בלי LOCALAPPDATA נופלים ל-ProgramFiles, לא לכונן', () async {
      final programFiles = p.join(dataDir.path, 'env', 'ProgramFiles');

      final target = await managerFor(
        environment: {'ProgramFiles': programFiles},
      ).resolveDefaultInstallDir();

      expect(target, p.join(programFiles, 'Otzaria'));
    });

    test('macOS: תיקיית האפליקציות — הראשית או זו של המשתמש', () async {
      final home = p.join(dataDir.path, 'home');

      final target = await managerFor(
        platform: OtzariaTargetPlatform.macos,
        environment: {'HOME': home},
      ).resolveDefaultInstallDir();

      // איזו מהשתיים תלוי בהרשאות המכונה שמריצה את הבדיקה; שתיהן תקינות.
      expect(target, anyOf('/Applications', p.join(home, 'Applications')));
    });

    // הבדיקה שהבאג עצמו נכשל בה: היעד לעולם אינו בתוך תיקיית הנתונים של
    // הלאנצ'ר, בשום פלטפורמה ובשום מצב סביבה.
    test('בשום מקרה לא בתוך תיקיית הנתונים של הלאנצ׳ר', () async {
      for (final platform in OtzariaTargetPlatform.values) {
        for (final environment in [
          const <String, String>{},
          {'LOCALAPPDATA': p.join(dataDir.path, 'l')},
          {'ProgramFiles': p.join(dataDir.path, 'pf')},
          {'HOME': p.join(dataDir.path, 'h')},
        ]) {
          final target = await managerFor(
            platform: platform,
            environment: environment,
          ).resolveDefaultInstallDir();

          expect(
            p.equals(target, p.join(dataDir.path, 'otzaria-app')),
            isFalse,
            reason: '$platform / $environment → $target',
          );
        }
      }
    });
  });

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
      // ההתקנה חייבת להיות קיימת בפועל, אחרת ה-state נפסל באימות.
      final dir = Directory(p.join(dataDir.path, 'Otzaria'))
        ..createSync(recursive: true);
      final exe = p.join(dir.path, 'otzaria.exe');
      File(exe).writeAsStringSync('exe מדומה');
      final detected = OtzariaInstallState(
        installedTagName: '0.9.96',
        installDir: dir.path,
        launchPath: exe,
      );

      await manager.adoptExistingInstall(detected);
      final check = await manager.checkForUpdate();

      expect(check.currentState, detected);
      // 0.9.96 מול 0.9.96+736 — הנרמול מונע את העדכון הפנטומי.
      expect(check.updateAvailable, isFalse);
    });
  });

  // הבאג מ-issue #19: קובץ ה-state יושב ב-OtzariaData שעל הכונן הנייד, ולכן
  // "מותקנת גרסה X" שנרשם במחשב אחד הגיע גם למחשבים שאין בהם אוצריא כלל —
  // והלאנצ'ר הכריז שם "אוצריא מעודכנת" וסירב להתקין.
  group('אימות ה-state השמור מול הדיסק של המחשב הזה', () {
    /// כותב state ידנית, בדיוק כמו קובץ שנסע על הכונן ממחשב אחר.
    Future<void> writeState(OtzariaInstallState state) async {
      await File(p.join(dataDir.path, 'otzaria_install_state.json'))
          .writeAsString(jsonEncode(state.toJson()));
    }

    test('state שנתיב ההתקנה שלו אינו קיים כאן נפסל, וההתקנה מוצעת', () async {
      if (_legacyInstallExists) return; // C:\אוצריא = כן תימצא התקנה אחרת
      await writeMirror(stable: _release('0.9.96', isPrerelease: false));
      await writeState(OtzariaInstallState(
        installedTagName: '0.9.96',
        installDir: p.join(dataDir.path, 'מחשב אחר'),
        launchPath: p.join(dataDir.path, 'מחשב אחר', 'otzaria.exe'),
      ));

      final check = await managerFor().checkForUpdate();

      expect(check.currentState, isNull);
      expect(check.updateAvailable, isTrue);
    });

    test('הפעלה מסרבת ל-state שההתקנה שלו אינה במחשב הזה', () async {
      if (_legacyInstallExists) return;
      await writeState(OtzariaInstallState(
        installedTagName: '0.9.96',
        installDir: p.join(dataDir.path, 'מחשב אחר'),
        launchPath: p.join(dataDir.path, 'מחשב אחר', 'otzaria.exe'),
      ));

      expect(
        managerFor().launch,
        throwsA(
          isA<StateError>().having((e) => e.message, 'message',
              AppL10n.strings.appDomain.noOtzariaInstallFound),
        ),
      );
    });

    test('state תקף נשמר — אין פסילה גורפת', () async {
      final dir = Directory(p.join(dataDir.path, 'קיימת'))
        ..createSync(recursive: true);
      final exe = p.join(dir.path, 'otzaria.exe');
      File(exe).writeAsStringSync('exe מדומה');
      await writeState(OtzariaInstallState(
        installedTagName: '0.9.90',
        installDir: dir.path,
        launchPath: exe,
      ));

      final check = await managerFor().checkForUpdate();

      expect(check.currentState!.launchPath, exe);
      // אין version resource בקובץ הזה, ולכן התג השמור נשאר על מקומו.
      expect(check.currentState!.installedTagName, '0.9.90');
    });

    // ההתקנה קיימת, אבל הגרסה על הדיסק אינה מה שאנחנו "זוכרים" — למשל
    // משתמש שעדכן את אוצריא במתקין שלה עצמה.
    test(
      'גרסה שהתחלפה על הדיסק גוברת על התג השמור, ונכתבת בחזרה',
      () async {
        if (!File(_systemExe).existsSync()) {
          markTestSkipped('אין $_systemExe במכונה הזאת');
          return;
        }
        final dir = Directory(p.join(dataDir.path, 'עודכנה מבחוץ'))
          ..createSync(recursive: true);
        final exe = p.join(dir.path, 'otzaria.exe');
        await File(_systemExe).copy(exe);
        await writeState(OtzariaInstallState(
          installedTagName: '0.0.1',
          installDir: dir.path,
          launchPath: exe,
        ));

        final check = await managerFor().checkForUpdate();
        final onDisk = check.currentState!.installedTagName;
        expect(onDisk, isNot('0.0.1'));

        // הבדיקה הבאה כבר קוראת את התג המעודכן מהקובץ.
        final stateFile =
            File(p.join(dataDir.path, 'otzaria_install_state.json'));
        expect(stateFile.readAsStringSync(), contains(onDisk));
      },
      testOn: 'windows',
    );
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

    test('launch זורק כשלא נמצאה שום התקנה', () async {
      if (_legacyInstallExists) return; // C:\אוצריא במכונה = כן תימצא התקנה
      expect(
        managerFor().launch,
        throwsA(
          isA<StateError>().having((e) => e.message, 'message',
              AppL10n.strings.appDomain.noOtzariaInstallFound),
        ),
      );
    });

    // הבאג: הזיהוי לפי הרג'יסטרי אינו נשמר ב-state (בכוונה), ולכן launch
    // שקרא מה-state בלבד סירב להפעיל התקנה שהוא עצמו הציג.
    test(
      'launch מפעיל התקנה שזוהתה ברג׳יסטרי, בלי שאומצה',
      () async {
        final dir = Directory(p.join(dataDir.path, 'registered'))
          ..createSync(recursive: true);
        final exe = p.join(dir.path, 'otzaria.exe');
        File(_systemExe).copySync(exe);
        final launcher = _RecordingLauncher();

        final manager = OtzariaManager(
          dataDir: dataDir.path,
          platform: OtzariaTargetPlatform.windows,
          environment: const {},
          runningLocator: _FakeRunningLocator(null),
          installRegistry: _FakeInstallRegistry([dir.path]),
          launcher: launcher,
        );
        addTearDown(manager.dispose);

        final check = await manager.checkForUpdate();
        await manager.launch();

        expect(check.currentState!.launchPath, exe);
        expect(launcher.launched, [exe]);
        // הפעלה רגילה אינה מוסרת קישור עומק.
        expect(launcher.uris, [null]);
      },
      testOn: 'windows',
    );

    // בקשת עדכון האינדקס נמסרת לאותו קובץ הרצה כארגומנט, ולא דרך מטפל
    // הפרוטוקול — כך היא עובדת גם בהתקנה ניידת, שאינה רושמת את הסכימה.
    test(
      'requestLibraryReindex מוסר את קישור העומק לקובץ ההרצה',
      () async {
        final dir = Directory(p.join(dataDir.path, 'reindex'))
          ..createSync(recursive: true);
        final exe = p.join(dir.path, 'otzaria.exe');
        File(_systemExe).copySync(exe);
        final launcher = _RecordingLauncher();

        final manager = OtzariaManager(
          dataDir: dataDir.path,
          platform: OtzariaTargetPlatform.windows,
          environment: const {},
          runningLocator: _FakeRunningLocator(null),
          installRegistry: _FakeInstallRegistry([dir.path]),
          launcher: launcher,
        );
        addTearDown(manager.dispose);

        await manager.checkForUpdate();
        await manager.requestLibraryReindex();

        expect(launcher.launched, [exe]);
        expect(launcher.uris, [OtzariaDeepLinks.libraryReindex]);
      },
      testOn: 'windows',
    );

    // בלי התקנה מזוהה אין למי למסור את הבקשה — אותה שגיאה כמו בהפעלה.
    test('requestLibraryReindex זורק כשלא זוהתה התקנה', () {
      expect(
        managerFor().requestLibraryReindex,
        throwsA(
          isA<StateError>().having((e) => e.message, 'message',
              AppL10n.strings.appDomain.noOtzariaInstallFound),
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

  // הזיהוי שמכסה את המשתמש שהתקין את אוצריא במקום שאינו ברשימה: כל עוד
  // היא פתוחה, נתיב התהליך שלה אומר בדיוק איפה היא.
  group('detectRunningInstall', () {
    test('null כשאוצריא אינה רצה', () async {
      expect(await managerFor().detectRunningInstall(), isNull);
    });

    test(
      'גוזר תיקיית התקנה מנתיב התהליך, וקורא ממנו גרסה',
      () async {
        if (!File(_systemExe).existsSync()) {
          markTestSkipped('אין $_systemExe במכונה הזאת');
          return;
        }
        final dir = Directory(p.join(dataDir.path, 'מיקום מוזר'))
          ..createSync(recursive: true);
        final exe = p.join(dir.path, 'otzaria.exe');
        await File(_systemExe).copy(exe);

        final detected =
            await managerFor(runningOtzariaPath: exe).detectRunningInstall();

        expect(detected, isNotNull);
        expect(detected!.installDir, dir.path);
        expect(detected.launchPath, exe);
        expect(detected.installedTagName, isNotEmpty);
      },
      testOn: 'windows',
    );

    test(
      'נתיב תהליך שאין ממנו גרסה אינו נחשב התקנה',
      () async {
        final exe = p.join(dataDir.path, 'otzaria.exe');
        File(exe).writeAsStringSync('לא exe');

        expect(
          await managerFor(runningOtzariaPath: exe).detectRunningInstall(),
          isNull,
        );
      },
      testOn: 'windows',
    );

    test(
      'התהליך הרץ קודם לתיקיות ברירת המחדל — גם כשיש התקנה מוכרת',
      () async {
        if (!File(_systemExe).existsSync()) {
          markTestSkipped('אין $_systemExe במכונה הזאת');
          return;
        }
        final managed = Directory(p.join(dataDir.path, 'otzaria-app'))
          ..createSync(recursive: true);
        await File(_systemExe).copy(p.join(managed.path, 'otzaria.exe'));

        final running = Directory(p.join(dataDir.path, 'D-Otzaria'))
          ..createSync(recursive: true);
        final runningExe = p.join(running.path, 'otzaria.exe');
        await File(_systemExe).copy(runningExe);

        final check =
            await managerFor(runningOtzariaPath: runningExe).checkForUpdate();

        expect(check.currentState!.launchPath, runningExe);
      },
      testOn: 'windows',
    );

    // הזיהוי חייב לשרוד את סגירת אוצריא — שזה בדיוק מה שמבקשים מהמשתמש
    // לעשות מיד אחרי שהוא רואה את ההודעה "אוצריא פתוחה".
    test(
      'מה שזוהה מהתהליך נשמר, ונשאר גם אחרי שאוצריא נסגרה',
      () async {
        if (!File(_systemExe).existsSync()) {
          markTestSkipped('אין $_systemExe במכונה הזאת');
          return;
        }
        final dir = Directory(p.join(dataDir.path, 'התקנה שלי'))
          ..createSync(recursive: true);
        final exe = p.join(dir.path, 'otzaria.exe');
        await File(_systemExe).copy(exe);

        await managerFor(runningOtzariaPath: exe).checkForUpdate();
        // מנהל חדש, ואוצריא כבר אינה רצה.
        final afterClose = await managerFor().checkForUpdate();

        expect(afterClose.currentState!.launchPath, exe);
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

    test(
      'תיקייה מהרג׳יסטרי מזוהה — גם כשאינה באף מיקום ברירת מחדל',
      () async {
        if (!File(_systemExe).existsSync()) {
          markTestSkipped('אין $_systemExe במכונה הזאת');
          return;
        }
        final registered = p.join(dataDir.path, 'תיקייה שלי', 'אוצריא');
        await installFakeOtzaria(registered);

        final check = await managerFor(registeredInstallDirs: [registered])
            .checkForUpdate();

        expect(check.currentState!.installDir, registered);
      },
      testOn: 'windows',
    );

    test(
      'הרג׳יסטרי קודם למיקומי ברירת המחדל, והתיקייה המנוהלת קודמת לשניהם',
      () async {
        if (!File(_systemExe).existsSync()) {
          markTestSkipped('אין $_systemExe במכונה הזאת');
          return;
        }
        final managed = p.join(dataDir.path, 'otzaria-app');
        final registered = p.join(dataDir.path, 'רשום-ברג׳יסטרי');
        final fromEnv = p.join(localAppData, 'Programs', 'Otzaria');
        for (final dir in [managed, registered, fromEnv]) {
          await installFakeOtzaria(dir);
        }

        final manager = managerFor(
          environment: {'LOCALAPPDATA': localAppData},
          registeredInstallDirs: [registered],
        );

        for (final expected in [managed, registered, fromEnv]) {
          final check = await manager.checkForUpdate();
          expect(check.currentState!.installDir, expected, reason: expected);
          await Directory(expected).delete(recursive: true);
        }
      },
      testOn: 'windows',
    );

    test(
      'כשההתקנה כבר ידועה אין סריקת רג׳יסטרי בכלל — היא עולה ~200ms',
      () async {
        if (!File(_systemExe).existsSync()) {
          markTestSkipped('אין $_systemExe במכונה הזאת');
          return;
        }
        final known = p.join(dataDir.path, 'ידועה');
        await installFakeOtzaria(known);
        final registry = _FakeInstallRegistry(const []);
        final manager = OtzariaManager(
          dataDir: dataDir.path,
          platform: OtzariaTargetPlatform.windows,
          environment: const {},
          runningLocator: _FakeRunningLocator(null),
          installRegistry: registry,
        );
        addTearDown(manager.dispose);

        final detected = await manager.detectExistingInstall(customDir: known);
        await manager.adoptExistingInstall(detected!);
        registry.calls = 0;

        await manager.checkForUpdate();

        expect(registry.calls, 0);
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

/// "אוצריא רצה מהנתיב הזה" קבוע — במקום לשאול את המערכת מה פתוח כרגע.
class _FakeRunningLocator extends RunningOtzariaLocator {
  const _FakeRunningLocator(this.launchPath);

  final String? launchPath;

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: launchPath != null, launchPath: launchPath);
}

/// קולט את נתיב ההפעלה (ואת קישור העומק, אם נמסר) במקום להריץ תהליך אמיתי.
class _RecordingLauncher extends OtzariaLauncher {
  final List<String> launched = [];
  final List<String?> uris = [];

  @override
  Future<void> launch(String launchPath, {String? withUri}) async {
    launched.add(launchPath);
    uris.add(withUri);
  }
}

/// מנטרל את הרג'יסטרי האמיתי: בלעדיו הבדיקות במכונת פיתוח עם אוצריא
/// מותקנת היו מזהות דווקא אותה.
class _FakeInstallRegistry extends WindowsInstallRegistry {
  _FakeInstallRegistry([this.dirs = const []]);

  final List<String> dirs;

  /// כמה פעמים נסרק הרג'יסטרי — הסריקה יקרה, ויש מסלול שאמור לדלג עליה.
  int calls = 0;

  @override
  List<String> installDirs() {
    calls++;
    return dirs;
  }
}
