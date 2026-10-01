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

OtzariaRelease _release({int? size, String tag = _tag}) => OtzariaRelease(
      tagName: tag,
      name: 'Otzaria $tag',
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

    // build חדש באותו מספר גרסה — הקודם יורד מהכונן במלואו, כולל חבילת
    // ה-FULL שלצדו. שתי גרסאות של אותו `0.9.96` הן ~2GB כפול על כונן נייד.
    test('build ותיק של אותה גרסה נמחק כולו', () async {
      final oldDir = Directory(p.join(cacheDir, '0.9.96+736'));
      await oldDir.create(recursive: true);
      File(p.join(oldDir.path, 'otzaria-0.9.96-windows.exe'))
          .writeAsStringSync('x');
      File(p.join(oldDir.path, 'otzaria-0.9.96-windows-full.exe'))
          .writeAsStringSync('x');
      await Directory(p.join(cacheDir, '0.9.96+741')).create(recursive: true);

      final installer = installerWith(mustNotBeUsed());
      addTearDown(installer.dispose);

      await installer.pruneCacheExcept(keepTagNames: {'0.9.96+741'});

      expect(oldDir.existsSync(), isFalse);
      expect(Directory(p.join(cacheDir, '0.9.96+741')).existsSync(), isTrue);
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

    // ב-`otzaria.iss` יש רשומת `[Run]` שרצה **רק** בהתקנה שקטה, ובלי הדגל
    // אוצריא נפתחה מיד וחסמה את עדכון המסד שרץ אחריה.
    test('אוצריא אינה נפתחת בסוף התקנה שקטה', () {
      expect(args, contains('/NOLAUNCH=1'));
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

    // 1 = `InitializeSetup` החזיר False, ובמתקין של אוצריא זה בדיוק מה
    // שקורה אחרי שהוא שיגר את עצמו מחדש (מורם ב-UAC, או שקט בשדרוג).
    // ההתקנה ממשיכה בתהליך השני — לא כשל.
    test('1 = המתקין שיגר את עצמו מחדש, לא כשל', () {
      expect(
        OtzariaInstaller.wizardOutcomeFor(1),
        OtzariaWizardOutcome.relaunched,
      );
    });

    test('כל קוד אחר = כשל', () {
      for (final code in [3, 4, 6, 7, 8]) {
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

    // מאתר במצב ווינדוס במפורש: זה מסלול ווינדוס, ובלי ההזרקה המאתר גזר את
    // הפלטפורמה מהמכונה שמריצה את הבדיקות וחיפש חבילת `.app` במקום `.exe`.
    setUp(() => installer = OtzariaInstaller(
          cacheDir: cacheDir,
          appLocator: const OtzariaAppLocator(
            platform: OtzariaTargetPlatform.windows,
          ),
        ));

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

    // הבאג מ-issue #26: המתקין שיגר את עצמו מחדש מורם (התקנה ישנה בנתיב
    // שדורש מנהל), התהליך שהרצנו יצא בקוד 1, וההתקנה בתהליך השני הצליחה —
    // אבל הלאנצ'ר הכריז "התקנת אוצריא נכשלה".
    test('קוד יציאה 1 — הודעה שהאשף פתוח, לא כשל', () async {
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);

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

    test('קוד יציאה 1 וההתקנה כבר נמצאה — הצלחה', () async {
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);
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

      expect(state.launchPath, detected.launchPath);
      expect(state.installedTagName, _tag);
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

  // Issue #26 on an update: the installer relaunched itself (exit 1) and the
  // old exe still in installDir must not count as the finished update.
  group('OtzariaInstaller.installWithWizard - relaunched update', () {
    late OtzariaInstaller installer;
    late String installDir;
    late String exe;

    setUp(() async {
      installer = OtzariaInstaller(
        cacheDir: cacheDir,
        appLocator: const OtzariaAppLocator(
          platform: OtzariaTargetPlatform.windows,
        ),
        versionReader: const _FileContentVersionReader(),
      );
      installDir = p.join(tempDir.path, 'existing install');
      exe = p.join(installDir, 'otzaria.exe');
      await Directory(installDir).create(recursive: true);
    });

    test('old version still on disk - still open, not done', () async {
      await File(exe).writeAsString('0.9.90+90900');
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);

      await expectLater(
        installer.installWithWizard(
          release: _release(),
          installerPath: fakeInstaller,
          installDir: installDir,
          locateInstalled: () async => null,
          detectTimeout: Duration.zero,
        ),
        throwsA(isA<OtzariaWizardStillOpen>()),
      );
    });

    test('done only once the elevated child replaced the exe', () async {
      await File(exe).writeAsString('0.9.90+90900');
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);
      var replaced = false;
      Future<void>.delayed(const Duration(seconds: 3), () async {
        await File(exe).writeAsString('0.9.96+99600');
        replaced = true;
      });

      final state = await installer.installWithWizard(
        release: _release(),
        installerPath: fakeInstaller,
        installDir: installDir,
        locateInstalled: () async => null,
      );

      expect(replaced, isTrue);
      expect(state.launchPath, exe);
      expect(state.installedTagName, _tag);
    });

    test('destination changed in the wizard - the new install is found',
        () async {
      await File(exe).writeAsString('0.9.90+90900');
      final otherDir = p.join(tempDir.path, 'chosen elsewhere');
      final otherExe = p.join(otherDir, 'otzaria.exe');
      await Directory(otherDir).create(recursive: true);
      await File(otherExe).writeAsString('0.9.96+99600');
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);

      final state = await installer.installWithWizard(
        release: _release(),
        installerPath: fakeInstaller,
        installDir: installDir,
        locateInstalled: () async => OtzariaInstallState(
          installedTagName: _tag,
          installDir: otherDir,
          launchPath: otherExe,
        ),
        detectTimeout: Duration.zero,
      );

      expect(state.launchPath, otherExe);
    });

    test('detection returning the same old exe - still open', () async {
      await File(exe).writeAsString('0.9.90+90900');
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);

      await expectLater(
        installer.installWithWizard(
          release: _release(),
          installerPath: fakeInstaller,
          installDir: installDir,
          locateInstalled: () async => OtzariaInstallState(
            installedTagName: _tag,
            installDir: installDir,
            launchPath: exe,
          ),
          detectTimeout: Duration.zero,
        ),
        throwsA(isA<OtzariaWizardStillOpen>()),
      );
    });

    test('detection finding an even older install elsewhere - still open',
        () async {
      await File(exe).writeAsString('0.9.90+90900');
      final otherDir = p.join(tempDir.path, 'older install');
      final otherExe = p.join(otherDir, 'otzaria.exe');
      await Directory(otherDir).create(recursive: true);
      await File(otherExe).writeAsString('0.9.80+98000');
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);

      await expectLater(
        installer.installWithWizard(
          release: _release(),
          installerPath: fakeInstaller,
          installDir: installDir,
          locateInstalled: () async => OtzariaInstallState(
            installedTagName: _tag,
            installDir: otherDir,
            launchPath: otherExe,
          ),
          detectTimeout: Duration.zero,
        ),
        throwsA(isA<OtzariaWizardStillOpen>()),
      );
    });

    test('version unreadable while the exe is replaced - not done yet',
        () async {
      await File(exe).writeAsString('0.9.90+90900');
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);
      Future<void>.delayed(const Duration(milliseconds: 500), () async {
        await File(exe).writeAsString('?');
      });

      await expectLater(
        installer.installWithWizard(
          release: _release(),
          installerPath: fakeInstaller,
          installDir: installDir,
          locateInstalled: () async => null,
          detectTimeout: const Duration(seconds: 3),
        ),
        throwsA(isA<OtzariaWizardStillOpen>()),
      );
    });

    // Inno keeps the build's file timestamps, so a reinstall of the same
    // build leaves nothing to tell the new exe from the old one.
    test('reinstall of the installed version - success right away', () async {
      await File(exe).writeAsString('0.9.96+99600');
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);

      final state = await installer.installWithWizard(
        release: _release(),
        installerPath: fakeInstaller,
        installDir: installDir,
        locateInstalled: () async => null,
        detectTimeout: Duration.zero,
      );

      expect(state.launchPath, exe);
    });

    // Hotfix tags have a 4th part the exe never reports, so the exe looks
    // the same before and after; this must not end as "still open".
    test('hotfix tag 0.9.97.2 over exe 0.9.97 - success, not still open',
        () async {
      await File(exe).writeAsString('0.9.97+99702');
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);

      final state = await installer.installWithWizard(
        release: _release(tag: '0.9.97.2+800'),
        installerPath: fakeInstaller,
        installDir: installDir,
        locateInstalled: () async => null,
        detectTimeout: Duration.zero,
      );

      expect(state.launchPath, exe);
      expect(state.installedTagName, '0.9.97.2+800');
    });

    test('update 0.9.96 -> 0.9.97 is stale until the exe is replaced',
        () async {
      await File(exe).writeAsString('0.9.96+99600');
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);

      await expectLater(
        installer.installWithWizard(
          release: _release(tag: '0.9.97+740'),
          installerPath: fakeInstaller,
          installDir: installDir,
          locateInstalled: () async => null,
          detectTimeout: Duration.zero,
        ),
        throwsA(isA<OtzariaWizardStillOpen>()),
      );
    });
  });

  group('OtzariaInstaller.installFromFile (silent, Windows)', () {
    late OtzariaInstaller installer;

    setUp(() => installer = OtzariaInstaller(
          cacheDir: cacheDir,
          appLocator: const OtzariaAppLocator(
            platform: OtzariaTargetPlatform.windows,
          ),
        ));

    // Under /VERYSILENT the installer never relaunches itself, so exit 1 is a
    // real init failure (e.g. unsupported architecture).
    test('exit 1 is a failure, unlike the wizard path', () async {
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 1);

      await expectLater(
        installer.installFromFile(
          release: _release(),
          installerPath: fakeInstaller,
          installDir: null,
          locateInstalled: () async => throw StateError('must not be called'),
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            startsWith(AppL10n.strings.appDomain.installerExitCode(1, '')))),
      );
    });

    test('update, exit 0 - the exe in installDir counts as installed',
        () async {
      final fakeInstaller = await _writeExitScript(tempDir.path, exitCode: 0);
      final dir = p.join(tempDir.path, 'existing install');
      await Directory(dir).create(recursive: true);
      await File(p.join(dir, 'otzaria.exe')).writeAsString('exe');

      final state = await installer.installFromFile(
        release: _release(),
        installerPath: fakeInstaller,
        installDir: dir,
        appAppearTimeout: const Duration(seconds: 5),
      );

      expect(state.launchPath, p.join(dir, 'otzaria.exe'));
    });
  });
}

/// Reads the "version" from the fake exe's text content.
class _FileContentVersionReader implements InstalledVersionReader {
  const _FileContentVersionReader();

  @override
  String? readVersion(String launchPath) {
    final file = File(launchPath);
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    // '?' stands for an exe whose version resource cannot be read yet.
    return content == '?' ? null : content;
  }
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
