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
