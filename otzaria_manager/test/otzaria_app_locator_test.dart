import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// שני המסלולים (Windows/macOS) נבדקים כאן מאותה מכונה, דרך דריסת
/// `platform` — בדיוק הסיבה שהפרמטר הזה קיים.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('app-locator-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('OtzariaAppLocator (Windows)', () {
    const locator = OtzariaAppLocator(platform: OtzariaTargetPlatform.windows);

    test('returns null when directory does not exist', () async {
      expect(await locator.findIn(p.join(tempDir.path, 'missing')), isNull);
    });

    test('finds the app exe nested inside subfolders, ignoring uninstaller',
        () async {
      final appDir = Directory(p.join(tempDir.path, 'app'))
        ..createSync(recursive: true);
      File(p.join(appDir.path, 'otzaria.exe')).writeAsStringSync('fake');
      File(p.join(tempDir.path, 'unins000.exe')).writeAsStringSync('fake');

      final result = await locator.findIn(tempDir.path);

      expect(result, isNotNull);
      expect(p.basename(result!), 'otzaria.exe');
    });

    test('returns null when only an uninstaller exe exists', () async {
      File(p.join(tempDir.path, 'unins000.exe')).writeAsStringSync('fake');

      expect(await locator.findIn(tempDir.path), isNull);
    });

    test('prefers otzaria.exe over helper exes that precede it alphabetically',
        () async {
      // תיקיית ההתקנה האמיתית: crashpad_handler.exe נסרק ראשון, ויש לו
      // version resource משלו — כך שהזיהוי דיווח על גרסה שאינה של אוצריא.
      File(p.join(tempDir.path, 'crashpad_handler.exe'))
          .writeAsStringSync('fake');
      File(p.join(tempDir.path, 'otzaria.exe')).writeAsStringSync('fake');
      File(p.join(tempDir.path, 'unins000.exe')).writeAsStringSync('fake');

      final result = await locator.findIn(tempDir.path);

      expect(p.basename(result!), 'otzaria.exe');
    });

    test('helper exes alone are not an install', () async {
      File(p.join(tempDir.path, 'crashpad_handler.exe'))
          .writeAsStringSync('fake');

      expect(await locator.findIn(tempDir.path), isNull);
    });

    test('falls back to an unknown exe name, in case the app is renamed',
        () async {
      File(p.join(tempDir.path, 'crashpad_handler.exe'))
          .writeAsStringSync('fake');
      File(p.join(tempDir.path, 'sefaria.exe')).writeAsStringSync('fake');

      expect(p.basename((await locator.findIn(tempDir.path))!), 'sefaria.exe');
    });

    test('שם תואם מנצח מועמד גיבוי שנסרק לפניו', () async {
      // `fallback ??=` חייב להמשיך לסרוק. `aaa` קודם ל-`otzaria` בכל מיון.
      File(p.join(tempDir.path, 'aaa.exe')).writeAsStringSync('fake');
      File(p.join(tempDir.path, 'otzaria.exe')).writeAsStringSync('fake');

      expect(p.basename((await locator.findIn(tempDir.path))!), 'otzaria.exe');
    });

    test('הלאנצ׳ר עצמו אינו מזוהה כאוצריא — שמו מכיל "אוצריא"', () async {
      // התרחיש: המשתמש העתיק את תיקיית העדכונים אל תוך C:\אוצריא.
      File(p.join(tempDir.path, 'עדכוני אוצריא.exe')).writeAsStringSync('fake');
      final appFiles = Directory(p.join(tempDir.path, 'app-files'))
        ..createSync(recursive: true);
      File(p.join(appFiles.path, 'launcher_app.exe')).writeAsStringSync('fake');

      expect(await locator.findIn(tempDir.path), isNull);
    });

    test('אוצריא האמיתית מנצחת את ה-stub של הלאנצ׳ר באותה תיקייה', () async {
      File(p.join(tempDir.path, 'עדכוני אוצריא.exe')).writeAsStringSync('fake');
      File(p.join(tempDir.path, 'otzaria.exe')).writeAsStringSync('fake');

      expect(p.basename((await locator.findIn(tempDir.path))!), 'otzaria.exe');
    });

    test('מועמד הגיבוי הרדוד מנצח מקונן — ולא סדר הסריקה', () async {
      final nested = Directory(p.join(tempDir.path, 'aaa', 'bbb'))
        ..createSync(recursive: true);
      File(p.join(nested.path, 'deep.exe')).writeAsStringSync('fake');
      File(p.join(tempDir.path, 'zzz.exe')).writeAsStringSync('fake');

      expect(p.basename((await locator.findIn(tempDir.path))!), 'zzz.exe');
    });

    test('מעבר לעומק המרבי אין סריקה — ספריית ספרים אינה נסרקת לעומק',
        () async {
      final deep = Directory(p.join(tempDir.path, 'a', 'b', 'c', 'd'))
        ..createSync(recursive: true);
      File(p.join(deep.path, 'otzaria.exe')).writeAsStringSync('fake');

      expect(await locator.findIn(tempDir.path), isNull);
      expect(
        await locator.findIn(tempDir.path, windowsMaxDepth: 5),
        isNotNull,
      );
    });
  });

  group('OtzariaAppLocator (macOS)', () {
    const locator = OtzariaAppLocator(platform: OtzariaTargetPlatform.macos);

    test('finds the .app bundle in the install dir', () async {
      Directory(p.join(tempDir.path, 'אוצריא.app', 'Contents', 'MacOS'))
          .createSync(recursive: true);

      final result = await locator.findIn(tempDir.path);

      expect(result, p.join(tempDir.path, 'אוצריא.app'));
    });

    test('does not descend into a found bundle, so nested helper apps lose',
        () async {
      // מבנה אמיתי של אפליקציית Flutter: לפעמים יש .app פנימית בתוך
      // Contents/Frameworks. חייבים להחזיר את החבילה הראשית.
      Directory(p.join(
        tempDir.path,
        'אוצריא.app',
        'Contents',
        'Frameworks',
        'Helper.app',
      )).createSync(recursive: true);

      expect(await locator.findIn(tempDir.path),
          p.join(tempDir.path, 'אוצריא.app'));
    });

    test('ignores dot-dirs, so staging/backup leftovers are not an install',
        () async {
      // אלה בדיוק השמות שה-installer יוצר בתוך תיקיית ההתקנה בזמן עדכון.
      Directory(p.join(tempDir.path, '.otzaria-install-staging', 'אוצריא.app'))
          .createSync(recursive: true);
      Directory(p.join(tempDir.path, '.otzaria-previous', 'אוצריא.app'))
          .createSync(recursive: true);

      expect(await locator.findIn(tempDir.path), isNull);
    });

    test('ignores __MACOSX leftovers of a zip extraction', () async {
      Directory(p.join(tempDir.path, '__MACOSX', 'אוצריא.app'))
          .createSync(recursive: true);

      expect(await locator.findIn(tempDir.path), isNull);
    });

    test('accept filter skips foreign apps in a shared dir like /Applications',
        () async {
      // הסימולציה של /Applications: אפליקציה זרה נוצרת ראשונה, כך שסריקה
      // בלי סינון הייתה עלולה להחזיר אותה.
      Directory(p.join(tempDir.path, 'Safari.app')).createSync(recursive: true);
      Directory(p.join(tempDir.path, 'אוצריא.app')).createSync(recursive: true);

      final result = await locator.findIn(
        tempDir.path,
        accept: (path) => p.basename(path).contains('אוצריא'),
        macMaxDepth: 1,
      );

      expect(result, p.join(tempDir.path, 'אוצריא.app'));
    });

    test('macMaxDepth: 1 does not look inside subfolders', () async {
      Directory(p.join(tempDir.path, 'nested', 'אוצריא.app'))
          .createSync(recursive: true);

      expect(await locator.findIn(tempDir.path, macMaxDepth: 1), isNull);
      expect(
        await locator.findIn(tempDir.path),
        p.join(tempDir.path, 'nested', 'אוצריא.app'),
      );
    });
  });
}
