import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _installerBytes = 'inno-setup-installer-bytes';
const String _tag = '0.9.96+736';
const String _assetName = 'otzaria-0.9.96-windows.exe';

OtzariaRelease _release({int? size}) => OtzariaRelease(
      tagName: _tag,
      name: 'Otzaria $_tag',
      isPrerelease: false,
      isDraft: false,
      publishedAt: null,
      installerKind: OtzariaInstallerKind.windowsSetupExe,
      installerAssetName: _assetName,
      installerDownloadUrl: 'https://example/$_assetName',
      installerSizeBytes: size ?? _installerBytes.length,
    );

void main() {
  late Directory tempDir;
  late String cacheDir;
  late int requests;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-installer-');
    cacheDir = p.join(tempDir.path, 'mirror', 'app', 'installers');
    requests = 0;
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  OtzariaInstaller installerWith(http.Client client) => OtzariaInstaller(
        cacheDir: cacheDir,
        httpClient: client,
        appLocator:
            const OtzariaAppLocator(platform: OtzariaTargetPlatform.windows),
      );

  http.Client mockDownload(String body, {int status = 200}) =>
      MockClient((_) async {
        requests++;
        return http.Response(body, status);
      });

  /// לקוח שכל פנייה אליו היא כישלון הבדיקה — כך "לא ניגשנו לרשת" נאכף.
  http.Client mustNotBeUsed() => MockClient((_) async {
        requests++;
        fail('לא הייתה אמורה להיות פנייה לרשת');
      });

  String cachedPath() => p.join(cacheDir, _tag, _assetName);

  group('OtzariaInstaller.ensureCached', () {
    test('מוריד לתת-תיקייה לפי תג, ומדווח התקדמות מול הגודל הצפוי', () async {
      final installer = installerWith(mockDownload(_installerBytes));
      addTearDown(installer.dispose);
      final progress = <(int, int)>[];

      final path = await installer.ensureCached(
        release: _release(),
        onDownloadProgress: (received, total) =>
            progress.add((received, total)),
      );

      expect(path, cachedPath());
      expect(File(path).readAsStringSync(), _installerBytes);
      expect(progress, isNotEmpty);
      expect(progress.last, (_installerBytes.length, _installerBytes.length));
      expect(requests, 1);
    });

    test('עותק תקין ב-cache נחשב hit — בלי רשת בכלל', () async {
      await Directory(p.join(cacheDir, _tag)).create(recursive: true);
      await File(cachedPath()).writeAsString(_installerBytes);
      final installer = installerWith(mustNotBeUsed());
      addTearDown(installer.dispose);

      expect(await installer.ensureCached(release: _release()), cachedPath());
      expect(requests, 0);
    });

    // הורדה שנקטעה משאירה קובץ בגודל שגוי — חייבים להוריד שוב.
    test('קובץ ב-cache בגודל שגוי מורד מחדש', () async {
      await Directory(p.join(cacheDir, _tag)).create(recursive: true);
      await File(cachedPath()).writeAsString('חצי');
      final installer = installerWith(mockDownload(_installerBytes));
      addTearDown(installer.dispose);

      await installer.ensureCached(release: _release());

      expect(requests, 1);
      expect(File(cachedPath()).readAsStringSync(), _installerBytes);
    });

    test('גודל שונה מהמוצהר — שגיאה, והקובץ החלקי נמחק', () async {
      final installer = installerWith(mockDownload('short'));
      addTearDown(installer.dispose);

      await expectLater(
        installer.ensureCached(release: _release(size: 999)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.appDomain.installerSizeMismatch(5, 999),
          ),
        ),
      );
      expect(File(cachedPath()).existsSync(), isFalse);
    });

    test('סטטוס HTTP לא תקין — שגיאת l10n ובלי קובץ שנשאר', () async {
      final installer = installerWith(mockDownload('', status: 404));
      addTearDown(installer.dispose);

      await expectLater(
        installer.ensureCached(release: _release()),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message',
              AppL10n.strings.appDomain.installerDownloadFailed(404)),
        ),
      );
      expect(File(cachedPath()).existsSync(), isFalse);
    });
  });

  group('OtzariaInstaller.pruneCacheExcept', () {
    test('משאיר רק את התגים המבוקשים', () async {
      for (final tag in ['0.9.90', '0.9.96+736', '0.9.97']) {
        await Directory(p.join(cacheDir, tag)).create(recursive: true);
      }
      final installer = installerWith(mustNotBeUsed());
      addTearDown(installer.dispose);

      // שני הערוצים נשמרים יחד — התקנה של אחד לא מוחקת את קובץ ההתקנה של
      // השני, אחרת החלפת ערוץ הייתה דורשת חזרה לרשת.
      await installer.pruneCacheExcept(keepTagNames: {'0.9.96+736', '0.9.97'});

      final remaining = Directory(cacheDir)
          .listSync()
          .map((e) => p.basename(e.path))
          .toList()
        ..sort();
      expect(remaining, ['0.9.96+736', '0.9.97']);
    });

    test('תיקיית cache שאינה קיימת אינה שגיאה', () async {
      final installer = installerWith(mustNotBeUsed());
      addTearDown(installer.dispose);

      await expectLater(
        installer.pruneCacheExcept(keepTagNames: const {}),
        completes,
      );
    });
  });

  // הלנדמיין מ-AGENTS.md: החתימה ה-ad-hoc של ה-.app שורדת רק חילוץ עם
  // `ditto`. אין דרך להריץ את המסלול הזה בווינדוס, ולכן נאכף על הקוד עצמו.
  group('מסלול macOS משתמש ב-ditto בלבד', () {
    final source =
        File(p.join('lib', 'src', 'services', 'otzaria_installer.dart'))
            .readAsStringSync();
    // ההערות בקובץ מזכירות את unzip דווקא כדי להסביר למה לא — לכן משווים
    // מול הקוד בלבד.
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    test('החילוץ וההעתקה קוראים ל-/usr/bin/ditto', () {
      expect(code, contains("Process.run('/usr/bin/ditto', ["));
      expect(code, contains("'-x',"));
      expect(code, contains("'-k',"));
    });

    test('אלה הכלים החיצוניים היחידים שהמסלול מריץ', () {
      final tools = RegExp(r"Process\.run\(\s*'([^']+)'")
          .allMatches(code)
          .map((m) => m.group(1)!)
          .toSet();

      expect(tools, {'/usr/bin/ditto', '/usr/bin/hdiutil', '/usr/bin/xattr'});
    });

    test('אין שימוש ב-unzip או ב-package:archive', () {
      expect(code, isNot(contains('unzip')));
      expect(code, isNot(contains('package:archive')));
    });
  });

  group('OtzariaInstaller.windowsSilentArgs', () {
    final args = OtzariaInstaller.windowsSilentArgs(
      installDir: r'C:\Otzaria',
      logPath: r'C:\Temp\otzaria-install.log',
    );

    test('התקנה שקטה, בלי תיבות הודעה ובלי הפעלה מחדש', () {
      expect(args,
          containsAll(['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']));
    });

    test('נתיב ההתקנה והלוג נמסרים כדגלים משורשרים', () {
      expect(args, contains(r'/DIR=C:\Otzaria'));
      expect(args, contains(r'/LOG=C:\Temp\otzaria-install.log'));
    });

    // המשימה מוגדרת `unchecked` ב-iss של אוצריא, ולכן בלי הדגל הזה התקנה
    // שקטה לא יוצרת קיצור-דרך בשולחן העבודה.
    test('משימת קיצור-הדרך בשולחן העבודה נדלקת במפורש', () {
      expect(args, contains('/MERGETASKS=desktopicon'));
    });
  });

  group('OtzariaInstaller.windowsSilentArgs — התקנה חדשה', () {
    // בלי `/DIR=` המתקין מתקין ל-DefaultDirName שלו. ניחוש משלנו התיישן
    // פעם, וזו בדיוק הסיבה שאין כאן דגל.
    test('התקנה חדשה (installDir=null) אינה מוסרת /DIR= בכלל', () {
      final args = OtzariaInstaller.windowsSilentArgs(
        installDir: null,
        logPath: r'C:\Temp\otzaria-install.log',
      );

      expect(args.where((a) => a.startsWith('/DIR=')), isEmpty);
      expect(args, contains('/VERYSILENT'));
      expect(args, contains('/MERGETASKS=desktopicon'));
    });

    test('עדכון של התקנה קיימת כן מוסר את התיקייה שלה', () {
      final args = OtzariaInstaller.windowsSilentArgs(
        installDir: r'D:\אוצריא',
        logPath: r'C:\Temp\otzaria-install.log',
      );

      expect(args, contains(r'/DIR=D:\אוצריא'));
    });
  });

  group('OtzariaInstaller.wizardOutcomeFor', () {
    test('0 = הסתיים', () {
      expect(
        OtzariaInstaller.wizardOutcomeFor(0),
        OtzariaWizardOutcome.finished,
      );
    });

    // 2 ו-5 הם הביטולים של Inno (לפני ההתקנה ובאמצעה), ו-1223 הוא סירוב
    // ל-UAC. שלושתם בחירה של המשתמש ולא תקלה.
    test('2, 5 ו-1223 = ביטול של המשתמש', () {
      for (final code in [2, 5, 1223]) {
        expect(
          OtzariaInstaller.wizardOutcomeFor(code),
          OtzariaWizardOutcome.cancelled,
          reason: 'קוד $code',
        );
      }
    });

    test('כל קוד אחר = כשל', () {
      for (final code in [1, 3, 4, 6, 7, 8]) {
        expect(
          OtzariaInstaller.wizardOutcomeFor(code),
          OtzariaWizardOutcome.failed,
          reason: 'קוד $code',
        );
      }
    });
  });

  group('OtzariaInstaller.installWithWizard', () {
    late OtzariaInstaller installer;

    setUp(() => installer = OtzariaInstaller(cacheDir: cacheDir));

    // המתקין שמורץ כאן הוא סקריפט אמיתי שיוצא בקוד 0 בלי לעשות כלום —
    // כלומר "האשף נסגר וההתקנה לא נמצאה", המצב של משתמש שעוד באמצע.
    test('אשף שהסתיים בלי שההתקנה נמצאה — OtzariaWizardStillOpen', () async {
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 0);

      await expectLater(
        installer.installWithWizard(
          release: _release(),
          installerPath: fakeInstaller,
          locateInstalled: () async => null,
          detectTimeout: Duration.zero,
        ),
        throwsA(isA<OtzariaWizardStillOpen>()),
      );
    });

    test('אשף שהמשתמש ביטל — OtzariaInstallCancelled, לא שגיאה', () async {
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 2);

      await expectLater(
        installer.installWithWizard(
          release: _release(),
          installerPath: fakeInstaller,
          locateInstalled: () async => throw StateError('לא אמור להיקרא'),
        ),
        throwsA(isA<OtzariaInstallCancelled>()),
      );
    });

    test('אשף שהסתיים וההתקנה זוהתה — המצב שמוחזר הוא של הזיהוי', () async {
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 0);
      final detected = OtzariaInstallState(
        installedTagName: '0.9.0',
        installDir: r'C:\אוצריא',
        launchPath: r'C:\אוצריא\otzaria.exe',
      );

      final state = await installer.installWithWizard(
        release: _release(),
        installerPath: fakeInstaller,
        locateInstalled: () async => detected,
      );

      expect(state.installDir, detected.installDir);
      expect(state.launchPath, detected.launchPath);
      // התג של ה-release, לא הגרסה שנקראה מה-exe — כמו במסלול השקט.
      expect(state.installedTagName, _tag);
    });

    // "להתקין בדיוק לאותו מקום": התיקייה שנמסרה קודמת לזיהוי הכללי, שיכול
    // להחזיר התקנה אחרת שנשארה במחשב.
    test('התיקייה שנמסרה מנצחת את הזיהוי הכללי', () async {
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 0);
      final existingDir = p.join(tempDir.path, 'התקנה קיימת');
      final existingExe = p.join(existingDir, 'otzaria.exe');
      await Directory(existingDir).create(recursive: true);
      await File(existingExe).writeAsString('exe');

      final state = await installer.installWithWizard(
        release: _release(),
        installerPath: fakeInstaller,
        installDir: existingDir,
        locateInstalled: () async => OtzariaInstallState(
          installedTagName: '0.1.0',
          installDir: r'C:\מקום אחר',
          launchPath: r'C:\מקום אחר\otzaria.exe',
        ),
      );

      expect(state.installDir, existingDir);
      expect(state.launchPath, existingExe);
    });

    test('תיקייה שנמסרה וריקה — נופלים לזיהוי (המשתמש שינה יעד באשף)',
        () async {
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 0);
      final chosenElsewhere = OtzariaInstallState(
        installedTagName: '0.1.0',
        installDir: r'D:\אוצריא',
        launchPath: r'D:\אוצריא\otzaria.exe',
      );

      final state = await installer.installWithWizard(
        release: _release(),
        installerPath: fakeInstaller,
        installDir: p.join(tempDir.path, 'תיקייה שאינה קיימת'),
        locateInstalled: () async => chosenElsewhere,
      );

      expect(state.installDir, chosenElsewhere.installDir);
    });
  });
}

/// כותב "מתקין" מדומה שכל תפקידו לצאת בקוד נתון. `.bat` בווינדוס ו-`sh`
/// בשאר — הבדיקה מריצה תהליך אמיתי, כי זה מה שמסלול האשף עושה.
Future<String> _writeExitScript(String dir, {required int exitCode}) async {
  if (Platform.isWindows) {
    final path = p.join(dir, 'fake-setup.bat');
    await File(path).writeAsString('@echo off\r\nexit /b $exitCode\r\n');
    return path;
  }
  final path = p.join(dir, 'fake-setup.sh');
  await File(path).writeAsString('#!/bin/sh\nexit $exitCode\n');
  await Process.run('chmod', ['+x', path]);
  return path;
}
