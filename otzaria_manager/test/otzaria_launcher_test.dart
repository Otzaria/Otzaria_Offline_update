import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('OtzariaLauncher', () {
    const launcher = OtzariaLauncher();
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-launcher-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('throws when the exe path does not exist', () {
      final missing = p.join(tempDir.path, 'otzaria.exe');

      expect(
        () => launcher.launch(missing),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message',
              AppL10n.strings.appDomain.launchFileMissing(missing)),
        ),
      );
    });

    test('throws when the .app bundle does not exist', () {
      expect(
        () => launcher.launch(p.join(tempDir.path, 'אוצריא.app')),
        throwsA(isA<StateError>()),
      );
    });

    // כל מסלול בודק את סוג הישות הנכון: bundle הוא תיקייה, exe הוא קובץ.
    test(
        'a file named .app is not a bundle, and a dir named .exe is not an exe',
        () async {
      await File(p.join(tempDir.path, 'אוצריא.app')).writeAsString('x');
      await Directory(p.join(tempDir.path, 'otzaria.exe')).create();

      await expectLater(
        launcher.launch(p.join(tempDir.path, 'אוצריא.app')),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        launcher.launch(p.join(tempDir.path, 'otzaria.exe')),
        throwsA(isA<StateError>()),
      );
    });

    // המסלול הלא-mac: התהליך מופעל מנותק, ולכן ההפעלה חוזרת מיד ולא
    // ממתינה לסיומו. ה"אוצריא" כאן הוא ה-dart שרץ ממילא — מדפיס עזרה ויוצא.
    test('starts a real executable detached and returns immediately', () async {
      await expectLater(
        launcher.launch(Platform.resolvedExecutable),
        completes,
      );
    });

    test(
      'finds an existing .app bundle (a directory) and hands it to open',
      () async {
        // הרגרסיה שהבדיקה הזאת שומרת עליה: חבילת .app היא **תיקייה**, ולכן
        // בדיקת File.exists עליה מחזירה false תמיד — והלאנצ'ר היה מדווח
        // "קובץ ההפעלה לא נמצא" על התקנה תקינה לגמרי.
        //
        // ה-bundle כאן ריק ולכן `open` נכשל, וזה בדיוק מה שמאשר שעברנו את
        // בדיקת הקיום והגענו להפעלה עצמה — בלי להריץ באמת אפליקציה.
        final fakeBundle = Directory(p.join(tempDir.path, 'אוצריא.app'));
        await fakeBundle.create(recursive: true);

        await expectLater(
          launcher.launch(fakeBundle.path),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('open'),
            ),
          ),
        );
      },
      // `open` הוא כלי של macOS; בפלטפורמה אחרת אין לו מקבילה.
      testOn: 'mac-os',
    );
  });
}
