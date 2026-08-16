import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

class _FakeRunner {
  final calls = <({String executable, List<String> arguments})>[];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    calls.add((executable: executable, arguments: arguments));
    return ProcessResult(1, 0, '', '');
  }
}

void main() {
  late String root;
  late _FakeRunner runner;
  late CustomAppsManager manager;

  setUp(() {
    root = tempMirrorRoot();
    runner = _FakeRunner();
    manager = CustomAppsManager(
      resolveMirrorDir: () async => root,
      readVersion: (_) => '1.4.2',
      processRunner: runner.call,
      downloadsDir: p.join(root, 'Downloads'),
    );
  });

  test('אין תוכנות — רשימה ריקה, וזה המצב הרגיל', () async {
    expect(await manager.loadAll(), isEmpty);
  });

  group('המסע המלא', () {
    test('טופס ← קובץ התקנה ← התקנה', () async {
      // 1. התוכנה נרשמת מהטופס שבממשק — אין ייבוא של תיאור מקובץ
      await manager.add(
        descriptor(id: 'org.example.myapp', name: 'התוכנה שלי'),
      );

      // 2. במחשב שיש בו את הקובץ — מצרפים אותו
      final setup = writeFile(
          p.join(root, 'downloads', 'MyApp-Setup.exe'), 'MZ Inno Setup');
      final stored = await manager.attachInstaller(
        'org.example.myapp',
        sourcePath: setup,
        version: '1.4.2',
      );
      expect(stored.fileName, 'MyApp-Setup.exe');
      expect(stored.sizeBytes, 13);

      // הקובץ הועתק פנימה — מכאן הוא נוסע על הכונן
      expect(
        File(p.join(root, 'apps', 'org.example.myapp', 'MyApp-Setup.exe'))
            .existsSync(),
        isTrue,
      );

      // 3. במחשב המנותק — התקנה מהעותק המקומי, בלי רשת
      await manager.install('org.example.myapp');
      expect(runner.calls.single.arguments, contains('/VERYSILENT'));
    });
  });

  /// ההצהרה "הקובץ הוא התוכנה עצמה" היא הדבר היחיד על הקובץ שאי אפשר
  /// להריח מהבייטים, ולכן היא היחידה שנשמרת ברשומה.
  group('קובץ נייד — התוכנה עצמה', () {
    Future<void> register({String fileName = 'MyApp.exe'}) async {
      await manager.add(descriptor(id: 'portable', portableFile: true));
      await manager.attachInstaller(
        'portable',
        // תוכן עם סימן של Inno, כדי שההצהרה תוכיח שהיא גוברת על הריחרוח.
        sourcePath: writeFile(p.join(root, 'src', fileName), 'MZ Inno Setup'),
        version: '3.0',
      );
    }

    test('מועתק ליעד שנבחר במקום לרוץ כמתקין', () async {
      await register();
      final target = p.join(root, 'Tools');

      final outcome = await manager.install('portable', copyToDir: target);

      expect(runner.calls, isEmpty);
      expect(outcome.kind, CustomInstallerKind.portableFile);
      expect(File(p.join(target, 'MyApp.exe')).existsSync(), isTrue);
    });

    // מתקין רגיל מלמד דרך רג'יסטרי ההסרה; כאן אין רישום כזה — אבל אנחנו
    // עצמנו העתקנו את הקובץ, וזו עדות ישירה וחזקה יותר.
    test('שם קובץ ההרצה והמיקום נלמדים מההעתקה עצמה', () async {
      await register();
      final target = p.join(root, 'Tools');

      final outcome = await manager.install('portable', copyToDir: target);

      expect(outcome.learned?.exeName, 'MyApp.exe');
      final saved = (await manager.load('portable'))!.descriptor;
      expect(saved.detect.exeName, 'MyApp.exe');
      expect(saved.portableFile, isTrue);

      final state = await manager.detectInstalled(saved);
      expect(state!.installDir, target);
    });

    /// נתיב מוחלט ברשומה הוא בדיוק המחלה של `otzaria_install_state.json` —
    /// היא נוסעת על הכונן, והמיקום נכון למחשב אחד בלבד.
    test('התיקייה נרשמת ל-locations.json ולא לרשומה', () async {
      await register();
      await manager.install('portable', copyToDir: p.join(root, 'Tools'));

      final saved = (await manager.load('portable'))!.descriptor;
      expect(saved.installDir, isNull);
      expect(
        File(p.join(root, 'apps', 'portable', 'locations.json')).existsSync(),
        isTrue,
      );
    });

    // `launch` מריץ את מה שנרשם כאן — ארכיון או PDF היו הופכים את כפתור
    // ההפעלה לשגיאה.
    test('קובץ שאינו exe מועתק, אך אינו נרשם כקובץ הרצה', () async {
      await register(fileName: 'manual.pdf');

      final outcome =
          await manager.install('portable', copyToDir: p.join(root, 'Tools'));

      expect(File(p.join(root, 'Tools', 'manual.pdf')).existsSync(), isTrue);
      expect(outcome.learned, isNull);
      expect(
          (await manager.load('portable'))!.descriptor.detect.exeName, isNull);
    });
  });

  /// המסלול השלם של חלק "הלמידה": התקנה ← רישום הסרה חדש ← הרשומה מתעדכנת
  /// ← הזיהוי מוצא, והמיקום נרשם ל-`locations.json`.
  group('למידה אחרי התקנה', () {
    late String installedDir;

    /// מנהל עם שני התפרים של הלמידה. [freshEntry] הוא הרישום שיופיע אחרי
    /// ההתקנה, כמו שמתקין אמיתי היה כותב.
    CustomAppsManager managerLearning({
      required String displayName,
      String? exeName = 'myapp.exe',
      bool withInstallDir = true,
    }) {
      var installed = false;
      List<UninstallEntry> entries() => [
            const UninstallEntry(keyName: '{OLD}', displayName: 'Other 1.0'),
            if (installed)
              UninstallEntry(
                keyName: '{NEW}_is1',
                displayName: displayName,
                installDir: withInstallDir ? installedDir : null,
              ),
          ];

      return CustomAppsManager(
        resolveMirrorDir: () async => root,
        readVersion: (_) => '1.4.2',
        processRunner: (executable, arguments) async {
          installed = true;
          return ProcessResult(1, 0, '', '');
        },
        downloadsDir: p.join(root, 'Downloads'),
        lookupUninstallEntries: () async => entries(),
        // ⚠️ שני התפרים נחוצים יחד: הראשון **לומד** את התבנית, והשני הוא
        // מה שהופך אותה לזיהוי בפועל. עם אחד מהם בלבד הרשומה מתעדכנת אבל
        // ממשיכה לדווח "אינה מותקנת" — כמו הלאנצ'ר, ששניהם יושבים בו.
        lookupUninstallDirs: (pattern) => [
          for (final entry in entries())
            if (pattern.hasMatch(entry.displayName) && entry.installDir != null)
              entry.installDir!,
        ],
        lookupInstalledExe: (dir, _) async =>
            exeName == null ? null : p.join(dir, exeName),
      );
    }

    /// קובץ עם הסימן של Inno — סוג ההתקנה נקבע מהתוכן.
    String innoInstaller() {
      final path = p.join(root, 'dl', 'MyApp-Setup-1.4.2.exe');
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(
          [...'MZ'.codeUnits, ...List.filled(64, 0), ...'Inno Setup'.codeUnits],
        );
      return path;
    }

    setUp(() {
      installedDir = p.join(root, 'Program Files', 'MyApp');
      writeFile(p.join(installedDir, 'myapp.exe'));
    });

    Future<CustomInstallOutcome> installFresh(CustomAppsManager m) async {
      await m.add(descriptor(name: 'MyApp'));
      await m.attachInstaller('org.example.app',
          sourcePath: innoInstaller(), version: '1.4.2');
      return m.install('org.example.app');
    }

    test('שני השדות שהטופס לא יכול לשאול עליהם נלמדים לבד', () async {
      final m = managerLearning(displayName: 'MyApp 1.4.2');
      final outcome = await installFresh(m);

      expect(outcome.didLearn, isTrue);
      expect(outcome.learned!.exeName, 'myapp.exe');

      // ונשמרו לרשומה שעל הדיסק, לא רק הוחזרו.
      final saved = (await m.loadAll()).single.descriptor;
      expect(saved.detect.exeName, 'myapp.exe');
      expect(
        RegistryDisplayNamePattern.matches(
            saved.detect.registryDisplayName!, 'MyApp 2.0'),
        isTrue,
      );
    });

    // זו הבדיקה שסוגרת את המעגל: מכאן והלאה הכרטיס מפסיק לומר "לא ניתן לזהות".
    test('מיד אחרי הלמידה הזיהוי כבר מוצא את התוכנה', () async {
      final m = managerLearning(displayName: 'MyApp 1.4.2');
      await installFresh(m);

      final saved = (await m.loadAll()).single.descriptor;
      final state = await m.detectInstalled(saved);
      expect(state, isNotNull);
      expect(state!.installDir, installedDir);
      expect(state.version, '1.4.2');
    });

    /// ⚠️ נתיב מוחלט **אינו** נכתב לרשומה: היא נוסעת על הכונן. מקומו
    /// ב-`locations.json` שהוא פר-מחשב — המחלה של `otzaria_install_state.json`.
    test('התיקייה נרשמת ל-locations.json ולא לרשומה', () async {
      final m = managerLearning(displayName: 'MyApp 1.4.2');
      await installFresh(m);

      final saved = (await m.loadAll()).single.descriptor;
      expect(saved.installDir, isNull);
      expect(saved.detect.dirs, isEmpty);

      final locations = File(
        p.join(root, 'apps', 'org.example.app', 'locations.json'),
      );
      expect(locations.existsSync(), isTrue);
      expect(locations.readAsStringSync(), contains('MyApp'));
    });

    test('ארכיון אינו מותקן לשום מקום, ולכן אין ממה ללמוד', () async {
      final m = managerLearning(displayName: 'MyApp 1.4.2');
      await m.add(descriptor(name: 'MyApp'));
      final zip = p.join(root, 'dl', 'portable.zip');
      File(zip)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([0x50, 0x4B, 0x03, 0x04, ...'x'.codeUnits]);
      await m.attachInstaller('org.example.app',
          sourcePath: zip, version: '1.0');

      final outcome = await m.install('org.example.app');
      expect(outcome.isArchive, isTrue);
      expect(outcome.didLearn, isFalse);
      expect((await m.loadAll()).single.descriptor.detect.isEmpty, isTrue);
    });

    test('לא נמצא קובץ הרצה — הרשומה נשמרת עם מה שכן נלמד', () async {
      final m = managerLearning(displayName: 'MyApp 1.4.2', exeName: null);
      final outcome = await installFresh(m);

      expect(outcome.learned!.exeName, isNull);
      expect(outcome.learned!.registryDisplayName, isNotNull);
    });

    /// ⚠️ הרגרסיה שבגללה תוכנה דיווחה "אינה מותקנת" מיד אחרי התקנה מוצלחת.
    /// הלמידה ידעה בדיוק לאן המתקין כתב, אבל זרקה את התיקייה והשאירה את
    /// הזיהוי לגזור אותה שוב מהרג'יסטרי — וכאן הגזירה אינה מחזירה כלום.
    test('התיקייה שהתגלתה שורדת גם כשהרג׳יסטרי לא יחזיר אותה שוב', () async {
      final m = CustomAppsManager(
        resolveMirrorDir: () async => root,
        readVersion: (_) => '1.4.2',
        processRunner: (_, __) async => ProcessResult(1, 0, '', ''),
        downloadsDir: p.join(root, 'Downloads'),
        lookupUninstallEntries: () async => [
          UninstallEntry(
            keyName: '{NEW}_is1',
            displayName: 'MyApp 1.4.2',
            installDir: installedDir,
          ),
        ],
        // הערוץ שהזיהוי נשען עליו שותק — בדיוק כמו רישום הסרה שה-
        // `InstallLocation` שלו ריק וה-`UninstallString` אינו נפתר לתיקייה.
        lookupUninstallDirs: (_) => const [],
        lookupInstalledExe: (dir, _) async => p.join(dir, 'myapp.exe'),
      );
      await installFresh(m);

      final saved = (await m.loadAll()).single.descriptor;
      final state = await m.detectInstalled(saved);
      expect(state, isNotNull);
      expect(state!.installDir, installedDir);
    });

    /// ⚠️ הלמידה סורקת דרך `OtzariaAppLocator` (עומק 3) והזיהוי סורק בעצמו.
    /// כששני העומקים אינם שווים, exe עמוק נלמד ואז אינו נמצא לעולם.
    test('exe שתי רמות מתחת לתיקיית ההתקנה — נלמד וגם נמצא', () async {
      final nested = p.join(installedDir, 'bin', 'win64');
      writeFile(p.join(nested, 'deep.exe'));

      final m = managerLearning(displayName: 'MyApp 1.4.2', exeName: null);
      await m.add(descriptor(name: 'MyApp'));
      await m.attachInstaller('org.example.app',
          sourcePath: innoInstaller(), version: '1.4.2');
      await m.install('org.example.app');

      final state = await m.detectInstalled(
        (await m.loadAll()).single.descriptor.copyWith(
              detect: const AppDetectRules(exeName: 'deep.exe'),
            ),
      );
      expect(state, isNotNull);
      expect(state!.installDir, nested);
    });
  });

  test('התקנה בלי קובץ שמור — הודעה שמסבירה מה חסר', () async {
    await manager.add(descriptor());

    await expectLater(
      manager.install('org.example.app'),
      throwsA(
        isA<AppDescriptorException>()
            .having((e) => e.message, 'message', contains('קובץ התקנה')),
      ),
    );
  });

  test('התקנה של תוכנה שאינה רשומה', () async {
    await expectLater(
      manager.install('אין-כזה'),
      throwsA(isA<AppDescriptorException>()),
    );
  });

  group('צירוף קובץ התקנה', () {
    setUp(() async => manager.add(descriptor()));

    test('קובץ חדש מחליף את הישן ואינו מצטבר על הכונן', () async {
      final first = writeFile(p.join(root, 'dl', 'App-1.0.exe'), 'aaa');
      await manager.attachInstaller('org.example.app',
          sourcePath: first, version: '1.0');

      final second = writeFile(p.join(root, 'dl', 'App-2.0.exe'), 'bbbbbb');
      await manager.attachInstaller('org.example.app',
          sourcePath: second, version: '2.0');

      final dir = Directory(p.join(root, 'apps', 'org.example.app'));
      final installers = dir
          .listSync()
          .map((e) => p.basename(e.path))
          .where((name) => name.endsWith('.exe'))
          .toList();

      expect(installers, ['App-2.0.exe']);
      expect(
          (await manager.load('org.example.app'))!.installer!.version, '2.0');
    });

    test('קובץ מקור חסר נדחה', () async {
      await expectLater(
        manager.attachInstaller('org.example.app',
            sourcePath: p.join(root, 'אין-כזה.exe'), version: '1'),
        throwsA(isA<AppDescriptorException>()),
      );
    });

    test('צירוף לתוכנה שאינה רשומה נדחה', () async {
      final setup = writeFile(p.join(root, 'dl', 'x.exe'));
      await expectLater(
        manager.attachInstaller('אין-כזה', sourcePath: setup, version: '1'),
        throwsA(isA<AppDescriptorException>()),
      );
    });
  });

  group('עריכה', () {
    test('שינוי פרטים נשמר, והקובץ שכבר על הכונן נשאר', () async {
      await manager.add(descriptor(id: 'org.example.app', name: 'השם הישן'));
      final setup = writeFile(p.join(root, 'dl', 'App-1.0.exe'), 'aaa');
      await manager.attachInstaller('org.example.app',
          sourcePath: setup, version: '1.0');

      await manager.update(
        descriptor(
          id: 'org.example.app',
          name: 'השם החדש',
          detect: const AppDetectRules(exeName: 'myapp.exe'),
        ),
      );

      final entry = (await manager.load('org.example.app'))!;
      expect(entry.descriptor.name, 'השם החדש');
      expect(entry.descriptor.detect.exeName, 'myapp.exe');
      expect(entry.installer!.version, '1.0');
    });

    test('עריכה של תוכנה שאינה רשומה נדחית ואינה יוצרת אותה', () async {
      await expectLater(
        manager.update(descriptor(id: 'אין-כזה')),
        throwsA(isA<AppDescriptorException>()),
      );
      expect(await manager.loadAll(), isEmpty);
    });
  });

  test('הסרה מוציאה מהרשימה', () async {
    await manager.add(descriptor());
    await manager.remove('org.example.app');
    expect(await manager.loadAll(), isEmpty);
  });

  test('זיהוי מה מותקן על המחשב הזה', () async {
    final dir = p.join(root, 'Installed');
    writeFile(p.join(dir, 'myapp.exe'));

    final state = await manager.detectInstalled(
      descriptor(detect: AppDetectRules(exeName: 'myapp.exe', dirs: [dir])),
    );

    expect(state!.version, '1.4.2');
  });
}
