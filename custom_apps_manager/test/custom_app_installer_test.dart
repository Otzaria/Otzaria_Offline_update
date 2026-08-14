import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// מריץ מדומה — הבדיקות אינן מריצות installer אמיתי על המחשב שמריץ אותן.
class _FakeRunner {
  final calls = <({String executable, List<String> arguments})>[];
  int exitCode = 0;

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    calls.add((executable: executable, arguments: arguments));
    return ProcessResult(1, exitCode, '', exitCode == 0 ? '' : 'boom');
  }
}

void main() {
  late String root;
  late String downloads;
  late _FakeRunner runner;
  late CustomAppInstaller installer;

  setUp(() {
    root = tempMirrorRoot();
    downloads = p.join(root, 'Downloads');
    runner = _FakeRunner();
    installer = CustomAppInstaller(
      processRunner: runner.call,
      downloadsDir: downloads,
    );
  });

  /// קובץ עם הסימן שמזהה framework מסוים — סוג ההתקנה נקבע מהתוכן, ולכן
  /// בדיקה עם קובץ ריק לא הייתה בודקת כלום.
  String writeBytes(String name, List<int> bytes) {
    final path = p.join(root, 'mirror', name);
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return path;
  }

  String innoSetup() => writeBytes(
        'setup.exe',
        [...'MZ'.codeUnits, ...List.filled(200, 0), ...'Inno Setup'.codeUnits],
      );

  String zipArchive([String name = 'portable.zip']) =>
      writeBytes(name, [0x50, 0x4B, 0x03, 0x04, ...'payload'.codeUnits]);

  group('סוג ההתקנה נקבע מהקובץ, לא מהרשומה', () {
    test('Inno מזוהה, ומורצות הדגלים השקטים שלו', () async {
      await installer.install(
        descriptor: descriptor(installDir: r'C:\Apps\X'),
        installerPath: innoSetup(),
      );

      expect(runner.calls.single.arguments, contains('/VERYSILENT'));
      expect(runner.calls.single.arguments.last, r'/DIR=C:\Apps\X');
    });

    test('NSIS מזוהה, ו-/D= נשאר אחרון', () async {
      final path = writeBytes(
        'setup.exe',
        [...'MZ'.codeUnits, ...List.filled(200, 0), ...'Nullsoft'.codeUnits],
      );

      await installer.install(
        descriptor: descriptor(installDir: r'C:\Apps\X'),
        installerPath: path,
      );

      expect(runner.calls.single.arguments.first, '/S');
      expect(runner.calls.single.arguments.last, r'/D=C:\Apps\X');
    });

    test('MSI מזוהה ומורץ דרך msiexec', () async {
      final path = writeBytes(
        'app.msi',
        [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0],
      );

      await installer.install(descriptor: descriptor(), installerPath: path);

      expect(runner.calls.single.executable, 'msiexec');
    });

    // הנפילה הזו אינה כישלון — היא הסיבה שאין בורר סוג בממשק.
    test('קובץ שלא זוהה — מורץ בלי דגלים, והמשתמש מסיים בעצמו', () async {
      final path = writeBytes('mystery.exe', List.filled(2048, 0x41));

      await installer.install(descriptor: descriptor(), installerPath: path);

      expect(runner.calls.single.executable, path);
      expect(runner.calls.single.arguments, isEmpty);
    });

    test('interactive מסומן כלא-שקט', () {
      expect(CustomInstallerKind.interactive.isSilent, isFalse);
      expect(CustomInstallerKind.innoSetup.isSilent, isTrue);
      expect(CustomInstallerKind.zipPortable.isSilent, isFalse);
    });
  });

  test('קובץ התקנה חסר — נופל לפני שמריצים כלום', () async {
    await expectLater(
      installer.install(
        descriptor: descriptor(),
        installerPath: p.join(root, 'אין-כזה.exe'),
      ),
      throwsA(isA<AppDescriptorException>()),
    );
    expect(runner.calls, isEmpty);
  });

  test('קוד יציאה שאינו אפס — ההודעה נושאת אותו ואת הפלט', () async {
    runner.exitCode = 1603;

    await expectLater(
      installer.install(descriptor: descriptor(), installerPath: innoSetup()),
      throwsA(
        isA<AppDescriptorException>().having(
          (e) => e.message,
          'message',
          allOf(contains('1603'), contains('boom')),
        ),
      ),
    );
  });

  group('ארכיון — יורד לתיקיית ההורדות ואינו "מותקן"', () {
    test('מועתק לתיקיית ההורדות, בלי להריץ תהליך', () async {
      final outcome = await installer.install(
        descriptor: descriptor(),
        installerPath: zipArchive(),
      );

      expect(runner.calls, isEmpty);
      expect(outcome.kind, CustomInstallerKind.zipPortable);
      expect(outcome.isArchive, isTrue);
      expect(outcome.archivePath, p.join(downloads, 'portable.zip'));
      expect(File(outcome.archivePath!).existsSync(), isTrue);
    });

    test('אינו דורש מיקום התקנה — אין ל-ZIP כזה', () async {
      expect(descriptor().installDir, isNull);
      await installer.install(
        descriptor: descriptor(),
        installerPath: zipArchive(),
      );
      expect(File(p.join(downloads, 'portable.zip')).existsSync(), isTrue);
    });

    test('תיקיית ההורדות נוצרת אם אינה קיימת', () async {
      expect(Directory(downloads).existsSync(), isFalse);
      await installer.install(
        descriptor: descriptor(),
        installerPath: zipArchive('a.zip'),
      );
      expect(Directory(downloads).existsSync(), isTrue);
    });

    // דריסה שקטה של קובץ בהורדות היא בדיוק מה שמשתמש לא מצפה לו.
    test('קובץ קיים אינו נדרס — נוצר שם פנוי', () async {
      writeFile(p.join(downloads, 'portable.zip'), 'הישן');

      final outcome = await installer.install(
        descriptor: descriptor(),
        installerPath: zipArchive(),
      );

      expect(p.basename(outcome.archivePath!), 'portable (2).zip');
      expect(
          File(p.join(downloads, 'portable.zip')).readAsStringSync(), 'הישן');
    });
  });

  test('בלי הזרקה, תיקיית ההורדות נגזרת מתיקיית הבית', () {
    final resolved =
        CustomAppInstaller(processRunner: runner.call).downloadsDir;
    expect(p.basename(resolved), 'Downloads');
  });
}
