import 'dart:io';

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
      expect(
        () => launcher.launch(p.join(tempDir.path, 'otzaria.exe')),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when the .app bundle does not exist', () {
      expect(
        () => launcher.launch(p.join(tempDir.path, 'אוצריא.app')),
        throwsA(isA<StateError>()),
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
